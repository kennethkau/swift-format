//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Dispatch
import Foundation
import SwiftDiagnostics
import SwiftFormat
import SwiftSyntax

/// Unifies the handling of findings from the linter, parsing errors from the syntax parser, and
/// generic errors from the frontend so that they are emitted in a uniform fashion.
final class DiagnosticsEngine {
  /// One diagnostic together with the notes that elaborate it, so a note always follows its
  /// parent diagnostic through buffering and sorting.
  private struct Entry {
    var diagnostic: Diagnostic
    var notes: [Diagnostic]
  }

  /// The handler functions that will be called to process diagnostics that are emitted.
  private let handlers: [(Diagnostic) -> Void]

  /// A Boolean value indicating whether any errors were emitted by the diagnostics engine.
  private(set) var hasErrors: Bool

  /// A Boolean value indicating whether any warnings were emitted by the diagnostics engine.
  private(set) var hasWarnings: Bool

  /// Whether to upgrade all warnings to errors.
  private let treatWarningsAsErrors: Bool

  /// Whether diagnostics are buffered and sorted before being forwarded to the handlers, which
  /// makes the emission order deterministic when files are processed in parallel.
  private let ordered: Bool

  /// Buffered entries awaiting `flush()`, when `ordered` is true.
  private var bufferedEntries: [Entry] = []

  /// Guards `bufferedEntries` and the severity flags when files are processed in parallel.
  private let lock = NSLock()

  /// Creates a new diagnostics engine with the given handlers.
  ///
  /// When `ordered` is true, diagnostics are buffered and forwarded in sorted order by
  /// `flush()` instead of immediately, making output deterministic under parallel processing.
  init(
    diagnosticsHandlers: [(Diagnostic) -> Void],
    treatWarningsAsErrors: Bool = false,
    ordered: Bool = false
  ) {
    self.handlers = diagnosticsHandlers
    self.hasErrors = false
    self.hasWarnings = false
    self.treatWarningsAsErrors = treatWarningsAsErrors
    self.ordered = ordered
  }

  /// Emits the diagnostic, tracking whether it was an error or warning.
  private func emit(_ diagnostic: Diagnostic) {
    record(Entry(diagnostic: diagnostic, notes: []))
  }

  /// Applies the warning-to-error upgrade, updates the severity flags, and buffers or
  /// forwards the entry atomically so notes stay with their finding.
  private func record(_ entry: Entry) {
    var diagnostic = entry.diagnostic
    if treatWarningsAsErrors, diagnostic.severity == .warning {
      diagnostic.severity = .error
    }

    lock.lock()
    switch diagnostic.severity {
    case .error: self.hasErrors = true
    case .warning: self.hasWarnings = true
    default: break
    }
    if ordered {
      bufferedEntries.append(Entry(diagnostic: diagnostic, notes: entry.notes))
      lock.unlock()
      return
    }
    lock.unlock()

    forward(diagnostic)
    for note in entry.notes {
      forward(note)
    }
  }

  /// Passes one diagnostic to the registered handlers.
  private func forward(_ diagnostic: Diagnostic) {
    for handler in handlers {
      handler(diagnostic)
    }
  }

  /// Forwards all buffered diagnostics in sorted order, notes after their findings. Does
  /// nothing when not `ordered`; must be called after all files are processed, and drains the
  /// buffer.
  func flush() {
    guard ordered else {
      return
    }
    lock.lock()
    let entries = bufferedEntries
    bufferedEntries.removeAll()
    lock.unlock()

    // Swift's sort is not guaranteed stable, so the original index breaks ties between
    // diagnostics with the same location, keeping notes after the findings they elaborate.
    let sorted = Array(entries.enumerated())
      .sorted { lhs, rhs in
        if Diagnostic.areInSortedOrder(lhs.element.diagnostic, rhs.element.diagnostic) {
          return true
        }
        if Diagnostic.areInSortedOrder(rhs.element.diagnostic, lhs.element.diagnostic) {
          return false
        }
        return lhs.offset < rhs.offset
      }
      .map(\.element)
    for entry in sorted {
      for handler in handlers {
        handler(entry.diagnostic)
      }
      for note in entry.notes {
        for handler in handlers {
          handler(note)
        }
      }
    }
  }

  /// Emits a generic error message.
  ///
  /// - Parameters:
  ///   - message: The message associated with the error.
  ///   - location: The location in the source code associated with the error, or nil if there is no
  ///     location associated with the error.
  func emitError(_ message: String, location: SourceLocation? = nil) {
    emit(
      Diagnostic(
        severity: .error,
        location: location.map(Diagnostic.Location.init),
        message: message
      )
    )
  }

  /// Emits a generic warning message.
  ///
  /// - Parameters:
  ///   - message: The message associated with the warning.
  ///   - location: The location in the source code associated with the warning, or nil if there
  ///     is no location associated with the warning.
  func emitWarning(_ message: String, location: SourceLocation? = nil) {
    emit(
      Diagnostic(
        severity: .warning,
        location: location.map(Diagnostic.Location.init),
        message: message
      )
    )
  }

  /// Emits a finding from the linter and any of its associated notes as diagnostics.
  ///
  /// - Parameter finding: The finding that should be emitted.
  func consumeFinding(_ finding: Finding) {
    let notes = finding.notes.map { note in
      Diagnostic(
        severity: .note,
        location: note.location.map(Diagnostic.Location.init),
        message: "\(note.message)"
      )
    }
    record(Entry(diagnostic: diagnosticMessage(for: finding), notes: notes))
  }

  /// Emits a diagnostic from the syntax parser and any of its associated notes.
  ///
  /// - Parameter diagnostic: The syntax parser diagnostic that should be emitted.
  func consumeParserDiagnostic(
    _ diagnostic: SwiftDiagnostics.Diagnostic,
    _ location: SourceLocation
  ) {
    emit(diagnosticMessage(for: diagnostic.diagMessage, at: location))
  }

  /// Converts a diagnostic message from the syntax parser into a diagnostic message that can be
  /// used by the diagnostics engine and returns it.
  private func diagnosticMessage(
    for message: SwiftDiagnostics.DiagnosticMessage,
    at location: SourceLocation
  ) -> Diagnostic {
    let severity: Diagnostic.Severity
    switch message.severity {
    case .error: severity = .error
    case .warning: severity = .warning
    case .note: severity = .note
    case .remark: severity = .note  // should we model this?
    }
    return Diagnostic(
      severity: severity,
      location: Diagnostic.Location(location),
      category: nil,
      message: message.message
    )
  }

  /// Converts a lint finding into a diagnostic message that can be used by the `TSCBasic`
  /// diagnostics engine and returns it.
  private func diagnosticMessage(for finding: Finding) -> Diagnostic {
    return Diagnostic(
      severity: .warning,
      location: finding.location.map(Diagnostic.Location.init),
      category: "\(finding.category)",
      message: "\(finding.message.text)"
    )
  }
}
