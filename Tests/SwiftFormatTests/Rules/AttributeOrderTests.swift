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

final class AttributeOrderTests: LintOrFormatRuleTestCase {
  func testSortsAllowlistedAttributesIntoFixedOrder() {
    assertFormatting(
      AttributeOrder.self,
      input: """
        struct S {
          1️⃣@objc @available(iOS 1, deprecated: 2) func tapped() {}
          2️⃣@discardableResult @MainActor func produce() -> Int { 1 }
        }
        """,
      expected: """
        struct S {
          @available(iOS 1, deprecated: 2) @objc func tapped() {}
          @MainActor @discardableResult func produce() -> Int { 1 }
        }
        """,
      findings: [
        FindingSpec("1️⃣", message: "sort the declaration attributes into their fixed order"),
        FindingSpec("2️⃣", message: "sort the declaration attributes into their fixed order"),
      ]
    )
  }

  func testAlreadySortedListIsUntouched() {
    assertFormatting(
      AttributeOrder.self,
      input: """
        struct S {
          @available(*, deprecated: 1.0) @objc func tapped() {}
        }
        """,
      expected: """
        struct S {
          @available(*, deprecated: 1.0) @objc func tapped() {}
        }
        """,
      findings: []
    )
  }

  func testBarriersStopMovement() {
    assertFormatting(
      AttributeOrder.self,
      input: """
        struct S {
          @objc @Clamped @available(*, deprecated: 1.0) var value: Int = 0
          @objc
          #if canImport(UIKit)
          @MainActor
          #endif
          @discardableResult
          func mixed() -> Int { 1 }
        }
        """,
      expected: """
        struct S {
          @objc @Clamped @available(*, deprecated: 1.0) var value: Int = 0
          @objc
          #if canImport(UIKit)
          @MainActor
          #endif
          @discardableResult
          func mixed() -> Int { 1 }
        }
        """,
      findings: []
    )
  }

  func testRunsSortIndependentlyAroundBarriers() {
    assertFormatting(
      AttributeOrder.self,
      input: """
        struct S {
          @inlinable @Clamped 1️⃣@objc @available(*, deprecated: 1.0) var value: Int = 0
        }
        """,
      expected: """
        struct S {
          @inlinable @Clamped @available(*, deprecated: 1.0) @objc var value: Int = 0
        }
        """,
      findings: [
        FindingSpec("1️⃣", message: "sort the declaration attributes into their fixed order")
      ]
    )
  }

  func testMultilineAttributeListCollapsesInteriorTrivia() {
    assertFormatting(
      AttributeOrder.self,
      input: """
        struct S {
          1️⃣@objc
          @available(*, deprecated: 1.0)
          func tapped() {}
        }
        """,
      expected: """
        struct S {
          @available(*, deprecated: 1.0) @objc
          func tapped() {}
        }
        """,
      findings: [
        FindingSpec("1️⃣", message: "sort the declaration attributes into their fixed order")
      ]
    )
  }

  func testImportsAndParametersAreUntouched() {
    assertFormatting(
      AttributeOrder.self,
      input: """
        @testable import Framework

        func apply(_ operation: @escaping () -> Void) {
          operation()
        }
        """,
      expected: """
        @testable import Framework

        func apply(_ operation: @escaping () -> Void) {
          operation()
        }
        """,
      findings: []
    )
  }

  func testCommentInRunIsDiagnosedButPreserved() {
    assertFormatting(
      AttributeOrder.self,
      input: """
        struct S {
          1️⃣@objc /* keep */ @available(*, deprecated: 1.0) func tapped() {}
        }
        """,
      expected: """
        struct S {
          @objc /* keep */ @available(*, deprecated: 1.0) func tapped() {}
        }
        """,
      findings: [
        FindingSpec("1️⃣", message: "sort the declaration attributes into their fixed order")
      ]
    )
  }

  func testDocCommentAboveListDoesNotBlockSorting() {
    // The doc comment is leading trivia of the first attribute, which keeps the position's
    // trivia; it must not count as a comment "in the way" of the sort.
    assertFormatting(
      AttributeOrder.self,
      input: """
        /// Computes a value.
        /// - Parameters:
        ///   - input: the input
        1️⃣@objc @available(iOS, deprecated: 2) func compute(input: Int) -> Int { input }
        """,
      expected: """
        /// Computes a value.
        /// - Parameters:
        ///   - input: the input
        @available(iOS, deprecated: 2) @objc func compute(input: Int) -> Int { input }
        """,
      findings: [
        FindingSpec("1️⃣", message: "sort the declaration attributes into their fixed order")
      ]
    )
  }

  func testAlphabeticalWithinAGroup() {
    assertFormatting(
      AttributeOrder.self,
      input: """
        struct S {
          1️⃣@usableFromInline @inlinable func fast() {}
        }
        """,
      expected: """
        struct S {
          @inlinable @usableFromInline func fast() {}
        }
        """,
      findings: [
        FindingSpec("1️⃣", message: "sort the declaration attributes into their fixed order")
      ]
    )
  }
}
