//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import SwiftDiagnostics
import SwiftOperators
import SwiftSyntax

/// Formats Swift source code or syntax trees according to the Swift style guidelines.
public final class SwiftFormatter {

  /// The configuration settings that control the formatter's behavior.
  public let configuration: Configuration

  /// An optional callback that will be notified with any findings encountered during formatting.
  public let findingConsumer: ((Finding) -> Void)?

  /// Advanced options that are useful when debugging the formatter's behavior but are not meant for
  /// general use.
  public var debugOptions: DebugOptions = []

  /// The maximum number of formatting passes performed when `iterateToFixpoint` is enabled.
  ///
  /// Convergence is normally reached in one or two passes; the limit exists so that pathological
  /// non-convergence surfaces as an error instead of looping forever.
  private static let maximumFixpointIterations = 10

  /// Creates a new Swift code formatter with the given configuration.
  ///
  /// - Parameters:
  ///   - configuration: The configuration settings that control the formatter's behavior.
  ///   - findingConsumer: An optional callback that will be notified with any findings encountered
  ///     during formatting. Unlike the `Linter` API, this defaults to nil for formatting because
  ///     findings are typically less useful than the final formatted output.
  public init(configuration: Configuration, findingConsumer: ((Finding) -> Void)? = nil) {
    self.configuration = configuration
    self.findingConsumer = findingConsumer
  }

  /// Formats the Swift code at the given file URL and writes the result to an output stream.
  ///
  /// This form of the `format` function automatically folds expressions using the default operator
  /// set defined in Swift. If you need more control over this—for example, to provide the correct
  /// precedence relationships for custom operators—you must parse and fold the syntax tree
  /// manually and then call ``format(syntax:source:operatorTable:assumingFileURL:selection:to:)``.
  ///
  /// - Parameters:
  ///   - url: The URL of the file containing the code to format.
  ///   - outputStream: A value conforming to `TextOutputStream` to which the formatted output will
  ///     be written.
  ///   - parsingDiagnosticHandler: An optional callback that will be notified if there are any
  ///     errors when parsing the source code. Source that does not parse is rejected whether or
  ///     not a handler is installed; the handler only controls whether diagnostics are reported.
  /// - Throws: If an unrecoverable error occurs when formatting the code.
  public func format<Output: TextOutputStream>(
    contentsOf url: URL,
    to outputStream: inout Output,
    parsingDiagnosticHandler: ((Diagnostic, SourceLocation) -> Void)? = nil
  ) throws {
    guard FileManager.default.isReadableFile(atPath: url.path) else {
      throw SwiftFormatError.fileNotReadable
    }
    var isDir: ObjCBool = false
    if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
      throw SwiftFormatError.isDirectory
    }

