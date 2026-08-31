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

@_spi(Testing) import SwiftFormat
import SwiftParser
import SwiftSyntax
import XCTest

/// Tests the `swift-format-disable`/`swift-format-enable` block directives and the
/// `:next`/`:this`/`:previous` line-scoped directives through `RuleMask`'s rule state lookups.
final class RuleMaskDisableDirectiveTests: XCTestCase {
  var converter: SourceLocationConverter!

  private func createMask(sourceText: String) -> RuleMask {
    let fileURL = URL(fileURLWithPath: "/tmp/test.swift")
    let syntax = Parser.parse(source: sourceText)
    converter = SourceLocationConverter(fileName: fileURL.path, tree: syntax)
    return RuleMask(syntaxNode: Syntax(syntax), sourceLocationConverter: converter)
  }

  /// Returns the source location that corresponds to the given line and column numbers.
  private func location(ofLine line: Int, column: Int = 1) -> SourceLocation {
    return converter.location(for: converter.position(ofLine: line, column: column))
  }

  // MARK: - Blocks

  func testDisableBlockDisablesAllRulesBetweenDirectives() {
    let mask = createMask(
      sourceText: """
        let a = 1
        // swift-format-disable
        let b = 2
        let c = 3
        // swift-format-enable
        let d = 4
        """
    )

    XCTAssertEqual(mask.ruleState("rule1", at: location(ofLine: 1)), .default)
    XCTAssertEqual(mask.ruleState("rule1", at: location(ofLine: 3)), .disabled)
    XCTAssertEqual(mask.ruleState("rule2", at: location(ofLine: 4)), .disabled)
    XCTAssertEqual(mask.ruleState("rule1", at: location(ofLine: 6)), .default)
  }

  func testDisableBlockDisablesNamedRulesOnly() {
    let mask = createMask(
      sourceText: """
        let a = 1
        // swift-format-disable: rule1, rule2
        let b = 2
        // swift-format-enable
        let c = 3
        """
    )

    XCTAssertEqual(mask.ruleState("rule1", at: location(ofLine: 3)), .disabled)
    XCTAssertEqual(mask.ruleState("rule2", at: location(ofLine: 3)), .disabled)
    XCTAssertEqual(mask.ruleState("rule3", at: location(ofLine: 3)), .default)
    XCTAssertEqual(mask.ruleState("rule1", at: location(ofLine: 5)), .default)
  }

  func testUnterminatedDisableBlockRunsToEndOfFile() {
    let mask = createMask(
      sourceText: """
        let a = 1
        // swift-format-disable
        let b = 2
        let c = 3
        """
    )

    XCTAssertEqual(mask.ruleState("rule1", at: location(ofLine: 1)), .default)
    XCTAssertEqual(mask.ruleState("rule1", at: location(ofLine: 3)), .disabled)
    XCTAssertEqual(mask.ruleState("rule1", at: location(ofLine: 4)), .disabled)
  }

  func testEnableWithRuleNamesReenablesInsideAllRulesBlock() {
    let mask = createMask(
      sourceText: """
        // swift-format-disable
        let a = 1
        // swift-format-enable: rule1
        let b = 2
        // swift-format-enable
        let c = 3
        """
    )

    // `rule1` is re-enabled inside the all-rules block, while other rules stay disabled.
    XCTAssertEqual(mask.ruleState("rule1", at: location(ofLine: 4)), .default)
    XCTAssertEqual(mask.ruleState("rule2", at: location(ofLine: 4)), .disabled)
    XCTAssertEqual(mask.ruleState("rule1", at: location(ofLine: 6)), .default)
    XCTAssertEqual(mask.ruleState("rule2", at: location(ofLine: 6)), .default)
  }

