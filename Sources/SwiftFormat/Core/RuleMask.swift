//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import SwiftSyntax

/// This class takes the raw source text and scans through it searching for comments that instruct
/// the formatter to change the status of rules. The comments may include no rule names to affect
/// all rules, a single rule name to affect that rule, or a comma delimited list of rule names to
/// affect a number of rules. Ignore is the only supported operation for the node- and file-level
/// directives; the `swift-format-disable`/`swift-format-enable` family additionally supports
/// blocks and line-scoped directives (see `DisableDirective`).
///
///   1. |  // swift-format-ignore
///   2. |  let a = 123
///   Ignores all rules for line 2.
///
///   1. |  // swift-format-ignore-file
///   2. |  let a = 123
///   3. | class Foo { }
///   Ignores all rules for an entire file (lines 2-3).
///
///   1. |  // swift-format-ignore: RuleName
///   2. |  let a = 123
///   Ignores `RuleName` for line 2.
///
///   1. |  // swift-format-ignore: RuleName, OtherRuleName
///   2. |  let a = 123
///   Ignores `RuleName` and `OtherRuleName` for line 2.
///
///   1. |  // swift-format-ignore-file: RuleName
///   2. |  let a = 123
///   3. | class Foo { }
///   Ignores `RuleName` for the entire file (lines 2-3).
///
///   1. |  // swift-format-ignore-file: RuleName, OtherRuleName
///   2. |  let a = 123
///   3. | class Foo { }
///   Ignores `RuleName` and `OtherRuleName` for the entire file (lines 2-3).
///
///   1. |  // swift-format-disable
///   2. |  let a = 123
///   3. |  // swift-format-enable
///   Disables all rules for the block spanning lines 2-2.
///
///   1. |  // swift-format-disable:next RuleName
///   2. |  let a = 123
///   Disables `RuleName` on line 2; `:this` and `:previous` scope to the directive's own line
///   and the line before it.
///
/// The rules themselves reference RuleMask to see if it is disabled for the line it is currently
/// examining.
@_spi(Testing)
public class RuleMask {
  /// Stores the source ranges in which all rules are ignored.
  private var allRulesIgnoredRanges: [SourceRange] = []

  /// Map of rule names to list ranges in the source where the rule is ignored.
  private var ruleMap: [String: [SourceRange]] = [:]

  /// Map of rule names to ranges where the rule was explicitly re-enabled inside an all-rules
  /// disable block with `swift-format-enable: RuleName`.
  private var reenabledRanges: [String: [SourceRange]] = [:]

  /// Used to compute line numbers of syntax nodes.
  private let sourceLocationConverter: SourceLocationConverter

  /// Creates a `RuleMask` that can specify whether a given rule's status is explicitly modified at
  /// a location obtained from the `SourceLocationConverter`.
  ///
  /// Ranges in the source where rules' statuses are modified are pre-computed during init so that
  /// lookups later don't require parsing the source.
  public init(syntaxNode: Syntax, sourceLocationConverter: SourceLocationConverter) {
    self.sourceLocationConverter = sourceLocationConverter
    computeIgnoredRanges(in: syntaxNode)
  }

  /// Computes the ranges in the given node where the status of rules are explicitly modified.
  private func computeIgnoredRanges(in node: Syntax) {
    let visitor = RuleStatusCollectionVisitor(sourceLocationConverter: sourceLocationConverter)
    visitor.walk(node)
    allRulesIgnoredRanges = visitor.allRulesIgnoredRanges
    ruleMap = visitor.ruleMap

    let sweeper = DisableDirectiveSweeper(sourceLocationConverter: sourceLocationConverter)
    sweeper.walk(node)
    applyDisableDirectiveEvents(sweeper.events, endOffset: node.totalLength.utf8Length)
  }

