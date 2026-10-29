// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

/// Flags the missing-interpolation-brace typo `'$ident.field'` (issue #766).
///
/// `'$row.sceneNumber'` interpolates the WHOLE `row` value via its
/// `toString()` (for a built_value DTO: `SollIstDiffRow{location=…,
/// sceneId=…}`) and appends the literal text `.sceneNumber` — user-visible
/// garbage that also leaks internal field names, ids and order keys. The
/// author meant `'${row.sceneNumber}'`.
///
/// A literal `.` directly after an unbraced interpolation is accepted only
/// when the interpolated value is a `String`: `'goldens/x_$name.png'` is
/// legitimate path concatenation, `'Szene $row.sceneNumber'` is a dropped
/// brace. The CI twin (`tool/breakdown_lints_runner`) implements the same
/// check with the plain `analyzer` API (issue #299).
class NoFieldAccessStringInterpolationRule extends AnalysisRule {
  static const LintCode code = LintCode(
    'no_field_access_string_interpolation',
    'Missing interpolation braces: the whole value is interpolated and the '
        'literal text is appended.',
    correctionMessage:
        'Wrap the receiver and field in braces — '
        "'\${ident.field}' instead of '\$ident.field'.",
    uniqueName: 'LintCode.no_field_access_string_interpolation',
  );

  NoFieldAccessStringInterpolationRule()
    : super(
        name: 'no_field_access_string_interpolation',
        description:
            "Flags unbraced interpolations followed by a literal '.field'.",
      );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    registry.addStringInterpolation(this, _Visitor(this));
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule);

  final AnalysisRule rule;

  static final RegExp _fieldAccessSuffix = RegExp(
    r'^\.([A-Za-z_][A-Za-z0-9_]*)',
  );

  @override
  void visitStringInterpolation(StringInterpolation node) {
    final elements = node.elements;
    for (var i = 0; i < elements.length - 1; i++) {
      final element = elements[i];
      // `${ident.field}` is the unambiguous form: never reported. Only the
      // brace-less `$ident` can swallow more than the identifier it names.
      if (element is! InterpolationExpression || element.rightBracket != null) {
        continue;
      }
      final following = elements[i + 1];
      if (following is! InterpolationString) continue;
      if (_fieldAccessSuffix.firstMatch(following.value) == null) continue;
      // A `String` value may legitimately take a literal suffix
      // (`'preview_$mode.png'`); a non-String value cannot, so the dot can
      // only be a dropped brace. Unresolved analysis is treated as
      // non-String — a false negative would let the bug through.
      final type = element.expression.staticType;
      if (type != null && type.isDartCoreString) continue;
      rule.reportAtOffset(element.offset, element.length);
    }
  }
}
