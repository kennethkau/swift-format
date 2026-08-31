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

final class RedundantSelfTests: LintOrFormatRuleTestCase {
  func testRemovesSelfPrefixInMethodBodies() {
    assertFormatting(
      RedundantSelf.self,
      input: """
        struct Foo {
          var value = 1
          func read() -> Int {
            return 1️⃣self.value
          }
          func write() {
            2️⃣self.value = 2
            3️⃣self.read()
          }
        }
        """,
      expected: """
        struct Foo {
          var value = 1
          func read() -> Int {
            return value
          }
          func write() {
            value = 2
            read()
          }
        }
        """,
      findings: [
        FindingSpec("1️⃣", message: "remove the redundant 'self.' prefix"),
        FindingSpec("2️⃣", message: "remove the redundant 'self.' prefix"),
        FindingSpec("3️⃣", message: "remove the redundant 'self.' prefix"),
      ]
    )
  }

  func testRemovesSelfInChainsAndCalls() {
    assertFormatting(
      RedundantSelf.self,
      input: """
        struct Foo {
          var inner: Inner
          func compute(_ x: Int) -> Inner { inner }
          func run() {
            1️⃣self.inner.advance()
            2️⃣self.compute(3).advance()
            let value = 4️⃣self.compute(5️⃣self.inner.count)
            _ = 6️⃣self.inner
          }
        }
        """,
      expected: """
        struct Foo {
          var inner: Inner
          func compute(_ x: Int) -> Inner { inner }
          func run() {
            inner.advance()
            compute(3).advance()
            let value = compute(inner.count)
            _ = inner
          }
        }
        """,
      findings: [
        FindingSpec("1️⃣", message: "remove the redundant 'self.' prefix"),
        FindingSpec("2️⃣", message: "remove the redundant 'self.' prefix"),
        FindingSpec("4️⃣", message: "remove the redundant 'self.' prefix"),
        FindingSpec("5️⃣", message: "remove the redundant 'self.' prefix"),
        FindingSpec("6️⃣", message: "remove the redundant 'self.' prefix"),
      ]
    )
  }

  func testRemovesSelfInComputedPropertiesObserversAndStaticContexts() {
    assertFormatting(
      RedundantSelf.self,
      input: """
        struct Foo {
          var stored = 0
          var computed: Int { 1️⃣self.stored }
          var observed = 0 {
            didSet {
              2️⃣self.stored = 3
            }
          }
          static let shared = Foo()
          static func make() -> Foo { 3️⃣self.shared }
          subscript(index: Int) -> Int {
            get { 4️⃣self.stored }
            set { 5️⃣self.stored = newValue }
          }
          func deferAndDo() {
            defer { 6️⃣self.stored = 0 }
            do {
              _ = 7️⃣self.stored
            }
          }
        }
        extension Foo {
          func extended() -> Int { 8️⃣self.stored }
        }
        """,
      expected: """
        struct Foo {
          var stored = 0
          var computed: Int { stored }
          var observed = 0 {
            didSet {
              stored = 3
            }
          }
          static let shared = Foo()
          static func make() -> Foo { shared }
          subscript(index: Int) -> Int {
            get { stored }
            set { stored = newValue }
          }
          func deferAndDo() {
            defer { stored = 0 }
            do {
              _ = stored
            }
          }
        }
        extension Foo {
          func extended() -> Int { stored }
        }
        """,
      findings: [
        FindingSpec("1️⃣", message: "remove the redundant 'self.' prefix"),
        FindingSpec("2️⃣", message: "remove the redundant 'self.' prefix"),
        FindingSpec("3️⃣", message: "remove the redundant 'self.' prefix"),
        FindingSpec("4️⃣", message: "remove the redundant 'self.' prefix"),
        FindingSpec("5️⃣", message: "remove the redundant 'self.' prefix"),
        FindingSpec("6️⃣", message: "remove the redundant 'self.' prefix"),
        FindingSpec("7️⃣", message: "remove the redundant 'self.' prefix"),
        FindingSpec("8️⃣", message: "remove the redundant 'self.' prefix"),
      ]
    )
  }

