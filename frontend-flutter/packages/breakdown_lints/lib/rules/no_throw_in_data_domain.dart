// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy3 (opencode-go)

import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

/// Forbids `throw` in `lib/data/**` and `lib/domain/**` — those layers must
/// return `Result`/`Either` (fail-closed, no panics in prod).
class NoThrowInDataDomainRule extends AnalysisRule {
  static const LintCode code = LintCode(
    'no_throw_in_data_domain',
    'throw is forbidden in lib/data/** and lib/domain/**.',
    correctionMessage:
        'Return a Result/Either from fpdart instead of throwing.',
    uniqueName: 'LintCode.no_throw_in_data_domain',
  );

  NoThrowInDataDomainRule()
    : super(
        name: 'no_throw_in_data_domain',
        description: 'Forbids throw in the data and domain layers.',
      );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    registry.addThrowExpression(this, _Visitor(this, context));
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule, this.context);

  final AnalysisRule rule;
  final RuleContext context;

  @override
  void visitThrowExpression(ThrowExpression node) {
    // Normalize backslashes to forward slashes so Windows paths
    // (e.g. `lib\data\foo.dart`) match the hard-coded `/lib/` fragments.
    final path = context.definingUnit.file.path.replaceAll('\\', '/');
    if (_isDataOrDomain(path)) {
      rule.reportAtNode(node);
    }
  }

  bool _isDataOrDomain(String path) =>
      path.contains('/lib/data/') || path.contains('/lib/domain/');
}
