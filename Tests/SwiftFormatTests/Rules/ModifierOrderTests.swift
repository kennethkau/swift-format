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

final class ModifierOrderTests: LintOrFormatRuleTestCase {
  func testAccessLevelSortsBeforeStatic() {
    assertFormatting(
      ModifierOrder.self,
      input: """
        static 1️⃣public var x = 1
        """,
      expected: """
        public static var x = 1
        """,
      findings: [FindingSpec("1️⃣", message: "sort the declaration modifiers into their fixed order")]
    )
  }

  func testFullFixedOrder() {
    assertFormatting(
      ModifierOrder.self,
      input: """
        final 1️⃣public class C {
          override 2️⃣public final func f() {}
          mutating 3️⃣internal func g(x: Int) -> Int { x }
          lazy 4️⃣private weak var d: AnyObject?
        }
        """,
      expected: """
        public final class C {
          public final override func f() {}
          internal mutating func g(x: Int) -> Int { x }
          private lazy weak var d: AnyObject?
        }
        """,
      findings: [
        FindingSpec("1️⃣", message: "sort the declaration modifiers into their fixed order"),
        FindingSpec("2️⃣", message: "sort the declaration modifiers into their fixed order"),
        FindingSpec("3️⃣", message: "sort the declaration modifiers into their fixed order"),
        FindingSpec("4️⃣", message: "sort the declaration modifiers into their fixed order"),
      ]
    )
  }

  func testSetterScopeModifierSortsAfterArgumentlessAccess() {
    assertFormatting(
      ModifierOrder.self,
      input: """
        private(set) 1️⃣public var x = 1
        """,
      expected: """
        public private(set) var x = 1
        """,
      findings: [FindingSpec("1️⃣", message: "sort the declaration modifiers into their fixed order")]
    )
  }

  func testAlreadyOrderedModifierListIsUntouched() {
    assertFormatting(
      ModifierOrder.self,
      input: """
        public final class C {
          public private(set) var x = 1
          static let y = 2
          private lazy var z = 3
        }
        """,
      expected: """
        public final class C {
          public private(set) var x = 1
          static let y = 2
          private lazy var z = 3
        }
        """,
      findings: []
    )
  }

  func testModifiersCarryingCommentsAreDiagnosedButNotReordered() {
    // Reordering would strand the comment between unrelated modifiers; the finding stands as
    // lint-only.
    assertFormatting(
      ModifierOrder.self,
      input: """
        final /* mid */ 1️⃣public class A {}
        static
        // orphan note
        2️⃣public var x = 1
        """,
      expected: """
        final /* mid */ public class A {}
        static
        // orphan note
        public var x = 1
        """,
      findings: [
        FindingSpec("1️⃣", message: "sort the declaration modifiers into their fixed order"),
        FindingSpec("2️⃣", message: "sort the declaration modifiers into their fixed order"),
      ]
    )
  }

  func testUnrankedModifiersKeepRelativeOrderAfterRankedOnes() {
    // `prefix` is a real modifier that the fixed order does not rank; it must sort after the
    // ranked ones while keeping its position relative to other unranked modifiers.
    assertFormatting(
      ModifierOrder.self,
      input: """
        static prefix 1️⃣public func -(x: Int) -> Int { x }
        """,
      expected: """
        public static prefix func -(x: Int) -> Int { x }
        """,
      findings: [FindingSpec("1️⃣", message: "sort the declaration modifiers into their fixed order")]
    )
  }
}
