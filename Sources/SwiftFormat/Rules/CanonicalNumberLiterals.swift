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

/// Normalizes the spelling of numeric literals.
///
/// Unlike `GroupNumericLiterals`, which only *adds* grouping to literals that do not already
/// contain underscores, this rule removes every degree of freedom in the literal's spelling that does not change its value: any
/// existing underscores are removed and the normalized grouping is recomputed — decimal every 3
/// digits at 7 or more, hexadecimal every 4 digits at 8 or more, binary every 8 digits at 10 or
/// more (the same thresholds as `GroupNumericLiterals`), and octal every 3 digits at 5 or more
/// (an extension: `GroupNumericLiterals` leaves octal alone) — hexadecimal digits are
/// uppercased, exponent markers are lowercased, insignificant leading zeros are removed down to a
/// single digit in the integer part and in the exponent, trailing fraction zeros are removed down
/// to a single digit so the literal stays floating-point, and fraction parts are left ungrouped.
///
/// Lint: A literal that differs from its normalized form yields a lint error.
///
/// Format: The literal is rewritten to its normalized form.
@_spi(Rules)
public final class CanonicalNumberLiterals: SyntaxFormatRule {
  public override class var isOptIn: Bool { return true }

  public override func visit(_ node: IntegerLiteralExprSyntax) -> ExprSyntax {
    let canonical = Self.canonicalInteger(node.literal.text)
    guard canonical != node.literal.text else {
      return super.visit(node)
    }
    diagnose(.canonicalizeNumberLiteral, on: node.literal)
    var result = node
    result.literal.tokenKind = .integerLiteral(canonical)
    return ExprSyntax(result)
  }

  public override func visit(_ node: FloatLiteralExprSyntax) -> ExprSyntax {
    let canonical = Self.canonicalFloat(node.literal.text)
    guard canonical != node.literal.text else {
      return super.visit(node)
    }
    diagnose(.canonicalizeNumberLiteral, on: node.literal)
    var result = node
    result.literal.tokenKind = .floatLiteral(canonical)
    return ExprSyntax(result)
  }

  /// Returns the normalized form of an integer literal's text, including any base prefix.
  private static func canonicalInteger(_ text: String) -> String {
    let (prefix, digits) = splitPrefix(text)
    let canonicalDigits = canonicalDigits(stripUnderscores(digits), base: base(of: prefix))
    return prefix + canonicalDigits
  }

  private static func stripUnderscores(_ text: String) -> String {
    String(text.filter { $0 != "_" })
  }

  /// Returns the normalized form of a floating-point literal's text, including any base prefix
  /// and exponent. Fraction digits are never grouped; the integer part follows the integer
  /// grouping thresholds; the exponent's marker is lowercased and its insignificant leading
  /// zeros are removed down to a single digit.
  private static func canonicalFloat(_ text: String) -> String {
    let (prefix, rest) = splitPrefix(text)
    // Exponents are identified by 'e' or 'p' (the latter only in hexadecimal floats).
    let exponentMarkers: Set<Character> = prefix == "0x" ? ["p", "P"] : ["e", "E"]
    var significand = stripUnderscores(rest)
    var exponent = ""
    if let marker = significand.firstIndex(where: { exponentMarkers.contains($0) }) {
      let markerText = significand[marker...].lowercased()
      significand = String(significand[..<marker])
      // Drop leading zeros after the marker and any sign; they do not change the value.
      var exponentDigits = markerText.dropFirst()
      let exponentSign = exponentDigits.prefix { $0 == "+" || $0 == "-" }
      exponentDigits = exponentDigits.dropFirst(exponentSign.count)
      while exponentDigits.count > 1, exponentDigits.hasPrefix("0") {
        exponentDigits = exponentDigits.dropFirst()
      }
      exponent = String(markerText.prefix(1)) + exponentSign + exponentDigits
    }

    var integerPart = significand
    var fractionPart = ""
    if let dot = significand.firstIndex(of: ".") {
      integerPart = String(significand[..<dot])
      fractionPart = String(significand[significand.index(after: dot)...])
    }

    var canonical = prefix
    canonical += canonicalDigits(integerPart, base: base(of: prefix))
    if !fractionPart.isEmpty {
      // Trailing fraction zeros do not change the literal's value; one fraction digit always
      // remains so the literal stays floating-point.
      while fractionPart.count > 1, fractionPart.hasSuffix("0") {
        fractionPart.removeLast()
      }
      canonical += "." + (prefix == "0x" ? fractionPart.uppercased() : fractionPart)
    }
    canonical += exponent
    return canonical
  }

  /// Returns the base prefix (if any) and the remaining digits of a literal's text.
  private static func splitPrefix(_ text: String) -> (prefix: String, digits: String) {
    if text.hasPrefix("0x") || text.hasPrefix("0o") || text.hasPrefix("0b") {
      return (String(text.prefix(2)), String(text.dropFirst(2)))
    }
    return ("", text)
  }

  private static func base(of prefix: String) -> Int {
    switch prefix {
    case "0x": return 16
    case "0o": return 8
    case "0b": return 2
    default: return 10
    }
  }

  /// Returns the normalized spelling of significand digits: uppercased in hexadecimal, stripped of
  /// insignificant leading zeros (one digit always remains), and grouped only when the digit
  /// count meets the threshold for the base.
  private static func canonicalDigits(_ digits: String, base: Int) -> String {
    var stripped = digits
    while stripped.count > 1, stripped.hasPrefix("0") {
      stripped.removeFirst()
    }
    let (stride, threshold): (Int, Int)
    switch base {
    case 16: (stride, threshold) = (4, 8)
    case 8: (stride, threshold) = (3, 5)
    case 2: (stride, threshold) = (8, 10)
    default: (stride, threshold) = (3, 7)
    }
    let normalized = base == 16 ? stripped.uppercased() : stripped
    guard normalized.count >= threshold else {
      return normalized
    }
    var grouped = ""
    let characters = Array(normalized)
    for (offset, character) in characters.enumerated() {
      if offset > 0 && (characters.count - offset) % stride == 0 {
        grouped += "_"
      }
      grouped.append(character)
    }
    return grouped
  }
}

extension Finding.Message {
  fileprivate static let canonicalizeNumberLiteral: Finding.Message =
    "normalize this number literal"
}
