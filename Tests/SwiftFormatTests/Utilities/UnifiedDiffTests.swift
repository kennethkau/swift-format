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

@_spi(Internal) import SwiftFormat
import XCTest

final class UnifiedDiffTests: XCTestCase {
  func testIdenticalInputsProduceEmptyDiff() {
    XCTAssertEqual(
      UnifiedDiff.diff(from: "a\nb\nc\n", to: "a\nb\nc\n", fromPath: "a/f", toPath: "b/f"),
      ""
    )
  }

  func testSingleLineInsertion() {
    let diff = UnifiedDiff.diff(
      from: "one\nthree\n",
      to: "one\ntwo\nthree\n",
      fromPath: "a/f",
      toPath: "b/f"
    )
    XCTAssertEqual(
      diff,
      """
      --- a/f
      +++ b/f
      @@ -1,2 +1,3 @@
       one
      +two
       three
      """
        + "\n"
    )
  }

  func testSingleLineDeletion() {
    let diff = UnifiedDiff.diff(
      from: "one\ntwo\nthree\n",
      to: "one\nthree\n",
      fromPath: "a/f",
      toPath: "b/f"
    )
    XCTAssertEqual(
      diff,
      """
      --- a/f
      +++ b/f
      @@ -1,3 +1,2 @@
       one
      -two
       three
      """
        + "\n"
    )
  }

  func testReplacementWithSurroundingContext() {
    let diff = UnifiedDiff.diff(
      from: "l1\nl2\nl3\nl4\nl5\nl6\nl7\n",
      to: "l1\nl2\nl3\nCHANGED\nl5\nl6\nl7\n",
      fromPath: "a/f",
      toPath: "b/f"
    )
    XCTAssertEqual(
      diff,
      """
      --- a/f
      +++ b/f
      @@ -1,7 +1,7 @@
       l1
       l2
       l3
      -l4
      +CHANGED
       l5
       l6
       l7
      """
        + "\n"
    )
  }

  func testDistantChangesProduceSeparateHunks() {
    // Ten unchanged lines between the two changes is more than twice the context window, so the
    // changes must not be merged into a single hunk.
    var oldText = "change1\n"
    var newText = "CHANGE1\n"
    for i in 0..<10 {
      oldText += "same\(i)\n"
      newText += "same\(i)\n"
    }
    oldText += "change2\n"
    newText += "CHANGE2\n"

    let diff = UnifiedDiff.diff(from: oldText, to: newText, fromPath: "a/f", toPath: "b/f")
    let hunkHeaders = diff.split(separator: "\n").filter { $0.hasPrefix("@@") }
    XCTAssertEqual(hunkHeaders.count, 2)
    XCTAssertEqual(
      hunkHeaders.first.map(String.init),
      "@@ -1,4 +1,4 @@"
    )
    XCTAssertTrue(diff.contains("-change1\n+CHANGE1"))
    XCTAssertTrue(diff.contains("-change2\n+CHANGE2"))
  }

  func testAdjacentChangesMergeIntoOneHunk() {
    let diff = UnifiedDiff.diff(
      from: "a\nb\nc\nd\n",
      to: "A\nB\nc\nd\n",
      fromPath: "a/f",
      toPath: "b/f"
    )
    let hunkHeaders = diff.split(separator: "\n").filter { $0.hasPrefix("@@") }
    XCTAssertEqual(hunkHeaders.count, 1)
    XCTAssertEqual(
      diff,
      """
      --- a/f
      +++ b/f
      @@ -1,4 +1,4 @@
      -a
      -b
      +A
      +B
       c
       d
      """
        + "\n"
    )
  }

  func testPureInsertionAtEnd() {
    let diff = UnifiedDiff.diff(
      from: "one\n",
      to: "one\ntwo\n",
      fromPath: "a/f",
      toPath: "b/f"
    )
    XCTAssertEqual(
      diff,
      """
      --- a/f
      +++ b/f
      @@ -1,1 +1,2 @@
       one
      +two
      """
        + "\n"
    )
  }

  func testPureInsertionWithZeroContextReportsEmptyOldRange() {
    // With no context lines, a pure insertion consumes no lines from the old text, so the old
    // range is empty and (per the unified diff format) starts at the line before the hunk.
    let diff = UnifiedDiff.diff(
      from: "one\n",
      to: "zero\none\n",
      fromPath: "a/f",
      toPath: "b/f",
      contextLines: 0
    )
    XCTAssertEqual(
      diff,
      """
      --- a/f
      +++ b/f
      @@ -0,0 +1,1 @@
      +zero
      """
        + "\n"
    )
  }

