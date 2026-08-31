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

// The test harness re-formats each expected output a second time, so every test below also
// verifies idempotence.
final class MagicTrailingCommaTests: PrettyPrintTestCase {
  func testTrailingCommaKeepsFittingArrayLiteralVertical() {
    let input = """
      let a = [
        .red,
        .green,
      ]
      """
    let expected = """
      let a = [
        .red,
        .green,
      ]

      """
    var config = Configuration.forTesting
    config.magicTrailingComma = true
    config.respectsExistingLineBreaks = false
    assertPrettyPrintEqual(input: input, expected: expected, linelength: 80, configuration: config)
  }

  func testArrayLiteralWithoutTrailingCommaStillCollapses() {
    let input = """
      let b = [
        .red,
        .green
      ]
      """
    let expected = """
      let b = [.red, .green]

      """
    var config = Configuration.forTesting
    config.magicTrailingComma = true
    config.respectsExistingLineBreaks = false
    assertPrettyPrintEqual(input: input, expected: expected, linelength: 80, configuration: config)
  }

  func testTrailingCommaKeepsFittingArgumentListVertical() {
    let input = """
      let c = foo(
        x: 1,
        y: 2,
      )
      """
    let expected = """
      let c = foo(
        x: 1,
        y: 2,
      )

      """
    var config = Configuration.forTesting
    config.magicTrailingComma = true
    config.respectsExistingLineBreaks = false
    assertPrettyPrintEqual(input: input, expected: expected, linelength: 80, configuration: config)
  }

  func testTrailingCommaKeepsFittingParameterListVertical() {
    let input = """
      func f(
        a: Int,
        b: Int,
      ) {}
      """
    let expected = """
      func f(
        a: Int,
        b: Int,
      ) {}

      """
    var config = Configuration.forTesting
    config.magicTrailingComma = true
    config.respectsExistingLineBreaks = false
    assertPrettyPrintEqual(input: input, expected: expected, linelength: 80, configuration: config)
  }

  func testDisabledByDefaultCollapsesCommaSeparatedListsThatFit() {
    let input = """
      let a = [
        .red,
        .green,
      ]
      """
    let expected = """
      let a = [.red, .green]

      """
    var config = Configuration.forTesting
    config.respectsExistingLineBreaks = false
    assertPrettyPrintEqual(input: input, expected: expected, linelength: 80, configuration: config)
  }

  func testTrailingCommaKeepsFittingDictionaryLiteralVertical() {
    let input = """
      let d = [
        "a": 1,
        "b": 2,
      ]
      """
    let expected = """
      let d = [
        "a": 1,
        "b": 2,
      ]

      """
    var config = Configuration.forTesting
    config.magicTrailingComma = true
    config.respectsExistingLineBreaks = false
    assertPrettyPrintEqual(input: input, expected: expected, linelength: 80, configuration: config)
  }

  func testMagicTrailingCommaOverridesFillShortLiterals() {
    let input = "let s = [1, 2,]"
    let expected = """
      let s = [
        1,
        2,
      ]

      """
    var config = Configuration.forTesting
    config.magicTrailingComma = true
    config.collectionElementLayout = .fillShortLiterals
    config.respectsExistingLineBreaks = false
    assertPrettyPrintEqual(input: input, expected: expected, linelength: 80, configuration: config)
  }

  func testSingleElementTrailingCommaIsMagic() {
    let input = "let z = [1,]"
    let expected = """
      let z = [
        1,
      ]

      """
    var config = Configuration.forTesting
    config.magicTrailingComma = true
    config.respectsExistingLineBreaks = false
    assertPrettyPrintEqual(input: input, expected: expected, linelength: 80, configuration: config)
  }

  func testSingleElementTrailingCommaWithoutMagicIsRemoved() {
    let input = "let z = [1,]"
    let expected = """
      let z = [1]

      """
    var config = Configuration.forTesting
    config.respectsExistingLineBreaks = false
    assertPrettyPrintEqual(input: input, expected: expected, linelength: 80, configuration: config)
  }

  func testSingleElementArgumentListTrailingCommaIsMagic() {
    let input = "foo(x: 1,)"
    let expected = """
      foo(
        x: 1,
      )

      """
    var config = Configuration.forTesting
    config.magicTrailingComma = true
    config.respectsExistingLineBreaks = false
    assertPrettyPrintEqual(input: input, expected: expected, linelength: 80, configuration: config)
  }

