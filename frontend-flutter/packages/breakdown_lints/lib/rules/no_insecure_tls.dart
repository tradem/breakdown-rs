// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy3 (opencode-go)

import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

/// Forbids insecure TLS configuration: a `badCertificateCallback` that returns
/// `true`, `dangerouslyAllowInsecureCerts`, or a trust-all `SecurityContext`
/// (`allowInsecure: true`). CA certificates are pinned per-flavor instead.
class NoInsecureTlsRule extends AnalysisRule {
  static const LintCode code = LintCode(
    'no_insecure_tls',
    'Insecure TLS configuration is forbidden.',
    correctionMessage: 'Pin CA certificates per-flavor; never disable certificate verification.',
    uniqueName: 'LintCode.no_insecure_tls',
  );

  NoInsecureTlsRule()
    : super(
        name: 'no_insecure_tls',
        description: 'Forbids disabling TLS certificate verification.',
      );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    registry
      ..addAssignmentExpression(this, _Visitor(this))
      ..addInstanceCreationExpression(this, _Visitor(this))
      ..addPropertyAccess(this, _Visitor(this))
      ..addPrefixedIdentifier(this, _Visitor(this))
      ..addMethodInvocation(this, _Visitor(this));
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule);

  final AnalysisRule rule;

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    final lhs = node.leftHandSide;
    if (lhs is PropertyAccess &&
        lhs.propertyName.name == 'badCertificateCallback' &&
        _returnsLiteralTrue(node.rightHandSide)) {
      rule.reportAtNode(node);
    }
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final classElement = node.constructorName.type.element;
    if (classElement?.name == 'SecurityContext') {
      for (final arg in node.argumentList.arguments) {
        if (arg is NamedArgument && arg.name.lexeme == 'allowInsecure') {
          final value = arg.argumentExpression;
          if (value is BooleanLiteral && value.value == true) {
            rule.reportAtNode(node);
          }
        }
      }
    }
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    if (node.propertyName.name == 'dangerouslyAllowInsecureCerts') {
      rule.reportAtNode(node);
    }
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    if (node.identifier.name == 'dangerouslyAllowInsecureCerts') {
      rule.reportAtNode(node);
    }
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    // Catch `SecureSocket.connect(host, port, onBadCertificate: (_) => true)` —
    // a literal-true callback bypasses certificate validation.
    final methodName = node.methodName.name;
    if (methodName != 'connect') return;
    final targetType = node.target?.staticType;
    final className = targetType?.element?.name;
    if (className != 'SecureSocket' && className != 'RawSecureSocket') {
      return;
    }
    for (final arg in node.argumentList.arguments) {
      if (arg is NamedArgument &&
          arg.name.lexeme == 'onBadCertificate' &&
          _returnsLiteralTrue(arg.argumentExpression)) {
        rule.reportAtNode(arg);
      }
    }
  }

  bool _returnsLiteralTrue(Expression expression) {
    final body = switch (expression) {
      FunctionExpression(:final body) => body,
      _ => null,
    };
    if (body is ExpressionFunctionBody) {
      return body.expression is BooleanLiteral &&
          (body.expression as BooleanLiteral).value == true;
    }
    if (body is BlockFunctionBody) {
      for (final statement in body.block.statements) {
        if (statement is ReturnStatement &&
            statement.expression is BooleanLiteral &&
            (statement.expression as BooleanLiteral).value == true) {
          return true;
        }
      }
    }
    return false;
  }
}
