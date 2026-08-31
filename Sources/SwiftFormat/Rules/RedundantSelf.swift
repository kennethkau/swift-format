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

/// Removes `self.` prefixes that are not required by the language.
///
/// The rule is conservative: a prefix is removed only where a purely syntactic analysis can
/// prove that the unqualified name resolves to the same member. The prefix is kept in the
/// following places:
///   * Inside a closure or local function, where whether `self` is required depends on the
///     escaping semantics of the context, which are not visible to the formatter
///   * Inside a property initializer, inside a macro expansion, and in a pattern position,
///     where the unqualified form would bind a name instead of referring to the member
///   * When a binding with the same name as the member is in scope at the use site, such as a
///     function parameter, an earlier local or type declaration, a condition or `catch`
///     binding, an implicit accessor name like `newValue`, or a generic parameter of the
///     enclosing type
///   * When the member's name is a keyword, so the bare form would not parse (for example
///     `self.init` or `self.Type`)
///
/// Lint: A redundant `self.` prefix yields one lint error.
///
/// Format: The prefix is removed in the same pass that diagnoses it. A prefix with a comment
///         attached to it is diagnosed but left unchanged, so that the comment is preserved.

@_spi(Rules)
public final class RedundantSelf: SyntaxFormatRule {
  public override class var isOptIn: Bool { return true }

  public override func visit(_ node: MemberAccessExprSyntax) -> ExprSyntax {
    guard let base = node.base,
      let baseReference = base.as(DeclReferenceExprSyntax.self),
      case .keyword(.self) = baseReference.baseName.tokenKind,
      node.declName.argumentNames == nil,
      case .identifier = node.declName.baseName.tokenKind,
      !Self.hardKeywords.contains(node.declName.baseName.text)
    else {
      return super.visit(node)
    }

    // A shadowing binding or declined context makes the prefix load-bearing; it is not
    // redundant and produces no finding.
    guard !Self.isExcludedContext(node) else {
      return super.visit(node)
    }
    let member = node.declName.baseName.text
    guard !isShadowed(member, at: node) else {
      return super.visit(node)
    }

    diagnose(.removeRedundantSelf, on: base)
    if Self.carriesComment(node) {
      return super.visit(node)
    }
    var replacement = DeclReferenceExprSyntax(baseName: node.declName.baseName)
    replacement.leadingTrivia = node.leadingTrivia
    replacement.trailingTrivia = node.trailingTrivia
    return ExprSyntax(replacement)
  }

  /// The hard keywords of Swift: names that never lex as bare identifiers, so a member named
  /// with one (`self.throws`) cannot survive losing its prefix. The metatype keywords `Type`
  /// and `Protocol` are included for the same reason (`self.Type`), and contextual keywords
  /// (`read`, `each`, …) are absent because they lex as identifiers in expression position.
  /// A member spelled with backticks keeps them in its token text and rewrites safely.
  private static let hardKeywords: Set<String> = [
    "Protocol", "Type", "any", "as", "associatedtype", "break", "catch", "case", "class",
    "continue", "default", "defer", "deinit", "do", "else", "enum", "extension",
    "fallthrough", "false", "fileprivate", "for", "func", "guard", "if", "import", "in",
    "init", "inout", "internal", "is", "let", "nil", "open", "operator", "precedencegroup",
    "private", "protocol", "public", "repeat", "rethrows", "return", "self", "static",
    "struct", "subscript", "super", "switch", "throw", "throws", "true", "try", "typealias",
    "var", "where", "while",
  ]

  /// Returns whether any comment sits on the token edges of the `self.` prefix.
  ///
  /// A comment between the period and the member name degrades the parse (the period moves into
  /// unexpected nodes and the name attaches without one), so the presence of unexpected material
  /// between the base and the name is treated the same as a comment.
  private static func carriesComment(_ node: MemberAccessExprSyntax) -> Bool {
    if node.unexpectedBetweenBaseAndPeriod != nil
      || node.unexpectedBetweenPeriodAndDeclName != nil
    {
      return true
    }
    if let base = node.base, base.trailingTrivia.contains(where: { $0.isComment }) {
      return true
    }
    if node.period.leadingTrivia.contains(where: { $0.isComment })
      || node.period.trailingTrivia.contains(where: { $0.isComment })
    {
      return true
    }
    return node.declName.baseName.leadingTrivia.contains(where: { $0.isComment })
  }

