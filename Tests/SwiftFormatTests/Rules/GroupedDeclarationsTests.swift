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

final class GroupedDeclarationsTests: LintOrFormatRuleTestCase {
  func testContiguousGroupsProduceNoFindings() {
    assertLint(
      GroupedDeclarations.self,
      """
      struct Sample {
        let first: Int
        let second: Int

        init(first: Int, second: Int) {
          self.first = first
          self.second = second
        }

        func one() {}
        func two() {}

        struct Nested {}
      }
      """
    )
  }

  func testInterleavedGroupsAreFlagged() {
    assertLint(
      GroupedDeclarations.self,
      """
      struct Sample {
        let first: Int
        func one() {}
        1️⃣let second: Int

        2️⃣func two() {}
        struct Nested {}
        3️⃣func three() {}
      }
      """,
      findings: [
        FindingSpec("1️⃣", message: "group this property declaration with the other property declarations"),
        FindingSpec("2️⃣", message: "group this method declaration with the other method declarations"),
        FindingSpec("3️⃣", message: "group this method declaration with the other method declarations"),
      ]
    )
  }

  func testNeutralMembersDoNotBreakARun() {
    assertLint(
      GroupedDeclarations.self,
      """
      struct Sample {
        let first: Int
        #if os(Linux)
        let second: Int
        #endif
        func one() {}
      }
      """
    )
  }

  func testEnumCasesFormAGroup() {
    assertLint(
      GroupedDeclarations.self,
      """
      enum Value {
        case first
        var description: String { "" }
        1️⃣case second
      }
      """,
      findings: [
        FindingSpec("1️⃣", message: "group this enum case declaration with the other enum case declarations")
      ]
    )
  }

  func testProtocolBodiesAreChecked() {
    assertLint(
      GroupedDeclarations.self,
      """
      protocol Value {
        var first: Int { get }
        func one()
        1️⃣var second: Int { get }
      }
      """,
      findings: [
        FindingSpec("1️⃣", message: "group this property declaration with the other property declarations")
      ]
    )
  }

  func testExtensionAndNestedBodiesAreChecked() {
    assertLint(
      GroupedDeclarations.self,
      """
      extension Value {
        func one() {}
        var flag = false
        1️⃣func two() {}

        struct Inner {
          func inner() {}
          var count = 0
          2️⃣func reset() {}
        }
      }
      """,
      findings: [
        FindingSpec("1️⃣", message: "group this method declaration with the other method declarations"),
        FindingSpec("2️⃣", message: "group this method declaration with the other method declarations"),
      ]
    )
  }
}
