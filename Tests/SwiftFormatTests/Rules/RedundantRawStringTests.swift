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

@_spi(Rules) import SwiftFormat
import _SwiftFormatTestSupport

final class RedundantRawStringTests: LintOrFormatRuleTestCase {
  func testDelimitersWithoutEscapingAreRemoved() {
    assertFormatting(
      RedundantRawString.self,
      input: """
        let a = 1️⃣#"no escapes here"#
        let b = 2️⃣#""#
        let c = "already plain"
        """,
      expected: """
        let a = "no escapes here"
        let b = ""
        let c = "already plain"
        """,
      findings: [
        FindingSpec("1️⃣", message: "remove the raw string delimiters; the literal needs no escaping"),
        FindingSpec("2️⃣", message: "remove the raw string delimiters; the literal needs no escaping"),
      ]
    )
  }

  func testInterpolationPoundSignsAreRemovedInTandem() {
    assertFormatting(
      RedundantRawString.self,
      input: """
        let d = 1️⃣#"interp \\#(1 + 2) and \\#(3) tail"#
        """,
      expected: """
        let d = "interp \\(1 + 2) and \\(3) tail"
        """,
      findings: [
        FindingSpec("1️⃣", message: "remove the raw string delimiters; the literal needs no escaping")
      ]
    )
  }

  func testPoundSignsAreReducedToTheMinimum() {
    assertFormatting(
      RedundantRawString.self,
      input: """
        let b = 1️⃣##"has "quotes" inside"##
        let e = 2️⃣###"x"#y"###
        let t = 3️⃣##"trailing quote""##
        """,
      expected: """
        let b = #"has "quotes" inside"#
        let e = ##"x"#y"##
        let t = #"trailing quote""#
        """,
      findings: [
        FindingSpec("1️⃣", message: "remove the redundant '#' signs from the raw string delimiters"),
        FindingSpec("2️⃣", message: "remove the redundant '#' signs from the raw string delimiters"),
        FindingSpec("3️⃣", message: "remove the redundant '#' signs from the raw string delimiters"),
      ]
    )
  }

  func testInterpolationPoundSignsAreRemovedWhenDelimitersAreRemoved() {
    // The literal's own text contains no quotes or backslashes, so the delimiters are removed
    // entirely and the interpolation delimiters lose their pound signs in tandem.
    assertFormatting(
      RedundantRawString.self,
      input: """
        let a = 1️⃣##"x \\##(b) y"##
        """,
      expected: """
        let a = "x \\(b) y"
        """,
      findings: [
        FindingSpec("1️⃣", message: "remove the raw string delimiters; the literal needs no escaping")
      ]
    )
  }

  func testLiteralsNestedInInterpolationsAreRewritten() {
    // Both the outer literal and the literal nested inside its interpolation become plain; the
    // nested one is only reached because the rewrite continues into the rewritten node's
    // children. The nested
    // literal's finding is emitted against the already-rewritten outer literal, so its reported
    // position sits a few columns left of where the nested literal began in the input.
    assertFormatting(
      RedundantRawString.self,
      input: """
        let a = 1️⃣##"x \\##(in2️⃣ner(#"nested"#)) y"##
        """,
      expected: """
        let a = "x \\(inner("nested")) y"
        """,
      findings: [
        FindingSpec("1️⃣", message: "remove the raw string delimiters; the literal needs no escaping"),
        FindingSpec("2️⃣", message: "remove the raw string delimiters; the literal needs no escaping"),
      ]
    )
  }

  func testPoundOnlyTextBecomesPlain() {
    assertFormatting(
      RedundantRawString.self,
      input: """
        let b = 1️⃣#"only pounds: #"#
        """,
      expected: """
        let b = "only pounds: #"
        """,
      findings: [
        FindingSpec("1️⃣", message: "remove the raw string delimiters; the literal needs no escaping")
      ]
    )
  }

  func testLongerPoundRunsKeepTheirPoundSigns() {
    // Reducing either literal would leave a double quote followed by more pound signs than the
    // reduced delimiter count, which the lexer rejects as a malformed closing delimiter.
    assertFormatting(
      RedundantRawString.self,
      input: """
        let x = ###"a""##b"###
        let y = ###"ab"##"###
        """,
      expected: """
        let x = ###"a""##b"###
        let y = ###"ab"##"###
        """
    )
  }

  func testLiteralsContainingParseErrorsAreUntouched() {
    assertFormatting(
      RedundantRawString.self,
      input: """
        let a = #"x \\#(1 +) y"#
        """,
      expected: """
        let a = #"x \\#(1 +) y"#
        """
    )
  }

  func testTrailingQuoteFollowedByPoundKeepsBothDelimiters() {
    // A trailing quote followed by one pound stays behind two delimiters: reducing to one pound
    // would put that quote directly before the closing delimiter's pound and close the literal
    // early.
    assertFormatting(
      RedundantRawString.self,
      input: """
        let c = ##"end pound: a b"#"##
        """,
      expected: """
        let c = ##"end pound: a b"#"##
        """
    )
  }

  func testQuotesThatWouldCloseEarlyKeepTheirPoundSigns() {
    assertFormatting(
      RedundantRawString.self,
      input: """
        let a = #"has "quotes" inside"#
        let b = ###"one pound: "#a two pounds: "##b y"###
        """,
      expected: """
        let a = #"has "quotes" inside"#
        let b = ###"one pound: "#a two pounds: "##b y"###
        """
    )
  }

  func testBackslashesKeepTheirDelimiters() {
    assertFormatting(
      RedundantRawString.self,
      input: """
        let a = #"back\\slash stays"#
        let b = ##"back\\slash stays"##
        let c = ##"escaped quote: \\"hi\\""##
        """,
      expected: """
        let a = #"back\\slash stays"#
        let b = ##"back\\slash stays"##
        let c = ##"escaped quote: \\"hi\\""##
        """
    )
  }

  func testMultilineLiteralsAreRewritten() {
    assertFormatting(
      RedundantRawString.self,
      input: """
        func f() {
          let m = 1️⃣#\"\"\"
          plain multiline text
          \"\"\"#
          let n = ##\"\"\"
          has "quotes" and "#pounds
          \"\"\"##
        }
        """,
      expected: """
        func f() {
          let m = \"\"\"
          plain multiline text
          \"\"\"
          let n = ##\"\"\"
          has "quotes" and "#pounds
          \"\"\"##
        }
        """,
      findings: [
        FindingSpec("1️⃣", message: "remove the raw string delimiters; the literal needs no escaping")
      ]
    )
  }
}