  /// Returns the `RuleState` for the given rule at the provided location.
  public func ruleState(_ rule: String, at location: SourceLocation) -> RuleState {
    // A rule re-enabled inside an all-rules block is governed by the named disables that
    // surround it, not by the block's remaining coverage of every other rule.
    if let reenabled = reenabledRanges[rule], reenabled.contains(where: { $0.contains(location) }) {
      if let ignoredRanges = ruleMap[rule], ignoredRanges.contains(where: { $0.contains(location) }) {
        return .disabled
      }
      return .default
    }
    if allRulesIgnoredRanges.contains(where: { $0.contains(location) }) {
      return .disabled
    }
    if let ignoredRanges = ruleMap[rule] {
      return ignoredRanges.contains { $0.contains(location) } ? .disabled : .default
    }
    return .default
  }

  /// Applies the disable/enable directive events found by the sweeper, in source order, to
  /// compute the ranges where rules are disabled.
  ///
  /// Blocks are line-granular: a block opened by `swift-format-disable` covers from the start of
  /// the directive's line, and one closed by `swift-format-enable` covers through the end of
  /// that directive's line. An unterminated block runs to the end of the file.
  private func applyDisableDirectiveEvents(_ events: [DisableDirectiveEvent], endOffset: Int) {
    func lineStart(_ line: Int) -> Int {
      sourceLocationConverter.position(ofLine: line, column: 1).utf8Offset
    }
    func lineEnd(_ line: Int) -> Int {
      max(lineStart(line + 1) - 1, lineStart(line))
    }
    func sourceRange(_ startOffset: Int, _ endOffset: Int) -> SourceRange {
      SourceRange(
        start: sourceLocationConverter.location(for: AbsolutePosition(utf8Offset: startOffset)),
        end: sourceLocationConverter.location(for: AbsolutePosition(utf8Offset: endOffset))
      )
    }

    /// The offset where the open all-rules block started, or nil when none is open.
    var allBlockStart: Int? = nil

    /// The offsets where named-rule blocks started, outside any all-rules block.
    var ruleBlockStarts: [String: Int] = [:]

    /// The offsets where rules were re-enabled inside the open all-rules block.
    var reenabledStarts: [String: Int] = [:]

    func closeRuleBlocks(at end: Int) {
      for (name, start) in ruleBlockStarts {
        ruleMap[name, default: []].append(sourceRange(start, max(end, start)))
      }
      ruleBlockStarts.removeAll()
    }
    func closeReenabled(at end: Int) {
      for (name, start) in reenabledStarts {
        reenabledRanges[name, default: []].append(sourceRange(start, max(end, start)))
      }
      reenabledStarts.removeAll()
    }

    for event in events.sorted(by: { $0.offset < $1.offset }) {
      let start = lineStart(event.line)
      let end = lineEnd(event.line)

      switch event.effect {
      case .disableAll:
        if allBlockStart == nil {
          // An all-rules block subsumes the open named blocks and re-enables.
          closeRuleBlocks(at: max(start - 1, 0))
          closeReenabled(at: max(start - 1, 0))
          allBlockStart = start
        }
      case .disableRules(let rules):
        if allBlockStart == nil {
          for rule in rules where ruleBlockStarts[rule] == nil {
            ruleBlockStarts[rule] = start
          }
        } else {
          // Re-disabling a rule inside the all-rules block cancels its re-enablement.
          for rule in rules {
            if let reenabledStart = reenabledStarts.removeValue(forKey: rule) {
              reenabledRanges[rule, default: []].append(
                sourceRange(reenabledStart, max(start - 1, reenabledStart))
              )
            }
          }
        }
      case .enableAll:
        if let blockStart = allBlockStart {
          allRulesIgnoredRanges.append(sourceRange(blockStart, end))
          allBlockStart = nil
        }
        closeRuleBlocks(at: end)
        closeReenabled(at: end)
      case .enableRules(let rules):
        if allBlockStart == nil {
          for rule in rules {
            if let blockStart = ruleBlockStarts.removeValue(forKey: rule) {
              ruleMap[rule, default: []].append(sourceRange(blockStart, end))
            }
          }
        } else {
          for rule in rules where reenabledStarts[rule] == nil {
            reenabledStarts[rule] = start
          }
        }
      case .lineScope(let scope, let rules):
        let targetLine: Int
        switch scope {
        case .next: targetLine = event.line + 1
        case .this: targetLine = event.line
        case .previous: targetLine = event.line - 1
        }
        guard targetLine >= 1 else { break }
        let scopeRange = sourceRange(lineStart(targetLine), lineEnd(targetLine))
        if rules.isEmpty {
          allRulesIgnoredRanges.append(scopeRange)
        } else {
          for rule in rules {
            ruleMap[rule, default: []].append(scopeRange)
          }
        }
      }
    }

    // An unterminated block runs to the end of the file.
    if let blockStart = allBlockStart {
      allRulesIgnoredRanges.append(sourceRange(blockStart, endOffset))
    }
    closeRuleBlocks(at: endOffset)
    closeReenabled(at: endOffset)
  }
}

