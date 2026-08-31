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

import SwiftDiagnostics
@_spi(Rules) import SwiftFormat
import XCTest
@_spi(Testing) import _SwiftFormatTestSupport

/// Stability tests for the formatter: formatting must be idempotent (formatting
/// formatted output changes nothing), both for targeted regressions and across the repository's
/// own sources; repeated formatting of the same input must produce identical output; and
/// alternative layouts of the same program must converge to the same output.
final class FormattingStabilityTests: DiagnosingTestCase {
  private func format(
    _ source: String,
    configuration: Configuration,
    file: StaticString = #file,
    line: UInt = #line
  ) throws -> String {
    var output = ""
    let formatter = SwiftFormatter(configuration: configuration)
    try formatter.format(
      source: source,
      assumingFileURL: nil,
      selection: .infinite,
      to: &output,
      parsingDiagnosticHandler: { _, _ in
        // Installing a handler makes formatting throw on input that does not parse, so the
        // stability checks below surface unparseable output instead of formatting it blindly.
      }
    )
    return output
  }

  /// Formats the input twice and asserts that the second pass changes nothing, returning the
  /// stable output.
  @discardableResult
  private func assertStable(
    _ source: String,
    configuration: Configuration,
    message: String,
    file: StaticString = #file,
    line: UInt = #line
  ) throws -> String {
    let pass1 = try format(source, configuration: configuration, file: file, line: line)
    do {
      let pass2 = try format(pass1, configuration: configuration, file: file, line: line)
      XCTAssertEqual(pass2, pass1, "\(message) (formatting is not idempotent)", file: file, line: line)
    } catch SwiftFormatError.fileContainsInvalidSyntax {
      // The `format` helper always installs a parsing-diagnostics handler, so output that does
      // not reparse cleanly surfaces here rather than as an opaque thrown error.
      XCTFail("\(message) (formatted output does not parse)", file: file, line: line)
    }
    return pass1
  }

  /// The test configuration with the fixpoint loop disabled, so that stability tests
  /// exercise exactly one format pass per call and cannot be masked by iteration.
  private func makeSinglePassTestConfiguration() -> Configuration {
    var configuration = makeStrictTestConfiguration()
    configuration.iterateToFixpoint = false
    return configuration
  }

  /// A configuration with the vertical layout options and the opt-in rules used by the tests
  /// in this file, applied on top of the default configuration.
  private func makeStrictTestConfiguration() -> Configuration {
    var configuration = Configuration()
    configuration.respectsExistingLineBreaks = false
    configuration.lineBreakBeforeEachArgument = true
    configuration.lineBreakBetweenDeclarationAttributes = true
    configuration.lineBreakAroundMultilineExpressionChainComponents = true
    configuration.lineBreakBeforeEachChainComponent = true
    configuration.attachLoneDeclarationAttributes = true
    configuration.collectionElementLayout = .onePerLine
    configuration.magicTrailingComma = true
    configuration.multilineTrailingCommaBehavior = .alwaysUsed
    configuration.forceBrokenArgumentsInMultilineArrayLiterals = true
    configuration.forceBrokenClosureBodies = true
    configuration.forceBrokenCodeBlockBodies = true
    configuration.rules[AttributeOrder.self.ruleName] = true
    configuration.rules[BlankLinePolicy.self.ruleName] = true
    configuration.rules[CanonicalDocComments.self.ruleName] = true
    configuration.rules[CanonicalNumberLiterals.self.ruleName] = true
    configuration.rules[CanonicalStringEscapes.self.ruleName] = true
    configuration.rules[ModifierOrder.self.ruleName] = true
    configuration.rules[RedundantParens.self.ruleName] = true
    configuration.rules[RedundantRawString.self.ruleName] = true
    configuration.rules[RedundantSelf.self.ruleName] = true
    configuration.rules[ReflowComments.self.ruleName] = true
    configuration.rules[GroupNumericLiterals.self.ruleName] = false
    return configuration
  }

