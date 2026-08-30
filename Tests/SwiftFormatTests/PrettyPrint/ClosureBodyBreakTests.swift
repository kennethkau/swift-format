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

final class ClosureBodyBreakTests: PrettyPrintTestCase {
  func testPreviewMacroTrailingClosureBreaksOpen() {
    let input = #"#Preview("ContentView") { NavigationStack { ContentView() } }"#
    let expected = """
      #Preview("ContentView") {
        NavigationStack {
          ContentView()
        }
      }

      """
    var config = Configuration.forTesting
    config.forceBrokenClosureBodies = true
    assertPrettyPrintEqual(
      input: input,
      expected: expected,
      linelength: 100,
      configuration: config
    )
  }

  func testTrailingClosureInCallBreaksOpen() {
    let input = #"Button("Tap") { save() }"#
    let expected = """
      Button("Tap") {
        save()
      }

      """
    var config = Configuration.forTesting
    config.forceBrokenClosureBodies = true
    assertPrettyPrintEqual(
      input: input,
      expected: expected,
      linelength: 100,
      configuration: config
    )
  }

  func testClosureLiteralBreaksOpen() {
    let input = #"let action = { reset() }"#
    let expected = """
      let action = {
        reset()
      }

      """
    var config = Configuration.forTesting
    config.forceBrokenClosureBodies = true
    assertPrettyPrintEqual(
      input: input,
      expected: expected,
      linelength: 100,
      configuration: config
    )
  }

  func testNonTrailingClosureArgumentBreaksOpen() {
    let input = #"list.map({ $0 + 1 })"#
    let expected = """
      list.map({
        $0 + 1
      })

      """
    var config = Configuration.forTesting
    config.forceBrokenClosureBodies = true
    assertPrettyPrintEqual(
      input: input,
      expected: expected,
      linelength: 100,
      configuration: config
    )
  }

  func testClosureSignatureStaysAttachedToOpeningBrace() {
    let input = #"list.forEach { item in print(item) }"#
    let expected = """
      list.forEach { item in
        print(item)
      }

      """
    var config = Configuration.forTesting
    config.forceBrokenClosureBodies = true
    assertPrettyPrintEqual(
      input: input,
      expected: expected,
      linelength: 100,
      configuration: config
    )
  }

  func testEmptyClosureIsUnaffected() {
    let input = #"let empty = {}"#
    let expected = """
      let empty = {}

      """
    var config = Configuration.forTesting
    config.forceBrokenClosureBodies = true
    assertPrettyPrintEqual(
      input: input,
      expected: expected,
      linelength: 100,
      configuration: config
    )
  }

  func testMultipleStatementClosureBreaksByDefault() {
    let input = """
      Button("Tap") {
        save()
        dismiss()
      }
      """
    let expected = """
      Button("Tap") {
        save()
        dismiss()
      }

      """
    var config = Configuration.forTesting
    config.forceBrokenClosureBodies = true
    assertPrettyPrintEqual(
      input: input,
      expected: expected,
      linelength: 100,
      configuration: config
    )
  }

  func testDisabledByDefaultKeepsSingleStatementClosureInline() {
    let input = #"Button("Tap") { save() }"#
    let expected = input + "\n"
    assertPrettyPrintEqual(input: input, expected: expected, linelength: 100)
  }
  func testMultipleTrailingClosuresAllBreakOpen() {
    let input = #"Button { save() } label: { Text("Tap") }"#
    let expected = """
      Button {
        save()
      } label: {
        Text("Tap")
      }

      """
    var config = Configuration.forTesting
    config.forceBrokenClosureBodies = true
    assertPrettyPrintEqual(
      input: input,
      expected: expected,
      linelength: 100,
      configuration: config
    )
  }

}
