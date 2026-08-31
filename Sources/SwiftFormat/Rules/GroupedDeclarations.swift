//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import SwiftSyntax

/// Requires that like-kind declarations in a type or extension body are grouped together.
///
/// Reordering declarations is not always safe: reordering stored properties changes
/// initialization order, and reordering enum cases changes the order produced by `CaseIterable`.
/// This rule therefore does not sort declarations. It checks that the properties, initializers
/// and deinitializers, methods, nested types, and enum cases of a body each form one contiguous
/// group, and it leaves the order within each group unchanged. A declaration that starts a
/// second group of its kind — after a declaration of another kind appeared in between — yields
/// a finding.
///
/// This rule is lint-only: it never rewrites the tree, so it cannot change program
/// behavior. Members the rule does not classify — `#if` regions, subscripts, associated types,
/// macro declarations, and placeholder or error declarations — are neutral: they neither break
/// a run nor are required to be grouped.
///
/// Lint: A declaration that restarts a like-kind run yields a lint error.
@_spi(Rules)
public final class GroupedDeclarations: SyntaxLintRule {
  public override class var isOptIn: Bool { return true }

  /// The declaration groups the rule recognizes; the raw value is the group's name in the
  /// finding message.
  fileprivate enum Group: String {
    case property
    case initializer
    case method
    case nestedType = "nested type"
    case enumCase = "enum case"
  }

  private static func group(of member: MemberBlockItemSyntax) -> Group? {
    switch member.decl.as(DeclSyntaxEnum.self) {
    case .variableDecl: return .property
    case .initializerDecl, .deinitializerDecl: return .initializer
    case .functionDecl: return .method
    case .structDecl, .classDecl, .enumDecl, .protocolDecl, .typeAliasDecl, .actorDecl:
      return .nestedType
    case .enumCaseDecl: return .enumCase
    default: return nil
    }
  }

  public override func visit(_ node: MemberBlockSyntax) -> SyntaxVisitorContinueKind {
    // A group is contiguous iff each classified member follows the previous member of the same
    // group immediately in the sequence of classified members (neutral members in between do
    // not break the run).
    var lastClassifiedIndex: [Group: Int] = [:]
    var classifiedCount = 0
    for member in node.members {
      guard let group = Self.group(of: member) else { continue }
      if let earlier = lastClassifiedIndex[group], earlier != classifiedCount - 1 {
        diagnose(.restartedRun(group), on: member.decl)
      }
      lastClassifiedIndex[group] = classifiedCount
      classifiedCount += 1
    }
    return .visitChildren
  }
}

extension Finding.Message {
  fileprivate static func restartedRun(_ group: GroupedDeclarations.Group) -> Finding.Message {
    Finding.Message(
      stringLiteral: "group this \(group.rawValue) declaration with the other \(group.rawValue) declarations"
    )
  }
}
