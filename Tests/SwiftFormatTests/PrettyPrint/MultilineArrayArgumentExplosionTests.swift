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

final class MultilineArrayArgumentExplosionTests: PrettyPrintTestCase {
  func testMultilineLiteralExplodesAllCallElementsWithMultipleArguments() {
    let input =
      #"let rows = [Widget(spec: SampleData.Registry.alpha, status: .loading(batch: "Processing")), Widget(spec: bravo, status: .done)]"#
    let expected = """
      let rows = [
        Widget(
          spec: SampleData.Registry.alpha,
          status: .loading(batch: "Processing")
        ),
        Widget(
          spec: bravo,
          status: .done
        ),
      ]

      """
    var config = Configuration.forTesting
    config.forceBrokenArgumentsInMultilineArrayLiterals = true
    assertPrettyPrintEqual(
      input: input,
      expected: expected,
      linelength: 100,
      configuration: config
    )
  }

  func testLiteralThatFitsOnOneLineIsUnaffected() {
    let input = #"let rows = [Widget(spec: alpha, status: .done), Widget(spec: bravo, status: .loading)]"#
    let expected = input + "\n"
    var config = Configuration.forTesting
    config.forceBrokenArgumentsInMultilineArrayLiterals = true
    assertPrettyPrintEqual(
      input: input,
      expected: expected,
      linelength: 100,
      configuration: config
    )
  }

  func testSingleArgumentCallElementsStayCompact() {
    let input =
      #"let t = [m(a: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", b: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"), m(a: "z")]"#
    let expected = """
      let t = [
        m(
          a: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          b: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        ), m(a: "z"),
      ]

      """
    var config = Configuration.forTesting
    config.forceBrokenArgumentsInMultilineArrayLiterals = true
    assertPrettyPrintEqual(
      input: input,
      expected: expected,
      linelength: 100,
      configuration: config
    )
  }

  func testMagicCommaForcedLiteralPropagatesVerticality() {
    let input = #"let t = [m(a: "x", b: "y"),]"#
    let expected = """
      let t = [
        m(
          a: "x",
          b: "y"
        ),
      ]

      """
    var config = Configuration.forTesting
    config.magicTrailingComma = true
    config.forceBrokenArgumentsInMultilineArrayLiterals = true
    assertPrettyPrintEqual(
      input: input,
      expected: expected,
      linelength: 100,
      configuration: config
    )
  }

  func testDisabledByDefaultLeavesArgumentsCompact() {
    let input =
      #"let rows = [Widget(spec: SampleData.Registry.alpha, status: .loading(batch: "Processing")), Widget(spec: bravo, status: .done)]"#
    let expected = """
      let rows = [
        Widget(spec: SampleData.Registry.alpha, status: .loading(batch: "Processing")),
        Widget(spec: bravo, status: .done),
      ]

      """
    assertPrettyPrintEqual(input: input, expected: expected, linelength: 100)
  }
  func testElementArgumentMagicCommaTakesPrecedenceOverPropagation() {
    let input = #"let t = [m(a: 1, b: 2,), n(c: 3, d: 4)]"#
    let expected = """
      let t = [
        m(
          a: 1,
          b: 2,
        ),
        n(
          c: 3,
          d: 4
        ),
      ]

      """
    var config = Configuration.forTesting
    config.magicTrailingComma = true
    config.forceBrokenArgumentsInMultilineArrayLiterals = true
    assertPrettyPrintEqual(
      input: input,
      expected: expected,
      linelength: 100,
      configuration: config
    )
  }

  func testVerticalityPropagatesPerLiteralInNestedArrays() {
    let input = #"let t = [[m(a: 1, b: 2), m(a: 3, b: 4)], [n(c: 5, d: 6)]]"#
    let expected = """
      let t = [
        [
          m(
            a: 1,
            b: 2
          ),
          m(
            a: 3,
            b: 4
          ),
        ], [n(c: 5, d: 6)],
      ]

      """
    var config = Configuration.forTesting
    config.forceBrokenArgumentsInMultilineArrayLiterals = true
    assertPrettyPrintEqual(
      input: input,
      expected: expected,
      linelength: 30,
      configuration: config
    )
  }

  func testDictionaryLiteralsAreUnaffected() {
    let input = #"let d = [a: m(x: 1, y: 2), b: m(x: 3, y: 4)]"#
    let expected = """
      let d = [
        a: m(x: 1, y: 2),
        b: m(x: 3, y: 4),
      ]

      """
    var config = Configuration.forTesting
    config.forceBrokenArgumentsInMultilineArrayLiterals = true
    assertPrettyPrintEqual(
      input: input,
      expected: expected,
      linelength: 30,
      configuration: config
    )
  }

  func testAuthorLineBreakInsideElementBreaksListOpen() {
    let input = """
      let t = [m(a: 1,
        b: 2), n(c: 3, d: 4)]
      """
    let expected = """
      let t = [
        m(
          a: 1,
          b: 2
        ),
        n(
          c: 3,
          d: 4
        ),
      ]

      """
    var config = Configuration.forTesting
    config.forceBrokenArgumentsInMultilineArrayLiterals = true
    assertPrettyPrintEqual(
      input: input,
      expected: expected,
      linelength: 100,
      configuration: config
    )
  }

}
