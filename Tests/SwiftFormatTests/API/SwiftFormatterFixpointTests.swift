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
import XCTest
import _SwiftFormatTestSupport

/// Tests for the fixpoint iteration loop in `SwiftFormatter`: input that does not parse is
/// rejected in both single-pass and fixpoint modes, and findings reach the consumer only from
/// the pass whose output is returned.
final class SwiftFormatterFixpointTests: XCTestCase {
  /// The shared input: the first line is rewritten, while the comment-carrying parenthesized
  /// expression on the second line is diagnosed but kept on every pass. (The expected output is
  /// the printer's normalization of that line, which spaces the comment differently than the
  /// input.)
  private let input = "let a = (x)\nlet b = (/* c */ y)\n"
  private let expectedOutput = "let a = x\nlet b = ( /* c */y)\n"

  @discardableResult
  private func format(_ source: String, iterate: Bool) throws -> (output: String, findings: [Finding]) {
    var configuration = Configuration.forTesting(enabledRule: "RedundantParens")
    configuration.iterateToFixpoint = iterate
    var findings: [Finding] = []
    let formatter = SwiftFormatter(
      configuration: configuration,
      findingConsumer: { findings.append($0) }
    )
    var output = ""
    try formatter.format(source: source, assumingFileURL: nil, selection: .infinite, to: &output)
    return (output, findings)
  }

  func testInvalidInputThrowsWithAndWithoutFixpointIteration() {
    // Parsing errors are validated on the first pass in both modes.
    for iterate in [false, true] {
      XCTAssertThrowsError(try format("func {{{\n", iterate: iterate)) { error in
        XCTAssertEqual(error as? SwiftFormatError, .fileContainsInvalidSyntax)
      }
    }
  }

  func testFindingsAreForwardedOnlyFromTheReturnedPass() throws {
    // Only the stabilizing pass's findings may reach the consumer; the rewrite finding from
    // pass 1 describes text the caller never receives and must be dropped.
    let result = try format(input, iterate: true)
    XCTAssertEqual(result.output, expectedOutput)
    XCTAssertEqual(result.findings.count, 1, "findings must be forwarded once from the stabilizing pass")
  }

  func testSinglePassForwardsAllFindings() throws {
    let result = try format(input, iterate: false)
    XCTAssertEqual(result.output, expectedOutput)
    XCTAssertEqual(result.findings.count, 2)
  }
}
