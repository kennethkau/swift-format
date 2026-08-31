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

@_spi(Rules) import SwiftFormat
import _SwiftFormatTestSupport

final class CanonicalStringEscapesTests: LintOrFormatRuleTestCase {
  func testUnnecessarySingleQuoteEscapeIsRemoved() {
    assertFormatting(
      CanonicalStringEscapes.self,
      input: """
        let a = 1️⃣"it\\'s here"
        """,
      expected: """
        let a = "it's here"
        """,
      findings: [
        FindingSpec("1️⃣", message: "rewrite the escape sequences in this string literal to their minimal form")
      ]
    )
  }

  func testUnicodeEscapesAreShortened() {
    assertFormatting(
      CanonicalStringEscapes.self,
      input: """
        let named = 1️⃣"a\\u{0A}b\\u{09}c\\u{00}d\\u{22}e\\u{5C}f"
        let printable = 2️⃣"\\u{48}ello \\u{7E}"
        """,
      expected: """
        let named = "a\\nb\\tc\\0d\\"e\\\\f"
        let printable = "Hello ~"
        """,
      findings: [
        FindingSpec("1️⃣", message: "rewrite the escape sequences in this string literal to their minimal form"),
        FindingSpec("2️⃣", message: "rewrite the escape sequences in this string literal to their minimal form"),
      ]
    )
  }

  func testUnicodeEscapeHexIsLowercasedAndUnpadded() {
    assertFormatting(
      CanonicalStringEscapes.self,
      input: """
        let emoji = 1️⃣"\\u{0001F600} and \\u{1F600}"
        """,
      expected: """
        let emoji = "\\u{1f600} and \\u{1f600}"
        """,
      findings: [
        FindingSpec("1️⃣", message: "rewrite the escape sequences in this string literal to their minimal form")
      ]
    )
  }

  func testAlreadyMinimalLiteralsAreUntouched() {
    assertFormatting(
      CanonicalStringEscapes.self,
      input: """
        let ok = "already minimal \\n \\t \\0 \\" \\\\ \\u{1f600}"
        let plain = "no escapes at all"
        """,
      expected: """
        let ok = "already minimal \\n \\t \\0 \\" \\\\ \\u{1f600}"
        let plain = "no escapes at all"
        """,
    )
  }

  func testRawLiteralsAndLiteralsWithParseErrorsAreSkipped() {
    assertFormatting(
      CanonicalStringEscapes.self,
      input: """
        let raw = #"raw \\#u{41} stays"#
        let broken = "\\u{zz} not hex and \\u{} empty stay"
        """,
      expected: """
        let raw = #"raw \\#u{41} stays"#
        let broken = "\\u{zz} not hex and \\u{} empty stay"
        """,
    )
  }

  func testMultilineLiteralsAreRewritten() {
    assertFormatting(
      CanonicalStringEscapes.self,
      input: """
        let text = 1️⃣\"\"\"
          line\\u{0A}break and \\u{41}
          \"\"\"
        """,
      expected: """
        let text = \"\"\"
          line\\nbreak and A
          \"\"\"
        """,
      findings: [
        FindingSpec("1️⃣", message: "rewrite the escape sequences in this string literal to their minimal form")
      ]
    )
  }

  func testQuoteAndBackslashEscapesStayEscaped() {
    // A literal consisting solely of the escaped quote or backslash, and the same escapes
    // inside a multiline literal: both must stay escaped (a bare quote would change the
    // literal's delimiters even where a multiline literal would allow it).
    assertFormatting(
      CanonicalStringEscapes.self,
      input: """
        let quote = 1️⃣"\\u{22}"
        let backslash = 2️⃣"\\u{5C}"
        let multi = 3️⃣\"\"\"
          quote \\u{22} and backslash \\u{5C} stay escaped
          \"\"\"
        """,
      expected: """
        let quote = "\\""
        let backslash = "\\\\"
        let multi = \"\"\"
          quote \\" and backslash \\\\ stay escaped
          \"\"\"
        """,
      findings: [
        FindingSpec("1️⃣", message: "rewrite the escape sequences in this string literal to their minimal form"),
        FindingSpec("2️⃣", message: "rewrite the escape sequences in this string literal to their minimal form"),
        FindingSpec("3️⃣", message: "rewrite the escape sequences in this string literal to their minimal form"),
      ]
    )
  }

  func testLiteralsNestedInInterpolationsAreRewritten() {
    // Both the outer literal and the literal nested inside its interpolation are rewritten; the
    // nested one is only reached because the rewrite continues into the rewritten node's
    // children. As with RedundantRawString, the nested literal's finding is emitted against the
    // already-rewritten outer literal, so its reported position sits left of where the nested
    // literal began in the input — the marker sits at that rewritten position.
    assertFormatting(
      CanonicalStringEscapes.self,
      input: """
        let message = 1️⃣"outer \\u{2️⃣41}\\("inner \\u{42}") tail"
        """,
      expected: """
        let message = "outer A\\("inner B") tail"
        """,
      findings: [
        FindingSpec("1️⃣", message: "rewrite the escape sequences in this string literal to their minimal form"),
        FindingSpec("2️⃣", message: "rewrite the escape sequences in this string literal to their minimal form"),
      ]
    )
  }
}
