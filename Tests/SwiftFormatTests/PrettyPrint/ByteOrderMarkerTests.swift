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

/// End-to-end tests for the byte-order marker at the `SwiftFormatter` API level: the formatter
/// preserves a leading BOM in its output, whether or not it rewrites the text. (The command
/// line tool drops it when it rewrites a file because its UTF-8 file reader treats the marker
/// as an encoding signature; that behavior is covered by `FormatFrontendCheckTests`.)
final class ByteOrderMarkerTests: XCTestCase {
  private func format(_ source: String) throws -> String {
    var output = ""
    let formatter = SwiftFormatter(configuration: Configuration())
    try formatter.format(
      source: source,
      assumingFileURL: nil,
      selection: .infinite,
      to: &output
    )
    return output
  }

  func testBOMIsPreservedWhenTheFileIsRewritten() throws {
    XCTAssertEqual(try format("\u{FEFF}let x=1\n"), "\u{FEFF}let x = 1\n")
  }

  func testBOMIsPreservedWhenTheFileNeedsNoRewrite() throws {
    XCTAssertEqual(try format("\u{FEFF}let x = 1\n"), "\u{FEFF}let x = 1\n")
  }
}
