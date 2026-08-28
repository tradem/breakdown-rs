// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy3 (opencode-go)

import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

/// Heuristic match of string literals against secret patterns. Advisory only
/// (warning) — `gitleaks` remains authoritative for secret detection.
class NoHardcodedSecretsRule extends AnalysisRule {
  static const LintCode code = LintCode(
    'no_hardcoded_secrets',
    'Possible hardcoded secret detected.',
    correctionMessage:
        'Source secrets from --dart-define / secure storage, not literals.',
    uniqueName: 'LintCode.no_hardcoded_secrets',
  );

  NoHardcodedSecretsRule()
    : super(
        name: 'no_hardcoded_secrets',
        description: 'Heuristic detection of hardcoded secrets.',
      );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    registry.addSimpleStringLiteral(this, _Visitor(this, context));
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule, this.context);

  final AnalysisRule rule;
  final RuleContext context;

  static final _secretName = RegExp(
    r'(secret|token|password|passwd|api_?key|client_?secret|private_?key)',
    caseSensitive: false,
  );
  static final _highEntropy = RegExp(r'^[A-Za-z0-9+/=_\-]{24,}$');

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    final value = node.value;
    if (value.isEmpty) return;
    final name = _surroundingName(node.parent);
    final nameLooksSecret = name != null && _secretName.hasMatch(name);
    if (nameLooksSecret && value.length >= 8) {
      rule.reportAtNode(node);
    } else if (nameLooksSecret && _highEntropy.hasMatch(value)) {
      rule.reportAtNode(node);
    }
  }

  String? _surroundingName(AstNode? parent) {
    final p = parent;
    if (p is VariableDeclaration) return p.name.lexeme;
    if (p is NamedArgument) return p.name.lexeme;
    if (p is FormalParameter) return p.name?.lexeme;
    if (p is AssignmentExpression) {
      final lhs = p.leftHandSide;
      if (lhs is SimpleIdentifier) return lhs.name;
      if (lhs is PropertyAccess) return lhs.propertyName.name;
    }
    return null;
  }
}
