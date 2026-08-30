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

/// Computes line-based unified diffs (the format printed by `diff -u` and understood by most code
/// review tools), used by `swift-format format --diff`.
@_spi(Internal) public enum UnifiedDiff {

  /// A line of text together with whether a newline terminates it.
  ///
  /// Termination is part of a line's identity: in the unified diff format `x` and `x` followed by
  /// a newline are different lines. An unterminated final line therefore never matches a
  /// terminated one, so a one-sided trailing-newline change diffs as a line replacement with the
  /// `\ No newline at end of file` marker on the correct side, and a marker never lands on a
  /// shared context line where it would apply to both sides.
  fileprivate struct Line: Equatable {
    var text: String
    var terminated: Bool
  }

  /// A single line-level operation in a diff.
  fileprivate enum Operation {
    case equal(Line)
    case deleted(Line)
    case inserted(Line)

    var isEqual: Bool {
      if case .equal = self { return true }
      return false
    }

    /// Whether this operation consumes a line from the old text.
    var isOldLine: Bool {
      switch self {
      case .equal, .deleted: return true
      case .inserted: return false
      }
    }

    /// Whether this operation consumes a line from the new text.
    var isNewLine: Bool {
      switch self {
      case .equal, .inserted: return true
      case .deleted: return false
      }
    }
  }

  /// A contiguous group of operations printed under a single `@@` header.
  fileprivate struct Hunk {
    var operations: [Operation] = []
    /// The zero-based index of the hunk's first line in the old text.
    var oldStart = 0
    /// The zero-based index of the hunk's first line in the new text.
    var newStart = 0
  }

  /// The maximum number of cells in the LCS table before falling back to a single whole-range
  /// replacement hunk, which bounds the memory used for pathological inputs.
  private static let maximumLCSCells = 2_000_000

  /// Returns a unified diff describing how to transform `from` into `to`, or an empty string if
  /// they are equal.
  ///
  /// - Parameters:
  ///   - from: The original text.
  ///   - to: The revised text.
  ///   - fromPath: The path label printed in the `---` header (e.g. `a/Sources/File.swift`).
  ///   - toPath: The path label printed in the `+++` header (e.g. `b/Sources/File.swift`).
  ///   - contextLines: The number of unchanged lines of context to print around each change.
  public static func diff(
    from: String,
    to: String,
    fromPath: String,
    toPath: String,
    contextLines: Int = 3
  ) -> String {
    if from == to { return "" }
    let oldLines = lines(from)
    let newLines = lines(to)

    // Trim the common prefix and suffix so the LCS only covers the changed middle; formatter
    // diffs are typically localized, which keeps the table small.
    var prefix = 0
    while prefix < oldLines.count && prefix < newLines.count && oldLines[prefix] == newLines[prefix] {
      prefix += 1
    }
    var suffix = 0
    while suffix < oldLines.count - prefix && suffix < newLines.count - prefix
      && oldLines[oldLines.count - 1 - suffix] == newLines[newLines.count - 1 - suffix]
    {
      suffix += 1
    }

    // Build the ordered operation list for the core, then stitch the untouched prefix and suffix
    // back in as equal lines.
    let oldCore = Array(oldLines[prefix..<(oldLines.count - suffix)])
    let newCore = Array(newLines[prefix..<(newLines.count - suffix)])
    var operations = oldLines[0..<prefix].map { Operation.equal($0) }
    operations.append(contentsOf: coreOperations(oldCore: oldCore, newCore: newCore))
    operations.append(
      contentsOf: (0..<suffix).map { .equal(oldLines[oldLines.count - suffix + $0]) }
    )

    var result = "--- \(fromPath)\n+++ \(toPath)\n"
    for hunk in hunks(over: operations, contextLines: contextLines) {
      let oldCount = hunk.operations.reduce(0) { $0 + ($1.isOldLine ? 1 : 0) }
      let newCount = hunk.operations.reduce(0) { $0 + ($1.isNewLine ? 1 : 0) }
      // Per the unified diff format, an empty range starts at the line *before* the hunk.
      let oldStart = hunk.oldStart + (oldCount == 0 ? 0 : 1)
      let newStart = hunk.newStart + (newCount == 0 ? 0 : 1)
      result += "@@ -\(oldStart),\(oldCount) +\(newStart),\(newCount) @@\n"
      for operation in hunk.operations {
        switch operation {
        case .equal(let line):
          result += " \(line.text)\n"
          if !line.terminated { result += "\\ No newline at end of file\n" }
        case .deleted(let line):
          result += "-\(line.text)\n"
          if !line.terminated { result += "\\ No newline at end of file\n" }
        case .inserted(let line):
          result += "+\(line.text)\n"
          if !line.terminated { result += "\\ No newline at end of file\n" }
        }
      }
    }
    return result
  }