  func testSingleElementCommaPreservedWhenRegionBreaksOnLength() {
    // The region breaks because the element does not fit, not because of the comma; the comma
    // is still kept.
    let input = #"let a = ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",]"#
    let expected = """
      let a = [
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      ]

      """
    var config = Configuration.forTesting
    config.magicTrailingComma = true
    config.respectsExistingLineBreaks = false
    assertPrettyPrintEqual(input: input, expected: expected, linelength: 45, configuration: config)
  }

  func testSingleElementDictionaryEntryCommaPreservedWhenRegionBreaks() {
    // A single-element dictionary entry whose region breaks on line length keeps the author's
    // comma.
    let input = """
      let a = [key2: ("this ", "string", "is long "),]
      """
    let expected = """
      let a = [
        key2: ("this ", "string", "is long "),
      ]

      """
    var config = Configuration.forTesting
    config.magicTrailingComma = true
    config.respectsExistingLineBreaks = false
    assertPrettyPrintEqual(input: input, expected: expected, linelength: 45, configuration: config)
  }

  func testSingleElementCommaPreservedWhenCommentPrecedesElement() {
    // A comment between the bracket and the sole element suppresses the magic fire, but the
    // comma is the author's signal and is preserved rather than silently dropped.
    let input = """
      let a = [
        // comment
        foo,
      ]
      """
    let expected = """
      let a = [
        // comment
        foo,
      ]

      """
    var config = Configuration.forTesting
    config.magicTrailingComma = true
    config.respectsExistingLineBreaks = false
    assertPrettyPrintEqual(input: input, expected: expected, linelength: 45, configuration: config)
  }

  func testTrailingCommaBreaksArgumentsBeforeTrailingClosure() {
    let input = "foo(1, 2,) { bar() }"
    let expected = """
      foo(
        1,
        2,
      ) { bar() }

      """
    var config = Configuration.forTesting
    config.magicTrailingComma = true
    config.respectsExistingLineBreaks = false
    assertPrettyPrintEqual(input: input, expected: expected, linelength: 80, configuration: config)
  }

  func testFormatterAddedTrailingCommaDoesNotReforceBreaking() {
    // A table of short scalars that is too long to fit keeps its packed rows even with
    // `magicTrailingComma` enabled: the comma the formatter adds to the broken literal must not
    // re-layout it on the next pass.
    let input = #"let xs = ["aaaaaaaa", "bbbbbbbb", "cccccccc", "dddddddd"]"#
    let expected = """
      let xs = [
        "aaaaaaaa", "bbbbbbbb", "cccccccc",
        "dddddddd",
      ]

      """
    var config = Configuration.forTesting
    config.magicTrailingComma = true
    config.collectionElementLayout = .fillShortLiterals
    config.respectsExistingLineBreaks = false
    assertPrettyPrintEqual(input: input, expected: expected, linelength: 40, configuration: config)
  }

  func testFormatterAddedCommaInOverflowingContextDoesNotReforceBreaking() {
    // The list's own content fits the line length, but the nested line does not. The comma the
    // formatter adds to the broken literal must not re-layout it on the next pass — the magic
    // comma only applies when the list fits on the line where it starts.

    let input = """
      if aaaaaaaa {
        if bbbbbbbb {
          let xs = ["aaaaaaaa", "bbbbbbbb", "cccccccc"]
        }
      }
      """
    let expected = """
      if aaaaaaaa {
        if bbbbbbbb {
          let xs = [
            "aaaaaaaa", "bbbbbbbb",
            "cccccccc",
          ]
        }
      }

      """
    var config = Configuration.forTesting
    config.magicTrailingComma = true
    config.respectsExistingLineBreaks = false
    assertPrettyPrintEqual(input: input, expected: expected, linelength: 40, configuration: config)
  }

  func testFormatterAddedCommaAfterLinePrefixDoesNotReforceBreaking() {
    // The line overflows because of the `foo(bar: `` prefix rather
    // than indentation. The formatter-added comma must still not re-layout the list.

    let input = #"let x = foo(bar: ["aaaaaaaa", "bbbbbbbb", "cccccccc", "dddddddd"])"#
    let expected = """
      let x = foo(bar: [
        "aaaaaaaa", "bbbbbbbb", "cccccccc", "dddddddd",
      ])

      """
    var config = Configuration.forTesting
    config.magicTrailingComma = true
    config.respectsExistingLineBreaks = false
    assertPrettyPrintEqual(input: input, expected: expected, linelength: 50, configuration: config)
  }

