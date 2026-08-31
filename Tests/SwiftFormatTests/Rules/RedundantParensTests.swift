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

@_spi(Rules) import SwiftFormat
import _SwiftFormatTestSupport

final class RedundantParensTests: LintOrFormatRuleTestCase {
  func testParensAroundIdentifierAreRemoved() {
    assertFormatting(
      RedundantParens.self,
      input: """
        let y = 1️⃣(x)
        f(2️⃣(x))
        return 3️⃣(x)
        """,
      expected: """
        let y = x
        f(x)
        return x
        """,
      findings: [
        FindingSpec("1️⃣", message: "remove the redundant parentheses around this expression"),
        FindingSpec("2️⃣", message: "remove the redundant parentheses around this expression"),
        FindingSpec("3️⃣", message: "remove the redundant parentheses around this expression"),
      ]
    )
  }

  func testParensAroundMemberChainsLiteralsSelfAndSuperAreRemoved() {
    assertFormatting(
      RedundantParens.self,
      input: """
        let a = 1️⃣(foo.bar.baz)
        let b = 2️⃣(42)
        let c = 3️⃣(self)
        let d = super.f(4️⃣(self.value))
        let e = 5️⃣("literal")
        """,
      expected: """
        let a = foo.bar.baz
        let b = 42
        let c = self
        let d = super.f(self.value)
        let e = "literal"
        """,
      findings: [
        FindingSpec("1️⃣", message: "remove the redundant parentheses around this expression"),
        FindingSpec("2️⃣", message: "remove the redundant parentheses around this expression"),
        FindingSpec("3️⃣", message: "remove the redundant parentheses around this expression"),
        FindingSpec("4️⃣", message: "remove the redundant parentheses around this expression"),
        FindingSpec("5️⃣", message: "remove the redundant parentheses around this expression"),
      ]
    )
  }

  func testNestedParensAreFullyRemovedInOnePass() {
    // In format mode the inner layer is rewritten away before it would be visited, so the
    // finding lands on the outermost layer; in lint mode the pipeline visits every original
    // layer and each gets its own finding.
    assertFormatting(
      RedundantParens.self,
      input: """
        let y = 1️⃣((x))
        """,
      expected: """
        let y = x
        """,
      findings: [FindingSpec("1️⃣", message: "remove the redundant parentheses around this expression")]
    )
  }

  func testOperatorReferencesAndLabeledTuplesAreKept() {
    assertFormatting(
      RedundantParens.self,
      input: """
        let plus: (Int, Int) -> Int = (+)
        let tuple: (label: Int) = (label: 5)
        let one = (1,)
        """,
      expected: """
        let plus: (Int, Int) -> Int = (+)
        let tuple: (label: Int) = (label: 5)
        let one = (1,)
        """,
      findings: []
    )
  }

  func testParensAroundNonAtomicExpressionsAreKept() {
    assertFormatting(
      RedundantParens.self,
      input: """
        let a = (x + y) * z
        let b = (f())
        let d: (Int, Int) = (1, 2)
        let e = (try g())
        """,
      expected: """
        let a = (x + y) * z
        let b = (f())
        let d: (Int, Int) = (1, 2)
        let e = (try g())
        """,
      findings: []
    )
  }

  func testConditionPositionsAreLeftToNoParensAroundConditions() {
    // Conditions are governed by NoParensAroundConditions; this rule must not emit duplicate
    // findings for them.
    assertFormatting(
      RedundantParens.self,
      input: """
        if (x) {}
        guard (x) else {}
        """,
      expected: """
        if (x) {}
        guard (x) else {}
        """,
      findings: []
    )
  }

  func testParensAroundCommentedInnerExpressionAreDiagnosedButKept() {
    // Comments attached to the wrapped expression's own edge tokens are preserved by keeping
    // the parentheses.
    assertFormatting(
      RedundantParens.self,
      input: """
        let a = 1️⃣(
          // explains the parens
          x
        )
        let b = 2️⃣(x /* why */)
        """,
      expected: """
        let a = (
          // explains the parens
          x
        )
        let b = (x /* why */)
        """,
      findings: [
        FindingSpec("1️⃣", message: "remove the redundant parentheses around this expression"),
        FindingSpec("2️⃣", message: "remove the redundant parentheses around this expression"),
      ]
    )
  }

  func testRepeatWhileConditionsAreLeftToNoParensAroundConditions() {
    assertFormatting(
      RedundantParens.self,
      input: """
        repeat {} while (x)
        """,
      expected: """
        repeat {} while (x)
        """,
      findings: []
    )
  }

  func testParensContainingCommentsAreDiagnosedButKept() {
    assertFormatting(
      RedundantParens.self,
      input: """
        let y = 1️⃣(/* wrap */ x)
        """,
      expected: """
        let y = (/* wrap */ x)
        """,
      findings: [FindingSpec("1️⃣", message: "remove the redundant parentheses around this expression")]
    )
  }
}
