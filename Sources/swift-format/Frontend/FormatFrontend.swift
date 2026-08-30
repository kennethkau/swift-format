//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import SwiftDiagnostics
@_spi(Internal) import SwiftFormat
import SwiftSyntax

/// The frontend for formatting operations.
class FormatFrontend: Frontend {
  /// Whether or not to format the Swift file in-place.
  private let inPlace: Bool

  /// Whether to check formatting without writing files, reporting files that would change.
  private let check: Bool

  /// Whether to print a unified diff of formatting changes instead of writing files.
  private let diff: Bool

  /// The paths of files that would be reformatted and their diffs, for `--check`/`--diff` mode.
  ///
  /// `processFile` may run concurrently when `--parallel` is passed, so access is synchronized
  /// with `resultsLock`; results are printed only after all files have been processed, in sorted
  /// order, so the output is deterministic.
  private var wouldReformatPaths: [String] = []
  private var collectedDiffs: [(path: String, text: String)] = []
  /// The paths of files that could not be parsed in `--check`/`--diff` mode with
  /// `--ignore-unparsable-files`: they are skipped, but a check gate cannot certify them as
  /// formatted, so they must not allow a clean exit.
  private var uncertifiedPaths: [String] = []
  private let resultsLock = NSLock()

  init(
    configurationOptions: ConfigurationOptions,
    lintFormatOptions: LintFormatOptions,
    inPlace: Bool,
    check: Bool = false,
    diff: Bool = false
  ) {
    self.inPlace = inPlace
    self.check = check
    self.diff = diff
    super.init(configurationOptions: configurationOptions, lintFormatOptions: lintFormatOptions)
  }

  /// The number of files that would be reformatted if formatting were applied.
  var wouldReformatCount: Int {
    resultsLock.lock()
    defer { resultsLock.unlock() }
    return wouldReformatPaths.count
  }

  /// The number of files that could not be parsed and were skipped under
  /// `--ignore-unparsable-files`, in `--check`/`--diff` mode.
  var uncertifiedCount: Int {
    resultsLock.lock()
    defer { resultsLock.unlock() }
    return uncertifiedPaths.count
  }

  /// Prints the results collected by `--check` and `--diff` in sorted order. Must be called
  /// after `run()` has completed.
  func printCollectedResults() {
    resultsLock.lock()
    let paths = wouldReformatPaths
    let diffs = collectedDiffs
    let uncertified = uncertifiedPaths
    resultsLock.unlock()

    let stdoutStream = FileHandleTextOutputStream(FileHandle.standardOutput)
    if check {
      for path in paths.sorted() {
        stdoutStream.write("would reformat \(path)\n")
      }
      for path in uncertified.sorted() {
        stdoutStream.write("could not be parsed, not certified as formatted: \(path)\n")
      }
    }
    if diff {
      for entry in diffs.sorted(by: { $0.path < $1.path }) {
        stdoutStream.write(entry.text)
      }
      // Not part of the unified diff; stderr keeps the diff stream applicable to `git apply`.
      let stderrStream = FileHandleTextOutputStream(FileHandle.standardError)
      for path in uncertified.sorted() {
        stderrStream.write("could not be parsed, not certified as formatted: \(path)\n")
      }
    }
  }

  override func processFile(_ fileToProcess: FileToProcess) {
    // In format mode, the diagnostics engine is reserved for fatal messages. Pass nil as the
    // finding consumer to ignore findings emitted while the syntax tree is processed because they
    // will be fixed automatically if they can be, or ignored otherwise.
    let formatter = SwiftFormatter(configuration: fileToProcess.configuration, findingConsumer: nil)
    formatter.debugOptions = debugOptions

    let url = fileToProcess.url
    guard let source = fileToProcess.sourceText else {
      diagnosticsEngine.emitError(
        "Unable to format \(url.relativePath): file is not readable or does not exist."
      )
      return
    }

    let diagnosticHandler: (SwiftDiagnostics.Diagnostic, SourceLocation) -> Void = {
      (diagnostic, location) in
      guard !self.lintFormatOptions.ignoreUnparsableFiles else {
        // No diagnostics should be emitted in this mode.
        return
      }
      self.diagnosticsEngine.consumeParserDiagnostic(diagnostic, location)
    }
    var stdoutStream = FileHandleTextOutputStream(FileHandle.standardOutput)
    do {
      if inPlace || check || diff {
        var buffer = ""
        try formatter.format(
          source: source,
          assumingFileURL: url,
          selection: fileToProcess.selection,
          experimentalFeatures: Set(lintFormatOptions.experimentalFeatures),
          to: &buffer,
          parsingDiagnosticHandler: diagnosticHandler
        )

        if buffer != source {
          if check || diff {
            resultsLock.lock()
            wouldReformatPaths.append(url.relativePath)
            resultsLock.unlock()
          }
          if diff {
            let text = UnifiedDiff.diff(
              from: source,
              to: buffer,
              fromPath: "a/\(url.relativePath)",
              toPath: "b/\(url.relativePath)"
            )
            resultsLock.lock()
            collectedDiffs.append((path: url.relativePath, text: text))
            resultsLock.unlock()
          }
        }
        if inPlace, buffer != source {
          let bufferData = buffer.data(using: .utf8)!  // Conversion to UTF-8 cannot fail
          try bufferData.write(to: url, options: .atomic)
        }
      } else {
        try formatter.format(
          source: source,
          assumingFileURL: url,
          selection: fileToProcess.selection,
          experimentalFeatures: Set(lintFormatOptions.experimentalFeatures),
          to: &stdoutStream,
          parsingDiagnosticHandler: diagnosticHandler
        )
      }
    } catch SwiftFormatError.fileContainsInvalidSyntax {
      guard !lintFormatOptions.ignoreUnparsableFiles else {
        if check || diff {
          // The file is skipped, but a check gate cannot certify it as formatted: record it so
          // the command cannot exit 0.
          resultsLock.lock()
          uncertifiedPaths.append(url.relativePath)
          resultsLock.unlock()
          return
        }
        guard !inPlace else {
          // For in-place mode, nothing is expected to stdout and the file shouldn't be modified.
          return
        }
        stdoutStream.write(source)
        return
      }
      // Otherwise, relevant diagnostics about the problematic nodes have already been emitted; we
      // don't need to print anything else.
    } catch {
      diagnosticsEngine.emitError("Unable to format \(url.relativePath): \(error.localizedDescription).")
    }
  }
}