  /// A long-line ternary repro: a wide conditional expression whose output is not stable in a
  /// single pass under these options.
  private let longLineTernaryInput = """
    struct Outer {
        func test() {
            let convertedValues: (ValueConverterFactory<FirstPayload>.Product?, IdentityFactory<Int32>.Product?, )? = (firstValue != nil || secondValue != nil || false) ? (firstValue, secondValue,) : nil
        }
    }
    """

  private func makeLongLineTernaryConfiguration() -> Configuration {
    var configuration = Configuration()
    configuration.lineLength = 120
    configuration.indentation = .spaces(4)
    configuration.indentConditionalCompilationBlocks = false
    configuration.lineBreakBeforeEachArgument = true
    configuration.lineBreakBetweenDeclarationAttributes = true
    configuration.prioritizeKeepingFunctionOutputTogether = true
    return configuration
  }

  /// A compact input that exercises many parts of the pipeline at once — doc-comment
  /// normalization, modifier and attribute ordering, number literals, redundant parentheses and
  /// `self`, the guard-prologue blank-line policy, and semicolon splitting — so every formatting
  /// call in the tests below performs real work.
  private let ruleExercisingInput = """
    ///Glued summary.
    ///
    ///
    /// Detail.
    struct Sample {
      static public var limit = 1000000

      private var value = 0

      @discardableResult @MainActor func advance() -> Int {
        guard value < Self.limit else { return 0 }
        self.value += 1; return (self.value)
      }
    }
    """

  /// Constructs whose wrapping is decided by the printer, each with several input spellings.
  /// The scaffolding is identical across a construct's variants so their outputs can converge.
  private static let layoutPermutations: [(name: String, variants: [String])] = [
    (
      "long argument list",
      [
        // Horizontal: exceeds the 100-column line length.
        """
        struct Sample {
          func build() -> Image {
            render(width: source.maximumAvailableWidth, height: source.maximumAvailableHeight, colorSpace: preferredColorSpace, dither: true)
          }
        }
        """,
        // Vertical: one argument per line.
        """
        struct Sample {
          func build() -> Image {
            render(
              width: source.maximumAvailableWidth,
              height: source.maximumAvailableHeight,
              colorSpace: preferredColorSpace,
              dither: true
            )
          }
        }
        """,
        // Ragged: wrapped mid-list with several arguments per line.
        """
        struct Sample {
          func build() -> Image {
            render(width: source.maximumAvailableWidth,
              height: source.maximumAvailableHeight,
              colorSpace: preferredColorSpace, dither: true)
          }
        }
        """,
      ]
    ),
    (
      "method chain",
      [
        // Horizontal: exceeds the 100-column line length.
        """
        struct Sample {
          func run() -> String {
            decoder.decode(container.payload).validated(against: schema).resolved(by: resolver).materialize().description
          }
        }
        """,
        // Vertical: one component per line.
        """
        struct Sample {
          func run() -> String {
            decoder
              .decode(container.payload)
              .validated(against: schema)
              .resolved(by: resolver)
              .materialize()
              .description
          }
        }
        """,
        // Ragged: several components per line.
        """
        struct Sample {
          func run() -> String {
            decoder.decode(container.payload).validated(against: schema)
              .resolved(by: resolver).materialize().description
          }
        }
        """,
      ]
    ),
    (
      "control flow body",
      [
        // Horizontal: fits on one line; `forceBrokenCodeBlockBodies` must break it open anyway.
        """
        struct Sample {
          func run(_ items: [Int]) {
            if !items.isEmpty { dispatcher.flush(items) }
          }
        }
        """,
        // Vertical: already broken open.
        """
        struct Sample {
          func run(_ items: [Int]) {
            if !items.isEmpty {
              dispatcher.flush(items)
            }
          }
        }
        """,
      ]
    ),
    (
      "closure body",
      [
        // Horizontal: fits on one line; `forceBrokenClosureBodies` must break it open anyway.
        """
        struct Sample {
          func run(_ inputs: [Input]) -> [Output] {
            inputs.map { input in transformer.apply(input) }
          }
        }
        """,
        // Vertical: already broken open.
        """
        struct Sample {
          func run(_ inputs: [Input]) -> [Output] {
            inputs.map { input in
              transformer.apply(input)
            }
          }
        }
        """,
      ]
    ),
  ]

