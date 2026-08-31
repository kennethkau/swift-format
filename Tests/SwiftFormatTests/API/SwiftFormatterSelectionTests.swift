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

import SwiftFormat
@_spi(Rules) import SwiftFormat
import SwiftOperators
import SwiftParser
import SwiftSyntax
import XCTest
import _SwiftFormatTestSupport

final class SwiftFormatterSelectionTests: XCTestCase {
  func testSingleLineFormatting() throws {
    let source = """
      func foo() {
      let x = 1
      let y = 2
          let z = 3
      }

      """

    let expected = """
      func foo() {
        let x = 1
      let y = 2
          let z = 3
      }

      """

    try assertFormatting(source, expected: expected, selection: Selection(lineRanges: [2...2]))
  }

  func testMultipleLinesFormatting() throws {
    let source = """
      func foo() {
      let x = 1
      let y = 2
          let z = 3
      }

      """

    let expected = """
      func foo() {
        let x = 1
        let y = 2
          let z = 3
      }

      """

    try assertFormatting(source, expected: expected, selection: Selection(lineRanges: [2...3]))
  }

  func testDisjointLineRanges() throws {
    let source = """
      func foo() {
      let x = 1
      let y = 2
      let z = 3
      }

      """

    let expected = """
      func foo() {
        let x = 1
      let y = 2
        let z = 3
      }

      """

    try assertFormatting(source, expected: expected, selection: Selection(lineRanges: [2...2, 4...4]))
  }

  func testPartiallyWrappedFunctionSignature() throws {
    let source = """
      func someFunction(
        param1: Int,
      param2: String,
        param3: Double
      ) {}

      """

    let expected = """
      func someFunction(
        param1: Int,
        param2: String,
        param3: Double
      ) {}

      """

    try assertFormatting(source, expected: expected, selection: Selection(lineRanges: [3...3]))
  }

  func testComplexExpressionIndentation() throws {
    let source = """
      let x = someFunction(
      a,
      b,
      c
      )

      """

    let expected = """
      let x = someFunction(
      a,
        b,
      c
      )

      """

    try assertFormatting(source, expected: expected, selection: Selection(lineRanges: [3...3]))
  }

  func testMultipleSpacesInsideLine() throws {
    let source = """
      let x = 1
      let y = 1   +   2
      let z = 1

      """

    let expected = """
      let x = 1
      let y = 1 + 2
      let z = 1

      """

    try assertFormatting(source, expected: expected, selection: Selection(lineRanges: [2...2]))
  }

  func testAdjacentLongLineNotWrapped() throws {
    let source = """
      let a = 1
      let veryLongVariableNameThatExceedsTheLineLengthLimitAndShouldBeWrappedIfSelected = 42

      """

    let expected = """
      let a = 1
      let veryLongVariableNameThatExceedsTheLineLengthLimitAndShouldBeWrappedIfSelected = 42

      """

    try assertFormatting(source, expected: expected, selection: Selection(lineRanges: [1...1]))
  }

  func testDegenerateSignatureIndentation() throws {
    let source = """
      func messyFunction(
        p1: Int,
      p2: String,
          p3: Double
      ) {}

      """

    let expected = """
      func messyFunction(
        p1: Int,
        p2: String,
          p3: Double
      ) {}

      """

    try assertFormatting(source, expected: expected, selection: Selection(lineRanges: [3...3]))
  }

  func testOutOfBoundsLineRange() throws {
    let source = """
      let x = 1
      let y = 2

      """

    let expected = """
      let x = 1
      let y = 2

      """

    try assertFormatting(source, expected: expected, selection: Selection(lineRanges: [10...20]))
  }

  func testPartialOutOfBoundsLineRange() throws {
    let source = """
      let x = 1
        let y = 2

      """

    let expected = """
      let x = 1
      let y = 2

      """

    try assertFormatting(source, expected: expected, selection: Selection(lineRanges: [2...100]))
  }

  func testZeroLineRange() throws {
    let source = """
      let x = 1
      let y = 2

      """

    let expected = """
      let x = 1
      let y = 2

      """

    try assertFormatting(source, expected: expected, selection: Selection(lineRanges: [0...0]))
  }

