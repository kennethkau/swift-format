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

/// Normalizes the layout of `///` doc comments without touching their prose.
///
/// Four normalizations are applied to every run of doc line comments: at least one space
/// separates `///` from the text of a non-empty line (a line glued as `///text` gains one);
/// runs of two or more blank doc lines collapse to a single blank doc line, and a trailing
/// blank doc line is removed; dashed list items are aligned — an item whose name is a
/// documented DocC field (for example `- Parameters:`) is written with exactly one space
/// before the dash, and any other dashed item (for example a parameter entry under
/// `- Parameters:`) with exactly three; and trailing whitespace is stripped from every
/// non-code-block line. Lines indented by four or more spaces are indented code blocks and pass
/// through unchanged, blank lines and trailing whitespace included. The words of the comment
/// are never rewrapped, reordered, or otherwise changed, and block doc comments (`/** */`) are
/// left to the `UseTripleSlashForDocumentationComments` rule.
///
/// Lint: A doc comment that differs from its normalized form yields one lint error.
///
/// Format: The doc comment is rewritten to its normalized form.
@_spi(Rules)
public final class CanonicalDocComments: SyntaxFormatRule {
  public override class var isOptIn: Bool { return true }

  /// Field names whose dashed items sit at the top level of a doc comment rather than nested
  /// under one — the documented DocC fields, singular and plural forms alike.
  private static let topLevelFields: Set<String> = [
    "Attention", "Author", "Authors", "Bug", "Bugs", "Complexity", "Copyright", "Date",
    "Experiment", "Important", "Invariant", "LocalizationKey", "Metadata", "Note",
    "Parameter", "Parameters", "Postcondition", "Precondition", "Remark", "Remarks",
    "Requires", "Returns", "SeeAlso", "Since", "Tag", "Throws", "Todo", "Version", "Warning",
  ]

  public override func visit(_ token: TokenSyntax) -> TokenSyntax {
    guard token.leadingTrivia.contains(where: { $0.isDocLineComment }) else {
      return token
    }

    let (rewritten, changed) = Self.normalizingDocComments(in: Array(token.leadingTrivia))
    guard changed else {
      return token
    }
    diagnose(.normalizeDocComment, on: token)
    return token.with(\.leadingTrivia, Trivia(pieces: rewritten))
  }

  /// One line of a doc comment run: the newline piece that preceded it (nil for the run's first
  /// line), the whitespace between that newline and the `///`, and the line's text. The
  /// separator and indentation are carried through the rewrite unchanged, so a CR LF file keeps
  /// CR LF line endings inside its doc comments and each surviving line keeps its own
  /// indentation.
  fileprivate struct DocLine {
    var separator: TriviaPiece?
    var indentation: [TriviaPiece]
    var text: String
  }

  /// Returns the trivia with every doc comment run normalized, and whether anything changed.
  private static func normalizingDocComments(
    in pieces: [TriviaPiece]
  ) -> (pieces: [TriviaPiece], changed: Bool) {
    var result: [TriviaPiece] = []
    result.reserveCapacity(pieces.count)
    var changed = false
    var index = 0

    while index < pieces.count {
      guard case .docLineComment(let text) = pieces[index] else {
        result.append(pieces[index])
        index += 1
        continue
      }

      // Gather the maximal run of doc lines separated by single line endings, keeping each
      // line's separator and indentation so the rewritten run keeps them.
      var lines = [DocLine(separator: nil, indentation: [], text: text)]
      lines.reserveCapacity(4)
      var cursor = index + 1
      loop: while cursor < pieces.count {
        guard let separator = pieces[cursor].singleLineEnding else {
          break loop
        }
        var next = cursor + 1
        var indentation = [TriviaPiece]()
        while next < pieces.count, pieces[next].isSpaceOrTab {
          indentation.append(pieces[next])
          next += 1
        }
        guard next < pieces.count, case .docLineComment(let line) = pieces[next] else {
          break loop
        }
        lines.append(DocLine(separator: separator, indentation: indentation, text: line))
        cursor = next + 1
      }

      let normalized = normalizing(lines: lines)
      changed = changed || normalized.map(\.text) != lines.map(\.text)
      for line in normalized {
        if let separator = line.separator {
          result.append(separator)
        }
        result.append(contentsOf: line.indentation)
        result.append(.docLineComment(line.text))
      }
      index = cursor
    }

    return (result, changed)
  }

  /// Returns the normalized doc lines, keeping each surviving line's own separator and
  /// indentation. Indented code blocks — and blank lines inside them — are content and pass
  /// through unchanged; the code block ends at the first non-blank line indented by less than
  /// four spaces.
  private static func normalizing(lines: [DocLine]) -> [DocLine] {
    var normalized: [DocLine] = []
    var previousWasBlank = false
    var inCodeBlock = false
    for line in lines {
      if isCodeBlockLine(line.text) {
        normalized.append(line)
        previousWasBlank = false
        inCodeBlock = true
        continue
      }
      let canonical = normalizing(line: line.text)
      var content = line
      content.text = canonical
      if isBlank(canonical) {
        if inCodeBlock {
          normalized.append(content)
          continue
        }
        if previousWasBlank {
          continue
        }
        normalized.append(content)
        previousWasBlank = true
      } else {
        inCodeBlock = false
        normalized.append(content)
        previousWasBlank = false
      }
    }
    // A doc comment never ends with a blank line.
    while normalized.count > 1, isBlank(normalized.last!.text) {
      normalized.removeLast()
    }
    return normalized
  }

  /// Returns the canonical form of one doc line. Lines indented by four or more spaces are
  /// indented code blocks in the rendered documentation and are returned unchanged — a dash
  /// inside one is content, not a list item.
  private static func normalizing(line: String) -> String {
    let body = line.dropFirst(3)
    let indentation = body.prefix { $0 == " " || $0 == "\t" }
    if indentation.count >= 4 {
      return line
    }

    var withoutTrailing = Substring(body)
    while let last = withoutTrailing.last, last == " " || last == "\t" {
      withoutTrailing = withoutTrailing.dropLast()
    }

    guard !withoutTrailing.isEmpty else {
      return "///"
    }

    let content = withoutTrailing.dropFirst(indentation.count)

    if content.hasPrefix("- ") {
      let item = content.dropFirst(2)
      let name = item.prefix { $0 != ":" && $0 != " " }
      if topLevelFields.contains(String(name)) {
        return "/// - \(item)"
      } else {
        return "///   - \(item)"
      }
    }

    if indentation.isEmpty {
      return "/// \(content)"
    }
    return "///\(withoutTrailing)"
  }

  private static func isBlank(_ line: String) -> Bool {
    line == "///"
  }

  /// Returns whether the doc line belongs to an indented code block: indented by four or more
  /// spaces after the slashes.
  private static func isCodeBlockLine(_ line: String) -> Bool {
    line.dropFirst(3).prefix { $0 == " " || $0 == "\t" }.count >= 4
  }
}

extension TriviaPiece {
  fileprivate var isDocLineComment: Bool {
    if case .docLineComment = self {
      return true
    }
    return false
  }

  /// Returns the piece if it is a newline piece denoting exactly one line ending, otherwise nil.
  fileprivate var singleLineEnding: TriviaPiece? {
    switch self {
    case .newlines(1), .carriageReturns(1), .carriageReturnLineFeeds(1):
      return self
    default:
      return nil
    }
  }
}

extension Finding.Message {
  fileprivate static let normalizeDocComment: Finding.Message =
    "normalize this doc comment's layout"
}
