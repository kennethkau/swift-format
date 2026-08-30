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

final class CodeBlockBodyBreakTests: PrettyPrintTestCase {
  func testFunctionAndInitializerBodiesBreakOpen() {
    let input = """
      struct Foo {
        func f() { bar() }
        init() { setup() }
      }
      """
    let expected = """
      struct Foo {
        func f() {
          bar()
        }
        init() {
          setup()
        }
      }

      """
    var config = Configuration.forTesting
    config.forceBrokenCodeBlockBodies = true
    assertPrettyPrintEqual(
      input: input,
      expected: expected,
      linelength: 100,
      configuration: config
    )
  }

  func testControlFlowStatementBodiesBreakOpen() {
    let input = """
      func k() {
        if x { y() }
        guard z else { return }
        for i in items { process(i) }
        while running { spin() }
        do { try work() } catch { recover() }
      }
      """
    let expected = """
      func k() {
        if x {
          y()
        }
        guard z else {
          return
        }
        for i in items {
          process(i)
        }
        while running {
          spin()
        }
        do {
          try work()
        } catch {
          recover()
        }
      }

      """
    var config = Configuration.forTesting
    config.forceBrokenCodeBlockBodies = true
    assertPrettyPrintEqual(
      input: input,
      expected: expected,
      linelength: 100,
      configuration: config
    )
  }

  func testSwitchCaseBodiesBreakBelowLabel() {
    let input = """
      switch value {
      case .a: return 0
      default: break
      }
      """
    let expected = """
      switch value {
      case .a:
        return 0
      default:
        break
      }

      """
    var config = Configuration.forTesting
    config.forceBrokenCodeBlockBodies = true
    assertPrettyPrintEqual(
      input: input,
      expected: expected,
      linelength: 100,
      configuration: config
    )
  }

  func testImplicitAccessorBodyIsUnaffected() {
    let input = #"var h: Int { 5 }"#
    let expected = """
      var h: Int { 5 }

      """
    var config = Configuration.forTesting
    config.forceBrokenCodeBlockBodies = true
    assertPrettyPrintEqual(
      input: input,
      expected: expected,
      linelength: 100,
      configuration: config
    )
  }

  func testEmptyFunctionBodyIsUnaffected() {
    let input = """
      struct Foo {
        func f() {}
      }
      """
    let expected = """
      struct Foo {
        func f() {}
      }

      """
    var config = Configuration.forTesting
    config.forceBrokenCodeBlockBodies = true
    assertPrettyPrintEqual(
      input: input,
      expected: expected,
      linelength: 100,
      configuration: config
    )
  }

  func testMemberBlockWithSingleMemberIsUnaffected() {
    let input = #"struct Point { let x: Int }"#
    let expected = """
      struct Point { let x: Int }

      """
    var config = Configuration.forTesting
    config.forceBrokenCodeBlockBodies = true
    assertPrettyPrintEqual(
      input: input,
      expected: expected,
      linelength: 100,
      configuration: config
    )
  }

  func testComposesWithForceBrokenClosureBodies() {
    let input = #"func render() { Group { content() } }"#
    let expected = """
      func render() {
        Group {
          content()
        }
      }

      """
    var config = Configuration.forTesting
    config.forceBrokenCodeBlockBodies = true
    config.forceBrokenClosureBodies = true
    assertPrettyPrintEqual(
      input: input,
      expected: expected,
      linelength: 100,
      configuration: config
    )
  }

  func testDisabledByDefaultKeepsCompactBodies() {
    let input = """
      struct Foo {
        func f() { bar() }
      }
      """
    let expected = """
      struct Foo {
        func f() { bar() }
      }

      """
    assertPrettyPrintEqual(input: input, expected: expected, linelength: 100)
  }
  func testDeferBodyBreaksOpen() {
    let input = #"func f() { defer { cleanup() } }"#
    let expected = """
      func f() {
        defer {
          cleanup()
        }
      }

      """
    var config = Configuration.forTesting
    config.forceBrokenCodeBlockBodies = true
    assertPrettyPrintEqual(
      input: input,
      expected: expected,
      linelength: 100,
      configuration: config
    )
  }

  func testExplicitAccessorBodiesBreakOpen() {
    let input = #"var x: Int { get { return compute() } set { stored = newValue } }"#
    let expected = """
      var x: Int {
        get {
          return compute()
        }
        set {
          stored = newValue
        }
      }

      """
    var config = Configuration.forTesting
    config.forceBrokenCodeBlockBodies = true
    assertPrettyPrintEqual(
      input: input,
      expected: expected,
      linelength: 100,
      configuration: config
    )
  }

  func testRepeatWhileBodyBreaksOpen() {
    let input = #"func f() { repeat { spin() } while running }"#
    let expected = """
      func f() {
        repeat {
          spin()
        } while running
      }

      """
    var config = Configuration.forTesting
    config.forceBrokenCodeBlockBodies = true
    assertPrettyPrintEqual(
      input: input,
      expected: expected,
      linelength: 100,
      configuration: config
    )
  }

}
