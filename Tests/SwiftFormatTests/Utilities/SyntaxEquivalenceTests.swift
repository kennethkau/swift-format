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

@_spi(Internal) import SwiftFormat
@_spi(ExperimentalLanguageFeatures) import SwiftParser
import SwiftSyntax
import XCTest

final class SyntaxEquivalenceTests: XCTestCase {
  private func assertEquivalent(
    _ original: String,
    _ formatted: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws {
    let originalTree = try SyntaxVerifier.parseFolded(original)
    let formattedTree = try SyntaxVerifier.parseFolded(formatted)
    let mismatches = SyntaxVerifier.verify(original: originalTree, formatted: formattedTree)
    XCTAssertTrue(
      mismatches.isEmpty,
      "expected equivalent trees but found \(mismatches.count) mismatches: \(mismatches.map(\.description))",
      file: file,
      line: line
    )
  }

  private func assertNotEquivalent(
    _ original: String,
    _ formatted: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws {
    let originalTree = try SyntaxVerifier.parseFolded(original)
    let formattedTree = try SyntaxVerifier.parseFolded(formatted)
    let mismatches = SyntaxVerifier.verify(original: originalTree, formatted: formattedTree)
    XCTAssertFalse(
      mismatches.isEmpty,
      "expected a mismatch but the trees were treated as equivalent",
      file: file,
      line: line
    )
  }

  // MARK: - Trivia and formatting-only differences are equivalent

  func testWhitespaceDifferencesAreEquivalent() throws {
    try assertEquivalent(
      """
      struct Foo {
        let a=1
      }
      """,
      """
      struct Foo {
        let a = 1
      }
      """
    )
  }

  func testCommentChangesAreEquivalent() throws {
    try assertEquivalent(
      """
      // A comment.
      let a = 1
      """,
      """
      // A different comment.
      // Now two lines.

      let a = 1
      """
    )
  }

  func testLineWrappingIsEquivalent() throws {
    try assertEquivalent(
      "let pair = (first, second)\n",
      """
      let pair = (
        first,
        second
      )
      """
    )
  }

  // MARK: - Documented tolerances

  func testRedundantParensAreEquivalent() throws {
    try assertEquivalent("let x = (1)\n", "let x = 1\n")
    try assertEquivalent("if (x) { }\n", "if x { }\n")
    try assertEquivalent("let x = ((1))\n", "let x = 1\n")
  }

  func testLabeledTupleIsNotUnwrapped() throws {
    try assertNotEquivalent("let x = (a: 1)\n", "let x = 1\n")
  }

  func testRedundantSelfIsEquivalent() throws {
    try assertEquivalent(
      """
      struct Foo {
        func bar() -> Int {
          return self.baz
        }
      }
      """,
      """
      struct Foo {
        func bar() -> Int {
          return baz
        }
      }
      """
    )
  }

  func testSelfRemovalIsEquivalentUnderShadowing() throws {
    // The comparison is syntactic: `self.a` compares equal to `a` even where a local binding
    // shadows the member, licensing the rewrites RedundantSelf performs.
    try assertEquivalent(
      """
      struct S {
        var a = 1
        func f(a: Int) -> Int {
          return self.a
        }
      }
      """,
      """
      struct S {
        var a = 1
        func f(a: Int) -> Int {
          return a
        }
      }
      """
    )
  }

  func testSelfBaseMismatchOnOtherBaseIsNotEquivalent() throws {
    try assertNotEquivalent("let x = self.a\n", "let x = other.a\n")
    try assertNotEquivalent("let x = self.a\n", "let x = b\n")
  }

  func testEmptyTupleTypeIsEquivalentToVoid() throws {
    try assertEquivalent("func f() -> () { }\n", "func f() -> Void { }\n")
  }

  func testEmptyTupleTypeIsNotEquivalentToNonEmptyTupleType() throws {
    try assertNotEquivalent("func f() -> (Int) { }\n", "func f() -> Void { }\n")
  }

  func testNumericLiteralSpellingsAreEquivalent() throws {
    try assertEquivalent("let a = 1_000\n", "let a = 1000\n")
    try assertEquivalent("let a = 0xffab\n", "let a = 0xFFAB\n")
    try assertEquivalent("let a = 0000000\n", "let a = 0\n")
    try assertEquivalent("let a = 001234567\n", "let a = 1_234_567\n")
    try assertEquivalent("let a = 000.500\n", "let a = 0.5\n")
    try assertEquivalent("let a = 1.5E3\n", "let a = 1.5e3\n")
    try assertEquivalent("let a = 1.5e03\n", "let a = 1.5e3\n")
    try assertEquivalent("let a = 0x1.8p2\n", "let a = 0x1.80p02\n")
  }

  func testNumericLiteralValueChangeIsNotEquivalent() throws {
    try assertNotEquivalent("let a = 1000\n", "let a = 1001\n")
    try assertNotEquivalent("let a = 0xffab\n", "let a = 0xffac\n")
    try assertNotEquivalent("let a = 0.5\n", "let a = 0.6\n")
  }

  func testStringLiteralSpellingsAreEquivalent() throws {
    try assertEquivalent("let s = \"a\\\"b\"\n", "let s = #\"a\"b\"#\n")
    try assertEquivalent("let s = \"\\u{41}\"\n", "let s = \"A\"\n")
    try assertEquivalent("let s = \"it\\'s\"\n", "let s = \"it's\"\n")
    try assertEquivalent("let s = \"tab\\t\"\n", "let s = \"tab\\u{9}\"")
    try assertEquivalent("let s = ##\"has #\" inside\"##\n", "let s = #\"has #\" inside\"#")
  }

  func testStringLiteralContentChangeIsNotEquivalent() throws {
    try assertNotEquivalent("let s = \"abc\"\n", "let s = \"abd\"\n")
    try assertNotEquivalent("let s = \"a\"\n", "let s = \"ab\"\n")
  }

  func testInterpolationChangesAreNotEquivalent() throws {
    try assertNotEquivalent("let s = \"\\(a)\"\n", "let s = \"\\(b)\"\n")
    try assertNotEquivalent("let s = \"\\(a + 1)\"\n", "let s = \"\\(a + 2)\"\n")
  }

  func testInterpolationValueExpressionsAreEquivalent() throws {
    try assertEquivalent("let s = \"\\(a)\"\n", "let s = #\"\\#(a)\"#")
  }

  func testMultilineStringIsEquivalentToItselfWithDifferentIndentation() throws {
    try assertEquivalent(
      """
      let s = \"\"\"
        abc
        \"\"\"
      """,
      """
      let s = \"\"\"
      abc
      \"\"\"
      """
    )
  }

  func testImportReorderingIsEquivalent() throws {
    try assertEquivalent(
      """
      import Zebra
      import Apple
      struct Foo {}
      """,
      """
      import Apple
      import Zebra
      struct Foo {}
      """
    )
  }

  func testImportAdditionIsNotEquivalent() throws {
    try assertNotEquivalent(
      """
      import Zebra
      struct Foo {}
      """,
      """
      import Zebra
      import Apple
      struct Foo {}
      """
    )
  }

  func testModifierReorderingIsEquivalent() throws {
    try assertEquivalent(
      "static public func f() {}\n",
      "public static func f() {}\n"
    )
  }

  func testModifierRemovalIsNotEquivalent() throws {
    try assertNotEquivalent(
      "public static func f() {}\n",
      "public func f() {}\n"
    )
  }

  func testAttributeReorderingIsEquivalent() throws {
    try assertEquivalent(
      """
      @discardableResult
      @available(iOS 1, *)
      func f() {}
      """,
      """
      @available(iOS 1, *)
      @discardableResult
      func f() {}
      """
    )
  }

  func testAttributeRemovalIsNotEquivalent() throws {
    try assertNotEquivalent(
      """
      @discardableResult
      func f() {}
      """,
      """
      func f() {}
      """
    )
  }

  func testTrailingCommasAreEquivalent() throws {
    try assertEquivalent("f(a: 1, b: 2)\n", "f(a: 1, b: 2,)\n")
    try assertEquivalent(
      "func f(a: Int, b: Int) {}\n",
      "func f(a: Int, b: Int,) {}\n"
    )
  }

  func testTrailingSemicolonsAreEquivalent() throws {
    try assertEquivalent("let a = 1\nlet b = 2\n", "let a = 1;\nlet b = 2\n")
  }

  func testAccessLevelOnExtensionIsEquivalentToMembers() throws {
    try assertEquivalent(
      """
      fileprivate extension Foo {
        var x: Int { 1 }
      }
      """,
      """
      extension Foo {
        fileprivate var x: Int { 1 }
      }
      """
    )
  }

  func testCaseLetDistributionIsEquivalent() throws {
    try assertEquivalent(
      "switch x { case let .foo(y): break }\n",
      "switch x { case .foo(let y): break }\n"
    )
  }

  func testAccessLevelRemovalIsNotEquivalent() throws {
    try assertNotEquivalent(
      """
      public extension Foo {
        var x: Int { 1 }
      }
      """,
      """
      extension Foo {
        var x: Int { 1 }
      }
      """
    )
  }

  func testVoidReturnClauseRemovalIsEquivalent() throws {
    try assertEquivalent("func f() -> Void { g() }\n", "func f() { g() }\n")
    try assertEquivalent("func f() -> () { g() }\n", "func f() { g() }\n")
  }

  func testNonVoidReturnClauseRemovalIsNotEquivalent() throws {
    try assertNotEquivalent("func f() -> Int { 1 }\n", "func f() { 1 }\n")
  }

  func testShorthandTypeNamesAreEquivalent() throws {
    try assertEquivalent("var x: Array<Int> = []\n", "var x: [Int] = []\n")
    try assertEquivalent("var x: Dictionary<String, Int> = [:]\n", "var x: [String: Int] = [:]\n")
    try assertEquivalent("var x: Optional<String> = nil\n", "var x: String? = nil\n")
    try assertEquivalent("let a = Array<Int>()\n", "let a = [Int]()\n")
    try assertEquivalent("let b = Dictionary<String, Int>()\n", "let b = [String: Int]()\n")
  }

  func testShorthandTypeArgumentChangeIsNotEquivalent() throws {
    try assertNotEquivalent("var x: Array<Int> = []\n", "var x: [String] = []\n")
  }

  func testSequenceFoldingHandlesRedundantOperatorParens() throws {
    // Both trees are operator-folded before comparison, so a parenthesized operand compares by
    // its folded shape rather than as a flat sequence element.
    try assertEquivalent("let x = 1 + (2 * 3)\n", "let x = 1 + 2 * 3\n")
  }

  func testParseFoldedHonorsLanguageFeatures() throws {
    let source = "let x = do { 1 }\n"
    let without = try SyntaxVerifier.parseFolded(source)
    XCTAssertTrue(without.hasError, "fixture must require the feature to parse")
    let with = try SyntaxVerifier.parseFolded(source, languageFeatures: [.doExpressions])
    XCTAssertFalse(with.hasError)
  }

  func testRecoveryTreesAreRefused() throws {
    let original = try SyntaxVerifier.parseFolded("func f() {")
    let formatted = try SyntaxVerifier.parseFolded("func f() {")
    let mismatches = SyntaxVerifier.verify(original: original, formatted: formatted)
    XCTAssertEqual(mismatches.count, 1)
    XCTAssertEqual(
      mismatches[0].description,
      "the source or the formatted output does not parse cleanly"
    )
  }

  func testPathologicalNestingFailsInsteadOfRecursingForever() {
    // Built programmatically: the parser's own nesting limit rejects deeply nested source
    // before the comparator's cap could engage, so only constructed trees reach it. The trees
    // match for hundreds of levels and differ only at the bottom.
    func deepNestedTuple(around inner: ExprSyntax, depth: Int) -> ExprSyntax {
      var expr = inner
      for _ in 0..<depth {
        expr = ExprSyntax(
          TupleExprSyntax(
            elements: LabeledExprListSyntax([
              // Labeled, so the parenthesis tolerance cannot unwrap it.
              LabeledExprSyntax(
                label: .identifier("a"),
                colon: .colonToken(),
                expression: expr
              )
            ])
          )
        )
      }
      return expr
    }

    func fileWrapping(_ value: ExprSyntax) -> SourceFileSyntax {
      let binding = PatternBindingSyntax(
        pattern: IdentifierPatternSyntax(identifier: .identifier("x")),
        initializer: InitializerClauseSyntax(equal: .equalToken(), value: value)
      )
      let item = CodeBlockItemSyntax(
        item: CodeBlockItemSyntax.Item.decl(
          DeclSyntax(
            VariableDeclSyntax(
              bindingSpecifier: .keyword(.let),
              bindings: PatternBindingListSyntax([binding])
            )
          )
        )
      )
      return SourceFileSyntax(statements: CodeBlockItemListSyntax([item]))
    }

    let x = ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("x")))
    let one = ExprSyntax(IntegerLiteralExprSyntax(literal: .integerLiteral("1")))
    // Each tuple costs three comparison levels, so depth 100 (~300 levels) exceeds the cap
    // of 200 well before the trees differ at the bottom.
    let original = fileWrapping(deepNestedTuple(around: x, depth: 100))
    let formatted = fileWrapping(deepNestedTuple(around: one, depth: 100))
    XCTAssertFalse(original.hasError)
    XCTAssertFalse(formatted.hasError)

    let mismatches = SyntaxVerifier.verify(original: original, formatted: formatted)
    XCTAssertTrue(
      mismatches.contains { $0.description.contains("too deep to verify") },
      "expected a depth-cap mismatch, got: \(mismatches.map(\.description))"
    )
  }

