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

import Foundation
import SwiftOperators
import SwiftParser
import SwiftSyntax

/// Compares two syntax trees for semantic-shape equivalence, for `format --verify`: the
/// formatted output is re-parsed and compared against a re-parse of the input, and any
/// difference that is not one of the tolerances below is a mismatch. Trivia is ignored
/// entirely.
///
/// Tolerated rewrites, each matching a rule that performs it:
///
/// 1. `(x)` ≡ `x` for single-element unlabeled tuples — `RedundantParens`,
///    `NoParensAroundConditions`
/// 2. `self.foo` ≡ `foo` where the base is exactly `self` — `RedundantSelf`
/// 3. `()` ≡ `Void` in type position — `ReturnVoidInsteadOfEmptyTuple`
/// 4. Numeric literal spellings: separators, case, insignificant zeros —
///    `GroupNumericLiterals`, `CanonicalNumberLiterals`
/// 5. String literals compared by decoded content: raw delimiters, escapes —
///    `RedundantRawString`, `CanonicalStringEscapes`
/// 6. Import runs and modifier/attribute lists compare as multisets — `OrderedImports`,
///    `ModifierOrder`, `AttributeOrder`
/// 7. Trailing commas and statement semicolons compare as absent — the trailing comma
///    configuration, `DoNotUseSemicolons`
/// 8. The nonlocal canonicalizations of the default-on rules (access levels moved off
///    extensions, `case let` distribution, `-> Void` removal, shorthand type names) are
///    tolerated by running those rules on both trees before comparing, so the tolerance
///    cannot drift from the rules that define it
///
/// The comparison is syntactic, not type-checked: `self`-removal is accepted even where a
/// local binding shadows the member, and the structural rewrites of
/// `OneVariableDeclarationPerLine`, `OneCasePerLine`, `NoCasesWithOnlyFallthrough`,
/// `NoEmptyTrailingClosureParentheses`, `UseSingleLinePropertyGetter`, and
/// `FileScopedDeclarationPrivacy` are reported as mismatches rather than tolerated.
/// Everything else must match exactly.
@_spi(Internal)
public enum SyntaxVerifier {

  /// A single difference found between the original and formatted trees.
  public struct Mismatch: CustomStringConvertible {
    /// A description of where in the tree the mismatch was found (e.g. the chain of node kinds
    /// from the root).
    public let path: [String]

    /// The byte offset of the mismatching node in the formatted source, if known.
    public let formattedOffset: Int?

    /// A human-readable description of the mismatch.
    public let description: String

    /// A shorter description of the mismatch location for diagnostics, e.g.
    /// "FunctionDecl > CodeBlock > ReturnStmt".
    public var pathDescription: String {
      path.joined(separator: " > ")
    }
  }

  /// The maximum number of mismatches `verify` reports before stopping.
  public static let defaultLimit = 5

  /// The maximum syntax-tree nesting depth the comparison recurses to; beyond it a mismatch is
  /// reported rather than exhausting the stack.
  private static let maximumDepth = 200

  /// The maximum number of candidate pairs the multiset matcher may probe before giving up and
  /// reporting a mismatch, bounding the worst-case factorial exploration on adversarial lists.
  /// Shared across nested matchers, whose probes would otherwise each restart the budget.
  private static let maximumMultisetProbes = 20_000

  /// Parses the given source and folds operators, producing the same shape of tree the
  /// formatter itself operates on, with the same experimental parser features.
  public static func parseFolded(
    _ source: String,
    languageFeatures: Parser.LanguageFeatures = []
  ) throws -> SourceFileSyntax {
    let tree = Parser.parse(source: source, languageFeatures: languageFeatures)
    return try OperatorTable.standardOperators.foldAll(tree) { _ in }
      .as(SourceFileSyntax.self)!
  }