  /// Returns whether the member access sits in a context the rule never touches: a closure or
  /// local function body, a property initializer, a macro expansion's arguments, or a pattern.
  private static func isExcludedContext(_ node: MemberAccessExprSyntax) -> Bool {
    var sawAccessorBlock = false
    var ancestor: Syntax? = Syntax(node).parent

    while let current = ancestor {
      switch current.kind {
      case .closureExpr, .expressionPattern, .macroExpansionExpr, .macroExpansionDecl:
        return true
      case .functionDecl:
        // Only methods of a type are scope roots; a function declared in a body is local.
        guard current.parent?.is(MemberBlockItemSyntax.self) == true else {
          return true
        }
      case .variableDecl:
        // A use inside a member property's initializer (no accessor block crossed) is
        // excluded: instance members are unavailable there, and `lazy` initializers are not
        // equivalent to the unqualified form on every compiler version. Local variables in
        // function bodies are unaffected.
        if current.parent?.is(MemberBlockItemSyntax.self) == true, !sawAccessorBlock {
          return true
        }
      case .accessorBlock:
        sawAccessorBlock = true
      default:
        break
      }
      ancestor = current.parent
    }
    return false
  }

  // MARK: Scope analysis

  /// Returns whether a binding with the given name is visible at the member access, so that the
  /// unqualified member name would resolve to the binding instead of the member.
  ///
  /// The walk climbs from the member access to the enclosing type declaration. Bindings
  /// introduced after the use in their block do not shadow it — a declaration is visible only
  /// from its declaration point onward — so only earlier statements are collected.
  private func isShadowed(_ member: String, at node: MemberAccessExprSyntax) -> Bool {
    let useOffset = node.positionAfterSkippingLeadingTrivia.utf8Offset
    var ancestor: Syntax? = Syntax(node).parent

    while let current = ancestor {
      switch current.kind {
      case .functionDecl:
        let function = current.cast(FunctionDeclSyntax.self)
        if declaresParameter(in: function.signature.parameterClause.parameters, name: member) {
          return true
        }
        if function.genericParameterClause?.parameters.contains(where: {
          $0.name.text == member
        }) == true {
          return true
        }
      case .initializerDecl:
        let initializer = current.cast(InitializerDeclSyntax.self)
        if declaresParameter(in: initializer.signature.parameterClause.parameters, name: member) {
          return true
        }
      case .subscriptDecl:
        let subscriptDecl = current.cast(SubscriptDeclSyntax.self)
        if declaresParameter(in: subscriptDecl.parameterClause.parameters, name: member) {
          return true
        }
        if subscriptDecl.genericParameterClause?.parameters.contains(where: {
          $0.name.text == member
        }) == true {
          return true
        }
      case .variableDecl:
        // Earlier bindings of a multi-binding declaration are in scope in the initializers of
        // the bindings that follow them (`let a = 1, b = a`); the binding that contains the
        // use ends after it and never matches.
        let variableDecl = current.cast(VariableDeclSyntax.self)
        if variableDecl.bindings.contains(where: { binding in
          binding.endPositionBeforeTrailingTrivia.utf8Offset <= useOffset
            && declares(binding.pattern, name: member)
        }) {
          return true
        }
      case .accessorDecl:
        if declaresAccessorName(current.cast(AccessorDeclSyntax.self), member) {
          return true
        }
      case .codeBlockItemList:
        // The statement lists of function bodies, accessor blocks (including the implicit
        // getter payload), and switch case bodies. Bindings of an earlier sibling that is a
        // declaration, local function or type, or guard statement outlive that statement.
        let list = current.cast(CodeBlockItemListSyntax.self)
        if list.contains(where: { item in
          item.endPositionBeforeTrailingTrivia.utf8Offset <= useOffset
            && declares(item, name: member)
        }) {
          return true
        }
      case .ifExpr:
        let conditions = current.cast(IfExprSyntax.self).conditions
        if declaresBinding(in: conditions, name: member) {
          return true
        }
      case .guardStmt:
        let conditions = current.cast(GuardStmtSyntax.self).conditions
        if declaresBinding(in: conditions, name: member) {
          return true
        }
      case .whileStmt:
        let conditions = current.cast(WhileStmtSyntax.self).conditions
        if declaresBinding(in: conditions, name: member) {
          return true
        }
      case .forStmt:
        if declares(current.cast(ForStmtSyntax.self).pattern, name: member) {
          return true
        }
      case .switchCase:
        let switchCase = current.cast(SwitchCaseSyntax.self)
        if case .case(let caseLabel) = switchCase.label,
          caseLabel.caseItems.contains(where: { declares($0.pattern, name: member) })
        {
          return true
        }
      case .catchClause:
        let clause = current.cast(CatchClauseSyntax.self)
        if declaresCatchName(clause, member) {
          return true
        }
      case .classDecl, .structDecl, .enumDecl, .extensionDecl, .actorDecl, .protocolDecl:
        // A generic parameter of the enclosing type shadows a same-named member for unqualified
        // references, exactly as a local type declaration does. An extension has no generic
        // parameters of its own but inherits the extended type's; those are visible only when
        // that type is declared in the same file.
        if current.is(ExtensionDeclSyntax.self) {
          return declaresExtendedTypeGenericParameter(of: current, name: member, near: node)
        }
        return declaresGenericParameter(of: current, name: member)
      case .sourceFile:
        // The walk reached file scope without crossing a type declaration, which valid `self`
        // cannot do; skip the rewrite rather than guess.
        return true
      default:
        break
      }
      ancestor = current.parent
    }
    return true
  }

