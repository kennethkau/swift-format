//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import SwiftSyntax

/// Rewrites escape sequences in non-raw string literals to their minimal form.
///
/// The minimal form uses the shortest escape that denotes its scalar: `\'` is never
/// needed and becomes a plain `'`, a `\u{...}` escape whose scalar has a shorter name (`\n`,
/// `\t`, `\r`, `\0`, `\"`, `\\`) or is a printable ASCII character needing no escape at all is
/// rewritten to that form, and every remaining `\u{...}` escape keeps its value but loses
/// leading zeros and uppercase hex digits. A double quote always stays escaped as `\"` — the
/// shortest *escape* — including in multiline literals, where a bare quote would also be legal.
/// The literal's value is preserved exactly in every rewrite.
///
/// Raw string literals are left to `RedundantRawString`: their escapes use `\#`, which changes
/// meaning with the delimiter's pound count. Literals containing parse errors are left alone,
/// and any other sequence — the fixed escapes, or text that does not follow the
/// `\u{hex-digits}` shape — is passed through verbatim.
///
/// Lint: A string literal that contains an escape sequence not in minimal form yields a lint
///       error.
///
/// Format: The escape sequences are rewritten to their minimal form.
@_spi(Rules)
public final class CanonicalStringEscapes: SyntaxFormatRule {
  public override class var isOptIn: Bool { return true }

  public override func visit(_ node: StringLiteralExprSyntax) -> ExprSyntax {
    guard !node.hasError, node.openingPounds == nil else {
      return super.visit(node)
    }

    var changed = false
    let elements = node.segments.map { segment -> StringLiteralSegmentListSyntax.Element in
      guard case .stringSegment(var stringSegment) = segment else { return segment }
      let text = stringSegment.content.text
      let rewritten = Self.minimalEscapes(in: text)
      if rewritten != text {
        changed = true
        stringSegment.content = TokenSyntax.stringSegment(
          rewritten,
          leadingTrivia: stringSegment.content.leadingTrivia,
          trailingTrivia: stringSegment.content.trailingTrivia
        )
      }
      return .stringSegment(stringSegment)
    }
    guard changed else { return super.visit(node) }
    diagnose(.canonicalizeStringEscapes, on: node)
    var result = node
    result.segments = StringLiteralSegmentListSyntax(elements)
    return super.visit(result)
  }

  /// Returns `text` with every escape sequence that is not already minimal rewritten to its
  /// minimal form. Sequences that cannot be recognized as one of Swift's escapes — including
  /// malformed `\u{...}` forms — are passed through unchanged.
  private static func minimalEscapes(in text: String) -> String {
    var result = String()
    var scalars = text.unicodeScalars.makeIterator()
    while let scalar = scalars.next() {
      guard scalar == "\\", let escaped = scalars.next() else {
        result.unicodeScalars.append(scalar)
        continue
      }
      switch escaped {
      case "'":
        result.unicodeScalars.append("'")
      case "u":
        result += Self.minimalUnicodeEscape(consuming: &scalars)
      default:
        // One of the fixed escapes (\n, \t, \r, \0, \", \\) or not an escape at all; both keep
        // their text.
        result.unicodeScalars.append(scalar)
        result.unicodeScalars.append(escaped)
      }
    }
    return result
  }

  /// Consumes the `{hex-digits}` body of a `\u` escape from `scalars` and returns the minimal
  /// spelling of the escape, or the consumed text verbatim when it is not the escape shape (in
  /// which case the remaining scalars are left for ordinary copying). Every failure path must
  /// re-emit each scalar it consumed: dropping one would corrupt the literal's text.
  private static func minimalUnicodeEscape(
    consuming scalars: inout String.UnicodeScalarView.Iterator
  ) -> String {
    guard let brace = scalars.next() else { return "\\u" }
    guard brace == "{" else { return "\\u" + String(Character(brace)) }
    var hex = ""
    while let next = scalars.next() {
      if next == "}" {
        if let value = UInt32(hex, radix: 16), let minimal = minimalForm(of: value) {
          return minimal
        }
        // The escape shape with empty or out-of-range hex: pass through verbatim.
        return "\\u{" + hex + "}"
      }
      guard "0123456789abcdefABCDEF".unicodeScalars.contains(next), hex.count < 8 else {
        // Not the `\u{hex-digits}` shape: pass through verbatim, including the scalar that
        // failed the guard.
        return "\\u{" + hex + String(Character(next))
      }
      hex.unicodeScalars.append(next)
    }
    // The text ended inside the escape: pass through what was consumed.
    return "\\u{" + hex
  }

  /// Returns the minimal spelling that denotes `value` inside a non-raw string literal, or nil
  /// if `value` is not a valid Unicode scalar.
  private static func minimalForm(of value: UInt32) -> String? {
    switch value {
    case 0x00: return "\\0"
    case 0x09: return "\\t"
    case 0x0A: return "\\n"
    case 0x0D: return "\\r"
    case 0x22: return "\\\""
    case 0x5C: return "\\\\"
    default: break
    }
    guard let scalar = Unicode.Scalar(value) else { return nil }
    if (0x20...0x7E).contains(value) {
      return String(Character(scalar))
    }
    // Nothing shorter than the escape exists; normalize its hex to lowercase without
    // padding.
    return "\\u{\(String(value, radix: 16))}"
  }
}

extension Finding.Message {
  fileprivate static let canonicalizeStringEscapes: Finding.Message =
    "rewrite the escape sequences in this string literal to their minimal form"
}