  /// Asserts that no comment in the text is glued to a preceding non-space character.
  ///
  /// These inputs contain no URLs or division operators, so any `//` that is not preceded by
  /// whitespace is a comment that was pulled up without its separating spaces.
  private func assertNoGluedComments(
    _ text: String,
    file: StaticString = #file,
    line: UInt = #line
  ) {
    for (lineNumber, lineText) in text.split(separator: "\n", omittingEmptySubsequences: false)
      .enumerated()
    {
      if let range = lineText.range(of: "//") {
        let indexBefore = range.lowerBound
        if indexBefore != lineText.startIndex, lineText[lineText.index(before: indexBefore)] != " " {
          XCTFail(
            "comment glued to preceding token at line \(lineNumber + 1): \(lineText)",
            file: file,
            line: line
          )
        }
      }
    }
  }

  func testPulledUpLineCommentsAreSeparatedAndStable() throws {
    // A line comment on its own line before a closing delimiter is pulled up to become an
    // end-of-line comment under the strict test configuration (discretionary breaks are not
    // respected). It must be separated by the configured number of spaces and the result must be
    // stable. Pulled-up trailing comments keep their configured separator between passes.
    let inputs = [
      // Comment before the closing brace of a function body.
      """
      func f() {
        g()
        // comment before close
      }
      """,
      // Comment before `catch`.
      """
      func f() {
        do {
          g()
          // comment before catch
        } catch {
          h()
        }
      }
      """,
      // Comment before `else`.
      """
      func f() {
        if x {
          g()
          // comment before else
        } else {
          h()
        }
      }
      """,
      // Comment before the closing brace of a loop.
      """
      func f() {
        for i in 0..<3 {
          g(i)
          // comment before loop close
        }
      }
      """,
      // Comment before the closing parenthesis of a wrapped call.
      """
      func f() {
        g(
          a,
          b
          // comment before call close
        )
      }
      """,
      // Comment before the closing brace of a computed getter.
      """
      struct S {
        var x: Int {
          g()
          // comment before getter close
        }
      }
      """,
      // A block comment pulled up the same way.
      """
      func f() {
        g()
        /* comment before close */
      }
      """,
    ]

    for input in inputs {
      let output = try assertStable(
        input,
        configuration: makeSinglePassTestConfiguration(),
        message: "pulled-up trailing comment case"
      )
      assertNoGluedComments(output)
    }
  }

  func testPulledUpCommentProducesExpectedStableOutput() throws {
    // The stable form: the comment joins the previous line, separated by two spaces (the default
    // `spacesBeforeEndOfLineComments`), and the body stays broken open.
    let input = """
      func f() {
        g()
        // comment before close
      }
      """
    let output = try assertStable(
      input,
      configuration: makeSinglePassTestConfiguration(),
      message: "pulled-up trailing comment case"
    )
    assertStringsEqualWithDiff(
      output,
      """
      func f() {
        g()  // comment before close
      }

      """
    )
  }

  func testLongLineTernaryIsIdempotent() throws {
    // The input must be a fixed point after a single pass under the configuration above.
    try assertStable(
      longLineTernaryInput,
      configuration: makeLongLineTernaryConfiguration(),
      message: "long-line ternary repro"
    )
  }

