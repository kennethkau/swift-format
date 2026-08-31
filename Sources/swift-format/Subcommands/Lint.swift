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

extension SwiftFormatCommand {
  /// Emits style diagnostics for one or more files containing Swift code.
  struct Lint: ParsableCommand {
    static var configuration = CommandConfiguration(
      abstract: "Diagnose style issues in Swift source code",
      discussion: "When no files are specified, it expects the source from standard input."
    )

    @OptionGroup()
    var configurationOptions: ConfigurationOptions

    @OptionGroup()
    var lintOptions: LintFormatOptions

    @Flag(
      name: .shortAndLong,
      help: "Treat all findings as errors instead of warnings."
    )
    var strict: Bool = false

    /// The format in which findings and other diagnostics are reported.
    @Option(
      name: .long,
      help: """
        The format in which diagnostics are reported: \(DiagnosticReporter.Kind.allCases.map(\.helpDescription).joined(separator: " ")) \
        Selecting a non-default reporter buffers diagnostics and writes the report to standard output when \
        the run finishes, in sorted order (by file, line, and column).
        """
    )
    var reporter: DiagnosticReporter.Kind = .default

    @OptionGroup(visibility: .hidden)
    var performanceMeasurementOptions: PerformanceMeasurementsOptions

    func run() throws {
      try performanceMeasurementOptions.printingInstructionCountIfRequested {
        let frontend = LintFrontend(
          configurationOptions: configurationOptions,
          lintFormatOptions: lintOptions,
          treatWarningsAsErrors: strict,
          reporter: reporter
        )
        frontend.run()
        frontend.flushDiagnostics()

        if frontend.diagnosticsEngine.hasErrors {
          throw ExitCode.failure
        }
      }
    }
  }
}