  /// Returns the name that introduces the parameter's value in the function body, or nil for a
  /// wildcard.
  private func internalName(of parameter: FunctionParameterSyntax) -> String? {
    if let secondName = parameter.secondName {
      return secondName.text == "_" ? nil : secondName.text
    }
    return parameter.firstName.text == "_" ? nil : parameter.firstName.text
  }

  /// Returns whether the type-like declaration introduces a generic parameter (or, for a
  /// protocol, a primary associated type) with the given name.
  private func declaresGenericParameter(of decl: Syntax, name: String) -> Bool {
    var parameters: [String] = []
    switch decl.kind {
    case .classDecl:
      parameters =
        decl.cast(ClassDeclSyntax.self).genericParameterClause?.parameters.map {
          $0.name.text
        } ?? []
    case .structDecl:
      parameters =
        decl.cast(StructDeclSyntax.self).genericParameterClause?.parameters.map {
          $0.name.text
        } ?? []
    case .enumDecl:
      parameters =
        decl.cast(EnumDeclSyntax.self).genericParameterClause?.parameters.map {
          $0.name.text
        } ?? []
    case .actorDecl:
      parameters =
        decl.cast(ActorDeclSyntax.self).genericParameterClause?.parameters.map {
          $0.name.text
        } ?? []
    case .protocolDecl:
      // Protocols have no generic parameter clause of their own; their primary associated
      // types play the shadowing role instead.
      let protocolDecl = decl.cast(ProtocolDeclSyntax.self)
      parameters =
        protocolDecl.primaryAssociatedTypeClause?.primaryAssociatedTypes.map {
          $0.name.text
        } ?? []
    default:
      // Extensions cannot introduce generic parameters of their own.
      return false
    }
    return parameters.contains(name)
  }

  /// Generic parameter names of the same-file type declarations, keyed by type name, built
  /// lazily from the tree the rule is currently rewriting. The rule's own rewrites never touch
  /// declarations, so the map stays valid for the lifetime of a rule instance.
  private var genericParametersByTypeName: [String: Set<String>]?

  /// Returns whether the extension's extended type — when it is declared in the same file —
  /// has a generic parameter with the given name.
  private func declaresExtendedTypeGenericParameter(
    of extensionDecl: Syntax,
    name: String,
    near node: MemberAccessExprSyntax
  ) -> Bool {
    let extendedType = extensionDecl.cast(ExtensionDeclSyntax.self).extendedType
    let typeName: String?
    if let identifier = extendedType.as(IdentifierTypeSyntax.self) {
      typeName = identifier.name.text
    } else if let member = extendedType.as(MemberTypeSyntax.self) {
      typeName = member.name.text
    } else {
      typeName = nil
    }
    guard let typeName else {
      return false
    }

    if genericParametersByTypeName == nil {
      var map: [String: Set<String>] = [:]
      for decl in Syntax(node.root).children(viewMode: .sourceAccurate) {
        Self.collectGenericParameters(of: decl, into: &map)
      }
      genericParametersByTypeName = map
    }
    return genericParametersByTypeName?[typeName]?.contains(name) == true
  }

