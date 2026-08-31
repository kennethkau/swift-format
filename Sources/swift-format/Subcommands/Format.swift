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

import ArgumentParser
import Foundation

extension SwiftFormatCommand {
  /// Formats one or more files containing Swift code.
  struct Format: ParsableCommand {
    static var configuration = CommandConfiguration(
      abstract: "Format Swift source code",
      discussion: "When no files are specified, it expects the source from standard input."
    )

    /// Whether or not to format the Swift file in-place.
    ///
    /// If specified, the current file is overwritten when formatting.
    @Flag(
      name: .shortAndLong,
      help: "Overwrite the current file when formatting."
    )
    var inPlace: Bool = false

    /// Whether to check formatting without writing files.
    ///
    /// If specified, no files are written. The command exits with status 1 if any file would be
    /// reformatted (printing the list of such files) or could not be certified as formatted —
    /// including a file that does not parse while `--ignore-unparsable-files` skips it, since a
    /// check gate cannot certify a file it could not parse — status 2 if an internal error
    /// occurred, and status 0 if every file is already formatted.
    @Flag(
      name: .long,
      help: """
        Check formatting without writing files. Exits with status 1 if any file would be reformatted \
        or could not be certified as formatted, or status 2 on error. Unparsable files are an error \
        unless '--ignore-unparsable-files' is also given, in which case they are skipped but still \
        count as not certified for the exit code.
        """
    )
    var check: Bool = false

    /// Whether to print a unified diff of formatting changes instead of writing files.
    ///
    /// If specified, no files are written. The exit codes match `--check`: status 1 if any file
    /// would be reformatted or could not be certified as formatted, status 2 if an internal
    /// error occurred, and status 0 if every file is already formatted and none were skipped
    /// as unparsable.
    @Flag(
      name: .long,
      help: """
        Print a unified diff of the formatting changes instead of writing files. Exit codes match \
        '--check'.
        """
    )
    var diff: Bool = false

    @Flag(
      name: .long,
      help: """
        Verify the formatted output before it is written, reported, or printed: it is re-parsed \
        and compared against a re-parse of the input, and any difference beyond the documented \
        tolerances (trivia, literal spellings, redundant parentheses and `self`, import, modifier, and \
        attribute order, trailing separators, and the canonicalizations performed by some \
        default-on rules) is reported as an error. The comparison is syntactic-shape \
        equivalence, not type checking: a few structural default-on rule rewrites are outside \
        the tolerance set and are reported as mismatches. Under '--check'/'--diff' a \
        verification failure is an internal error (exit code 2) and the file is not listed as \
        merely needing reformatting.
        """
    )
    var verify: Bool = false

    @OptionGroup()
    var configurationOptions: ConfigurationOptions

    @OptionGroup()
    var formatOptions: LintFormatOptions

    @OptionGroup(visibility: .hidden)
    var performanceMeasurementOptions: PerformanceMeasurementsOptions

    func validate() throws {
      if inPlace && formatOptions.paths.isEmpty {
        throw ValidationError("'--in-place' is only valid when formatting files")
      }
      if (check || diff) && inPlace {
        throw ValidationError("'--check' and '--diff' cannot be combined with '--in-place'")
      }
      if check && diff {
        throw ValidationError("'--check' and '--diff' are mutually exclusive")
      }
    }

    func run() throws {
      try performanceMeasurementOptions.printingInstructionCountIfRequested {
        let frontend = FormatFrontend(
          configurationOptions: configurationOptions,
          lintFormatOptions: formatOptions,
          inPlace: inPlace,
          check: check,
          diff: diff,
          verify: verify
        )
        frontend.run()
        // Under --parallel, diagnostics are buffered so concurrent file processing cannot
        // reorder them; forward them now that all files have been processed.
        frontend.flushDiagnostics()

        if check || diff {
          frontend.printCollectedResults()
          let wouldReformat = frontend.wouldReformatCount
          if wouldReformat > 0 {
            let stderrStream = FileHandleTextOutputStream(FileHandle.standardError)
            if wouldReformat == 1 {
              stderrStream.write("1 file would be reformatted.\n")
            } else {
              stderrStream.write("\(wouldReformat) files would be reformatted.\n")
            }
          }
          let uncertified = frontend.uncertifiedCount
          if uncertified > 0 {
            let stderrStream = FileHandleTextOutputStream(FileHandle.standardError)
            if uncertified == 1 {
              stderrStream.write("1 file could not be parsed and was not certified as formatted.\n")
            } else {
              stderrStream.write("\(uncertified) files could not be parsed and were not certified as formatted.\n")
            }
          }
        }

        // Exit code contract (matches Black/rustfmt conventions), shared by `--check` and
        // `--diff`: 0 = nothing would change, 1 = some file would be reformatted or could not be
        // certified as formatted (skipped unparsable files under --ignore-unparsable-files),
        // 2 = an internal error occurred. Without either flag: 0 = success (regardless of
        // changes), 1 = an error occurred.
        if frontend.diagnosticsEngine.hasErrors {
          throw (check || diff) ? ExitCode(2) : ExitCode.failure
        }
        if (check || diff) && (frontend.wouldReformatCount > 0 || frontend.uncertifiedCount > 0) {
          throw ExitCode.failure
        }
      }
    }
  }
}
