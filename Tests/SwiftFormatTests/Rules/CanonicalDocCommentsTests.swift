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

final class CanonicalDocCommentsTests: LintOrFormatRuleTestCase {
  func testAddsMissingSpaceAfterSlashes() {
    assertFormatting(
      CanonicalDocComments.self,
      input: """
        ///Glued to the slashes.
        1️⃣struct S {}
        """,
      expected: """
        /// Glued to the slashes.
        struct S {}
        """,
      findings: [
        FindingSpec("1️⃣", message: "normalize this doc comment's layout")
      ]
    )
  }

  func testCollapsesMultipleBlankDocLines() {
    assertFormatting(
      CanonicalDocComments.self,
      input: """
        /// First line.
        ///
        ///
        ///
        /// Last line.
        1️⃣struct S {}
        """,
      expected: """
        /// First line.
        ///
        /// Last line.
        struct S {}
        """,
      findings: [
        FindingSpec("1️⃣", message: "normalize this doc comment's layout")
      ]
    )
  }

  func testRemovesTrailingBlankDocLines() {
    assertFormatting(
      CanonicalDocComments.self,
      input: """
        /// Only line.
        ///
        1️⃣struct S {}
        """,
      expected: """
        /// Only line.
        struct S {}
        """,
      findings: [
        FindingSpec("1️⃣", message: "normalize this doc comment's layout")
      ]
    )
  }

  func testStripsTrailingWhitespaceOnDocLines() {
    assertFormatting(
      CanonicalDocComments.self,
      input: "/// Text with trailing spaces.   \n1️⃣struct S {}\n",
      expected: "/// Text with trailing spaces.\nstruct S {}\n",
      findings: [
        FindingSpec("1️⃣", message: "normalize this doc comment's layout")
      ]
    )
  }

  func testAlignsParameterListItems() {
    assertFormatting(
      CanonicalDocComments.self,
      input: """
        /// Computes a value.
        /// - Parameters:
        ///  - input: the input value
        ///   - scale: how much to scale
        /// - Returns: the scaled value
        1️⃣func compute(input: Int, scale: Int) -> Int { input * scale }
        """,
      expected: """
        /// Computes a value.
        /// - Parameters:
        ///   - input: the input value
        ///   - scale: how much to scale
        /// - Returns: the scaled value
        func compute(input: Int, scale: Int) -> Int { input * scale }
        """,
      findings: [
        FindingSpec("1️⃣", message: "normalize this doc comment's layout")
      ]
    )
  }

  func testAlreadyCanonicalDocCommentIsUntouched() {
    assertFormatting(
      CanonicalDocComments.self,
      input: """
        /// Computes a value.
        ///
        /// Blank lines are content.
        /// - Parameters:
        ///   - input: the input value
        /// - Returns: the scaled value
        func compute(input: Int) -> Int { input }
        """,
      expected: """
        /// Computes a value.
        ///
        /// Blank lines are content.
        /// - Parameters:
        ///   - input: the input value
        /// - Returns: the scaled value
        func compute(input: Int) -> Int { input }
        """,
      findings: []
    )
  }

  func testPreservesIndentedContinuationLinesAndCodeBlocks() {
    assertFormatting(
      CanonicalDocComments.self,
      input: """
        /// Example:
        ///
        ///
        ///     let value = compute()
        ///
        ///
        /// Done.
        1️⃣struct S {}
        """,
      expected: """
        /// Example:
        ///
        ///     let value = compute()
        ///
        ///
        /// Done.
        struct S {}
        """,
      findings: [
        FindingSpec("1️⃣", message: "normalize this doc comment's layout")
      ]
    )
  }

  func testIndentedCodeBlockDashesAndBlanksAreContent() {
    assertFormatting(
      CanonicalDocComments.self,
      input: """
        /// Example:
        ///
        ///
        ///     - first item
        ///     - second item
        ///
        ///
        ///     let more = code()
        /// Done.
        1️⃣struct S {}
        """,
      expected: """
        /// Example:
        ///
        ///     - first item
        ///     - second item
        ///
        ///
        ///     let more = code()
        /// Done.
        struct S {}
        """,
      findings: [
        FindingSpec("1️⃣", message: "normalize this doc comment's layout")
      ]
    )
  }

  func testNestedScopeDocCommentsStayIndented() {
    assertFormatting(
      CanonicalDocComments.self,
      input: """
        struct S {
          ///Glued and multi-blank.
          ///
          ///
          /// More.
          1️⃣func f() {}
        }
        """,
      expected: """
        struct S {
          /// Glued and multi-blank.
          ///
          /// More.
          func f() {}
        }
        """,
      findings: [
        FindingSpec("1️⃣", message: "normalize this doc comment's layout")
      ]
    )
  }

  func testSingularParameterFieldStaysTopLevel() {
    assertFormatting(
      CanonicalDocComments.self,
      input: """
        /// Applies an operation.
        ///   - Parameter operation: the closure to run
        1️⃣func apply(_ operation: () -> Void) {
          operation()
        }
        """,
      expected: """
        /// Applies an operation.
        /// - Parameter operation: the closure to run
        func apply(_ operation: () -> Void) {
          operation()
        }
        """,
      findings: [
        FindingSpec("1️⃣", message: "normalize this doc comment's layout")
      ]
    )
  }

  func testRemainingDocCFieldNamesStayTopLevel() {
    assertFormatting(
      CanonicalDocComments.self,
      input: """
        /// A documented value.
        ///   - Date: today
        ///   - Invariant: always positive
        ///   - Metadata: extra
        1️⃣struct S {}
        """,
      expected: """
        /// A documented value.
        /// - Date: today
        /// - Invariant: always positive
        /// - Metadata: extra
        struct S {}
        """,
      findings: [
        FindingSpec("1️⃣", message: "normalize this doc comment's layout")
      ]
    )
  }

  func testBlockDocCommentsAndLineCommentsAreUntouched() {
    assertFormatting(
      CanonicalDocComments.self,
      input: """
        /** A block doc comment. */
        struct A {}

        // A plain line comment.
        struct B {}
        """,
      expected: """
        /** A block doc comment. */
        struct A {}

        // A plain line comment.
        struct B {}
        """,
      findings: []
    )
  }

  func testCRLEndingsInsideARunArePreserved() {
    // The newline pieces that separate a run's lines are carried through the rewrite, so a CR LF
    // file does not come out of normalization with mixed line endings.
    assertFormatting(
      CanonicalDocComments.self,
      input: "///Glued.\r\n///\r\n///\r\n/// Done.\r\n1️⃣struct S {}\r\n",
      expected: "/// Glued.\r\n///\r\n/// Done.\r\nstruct S {}\r\n",
      findings: [
        FindingSpec("1️⃣", message: "normalize this doc comment's layout")
      ]
    )
  }

  func testEachSurvivingLineKeepsItsOwnIndentation() {
    // When blank doc lines collapse, the surviving lines keep their own indentation: the kept
    // blank uses the first blank's indentation and the following line keeps the indentation it
    // was written with, not the dropped blank's.
    assertFormatting(
      CanonicalDocComments.self,
      input: "/// A\n  ///\n    ///\n      /// B\n1️⃣struct S {}\n",
      expected: "/// A\n  ///\n      /// B\nstruct S {}\n",
      findings: [
        FindingSpec("1️⃣", message: "normalize this doc comment's layout")
      ]
    )
  }
}
