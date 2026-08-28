// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy3 (opencode-go)

import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/error/error.dart';

/// Flags an un-awaited `Future` (or a discarded fpdart `Result`/`Either`) used
/// as a bare statement — the backend `discard-result` analog. A discarded
/// result must be awaited, bound, or explicitly suppressed with
/// `// ignore: discard_result` + a reason comment.
class DiscardResultRule extends AnalysisRule {
  static const LintCode code = LintCode(
    'discard_result',
    'Discarded result (Future / Result) must be handled.',
    correctionMessage:
        'Await it, bind it to a variable, or suppress with '
        '// ignore: discard_result and a reason.',
    uniqueName: 'LintCode.discard_result',
  );

  DiscardResultRule()
      : super(
          name: 'discard_result',
          description:
              'Flags an un-awaited Future or a discarded Result/Either in '
              'statement position.',
        );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) {
    registry.addExpressionStatement(this, _Visitor(this, context));
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule, this.context);

  final AnalysisRule rule;
  final RuleContext context;

  @override
  void visitExpressionStatement(ExpressionStatement node) {
    final type = node.expression.staticType;
    if (type == null) return;
    if (_isFuture(type) || _isFpdartResultOrEither(type)) {
      rule.reportAtNode(node.expression);
    }
  }

  bool _isFuture(DartType type) {
    final element = type.element;
    if (element == null) return false;
    return element.name == 'Future' && element.library?.isDartAsync == true;
  }

  bool _isFpdartResultOrEither(DartType type) {
    final element = type.element;
    if (element == null) return false;
    final uri = element.library?.uri.toString() ?? '';
    if (!uri.contains('fpdart')) return false;
    return element.name == 'Result' || element.name == 'Either';
  }
}