  func testDisableInsideAllRulesBlockCancelsReenablement() {
    let mask = createMask(
      sourceText: """
        // swift-format-disable
        // swift-format-enable: rule1
        let a = 1
        // swift-format-disable: rule1
        let b = 2
        // swift-format-enable
        let c = 3
        """
    )

    XCTAssertEqual(mask.ruleState("rule1", at: location(ofLine: 3)), .default)
    XCTAssertEqual(mask.ruleState("rule1", at: location(ofLine: 5)), .disabled)
    XCTAssertEqual(mask.ruleState("rule2", at: location(ofLine: 5)), .disabled)
  }

  func testDisableBlocksWorkInsideFunctionBodies() {
    let mask = createMask(
      sourceText: """
        func f() {
          // swift-format-disable
          let a = 1
          // swift-format-enable
          let b = 2
        }
        """
    )

    XCTAssertEqual(mask.ruleState("rule1", at: location(ofLine: 3)), .disabled)
    XCTAssertEqual(mask.ruleState("rule1", at: location(ofLine: 5)), .default)
  }

  func testTrailingDisableBehavesLikeNodeIgnore() {
    // A directive comment travels in the leading trivia of the next statement, and — exactly
    // like the node-level `swift-format-ignore` — a comment at the end of a line of code is
    // still recognized there. The block is line-anchored, so it covers the directive's own
    // line, and being unterminated it runs to the end of the file.
    let mask = createMask(
      sourceText: """
        let a = 1  // swift-format-disable
        let b = 2
        """
    )

    XCTAssertEqual(mask.ruleState("rule1", at: location(ofLine: 1)), .disabled)
    XCTAssertEqual(mask.ruleState("rule1", at: location(ofLine: 2)), .disabled)
  }

  // MARK: - Line-scoped directives

  func testDisableNextLine() {
    let mask = createMask(
      sourceText: """
        let a = 1
        // swift-format-disable:next
        let b = 2
        let c = 3
        """
    )

    XCTAssertEqual(mask.ruleState("rule1", at: location(ofLine: 1)), .default)
    XCTAssertEqual(mask.ruleState("rule1", at: location(ofLine: 3)), .disabled)
    XCTAssertEqual(mask.ruleState("rule1", at: location(ofLine: 4)), .default)
  }

  func testDisableNextLineWithRuleNames() {
    let mask = createMask(
      sourceText: """
        // swift-format-disable:next rule1, rule2
        let a = 1
        """
    )

    XCTAssertEqual(mask.ruleState("rule1", at: location(ofLine: 2)), .disabled)
    XCTAssertEqual(mask.ruleState("rule2", at: location(ofLine: 2)), .disabled)
    XCTAssertEqual(mask.ruleState("rule3", at: location(ofLine: 2)), .default)
  }

  func testDisableThisLineAsTrailingComment() {
    let mask = createMask(
      sourceText: """
        let a = 1  // swift-format-disable:this
        let b = 2
        """
    )

    XCTAssertEqual(mask.ruleState("rule1", at: location(ofLine: 1)), .disabled)
    XCTAssertEqual(mask.ruleState("rule1", at: location(ofLine: 2)), .default)
  }

  func testDisablePreviousLineAsTrailingComment() {
    let mask = createMask(
      sourceText: """
        let a = 1
        let b = 2  // swift-format-disable:previous rule1
        let c = 3
        """
    )

    XCTAssertEqual(mask.ruleState("rule1", at: location(ofLine: 1)), .disabled)
    XCTAssertEqual(mask.ruleState("rule2", at: location(ofLine: 1)), .default)
    XCTAssertEqual(mask.ruleState("rule1", at: location(ofLine: 2)), .default)
    XCTAssertEqual(mask.ruleState("rule1", at: location(ofLine: 3)), .default)
  }

  func testDisableNextOnLastLineIsInert() {
    let mask = createMask(
      sourceText: """
        let a = 1
        // swift-format-disable:next
        """
    )

    // The next line is past EOF; the directive's own comment line is not disabled either.
    XCTAssertEqual(mask.ruleState("rule1", at: location(ofLine: 1)), .default)
    XCTAssertEqual(mask.ruleState("rule1", at: location(ofLine: 2)), .default)
  }