  func testDocCommentReflowAndNormalizationAreStableTogether() throws {
    // ReflowComments (whose `reflowComments.reflowedCommentKinds` defaults to including `.docLine`) joins hard-wrapped `///` prose inside a
    // paragraph while CanonicalDocComments normalizes spacing and dashed-list alignment. The two
    // rules must reach a shared fixed point in a single pass: the wrapped summary joins, the
    // wrapped list-item continuation joins, the list marker keeps its alignment, and the blank
    // doc line between the summary and the detail paragraph collapses to one.
    let input = """
      /// Joins the wrapped words of the summary paragraph
      /// back onto one line.
      ///
      ///
      /// - Parameter x: a dashed list item whose continuation text
      ///   also reflows onto the item line.
      /// - Returns: the result.
      func f(x: Int) -> Int { x }
      """
    let output = try assertStable(
      input,
      configuration: makeSinglePassTestConfiguration(),
      message: "doc-comment reflow/normalization interplay"
    )
    assertStringsEqualWithDiff(
      output,
      """
      /// Joins the wrapped words of the summary paragraph back onto one line.
      ///
      /// - Parameter x: a dashed list item whose continuation text also reflows onto the item line.
      /// - Returns: the result.
      func f(x: Int) -> Int {
        x
      }

      """
    )
  }

  func testReflowedDocCommentCodeBlocksArePreserved() throws {
    // Indented code blocks inside a doc comment are never joined, and the block's indentation
    // survives reflow of the surrounding prose.
    let input = """
      /// Summary prose that is hard wrapped
      /// and joins back together.
      ///
      /// Example:
      ///
      ///     let x = f(1)
      ///     let y = f(2)
      func f(_ v: Int) -> Int { v }
      """
    let output = try assertStable(
      input,
      configuration: makeSinglePassTestConfiguration(),
      message: "doc-comment code block preservation under reflow"
    )
    assertStringsEqualWithDiff(
      output,
      """
      /// Summary prose that is hard wrapped and joins back together.
      ///
      /// Example:
      ///
      ///     let x = f(1)
      ///     let y = f(2)
      func f(_ v: Int) -> Int {
        v
      }

      """
    )
  }

  func testAttributeBlankLinesDoNotAffectOutput() throws {
    // Blank lines between attributes must not influence output when `respectsExistingLineBreaks`
    // is false. The printer intentionally retains blank-line runs (they are author-placed
    // blank lines), so this must hold via BlankLinePolicy's `attributes` axis (default
    // `.none`) rather than the printer itself.
    let withBlankLines = """
      @available(iOS 16.0, *) @available(macOS 14.0, *)

      @available(tvOS 16.0, *)

      @frozen
      struct X {}
      """
    let withoutBlankLines = """
      @available(iOS 16.0, *) @available(macOS 14.0, *)
      @available(tvOS 16.0, *)
      @frozen
      struct X {}
      """
    let configuration = makeSinglePassTestConfiguration()
    let withBlanks = try assertStable(
      withBlankLines,
      configuration: configuration,
      message: "attributes with blank lines"
    )
    let withoutBlanks = try assertStable(
      withoutBlankLines,
      configuration: configuration,
      message: "attributes without blank lines"
    )
    XCTAssertEqual(
      withBlanks,
      withoutBlanks,
      "blank lines between attributes must not affect the output"
    )
  }

  func testIterateToFixpointOutputIsStableAfterOneMorePass() throws {
    // With the fixpoint loop enabled, a single call must return output that is already stable.
    var configuration = makeLongLineTernaryConfiguration()
    configuration.iterateToFixpoint = true

    let viaFixpoint = try format(longLineTernaryInput, configuration: configuration)
    let secondPass = try format(viaFixpoint, configuration: configuration)
    XCTAssertEqual(secondPass, viaFixpoint)
  }

  func testIterateToFixpointIsSkippedForLineSelections() throws {
    // Line selections are excluded from fixpoint iteration because their ranges are not valid
    // for the formatted text of later passes; formatting must still succeed in a single pass.
    let input = """
      struct S {
        var x: Int
        func f() { g() }
      }
      """
    var configuration = makeSinglePassTestConfiguration()
    configuration.iterateToFixpoint = true

    var output = ""
    let formatter = SwiftFormatter(configuration: configuration)
    try formatter.format(
      source: input,
      assumingFileURL: nil,
      selection: Selection(lineRanges: [1...3]),
      to: &output
    )
    XCTAssertFalse(output.isEmpty)
    XCTAssertTrue(
      output.contains("struct S"),
      "selected lines must be present in the formatted output"
    )
  }

