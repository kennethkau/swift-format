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
@_spi(Rules) import SwiftFormat
import XCTest
import _SwiftFormatTestSupport

final class FileHeaderTests: LintOrFormatRuleTestCase {
  private func configuration(template: String?) -> Configuration {
    var configuration = Configuration.forTesting(enabledRule: FileHeader.self.ruleName)
    configuration.fileHeader.template = template
    return configuration
  }

  func testInsertsHeaderWhenNoneExists() {
    // `{file}` substitution is covered separately through the public formatter API; the shared
    // rule harness formats once with a `/tmp/test.swift` URL and once with no URL at all, which
    // would render different file names.
    assertFormatting(
      FileHeader.self,
      input: """
        1️⃣let x = 1
        """,
      expected: """
        // Part of the test project.
        // Generated canonically.

        let x = 1
        """,
      findings: [
        FindingSpec("1️⃣", message: "add the configured file header")
      ],
      configuration: configuration(template: "Part of the test project.\nGenerated canonically.")
    )
  }

  func testFileNamePlaceholderSubstitution() throws {
    var configuration = Configuration()
    configuration.rules[FileHeader.self.ruleName] = true
    configuration.fileHeader.template = "Part of the project.\nFile: {file}"
    let formatter = SwiftFormatter(configuration: configuration)
    var output = ""
    try formatter.format(
      source: "let x = 1",
      assumingFileURL: URL(fileURLWithPath: "/tmp/MyFile.swift"),
      selection: .infinite,
      to: &output
    )
    XCTAssertEqual(
      output,
      "// Part of the project.\n// File: MyFile\n\nlet x = 1\n",
      "expected the {file} placeholder to render the formatted file's name"
    )
  }

  func testMatchingHeaderWithoutBlankLineIsLeftUntouched() {
    // A header that already matches the template is left untouched even when no blank line
    // follows it; blank lines around the header are the blank-line policy's domain.
    assertFormatting(
      FileHeader.self,
      input: """
        // Header
        let x = 1
        """,
      expected: """
        // Header
        let x = 1
        """,
      configuration: configuration(template: "Header")
    )
  }

  func testCommentsOnlyFileIsLeftUntouched() {
    // A file with no statements has nothing to attach the header to (its comments live on the
    // end-of-file token), so the rule must neither rewrite nor diagnose.
    assertFormatting(
      FileHeader.self,
      input: """
        // Just a comment
        """,
      expected: """
        // Just a comment
        """,
      configuration: configuration(template: "Header")
    )
  }

  func testDocBlockCommentIsNotHeaderMaterial() {
    // A leading documentation block comment belongs to the first declaration; the header is
    // inserted before it and the doc comment is preserved.
    assertFormatting(
      FileHeader.self,
      input: """
        /** Docs for x. */
        1️⃣let x = 1
        """,
      expected: """
        // Header

        /** Docs for x. */
        let x = 1
        """,
      findings: [
        FindingSpec("1️⃣", message: "add the configured file header")
      ],
      configuration: configuration(template: "Header")
    )
  }

  func testEmptyTemplateMeansNoRewriting() {
    // An empty template specifies no header, like a missing one.
    assertFormatting(
      FileHeader.self,
      input: """
        // Old header

        let x = 1
        """,
      expected: """
        // Old header

        let x = 1
        """,
      configuration: configuration(template: "")
    )
  }

  func testNoSpaceAfterMarkerIsReplacedWithCanonicalForm() {
    // Only the rule's own rendering — `//` plus one space — counts as canonical.
    assertFormatting(
      FileHeader.self,
      input: """
        //Header
        1️⃣let x = 1
        """,
      expected: """
        // Header

        let x = 1
        """,
      findings: [
        FindingSpec("1️⃣", message: "replace this file header with the configured one")
      ],
      configuration: configuration(template: "Header")
    )
  }

