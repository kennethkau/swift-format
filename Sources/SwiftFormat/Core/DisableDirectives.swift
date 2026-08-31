//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import SwiftSyntax

/// Parsing for `swift-format-disable`/`swift-format-enable` directive comments and collection
/// of the regions they cover, shared by the rule mask and the pretty printer.
///
///   // swift-format-disable
///   let a = 123            // all rules disabled, region printed verbatim
///   // swift-format-enable
///
///   // swift-format-disable: RuleName, OtherRuleName
///   let a = 123            // only the named rules disabled, region still formatted
///   // swift-format-enable
///
///   // swift-format-disable:next RuleName
///   let a = 123            // named rules (or all, with no list) off on this line only
///
/// `:this` and `:previous` scope to the directive's own line and the line before it; line
/// scopes suppress rules and findings only. An unterminated block runs to end of file, and
/// `swift-format-enable: RuleName` re-enables one rule inside an all-rules block. Directives
/// are recognized before statement-level items (including as trailing comments), before the
/// closing brace of a code or member block, and at end of file; anywhere else they are inert.
enum DisableDirective {
  /// What a directive comment instructs the formatter to do.
  enum Effect: Equatable {
    /// Begin a block in which all rules are disabled.
    case disableAll

    /// Begin a block in which the named rules are disabled.
    case disableRules([String])

    /// End all open blocks, re-enabling every rule.
    case enableAll

    /// Re-enable the named rules inside open blocks.
    case enableRules([String])

    /// Disable the named rules (or all rules when the list is empty) on a single line.
    case lineScope(LineScope, [String])
  }

  /// The line a line-scoped directive applies to, relative to the directive's own line.
  enum LineScope: String, Equatable, CaseIterable {
    case next
    case this
    case previous
  }

  /// Matches a directive in the text of a line comment, or nil if there is none.
  static func match(commentText: String) -> Effect? {
    var text = Substring(commentText)
    guard text.hasPrefix("//") else {
      return nil
    }
    text = text.dropFirst(2).drop(while: { $0 == " " || $0 == "\t" })

    guard let (verb, remainder) = splitVerb(text) else {
      return nil
    }

    switch verb {
    case "swift-format-disable":
      if remainder.isEmpty {
        return .disableAll
      }
      guard remainder.first == ":" else {
        return nil
      }
      let arguments = remainder.dropFirst().drop(while: { $0 == " " || $0 == "\t" })
      if let scope = lineScopePrefix(of: arguments) {
        let rules = parseRuleNames(String(scope.remainder))
        return .lineScope(scope.scope, rules)
      }
      let rules = parseRuleNames(String(arguments))
      return rules.isEmpty ? nil : .disableRules(rules)

    case "swift-format-enable":
      if remainder.isEmpty {
        return .enableAll
      }
      guard remainder.first == ":" else {
        return nil
      }
      let arguments = remainder.dropFirst().drop(while: { $0 == " " || $0 == "\t" })
      let rules = parseRuleNames(String(arguments))
      return rules.isEmpty ? nil : .enableRules(rules)

    default:
      return nil
    }
  }

  /// Splits the directive verb from the rest of the comment; a colon, whitespace, or end of
  /// comment must follow so `swift-format-disabled` is not mistaken for a directive.
  private static func splitVerb(_ text: Substring) -> (String, Substring)? {
    let verbs = ["swift-format-disable", "swift-format-enable"]
    for verb in verbs where text.hasPrefix(verb) {
      let remainder = text.dropFirst(verb.count)
      if remainder.isEmpty || remainder.first == ":" {
        return (verb, remainder)
      }
    }
    return nil
  }

  /// Splits a leading `next`/`this`/`previous` keyword (followed by whitespace or end of
  /// comment) from a disable directive's arguments; the keywords are reserved for the
  /// line-scoped form and cannot be rule names.
  private static func lineScopePrefix(of text: Substring) -> (scope: LineScope, remainder: Substring)? {
    for scope in LineScope.allCases {
      let keyword = scope.rawValue
      guard text.hasPrefix(keyword) else {
        continue
      }
      let remainder = text.dropFirst(keyword.count)
      if remainder.isEmpty || remainder.first == " " || remainder.first == "\t" {
        return (scope, remainder)
      }
    }
    return nil
  }

  /// Parses a comma- and/or whitespace-separated list of rule names.
  private static func parseRuleNames(_ text: String) -> [String] {
    return
      text
      .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\t" })
      .map(String.init)
  }