  /// Collects the generic parameter names of every type declaration — top-level, nested, and
  /// inside `#if` regions — keyed by the type's simple name. Name collisions across nesting
  /// levels union their parameters, which only ever skips the rewrite.
  private static func collectGenericParameters(
    of node: Syntax,
    into map: inout [String: Set<String>]
  ) {
    switch node.kind {
    case .codeBlockItemList:
      let list = node.cast(CodeBlockItemListSyntax.self)
      for item in list {
        collectGenericParameters(of: Syntax(item), into: &map)
      }
    case .codeBlockItem:
      let item = node.cast(CodeBlockItemSyntax.self)
      collectGenericParameters(of: Syntax(item.item), into: &map)
    case .memberBlockItem:
      let item = node.cast(MemberBlockItemSyntax.self)
      collectGenericParameters(of: Syntax(item.decl), into: &map)
    case .memberBlock:
      let block = node.cast(MemberBlockSyntax.self)
      for member in block.members {
        collectGenericParameters(of: Syntax(member), into: &map)
      }
    case .ifConfigDecl:
      let decl = node.cast(IfConfigDeclSyntax.self)
      for clause in decl.clauses {
        switch clause.elements {
        case .statements(let statements):
          for item in statements {
            collectGenericParameters(of: Syntax(item), into: &map)
          }
        case .decls(let members):
          for member in members {
            collectGenericParameters(of: Syntax(member.decl), into: &map)
          }
        default:
          break
        }
      }
    case .classDecl:
      let decl = node.cast(ClassDeclSyntax.self)
      insert(names: decl.genericParameterClause?.parameters, for: decl.name.text, into: &map)
      collectGenericParameters(of: Syntax(decl.memberBlock), into: &map)
    case .structDecl:
      let decl = node.cast(StructDeclSyntax.self)
      insert(names: decl.genericParameterClause?.parameters, for: decl.name.text, into: &map)
      collectGenericParameters(of: Syntax(decl.memberBlock), into: &map)
    case .enumDecl:
      let decl = node.cast(EnumDeclSyntax.self)
      insert(names: decl.genericParameterClause?.parameters, for: decl.name.text, into: &map)
      collectGenericParameters(of: Syntax(decl.memberBlock), into: &map)
    case .actorDecl:
      let decl = node.cast(ActorDeclSyntax.self)
      insert(names: decl.genericParameterClause?.parameters, for: decl.name.text, into: &map)
      collectGenericParameters(of: Syntax(decl.memberBlock), into: &map)
    case .protocolDecl:
      let decl = node.cast(ProtocolDeclSyntax.self)
      if let primary = decl.primaryAssociatedTypeClause, !primary.primaryAssociatedTypes.isEmpty {
        map[decl.name.text, default: []].formUnion(
          primary.primaryAssociatedTypes.map { $0.name.text }
        )
      }
      collectGenericParameters(of: Syntax(decl.memberBlock), into: &map)
    case .extensionDecl:
      // Extensions cannot introduce generic parameters of their own, but types nested inside
      // them can.
      let decl = node.cast(ExtensionDeclSyntax.self)
      collectGenericParameters(of: Syntax(decl.memberBlock), into: &map)
    default:
      break
    }
  }

  private static func insert(
    names parameters: GenericParameterListSyntax?,
    for typeName: String,
    into map: inout [String: Set<String>]
  ) {
    guard let parameters, !parameters.isEmpty else { return }
    map[typeName, default: []].formUnion(parameters.map { $0.name.text })
  }

  private func declaresParameter(in parameters: FunctionParameterListSyntax, name: String) -> Bool {
    parameters.contains { internalName(of: $0) == name }
  }

  /// Returns whether the accessor binds the name: through an explicit parameter, or through the
  /// implicit `newValue` of setters and `willSet` observers and `oldValue` of `didSet`, which
  /// shadow same-named members even without a parameter list.
  private func declaresAccessorName(_ accessor: AccessorDeclSyntax, _ name: String) -> Bool {
    if let parameters = accessor.parameters {
      return parameters.name.text == name
    }
    switch accessor.accessorSpecifier.tokenKind {
    case .keyword(.set), .keyword(.willSet):
      return name == "newValue"
    case .keyword(.didSet):
      return name == "oldValue"
    default:
      return false
    }
  }

  private func declaresCatchName(_ clause: CatchClauseSyntax, _ name: String) -> Bool {
    // A `catch` with no items binds the error implicitly as `error`.
    if clause.catchItems.isEmpty {
      return name == "error"
    }
    for item in clause.catchItems {
      guard let pattern = item.pattern else {
        continue
      }
      if declares(pattern, name: name) {
        return true
      }
    }
    return false
  }

