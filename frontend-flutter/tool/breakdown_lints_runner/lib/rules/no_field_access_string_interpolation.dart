// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

/// One suspicious `'$ident.field'` string literal (issue #766).
class StringInterpolationFinding {
  const StringInterpolationFinding({
    required this.offset,
    required this.length,
    required this.expression,
    required this.fieldName,
  });

  /// Offset of the interpolation (`$ident`) inside the compilation unit.
  final int offset;

  /// Length of the interpolation (`$ident`) — the bracket is NOT part of it,
  /// so the author sees the fix point (`'${ident.field}'`) highlighted.
  final int length;

  /// Source text of the interpolated expression (`ident`).
  final String expression;

  /// The identifier read off the literal text after the dot (`field`).
  final String fieldName;
}

/// Detects the missing-interpolation-brace typo `'$ident.field'`.
///
/// `'$row.sceneNumber'` interpolates the WHOLE `row` value — via its
/// `toString()`, which for a built_value DTO is
/// `SollIstDiffRow{location=…, sceneId=…}` — and then appends the literal
/// text `.sceneNumber`. It is always a dropped brace for `'${row.sceneNumber}'`
/// (issue #766 shipped exactly this into the Dispo/Soll-Ist view).
///
/// A literal `.` directly after an UNBRACED interpolation is only accepted
/// when the interpolated value is a `String`: `'goldens/x_$name.png'` is a
/// legitimate path concatenation, `'Szene $row.sceneNumber'` is not.
///
/// Implemented over the plain `analyzer` AST so the CI runner
/// (`tool/breakdown_lints_runner`) and the unit test can use it without the
/// `analysis_server_plugin` machinery; the plugin twin lives in
/// `packages/breakdown_lints/lib/rules/no_field_access_string_interpolation.dart`.
class NoFieldAccessStringInterpolationRule {
  const NoFieldAccessStringInterpolationRule();

  /// `.<identifier>` immediately following the interpolation's text.
  ///
  /// A dot followed by anything else (whitespace, a digit, punctuation) is
  /// ordinary prose — `'Tag $day. Danach …'` — and stays silent.
  static final RegExp _fieldAccessSuffix = RegExp(
    r'^\.([A-Za-z_][A-Za-z0-9_]*)',
  );

  static const String message =
      'Missing interpolation braces: the whole value is interpolated and the '
      'literal text is appended. Use braces.';

  /// The pure decision behind the rule — see [collect] for the AST wiring.
  ///
  /// Returns the field name read off [followingText] (the literal text right
  /// after the interpolation) when the interpolation looks like a dropped
  /// brace, otherwise `null`.
  ///
  /// A `String` value ([interpolatesString]) may legitimately take a literal
  /// suffix (`'preview_$mode.png'`); a non-String value cannot, so a following
  /// `.identifier` can only be a dropped brace.
  static String? suspiciousFieldAccess({
    required bool braced,
    required bool interpolatesString,
    required String followingText,
  }) {
    // `${ident.field}` is the unambiguous form: never suspicious.
    if (braced) return null;
    if (interpolatesString) return null;
    return _fieldAccessSuffix.firstMatch(followingText)?.group(1);
  }

  /// Collects every finding in [unit].
  List<StringInterpolationFinding> collect(CompilationUnit unit) {
    final findings = <StringInterpolationFinding>[];
    unit.accept(_Visitor(findings));
    return findings;
  }

  /// Message for one finding, naming the source range involved.
  static String describe(StringInterpolationFinding finding) =>
      "'\$${finding.expression}.${finding.fieldName}' interpolates the whole "
      "${finding.expression} value (its toString()) and then appends the "
      "literal text '.${finding.fieldName}'. $message";
}

class _Visitor extends RecursiveAstVisitor<void> {
  _Visitor(this.findings);

  final List<StringInterpolationFinding> findings;

  @override
  void visitStringInterpolation(StringInterpolation node) {
    final elements = node.elements;
    for (var i = 0; i < elements.length - 1; i++) {
      final element = elements[i];
      if (element is! InterpolationExpression) continue;
      final following = elements[i + 1];
      if (following is! InterpolationString) continue;
      // Unresolved analysis (`staticType == null`) counts as non-String: a
      // false negative would let the bug through.
      final type = element.expression.staticType;
      final fieldName =
          NoFieldAccessStringInterpolationRule.suspiciousFieldAccess(
            braced: element.rightBracket != null,
            interpolatesString: type?.isDartCoreString ?? false,
            followingText: following.value,
          );
      if (fieldName == null) continue;
      findings.add(
        StringInterpolationFinding(
          offset: element.offset,
          length: element.length,
          expression: element.expression.toSource(),
          fieldName: fieldName,
        ),
      );
    }
    super.visitStringInterpolation(node);
  }
}