  func testFormattingTheSameInputTwiceProducesIdenticalOutput() throws {
    // A determinism check: two format calls on the same input in the same process must return
    // identical bytes. Hidden state, or iteration order leaking into rewrites, would otherwise
    // surface only indirectly as an idempotency failure on some inputs.
    let configuration = makeSinglePassTestConfiguration()
    let first = try format(ruleExercisingInput, configuration: configuration)
    let second = try format(ruleExercisingInput, configuration: configuration)
    XCTAssertEqual(
      first,
      second,
      "formatting the same input twice produced different output; the formatter is not deterministic"
    )
  }

  /// Formats the repository's own sources twice under the strict test configuration (with the
  /// fixpoint loop disabled so that genuine instabilities are not masked) and asserts that every
  /// file is already stable after one pass.
  ///
  /// Set `SWIFT_FORMAT_SKIP_CORPUS_STABILITY=1` to skip it (for
  /// example during inner-loop test runs).
  func testRepositorySourcesAreStableUnderTestConfiguration() throws {
    if ProcessInfo.processInfo.environment["SWIFT_FORMAT_SKIP_CORPUS_STABILITY"] == "1" {
      throw XCTSkip("corpus stability test skipped by environment variable")
    }

    let repositoryRoot =
      URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // FormattingStabilityTests.swift
      .deletingLastPathComponent()  // PrettyPrint/
      .deletingLastPathComponent()  // SwiftFormatTests/
      .deletingLastPathComponent()  // Tests/

    let corpusDirectories = [
      repositoryRoot.appendingPathComponent("Sources/SwiftFormat"),
      repositoryRoot.appendingPathComponent("Sources/swift-format"),
    ]

    // The fixpoint loop must be off so this test detects real instabilities. The corpus run also
    // exercises `FileHeader` with a configured template: replacing every file's real license
    // header and then re-formatting must still be a fixed point. (A header template is
    // repository-specific content, so it is configured here rather than in
    // `makeStrictTestConfiguration()`, which must stay repository-agnostic — unlike
    // `ReflowComments`, which needs no per-repository input.)
    var configuration = makeSinglePassTestConfiguration()
    configuration.rules[FileHeader.self.ruleName] = true
    configuration.fileHeader.template = "Test header for {file}."

    var testedFileCount = 0
    for directory in corpusDirectories {
      guard
        let enumerator = FileManager.default.enumerator(
          at: directory,
          includingPropertiesForKeys: nil
        )
      else {
        continue
      }
      for case let url as URL in enumerator {
        guard url.pathExtension == "swift" else { continue }
        let source = try String(contentsOf: url, encoding: .utf8)
        guard !source.isEmpty else { continue }
        testedFileCount += 1
        try assertStable(
          source,
          configuration: configuration,
          message: "corpus file \(url.relativePath) under the strict test configuration"
        )
      }
    }
    XCTAssertGreaterThan(testedFileCount, 100, "corpus unexpectedly small; test is not running")
  }

  /// Alternative layouts of the same program — differing only in line breaks, never in the
  /// author-placed blank lines or trailing commas (no blank lines, no trailing commas, no
  /// comments anywhere) —
  /// must converge to identical output: the output layout is a function of the syntax, not of how
  /// the source happened to be wrapped.
  func testLayoutPermutationsConvergeToTheSameOutput() throws {
    let configuration = makeSinglePassTestConfiguration()
    for construct in Self.layoutPermutations {
      var reference: String?
      for variant in construct.variants {
        let output = try assertStable(
          variant,
          configuration: configuration,
          message: "'\(construct.name)' variant is not a fixed point"
        )
        if let reference {
          XCTAssertEqual(
            output,
            reference,
            "'\(construct.name)': layouts that differ only in line breaks disagree on the output"
          )
        } else {
          reference = output
        }
      }
    }
  }
}
