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

import SwiftSyntax

/// Sorts order-insensitive declaration attributes into a fixed order.
///
/// Only attributes from a fixed allowlist of compiler-defined, order-insensitive attributes are
/// reordered — availability (`@available`), concurrency and isolation (`@MainActor`,
/// `@preconcurrency`, `@Sendable`), introspection (`@nonobjc`, `@objc`, `@_spi`), optimization
/// (`@frozen`, `@inlinable`, `@usableFromInline`), and ergonomics (`@discardableResult`,
/// `@dynamicMemberLookup`), in the order listed here. Anything
/// else — property wrappers, macro attributes (whose expansion order is their source order),
/// and `#if` regions inside the attribute list — is a barrier: attributes are sorted only
/// within a maximal run of consecutive allowlisted attributes, so nothing ever moves across a
/// barrier. Attributes of `import` declarations and of function parameters are never touched.
///
/// Lint: An attribute list whose canonical run order differs from the source order yields one
///       lint error on the first attribute of the affected run.
///
/// Format: The allowlisted runs are sorted in place. A run carrying a comment on any of its
///         attributes is diagnosed but left as written.
@_spi(Rules)
public final class AttributeOrder: SyntaxFormatRule {
  public override class var isOptIn: Bool { return true }

  /// The canonical order of allowlisted attributes.
  private static let canonicalOrder: [String] = [
    "available",
    "MainActor",
    "preconcurrency",
    "Sendable",
    "nonobjc",
    "objc",
    "_spi",
    "frozen",
    "inlinable",
    "usableFromInline",
    "discardableResult",
    "dynamicMemberLookup",
  ]

  public override func visit(_ node: AttributeListSyntax) -> AttributeListSyntax {
    guard isReorderableDeclaration(node) else {
      return super.visit(node)
    }

    var adjusted = node
    var runStart = adjusted.startIndex
    while runStart < adjusted.endIndex {
      guard Self.isAllowlisted(adjusted[runStart]) else {
        runStart = adjusted.index(after: runStart)
        continue
      }
      var runEnd = runStart
      while runEnd < adjusted.endIndex, Self.isAllowlisted(adjusted[runEnd]) {
        runEnd = adjusted.index(after: runEnd)
      }
      if runEnd > adjusted.index(after: runStart) {
        var run = [AttributeListSyntax.Index]()
        var index = runStart
        while index < runEnd {
          run.append(index)
          index = adjusted.index(after: index)
        }
        adjusted = sortRun(run, in: adjusted)
      }
      runStart = runEnd
    }
    return super.visit(adjusted)
  }

  /// Returns whether the attribute list belongs to a declaration whose attributes may be
  /// reordered. Import declarations and function parameters are excluded: attribute order is
  /// significant for both (`@testable`, `@escaping`/`@autoclosure`).
  private func isReorderableDeclaration(_ node: AttributeListSyntax) -> Bool {
    guard let parent = node.parent else {
      return false
    }
    switch parent.kind {
    case .classDecl, .structDecl, .enumDecl, .protocolDecl, .extensionDecl, .actorDecl,
      .functionDecl, .initializerDecl, .deinitializerDecl, .subscriptDecl, .variableDecl,
      .typeAliasDecl, .associatedTypeDecl, .accessorDecl, .enumCaseDecl, .macroExpansionDecl:
      return true
    default:
      return false
    }
  }

  /// Returns whether the element is an allowlisted, syntactically complete attribute.
  private static func isAllowlisted(_ element: AttributeListSyntax.Element) -> Bool {
    guard case .attribute(let attribute) = element,
      let identifier = attribute.attributeName.as(IdentifierTypeSyntax.self),
      canonicalOrder.contains(identifier.name.text),
      attribute.leftParen == nil || attribute.rightParen != nil
    else {
      return false
    }
    return true
  }

  /// Sorts the given run of attributes canonically. Trivia is normalized after the sort — the
  /// run's first position keeps its leading trivia and its last keeps its trailing trivia,
  /// interior attributes are separated by single spaces — because the elements' own edge
  /// trivia describes their old positions.
  private func sortRun(
    _ run: [AttributeListSyntax.Index],
    in list: AttributeListSyntax
  ) -> AttributeListSyntax {
    let elements = run.map { list[$0] }
    let sorted = elements.sorted { lhs, rhs in
      let lhsRank = Self.rank(of: lhs)
      let rhsRank = Self.rank(of: rhs)
      if lhsRank != rhsRank {
        return lhsRank < rhsRank
      }
      return Self.name(of: lhs) < Self.name(of: rhs)
    }
    guard sorted != elements else {
      return list
    }

    diagnose(.sortAttributes, on: Syntax(elements.first!))

    // The run's first position keeps its leading trivia (which may hold the declaration's doc
    // comment) and its last keeps its trailing; comments anywhere else would be lost by the
    // sort's trivia normalization, so those runs are left as written.
    for (offset, element) in elements.enumerated() {
      if Self.carriesComment(
        element,
        includingLeading: offset != 0,
        includingTrailing: offset != elements.count - 1
      ) {
        return list
      }
    }

    var adjusted = list
    for (offset, index) in run.enumerated() {
      // Every element of the run was verified `.attribute` by `isAllowlisted`.
      var attribute = sorted[offset].cast(AttributeSyntax.self)
      if offset == 0 {
        attribute.leadingTrivia = elements.first!.leadingTrivia
      } else {
        attribute.leadingTrivia = [.spaces(1)]
      }
      if offset == run.count - 1 {
        attribute.trailingTrivia = elements.last!.trailingTrivia
      } else {
        attribute.trailingTrivia = []
      }
      adjusted[index] = .attribute(attribute)
    }
    return adjusted
  }

  private static func rank(of element: AttributeListSyntax.Element) -> Int {
    canonicalOrder.firstIndex(of: name(of: element)) ?? canonicalOrder.count
  }

  private static func name(of element: AttributeListSyntax.Element) -> String {
    guard case .attribute(let attribute) = element,
      let identifier = attribute.attributeName.as(IdentifierTypeSyntax.self)
    else {
      return ""
    }
    return identifier.name.text
  }

  /// Returns whether a checked token edge of the attribute carries a comment.
  private static func carriesComment(
    _ element: AttributeListSyntax.Element,
    includingLeading: Bool,
    includingTrailing: Bool
  ) -> Bool {
    guard case .attribute(let attribute) = element else {
      return true
    }
    if includingLeading,
      let first = attribute.firstToken(viewMode: .sourceAccurate),
      first.leadingTrivia.contains(where: { $0.isComment })
    {
      return true
    }
    if includingTrailing,
      let last = attribute.lastToken(viewMode: .sourceAccurate),
      last.trailingTrivia.contains(where: { $0.isComment })
    {
      return true
    }
    return false
  }
}

extension Finding.Message {
  fileprivate static let sortAttributes: Finding.Message =
    "sort the declaration attributes into their fixed order"
}
