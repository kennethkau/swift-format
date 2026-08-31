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

import SwiftFormat

/// Regression tests for disable-region placements where the region's source-order semantics are
/// easy to get wrong: a block ending a switch case or `#if` clause (which must not crash the
/// printer with an unclosed group), a block opened inside a nested scope and closed later, a
/// block closed on the line before a closing brace, and a nested `enable` closing an open
/// block.
final class DisableRegionEdgeCaseTests: PrettyPrintTestCase {
  func testDisableBlockEndingIfConfigClauseDoesNotCrash() {
    let input = """
      #if compiler(>=5)
      // swift-format-disable
      let  x  =  1
      #endif
      let y = 2

      """

    // A verbatim item's first line is indented to the printer's current indentation, like a
    // node-level `swift-format-ignore` inside the clause.
    let expected = """
      #if compiler(>=5)
        // swift-format-disable
        let  x  =  1
      #endif
      let y = 2

      """

    assertPrettyPrintEqual(input: input, expected: expected, linelength: 100)
  }

  func testDisableBlockEndingSwitchCaseDoesNotCrash() {
    let input = """
      func f(x: Int) {
        switch x {
        case 1:
          // swift-format-disable
          h(  1,2 )
        default:
          g()
        }
      }

      """

    let expected = input

    assertPrettyPrintEqual(input: input, expected: expected, linelength: 100)
  }

  func testUnterminatedBlockOpenedInNestedScopeRunsToEndOfFile() {
    // The disable comment is attached to a statement inside the function, but the block is
    // unterminated: like the rule mask's ranges, the verbatim region runs to the end of the
    // file, covering the top-level statement after the function.
    let input = """
      func f() {
        // swift-format-disable
        let  a  =  1
      }
      let  c  =  3

      """

    let expected = input

    assertPrettyPrintEqual(input: input, expected: expected, linelength: 100)
  }

  func testEnableInLaterSiblingAppliesInSourceOrder() {
    // The enable comment travels in the leading trivia of a top-level item; the block opened
    // inside the function body must stay open until that point, and close there.
    let input = """
      func f() {
        // swift-format-disable
        let  x  =  1
      }
      // swift-format-enable
      func g() {
        let y = 2
      }

      """

    let expected = input

    assertPrettyPrintEqual(input: input, expected: expected, linelength: 100)
  }

  func testEnableBeforeClosingBraceEndsBlock() {
    let input = """
      struct Foo {
        // swift-format-disable
        var  x=1
        // swift-format-enable
      }
      struct Bar {
        var y=2
      }

      """

    let expected = """
      struct Foo {
        // swift-format-disable
        var  x=1
        // swift-format-enable
      }
      struct Bar {
        var y = 2
      }

      """

    assertPrettyPrintEqual(input: input, expected: expected, linelength: 100)
  }

  func testRegionEndingInsideSwitchCaseItemDoesNotCrash() {
    // The enable closes the region inside the covered statement, so the case's last token lies
    // outside the region while the statement that owns it is emitted verbatim; the case's
    // closing tokens must anchor somewhere visited.
    let input = """
      func f(x: Int) {
        switch x {
        case 1:
          // swift-format-disable
          if x == 1 {
            // swift-format-enable
          }
        default:
          g( )
        }
      }

      """

    let expected = """
      func f(x: Int) {
        switch x {
        case 1:
          // swift-format-disable
          if x == 1 {
            // swift-format-enable
          }
        default:
          g()
        }
      }

      """

    assertPrettyPrintEqual(input: input, expected: expected, linelength: 100)
  }

  func testRegionEndingInsideIfConfigMemberDoesNotCrash() {
    let input = """
      struct S {
        #if FOO
        // swift-format-disable
        struct T {
          // swift-format-enable
        }
        #endif
      }

      """

    // The verbatim member's first line is re-indented to the printer's indentation, like a
    // node-level ignore inside the clause.
    let expected = """
      struct S {
        #if FOO
          // swift-format-disable
          struct T {
          // swift-format-enable
        }
        #endif
      }

      """

    assertPrettyPrintEqual(input: input, expected: expected, linelength: 100)
  }

  func testNestedEnableCoversOnlyLaterStatements() {
    // An enable nested inside an all-rules block is honored: the function that was opened
    // before it is verbatim, and the statement after it is formatted again.
    let input = """
      // swift-format-disable
      func f() {
        // swift-format-enable
        let  b  =  2
      }
      let  c  =  3

      """

    let expected = """
      // swift-format-disable
      func f() {
        // swift-format-enable
        let  b  =  2
      }
      let c = 3

      """

    assertPrettyPrintEqual(input: input, expected: expected, linelength: 100)
  }
}
