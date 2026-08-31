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

/// Enforces a canonical file header comment block.
///
/// The header text is supplied as `fileHeader.template`; each template line is written as a `//`
/// line comment. The only placeholder is `{file}`, replaced with the name (without extension) of
/// the file being formatted; date- and environment-derived placeholders are unsupported because
/// they would make the output depend on when or where the tool runs.
///
/// A leading comment block that differs from the rendered template is replaced; a file with no
/// leading comment block gets the header inserted at the top, after any non-comment trivia (a
/// byte-order marker stays at offset 0). Documentation comments (`///` and `/** */`) are never
/// treated as header material. A written header is followed by a blank line; a header that
/// already matches the template is left untouched, even when no blank line follows it. A file
/// with no statements — including one containing only comments — is left alone.
///
/// Lint: A file whose leading comment block differs from `fileHeader.template` — or that has
///       none — yields a lint error.
///
/// Format: The leading comment block is replaced with — or the rendered template is inserted as —
///         the file header.
@_spi(Rules)
public final class FileHeader: SyntaxFormatRule {
  public override class var isOptIn: Bool { return true }

  public override func visit(_ node: SourceFileSyntax) -> SourceFileSyntax {
    guard let template = context.configuration.fileHeader.template else { return node }
    // Trivia is attached to the first statement; a file with no statements (including one that
    // contains only comments) has nothing for the rule to rewrite.
    guard !node.statements.isEmpty else { return node }

    let expectedLines = render(template)
    // An empty template specifies no header, like a missing one.
    guard !expectedLines.isEmpty else { return node }
    let expectedComments = expectedLines.map { $0.isEmpty ? "//" : "// \($0)" }

    let leading = Array(node.statements.leadingTrivia)

    // Split the leading trivia into the pieces that precede the header block (kept verbatim),
    // the contiguous comment block that the rule owns, and the trailing remainder. The block
    // ends at the first blank line — including one containing only whitespace — at a
    // documentation comment, or at any other non-comment, non-whitespace piece, so only a
    // comment block at the very top of the file is rewritten.
    var prefix = [TriviaPiece]()
    var blockEnd: Int? = nil
    var sawComment = false
    var sawLineEndFollowedByOnlyWhitespace = false

    var index = 0
    while index < leading.count, blockEnd == nil {
      let piece = leading[index]
      switch piece {
      case .spaces, .tabs:
        if !sawComment {
          prefix.append(piece)
        }
      case .lineComment, .blockComment:
        sawComment = true
        sawLineEndFollowedByOnlyWhitespace = false
      case .newlines(let count), .carriageReturns(let count), .carriageReturnLineFeeds(let count):
        if !sawComment {
          prefix.append(piece)
        } else if count > 1 || sawLineEndFollowedByOnlyWhitespace {
          blockEnd = index
          break
        }
        sawLineEndFollowedByOnlyWhitespace = true
      default:
        // Documentation comments and unexpected content (e.g. a byte-order marker) are not
        // header material; the block, if any, ends before them.
        blockEnd = index
        break
      }
      index += 1
    }

    // The block extends either to the recorded boundary or to the end of the leading trivia.
    let end = blockEnd ?? leading.count
    if sawComment, let currentComments = commentTexts(in: leading[..<end]),
      currentComments == expectedComments
    {
      // The header is already canonical; leave the file untouched so the rule is idempotent.
      return node
    }

    var headerPieces = [TriviaPiece]()
    for comment in expectedComments {
      headerPieces.append(.lineComment(comment))
      headerPieces.append(.newlines(1))
    }
    // A blank line separates the header from the code that follows.
    headerPieces.append(.newlines(1))

    // Blank lines above the header are dropped, matching the insert branch below.
    while let last = prefix.last, Self.isNewlineRun(last) {
      prefix.removeLast()
    }

    var newNode = node
    if sawComment {
      // Replace the old block; the replacement supplies its own blank-line separator, so one
      // following newline run is dropped.
      var remainder = Array(leading[end...])
      if let first = remainder.first, Self.isNewlineRun(first) {
        remainder.removeFirst()
      }
      newNode.statements.leadingTrivia = Trivia(pieces: prefix + headerPieces + remainder)
      diagnose(.replaceFileHeader, on: node.statements)
    } else {
      // Keep non-whitespace leading content (e.g. a byte-order marker) ahead of the inserted
      // header so a marker stays at offset 0, and drop blank lines that preceded the old top of
      // the file.
      var leadingContent = [TriviaPiece]()
      var remainder = [TriviaPiece]()
      for piece in leading {
        switch piece {
        case .spaces, .tabs, .newlines, .carriageReturns, .carriageReturnLineFeeds,
          .lineComment, .blockComment, .docLineComment, .docBlockComment:
          remainder.append(piece)
        default:
          leadingContent.append(piece)
        }
      }
      while let first = remainder.first, Self.isNewlineRun(first) {
        remainder.removeFirst()
      }
      newNode.statements.leadingTrivia = Trivia(pieces: leadingContent + headerPieces + remainder)
      diagnose(.addFileHeader, on: node.statements)
    }
    return newNode
  }

  /// Extracts the raw text of each line comment in the given trivia range, or `nil` when it
  /// contains a block comment (which can never match a line-comment header and is replaced
  /// wholesale).
  private func commentTexts(in pieces: ArraySlice<TriviaPiece>) -> [String]? {
    var texts = [String]()
    for piece in pieces {
      switch piece {
      case .lineComment(let text):
        texts.append(text)
      case .blockComment:
        return nil
      default:
        break
      }
    }
    return texts
  }

  /// Splits the template into lines, substituting `{file}` with the name of the file being
  /// formatted; a single trailing empty line — from a trailing newline in the template — is
  /// dropped.
  private func render(_ template: String) -> [String] {
    let fileName = context.fileURL.deletingPathExtension().lastPathComponent
    var lines =
      template
      .split(separator: "\n", omittingEmptySubsequences: false)
      .map { String($0).replacingOccurrences(of: "{file}", with: fileName) }
    if lines.last == "" {
      lines.removeLast()
    }
    return lines
  }

  private static func isNewlineRun(_ piece: TriviaPiece) -> Bool {
    switch piece {
    case .newlines, .carriageReturns, .carriageReturnLineFeeds:
      return true
    default:
      return false
    }
  }
}

extension Finding.Message {
  fileprivate static let addFileHeader: Finding.Message = "add the configured file header"
  fileprivate static let replaceFileHeader: Finding.Message =
    "replace this file header with the configured one"
}