  func testKnownLimitStructuralRuleRewritesAreReportedAsMismatches() throws {
    // Pin that the documented known-limit rules are reported, not silently tolerated.
    try assertNotEquivalent(
      "let a = 1, b = 2\n",
      "let a = 1\nlet b = 2\n"
    )
    try assertNotEquivalent(
      "enum E { case a, b }\n",
      "enum E { case a\ncase b }\n"
    )
    try assertNotEquivalent(
      "struct S { private var x = 1 }\nfileprivate struct T {}\n",
      "struct S { private var x = 1 }\nstruct T {}\n"
    )
  }

  // MARK: - Real corruption is caught

  func testIdentifierRenameIsNotEquivalent() throws {
    try assertNotEquivalent("let foo = 1\n", "let bar = 1\n")
  }

  func testDroppedStatementIsNotEquivalent() throws {
    try assertNotEquivalent(
      "let a = 1\nlet b = 2\n",
      "let a = 1\n"
    )
  }

  func testOperatorChangeIsNotEquivalent() throws {
    try assertNotEquivalent("let a = 1 + 2\n", "let a = 1 - 2\n")
  }

  func testKeywordChangeIsNotEquivalent() throws {
    try assertNotEquivalent("struct Foo {}\n", "class Foo {}\n")
  }

