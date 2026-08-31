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

import SwiftSyntax
import XCTest

@testable import swift_format

/// Tests the machine-readable diagnostic reporters (`--reporter github-actions` and
/// `--reporter json`) and the deterministic, sorted forwarding of buffered diagnostics.
final class LintReporterTests: XCTestCase {
  /// A stream that collects everything written to it, for capturing reporter output.
  private final class TextStringStream: TextOutputStream {
    var output = ""

    func write(_ string: String) {
      output += string
    }
  }

  private func makeDiagnostic(
    severity: Diagnostic.Severity = .warning,
    file: String?,
    line: Int?,
    column: Int?,
    category: String? = "Spacing",
    message: String
  ) -> Diagnostic {
    let location =
      (file.map { file in
        SourceLocation(
          line: line ?? 0,
          column: column ?? 0,
          offset: 0,
          file: file,
          presumedLine: line ?? 0,
          presumedFile: file
        )
      }).map(Diagnostic.Location.init)
    return Diagnostic(
      severity: severity,
      location: location,
      category: category,
      message: message
    )
  }

  // MARK: - JSON reporter

  func testJSONReporterRendersSortedDiagnostics() {
    let stream = TextStringStream()
    let reporter = DiagnosticReporter(kind: .json, outputStream: stream)
    // Consumed out of order: the report must still be sorted by file, line, then column.
    reporter.consume(
      makeDiagnostic(file: "B.swift", line: 2, column: 1, message: "second file")
    )
    reporter.consume(
      makeDiagnostic(file: "A.swift", line: 10, column: 4, message: "later line")
    )
    reporter.consume(
      makeDiagnostic(file: "A.swift", line: 10, column: 2, message: "earlier column")
    )
    reporter.finish()

    XCTAssertEqual(
      stream.output,
      "[{\"severity\":\"warning\",\"file\":\"A.swift\",\"line\":10,\"column\":2,\"category\":\"Spacing\",\"message\":\"earlier column\"},{\"severity\":\"warning\",\"file\":\"A.swift\",\"line\":10,\"column\":4,\"category\":\"Spacing\",\"message\":\"later line\"},{\"severity\":\"warning\",\"file\":\"B.swift\",\"line\":2,\"column\":1,\"category\":\"Spacing\",\"message\":\"second file\"}]\n"
    )
  }

  func testJSONReporterOmitsAbsentFieldsAndEscapesStrings() {
    let stream = TextStringStream()
    let reporter = DiagnosticReporter(kind: .json, outputStream: stream)
    reporter.consume(
      makeDiagnostic(file: nil, line: nil, column: nil, category: nil, message: "a \"quote\" and \\ backslash\nnewline")
    )
    reporter.finish()

    XCTAssertEqual(
      stream.output,
      """
      [{"severity":"warning","message":"a \\"quote\\" and \\\\ backslash\\nnewline"}]

      """
    )
  }

  func testJSONReporterRendersEmptyReport() {
    let stream = TextStringStream()
    let reporter = DiagnosticReporter(kind: .json, outputStream: stream)
    reporter.finish()
    XCTAssertEqual(stream.output, "[]\n")
  }

  func testSortKeysBeyondLocationArePinned() {
    // Four diagnostics chosen so that removing any single sort key beyond file — line,
    // column, severity, or category — inverts the rendered order, while the message key (the
    // final tiebreak) would order each pair the opposite way.
    let stream = TextStringStream()
    let reporter = DiagnosticReporter(kind: .json, outputStream: stream)
    // line key: line 2 sorts before line 1's... no — line 1 first; messages oppose column order.
    reporter.consume(
      makeDiagnostic(file: "A.swift", line: 2, column: 1, message: "aaa")
    )
    reporter.consume(
      makeDiagnostic(file: "A.swift", line: 1, column: 1, message: "zzz")
    )
    // column key: same line, later column first by message would invert.
    reporter.consume(
      makeDiagnostic(file: "B.swift", line: 1, column: 9, message: "aaa")
    )
    reporter.consume(
      makeDiagnostic(file: "B.swift", line: 1, column: 1, message: "zzz")
    )
    reporter.finish()

    let order = stream.output.components(separatedBy: "\"message\":")
    XCTAssertEqual(order.count, 5)
    let messages = [String](order[1...]).map { String($0.dropFirst().prefix(3)) }
    XCTAssertEqual(messages, ["zzz", "aaa", "zzz", "aaa"])
  }

