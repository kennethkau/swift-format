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

/// Sorts the modifiers of a declaration into a fixed order.
///
/// Modifier order is not semantic in Swift — the modifiers in a declaration's modifier list
/// commute — so a fixed order removes one degree of freedom from the source without changing
/// meaning. The fixed order is: access level (`open`, `public`, `package`, `internal`,
/// `fileprivate`, `private`), then `final`, `required`, `convenience`, `static`/`class`,
/// `override`, `mutating`/`nonmutating`, `borrowing`/`consuming`, `lazy`, `weak`/`unowned`,
/// `optional`, `indirect`, `dynamic`, and `nonisolated`/`isolated`/`distributed`. Modifiers not
/// in this list keep their relative order after the ranked ones. A modifier carrying an
/// argument sorts after the same-rank argument-less form (for example `public private(set) var`,
/// never `private(set) public var`).
///
/// Lint: A modifier list that is not in the fixed order yields a lint error on the first
///       modifier that follows a higher-ranked modifier.
///
/// Format: The modifier list is reordered into the fixed order; the leading trivia of the
///         list's first modifier and the trailing trivia of its last modifier are preserved and
///         interior separation is normalized to a single space. When any modifier carries a
///         comment, only the lint error is emitted — the rewrite is skipped so no comment is
///         displaced or lost.
@_spi(Rules)
public final class ModifierOrder: SyntaxFormatRule {
  /// The rank of each known modifier, matched by the modifier's name. Lower ranks
  /// come first. Unlisted modifiers rank last and keep their relative order (stable sort).
  private static let ranks: [String: Int] = [
    "open": 0,
    "public": 0,
    "package": 0,
    "internal": 0,
    "fileprivate": 0,
    "private": 0,
    "final": 1,
    "required": 2,
    "convenience": 3,
    "static": 4,
    "class": 4,
    "override": 5,
    "mutating": 6,
    "nonmutating": 6,
    "borrowing": 7,
    "consuming": 7,
    "lazy": 8,
    "weak": 9,
    "unowned": 9,
    "optional": 10,
    "indirect": 11,
    "dynamic": 12,
    "nonisolated": 13,
    "isolated": 13,
    "distributed": 13,
  ]
  private static let unranked = 100

  public override class var isOptIn: Bool { return true }

  public override func visit(_ node: DeclModifierListSyntax) -> DeclModifierListSyntax {
    // Sorting is keyed by (rank, argument, original position) so the result does not depend on
    // `sorted` being stable: equal keys keep their written order by construction.
    let original = Array(node)
    let sorted = original.enumerated()
      .sorted { left, right in
        let (l, r) = (key(left.element), key(right.element))
        return l < r || (l == r && left.offset < right.offset)
      }
      .map(\.element)
    guard sorted != original, let first = original.first, let last = original.last else {
      return super.visit(node)
    }

    // The first mispositioned modifier is the first whose key is less than the largest key seen
    // so far.
    var highest = (Int.min, Int.min)
    for modifier in node {
      let current = key(modifier)
      if current < highest {
        diagnose(.sortModifiersIntoFixedOrder, on: modifier)
        break
      }
      if current > highest {
        highest = current
      }
    }

    // When any modifier carries a comment, reordering would strand it between unrelated
    // modifiers; keep the list as written and let the finding stand as lint-only.
    var hasComment = false
    for modifier in node {
      if modifier.leadingTrivia.contains(where: { $0.isComment })
        || modifier.trailingTrivia.contains(where: { $0.isComment })
      {
        hasComment = true
        break
      }
    }
    if hasComment {
      return super.visit(node)
    }

    // Rebuild the list with normalized interior trivia: each modifier is separated by a single
    // space, the list's first token keeps the original first modifier's leading trivia, and the
    // last modifier keeps the original last modifier's trailing trivia. Stale trivia from the
    // pre-sort positions would otherwise travel with each modifier.
    let leading = first.leadingTrivia
    let trailing = last.trailingTrivia
    var normalized: [DeclModifierSyntax] = []
    for (index, modifier) in sorted.enumerated() {
      var adjusted = modifier
      adjusted = adjusted.with(\.leadingTrivia, index == 0 ? leading : [])
      let isLast = index == sorted.count - 1
      adjusted = adjusted.with(\.trailingTrivia, isLast ? trailing : [.spaces(1)])
      normalized.append(adjusted)
    }
    return super.visit(DeclModifierListSyntax(normalized))
  }

  /// The sort key of a modifier: its rank, with the argument-less form of a modifier sorting
  /// before the same modifier carrying an argument (`public private(set) var`, never
  /// `private(set) public var`).
  private func key(_ modifier: DeclModifierSyntax) -> (Int, Int) {
    let rank = Self.ranks[modifier.name.text] ?? Self.unranked
    let argument = modifier.detail != nil ? 1 : 0
    return (rank, argument)
  }
}

extension Finding.Message {
  fileprivate static let sortModifiersIntoFixedOrder: Finding.Message =
    "sort the declaration modifiers into their fixed order"
}