  /// Compares the original and formatted trees, returning up to `limit` mismatches in the
  /// formatted tree's source order; empty when the trees are equivalent.
  public static func verify(
    original: SourceFileSyntax,
    formatted: SourceFileSyntax,
    limit: Int = defaultLimit
  ) -> [Mismatch] {
    // Error-recovery trees are not faithful parses; comparing two of them could certify a
    // broken rewrite, so verification refuses.
    if original.hasError || formatted.hasError {
      return [
        Mismatch(
          path: [],
          formattedOffset: nil,
          description: "the source or the formatted output does not parse cleanly"
        )
      ]
    }
    var collector = MismatchCollector(limit: limit)
    collector.compare(Syntax(normalized(original)), Syntax(normalized(formatted)), path: [], depth: 0)
    return collector.mismatches
  }

  /// Applies the normalizer rules to a tree. Their rewrites move tokens across node
  /// boundaries, which the local comparison cannot tolerate; running the rules on both sides
  /// normalizes them into the same shape.
  private static func normalized(_ tree: SourceFileSyntax) -> SourceFileSyntax {
    var configuration = Configuration()
    let normalizingRules: [SyntaxFormatRule.Type] = [
      NoAccessLevelOnExtensionDeclaration.self,
      UseLetInEveryBoundCaseVariable.self,
      NoVoidReturnOnFunctionSignature.self,
      UseShorthandTypeNames.self,
    ]
    for rule in normalizingRules {
      configuration.rules[rule.ruleName] = true
    }
    let context = Context(
      configuration: configuration,
      operatorTable: .standardOperators,
      findingConsumer: nil,
      fileURL: URL(fileURLWithPath: "verify.swift"),
      selection: .infinite,
      sourceFileSyntax: tree,
      ruleNameCache: ruleNameCache
    )
    var normalized = Syntax(tree)
    for rule in normalizingRules {
      normalized = rule.init(context: context).rewrite(normalized)
    }
    return normalized.cast(SourceFileSyntax.self)
  }

  // MARK: - Comparison

  /// Accumulates mismatches up to a limit while the trees are compared.
  private struct MismatchCollector {
    let limit: Int
    var mismatches: [Mismatch] = []

    /// The multiset matcher's probe budget, shared by every nested matcher so the bound holds
    /// for the whole comparison rather than per nesting level.
    final class ProbeBudget {
      var probes = 0
    }

    let probeBudget: ProbeBudget

    init(limit: Int, probeBudget: ProbeBudget = ProbeBudget()) {
      self.limit = max(limit, 1)
      self.probeBudget = probeBudget
    }

    var isFull: Bool {
      mismatches.count >= limit
    }

    /// Compares two nodes, recording a mismatch describing the first way they differ.
    mutating func compare(_ a: Syntax, _ b: Syntax, path: [String], depth: Int) {
      if isFull {
        return
      }

      // Bounded depth: fail with a diagnostic instead of exhausting the stack.
      guard depth < SyntaxVerifier.maximumDepth else {
        record(
          a: a,
          b: b,
          path: path,
          description: "nesting is too deep to verify (more than \(SyntaxVerifier.maximumDepth) levels)"
        )
        return
      }

      // Unwrap redundant parentheses on either side before any kind comparison.
      let normalizedA = Self.withoutRedundantParens(a)
      let normalizedB = Self.withoutRedundantParens(b)
      if normalizedA != a || normalizedB != b {
        compare(normalizedA, normalizedB, path: path, depth: depth)
        return
      }

      // Token kinds carry the text of identifiers, keywords, and operators.
      if let aToken = a.as(TokenSyntax.self), let bToken = b.as(TokenSyntax.self) {
        if !tokensMatch(aToken, bToken) {
          record(a: a, b: b, path: path)
        }
        return
      }

      // `self.foo` is equivalent to `foo`.
      if let strippedA = Self.selfBaseStripped(a) {
        compare(strippedA, b, path: path, depth: depth)
        return
      }
      if let strippedB = Self.selfBaseStripped(b) {
        compare(a, strippedB, path: path, depth: depth)
        return
      }

      // `()` is equivalent to `Void` in type position.
      if Self.isEmptyTupleType(a), Self.isVoidType(b) {
        return
      }
      if Self.isVoidType(a), Self.isEmptyTupleType(b) {
        return
      }

      // String literals compare by decoded content.
      if let aString = a.as(StringLiteralExprSyntax.self),
        let bString = b.as(StringLiteralExprSyntax.self)
      {
        if !stringLiteralsMatch(aString, bString) {
          record(a: a, b: b, path: path)
        }
        return
      }

      guard a.kind == b.kind else {
        record(a: a, b: b, path: path)
        return
      }

      let childrenA = Array(a.children(viewMode: .sourceAccurate))
      let childrenB = Array(b.children(viewMode: .sourceAccurate))

      // Import runs and modifier/attribute lists compare as multisets.
      if Self.isOrderInsensitiveList(a) {
        if !childrenMatchAsMultiset(childrenA[...], childrenB[...], path: path, depth: depth) {
          record(a: a, b: b, path: path)
        }
        return
      }
      if Self.isStatementLevelList(a) {
        let nonImportsA = childrenA.filter { !Self.isImportItem($0) }
        let nonImportsB = childrenB.filter { !Self.isImportItem($0) }
        let importsA = childrenA.filter(Self.isImportItem)
        let importsB = childrenB.filter(Self.isImportItem)
        if nonImportsA.count != nonImportsB.count
          || !childrenMatchAsMultiset(importsA[...], importsB[...], path: path, depth: depth)
        {
          record(a: a, b: b, path: path)
          return
        }
        compareChildren(nonImportsA[...], nonImportsB[...], path: path, depth: depth)
        return
      }

      // A trailing comma or statement semicolon is inert.
      if Self.lastChildIsTrailingSeparator(childrenA) || Self.lastChildIsTrailingSeparator(childrenB) {
        compareChildren(
          Self.withoutTrailingSeparator(childrenA)[...],
          Self.withoutTrailingSeparator(childrenB)[...],
          path: path,
          depth: depth
        )
        return
      }

      guard childrenA.count == childrenB.count else {
        record(a: a, b: b, path: path)
        return
      }
      compareChildren(childrenA[...], childrenB[...], path: path, depth: depth)
    }

