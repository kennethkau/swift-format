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
import Foundation

/// Renders diagnostics in a machine-readable format for CI systems, selected with the
/// `--reporter` flag. Diagnostics are sorted by file, line, column, severity (notes last),
/// category, and message; each note is kept after the finding it elaborates.
final class DiagnosticReporter {
  /// The available output formats.
  enum Kind: String, CaseIterable, ExpressibleByArgument {
    /// The default human-readable format on standard error.
    case `default`

    /// GitHub Actions workflow commands, printed to standard output as
    /// `::warning file=...,line=...,col=...,title=<category>::<message>` annotations.
    case githubActions = "github-actions"

    /// A JSON array of diagnostic objects, omitting absent `file` and `category` fields.
    case json

    /// One line of user-facing help per kind.
    var helpDescription: String {
      switch self {
      case .default:
        return "Human-readable diagnostics on standard error (the default)."
      case .githubActions:
        return "GitHub Actions annotations on standard output."
      case .json:
        return "A JSON array of diagnostics on standard output."
      }
    }
  }

  /// The selected output format.
  private let kind: Kind

  /// The diagnostics collected since the reporter was created, in the order they were
  /// consumed.
  private var collected: [Diagnostic] = []

  /// Where the rendered report is written.
  private let outputStream: any TextOutputStream

  /// The queue used to synchronize collection when files are processed in parallel.
  private let collectQueue = DispatchQueue(label: "com.apple.swift-format.DiagnosticReporter")

  /// Creates a reporter for the given kind that writes to standard output.
  ///
  /// - Parameter kind: The output format to render. The `.default` kind is not handled here;
  ///   the frontend keeps using the standard error printer for it.
  convenience init(kind: Kind) {
    self.init(kind: kind, outputStream: FileHandleTextOutputStream(FileHandle.standardOutput))
  }

  /// Creates a reporter for the given kind that writes to the given stream.
  ///
  /// - Parameters:
  ///   - kind: The output format to render.
  ///   - outputStream: The stream to which the rendered report is written by `finish()`.
  init(kind: Kind, outputStream: any TextOutputStream) {
    self.kind = kind
    self.outputStream = outputStream
  }

  /// Records a diagnostic for the report.
  ///
  /// - Parameter diagnostic: The diagnostic to include.
  func consume(_ diagnostic: Diagnostic) {
    collectQueue.sync {
      collected.append(diagnostic)
    }
  }

  /// One diagnostic together with the notes that follow it, which must stay adjacent to it in
  /// the rendered report.
  private struct Group {
    var diagnostic: Diagnostic
    var notes: [Diagnostic]
  }

  /// Writes the rendered report, after all diagnostics have been consumed.
  func finish() {
    // `TextOutputStream.write` is mutating, so the stream is copied into a variable; the
    // streams used here are reference-backed classes.
    var stream = outputStream
    // Sorting here (in addition to the diagnostics engine's buffering) keeps the report
    // deterministic even when diagnostics reached the reporter unsorted. The original index
    // breaks any remaining ties (Swift's sort is not guaranteed stable).
    let groups = Array(grouped().enumerated())
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
    switch kind {
    case .default:
      break
    case .githubActions:
      for group in groups {
        stream.write(githubActionsCommand(for: group.diagnostic) + "\n")
        for note in group.notes {
          stream.write(githubActionsCommand(for: note) + "\n")
        }
      }
    case .json:
      let diagnostics = groups.flatMap { group in [group.diagnostic] + group.notes }
      stream.write(renderJSON(diagnostics) + "\n")
    }
  }

  /// Groups the collected diagnostics so that each note follows the diagnostic it elaborates.
  private func grouped() -> [Group] {
    var groups: [Group] = []
    for diagnostic in collected {
      if diagnostic.severity == .note, !groups.isEmpty {
        groups[groups.count - 1].notes.append(diagnostic)
      } else {
        groups.append(Group(diagnostic: diagnostic, notes: []))
      }
    }
    return groups
  }

  // MARK: - GitHub Actions

  /// Renders one diagnostic as a GitHub Actions workflow command.
  private func githubActionsCommand(for diagnostic: Diagnostic) -> String {
    let keyword: String
    switch diagnostic.severity {
    case .error: keyword = "error"
    case .warning: keyword = "warning"
    case .note: keyword = "notice"
    }

    var properties: [String] = []
    if let location = diagnostic.location {
      properties.append("file=\(Self.escapeProperty(location.file))")
      properties.append("line=\(location.line)")
      properties.append("col=\(location.column)")
    }
    if let category = diagnostic.category {
      properties.append("title=\(Self.escapeProperty(category))")
    }

    let propertyText = properties.isEmpty ? "" : " " + properties.joined(separator: ",")
    return "::\(keyword)\(propertyText)::\(Self.escapeMessage(diagnostic.message))"
  }

  /// Escapes a workflow command property value.
  private static func escapeProperty(_ value: String) -> String {
    var escaped = ""
    for scalar in value.unicodeScalars {
      switch scalar {
      case "%": escaped += "%25"
      case "\r": escaped += "%0D"
      case "\n": escaped += "%0A"
      case ":": escaped += "%3A"
      case ",": escaped += "%2C"
      default: escaped.unicodeScalars.append(scalar)
      }
    }
    return escaped
  }

  /// Escapes a workflow command message value.
  private static func escapeMessage(_ value: String) -> String {
    var escaped = ""
    for scalar in value.unicodeScalars {
      switch scalar {
      case "%": escaped += "%25"
      case "\r": escaped += "%0D"
      case "\n": escaped += "%0A"
      default: escaped.unicodeScalars.append(scalar)
      }
    }
    return escaped
  }

  // MARK: - JSON

  /// Renders the collected diagnostics as a JSON array.
  private func renderJSON(_ diagnostics: [Diagnostic]) -> String {
    if diagnostics.isEmpty {
      return "[]"
    }
    let entries = diagnostics.map(renderedEntry).joined(separator: ",")
    return "[\(entries)]"
  }

  /// Renders one diagnostic as a JSON object.
  private func renderedEntry(for diagnostic: Diagnostic) -> String {
    var fields: [String] = []
    fields.append("\"severity\":\(jsonString(severityName(diagnostic.severity)))")
    if let location = diagnostic.location {
      fields.append("\"file\":\(jsonString(location.file))")
      fields.append("\"line\":\(location.line)")
      fields.append("\"column\":\(location.column)")
    }
    if let category = diagnostic.category {
      fields.append("\"category\":\(jsonString(category))")
    }
    fields.append("\"message\":\(jsonString(diagnostic.message))")
    return "{" + fields.joined(separator: ",") + "}"
  }

  /// The JSON name of a diagnostic severity.
  private func severityName(_ severity: Diagnostic.Severity) -> String {
    switch severity {
    case .note: return "note"
    case .warning: return "warning"
    case .error: return "error"
    }
  }

  /// Encodes a string as a JSON string literal, escaping quotes, backslashes, and control
  /// characters.
  private func jsonString(_ value: String) -> String {
    var encoded = "\""
    for scalar in value.unicodeScalars {
      switch scalar {
      case "\"": encoded += "\\\""
      case "\\": encoded += "\\\\"
      case "\n": encoded += "\\n"
      case "\r": encoded += "\\r"
      case "\t": encoded += "\\t"
      default:
        if scalar.value < 0x20 {
          encoded += String(format: "\\u%04x", scalar.value)
        } else {
          encoded.unicodeScalars.append(scalar)
        }
      }
    }
    return encoded + "\""
  }
}