  /// Splits text into lines whose identity includes newline termination.
  ///
  /// Splitting happens below the grapheme-cluster level so that a CR LF pair terminates the line
  /// while the CR stays part of the line's content — a CRLF file therefore differs from its LF
  /// counterpart on every line, which is what `--check` (a byte comparison) reports and what
  /// makes the emitted patches applicable. A trailing newline terminates the final line rather
  /// than starting an empty final line.
  private static func lines(_ text: String) -> [Line] {
    // Split on the newline scalar directly: `components(separatedBy: "\n")` treats a CR LF pair
    // as a single grapheme cluster on some platforms and would not split CRLF text at all.
    guard !text.isEmpty else { return [] }
    var pieces = [String]()
    var current = String()
    for scalar in text.unicodeScalars {
      if scalar == "\n" {
        pieces.append(current)
        current = String()
      } else {
        current.unicodeScalars.append(scalar)
      }
    }
    let lastIsTerminated = text.unicodeScalars.last == "\n"
    if !current.isEmpty || !lastIsTerminated {
      pieces.append(current)
    }
    return pieces.enumerated().map { index, piece in
      // Every piece except the last is followed by a separator and therefore terminated.
      Line(text: piece, terminated: index < pieces.count - 1 || lastIsTerminated)
    }
  }

  /// Computes the ordered edit operations transforming `oldCore` into `newCore`.
  private static func coreOperations(oldCore: [Line], newCore: [Line]) -> [Operation] {
    if oldCore.isEmpty {
      return newCore.map { .inserted($0) }
    }
    if newCore.isEmpty {
      return oldCore.map { .deleted($0) }
    }

    let width = newCore.count + 1
    if oldCore.count * width > maximumLCSCells {
      // Fall back to replacing the whole core rather than allocating a pathological table.
      return oldCore.map { .deleted($0) } + newCore.map { .inserted($0) }
    }

    // table[i * width + j] is the LCS length of oldCore[i...] and newCore[j...].
    var table = [Int](repeating: 0, count: (oldCore.count + 1) * width)
    for i in stride(from: oldCore.count - 1, through: 0, by: -1) {
      for j in stride(from: newCore.count - 1, through: 0, by: -1) {
        table[i * width + j] =
          oldCore[i] == newCore[j]
          ? table[(i + 1) * width + (j + 1)] + 1
          : max(table[(i + 1) * width + j], table[i * width + (j + 1)])
      }
    }

    var operations: [Operation] = []
    var i = 0
    var j = 0
    while i < oldCore.count && j < newCore.count {
      if oldCore[i] == newCore[j] {
        operations.append(.equal(oldCore[i]))
        i += 1
        j += 1
      } else if table[(i + 1) * width + j] >= table[i * width + (j + 1)] {
        operations.append(.deleted(oldCore[i]))
        i += 1
      } else {
        operations.append(.inserted(newCore[j]))
        j += 1
      }
    }
    while i < oldCore.count {
      operations.append(.deleted(oldCore[i]))
      i += 1
    }
    while j < newCore.count {
      operations.append(.inserted(newCore[j]))
      j += 1
    }
    return operations
  }

  /// Groups operations into hunks with up to `contextLines` equal lines around each run of
  /// changes, merging runs separated by no more than twice that many equal lines.
  private static func hunks(over operations: [Operation], contextLines: Int) -> [Hunk] {
    guard operations.contains(where: { !$0.isEqual }) else { return [] }

    // Precompute the old/new line index at which each operation starts.
    var oldIndices = [Int](repeating: 0, count: operations.count)
    var newIndices = [Int](repeating: 0, count: operations.count)
    var oldIndex = 0
    var newIndex = 0
    for (position, operation) in operations.enumerated() {
      oldIndices[position] = oldIndex
      newIndices[position] = newIndex
      switch operation {
      case .equal:
        oldIndex += 1
        newIndex += 1
      case .deleted:
        oldIndex += 1
      case .inserted:
        newIndex += 1
      }
    }

    // Find clusters of changes, merging clusters separated by at most 2 * contextLines equal
    // operations (their surrounding contexts would touch or overlap).
    var clusters = [Range<Int>]()
    var clusterStart: Int? = nil
    var lastChange = -1
    for (position, operation) in operations.enumerated() where !operation.isEqual {
      if let start = clusterStart, position - lastChange - 1 > 2 * contextLines {
        clusters.append(start..<lastChange + 1)
        clusterStart = position
      } else if clusterStart == nil {
        clusterStart = position
      }
      lastChange = position
    }
    if let start = clusterStart {
      clusters.append(start..<lastChange + 1)
    }

    return clusters.map { cluster in
      let lead = min(contextLines, cluster.lowerBound)
      let leadStart = cluster.lowerBound - lead

      var trail = 0
      var position = cluster.upperBound
      while trail < contextLines && position < operations.count && operations[position].isEqual {
        trail += 1
        position += 1
      }

      var hunk = Hunk()
      hunk.operations = Array(operations[leadStart..<(cluster.upperBound + trail)])
      hunk.oldStart = oldIndices[leadStart]
      hunk.newStart = newIndices[leadStart]
      return hunk
    }
  }
}