    /// Compares two same-length child sequences pairwise.
    mutating func compareChildren(
      _ a: ArraySlice<Syntax>,
      _ b: ArraySlice<Syntax>,
      path: [String],
      depth: Int
    ) {
      for (childA, childB) in zip(a, b) {
        if isFull {
          return
        }
        compare(childA, childB, path: path + [Self.nodeName(childA)], depth: depth + 1)
      }
    }

    /// Compares two child sequences as a multiset. Mismatches are not recorded here; the caller
    /// records one for the list as a whole when the match fails.
    mutating func childrenMatchAsMultiset(
      _ a: ArraySlice<Syntax>,
      _ b: ArraySlice<Syntax>,
      path: [String],
      depth: Int
    ) -> Bool {
      if a.isEmpty {
        return b.isEmpty
      }
      guard let first = a.first else {
        return false
      }
      for (offset, candidate) in b.enumerated() {
        // The shared budget bounds the factorial exploration of equivalent-but-unmatchable
        // lists, including through nested matchers; exhausting it fails the match, which the
        // caller reports as a mismatch.
        guard probeBudget.probes < SyntaxVerifier.maximumMultisetProbes else {
          return false
        }
        probeBudget.probes += 1
        var probe = MismatchCollector(limit: 1, probeBudget: probeBudget)
        probe.compare(first, candidate, path: path, depth: depth + 1)
        if probe.mismatches.isEmpty {
          var remaining = b
          remaining.remove(at: offset)
          if childrenMatchAsMultiset(a.dropFirst(), remaining[...], path: path, depth: depth) {
            return true
          }
        }
      }
      return false
    }

    /// Records a mismatch between the two nodes.
    mutating func record(a: Syntax, b: Syntax, path: [String], description: String? = nil) {
      guard !isFull else { return }
      mismatches.append(
        Mismatch(
          path: path,
          formattedOffset: b.positionAfterSkippingLeadingTrivia.utf8Offset,
          description: description ?? Self.describeDifference(a: a, b: b)
        )
      )
    }

    // MARK: Token comparison

    /// Compares two tokens, normalizing numeric literal spellings.
    func tokensMatch(_ a: TokenSyntax, _ b: TokenSyntax) -> Bool {
      switch (a.tokenKind, b.tokenKind) {
      case (.integerLiteral(let textA), .integerLiteral(let textB)),
        (.floatLiteral(let textA), .floatLiteral(let textB)):
        return Self.numericSpellingsMatch(textA, textB)
      default:
        return a.tokenKind == b.tokenKind
      }
    }

