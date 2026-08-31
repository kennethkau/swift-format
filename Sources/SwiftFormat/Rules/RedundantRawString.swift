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

/// Rewrites raw string literals to their minimal delimiters.
///
/// A raw string literal whose text contains no double quote and no backslash needs no escaping,
/// so its `#` delimiters are removed and the literal becomes an ordinary string; interpolation
/// delimiters lose their pound signs in tandem. A literal with more than one `#` has them
/// reduced to the smallest count that still keeps every double quote in the text from closing
/// the literal early or forming a malformed closing delimiter. Multiline literals are checked the same
/// way, which declines some reductions that would in fact be safe. Literals whose text contains a backslash, or that contain
/// parse errors, are never rewritten: pound signs also govern escapes and interpolation inside
/// raw strings, and damaged literals cannot be checked reliably. Rewriting continues into the
/// literal's interpolations, so literals nested there are rewritten in the same pass. The
/// literal's value is preserved exactly in every rewrite.
///
/// Lint: A raw string literal that does not use its minimal delimiters yields a lint error.
///
/// Format: The literal is rewritten with minimal delimiters.
@_spi(Rules)
public final class RedundantRawString: SyntaxFormatRule {
  public override class var isOptIn: Bool { return true }

  public override func visit(_ node: StringLiteralExprSyntax) -> ExprSyntax {
    // Unexpected nodes inside the literal are not part of any segment, so their text cannot be
    // checked for quotes and pound signs; leave damaged literals alone.
    guard !node.hasError, let openingPounds = node.openingPounds,
      let closingPounds = node.closingPounds
    else {
      return super.visit(node)
    }

    let text = node.segments.compactMap { segment -> String? in
      guard case .stringSegment(let stringSegment) = segment else { return nil }
      return stringSegment.content.text
    }.joined()

    if !text.contains("\"") && !text.contains("\\") {
      diagnose(.removeRawStringDelimiters, on: node)
      var result = node
      result.openingPounds = nil
      result.closingPounds = nil
      result.segments = Self.rewrittenSegments(node.segments, poundCount: 0)
      return super.visit(result)
    }

    let poundCount = openingPounds.text.count
    if !text.contains("\\"), let reducedCount = Self.minimalPoundCount(below: poundCount, for: text) {
      diagnose(.removeRedundantPoundSigns, on: node)
      var result = node
      result.openingPounds = TokenSyntax.rawStringPoundDelimiter(
        String(repeating: "#", count: reducedCount),
        leadingTrivia: openingPounds.leadingTrivia,
        trailingTrivia: openingPounds.trailingTrivia
      )
      result.closingPounds = TokenSyntax.rawStringPoundDelimiter(
        String(repeating: "#", count: reducedCount),
        leadingTrivia: closingPounds.leadingTrivia,
        trailingTrivia: closingPounds.trailingTrivia
      )
      result.segments = Self.rewrittenSegments(node.segments, poundCount: reducedCount)
      return super.visit(result)
    }

    return super.visit(node)
  }

  /// Returns the segments with their interpolation delimiters rewritten for a literal that uses
  /// `poundCount` pound signs; zero removes the delimiters' pound signs entirely.
  private static func rewrittenSegments(
    _ segments: StringLiteralSegmentListSyntax,
    poundCount: Int
  ) -> StringLiteralSegmentListSyntax {
    let elements = segments.map { segment -> StringLiteralSegmentListSyntax.Element in
      guard case .expressionSegment(var interpolation) = segment else { return segment }
      if poundCount == 0 {
        interpolation.pounds = nil
      } else if let pounds = interpolation.pounds {
        interpolation.pounds = TokenSyntax.rawStringPoundDelimiter(
          String(repeating: "#", count: poundCount),
          leadingTrivia: pounds.leadingTrivia,
          trailingTrivia: pounds.trailingTrivia
        )
      }
      return .expressionSegment(interpolation)
    }
    return StringLiteralSegmentListSyntax(elements)
  }

  /// Returns the smallest raw-string pound count below `poundCount` that delimits `text` without
  /// any of its double quotes terminating the literal early, or nil if there is none.
  private static func minimalPoundCount(below poundCount: Int, for text: String) -> Int? {
    (1..<poundCount).first { !wouldCloseEarly(text, poundCount: $0) }
  }

  /// Returns whether a double quote in `text` followed by at least `poundCount` pound signs
  /// would break a single-line literal delimited with that many pound signs: exactly that many
  /// closes the literal early, and more are rejected as a malformed closing delimiter outright.
  /// That is the only way text without backslashes can change meaning when the pound count
  /// shrinks. Multiline literals close on three quotes, so treating every quote this way only
  /// declines some of their reductions; it cannot enable an unsafe one.
  private static func wouldCloseEarly(_ text: String, poundCount: Int) -> Bool {
    var index = text.startIndex
    while let quoteIndex = text[index...].firstIndex(of: "\"") {
      var next = text.index(after: quoteIndex)
      var pounds = 0
      while next < text.endIndex, text[next] == "#" {
        pounds += 1
        next = text.index(after: next)
      }
      if pounds >= poundCount {
        return true
      }
      index = next
    }
    return false
  }
}

extension Finding.Message {
  fileprivate static let removeRawStringDelimiters: Finding.Message =
    "remove the raw string delimiters; the literal needs no escaping"

  fileprivate static let removeRedundantPoundSigns: Finding.Message =
    "remove the redundant '#' signs from the raw string delimiters"
}