  func testSeverityAndCategoryKeysArePinned() {
    // error before warning at one location, and category Alpha before Zeta, in both cases
    // against the message order.
    let stream = TextStringStream()
    let reporter = DiagnosticReporter(kind: .json, outputStream: stream)
    reporter.consume(
      makeDiagnostic(severity: .warning, file: "A.swift", line: 1, column: 1, message: "aaa")
    )
    reporter.consume(
      makeDiagnostic(severity: .error, file: "A.swift", line: 1, column: 1, message: "zzz")
    )
    reporter.consume(
      makeDiagnostic(file: "B.swift", line: 1, column: 1, category: "Zeta", message: "aaa")
    )
    reporter.consume(
      makeDiagnostic(file: "B.swift", line: 1, column: 1, category: "Alpha", message: "zzz")
    )
    reporter.finish()

    let order = stream.output.components(separatedBy: "\"message\":")
    let messages = [String](order[1...]).map { String($0.dropFirst().prefix(3)) }
    XCTAssertEqual(messages, ["zzz", "aaa", "zzz", "aaa"])
  }

  // MARK: - GitHub Actions reporter

  func testGitHubActionsReporterRendersAnnotations() {
    let stream = TextStringStream()
    let reporter = DiagnosticReporter(kind: .githubActions, outputStream: stream)
    reporter.consume(
      makeDiagnostic(file: "A.swift", line: 3, column: 5, message: "add 1 space")
    )
    reporter.consume(
      makeDiagnostic(
        severity: .error,
        file: "A.swift",
        line: 4,
        column: 1,
        category: nil,
        message: "invalid syntax"
      )
    )
    reporter.finish()

    XCTAssertEqual(
      stream.output,
      "::warning file=A.swift,line=3,col=5,title=Spacing::add 1 space\n"
        + "::error file=A.swift,line=4,col=1::invalid syntax\n"
    )
  }

  func testGitHubActionsReporterEscapesWorkflowCommandSyntax() {
    let stream = TextStringStream()
    let reporter = DiagnosticReporter(kind: .githubActions, outputStream: stream)
    reporter.consume(
      makeDiagnostic(file: "A,B.swift", line: 1, column: 1, message: "100% done: really\n")
    )
    reporter.finish()

    XCTAssertEqual(
      stream.output,
      "::warning file=A%2CB.swift,line=1,col=1,title=Spacing::100%25 done: really%0A\n"
    )
  }

  // MARK: - JSON reporter (notes grouping)

  func testJSONReporterKeepsNotesAfterTheirFinding() {
    let stream = TextStringStream()
    let reporter = DiagnosticReporter(kind: .json, outputStream: stream)
    reporter.consume(
      makeDiagnostic(file: "A.swift", line: 5, column: 1, message: "the finding")
    )
    // The note sits at an earlier location but must render after its finding.
    reporter.consume(
      makeDiagnostic(severity: .note, file: "A.swift", line: 2, column: 3, category: nil, message: "a note")
    )
    reporter.finish()

    XCTAssertEqual(
      stream.output,
      "[{\"severity\":\"warning\",\"file\":\"A.swift\",\"line\":5,\"column\":1,\"category\":\"Spacing\",\"message\":\"the finding\"},{\"severity\":\"note\",\"file\":\"A.swift\",\"line\":2,\"column\":3,\"message\":\"a note\"}]\n"
    )
  }

  func testSameLocationFindingsAreOrderedByMessage() {
    let stream = TextStringStream()
    let reporter = DiagnosticReporter(kind: .json, outputStream: stream)
    reporter.consume(
      makeDiagnostic(file: "A.swift", line: 1, column: 1, category: "Same", message: "second")
    )
    reporter.consume(
      makeDiagnostic(file: "A.swift", line: 1, column: 1, category: "Same", message: "first")
    )
    reporter.finish()

    let firstIndex = stream.output.range(of: "\"first\"")
    let secondIndex = stream.output.range(of: "\"second\"")
    XCTAssertNotNil(firstIndex)
    XCTAssertNotNil(secondIndex)
    XCTAssertLessThan(firstIndex!.lowerBound, secondIndex!.lowerBound)
  }