extension SourceRange {
  /// Returns whether the range includes the given location.
  fileprivate func contains(_ location: SourceLocation) -> Bool {
    return start.offset <= location.offset && end.offset >= location.offset
  }
}

/// One `swift-format-disable`/`swift-format-enable` directive comment found in the source.
private struct DisableDirectiveEvent {
  /// What the directive instructs.
  let effect: DisableDirective.Effect

  /// The line the directive comment sits on.
  let line: Int

  /// The byte offset of the directive comment, which orders events in source order.
  let offset: Int
}

/// A syntax visitor that collects `swift-format-disable`/`swift-format-enable` directive events
/// with the line each comment sits on.
///
/// Directives are recognized wherever they are syntactically recognizable — the same set of
/// points the pretty printer's `DisableRegionCollector` uses, so the two never disagree: the
/// preceding trivia of statement-level items (`CodeBlockItem` and `MemberBlockItem` nodes,
/// including directives trailing code on the previous line), plus the leading trivia of the
/// closing brace of code and member blocks (so a block opened inside a declaration can be
/// closed on the line before `}`) and of the end-of-file token.
private final class DisableDirectiveSweeper: SyntaxVisitor {
  /// Computes source locations and ranges for syntax nodes in a source file.
  private let sourceLocationConverter: SourceLocationConverter

  /// The directive events found so far, in the order the walk encountered them; sort by offset
  /// before use, because trivia attached to enclosing structure (closing braces) is visited
  /// before the items that precede it in the source.
  var events: [DisableDirectiveEvent] = []

  init(sourceLocationConverter: SourceLocationConverter) {
    self.sourceLocationConverter = sourceLocationConverter
    super.init(viewMode: .sourceAccurate)
  }

  // MARK: - Syntax Visitation Methods

  override func visit(_ node: SourceFileSyntax) -> SyntaxVisitorContinueKind {
    collect(from: node.endOfFileToken.allPrecedingTrivia, of: node.endOfFileToken)
    return .visitChildren
  }

  override func visit(_ node: CodeBlockItemSyntax) -> SyntaxVisitorContinueKind {
    collectFromAllPrecedingTrivia(of: node)
    return .visitChildren
  }

  override func visit(_ node: MemberBlockItemSyntax) -> SyntaxVisitorContinueKind {
    collectFromAllPrecedingTrivia(of: node)
    return .visitChildren
  }

  override func visit(_ node: CodeBlockSyntax) -> SyntaxVisitorContinueKind {
    collect(from: node.rightBrace.leadingTrivia, of: node.rightBrace)
    return .visitChildren
  }

  override func visit(_ node: MemberBlockSyntax) -> SyntaxVisitorContinueKind {
    collect(from: node.rightBrace.leadingTrivia, of: node.rightBrace)
    return .visitChildren
  }

  // MARK: - Helper Methods

  /// Records the directives in the preceding trivia of a statement-level item.
  private func collectFromAllPrecedingTrivia(of item: some SyntaxProtocol) {
    guard let token = item.firstToken(viewMode: .sourceAccurate) else {
      return
    }
    collect(
      from: token.allPrecedingTrivia,
      of: token
    )
  }