    // MARK: String literals

    /// One piece of a decoded string literal: literal text or an interpolated expression.
    private enum StringSegment {
      case text(String)
      case expression(Syntax)
    }

    /// Compares two string literals by their decoded content.
    func stringLiteralsMatch(_ a: StringLiteralExprSyntax, _ b: StringLiteralExprSyntax) -> Bool {
      let segmentsA = Self.decodedSegments(a)
      let segmentsB = Self.decodedSegments(b)
      guard segmentsA.count == segmentsB.count else {
        return false
      }
      for (segmentA, segmentB) in zip(segmentsA, segmentsB) {
        switch (segmentA, segmentB) {
        case (.text(let textA), .text(let textB)):
          if textA != textB {
            return false
          }
        case (.expression(let exprA), .expression(let exprB)):
          var probe = MismatchCollector(limit: 1, probeBudget: probeBudget)
          probe.compare(exprA, exprB, path: [], depth: 0)
          if !probe.mismatches.isEmpty {
            return false
          }
        default:
          return false
        }
      }
      return true
    }

    /// Decodes the segments of a string literal into text and interpolated expressions:
    /// escapes are decoded in regular literals and inert in raw ones; a multiline literal's
    /// opening and closing newlines are stripped.
    private static func decodedSegments(_ literal: StringLiteralExprSyntax) -> [StringSegment] {
      let isRaw = literal.openingPounds != nil
      let isMultiline = literal.openingQuote.text == "\"\"\""

      var segments: [StringSegment] = []
      var pendingText: [String] = []

      func flush() {
        guard !pendingText.isEmpty else { return }
        segments.append(.text(pendingText.joined()))
        pendingText.removeAll()
      }

      for segment in literal.segments {
        if let textSegment = segment.as(StringSegmentSyntax.self) {
          var text = textSegment.content.text
          if !isRaw {
            text = decodeEscapes(in: text)
          }
          pendingText.append(text)
        } else if let expressionSegment = segment.as(ExpressionSegmentSyntax.self) {
          flush()
          // Only the interpolated expressions are compared: the segment's delimiters carry the
          // raw-string pound spelling, which the tolerated rewrites may change.
          segments.append(.expression(Syntax(expressionSegment.expressions)))
        } else {
          pendingText.append(segment.description)
        }
      }
      flush()

      // A multiline literal whose content begins with a newline has that newline stripped, as
      // does a final newline before the closing delimiter.
      if isMultiline, case .text(let text)? = segments.first {
        var stripped = text
        if stripped.hasPrefix("\r\n") {
          stripped.removeFirst(2)
        } else if stripped.hasPrefix("\n") {
          stripped.removeFirst()
        }
        segments[0] = .text(stripped)
      }
      if isMultiline, case .text(let text)? = segments.last {
        var stripped = text
        if stripped.hasSuffix("\r\n") {
          stripped.removeLast(2)
        } else if stripped.hasSuffix("\n") {
          stripped.removeLast()
        }
        segments[segments.count - 1] = .text(stripped)
      }

      return segments
    }

    /// Decodes the escape sequences in a non-raw string literal segment; unrecognized shapes
    /// pass through unchanged.
    private static func decodeEscapes(in text: String) -> String {
      var scalars = Substring(text)
      var decoded = ""
      while let backslash = scalars.firstIndex(of: "\\") {
        decoded += scalars[..<backslash]
        scalars = scalars[scalars.index(after: backslash)...]
        guard let escape = scalars.first else {
          decoded += "\\"
          return decoded
        }
        switch escape {
        case "0": decoded += "\u{0}"; scalars = scalars.dropFirst()
        case "t": decoded += "\t"; scalars = scalars.dropFirst()
        case "n": decoded += "\n"; scalars = scalars.dropFirst()
        case "r": decoded += "\r"; scalars = scalars.dropFirst()
        case "\"": decoded += "\""; scalars = scalars.dropFirst()
        case "'": decoded += "'"; scalars = scalars.dropFirst()
        case "\\": decoded += "\\"; scalars = scalars.dropFirst()
        case "u":
          // `\u{XXXX}` with any number of hex digits.
          if scalars.dropFirst().first == "{" {
            let afterBrace = scalars.dropFirst(2)
            var hex = ""
            var length = 0
            var closed = false
            for scalar in afterBrace {
              length += 1
              if scalar == "}" {
                closed = true
                break
              }
              hex.append(scalar)
            }
            scalars = scalars.dropFirst(2 + length)
            if closed, let value = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(value) {
              decoded.unicodeScalars.append(scalar)
            } else {
              // Malformed escape; keep the source shape on both sides.
              decoded += "u{" + hex + (closed ? "}" : "")
            }
          } else {
            decoded += "u"
            scalars = scalars.dropFirst()
          }
        default:
          decoded.append(escape)
          scalars = scalars.dropFirst()
        }
      }
      return decoded + scalars
    }

