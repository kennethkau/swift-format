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

import Foundation
import XCTest

@testable import swift_format

/// Tests the outcomes that drive the `format --check`/`--diff` exit-code contract
/// (0 = clean, 1 = would reformat or could not be certified, 2 = internal error): the
/// would-reformat count, the uncertified count, and the error state, including the
/// `--ignore-unparsable-files` interactions.
///
/// The option groups are built with `Format.parse` because this ArgumentParser version rejects
/// reads of wrapped properties on directly initialized instances.
final class FormatFrontendCheckTests: XCTestCase {
  private func withTempDirectory<T>(_ body: (URL) throws -> T) throws -> T {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("FormatFrontendCheckTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    return try body(directory)
  }

  private func makeFrontend(
    paths: [String],
    check: Bool = true,
    diff: Bool = false,
    ignoreUnparsable: Bool = false,
    parallel: Bool = false,
    inPlace: Bool = false
  ) throws -> FormatFrontend {
    var arguments = paths
    if check { arguments.append("--check") }
    if diff { arguments.append("--diff") }
    if inPlace { arguments.append("--in-place") }
    if ignoreUnparsable { arguments.append("--ignore-unparsable-files") }
    if parallel { arguments.append("--parallel") }
    let command = try SwiftFormatCommand.Format.parse(arguments)
    return FormatFrontend(
      configurationOptions: command.configurationOptions,
      lintFormatOptions: command.formatOptions,
      inPlace: command.inPlace,
      check: command.check,
      diff: command.diff
    )
  }

  func testCheckCountsOnlyFilesThatWouldChange() throws {
    try withTempDirectory { directory in
      let clean = directory.appendingPathComponent("Clean.swift")
      try "let x = 1\n".write(to: clean, atomically: true, encoding: .utf8)
      let dirty = directory.appendingPathComponent("Dirty.swift")
      try "let x=1\n".write(to: dirty, atomically: true, encoding: .utf8)

      let frontend = try makeFrontend(paths: [clean.path, dirty.path])
      frontend.run()
      XCTAssertEqual(frontend.wouldReformatCount, 1)
      XCTAssertFalse(frontend.diagnosticsEngine.hasErrors)
    }
  }

  func testCheckReportsUnparsableFileAsError() throws {
    try withTempDirectory { directory in
      let broken = directory.appendingPathComponent("Broken.swift")
      try "func {{{\n".write(to: broken, atomically: true, encoding: .utf8)

      let frontend = try makeFrontend(paths: [broken.path])
      frontend.run()
      // The exit-code contract maps an engine error to exit 2, and the would-reformat count
      // must not also claim the file.
      XCTAssertTrue(frontend.diagnosticsEngine.hasErrors)
      XCTAssertEqual(frontend.wouldReformatCount, 0)
    }
  }

  func testCheckWithIgnoreUnparsableFilesCountsFileAsUncertified() throws {
    try withTempDirectory { directory in
      let broken = directory.appendingPathComponent("Broken.swift")
      try "func {{{\n".write(to: broken, atomically: true, encoding: .utf8)

      let frontend = try makeFrontend(paths: [broken.path], ignoreUnparsable: true)
      frontend.run()
      // Documented behavior: with --ignore-unparsable-files, a file that does not parse is
      // skipped rather than reported as an internal error, but a check gate cannot certify a
      // file it could not parse — it is counted as uncertified and must force a nonzero exit.
      XCTAssertFalse(frontend.diagnosticsEngine.hasErrors)
      XCTAssertEqual(frontend.wouldReformatCount, 0)
      XCTAssertEqual(frontend.uncertifiedCount, 1)
    }
  }

  func testDiffWithIgnoreUnparsableFilesCountsFileAsUncertified() throws {
    try withTempDirectory { directory in
      let broken = directory.appendingPathComponent("Broken.swift")
      try "func {{{\n".write(to: broken, atomically: true, encoding: .utf8)

      // --diff shares the --check exit contract, so a skipped unparsable file must count as
      // uncertified there as well.
      let frontend = try makeFrontend(paths: [broken.path], check: false, diff: true, ignoreUnparsable: true)
      frontend.run()
      XCTAssertFalse(frontend.diagnosticsEngine.hasErrors)
      XCTAssertEqual(frontend.wouldReformatCount, 0)
      XCTAssertEqual(frontend.uncertifiedCount, 1)
    }
  }

  func testMultipleUnparsableFilesAreAllCounted() throws {
    try withTempDirectory { directory in
      let first = directory.appendingPathComponent("FirstBroken.swift")
      try "func {{{\n".write(to: first, atomically: true, encoding: .utf8)
      let second = directory.appendingPathComponent("SecondBroken.swift")
      try "let ]\n".write(to: second, atomically: true, encoding: .utf8)

      let frontend = try makeFrontend(paths: [first.path, second.path], ignoreUnparsable: true)
      frontend.run()
      XCTAssertFalse(frontend.diagnosticsEngine.hasErrors)
      XCTAssertEqual(frontend.wouldReformatCount, 0)
      XCTAssertEqual(frontend.uncertifiedCount, 2)
    }
  }

  func testCheckCountsAllFilesInParallelMode() throws {
    try withTempDirectory { directory in
      let first = directory.appendingPathComponent("First.swift")
      try "let x=1\n".write(to: first, atomically: true, encoding: .utf8)
      let second = directory.appendingPathComponent("Second.swift")
      try "let y=2\n".write(to: second, atomically: true, encoding: .utf8)

      let frontend = try makeFrontend(paths: [first.path, second.path], parallel: true)
      frontend.run()
      XCTAssertEqual(frontend.wouldReformatCount, 2)
      XCTAssertFalse(frontend.diagnosticsEngine.hasErrors)
    }
  }

  func testInPlaceRewritesFileWithoutCountingIt() throws {
    try withTempDirectory { directory in
      let dirty = directory.appendingPathComponent("Dirty.swift")
      try "let x=1\n".write(to: dirty, atomically: true, encoding: .utf8)

      let frontend = try makeFrontend(paths: [dirty.path], check: false, inPlace: true)
      frontend.run()
      XCTAssertEqual(try String(contentsOf: dirty, encoding: .utf8), "let x = 1\n")
      XCTAssertEqual(frontend.wouldReformatCount, 0)
      XCTAssertFalse(frontend.diagnosticsEngine.hasErrors)
    }
  }

  func testInPlaceDropsByteOrderMarkerOnRewrite() throws {
    // The formatter itself preserves a leading BOM, but the tool's UTF-8 file reader treats it
    // as an encoding signature and strips it, so it is gone from any file it rewrites.
    try withTempDirectory { directory in
      let bomFile = directory.appendingPathComponent("BOM.swift")
      try Data([0xEF, 0xBB, 0xBF] + Array("let x=1\n".utf8)).write(to: bomFile)

      let frontend = try makeFrontend(paths: [bomFile.path], check: false, inPlace: true)
      frontend.run()
      XCTAssertEqual(try String(contentsOf: bomFile, encoding: .utf8), "let x = 1\n")
      XCTAssertFalse(frontend.diagnosticsEngine.hasErrors)
    }
  }
}
