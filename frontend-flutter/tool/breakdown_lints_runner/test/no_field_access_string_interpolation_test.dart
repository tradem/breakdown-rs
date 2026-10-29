// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

// Unit tests for `no_field_access_string_interpolation` (issue #766).
//
// Parse-only on purpose: the rule's decision hinges on (a) the interpolation
// being unbraced and (b) the text right after it. Parse-only analysis has no
// resolved types, so every interpolation here counts as "not a `String`" —
// which is exactly the conservative default the rule uses when it cannot
// prove otherwise. The `String` exemption is covered by
// `_stringSuffixedLiteralsAreNotReported` at the predicate level.

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:breakdown_lints_runner/rules/no_field_access_string_interpolation.dart';
import 'package:test/test.dart';

const _rule = NoFieldAccessStringInterpolationRule();

/// Findings for a single expression statement holding [literal].
List<StringInterpolationFinding> _findingsFor(String source) {
  final unit = parseString(
    content: 'void f() { final s = $source; }',
    throwIfDiagnostics: false,
  ).unit;
  return _rule.collect(unit);
}

void main() {
  group('reports the dropped brace', () {
    test("'\$a.b' — the typo itself", () {
      final findings = _findingsFor("'\$a.b'");
      expect(findings, hasLength(1));
      expect(findings.single.expression, 'a');
      expect(findings.single.fieldName, 'b');
      expect(findings.single.offset, greaterThan(0));
      expect(findings.single.length, r'$a'.length);
    });

    test("'\$a.bc' — a longer field name", () {
      final findings = _findingsFor("'\$a.bc'");
      expect(findings, hasLength(1));
      expect(findings.single.fieldName, 'bc');
    });

    test("'Szene \$row.sceneNumber' — the shipped bug (prefixed text)", () {
      final findings = _findingsFor("'Szene \$row.sceneNumber'");
      expect(findings, hasLength(1));
      expect(findings.single.expression, 'row');
      expect(findings.single.fieldName, 'sceneNumber');
    });

    test("'\$row.scriptDay · \$row.location' — one finding per typo", () {
      final findings = _findingsFor("'\$row.scriptDay · \$row.x'");
      expect(findings.map((f) => f.fieldName), ['scriptDay', 'x']);
    });

    test('the message names both the value and the literal suffix', () {
      final finding = _findingsFor("'\$row.sceneNumber'").single;
      final message = NoFieldAccessStringInterpolationRule.describe(finding);
      expect(message, contains(r'$row.sceneNumber'));
      expect(message, contains('toString()'));
      expect(message, contains("'.sceneNumber'"));
    });
  });

  group('stays silent', () {
    test("'\${a.b}' — braced access is the correct form", () {
      expect(_findingsFor("'\${a.b}'"), isEmpty);
    });

    test("'\$a. b' — a sentence dot, not a field access", () {
      expect(_findingsFor("'Tag \$a. Danach'"), isEmpty);
    });

    test("'\$a.5' — a numeric suffix is not an identifier", () {
      expect(_findingsFor("'\$a.5'"), isEmpty);
    });

    test("'\$a' / plain text / escaped dollar", () {
      expect(_findingsFor("'\$a'"), isEmpty);
      expect(_findingsFor("'a.b'"), isEmpty);
      expect(_findingsFor(r"'cost: \$5.50'"), isEmpty);
    });

    test("'\$a[0].x' — an index expression, not a dropped brace", () {
      expect(_findingsFor("'\${a[0]}.x'"), isEmpty);
    });
  });

  group('String values may legitimately take a literal suffix', () {
    test("'preview_\$mode.png' — a String plus a literal extension", () {
      expect(
        NoFieldAccessStringInterpolationRule.suspiciousFieldAccess(
          braced: false,
          interpolatesString: true,
          followingText: '.png',
        ),
        isNull,
      );
    });

    test('a non-String value followed by .png is still suspicious', () {
      expect(
        NoFieldAccessStringInterpolationRule.suspiciousFieldAccess(
          braced: false,
          interpolatesString: false,
          followingText: '.png',
        ),
        'png',
      );
    });

    test('the exemption never rescues a braced literal', () {
      expect(
        NoFieldAccessStringInterpolationRule.suspiciousFieldAccess(
          braced: true,
          interpolatesString: false,
          followingText: '.sceneNumber',
        ),
        isNull,
      );
    });

    test('unresolved parse-only analysis counts as non-String', () {
      // This is what makes the parse-only cases above meaningful: without a
      // resolved type the rule must report, or the bug could slip through.
      final unit = parseString(
        content: r'''
String g(String name) => 'goldens/x_$name.png';
''',
        throwIfDiagnostics: false,
      ).unit;
      expect(_rule.collect(unit), hasLength(1));
    });
  });

  group('scope', () {
    test('reports once per compilation unit, not per element', () {
      final unit = parseString(
        content: r'''
void f() {
  final a = '$x.y';
  final b = 'Szene $row.sceneNumber';
}
''',
        throwIfDiagnostics: false,
      ).unit;
      expect(_rule.collect(unit), hasLength(2));
    });
  });
}