    // MARK: Normalizations

    /// Returns the node with one level of redundant parentheses unwrapped, or the node itself;
    /// labeled and multi-element tuples keep their structure.
    static func withoutRedundantParens(_ node: Syntax) -> Syntax {
      guard let tuple = node.as(TupleExprSyntax.self),
        tuple.elements.count == 1,
        let only = tuple.elements.first,
        only.label == nil
      else {
        return node
      }
      return Syntax(only.expression)
    }

    /// If the node is a member access with base exactly `self`, returns the bare reference.
    static func selfBaseStripped(_ node: Syntax) -> Syntax? {
      guard let memberAccess = node.as(MemberAccessExprSyntax.self),
        let base = memberAccess.base,
        Self.isSelfReference(Syntax(base))
      else {
        return nil
      }
      return Syntax(memberAccess.declName)
    }

    /// Whether the node is a plain `self` reference.
    static func isSelfReference(_ node: Syntax) -> Bool {
      guard let reference = node.as(DeclReferenceExprSyntax.self),
        reference.argumentNames == nil
      else {
        return false
      }
      if case .keyword(.self) = reference.baseName.tokenKind {
        return true
      }
      return false
    }

    /// Whether the node is a tuple type with no elements (`()`).
    static func isEmptyTupleType(_ node: Syntax) -> Bool {
      guard let tupleType = node.as(TupleTypeSyntax.self) else {
        return false
      }
      return tupleType.elements.isEmpty
    }

    /// Whether the node is the `Void` type identifier.
    static func isVoidType(_ node: Syntax) -> Bool {
      guard let identifierType = node.as(IdentifierTypeSyntax.self),
        identifierType.genericArgumentClause == nil
      else {
        return false
      }
      return identifierType.name.tokenKind == .identifier("Void")
    }

    /// Whether the node is a modifier or attribute list, whose order the formatter may
    /// canonicalize.
    static func isOrderInsensitiveList(_ node: Syntax) -> Bool {
      node.kind == .declModifierList || node.kind == .attributeList
    }

    /// Whether the node is a statement or member list, in which runs of imports may be
    /// reordered.
    static func isStatementLevelList(_ node: Syntax) -> Bool {
      node.kind == .codeBlockItemList || node.kind == .memberBlockItemList
    }

    /// Whether the node's last child is a trailing separator token: a comma in a comma-delimited
    /// element such as a labeled expression or a function parameter, or a semicolon on a
    /// statement.
    static func lastChildIsTrailingSeparator(_ children: [Syntax]) -> Bool {
      guard let last = children.last, let token = last.as(TokenSyntax.self) else {
        return false
      }
      return token.tokenKind == .comma || token.tokenKind == .semicolon
    }

    /// Returns the children with a single trailing separator token removed, if one is present.
    static func withoutTrailingSeparator(_ children: [Syntax]) -> [Syntax] {
      guard lastChildIsTrailingSeparator(children) else {
        return children
      }
      return Array(children.dropLast())
    }

    /// Whether the node is a statement wrapping an import declaration.
    static func isImportItem(_ node: Syntax) -> Bool {
      guard let item = node.as(CodeBlockItemSyntax.self) else {
        return false
      }
      return item.item.is(ImportDeclSyntax.self)
    }

