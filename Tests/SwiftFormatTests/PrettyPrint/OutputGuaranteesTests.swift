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

import SwiftDiagnostics
@_spi(Rules) import SwiftFormat
import XCTest
@_spi(Testing) import _SwiftFormatTestSupport

/// Pins the printer-level output guarantees that hold for every configuration: the output uses
/// LF line endings exclusively outside string literal content, ends with exactly one newline
/// whenever it has any content, and is empty for an empty input. These are documented as
/// guarantees in `Documentation/OutputGuarantees.md`.
final class OutputGuaranteesTests: XCTestCase {
  private func format(
    _ source: String,
    configuration: Configuration = Configuration()
  ) throws -> String {
    var output = ""
    let formatter = SwiftFormatter(configuration: configuration)
    try formatter.format(
      source: source,
      assumingFileURL: nil,
      selection: .infinite,
      to: &output,
      parsingDiagnosticHandler: { _, _ in }
    )
    return output
  }

  func testCRLFInputProducesLFOutput() throws {
    let output = try format("let x=1\r\nlet y=2\r\n")
    XCTAssertEqual(output, "let x = 1\nlet y = 2\n")
  }

  func testNoCarriageReturnsOutsideStringLiterals() throws {
    // A literal CR inside a string's *content* is source data and is preserved; everywhere else
    // the output must use LF exclusively.
    let output = try format("if x\r\n\t== 1 {\r\n  print(1)\r\n}\r\n\r\n\r\n")
    XCTAssertFalse(output.contains("\r"))
  }

  func testMissingTrailingNewlineIsRestored() throws {
    let output = try format("let x=1")
    XCTAssertEqual(output, "let x = 1\n")
  }

  func testExactlyOneTrailingNewline() throws {
    XCTAssertEqual(try format("let x=1\n\n\n"), "let x = 1\n")
    XCTAssertEqual(try format("let x=1\n\n\n\n\n"), "let x = 1\n")
    // A *trailing* run of blank lines collapses to exactly one final newline, but a run
    // *between* statements is author-placed and survives, clamped to one blank
    // line under the default configuration.
    XCTAssertEqual(try format("let x=1\n\n\nlet y=2\n\n\n\n"), "let x = 1\n\nlet y = 2\n")
  }

  func testEmptyInputProducesEmptyOutput() throws {
    // The formatting driver skips empty sources, so there is no trailing newline to produce.
    XCTAssertEqual(try format(""), "")
  }

  func testGuaranteesHoldWhenExistingLineBreaksAreIgnored() throws {
    // The same guarantees hold with non-default options, not just the defaults.
    var configuration = Configuration()
    configuration.respectsExistingLineBreaks = false
    let output = try format("let x=1\r\n\r\nlet y=2", configuration: configuration)
    XCTAssertEqual(output, "let x = 1\nlet y = 2\n")
  }

  func testCarriageReturnInsideLiteralContentIsPreserved() throws {
    // A CR that is *content* of a multiline literal (between two words, not a line ending) is
    // source data and survives; the CRs that are part of line endings normalize to LF.
    let output = try format("let text = \"\"\"\r\nline one\rline two\r\n\"\"\"\r\n")
    XCTAssertTrue(output.unicodeScalars.contains("\r"), "CR content inside the literal was dropped")
    XCTAssertEqual(output, "let text = \"\"\"\n  line one\rline two\n  \"\"\"\n")
  }

  func testLoneCarriageReturnsAreNormalizedToLineFeeds() throws {
    XCTAssertEqual(try format("let x=1\rlet y=2\r"), "let x = 1\nlet y = 2\n")
  }

  func testNoUnicodeNormalization() throws {
    // NFC vs NFD are different bytes — and different identifiers to the compiler — so the
    // formatter must never normalize: decomposed scalars in identifiers, comments, and string
    // content pass through byte-identically. ("e" + U+0301 vs the precomposed U+00E9.)
    let nfd = "let cafe\u{301} = \"cafe\u{301}\"  // cafe\u{301}\n"
    let output = try format(nfd)
    // String-level comparison is canonically equivalent between NFC and NFD, so the check must
    // be on unicode scalars: the decomposed combining scalar survives and the precomposed
    // scalar never appears.
    XCTAssertTrue(output.unicodeScalars.contains("\u{301}"), "decomposed scalars were normalized")
    XCTAssertFalse(output.unicodeScalars.contains("\u{e9}"), "decomposed scalars were recomposed")
  }
}