  func testKeepsSelfInsideClosuresAndPropertyInitializers() {
    assertFormatting(
      RedundantSelf.self,
      input: """
        struct Foo {
          var stored = 0
          var handlers: [() -> Void] = []
          func run() {
            handlers.append { self.stored = 1 }
            [1, 2].map { _ in self.stored }
            _ = { self.stored }()
            func local() -> Int { self.stored }
          }
          lazy var deferred = self.stored
        }
        """,
      expected: """
        struct Foo {
          var stored = 0
          var handlers: [() -> Void] = []
          func run() {
            handlers.append { self.stored = 1 }
            [1, 2].map { _ in self.stored }
            _ = { self.stored }()
            func local() -> Int { self.stored }
          }
          lazy var deferred = self.stored
        }
        """,
      findings: []
    )
  }

  func testKeepsSelfWhenShadowedByParameters() {
    assertFormatting(
      RedundantSelf.self,
      input: """
        struct Foo {
          var value = 0
          func update(value: Int) -> Int {
            self.value = value
            return self.value
          }
          init(value: Int) {
            self.value = value
          }
          func generic<T>(value: T) -> T {
            self.value = 1
            _ = value
            return value
          }
        }
        """,
      expected: """
        struct Foo {
          var value = 0
          func update(value: Int) -> Int {
            self.value = value
            return self.value
          }
          init(value: Int) {
            self.value = value
          }
          func generic<T>(value: T) -> T {
            self.value = 1
            _ = value
            return value
          }
        }
        """,
      findings: []
    )
  }

  func testKeepsSelfWhenShadowedByEarlierLocals() {
    assertFormatting(
      RedundantSelf.self,
      input: """
        struct Foo {
          var value = 0
          var label = "a"
          var count = 0
          var item = 0
          var result = 0
          func locals() {
            let value = 1
            self.value = value
            guard let label = optionalLabel() else { return }
            _ = self.label + label
            for count in 0..<3 {
              _ = self.count + count
            }
            switch optionalItem() {
            case .some(let item):
              _ = self.item + item
            default:
              break
            }
            do {
              _ = try throwing()
            } catch let result {
              _ = self.result + result
            }
          }
          func shadows() {
            struct value {}
            _ = self.value
            func label() {}
            _ = self.label
            typealias count = Int
            _ = self.count
          }
          func optionalLabel() -> String? { nil }
          func optionalItem() -> Int? { nil }
          func throwing() throws -> Int { 0 }
        }
        """,
      expected: """
        struct Foo {
          var value = 0
          var label = "a"
          var count = 0
          var item = 0
          var result = 0
          func locals() {
            let value = 1
            self.value = value
            guard let label = optionalLabel() else { return }
            _ = self.label + label
            for count in 0..<3 {
              _ = self.count + count
            }
            switch optionalItem() {
            case .some(let item):
              _ = self.item + item
            default:
              break
            }
            do {
              _ = try throwing()
            } catch let result {
              _ = self.result + result
            }
          }
          func shadows() {
            struct value {}
            _ = self.value
            func label() {}
            _ = self.label
            typealias count = Int
            _ = self.count
          }
          func optionalLabel() -> String? { nil }
          func optionalItem() -> Int? { nil }
          func throwing() throws -> Int { 0 }
        }
        """,
      findings: []
    )
  }

  func testRemovesSelfWhenLocalIsDeclaredAfterTheUse() {
    assertFormatting(
      RedundantSelf.self,
      input: """
        struct Foo {
          var value = 0
          func later() -> Int {
            let early = 1️⃣self.value
            let value = 2
            return early + value
          }
        }
        """,
      expected: """
        struct Foo {
          var value = 0
          func later() -> Int {
            let early = value
            let value = 2
            return early + value
          }
        }
        """,
      findings: [
        FindingSpec("1️⃣", message: "remove the redundant 'self.' prefix")
      ]
    )
  }

  func testKeepsImplicitAccessorNames() {
    assertFormatting(
      RedundantSelf.self,
      input: """
        struct Foo {
          var newValue = 0
          var oldValue = 0
          var observed = 0 {
            willSet { _ = self.newValue }
            didSet { _ = self.oldValue }
          }
          subscript(index: Int) -> Int {
            get { observed }
            set { _ = self.newValue }
          }
        }
        """,
      expected: """
        struct Foo {
          var newValue = 0
          var oldValue = 0
          var observed = 0 {
            willSet { _ = self.newValue }
            didSet { _ = self.oldValue }
          }
          subscript(index: Int) -> Int {
            get { observed }
            set { _ = self.newValue }
          }
        }
        """,
      findings: []
    )
  }