  func testAlwaysUsedCommaInOverflowingContextDoesNotReforceBreaking() {
    // `multilineTrailingCommaBehavior: alwaysUsed` adds a trailing comma to every multiline list,
    // including one that only broke because its line overflowed. That comma must not re-layout
    // the list on the next pass.
    let input = #"let x = foo(bar: ["aaaaaaaa", "bbbbbbbb", "cccccccc", "dddddddd"])"#
    let expected = """
      let x = foo(bar: [
        "aaaaaaaa", "bbbbbbbb", "cccccccc", "dddddddd",
      ])

      """
    var config = Configuration.forTesting
    config.magicTrailingComma = true
    config.multilineTrailingCommaBehavior = .alwaysUsed
    config.respectsExistingLineBreaks = false
    assertPrettyPrintEqual(input: input, expected: expected, linelength: 50, configuration: config)
  }

  func testMagicCommaIsPreservedWhenTrailingCommasWouldOtherwiseBeRemoved() {
    // `multilineTrailingCommaBehavior: neverUsed` removes trailing commas from multiline lists,
    // but a comma that forced the vertical layout is load-bearing: removing it would collapse
    // the list on the next pass, so it is preserved.
    let input = "let a = [.red, .green,]"
    let expected = """
      let a = [
        .red,
        .green,
      ]

      """
    var config = Configuration.forTesting
    config.magicTrailingComma = true
    config.multilineTrailingCommaBehavior = .neverUsed
    config.respectsExistingLineBreaks = false
    assertPrettyPrintEqual(input: input, expected: expected, linelength: 80, configuration: config)
  }

  func testMagicCommaHonoredForVerticallyWrittenList() {
    // A discretionary newline from the source after the opening delimiter must not subsume the
    // magic comma decision: the list fits on its line, so the comma still forces one element per
    // line even though the source was written partially vertically. This exercises the default
    // `respectsExistingLineBreaks` behavior.
    let input = """
      let x = [
        a, b,
      ]
      """
    let expected = """
      let x = [
        a,
        b,
      ]

      """
    var config = Configuration.forTesting
    config.magicTrailingComma = true
    assertPrettyPrintEqual(input: input, expected: expected, linelength: 80, configuration: config)
  }

  func testMagicCommaPreservedForVerticallyWrittenListWhenCommasWouldBeRemoved() {
    // The load-bearing comma is preserved under `neverUsed` regardless of whether the source was
    // written horizontally or vertically.
    let input = """
      let a = [
        .red,
        .green,
      ]
      """
    let expected = """
      let a = [
        .red,
        .green,
      ]

      """
    var config = Configuration.forTesting
    config.magicTrailingComma = true
    config.multilineTrailingCommaBehavior = .neverUsed
    assertPrettyPrintEqual(input: input, expected: expected, linelength: 80, configuration: config)
  }

  func testClosureParameterMagicCommaDoesNotAffectLaterLists() {
    // Closure parameter lists honor a magic trailing comma but are not comma-delimited regions,
    // so their fire must not leak into an unrelated later list: under `neverUsed`, the array in
    // the closure body must not gain a trailing comma.
    let input = """
      let c = { (a: Int, b: Int,) in
        let xs = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14]
      }
      """
    let expected = """
      let c = {
        (
          a: Int,
          b: Int,
        ) in
        let xs = [
          1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11,
          12, 13, 14
        ]
      }

      """
    var config = Configuration.forTesting
    config.magicTrailingComma = true
    config.multilineTrailingCommaBehavior = .neverUsed
    assertPrettyPrintEqual(input: input, expected: expected, linelength: 40, configuration: config)
  }

  func testBlankLineInsideMagicCommaListIsPreserved() {
    let input =
      """
      let x = [

        foo(), bar(),
      ]
      """
    let expected = """
      let x = [

        foo(),
        bar(),
      ]

      """
    var config = Configuration.forTesting
    config.magicTrailingComma = true
    config.respectsExistingLineBreaks = false
    assertPrettyPrintEqual(input: input, expected: expected, linelength: 80, configuration: config)
  }

  func testCommaWithCommentInListUsesConservativeFit() {
    // A comment prevents computing the list's exact single-line width, so the fits test falls
    // back to the group's conservative width: the comma is preserved, but it does not force the
    // one-element-per-line layout.
    let input =
      """
      let x = [
        // A comment keeps the row readable.
        foo(), bar(),
      ]
      """
    let expected = """
      let x = [
        // A comment keeps the row readable.
        foo(), bar(),
      ]

      """
    var config = Configuration.forTesting
    config.magicTrailingComma = true
    config.respectsExistingLineBreaks = false
    assertPrettyPrintEqual(input: input, expected: expected, linelength: 80, configuration: config)
  }

}
