// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (neuralwatt)

import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/app.dart';
import 'package:frontend_flutter/app_config.dart';

AppConfig _config({
  required Flavor flavor,
  String apiBase = 'https://api.breakdown.rs',
  String oidcIss = 'https://idp.example',
  String devAuthSub = '',
  String oidcAudience = 'aud',
  String oidcClientId = 'client',
  String oidcRedirectUri = 'breakdown://redirect',
  String devIdpInsecure = '',
  String appVersion = '1.0.0+1',
  String defaultProjectId = '',
}) => AppConfig(
  flavor: flavor,
  apiBase: apiBase,
  oidcIss: oidcIss,
  devAuthSub: devAuthSub,
  oidcAudience: oidcAudience,
  oidcClientId: oidcClientId,
  oidcRedirectUri: oidcRedirectUri,
  devIdpInsecure: devIdpInsecure,
  appVersion: appVersion,
  defaultProjectId: defaultProjectId,
);

/// Issue #483 (ADR-031 follow-up to #467): a `Flavor.dev` build shipped
/// without `--dart-define=DEFAULT_PROJECT_ID` surfaces at boot (non-fatal log),
/// complementing the wizard's dispatch-time fail-fast. The pure predicate is
/// the seam; the emission is proven from a widget test through the injectable
/// `log` callback (no global-mutation of `debugPrint`).
void main() {
  group('devMissingProjectIdWarning (pure predicate, both branches)', () {
    test('dev + empty DEFAULT_PROJECT_ID → actionable message', () {
      final warning = devMissingProjectIdWarning(
        _config(flavor: Flavor.dev, defaultProjectId: ''),
      );
      expect(warning, isNotNull);
      expect(warning, contains('DEFAULT_PROJECT_ID'));
      expect(warning, contains('--dart-define'));
    });

    test('dev + set DEFAULT_PROJECT_ID → null', () {
      expect(
        devMissingProjectIdWarning(
          _config(flavor: Flavor.dev, defaultProjectId: '732f…'),
        ),
        isNull,
      );
    });

    test('prod + empty DEFAULT_PROJECT_ID → null', () {
      expect(
        devMissingProjectIdWarning(
          _config(flavor: Flavor.prod, defaultProjectId: ''),
        ),
        isNull,
      );
    });
  });

  group('logDevMissingProjectIdWarning (widget-testable emission seam)', () {
    testWidgets('dev + empty emits the boot warning', (tester) async {
      final messages = <String>[];
      logDevMissingProjectIdWarning(
        _config(flavor: Flavor.dev, defaultProjectId: ''),
        log: messages.add,
      );
      expect(messages, hasLength(1));
      expect(messages.single, contains('[bootstrap]'));
      expect(messages.single, contains('DEFAULT_PROJECT_ID'));
    });

    testWidgets('dev + set stays silent', (tester) async {
      final messages = <String>[];
      logDevMissingProjectIdWarning(
        _config(flavor: Flavor.dev, defaultProjectId: '732f…'),
        log: messages.add,
      );
      expect(messages, isEmpty);
    });

    testWidgets('prod stays silent even with an empty pre-fill', (
      tester,
    ) async {
      final messages = <String>[];
      logDevMissingProjectIdWarning(
        _config(flavor: Flavor.prod, defaultProjectId: ''),
        log: messages.add,
      );
      expect(messages, isEmpty);
    });
  });
}