    try format(
      source: String(contentsOf: url, encoding: .utf8),
      assumingFileURL: url,
      selection: .infinite,
      to: &outputStream,
      parsingDiagnosticHandler: parsingDiagnosticHandler
    )
  }

  /// Formats the given Swift source code and writes the result to an output stream.
  ///
  /// This form of the `format` function automatically folds expressions using the default operator
  /// set defined in Swift. If you need more control over this—for example, to provide the correct
  /// precedence relationships for custom operators—you must parse and fold the syntax tree
  /// manually and then call ``format(syntax:source:operatorTable:assumingFileURL:selection:to:)``.
  ///
  /// - Parameters:
  ///   - source: The Swift source code to be formatted.
  ///   - url: A file URL denoting the filename/path that should be assumed for this syntax tree,
  ///     which is associated with any diagnostics emitted during formatting. If this is nil, a
  ///     dummy value will be used.
  ///   - selection: The ranges to format
  ///   - experimentalFeatures: The set of experimental features that should be enabled in the
  ///     parser. These names must be from the set of parser-recognized experimental language
  ///     features in `SwiftParser`'s `Parser.LanguageFeatures` enum, which match the spelling
  ///     defined in the compiler's `Features.def` file.
  ///   - outputStream: A value conforming to `TextOutputStream` to which the formatted output will
  ///     be written.
  ///   - parsingDiagnosticHandler: An optional callback that will be notified if there are any
  ///     errors when parsing the source code. Source that does not parse is rejected whether or
  ///     not a handler is installed; the handler only controls whether diagnostics are reported.
  /// - Throws: If an unrecoverable error occurs when formatting the code.
  public func format<Output: TextOutputStream>(
    source: String,
    assumingFileURL url: URL?,
    selection: Selection,
    experimentalFeatures: Set<String> = [],
    to outputStream: inout Output,
    parsingDiagnosticHandler: ((Diagnostic, SourceLocation) -> Void)? = nil
  ) throws {
    // If the file or input string is completely empty, do nothing. This prevents even a trailing
    // newline from being emitted for an empty file. (This is consistent with clang-format, which
    // also does not touch an empty file even if the setting to add trailing newlines is enabled.)
    guard !source.isEmpty else { return }

    // When `iterateToFixpoint` is enabled, the format pass — rules plus pretty printing — is
    // repeated until the output stops changing, so that interactions between rules cannot
    // produce output that changes again when formatted a second time. Line/offset selections are
    // excluded because their ranges are not valid for the formatted text of later passes.
    var canIterate = false
    if case .infinite = selection {
      canIterate = true
    }
    let maximumPasses =
      configuration.iterateToFixpoint && canIterate
      ? Self.maximumFixpointIterations
      : 1

    var currentSource = source
    // Findings are collected per pass and replayed only from the pass whose output is returned,
    // so a consumer never receives the same finding once per fixpoint pass.
    var passFindings: [Finding] = []
    let passFindingSink: ((Finding) -> Void)? = findingConsumer.map { _ in
      { passFindings.append($0) }
    }

    for pass in 1...maximumPasses {
      passFindings.removeAll(keepingCapacity: true)

      // The first pass reports parser diagnostics for the user's input to the caller's handler.
      // Later passes run on formatter-generated text, which must parse cleanly; if it does not,
      // the formatter itself is at fault and the error says so instead of the pass silently
      // formatting a recovery tree.
      let sourceFile: SourceFileSyntax
      do {
        sourceFile = try parseAndEmitDiagnostics(
          source: currentSource,
          operatorTable: .standardOperators,
          assumingFileURL: url,
          experimentalFeatures: experimentalFeatures,
          parsingDiagnosticHandler: pass == 1 ? parsingDiagnosticHandler : nil
        )
      } catch SwiftFormatError.fileContainsInvalidSyntax where pass > 1 {
        throw SwiftFormatError.formatterProducedInvalidSyntax(pass: pass)
      }

      var buffer = ""
      try format(
        syntax: sourceFile,
        source: currentSource,
        operatorTable: .standardOperators,
        assumingFileURL: url,
        selection: selection,
        to: &buffer,
        findingConsumer: passFindingSink
      )

      if buffer == currentSource {
        // The output is a fixed point of the formatter; it is stable by construction.
        outputStream.write(buffer)
        if let findingConsumer {
          passFindings.forEach(findingConsumer)
        }
        return
      }
      if pass == maximumPasses {
        if maximumPasses == 1 {
          // Single-pass mode returns the output of the one pass.
          outputStream.write(buffer)
          if let findingConsumer {
            passFindings.forEach(findingConsumer)
          }
          return
        }
        throw SwiftFormatError.formattingDidNotConverge(
          maximumPasses: Self.maximumFixpointIterations
        )
      }
      currentSource = buffer
    }
  }

  /// Formats the given Swift syntax tree and writes the result to an output stream.
  ///
  /// This form of the `format` function does not perform any additional processing on the given
  /// syntax tree. The tree **must** have all expressions folded using an `OperatorTable`, and no
  /// detection of warnings/errors is performed.
  ///
  /// - Note: The formatter may be faster using the source text, if it's available.
  ///
  /// - Parameters:
  ///   - syntax: The Swift syntax tree to be converted to source code and formatted.
  ///   - source: The original Swift source code used to build the syntax tree.
  ///   - operatorTable: The table that defines the operators and their precedence relationships.
  ///     This must be the same operator table that was used to fold the expressions in the `syntax`
  ///     argument.
  ///   - url: A file URL denoting the filename/path that should be assumed for this syntax tree,
  ///     which is associated with any diagnostics emitted during formatting. If this is nil, a
  ///     dummy value will be used.
  ///   - selection: The ranges to format
  ///   - outputStream: A value conforming to `TextOutputStream` to which the formatted output will
  ///     be written.
  /// - Throws: If an unrecoverable error occurs when formatting the code.
  public func format<Output: TextOutputStream>(
    syntax: SourceFileSyntax,
    source: String,
    operatorTable: OperatorTable,
    assumingFileURL url: URL?,
    selection: Selection,
    to outputStream: inout Output
  ) throws {
    try format(
      syntax: syntax,
      source: source,
      operatorTable: operatorTable,
      assumingFileURL: url,
      selection: selection,
      to: &outputStream,
      findingConsumer: findingConsumer
    )
  }

  /// The body of the tree-based format entry point, parameterized by the finding consumer so the
  /// fixpoint loop can collect findings per pass and forward them only from the pass whose
  /// output is returned.
  private func format<Output: TextOutputStream>(
    syntax: SourceFileSyntax,
    source: String,
    operatorTable: OperatorTable,
    assumingFileURL url: URL?,
    selection: Selection,
    to outputStream: inout Output,
    findingConsumer: ((Finding) -> Void)?
  ) throws {
    let assumedURL = url ?? URL(fileURLWithPath: "source")
    var selection = selection.resolved(
      with: SourceLocationConverter(fileName: assumedURL.relativePath, tree: syntax)
    )
    if case .ranges(let ranges) = selection {
      // Normalizing here covers both the rule runs below and the printing pass: an empty range
      // selects nothing but the printer treats a boundary-touching range as selecting the
      // tokens on both sides of the boundary, and overlapping ranges select the same text as
      // their coalesced union.
      selection = .ranges(Self.coalescedRanges(ranges))
    }

    // When a selection is active, the selected ranges are formatted in source order, and each
    // range is shifted by the length changes of the rewrites performed for the ranges before it.
    // Rules only rewrite nodes that are fully contained in a range, so those are the only length
    // changes there can be, and this keeps the rewritten tree's positions — which always describe
    // its own text — aligned with the selection in that text, which the pretty printer relies on
    // to locate the text it must leave verbatim. The shift is only meaningful for disjoint
    // ranges, so overlapping or adjacent ranges are coalesced first.
    var transformedSyntax = syntax
    var transformedSource = source
    var printingSelection = selection
    var didRewrite = false
    let originalConverter = SourceLocationConverter(fileName: assumedURL.relativePath, tree: syntax)
    var printingRanges: [Range<AbsolutePosition>] = []
    var rangeDeltas: [Int] = []
    if case .ranges(let ranges) = selection {
      var totalShift = 0

      for range in ranges {
        let rangeShift = totalShift
        let lower = AbsolutePosition(utf8Offset: range.lowerBound.utf8Offset + rangeShift)
        let upper = AbsolutePosition(utf8Offset: range.upperBound.utf8Offset + rangeShift)
        let rangeConverter = SourceLocationConverter(
          fileName: assumedURL.relativePath,
          tree: transformedSyntax
        )
        let context = Context(
          configuration: configuration,
          operatorTable: operatorTable,
          findingConsumer: unshiftingFindingConsumer(
            findingConsumer,
            ranges: printingRanges,
            deltas: rangeDeltas,
            shiftedConverter: rangeConverter,
            originalConverter: originalConverter
          ),
          fileURL: assumedURL,
          selection: .ranges([lower..<upper]),
          sourceFileSyntax: transformedSyntax,
          ruleNameCache: ruleNameCache
        )
        // Every rule rewrites a node using nodes of the kinds it visited, so the root survives
        // each pipeline pass with the same syntax kind it entered with.
        transformedSyntax = FormatPipeline(context: context)
          .rewrite(Syntax(transformedSyntax))
          .cast(SourceFileSyntax.self)
        let rewrittenSource = transformedSyntax.description
        if rewrittenSource != transformedSource {
          didRewrite = true
        }
        let delta = rewrittenSource.utf8.count - transformedSource.utf8.count
        // A selection that ran to the end of the file must keep covering the end of the
        // rewritten text: a half-open range ending exactly at the new end excludes the EOF
        // token, whose formatting emits the file's final line break.
        let remappedUpper: AbsolutePosition
        if range.upperBound.utf8Offset >= source.utf8.count {
          remappedUpper = AbsolutePosition(
            utf8Offset: max(upper.utf8Offset + delta, rewrittenSource.utf8.count + 1)
          )
        } else {
          remappedUpper = AbsolutePosition(utf8Offset: upper.utf8Offset + delta)
        }
        printingRanges.append(lower..<remappedUpper)
        rangeDeltas.append(delta)
        totalShift += delta
        transformedSource = rewrittenSource
      }

      if didRewrite {
        printingSelection = .ranges(printingRanges)
      } else {
        // No rule rewrote anything, so the original tree and selection are already mutually
        // consistent and there is nothing to shift.
        transformedSyntax = syntax
        transformedSource = source
      }
    }

    let context: Context
    if !didRewrite {
      context = Context(
        configuration: configuration,
        operatorTable: operatorTable,
        findingConsumer: findingConsumer,
        fileURL: assumedURL,
        selection: selection,
        sourceFileSyntax: syntax,
        source: source,
        ruleNameCache: ruleNameCache
      )
      if case .infinite = selection {
        // An unselected formatting pass runs the rules over the whole file in a single pipeline
        // pass; a selected pass has already run them range by range above.
        transformedSyntax = FormatPipeline(context: context)
          .rewrite(Syntax(syntax))
          .cast(SourceFileSyntax.self)
      }
    } else {
      let printingConverter = SourceLocationConverter(
        fileName: assumedURL.relativePath,
        tree: transformedSyntax
      )
      context = Context(
        configuration: configuration,
        operatorTable: operatorTable,
        findingConsumer: unshiftingFindingConsumer(
          findingConsumer,
          ranges: printingRanges,
          deltas: rangeDeltas,
          shiftedConverter: printingConverter,
          originalConverter: originalConverter
        ),
        fileURL: assumedURL,
        selection: printingSelection,
        sourceFileSyntax: transformedSyntax,
        ruleNameCache: ruleNameCache
      )
    }

    if debugOptions.contains(.disablePrettyPrint) {
      outputStream.write(transformedSyntax.description)
      return
    }

    let printer = PrettyPrinter(
      context: context,
      source: transformedSource,
      node: Syntax(transformedSyntax),
      printTokenStream: debugOptions.contains(.dumpTokenStream),
      whitespaceOnly: false
    )
    outputStream.write(printer.prettyPrint())
  }

  /// Drops empty ranges and merges overlapping and adjacent ones into a sorted list of disjoint
  /// ranges, so that each range's rewrites precede those of every later range. An empty range
  /// selects nothing, and the printer treats a boundary-touching range as selecting the tokens
  /// on both sides of that boundary, so keeping one could reformat unselected text.
  private static func coalescedRanges(
    _ ranges: [Range<AbsolutePosition>]
  ) -> [Range<AbsolutePosition>] {
    let sorted = ranges.filter { !$0.isEmpty }.sorted {
      ($0.lowerBound, $0.upperBound) < ($1.lowerBound, $1.upperBound)
    }
    var coalesced: [Range<AbsolutePosition>] = []
    for range in sorted {
      if let last = coalesced.last, range.lowerBound <= last.upperBound {
        coalesced[coalesced.count - 1] =
          last.lowerBound..<max(last.upperBound, range.upperBound)
      } else {
        coalesced.append(range)
      }
    }
    return coalesced
  }

  /// Returns a consumer that translates finding locations reported in the rewritten text back
  /// into original-source coordinates.
  ///
  /// A location is shifted only by the length changes of the ranges whose rewrites lie entirely
  /// before it, so findings above or between rewritten regions keep their exact positions. Each
  /// range's rewrites end before its (already remapped) upper bound. Locations are only
  /// line/column pairs, so the shifted converter turns them into byte offsets where the shift
  /// can be applied, and the original converter turns them back.
  private func unshiftingFindingConsumer(
    _ consumer: ((Finding) -> Void)?,
    ranges: [Range<AbsolutePosition>],
    deltas: [Int],
    shiftedConverter: SourceLocationConverter,
    originalConverter: SourceLocationConverter
  ) -> ((Finding) -> Void)? {
    guard let consumer, deltas.contains(where: { $0 != 0 }) else { return consumer }
    func unshifted(_ location: Finding.Location) -> Finding.Location {
      let shifted = shiftedConverter.position(ofLine: location.line, column: location.column)
      let shift = zip(ranges, deltas).reduce(0) { sum, pair in
        pair.0.upperBound <= shifted ? sum + pair.1 : sum
      }
      let original = originalConverter.location(
        for: AbsolutePosition(utf8Offset: shifted.utf8Offset - shift)
      )
      return Finding.Location(file: location.file, line: original.line, column: original.column)
    }
    return { finding in
      consumer(
        Finding(
          category: finding.category,
          message: finding.message,
          location: finding.location.map(unshifted),
          notes: finding.notes.map { note in
            Finding.Note(message: note.message, location: note.location.map(unshifted))
          }
        )
      )
    }
  }
}