    // MARK: Literal normalization

    /// Compares two numeric literal spellings after normalizing the dimensions the formatter's
    /// literal rules are allowed to change: digit separators, case, and insignificant leading or
    /// trailing zeros.
    static func numericSpellingsMatch(_ a: String, _ b: String) -> Bool {
      normalizeNumericSpelling(a) == normalizeNumericSpelling(b)
    }

    /// Normalizes a numeric literal spelling: radix prefixes and exponent markers lowercased,
    /// underscores removed, insignificant leading and trailing zeros removed (keeping one
    /// digit so a float stays floating-point). Value-relevant digits are untouched.
    static func normalizeNumericSpelling(_ literal: String) -> String {
      var text = literal.replacingOccurrences(of: "_", with: "")
      text = text.lowercased()

      var prefix = ""
      if text.hasPrefix("0x") || text.hasPrefix("0o") || text.hasPrefix("0b") {
        prefix = String(text.prefix(2))
        text = String(text.dropFirst(2))
      }

      // Split off a decimal exponent so fraction normalization does not touch it. In a
      // hexadecimal literal `p` starts the exponent and `e` is a digit; otherwise `e` starts it.
      let exponentMarker: Character? = prefix == "0x" ? "p" : "e"
      var exponent = ""
      if let marker = exponentMarker, let markerIndex = text.firstIndex(of: marker) {
        exponent = String(text[markerIndex...])
        text = String(text[..<markerIndex])
      }

      var parts = text.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        .map(String.init)
      if !parts.isEmpty {
        parts[0] = Self.trimLeadingZeros(parts[0])
      }
      if parts.count == 2 {
        parts[1] = Self.trimTrailingZeros(parts[1])
      }
      var normalized = parts.joined(separator: ".")
      if !exponent.isEmpty {
        let marker = exponent.first!
        let digits = String(exponent.dropFirst())
        normalized += "\(marker)\(Self.trimLeadingZeros(digits, allowSign: true))"
      }
      return prefix + normalized
    }

    /// Removes insignificant leading zeros from a digit string, keeping at least one digit. A
    /// leading sign, when allowed, is preserved.
    private static func trimLeadingZeros(_ digits: String, allowSign: Bool = false) -> String {
      var sign = ""
      var body = digits
      if allowSign, let first = body.first, first == "+" || first == "-" {
        sign = String(first)
        body = String(body.dropFirst())
      }
      var stripped = Substring(body)
      while stripped.count > 1, stripped.first == "0" {
        stripped = stripped.dropFirst()
      }
      return sign + String(stripped)
    }

    /// Removes trailing zeros from a fraction digit string, keeping at least one digit.
    private static func trimTrailingZeros(_ digits: String) -> String {
      var stripped = Substring(digits)
      while stripped.count > 1, stripped.last == "0" {
        stripped = stripped.dropLast()
      }
      return String(stripped)
    }

    // MARK: Descriptions

    /// A short, stable description of the first difference between two nodes.
    static func describeDifference(a: Syntax, b: Syntax) -> String {
      let summaryA = summary(of: a)
      let summaryB = summary(of: b)
      if a.kind == b.kind {
        return
          "\(String(describing: a.kind)) differs: \(summaryA) vs \(summaryB)"
      } else {
        return
          "expected \(String(describing: a.kind))\(summaryA.isEmpty ? "" : " (\(summaryA))") but found \(String(describing: b.kind))\(summaryB.isEmpty ? "" : " (\(summaryB))")"
      }
    }

    /// A one-line summary of a node's identifying content for mismatch messages.
    static func summary(of node: Syntax) -> String {
      if let token = node.as(TokenSyntax.self) {
        let text = token.text
        return text.isEmpty ? "\(token.tokenKind)" : "'\(text)'"
      }
      if let identifier = node.firstToken(viewMode: .sourceAccurate) {
        return "\(node.children(viewMode: .sourceAccurate).count) children, first token '\(identifier.text)'"
      }
      return "\(node.children(viewMode: .sourceAccurate).count) children"
    }

    /// The name used for a node in mismatch paths.
    static func nodeName(_ node: Syntax) -> String {
      String(describing: node.kind)
    }
  }
}