  func testFunctionSignatureChangeIsNotEquivalent() throws {
    try assertNotEquivalent("func f(a: Int) {}\n", "func f(a: String) {}\n")
  }

  func testCallArgumentSwapIsNotEquivalent() throws {
    try assertNotEquivalent("f(a: 1, b: 2)\n", "f(a: 2, b: 1)\n")
  }

  func testMismatchLimitIsRespected() throws {
    let original = try SyntaxVerifier.parseFolded("let a = 1\nlet b = 2\nlet c = 3\n")
    let formatted = try SyntaxVerifier.parseFolded("let a = 2\nlet b = 3\nlet c = 4\n")
    XCTAssertEqual(SyntaxVerifier.verify(original: original, formatted: formatted, limit: 2).count, 2)
    XCTAssertEqual(SyntaxVerifier.verify(original: original, formatted: formatted).count, 3)
  }

  func testMismatchCarriesLocationAndDescription() throws {
    let original = try SyntaxVerifier.parseFolded("let foo = 1\n")
    let formatted = try SyntaxVerifier.parseFolded("let bar = 1\n")
    let mismatches = SyntaxVerifier.verify(original: original, formatted: formatted)
    XCTAssertEqual(mismatches.count, 1)
    XCTAssertNotNil(mismatches.first?.formattedOffset)
    XCTAssertFalse(mismatches.first?.description.isEmpty ?? true)
  }
}