  func testGitHubActionsReporterRendersNotesAsNoticesAfterTheirFinding() {
    let stream = TextStringStream()
    let reporter = DiagnosticReporter(kind: .githubActions, outputStream: stream)
    reporter.consume(
      makeDiagnostic(file: "A.swift", line: 5, column: 5, message: "the finding")
    )
    reporter.consume(
      makeDiagnostic(severity: .note, file: "A.swift", line: 2, column: 3, category: nil, message: "a note")
    )
    reporter.finish()

    XCTAssertEqual(
      stream.output,
      "::warning file=A.swift,line=5,col=5,title=Spacing::the finding\n"
        + "::notice file=A.swift,line=2,col=3::a note\n"
    )
  }

  func testOrderedEngineUpgradesWarningsToErrors() {
    var forwarded: [Diagnostic] = []
    let engine = DiagnosticsEngine(
      diagnosticsHandlers: [{ forwarded.append($0) }],
      treatWarningsAsErrors: true,
      ordered: true
    )

    engine.emitWarning("strict", location: nil)
    engine.flush()

    XCTAssertEqual(forwarded.map(\.severity), [.error])
  }

  func testSecondFlushForwardsNothing() {
    var forwarded: [Diagnostic] = []
    let engine = DiagnosticsEngine(
      diagnosticsHandlers: [{ forwarded.append($0) }],
      ordered: true
    )

    engine.emitWarning("only", location: nil)
    engine.flush()
    engine.flush()

    XCTAssertEqual(forwarded.map(\.message), ["only"])
  }

  func testFrontendWiresSelectedReporter() throws {
    let command = try SwiftFormatCommand.Lint.parse(["--reporter", "json", "-"])
    let frontend = LintFrontend(
      configurationOptions: command.configurationOptions,
      lintFormatOptions: command.lintOptions,
      treatWarningsAsErrors: command.strict,
      reporter: command.reporter
    )
    XCTAssertNotNil(frontend.diagnosticReporter)

    let defaultCommand = try SwiftFormatCommand.Lint.parse(["-"])
    let defaultFrontend = LintFrontend(
      configurationOptions: defaultCommand.configurationOptions,
      lintFormatOptions: defaultCommand.lintOptions,
      treatWarningsAsErrors: defaultCommand.strict,
      reporter: defaultCommand.reporter
    )
    XCTAssertNil(defaultFrontend.diagnosticReporter)
  }

  // MARK: - Deterministic engine forwarding

  func testOrderedEngineSortsDiagnosticsOnFlush() {
    var forwarded: [Diagnostic] = []
    let engine = DiagnosticsEngine(
      diagnosticsHandlers: [{ forwarded.append($0) }],
      ordered: true
    )

    engine.emitWarning("second", location: SourceLocation(line: 10, column: 1, offset: 0, file: "A.swift"))
    engine.emitWarning("first", location: SourceLocation(line: 2, column: 1, offset: 0, file: "A.swift"))
    engine.emitWarning("other file", location: SourceLocation(line: 1, column: 1, offset: 0, file: "B.swift"))

    // Nothing is forwarded until the flush.
    XCTAssertTrue(forwarded.isEmpty)
    engine.flush()

    XCTAssertEqual(forwarded.map(\.message), ["first", "second", "other file"])
  }

  func testUnorderedEngineForwardsImmediately() {
    var forwarded: [Diagnostic] = []
    let engine = DiagnosticsEngine(
      diagnosticsHandlers: [{ forwarded.append($0) }],
      ordered: false
    )

    engine.emitWarning("only", location: nil)
    XCTAssertEqual(forwarded.map(\.message), ["only"])
    engine.flush()
    XCTAssertEqual(forwarded.map(\.message), ["only"])
  }

  func testReporterKindParsesFromArguments() {
    XCTAssertEqual(DiagnosticReporter.Kind(argument: "github-actions"), .githubActions)
    XCTAssertEqual(DiagnosticReporter.Kind(argument: "json"), .json)
    XCTAssertEqual(DiagnosticReporter.Kind(argument: "default"), .default)
    XCTAssertNil(DiagnosticReporter.Kind(argument: "sarif"))
  }
}