  func testKeepsSelfInSpecialPositions() {
    assertFormatting(
      RedundantSelf.self,
      input: """
        struct Foo {
          var value = 0
          init() {
            self.init(value: 0)
          }
          init(value: Int) {
            self.value = value
          }
          func describe() -> String {
            return "\\(1️⃣self.value) of \\(self)"
          }
          func match(_ other: Int) -> Bool {
            if case self.value = other {
              return true
            }
            return false
          }
        }
        """,
      expected: """
        struct Foo {
          var value = 0
          init() {
            self.init(value: 0)
          }
          init(value: Int) {
            self.value = value
          }
          func describe() -> String {
            return "\\(value) of \\(self)"
          }
          func match(_ other: Int) -> Bool {
            if case self.value = other {
              return true
            }
            return false
          }
        }
        """,
      findings: [
        FindingSpec("1️⃣", message: "remove the redundant 'self.' prefix")
      ]
    )
  }

  func testCommentOnPrefixIsDiagnosedButPreserved() {
    assertFormatting(
      RedundantSelf.self,
      input: """
        struct Foo {
          var value = 0
          func write() {
            1️⃣self /* keep */.value = 1
            _ = 2️⃣self.value /* keep */
          }
        }
        """,
      expected: """
        struct Foo {
          var value = 0
          func write() {
            self /* keep */.value = 1
            _ = value /* keep */
          }
        }
        """,
      findings: [
        FindingSpec("1️⃣", message: "remove the redundant 'self.' prefix"),
        FindingSpec("2️⃣", message: "remove the redundant 'self.' prefix"),
      ]
    )
  }

  func testKeepsSelfInsideMacroExpansionArguments() {
    assertFormatting(
      RedundantSelf.self,
      input: """
        final class Foo: NSObject {
          @objc func tapped() {}
          func wire() {
            _ = #selector(self.tapped)
          }
        }
        """,
      expected: """
        final class Foo: NSObject {
          @objc func tapped() {}
          func wire() {
            _ = #selector(self.tapped)
          }
        }
        """,
      findings: []
    )
  }

  func testKeepsSelfWhenCasePatternBindsTheName() {
    assertFormatting(
      RedundantSelf.self,
      input: """
        enum Event {
          case payload(Int)
          case labeled(Int)
          case plain(Int)
        }
        struct Handler {
          var payload = 1
          var labeled = 2
          var plain = 3
          var value = 4
          func apply(_ event: Event) {
            if case let .payload(payload) = event {
              _ = self.payload + payload
            }
            guard case let .labeled(labeled) = event else { return }
            _ = self.labeled + labeled
            while case let .plain(plain) = event {
              _ = self.plain + plain
              break
            }
            switch event {
            case .payload(let inner):
              _ = 1️⃣self.payload + inner
            default:
              break
            }
          }
        }
        struct Binder {
          var value = 1
          func bind(_ input: Int?) -> Int {
            guard case let value = input else { return 0 }
            return self.value + value
          }
        }
        """,
      expected: """
        enum Event {
          case payload(Int)
          case labeled(Int)
          case plain(Int)
        }
        struct Handler {
          var payload = 1
          var labeled = 2
          var plain = 3
          var value = 4
          func apply(_ event: Event) {
            if case let .payload(payload) = event {
              _ = self.payload + payload
            }
            guard case let .labeled(labeled) = event else { return }
            _ = self.labeled + labeled
            while case let .plain(plain) = event {
              _ = self.plain + plain
              break
            }
            switch event {
            case .payload(let inner):
              _ = payload + inner
            default:
              break
            }
          }
        }
        struct Binder {
          var value = 1
          func bind(_ input: Int?) -> Int {
            guard case let value = input else { return 0 }
            return self.value + value
          }
        }
        """,
      findings: [
        FindingSpec("1️⃣", message: "remove the redundant 'self.' prefix")
      ]
    )
  }