  /// Returns the line comments in the given trivia with their byte offsets, in source order,
  /// computed backwards from `endingOffset` (where the trivia ends at its token). A comment
  /// with no newline after it — before the file's first token, or trailing a line of code —
  /// counts too, like the node-level ignore directive.
  static func lineComments(
    in trivia: Trivia,
    endingAt endingOffset: Int
  ) -> [(text: String, startOffset: Int)] {
    var comments: [(text: String, startOffset: Int)] = []
    var cursor = endingOffset
    for piece in trivia.reversed() {
      cursor -= piece.sourceLength.utf8Length
      if case .lineComment(let text) = piece {
        comments.append((text, cursor))
      }
    }
    return comments.reversed()
  }
}

/// Computes the byte-offset regions covered by all-rules disable blocks, which the pretty
/// printer emits verbatim. The regions are precomputed from events in source order rather than
/// tracked during the walk, because a `SyntaxVisitor` visits a statement list before its items.
enum DisableRegionCollector {
  /// A half-open range of UTF-8 byte offsets covering one all-rules disable block, from the
  /// start of its `swift-format-disable` comment through the end of its `swift-format-enable`
  /// comment (or the end of the tree when the block is unterminated).
  struct Region: Equatable {
    var lowerBound: Int
    var upperBound: Int

    /// Whether the given UTF-8 byte offset lies inside the region.
    func contains(_ offset: Int) -> Bool {
      lowerBound <= offset && offset < upperBound
    }
  }

  /// Collects the all-rules disable block regions in the given tree.
  static func verbatimRegions(in root: Syntax) -> [Region] {
    let walker = DirectiveEventWalker()
    walker.walk(root)

    var regions: [Region] = []
    var openStart: Int? = nil
    for event in walker.events.sorted(by: { $0.startOffset < $1.startOffset }) {
      switch event.effect {
      case .disableAll:
        if openStart == nil {
          openStart = event.startOffset
        }
      case .enableAll:
        if let start = openStart {
          regions.append(Region(lowerBound: start, upperBound: event.endOffset))
          openStart = nil
        }
      case .disableRules, .enableRules, .lineScope:
        // Only all-rules blocks are printed verbatim; named-rule blocks and line-scoped
        // directives suppress rules and findings without changing how the region prints.
        break
      }
    }
    if let start = openStart {
      regions.append(Region(lowerBound: start, upperBound: root.totalLength.utf8Length))
    }
    return regions
  }

  /// Whether the node's code (its first token, after leading trivia) starts inside one of the
  /// given regions, i.e. the node is covered by an all-rules disable block.
  static func isVerbatim(_ node: Syntax, regions: [Region]) -> Bool {
    let offset = node.positionAfterSkippingLeadingTrivia.utf8Offset
    return regions.contains { $0.contains(offset) }
  }

  /// Whether the token's text starts inside one of the given regions.
  static func isVerbatim(_ token: TokenSyntax, regions: [Region]) -> Bool {
    return regions.contains { $0.contains(token.positionAfterSkippingLeadingTrivia.utf8Offset) }
  }

  /// A syntax visitor that records disable/enable directives with their byte offsets, using
  /// the same recognition points as the rule mask's `DisableDirectiveSweeper`.
  private final class DirectiveEventWalker: SyntaxVisitor {
    /// One directive comment: its effect and the byte range its text occupies.
    struct Event {
      var effect: DisableDirective.Effect
      var startOffset: Int
      var endOffset: Int
    }

    /// The events found so far; sort by offset before use, because closing-brace trivia is
    /// visited before the items that precede it in the source.
    var events: [Event] = []

    init() {
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
      for comment in DisableDirective.lineComments(
        in: token.allPrecedingTrivia,
        endingAt: token.positionAfterSkippingLeadingTrivia.utf8Offset
      ) {
        record(comment)
      }
    }

    /// Records the directives in the preceding trivia of a structural token (a closing brace
    /// or the end-of-file token).
    private func collect(from trivia: Trivia, of token: TokenSyntax) {
      for comment in DisableDirective.lineComments(
        in: trivia,
        endingAt: token.positionAfterSkippingLeadingTrivia.utf8Offset
      ) {
        record(comment)
      }
    }

    /// Records an event for the given comment when it is a disable/enable directive.
    private func record(_ comment: (text: String, startOffset: Int)) {
      guard let effect = DisableDirective.match(commentText: comment.text) else {
        return
      }
      events.append(
        Event(
          effect: effect,
          startOffset: comment.startOffset,
          endOffset: comment.startOffset + comment.text.utf8.count
        )
      )
    }
  }
}