  /// Records the directives in the given trivia, anchored at the following token.
  private func collect(from trivia: Trivia, of token: TokenSyntax) {
    for comment in DisableDirective.lineComments(
      in: trivia,
      endingAt: token.positionAfterSkippingLeadingTrivia.utf8Offset
    ) {
      record(comment: comment.text, offset: comment.startOffset)
    }
  }

  /// Records an event for the given comment when it is a disable/enable directive.
  private func record(comment text: String, offset: Int) {
    guard let effect = DisableDirective.match(commentText: text) else {
      return
    }
    let line = sourceLocationConverter.location(for: AbsolutePosition(utf8Offset: offset)).line
    events.append(
      DisableDirectiveEvent(effect: effect, line: line, offset: offset)
    )
  }
}

/// Represents the kind of ignore directive encountered in the source.
enum IgnoreDirective: CustomStringConvertible {
  typealias RegexExpression = Regex<(Substring, ruleNames: Substring?)>

  /// A node-level directive that disables rules for the following node and its children.
  case node
  /// A file-level directive that disables rules for the entire file.
  case file

  var description: String {
    switch self {
    case .node:
      return "swift-format-ignore"
    case .file:
      return "swift-format-ignore-file"
    }
  }

  /// Regex pattern to match an ignore directive comment.
  /// - Captures rule names when `:` is present.
  ///
  /// Note: We are using a string-based regex instead of a regex literal (`#/regex/#`)
  /// because Windows did not have full support for regex literals until Swift 5.10.
  fileprivate func makeRegex() -> RegexExpression {
    let pattern = #"^\s*\/\/\s*"# + description + #"(?:\s*:\s*(?<ruleNames>.+))?$"#
    return try! Regex(pattern).matchingSemantics(.unicodeScalar)
  }
}

/// A syntax visitor that finds `SourceRange`s of nodes that have rule status modifying comment
/// directives. The changes requested in each comment is parsed and collected into a map to support
/// status lookup per rule name.
///
/// The rule status comment directives implementation intentionally supports exactly the same nodes
/// as `TokenStreamCreator` to disable pretty printing. This ensures ignore comments for pretty
/// printing and for rules are as consistent as possible.
private class RuleStatusCollectionVisitor: SyntaxVisitor {
  /// Describes the possible matches for ignore directives, in comments.
  enum RuleStatusDirectiveMatch {
    /// There is a directive that applies to all rules.
    case all

    /// There is a directive that applies to a number of rules. The names of the rules are provided
    /// in `ruleNames`.
    case subset(ruleNames: [String])
  }

  /// Cached regex object for ignoring rules at the node.
  private static let ignoreRegex: IgnoreDirective.RegexExpression = IgnoreDirective.node.makeRegex()

  /// Cached regex object for ignoring rules at the file.
  private static let ignoreFileRegex: IgnoreDirective.RegexExpression = IgnoreDirective.file.makeRegex()

  /// Computes source locations and ranges for syntax nodes in a source file.
  private let sourceLocationConverter: SourceLocationConverter

  /// Stores the source ranges in which all rules are ignored.
  var allRulesIgnoredRanges: [SourceRange] = []

  /// Map of rule names to list ranges in the source where the rule is ignored.
  var ruleMap: [String: [SourceRange]] = [:]

  init(sourceLocationConverter: SourceLocationConverter) {
    self.sourceLocationConverter = sourceLocationConverter
    super.init(viewMode: .sourceAccurate)
  }

  // MARK: - Syntax Visitation Methods

  override func visit(_ node: SourceFileSyntax) -> SyntaxVisitorContinueKind {
    guard let firstToken = node.firstToken(viewMode: .sourceAccurate) else {
      return .visitChildren
    }
    let sourceRange = node.sourceRange(
      converter: sourceLocationConverter,
      afterLeadingTrivia: false,
      afterTrailingTrivia: true
    )
    return appendRuleStatus(from: firstToken, of: sourceRange, using: Self.ignoreFileRegex)
  }