  func testKeepsSelfWhenCatchPatternUsesAsBinding() {
    assertFormatting(
      RedundantSelf.self,
      input: """
        struct Worker {
          var result = 1
          func run() -> Int {
            do {
              _ = try attempt()
            } catch let result as Error {
              _ = result
              return self.result
            } catch {
              return 1️⃣self.result
            }
          }
          func attempt() throws -> Int { 1 }
        }
        """,
      expected: """
        struct Worker {
          var result = 1
          func run() -> Int {
            do {
              _ = try attempt()
            } catch let result as Error {
              _ = result
              return self.result
            } catch {
              return result
            }
          }
          func attempt() throws -> Int { 1 }
        }
        """,
      findings: [
        FindingSpec("1️⃣", message: "remove the redundant 'self.' prefix")
      ]
    )
  }

  func testKeepsSelfWhenEnclosingTypeGenericParameterShadows() {
    assertFormatting(
      RedundantSelf.self,
      input: """
        struct Box<value> {
          var value = 0
          func read() -> Int {
            return self.value
          }
        }

        protocol Stream<Element> {
          var element = 0
        }

        extension Box {
          func extended() -> Int {
            return self.value
          }
        }
        """,
      expected: """
        struct Box<value> {
          var value = 0
          func read() -> Int {
            return self.value
          }
        }

        protocol Stream<Element> {
          var element = 0
        }

        extension Box {
          func extended() -> Int {
            return self.value
          }
        }
        """,
      findings: []
    )
  }

  func testKeepsSelfWhenLocalIsDeclaredInsideIfConfig() {
    assertFormatting(
      RedundantSelf.self,
      input: """
        struct Diagnostics {
          var count = 0
          func record() {
        #if DEBUG
            let count = 1
        #endif
            _ = self.count
          }
        }
        """,
      expected: """
        struct Diagnostics {
          var count = 0
          func record() {
        #if DEBUG
            let count = 1
        #endif
            _ = self.count
          }
        }
        """,
      findings: []
    )
  }

  func testKeepsSelfInExtensionsOfGenericTypesDeclaredInFile() {
    assertFormatting(
      RedundantSelf.self,
      input: """
        #if true
        struct Boxed<T> {
          var T = 1
        }
        #endif

        struct Outer {
          struct Inner<T> {
            var T = 1
          }
        }

        extension Boxed {
          func boxed() -> Int {
            return self.T
          }
        }

        extension Outer.Inner {
          func inner() -> Int {
            return self.T
          }
        }
        """,
      expected: """
        #if true
        struct Boxed<T> {
          var T = 1
        }
        #endif

        struct Outer {
          struct Inner<T> {
            var T = 1
          }
        }

        extension Boxed {
          func boxed() -> Int {
            return self.T
          }
        }

        extension Outer.Inner {
          func inner() -> Int {
            return self.T
          }
        }
        """,
      findings: []
    )
  }

  func testKeepsSelfInExtensionsOfTypesNestedInExtensions() {
    assertFormatting(
      RedundantSelf.self,
      input: """
        struct Host {}

        extension Host {
          struct Nested<T> {
            var T = 1
          }
        }

        extension Host.Nested {
          func f() -> Int {
            return self.T
          }
        }
        """,
      expected: """
        struct Host {}

        extension Host {
          struct Nested<T> {
            var T = 1
          }
        }

        extension Host.Nested {
          func f() -> Int {
            return self.T
          }
        }
        """,
      findings: []
    )
  }

  func testKeepsSelfWhenBareCatchShadowsErrorMember() {
    assertFormatting(
      RedundantSelf.self,
      input: """
        enum Failure: Error {
          case boom
        }
        struct Tryer {
          var error = 1
          func attempt() {
            do {
              throw Failure.boom
            } catch {
              _ = self.error + 1
            }
          }
        }
        """,
      expected: """
        enum Failure: Error {
          case boom
        }
        struct Tryer {
          var error = 1
          func attempt() {
            do {
              throw Failure.boom
            } catch {
              _ = self.error + 1
            }
          }
        }
        """,
      findings: []
    )
  }

