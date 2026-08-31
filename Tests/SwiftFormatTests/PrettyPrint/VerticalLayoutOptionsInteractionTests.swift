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

/// Gates for the canonical vertical layout options: the layout must be idempotent, its output
/// must not depend on how the source was line-wrapped, and it must never glue conditional
/// compilation blocks onto adjacent code.
final class VerticalLayoutOptionsInteractionTests: PrettyPrintTestCase {
  private func makeVerticalLayoutConfiguration() -> Configuration {
    var config = Configuration.forTesting
    config.respectsExistingLineBreaks = false
    config.lineBreakBeforeEachArgument = true
    config.lineBreakBetweenDeclarationAttributes = true
    config.lineBreakAroundMultilineExpressionChainComponents = true
    config.multilineTrailingCommaBehavior = .alwaysUsed
    config.lineBreakBeforeEachChainComponent = true
    config.attachLoneDeclarationAttributes = true
    config.collectionElementLayout = .onePerLine
    config.magicTrailingComma = true
    config.forceBrokenArgumentsInMultilineArrayLiterals = true
    config.forceBrokenClosureBodies = true
    config.forceBrokenCodeBlockBodies = true
    return config
  }

  func testVerticalLayoutIsIdempotentAcrossConstructs() {
    let input = """
      struct Screen: View {
        private let rows: [Row]

        var body: some View {
          #Preview("Main") { NavigationStack { Screen() } }
          ScrollView {
            LazyVStack { rows }
          }
          .scrollBounceBehavior(.basedOnSize).frame(1, 2)
          .refreshable { await reload() }
          if let first = rows.first { show(first) }
          let table = [Widget(spec: alpha, status: .done), Widget(spec: bravo, status: .loading)]
          let magic = [first, second,]
          let total = wideCondition ? computeFirstPart() : computeSecondPartWithFallback()
        }
      }
      """
    let expected = """
      struct Screen: View {
        private let rows: [Row]

        var body: some View {
          #Preview("Main") {
            NavigationStack {
              Screen()
            }
          }
          ScrollView {
            LazyVStack {
              rows
            }
          }
          .scrollBounceBehavior(.basedOnSize)
          .frame(1, 2)
          .refreshable {
            await reload()
          }
          if let first = rows.first {
            show(first)
          }
          let table = [Widget(spec: alpha, status: .done), Widget(spec: bravo, status: .loading)]
          let magic = [
            first,
            second,
          ]
          let total = wideCondition ? computeFirstPart() : computeSecondPartWithFallback()
        }
      }

      """
    // The test harness formats the expected output a second time and fails on any difference,
    // so each test also verifies that formatting the output again leaves it unchanged.
    assertPrettyPrintEqual(
      input: input,
      expected: expected,
      linelength: 100,
      configuration: makeVerticalLayoutConfiguration()
    )
  }

  func testLayoutIsIndependentOfSourceLineBreaks() {
    let expected = """
      struct Card: View {
        var body: some View {
          HStack {
            Text(title)
              .font(.headline)
              .foregroundStyle(.secondary)
          }
        }
      }

      """
    let horizontal =
      "struct Card: View { var body: some View { HStack { "
      + "Text(title).font(.headline).foregroundStyle(.secondary) } } }"
    let vertical = """
      struct Card: View {
        var body: some View {
          HStack {
            Text(title)
              .font(.headline)
              .foregroundStyle(.secondary)
          }
        }
      }
      """
    let config = makeVerticalLayoutConfiguration()
    assertPrettyPrintEqual(
      input: horizontal,
      expected: expected,
      linelength: 100,
      configuration: config
    )
    assertPrettyPrintEqual(
      input: vertical,
      expected: expected,
      linelength: 100,
      configuration: config
    )
  }

  func testChainComponentInsidePostfixIfConfigStaysValid() {
    let input = """
      struct Row: View {
        var body: some View {
          Group { content() }
          #if os(macOS)
            .padding(4)
          #endif
          Text(verbatim: label).bold()
        }
      }
      """
    let expected = """
      struct Row: View {
        var body: some View {
          Group {
            content()
          }
          #if os(macOS)
            .padding(4)
          #endif
          Text(verbatim: label)
            .bold()
        }
      }

      """
    assertPrettyPrintEqual(
      input: input,
      expected: expected,
      linelength: 100,
      configuration: makeVerticalLayoutConfiguration()
    )
  }

  func testDeclarationAfterEndifStaysOnItsOwnLine() {
    let input = """
      #if DEBUG
      struct DebugRow: View { var body: some View { Text("debug") } }
      #endif
      struct AfterIf: View { var body: some View { Text("after") } }
      """
    let expected = """
      #if DEBUG
        struct DebugRow: View { var body: some View { Text("debug") } }
      #endif
      struct AfterIf: View { var body: some View { Text("after") } }

      """
    assertPrettyPrintEqual(
      input: input,
      expected: expected,
      linelength: 100,
      configuration: makeVerticalLayoutConfiguration()
    )
  }
}