  func testUnchangedLastLineWithAddedTrailingNewlineDiffsAsReplacement() {
    // The old text's final line lacks a newline and the new text's has one; the line is
    // otherwise identical. Because termination is part of line identity, the line must diff as
    // a replacement pair with the marker on the old side — a marker on a shared context line
    // would wrongly apply to both sides and produce a post-image missing the newline.
    let diff = UnifiedDiff.diff(
      from: "func f() {\n  let x=1\n}",
      to: "func f() {\n  let x = 1\n}\n",
      fromPath: "a/f.swift",
      toPath: "b/f.swift"
    )
    XCTAssertEqual(
      diff,
      """
      --- a/f.swift
      +++ b/f.swift
      @@ -1,3 +1,3 @@
       func f() {
      -  let x=1
      -}
      \\ No newline at end of file
      +  let x = 1
      +}
      """
        + "\n"
    )
  }

  func testInsertionAfterUnterminatedLastLineKeepsLinesSeparate() {
    // An inserted line following an unchanged-but-unterminated final line must not merge the
    // two in the reconstructed post-image: the unterminated line diffs as a replacement.
    let diff = UnifiedDiff.diff(
      from: "a\nx",
      to: "a\nx\ny\n",
      fromPath: "a/f.swift",
      toPath: "b/f.swift"
    )
    XCTAssertEqual(
      diff,
      """
      --- a/f.swift
      +++ b/f.swift
      @@ -1,2 +1,3 @@
       a
      -x
      \\ No newline at end of file
      +x
      +y
      """
        + "\n"
    )
  }

  func testChangedLinesWithoutTrailingNewlineCarryMarkersOnBothSides() {
    let diff = UnifiedDiff.diff(
      from: "let x=1",
      to: "let x = 1",
      fromPath: "a/f.swift",
      toPath: "b/f.swift"
    )
    XCTAssertEqual(
      diff,
      """
      --- a/f.swift
      +++ b/f.swift
      @@ -1,1 +1,1 @@
      -let x=1
      \\ No newline at end of file
      +let x = 1
      \\ No newline at end of file
      """
        + "\n"
    )
  }

  func testTrailingNewlineAdditionProducesMarkerHunk() {
    // A difference consisting solely of an added trailing newline must not produce an empty
    // diff: `--check` counts the file, so `--diff` must show the change. The marker follows the
    // "-" line, the side that lacks the newline.
    let diff = UnifiedDiff.diff(
      from: "let x = 1",
      to: "let x = 1\n",
      fromPath: "a/f.swift",
      toPath: "b/f.swift"
    )
    XCTAssertEqual(
      diff,
      """
      --- a/f.swift
      +++ b/f.swift
      @@ -1,1 +1,1 @@
      -let x = 1
      \\ No newline at end of file
      +let x = 1
      """
        + "\n"
    )
  }

  func testTrailingNewlineRemovalProducesMarkerHunk() {
    // The marker follows the "+" line: the revised text is the side lacking the newline.
    let diff = UnifiedDiff.diff(
      from: "let x = 1\n",
      to: "let x = 1",
      fromPath: "a/f.swift",
      toPath: "b/f.swift"
    )
    XCTAssertEqual(
      diff,
      """
      --- a/f.swift
      +++ b/f.swift
      @@ -1,1 +1,1 @@
      -let x = 1
      +let x = 1
      \\ No newline at end of file
      """
        + "\n"
    )
  }

  func testCRLFInputDiffsAgainstLFOutputPerLine() {
    // CR LF is a single grapheme cluster in Swift, so splitting on "\n" as Characters would not
    // split a CRLF file at all. Splitting must keep the CR in the deleted lines' content so the
    // patch is applicable and matches what `--check` (a byte comparison) reports.
    let diff = UnifiedDiff.diff(
      from: "let x = 1\r\nlet y = 2\r\n",
      to: "let x = 1\nlet y = 2\n",
      fromPath: "a/f.swift",
      toPath: "b/f.swift"
    )
    XCTAssertEqual(
      diff,
      "--- a/f.swift\n+++ b/f.swift\n@@ -1,2 +1,2 @@\n"
        + "-let x = 1\r\n"
        + "-let y = 2\r\n"
        + "+let x = 1\n"
        + "+let y = 2\n"
    )
  }

  func testChangedLastLinesWithoutTrailingNewlineCarryMarkers() {
    let diff = UnifiedDiff.diff(
      from: "let x=1\nlet y=2",
      to: "let x = 1\nlet y = 2",
      fromPath: "a/f.swift",
      toPath: "b/f.swift"
    )
    XCTAssertEqual(
      diff,
      """
      --- a/f.swift
      +++ b/f.swift
      @@ -1,2 +1,2 @@
      -let x=1
      -let y=2
      \\ No newline at end of file
      +let x = 1
      +let y = 2
      \\ No newline at end of file
      """
        + "\n"
    )
  }
}