  func testKeepsMetatypeKeywordMemberNames() {
    assertFormatting(
      RedundantSelf.self,
      input: """
        struct Reflected {
          var `Type` = 0
          var `Protocol` = 0
          var member = 0
          func apply() {
            self.Type = 1
            self.Protocol = 2
            1️⃣self.member = 3
          }
        }
        """,
      expected: """
        struct Reflected {
          var `Type` = 0
          var `Protocol` = 0
          var member = 0
          func apply() {
            self.Type = 1
            self.Protocol = 2
            member = 3
          }
        }
        """,
      findings: [
        FindingSpec("1️⃣", message: "remove the redundant 'self.' prefix")
      ]
    )
  }

  func testKeepsKeywordMemberNames() {
    // Keywords are legal member names after a dot but the bare form would not reparse.
    assertFormatting(
      RedundantSelf.self,
      input: """
        struct Fields {
          var `throws`: String
          var returns: String
          var member: String
          func apply() {
            self.throws = "none"
            1️⃣self.returns = "value"
            2️⃣self.member = "extra"
          }
        }
        """,
      expected: """
        struct Fields {
          var `throws`: String
          var returns: String
          var member: String
          func apply() {
            self.throws = "none"
            returns = "value"
            member = "extra"
          }
        }
        """,
      findings: [
        FindingSpec("1️⃣", message: "remove the redundant 'self.' prefix"),
        FindingSpec("2️⃣", message: "remove the redundant 'self.' prefix"),
      ]
    )
  }

  func testRemovesSelfWithinGuardElseAndSwitchBodies() {
    assertFormatting(
      RedundantSelf.self,
      input: """
        struct Foo {
          var value = 0
          func optionalValue() -> Int? { nil }
          func branches() {
            guard let unwrapped = optionalValue() else {
              1️⃣self.value = 0
              return
            }
            _ = unwrapped
            switch value {
            case 0:
              2️⃣self.value = 1
            default:
              break
            }
            if let inner = optionalValue() {
              _ = inner + 3️⃣self.value
            }
          }
        }
        """,
      expected: """
        struct Foo {
          var value = 0
          func optionalValue() -> Int? { nil }
          func branches() {
            guard let unwrapped = optionalValue() else {
              value = 0
              return
            }
            _ = unwrapped
            switch value {
            case 0:
              value = 1
            default:
              break
            }
            if let inner = optionalValue() {
              _ = inner + value
            }
          }
        }
        """,
      findings: [
        FindingSpec("1️⃣", message: "remove the redundant 'self.' prefix"),
        FindingSpec("2️⃣", message: "remove the redundant 'self.' prefix"),
        FindingSpec("3️⃣", message: "remove the redundant 'self.' prefix"),
      ]
    )
  }

  func testKeepsSelfWhenParameterShadowsMemberInsideSwitchCase() {
    assertFormatting(
      RedundantSelf.self,
      input: """
        struct Foo {
          var value = 0
          func update(value: Int) -> Int {
            switch value {
            case 0:
              return self.value
            default:
              return self.value
            }
          }
        }
        """,
      expected: """
        struct Foo {
          var value = 0
          func update(value: Int) -> Int {
            switch value {
            case 0:
              return self.value
            default:
              return self.value
            }
          }
        }
        """,
      findings: []
    )
  }

  func testKeepsSelfWhenEarlierBindingOfSameDeclarationShadowsMember() {
    // The earlier binding of the multi-binding declaration is in scope in the later
    // initializer, so the unqualified name would resolve to the local, not the member.
    assertFormatting(
      RedundantSelf.self,
      input: """
        struct Foo {
          var value = 0
          func f() -> Int {
            let value = 1, other = self.value
            return other
          }
        }
        """,
      expected: """
        struct Foo {
          var value = 0
          func f() -> Int {
            let value = 1, other = self.value
            return other
          }
        }
        """,
      findings: []
    )
  }

  func testKeepsSelfWhenSubscriptGenericParameterShadowsMember() {
    assertFormatting(
      RedundantSelf.self,
      input: """
        struct Foo {
          var value = 0
          subscript<value>(i: Int) -> Int {
            return self.value
          }
        }
        """,
      expected: """
        struct Foo {
          var value = 0
          subscript<value>(i: Int) -> Int {
            return self.value
          }
        }
        """,
      findings: []
    )
  }
}
