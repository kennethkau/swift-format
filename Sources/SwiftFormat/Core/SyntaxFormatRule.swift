//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import SwiftSyntax

/// A rule that both formats and lints a given file.
@_spi(Rules)
public class SyntaxFormatRule: SyntaxRewriter, Rule {
  /// Whether this rule is opt-in, meaning it's disabled by default. Rules are opt-out unless they
  /// override this property.
  public class var isOptIn: Bool {
    return false
  }

  /// The context in which the rule is executed.
  public let context: Context

  /// Creates a new SyntaxFormatRule in the given context.
  public required init(context: Context) {
    self.context = context
  }

  public override func visitAny(_ node: Syntax) -> Syntax? {
    // If the rule is not enabled, then return the node unmodified; otherwise, returning nil tells
    // SwiftSyntax to continue with the standard dispatch.
    guard context.shouldFormat(type(of: self), node: node) else { return node }
    return nil
  }

  /// Rewrites a subtree the selection walk has determined this rule may modify.
  ///
  /// Rules that must walk the tree more than once — for example, to collect planned edits before
  /// applying them — override this to run their own passes, since their logic cannot live in the
  /// typed `visit` methods if it must also run when a subtree other than the whole file is handed
  /// over. The default performs the standard single rewriting walk. Like the typed visits, this is
  /// only reached for nodes that are fully contained in the selection, unmasked, and governed by
  /// an enabled rule.
  public func rewriteSubtree(_ node: Syntax) -> Syntax {
    return rewrite(node, detach: true)
  }

  /// Applies the rule to the given node without rewriting anything outside the context's
  /// selection.
  ///
  /// A direct `rewrite` cannot be used when a selection covers only part of the file:
  /// `visitAny` declines every node that is not fully contained in the selection, and the root
  /// node is not, so the entire walk would be pruned before any rule could fire. This entry
  /// point instead descends through nodes that are not fully contained (leaving them and their
  /// text unchanged) and hands each fully contained subtree to the rule, where `visitAny`
  /// enforces the same containment and masking checks as it does for an unselected formatting
  /// pass.
  public func apply(to node: Syntax) -> Syntax {
    guard context.isRuleEnabled(type(of: self)) else { return node }
    return SelectionScopedRewriter(rule: self, context: context).rewrite(node)
  }
}

/// Walks a syntax tree to locate the subtrees a rule may rewrite when a selection is active.
///
/// A node that is fully contained in the selection is handed to the rule in its entirety. Any
/// other node that still intersects the selection is rebuilt from its walked children, so the
/// rule never gets the chance to rewrite the node itself. Subtrees that do not intersect the
/// selection cannot contain a rewritable node and are pruned.
private final class SelectionScopedRewriter: SyntaxRewriter {
  private let rule: SyntaxFormatRule
  private let context: Context

  init(rule: SyntaxFormatRule, context: Context) {
    self.rule = rule
    self.context = context
  }

  override func visitAny(_ node: Syntax) -> Syntax? {
    if node.isInsideSelection(context.selection) {
      return rule.rewriteSubtree(node)
    }
    if context.selection.overlapsOrTouches(node.position..<node.endPosition) {
      return nil
    }
    return node
  }
}
