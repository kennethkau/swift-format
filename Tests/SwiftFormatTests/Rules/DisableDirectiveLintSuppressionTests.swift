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
import SwiftSyntax
import _SwiftFormatTestSupport

/// Tests that disable directives suppress a rule's findings end-to-end through the lint
/// pipeline's rule mask.
final class DisableDirectiveLintSuppressionTests: LintOrFormatRuleTestCase {
  func testFindingsSuppressedInsideAllRulesBlock() {
    assertLint(
      AlwaysUseLowerCamelCase.self,
      """
      // swift-format-disable
      let bad_name = 1
      let also_bad = 2
      // swift-format-enable
      let 1️⃣still_bad = 3
      """,
      findings: [
        FindingSpec("1️⃣", message: "rename the constant 'still_bad' using lowerCamelCase")
      ]
    )
  }

  func testFindingsSuppressedByLineScope() {
    assertLint(
      AlwaysUseLowerCamelCase.self,
      """
      // swift-format-disable:next
      let bad_name = 1
      let 1️⃣still_bad = 2
      """,
      findings: [
        FindingSpec("1️⃣", message: "rename the constant 'still_bad' using lowerCamelCase")
      ]
    )
  }

  func testFindingsNotSuppressedForOtherRuleNames() {
    assertLint(
      AlwaysUseLowerCamelCase.self,
      """
      // swift-format-disable: SomeOtherRule
      let 1️⃣bad_name = 1
      // swift-format-enable
      let 2️⃣still_bad = 2
      """,
      findings: [
        FindingSpec("1️⃣", message: "rename the constant 'bad_name' using lowerCamelCase"),
        FindingSpec("2️⃣", message: "rename the constant 'still_bad' using lowerCamelCase"),
      ]
    )
  }

  func testFindingsSuppressedInsideNestedScope() {
    assertLint(
      AlwaysUseLowerCamelCase.self,
      """
      struct Foo {
        // swift-format-disable
        func bad_name() {}
        // swift-format-enable
        func 1️⃣also_bad() {}
      }
      """,
      findings: [
        FindingSpec("1️⃣", message: "rename the function 'also_bad' using lowerCamelCase")
      ]
    )
  }

  func testThisScopeSuppressesFindingsAsTrailingComment() {
    assertLint(
      AlwaysUseLowerCamelCase.self,
      """
      let bad_name = 1  // swift-format-disable:this
      let 1️⃣also_bad = 2
      """,
      findings: [
        FindingSpec("1️⃣", message: "rename the constant 'also_bad' using lowerCamelCase")
      ]
    )
  }

  func testPreviousScopeSuppressesFindingsOnPriorLine() {
    assertLint(
      AlwaysUseLowerCamelCase.self,
      """
      let bad_name = 1
      let 1️⃣ok_name = 2  // swift-format-disable:previous
      """,
      findings: [
        FindingSpec("1️⃣", message: "rename the constant 'ok_name' using lowerCamelCase")
      ]
    )
  }

  func testUnterminatedBlockSuppressesFindingsToEOF() {
    assertLint(
      AlwaysUseLowerCamelCase.self,
      """
      // swift-format-disable
      let bad_name = 1
      let also_bad = 2
      """,
      findings: []
    )
  }
}