  override func visit(_ node: CodeBlockItemSyntax) -> SyntaxVisitorContinueKind {
    guard let firstToken = node.firstToken(viewMode: .sourceAccurate) else {
      return .visitChildren
    }
    let sourceRange = node.sourceRange(converter: sourceLocationConverter)
    return appendRuleStatus(from: firstToken, of: sourceRange, using: Self.ignoreRegex)
  }

  override func visit(_ node: MemberBlockItemSyntax) -> SyntaxVisitorContinueKind {
    guard let firstToken = node.firstToken(viewMode: .sourceAccurate) else {
      return .visitChildren
    }
    let sourceRange = node.sourceRange(converter: sourceLocationConverter)
    return appendRuleStatus(from: firstToken, of: sourceRange, using: Self.ignoreRegex)
  }

  // MARK: - Helper Methods

  /// Searches for comments on the given token that explicitly modify the status of rules and adds
  /// them to the appropriate collection of those changes.
  ///
  /// - Parameters:
  ///   - token: A token that may have comments that modify the status of rules.
  ///   - sourceRange: The range covering the node to which `token` belongs. If an ignore directive
  ///     is found among the comments, this entire range is used to ignore the specified rules.
  ///   - regex: The regular expression used to detect ignore directives.
  private func appendRuleStatus(
    from token: TokenSyntax,
    of sourceRange: SourceRange,
    using regex: IgnoreDirective.RegexExpression
  ) -> SyntaxVisitorContinueKind {
    let isFirstInFile = token.previousToken(viewMode: .sourceAccurate) == nil
    let comments = loneLineComments(in: token.leadingTrivia, isFirstToken: isFirstInFile)
    for comment in comments {
      guard let matchResult = ruleStatusDirectiveMatch(in: comment, using: regex) else { continue }
      switch matchResult {
      case .all:
        allRulesIgnoredRanges.append(sourceRange)

        // All rules are ignored for the entire node and its children. Any ignore comments in the
        // node's children are irrelevant because all rules are suppressed by this node.
        return .skipChildren
      case .subset(let ruleNames):
        for ruleName in ruleNames {
          ruleMap[ruleName, default: []].append(sourceRange)
        }
        break
      }
    }
    return .visitChildren
  }

  /// Checks if a comment containing the given text matches a rule status directive. When it does
  /// match, its contents (e.g. list of rule names) are returned.
  private func ruleStatusDirectiveMatch(
    in text: String,
    using regex: IgnoreDirective.RegexExpression
  ) -> RuleStatusDirectiveMatch? {
    guard let match = text.firstMatch(of: regex) else {
      return nil
    }
    guard let matchedRuleNames = match.output.ruleNames else {
      return .all
    }
    let rules = matchedRuleNames.split(separator: ",")
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { $0.count > 0 }
    return .subset(ruleNames: rules)
  }

  /// Returns the list of line comments in the given trivia that are on a line by themselves
  /// (excluding leading whitespace).
  ///
  /// - Parameters:
  ///   - trivia: The trivia collection to scan for comments.
  ///   - isFirstToken: True if the trivia came from the first token in the file.
  /// - Returns: The list of lone line comments from the trivia.
  private func loneLineComments(in trivia: Trivia, isFirstToken: Bool) -> [String] {
    var currentComment: String? = nil
    var lineComments = [String]()

    for piece in trivia.reversed() {
      switch piece {
      case .lineComment(let text):
        currentComment = text
      case .spaces, .tabs:
        break  // Intentionally do nothing.
      case .carriageReturnLineFeeds, .carriageReturns, .newlines:
        if let text = currentComment {
          lineComments.insert(text, at: 0)
          currentComment = nil
        }
      default:
        // If anything other than spaces intervened between the line comment and a newline, then the
        // comment isn't on a line by itself, so reset our state.
        currentComment = nil
      }
    }

    // For the first token in the file, there may not be a newline preceding the first line comment,
    // so check for that here.
    if isFirstToken, let text = currentComment {
      lineComments.insert(text, at: 0)
    }

    return lineComments
  }
}
