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

/// Tests that an all-rules `swift-format-disable` block is emitted verbatim by the pretty
/// printer, that a named-rules block is still formatted, and that the surrounding code is
/// formatted normally.
final class DisableRegionTests: PrettyPrintTestCase {
  func testAllRulesBlockIsVerbatim() {
    let input = """
      let a = 1
      // swift-format-disable
      let  b   =  2
      var   c  =  3
      // swift-format-enable
      let d = 4

      """

    let expected = input

    assertPrettyPrintEqual(input: input, expected: expected, linelength: 100)
  }

  func testNamedRulesBlockIsStillFormatted() {
    let input = """
      let a = 1
      // swift-format-disable: SomeRule
      let  b   =  2
      // swift-format-enable
      let d = 4

      """

    let expected = """
      let a = 1
      // swift-format-disable: SomeRule
      let b = 2
      // swift-format-enable
      let d = 4

      """

    assertPrettyPrintEqual(input: input, expected: expected, linelength: 100)
  }

  func testUnterminatedBlockRunsToEndOfFile() {
    let input = """
      let a = 1
      // swift-format-disable
      let  b   =  2

      """

    let expected = input

    assertPrettyPrintEqual(input: input, expected: expected, linelength: 100)
  }

  func testBlockInsideFunctionBody() {
    let input = """
      func f() {
        let a = 1
        // swift-format-disable
          let    b = 2
          let    c = 3
        // swift-format-enable
        let d = 4
      }

      """

    let expected = """
      func f() {
        let a = 1
        // swift-format-disable
        let    b = 2
        let    c = 3
        // swift-format-enable
        let d = 4
      }

      """

    assertPrettyPrintEqual(input: input, expected: expected, linelength: 100)
  }

  func testBlockInsideTypeMembers() {
    let input = """
      struct Foo {
        // swift-format-disable
          var   x=1
          var   y=2
        // swift-format-enable
        var   z=3
      }

      """

    let expected = """
      struct Foo {
        // swift-format-disable
        var   x=1
        var   y=2
        // swift-format-enable
        var z = 3
      }

      """

    assertPrettyPrintEqual(input: input, expected: expected, linelength: 100)
  }

  func testLineScopeDirectiveDoesNotMakeTextVerbatim() {
    // Line-scoped directives suppress rules and findings only; the pretty printer still
    // formats the line. Use a node-level `swift-format-ignore` or a block for verbatim text.
    let input = """
      // swift-format-disable:next
      let  a  =  1

      """

    let expected = """
      // swift-format-disable:next
      let a = 1

      """

    assertPrettyPrintEqual(input: input, expected: expected, linelength: 100)
  }

  func testDisableBlockIsIdempotent() {
    let input = """
      // swift-format-disable
      let  b   =  2
      // swift-format-enable
      let  d  =  4

      """

    let expected = """
      // swift-format-disable
      let  b   =  2
      // swift-format-enable
      let d = 4

      """

    assertPrettyPrintEqual(input: input, expected: expected, linelength: 100)
  }
}
