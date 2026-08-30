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

final class ChainComponentBreakTests: PrettyPrintTestCase {
  func testBreaksChainComponentsEvenWhenChainFits() {
    let input =
      #"let x = Text(event.title).font(.subheadline).foregroundStyle(theme.colors.mutedLabel)"#
    let expected = """
      let x = Text(event.title)
        .font(.subheadline)
        .foregroundStyle(theme.colors.mutedLabel)

      """
    var config = Configuration.forTesting
    config.lineBreakBeforeEachChainComponent = true
    assertPrettyPrintEqual(
      input: input,
      expected: expected,
      linelength: 100,
      configuration: config
    )
  }

  func testBreaksChainRootedInCallExpression() {
    let input = #"let w = SampleView(entries: rows).component("x")"#
    let expected = """
      let w = SampleView(entries: rows)
        .component("x")

      """
    var config = Configuration.forTesting
    config.lineBreakBeforeEachChainComponent = true
    assertPrettyPrintEqual(
      input: input,
      expected: expected,
      linelength: 100,
      configuration: config
    )
  }

  func testOnlyComponentsFollowingCallsBreak() {
    let input = """
      let y = model.load()
      let z = theme.colors.accent
      let q = model.compute().result
      """
    let expected = """
      let y = model.load()
      let z = theme.colors.accent
      let q = model.compute()
        .result

      """
    var config = Configuration.forTesting
    config.lineBreakBeforeEachChainComponent = true
    assertPrettyPrintEqual(
      input: input,
      expected: expected,
      linelength: 100,
      configuration: config
    )
  }

  func testDoesNotPackShortChainComponents() {
    let input = """
      ScrollView {
        LazyVStack { rows }
      }
      .scrollBounceBehavior(.basedOnSize).frame(1, 2)
      .refreshable { await reload() }
      """
    let expected = """
      ScrollView {
        LazyVStack { rows }
      }
      .scrollBounceBehavior(.basedOnSize)
      .frame(1, 2)
      .refreshable { await reload() }

      """
    var config = Configuration.forTesting
    config.lineBreakBeforeEachChainComponent = true
    assertPrettyPrintEqual(
      input: input,
      expected: expected,
      linelength: 100,
      configuration: config
    )
  }

  func testDisabledByDefaultKeepsFittingChainOnOneLine() {
    let input =
      #"let x = Text(event.title).font(.subheadline).foregroundStyle(theme.colors.mutedLabel)"#
    let expected = """
      let x = Text(event.title).font(.subheadline).foregroundStyle(theme.colors.mutedLabel)

      """
    assertPrettyPrintEqual(input: input, expected: expected, linelength: 100)
  }

  func testSubscriptRootedChainsBreakButOptionalAndForcedDoNot() {
    let input = """
      let a = array[0].count
      let b = model?.load()
      let c = x!.y
      """
    let expected = """
      let a = array[0]
        .count
      let b = model?.load()
      let c = x!.y

      """
    var config = Configuration.forTesting
    config.lineBreakBeforeEachChainComponent = true
    assertPrettyPrintEqual(
      input: input,
      expected: expected,
      linelength: 100,
      configuration: config
    )
  }

  func testCallRootedChainsBreakThroughWrappers() {
    let input = """
      let a = foo()?.bar
      let b = (foo()).bar
      let c = model.compute()?.result
      """
    let expected = """
      let a = foo()?
        .bar
      let b = (foo())
        .bar
      let c = model.compute()?
        .result

      """
    var config = Configuration.forTesting
    config.lineBreakBeforeEachChainComponent = true
    assertPrettyPrintEqual(
      input: input,
      expected: expected,
      linelength: 100,
      configuration: config
    )
  }

  func testGenuineTuplesAreNotTreatedAsParenthesizedCalls() {
    let input = """
      let a = (x: foo()).bar
      let b = (foo(),).0
      """
    // A labeled or trailing-comma single-element tuple is a genuine tuple, so `.bar`/`.0` do not
    // follow a call and are never broken. (The missing space after the label colon is the
    // formatter's existing treatment of one-element tuples as parenthesized expressions.)
    let expected = """
      let a = (x:foo()).bar
      let b = (foo(),).0

      """
    var config = Configuration.forTesting
    config.lineBreakBeforeEachChainComponent = true
    assertPrettyPrintEqual(
      input: input,
      expected: expected,
      linelength: 100,
      configuration: config
    )
  }

  func testKeywordModifiedCallsBreakThroughParens() {
    let input = """
      let a = (await foo()).bar
      let b = (try foo()).bar
      """
    let expected = """
      let a = (await foo())
        .bar
      let b = (try foo())
        .bar

      """
    var config = Configuration.forTesting
    config.lineBreakBeforeEachChainComponent = true
    assertPrettyPrintEqual(
      input: input,
      expected: expected,
      linelength: 100,
      configuration: config
    )
  }
  func testBreaksPropagateThroughWrapperExpressionsMidChain() {
    let input = """
      let y = foo().bar?.baz()
      let w = foo().bar!.baz()
      """
    let expected = """
      let y = foo()
        .bar?
        .baz()
      let w = foo()
        .bar!
        .baz()

      """
    var config = Configuration.forTesting
    config.lineBreakBeforeEachChainComponent = true
    assertPrettyPrintEqual(
      input: input,
      expected: expected,
      linelength: 100,
      configuration: config
    )
  }

}
