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

/// Removes parentheses that cannot change the meaning of the expression they wrap.
///
/// A parenthesized expression is redundant when it wraps an atomic expression — an identifier,
/// member-access chain of atomic expressions, `self`, `super`, or a simple literal. Atoms have
/// no operators, so no precedence or tuple-shape rule can distinguish the parenthesized and
/// unparenthesized forms. Parentheses with any other contents (operators, calls, casts, real
/// tuples, labeled or trailing-comma single-element tuples, operator references like `(+)`) are
/// left alone. The outermost parenthesized layer of an `if`/`guard`/`while`/`switch`/`repeat`
/// condition is left to the `NoParensAroundConditions` rule; nested layers inside it are still
/// unwrapped here.
///
/// Lint: Parentheses around an atomic expression yield one lint error per redundant layer.
///
/// Format: All redundant layers are removed in a single pass, with the finding reported on the
///         outermost layer. A layer containing a comment is kept and only its lint error is
///         emitted; comment-free layers beneath a kept layer may still be unwrapped.
@_spi(Rules)
public final class RedundantParens: SyntaxFormatRule {
  public override class var isOptIn: Bool { return true }

  public override func visit(_ node: TupleExprSyntax) -> ExprSyntax {
    guard isRedundantParenTuple(node) else {
      return super.visit(node)
    }

    // The whole-condition case belongs to NoParensAroundConditions; also skip its other subjects
    // so the two rules never diagnose the same parentheses.
    if let parent = node.parent, isConditionPosition(parent) {
      return super.visit(node)
    }

    // Collect every nested redundant layer so that each is diagnosed exactly once and all are
    // unwrapped in this single visit; recursing through `visit` instead would re-diagnose the
    // inner layers when the pipeline visits them again.
    var layers = [node]
    loop: while true {
      let inner = layers.last!.elements.first!.expression
      guard let innerTuple = inner.as(TupleExprSyntax.self), isRedundantParenTuple(innerTuple)
      else {
        break loop
      }
      layers.append(innerTuple)
    }

    diagnose(.removeRedundantParens, on: node.leftParen)

    // If the user has put a comment anywhere inside any layer — on a paren edge or on a wrapped
    // expression's own edge tokens — it is not obvious where it should go, so the parentheses
    // are kept despite the findings.
    for layer in layers {
      if layer.containsComment {
        return super.visit(node)
      }
    }

    var unwrapped = layers.last!.elements.first!.expression
    unwrapped.leadingTrivia = node.leftParen.leadingTrivia
    unwrapped.trailingTrivia = node.rightParen.trailingTrivia
    // When nothing separates the expression from a preceding keyword (`return(x)`), the raw
    // rewrite would glue the two tokens together; the pretty printer re-adds spacing, but the
    // rewritten tree itself must stay lexically valid.
    if let previous = node.leftParen.previousToken(viewMode: .sourceAccurate),
      case .keyword = previous.tokenKind,
      !previous.trailingTrivia.contains(where: { $0.isSpaceOrTab || $0.isNewline }),
      !node.leftParen.leadingTrivia.contains(where: { $0.isSpaceOrTab || $0.isNewline })
    {
      unwrapped.leadingTrivia = [.spaces(1)] + unwrapped.leadingTrivia
    }
    return unwrapped
  }

  /// Returns whether the tuple is a parenthesized expression rather than a tuple: exactly one
  /// element with no trailing comma and no label, wrapping an atomic expression.
  private func isRedundantParenTuple(_ node: TupleExprSyntax) -> Bool {
    guard
      node.elements.count == 1,
      let element = node.elements.first,
      element.trailingComma == nil,
      element.label == nil,
      isAtomic(element.expression)
    else {
      return false
    }
    return true
  }

  /// Returns whether the expression is atomic: an identifier, a member-access chain whose base
  /// is atomic (or omitted), `self`, `super`, or a simple literal.
  private func isAtomic(_ expression: ExprSyntax) -> Bool {
    switch Syntax(expression).kind {
    case .declReferenceExpr:
      // Plain identifiers and `self` (both parse as decl references in this syntax version).
      // Operator references (`(+)`) are excluded: without the parentheses the operator token
      // lexes as an operator rather than a reference, and the result generally does not
      // reparse.
      let reference = expression.cast(DeclReferenceExprSyntax.self)
      switch reference.baseName.tokenKind {
      case .binaryOperator, .prefixOperator, .postfixOperator:
        return false
      default:
        return true
      }
    case .memberAccessExpr:
      let memberAccess = expression.cast(MemberAccessExprSyntax.self)
      guard let base = memberAccess.base else {
        return true
      }
      return isAtomic(base)
    case .superExpr:
      return true
    case .integerLiteralExpr, .floatLiteralExpr, .booleanLiteralExpr, .nilLiteralExpr,
      .stringLiteralExpr:
      return true
    case .tupleExpr:
      // Parentheses wrapping an atomic expression are themselves atomic, so nested redundant
      // parentheses unwrap fully.
      let tuple = expression.cast(TupleExprSyntax.self)
      return isRedundantParenTuple(tuple)
    default:
      return false
    }
  }

  /// Returns whether the given parent node is a position whose parentheses are governed by the
  /// `NoParensAroundConditions` rule: the condition of an `if`, `guard`, or `while` statement,
  /// or the subject of a `switch` statement or `repeat` statement.
  private func isConditionPosition(_ parent: Syntax) -> Bool {
    switch parent.kind {
    case .conditionElement:
      // The condition's expression is stored as an enum payload; a parenthesized condition is
      // wrapped in a TupleExpr whose parent is the condition element.
      return true
    case .switchExpr, .repeatStmt:
      return true
    default:
      return false
    }
  }
}

extension TupleExprSyntax {
  /// Returns whether any token edge inside the tuple's parentheses carries a comment.
  fileprivate var containsComment: Bool {
    if leftParen.trailingTrivia.contains(where: { $0.isComment })
      || rightParen.leadingTrivia.contains(where: { $0.isComment })
    {
      return true
    }
    if let first = elements.first?.expression.firstToken(viewMode: .sourceAccurate),
      first.leadingTrivia.contains(where: { $0.isComment })
    {
      return true
    }
    if let last = elements.first?.expression.lastToken(viewMode: .sourceAccurate),
      last.trailingTrivia.contains(where: { $0.isComment })
    {
      return true
    }
    return false
  }
}

extension Finding.Message {
  fileprivate static let removeRedundantParens: Finding.Message =
    "remove the redundant parentheses around this expression"
}