  func testRulesApplyToSelectionNotStartingAtFileStart() throws {
    let source = """
      func first() {
        let a = 1
      }

      func second() -> Void {
        let b = 2;
      }

      """

    let expected = """
      func first() {
        let a = 1
      }

      func second() {
        let b = 2
      }

      """

    // The selected declaration is fully rewritten by format rules: the explicit `Void` return
    // type is removed and the semicolon is replaced by a line break, while the unselected first
    // declaration is left untouched.
    try assertFormatting(source, expected: expected, selection: Selection(lineRanges: [5...7]))
  }

  func testLengthChangingRewriteKeepsFollowingTextIntact() throws {
    let source = """
      func f() {
          let x = 1000000
          let y = "\u{1F600}"
      }

      """

    let expected = """
      func f() {
        let x = 1_000_000
          let y = "\u{1F600}"
      }

      """

    // Inserting the underscores into the literal grows the rewritten text; the text after the
    // selection must remain byte-for-byte identical, including the line break that separates it
    // from the rewritten statement. The multi-byte content after the selection also pins that
    // ranges and slices are measured in UTF-8 bytes, not in Characters.
    try assertFormatting(source, expected: expected, selection: Selection(lineRanges: [2...2]))
  }

  func testSelectionThroughEndOfFileKeepsFinalLineBreak() throws {
    let source = """
      let a = 1
      func f() -> Void {
        let x = 1;
      }
      """

    let expected = """
      let a = 1
      func f() {
        let x = 1
      }
      """

    // The rewrites shrink the file, so the range must shrink with them: an unshifted range
    // would run past the end of the rewritten text and swallow the EOF token, which formats to
    // a second, spurious line break. The range never covers the EOF token itself — for a line
    // range that resolves to the last byte before it — so the final line break here survives
    // as verbatim text rather than being emitted by formatting.
    try assertFormatting(source, expected: expected, selection: Selection(lineRanges: [2...4]))
  }

  func testOffsetRangeThroughEndOfFileKeepsFinalLineBreak() throws {
    let source = """
      let a = 1
      func f() -> Void {
        let x = 1;
      }
      """

    let expected = """
      let a = 1
      func f() {
        let x = 1
      }
      """

    // An offset range that ends at or beyond the end of the file exercises the same coverage of
    // the rewritten end: the range is remapped past the shrunken text so the EOF token stays
    // formatted. Unlike the line-range variant above, this selection includes the end of the
    // file, so formatting also supplies the file's final line break.
    let end = source.utf8.count
    try assertFormatting(
      source,
      expected: expected + "\n",
      selection: Selection(offsetRanges: [10..<end])
    )
  }

  func testUnorderedAndOverlappingRanges() throws {
    let source = """
      func f() {
          let x = 1000000
          let y = 2
          let z = 3000000
          let w = 4
      }

      """

    let expected = """
      func f() {
        let x = 1_000_000
        let y = 2
        let z = 3_000_000
          let w = 4
      }

      """

    // Ranges given out of order are sorted; a range overlapping an earlier one is coalesced with
    // it rather than shifted by its rewrites.
    try assertFormatting(
      source,
      expected: expected,
      selection: Selection(lineRanges: [4...4, 3...4, 2...2, 3...3])
    )
  }

  func testDuplicateRangesAreCoalescedNotShifted() throws {
    let source = """
      struct S {
        let a = 1
        let b = 2
        let c = 3
        func f() {
          let n = 1000000
          print(self.a, self.b, self.c)
        }
      }

      """

    let expected = """
      struct S {
        let a = 1
        let b = 2
        let c = 3
        func f() {
          let n = 1000000
          print(a, b, c)
        }
      }

      """

    // The duplicated range must be coalesced with itself rather than run a second time shifted
    // by its own rewrites: the `self.` removals shrink the line by 15 bytes, so a shifted
    // rerun would slide 15 bytes left and reformat the unselected `let n` line above it.
    var configuration = Configuration.forTesting
    configuration.rules[RedundantSelf.self.ruleName] = true
    try assertFormatting(
      source,
      expected: expected,
      selection: Selection(lineRanges: [7...7, 7...7]),
      configuration: configuration
    )
  }