  func testDisablePreviousOnFirstLineIsInert() {
    let mask = createMask(
      sourceText: """
        // swift-format-disable:previous rule1
        let a = 1
        """
    )

    XCTAssertEqual(mask.ruleState("rule1", at: location(ofLine: 1)), .default)
    XCTAssertEqual(mask.ruleState("rule1", at: location(ofLine: 2)), .default)
  }

  func testDisableThisWithRuleNames() {
    let mask = createMask(
      sourceText: """
        let a = 1  // swift-format-disable:this rule1, rule2
        let b = 2
        """
    )

    XCTAssertEqual(mask.ruleState("rule1", at: location(ofLine: 1)), .disabled)
    XCTAssertEqual(mask.ruleState("rule2", at: location(ofLine: 1)), .disabled)
    XCTAssertEqual(mask.ruleState("rule3", at: location(ofLine: 1)), .default)
    XCTAssertEqual(mask.ruleState("rule1", at: location(ofLine: 2)), .default)
  }

  func testEnableWithRuleNamesClosesNamedBlock() {
    let mask = createMask(
      sourceText: """
        // swift-format-disable: rule1, rule2
        let a = 1
        // swift-format-enable: rule1
        let b = 2
        // swift-format-enable
        let c = 3
        """
    )

    XCTAssertEqual(mask.ruleState("rule1", at: location(ofLine: 2)), .disabled)
    // Re-enabled mid-block; rule2 stays disabled until the bare enable.
    XCTAssertEqual(mask.ruleState("rule1", at: location(ofLine: 4)), .default)
    XCTAssertEqual(mask.ruleState("rule2", at: location(ofLine: 4)), .disabled)
    XCTAssertEqual(mask.ruleState("rule2", at: location(ofLine: 6)), .default)
  }

  // MARK: - Recognition points beyond statement items

  func testEnableBeforeClosingBraceEndsBlock() {
    let mask = createMask(
      sourceText: """
        struct Foo {
          // swift-format-disable
          let a = 1
          // swift-format-enable
        }
        struct Bar {
          let b = 2
        }
        """
    )

    XCTAssertEqual(mask.ruleState("rule1", at: location(ofLine: 3)), .disabled)
    XCTAssertEqual(mask.ruleState("rule1", at: location(ofLine: 6)), .default)
  }

  func testNestedEnableClosesAllRulesBlock() {
    let mask = createMask(
      sourceText: """
        // swift-format-disable
        func f() {
          // swift-format-enable
          let b = 2
        }
        let c = 3
        """
    )

    XCTAssertEqual(mask.ruleState("rule1", at: location(ofLine: 2)), .disabled)
    XCTAssertEqual(mask.ruleState("rule1", at: location(ofLine: 4)), .default)
    XCTAssertEqual(mask.ruleState("rule1", at: location(ofLine: 6)), .default)
  }

  func testEnableAtEndOfFileEndsBlock() {
    let mask = createMask(
      sourceText: """
        let a = 1
        // swift-format-disable
        let b = 2
        // swift-format-enable
        """
    )

    XCTAssertEqual(mask.ruleState("rule1", at: location(ofLine: 1)), .default)
    XCTAssertEqual(mask.ruleState("rule1", at: location(ofLine: 3)), .disabled)
  }

  // MARK: - Coexistence with the node-level directive

  func testNodeLevelIgnoreStillWorksAlongsideBlocks() {
    let mask = createMask(
      sourceText: """
        // swift-format-ignore: rule1
        let a = 1
        // swift-format-disable
        let b = 2
        // swift-format-enable
        let c = 3
        """
    )

    XCTAssertEqual(mask.ruleState("rule1", at: location(ofLine: 2)), .disabled)
    XCTAssertEqual(mask.ruleState("rule2", at: location(ofLine: 2)), .default)
    XCTAssertEqual(mask.ruleState("rule2", at: location(ofLine: 4)), .disabled)
    XCTAssertEqual(mask.ruleState("rule1", at: location(ofLine: 6)), .default)
  }
}