  /// Returns whether any `let`/`var` or `case` condition introduces the name.
  private func declaresBinding(
    in conditions: ConditionElementListSyntax,
    name: String
  ) -> Bool {
    conditions.contains { condition in
      switch condition.condition {
      case .optionalBinding(let binding):
        return declares(binding.pattern, name: name)
      case .matchingPattern(let matching):
        return declares(matching.pattern, name: name)
      default:
        return false
      }
    }
  }

  /// Returns whether a direct statement of an enclosing block declares the name. Constructs
  /// whose bindings are scoped to a nested block (if, for, while bodies) cannot shadow a use
  /// outside it, but their condition bindings are checked for simplicity; over-detecting only
  /// skips the rewrite.
  private func declares(_ statement: CodeBlockItemSyntax, name: String) -> Bool {
    var item = Syntax(statement.item)
    if let labeled = item.as(LabeledStmtSyntax.self) {
      item = Syntax(labeled.statement)
    }
    switch item.kind {
    case .variableDecl:
      let variable = item.cast(VariableDeclSyntax.self)
      return variable.bindings.contains { declares($0.pattern, name: name) }
    case .functionDecl:
      return item.cast(FunctionDeclSyntax.self).name.text == name
    case .classDecl:
      return item.cast(ClassDeclSyntax.self).name.text == name
    case .structDecl:
      return item.cast(StructDeclSyntax.self).name.text == name
    case .enumDecl:
      return item.cast(EnumDeclSyntax.self).name.text == name
    case .typeAliasDecl:
      return item.cast(TypeAliasDeclSyntax.self).name.text == name
    case .actorDecl:
      return item.cast(ActorDeclSyntax.self).name.text == name
    case .guardStmt:
      let conditions = item.cast(GuardStmtSyntax.self).conditions
      return declaresBinding(in: conditions, name: name)
    case .ifExpr:
      let conditions = item.cast(IfExprSyntax.self).conditions
      return declaresBinding(in: conditions, name: name)
    case .forStmt:
      return declares(item.cast(ForStmtSyntax.self).pattern, name: name)
    case .ifConfigDecl:
      // A local declared inside a preceding `#if` block shadows when the branch is active;
      // declining is safe regardless of branch.
      let clauses = item.cast(IfConfigDeclSyntax.self).clauses
      return clauses.contains { clause in
        if case .statements(let statements) = clause.elements {
          return statements.contains { declares($0, name: name) }
        }
        return false
      }
    default:
      return false
    }
  }

  /// Returns whether the pattern binds the name, descending through value-binding, identifier,
  /// tuple, and expression-case payloads.
  private func declares(_ pattern: PatternSyntax, name: String) -> Bool {
    switch pattern.kind {
    case .identifierPattern:
      return pattern.cast(IdentifierPatternSyntax.self).identifier.text == name
    case .valueBindingPattern:
      return declares(pattern.cast(ValueBindingPatternSyntax.self).pattern, name: name)
    case .tuplePattern:
      return pattern.cast(TuplePatternSyntax.self).elements.contains {
        declares($0.pattern, name: name)
      }
    default:
      // Enum case patterns (`case .foo(let x)`) wrap their payload bindings inside an
      // expression pattern; a subtree search finds them regardless of the nesting shape.
      return subtreeBindsName(Syntax(pattern), name: name)
    }
  }

  /// Recursively searches the subtree for a binding introducing the name. Both shapes count:
  /// an explicit `let`/`var` value-binding pattern, and the bare identifier pattern that
  /// `let x = e` / `let x as E` conditions wrap in an expression pattern.
  private func subtreeBindsName(_ node: Syntax, name: String) -> Bool {
    if let binding = node.as(ValueBindingPatternSyntax.self),
      declares(binding.pattern, name: name)
    {
      return true
    }
    if let patternExpr = node.as(PatternExprSyntax.self),
      let identifier = patternExpr.pattern.as(IdentifierPatternSyntax.self),
      identifier.identifier.text == name
    {
      return true
    }
    return node.children(viewMode: .sourceAccurate).contains {
      subtreeBindsName($0, name: name)
    }
  }
}

extension Finding.Message {
  fileprivate static let removeRedundantSelf: Finding.Message =
    "remove the redundant 'self.' prefix"
}