  func testByteOrderMarkerStaysAheadOfInsertedHeader() {
    assertFormatting(
      FileHeader.self,
      input: "\u{FEFF}1️⃣let x = 1",
      expected: "\u{FEFF}// Header\n\nlet x = 1",
      findings: [
        FindingSpec("1️⃣", message: "add the configured file header")
      ],
      configuration: configuration(template: "Header")
    )
  }

  func testReplacesDifferingHeader() {
    assertFormatting(
      FileHeader.self,
      input: """
        // Old header line 1
        // Old header line 2

        1️⃣let x = 1
        """,
      expected: """
        // New header

        let x = 1
        """,
      findings: [
        FindingSpec("1️⃣", message: "replace this file header with the configured one")
      ],
      configuration: configuration(template: "New header")
    )
  }

  func testMatchingHeaderIsLeftUntouched() {
    assertFormatting(
      FileHeader.self,
      input: """
        // Header

        let x = 1
        """,
      expected: """
        // Header

        let x = 1
        """,
      configuration: configuration(template: "Header")
    )
  }

  func testCommentAfterBlankLineIsNotHeaderMaterial() {
    assertFormatting(
      FileHeader.self,
      input: """
        // Header

        // Not part of the header
        1️⃣let x = 1
        """,
      expected: """
        // Different

        // Not part of the header
        let x = 1
        """,
      findings: [
        FindingSpec("1️⃣", message: "replace this file header with the configured one")
      ],
      configuration: configuration(template: "Different")
    )
  }

  func testCommentAfterWhitespaceOnlyBlankLineIsNotHeaderMaterial() {
    // A blank line containing only whitespace must end the header block just like a clean one.
    // The input is written as a single-line string so the whitespace-only blank line is
    // explicit.
    assertFormatting(
      FileHeader.self,
      input: "// Header\n \n// Not part of the header\n1️⃣let x = 1",
      expected: "// Different\n\n// Not part of the header\nlet x = 1",
      findings: [
        FindingSpec("1️⃣", message: "replace this file header with the configured one")
      ],
      configuration: configuration(template: "Different")
    )
  }

  func testDocCommentIsNotHeaderMaterial() {
    // A leading documentation comment belongs to the first declaration; the header is inserted
    // before it and the doc comment is preserved.
    assertFormatting(
      FileHeader.self,
      input: """
        /// Docs for x.
        1️⃣let x = 1
        """,
      expected: """
        // Header

        /// Docs for x.
        let x = 1
        """,
      findings: [
        FindingSpec("1️⃣", message: "add the configured file header")
      ],
      configuration: configuration(template: "Header")
    )
  }

  func testReplacesBlockCommentHeader() {
    assertFormatting(
      FileHeader.self,
      input: """
        /* Old header */
        1️⃣let x = 1
        """,
      expected: """
        // New header

        let x = 1
        """,
      findings: [
        FindingSpec("1️⃣", message: "replace this file header with the configured one")
      ],
      configuration: configuration(template: "New header")
    )
  }

  func testNoTemplateMeansNoRewriting() {
    // The rule may be enabled without a template; it must not touch anything.
    assertFormatting(
      FileHeader.self,
      input: """
        // Old header line 1
        // Old header line 2

        let x = 1
        """,
      expected: """
        // Old header line 1
        // Old header line 2

        let x = 1
        """,
      configuration: configuration(template: nil)
    )
  }

  func testTrailingNewlineInTemplateIsDropped() {
    assertFormatting(
      FileHeader.self,
      input: """
        1️⃣let x = 1
        """,
      expected: """
        // Header

        let x = 1
        """,
      findings: [
        FindingSpec("1️⃣", message: "add the configured file header")
      ],
      configuration: configuration(template: "Header\n")
    )
  }

  func testEmptyTemplateLineRendersBareComment() {
    assertFormatting(
      FileHeader.self,
      input: """
        1️⃣let x = 1
        """,
      expected: """
        // First
        //
        // Second

        let x = 1
        """,
      findings: [
        FindingSpec("1️⃣", message: "add the configured file header")
      ],
      configuration: configuration(template: "First\n\nSecond")
    )
  }
}
