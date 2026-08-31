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

final class CanonicalNumberLiteralsTests: LintOrFormatRuleTestCase {
  func testWrongGroupingIsRegrouped() {
    assertFormatting(
      CanonicalNumberLiterals.self,
      input: """
        let a = 1️⃣1_23_456
        let b = 2️⃣1000000
        """,
      expected: """
        let a = 123456
        let b = 1_000_000
        """,
      findings: [
        FindingSpec("1️⃣", message: "normalize this number literal"),
        FindingSpec("2️⃣", message: "normalize this number literal"),
      ]
    )
  }

  func testGroupingBelowThresholdIsRemoved() {
    assertFormatting(
      CanonicalNumberLiterals.self,
      input: """
        let a = 1️⃣1_234
        let b = 2️⃣0xF_F
        """,
      expected: """
        let a = 1234
        let b = 0xFF
        """,
      findings: [
        FindingSpec("1️⃣", message: "normalize this number literal"),
        FindingSpec("2️⃣", message: "normalize this number literal"),
      ]
    )
  }

  func testHexDigitsAreUppercasedAndGroupedEveryFour() {
    assertFormatting(
      CanonicalNumberLiterals.self,
      input: """
        let a = 1️⃣0xdeadbeef
        let b = 2️⃣0xAB_CDEF
        """,
      expected: """
        let a = 0xDEAD_BEEF
        let b = 0xABCDEF
        """,
      findings: [
        FindingSpec("1️⃣", message: "normalize this number literal"),
        FindingSpec("2️⃣", message: "normalize this number literal"),
      ]
    )
  }

  func testBinaryAndOctalGrouping() {
    assertFormatting(
      CanonicalNumberLiterals.self,
      input: """
        let a = 1️⃣0b1010_101010
        let b = 2️⃣0o7_777
        """,
      expected: """
        let a = 0b10_10101010
        let b = 0o7777
        """,
      findings: [
        FindingSpec("1️⃣", message: "normalize this number literal"),
        FindingSpec("2️⃣", message: "normalize this number literal"),
      ]
    )
  }

  func testFloatsGroupIntegerPartOnly() {
    assertFormatting(
      CanonicalNumberLiterals.self,
      input: """
        let a = 1️⃣1_000_000.000_1
        let b = 2️⃣1_0e3
        """,
      expected: """
        let a = 1_000_000.0001
        let b = 10e3
        """,
      findings: [
        FindingSpec("1️⃣", message: "normalize this number literal"),
        FindingSpec("2️⃣", message: "normalize this number literal"),
      ]
    )
  }

  func testNegativeLiteralsGroupAfterTheSign() {
    // A leading minus is a prefix operator, not part of the literal token, so grouping starts
    // at the literal's own digits.
    assertFormatting(
      CanonicalNumberLiterals.self,
      input: """
        let a = -1️⃣1234567
        let b = -0x34242
        """,
      expected: """
        let a = -1_234_567
        let b = -0x34242
        """,
      findings: [FindingSpec("1️⃣", message: "normalize this number literal")]
    )
  }

  func testInsignificantLeadingZerosAreRemoved() {
    assertFormatting(
      CanonicalNumberLiterals.self,
      input: """
        let a = 1️⃣007
        let b = 2️⃣0000000
        let c = 3️⃣0001234
        let d = 4️⃣001234567
        let e = 5️⃣0x00FF
        let f = 6️⃣0b0001
        let g = 7️⃣0o0777
        """,
      expected: """
        let a = 7
        let b = 0
        let c = 1234
        let d = 1_234_567
        let e = 0xFF
        let f = 0b1
        let g = 0o777
        """,
      findings: [
        FindingSpec("1️⃣", message: "normalize this number literal"),
        FindingSpec("2️⃣", message: "normalize this number literal"),
        FindingSpec("3️⃣", message: "normalize this number literal"),
        FindingSpec("4️⃣", message: "normalize this number literal"),
        FindingSpec("5️⃣", message: "normalize this number literal"),
        FindingSpec("6️⃣", message: "normalize this number literal"),
        FindingSpec("7️⃣", message: "normalize this number literal"),
      ]
    )
  }

  func testTrailingFractionZerosAreRemoved() {
    assertFormatting(
      CanonicalNumberLiterals.self,
      input: """
        let a = 1️⃣1.500
        let b = 2️⃣0x1.80p3
        let c = 3️⃣000.500
        let d = 1.0
        let e = 0.5
        """,
      expected: """
        let a = 1.5
        let b = 0x1.8p3
        let c = 0.5
        let d = 1.0
        let e = 0.5
        """,
      findings: [
        FindingSpec("1️⃣", message: "normalize this number literal"),
        FindingSpec("2️⃣", message: "normalize this number literal"),
        FindingSpec("3️⃣", message: "normalize this number literal"),
      ]
    )
  }

  func testExponentAndHexFractionSpellingIsNormalized() {
    assertFormatting(
      CanonicalNumberLiterals.self,
      input: """
        let a = 1️⃣1E3
        let b = 2️⃣0xa.bP2
        let c = 3️⃣1e05
        let d = 4️⃣1E-05
        """,
      expected: """
        let a = 1e3
        let b = 0xA.Bp2
        let c = 1e5
        let d = 1e-5
        """,
      findings: [
        FindingSpec("1️⃣", message: "normalize this number literal"),
        FindingSpec("2️⃣", message: "normalize this number literal"),
        FindingSpec("3️⃣", message: "normalize this number literal"),
        FindingSpec("4️⃣", message: "normalize this number literal"),
      ]
    )
  }

  func testZeroValuedLiteralsKeepIntegerOrFloatingForm() {
    // A zero with no fraction digits stays an integer literal and a zero with one stays floating
    // point, including IEEE negative zero, whose sign is carried by a prefix operator.
    assertFormatting(
      CanonicalNumberLiterals.self,
      input: """
        let a = 1️⃣000
        let b = 2️⃣0x000
        let c = 3️⃣0.000
        let d = -0.0
        let e = 0.0e0
        """,
      expected: """
        let a = 0
        let b = 0x0
        let c = 0.0
        let d = -0.0
        let e = 0.0e0
        """,
      findings: [
        FindingSpec("1️⃣", message: "normalize this number literal"),
        FindingSpec("2️⃣", message: "normalize this number literal"),
        FindingSpec("3️⃣", message: "normalize this number literal"),
      ]
    )
  }

  func testCanonicalLiteralsAreUntouched() {
    assertFormatting(
      CanonicalNumberLiterals.self,
      input: """
        let a = 123
        let b = 1_000_000
        let c = 0xFF
        let d = 0xDEAD_BEEF
        let e = 12.5
        let f = 10e3
        """,
      expected: """
        let a = 123
        let b = 1_000_000
        let c = 0xFF
        let d = 0xDEAD_BEEF
        let e = 12.5
        let f = 10e3
        """,
      findings: []
    )
  }
}