  func testEmptyRangeFormatsNothing() throws {
    let source = """
      let  x  =  1
      let  y  =  2

      """

    // An empty range selects nothing; the printing pass treats a boundary-touching range as
    // selecting the tokens on both sides of the boundary, so keeping it would reformat the
    // adjacent unselected line.
    try assertFormatting(
      source,
      expected: source,
      selection: Selection(offsetRanges: [10..<10])
    )
  }

  func testDeclarationStraddlingSelectionStartIsNotRewritten() throws {
    let source = """
      func first() -> Void {
        let a = 1
      }
      func second() -> Void {
              let b = 2
      }

      """

    let expected = """
      func first() -> Void {
        let a = 1
      }
      func second() -> Void {
        let b = 2
      }

      """

    // The selection starts inside `second`'s body, so the declaration itself is not fully
    // contained and a rule that rewrites declarations must decline it; the selected statement is
    // still re-indented.
    try assertFormatting(source, expected: expected, selection: Selection(lineRanges: [5...5]))
  }

  func testDisjointRangesWithLengthChanges() throws {
    let source = """
      func f() {
          let x = 1000000
          let y = 2
          let z = 3000000
          let w = 4
      }

      """

    let expected = """
      func f() {
        let x = 1_000_000
          let y = 2
        let z = 3_000_000
          let w = 4
      }

      """

    // The rewrite in the first range grows the text between the two ranges; the second range
    // must still cover its own statements in the rewritten text.
    try assertFormatting(
      source,
      expected: expected,
      selection: Selection(lineRanges: [2...2, 4...4])
    )
  }

  func testIgnoredStatementInsideSelectionSkipsRules() throws {
    let source = """
      func f() {
        // swift-format-ignore
            let x = 1000000
            let y = 2
      }

      """

    let expected = """
      func f() {
        // swift-format-ignore
        let x = 1000000
        let y = 2
      }

      """

    // The ignore comment keeps the rules away from the statement that follows it — its numeric
    // literal is not regrouped — even though the whole function is selected and the statement
    // is still re-indented like any other verbatim text.
    try assertFormatting(source, expected: expected, selection: Selection(lineRanges: [1...5]))
  }

  func testFindingLinesReferToOriginalSourceAcrossShiftingRanges() throws {
    let source = """
      func f() {
        let a = 1

        let b = 1000000
      }
      let c = 1000000

      """

    let expected = """
      func f() {
        let a = 1
        let b = 1_000_000
      }
      let c = 1_000_000

      """

    var configuration = Configuration()
    configuration.rules[BlankLinePolicy.self.ruleName] = true
    configuration.blankLinePolicy.statements = .none

    var findings: [Finding] = []
    let formatter = SwiftFormatter(
      configuration: configuration,
      findingConsumer: { findings.append($0) }
    )
    var output = ""
    try formatter.format(
      source: source,
      assumingFileURL: nil,
      selection: Selection(lineRanges: [1...5, 6...6]),
      to: &output
    )
    XCTAssertEqual(output, expected)

    // The first range's rewrite removes the blank line inside the function, so the second range
    // runs on text where `let c` has moved up a line; its finding must still be reported at the
    // location in the original source, line 6. The finding for `let b` is emitted after the
    // blank-line removal has already shifted the tree one byte left of the original source, so
    // it reports the column the shifted byte offset lands on.
    let grouped = findings.filter {
      "\($0.message)" == "group every 3 digits in this decimal literal using a '_' separator"
    }
    let groupedLocations = grouped.compactMap { finding in
      finding.location.map { "\($0.line):\($0.column)" }
    }
    XCTAssertEqual(groupedLocations, ["4:10", "6:9"])
  }

  private func assertFormatting(
    _ source: String,
    expected: String,
    selection: Selection,
    configuration: Configuration? = nil,
    file: StaticString = #file,
    line: UInt = #line
  ) throws {
    var configuration = configuration ?? Configuration.forTesting
    configuration.lineLength = 60

    let formatter = SwiftFormatter(configuration: configuration)
    var output = ""
    let tree = Parser.parse(source: source)
    let foldedTree = try! OperatorTable.standardOperators.foldAll(tree).as(SourceFileSyntax.self)!
    try formatter.format(
      syntax: foldedTree,
      source: source,
      operatorTable: .standardOperators,
      assumingFileURL: nil,
      selection: selection,
      to: &output
    )
    XCTAssertEqual(output, expected, file: file, line: line)
  }
}
