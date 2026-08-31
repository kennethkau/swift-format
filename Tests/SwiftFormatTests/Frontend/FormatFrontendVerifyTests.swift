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

import ArgumentParser
import XCTest

@testable import swift_format

/// Tests the `format --verify` mode: the formatted output is re-parsed and compared against a
/// re-parse of the input, and a difference beyond the documented meaning-preserving rewrites is
/// an error that must prevent the output from being written.
final class FormatFrontendVerifyTests: XCTestCase {
  private func withTempDirectory<T>(_ body: (URL) throws -> T) throws -> T {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("FormatFrontendVerifyTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    return try body(directory)
  }

  private func makeFrontend(paths: [String], verify: Bool = true) throws -> FormatFrontend {
    var arguments = paths
    if verify {
      arguments.append("--verify")
    }
    let command = try SwiftFormatCommand.Format.parse(arguments)
    return FormatFrontend(
      configurationOptions: command.configurationOptions,
      lintFormatOptions: command.formatOptions,
      inPlace: command.inPlace,
      check: command.check,
      diff: command.diff,
      verify: command.verify
    )
  }

  func testVerifyPassesForFormattedOutput() throws {
    try withTempDirectory { directory in
      let file = directory.appendingPathComponent("Clean.swift")
      try "let x=1\n".write(to: file, atomically: true, encoding: .utf8)

      let frontend = try makeFrontend(paths: [file.path])
      frontend.run()
      XCTAssertFalse(frontend.diagnosticsEngine.hasErrors)
    }
  }

  func testVerifyCatchesNonEquivalentOutput() throws {
    try withTempDirectory { directory in
      let file = directory.appendingPathComponent("Broken.swift")
      try "let x=1\n".write(to: file, atomically: true, encoding: .utf8)

      let frontend = try makeFrontend(paths: [file.path])
      // A rename is beyond every tolerated rewrite.
      XCTAssertTrue(
        !frontend.verifyFormattedOutput(source: "let foo = 1\n", formatted: "let bar = 1\n", url: file)
      )
      XCTAssertTrue(frontend.diagnosticsEngine.hasErrors)
    }
  }

  func testVerifyAcceptsToleratedRewrites() throws {
    try withTempDirectory { directory in
      let file = directory.appendingPathComponent("Rewrites.swift")

      let frontend = try makeFrontend(paths: [file.path])
      XCTAssertTrue(
        frontend.verifyFormattedOutput(
          source: "let x = (1)\nlet s = #\"a\"b\"#\n",
          formatted: "let x = 1\nlet s = \"a\\\"b\"\n",
          url: file
        )
      )
      XCTAssertFalse(frontend.diagnosticsEngine.hasErrors)
    }
  }

  func testVerifyWritesInPlaceForEquivalentOutput() throws {
    try withTempDirectory { directory in
      let file = directory.appendingPathComponent("InPlace.swift")
      try "let foo=1\nlet bar=2\n".write(to: file, atomically: true, encoding: .utf8)

      let command = try SwiftFormatCommand.Format.parse(["--verify", "--in-place", file.path])
      let frontend = FormatFrontend(
        configurationOptions: command.configurationOptions,
        lintFormatOptions: command.formatOptions,
        inPlace: command.inPlace,
        verify: command.verify
      )
      frontend.run()
      // The real formatter produces equivalent output, so the file is written.
      XCTAssertFalse(frontend.diagnosticsEngine.hasErrors)
      let contents = try String(contentsOf: file, encoding: .utf8)
      XCTAssertEqual(contents, "let foo = 1\nlet bar = 2\n")
    }
  }

  /// A frontend whose verification always fails, to exercise the failure path of a real run.
  private final class FailingVerifyFrontend: FormatFrontend {
    override func verifyFormattedOutput(source: String, formatted: String, url: URL) -> Bool {
      diagnosticsEngine.emitError("Verification failed for \(url.relativePath)")
      return false
    }
  }

  func testVerifyFailureUnderCheckIsAnErrorNotAWouldReformat() throws {
    try withTempDirectory { directory in
      // A dirty file: with verification passing it counts as needing reformatting, so a zero
      // count after a failing run can only come from the early return on failed verification.
      let file = directory.appendingPathComponent("Checked.swift")
      try "let foo=1\n".write(to: file, atomically: true, encoding: .utf8)

      let command = try SwiftFormatCommand.Format.parse(["--verify", "--check", file.path])
      let frontend = FailingVerifyFrontend(
        configurationOptions: command.configurationOptions,
        lintFormatOptions: command.formatOptions,
        inPlace: command.inPlace,
        check: command.check,
        diff: command.diff,
        verify: command.verify
      )
      frontend.run()

      XCTAssertTrue(frontend.diagnosticsEngine.hasErrors)
      XCTAssertEqual(frontend.wouldReformatCount, 0)
      // And nothing was written: the file still holds its original bytes.
      XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "let foo=1\n")
    }
  }

  func testCheckRunWithAnyErrorExitsTwo() throws {
    try withTempDirectory { directory in
      let broken = directory.appendingPathComponent("Broken.swift")
      try "func {{{\n".write(to: broken, atomically: true, encoding: .utf8)

      // The subcommand's exit contract: an error under --check maps to exit code 2, not the
      // would-reformat exit 1.
      let command = try SwiftFormatCommand.Format.parse(["--check", broken.path])
      XCTAssertThrowsError(try command.run()) { error in
        XCTAssertEqual(
          error as? ExitCode,
          ExitCode(2),
          "expected exit code 2, got \(error)"
        )
      }
    }
  }

  func testCheckWithVerifyStillCountsWouldReformatFiles() throws {
    try withTempDirectory { directory in
      let dirty = directory.appendingPathComponent("Dirty.swift")
      try "let x=1\n".write(to: dirty, atomically: true, encoding: .utf8)

      let command = try SwiftFormatCommand.Format.parse(["--verify", "--check", dirty.path])
      let frontend = FormatFrontend(
        configurationOptions: command.configurationOptions,
        lintFormatOptions: command.formatOptions,
        inPlace: command.inPlace,
        check: command.check,
        diff: command.diff,
        verify: command.verify
      )
      frontend.run()
      // With verification passing, the check contract is unchanged.
      XCTAssertFalse(frontend.diagnosticsEngine.hasErrors)
      XCTAssertEqual(frontend.wouldReformatCount, 1)
    }
  }

  func testVerifyRefusesUnparseableTrees() throws {
    try withTempDirectory { directory in
      let file = directory.appendingPathComponent("Broken.swift")

      let frontend = try makeFrontend(paths: [file.path])
      // A tree with error elements is a recovery tree, not a faithful parse; comparing two of
      // them could certify a broken rewrite, so verification refuses with an error.
      XCTAssertFalse(
        frontend.verifyFormattedOutput(source: "func {{{\n", formatted: "func {{{\n", url: file)
      )
      XCTAssertTrue(frontend.diagnosticsEngine.hasErrors)
    }
  }
}
