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

final class CollectionElementLayoutTests: PrettyPrintTestCase {
  func testOnePerLineBreaksEachElementOntoItsOwnLine() {
    // At this line length the default binPack layout would pack two elements per row, so this
    // test distinguishes onePerLine from both binPack and the plain line-length break.
    let input = #"let deps = [dep("alpha"), dep("beta"), dep("gamma")]"#
    let expected = """
      let deps = [
        dep("alpha"),
        dep("beta"),
        dep("gamma"),
      ]

      """
    var config = Configuration.forTesting
    config.collectionElementLayout = .onePerLine
    assertPrettyPrintEqual(input: input, expected: expected, linelength: 40, configuration: config)
  }

  func testFillShortLiteralsBreaksStructuredElements() {
    // Call elements are not short scalar literals, so they go one per line even though binPack
    // would fit two per row (as in the onePerLine test above).
    let input = #"let deps = [dep("alpha"), dep("beta"), dep("gamma")]"#
    let expected = """
      let deps = [
        dep("alpha"),
        dep("beta"),
        dep("gamma"),
      ]

      """
    var config = Configuration.forTesting
    config.collectionElementLayout = .fillShortLiterals
    assertPrettyPrintEqual(input: input, expected: expected, linelength: 40, configuration: config)
  }

  func testFittingLiteralsAreUnchangedInAllModes() {
    let input = "let xs = [1, 2, 3]"
    let expected = """
      let xs = [1, 2, 3]

      """
    for mode in Configuration.CollectionElementLayout.allCases {
      var config = Configuration.forTesting
      config.collectionElementLayout = mode
      assertPrettyPrintEqual(
        input: input,
        expected: expected,
        linelength: 80,
        configuration: config
      )
    }
  }

  func testBinPackPacksRowsByDefault() {
    let input = "let xs = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]"
    let expected = """
      let xs = [
        1, 2, 3, 4, 5, 6, 7, 8, 9,
        10, 11, 12,
      ]

      """
    assertPrettyPrintEqual(input: input, expected: expected, linelength: 30)
  }

  func testFillShortLiteralsPacksShortScalars() {
    let input = "let xs = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]"
    let expected = """
      let xs = [
        1, 2, 3, 4, 5, 6, 7, 8, 9,
        10, 11, 12,
      ]

      """
    var config = Configuration.forTesting
    config.collectionElementLayout = .fillShortLiterals
    assertPrettyPrintEqual(input: input, expected: expected, linelength: 30, configuration: config)
  }

  func testFillShortLiteralsPacksMixedKindsOfShortScalars() {
    let input = #"let values = ["a", "b", true, nil, .red, .green, "xy", false, .blue]"#
    let expected = """
      let values = [
        "a", "b", true, nil, .red, .green, "xy",
        false, .blue,
      ]

      """
    var config = Configuration.forTesting
    config.collectionElementLayout = .fillShortLiterals
    assertPrettyPrintEqual(input: input, expected: expected, linelength: 45, configuration: config)
  }

  func testOnePerLineBreaksShortScalars() {
    let input = "let xs = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]"
    let expected = """
      let xs = [
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
        9,
        10,
        11,
        12,
      ]

      """
    var config = Configuration.forTesting
    config.collectionElementLayout = .onePerLine
    assertPrettyPrintEqual(input: input, expected: expected, linelength: 30, configuration: config)
  }

  func testFillShortLiteralsBreaksWhenAnyElementIsTooLong() {
    let input = #"let xs = ["ok", "this-string-is-long", "hi"]"#
    let expected = """
      let xs = [
        "ok",
        "this-string-is-long",
        "hi",
      ]

      """
    var config = Configuration.forTesting
    config.collectionElementLayout = .fillShortLiterals
    assertPrettyPrintEqual(input: input, expected: expected, linelength: 30, configuration: config)
  }

  func testFillShortLiteralsBreaksWhenAnyElementHasAPrecedingComment() {
    let input = "let xs = [1, 2, /* c */ 3, 4]"
    var config = Configuration.forTesting
    config.collectionElementLayout = .fillShortLiterals
    // The elements must not be packed into shared rows when a comment is
    // present; the comment is attached to the preceding line.
    assertPrettyPrintEqual(
      input: input,
      expected: """
        let xs = [
          1,
          2, /* c */
          3,
          4,
        ]

        """,
      linelength: 20,
      configuration: config
    )
  }

  func testDictionaryOnePerLine() {
    let input = #"let d = ["a": 1, "b": 2, "c": 3]"#
    let expected = """
      let d = [
        "a": 1,
        "b": 2,
        "c": 3,
      ]

      """
    var config = Configuration.forTesting
    config.collectionElementLayout = .onePerLine
    assertPrettyPrintEqual(input: input, expected: expected, linelength: 20, configuration: config)
  }

  func testDictionaryFillShortLiteralsPacksShortEntries() {
    let input = #"let d = ["a": 1, "b": 2, "c": 3]"#
    let expected = """
      let d = [
        "a": 1, "b": 2,
        "c": 3,
      ]

      """
    var config = Configuration.forTesting
    config.collectionElementLayout = .fillShortLiterals
    assertPrettyPrintEqual(input: input, expected: expected, linelength: 24, configuration: config)
  }
  func testSignedLiteralsArePackedInFillShortLiterals() {
    let input = #"let n = [-1, -2, -3, -4, -5, -6, -7, -8, -9, -10, -11, -12]"#
    let expected = """
      let n = [
        -1, -2, -3, -4, -5, -6, -7, -8, -9,
        -10, -11, -12,
      ]

      """
    var config = Configuration.forTesting
    config.collectionElementLayout = .fillShortLiterals
    assertPrettyPrintEqual(
      input: input,
      expected: expected,
      linelength: 40,
      configuration: config
    )
  }

}
