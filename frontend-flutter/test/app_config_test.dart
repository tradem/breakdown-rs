// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)

import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/app.dart';
import 'package:frontend_flutter/app_config.dart';

AppConfig _config({
  required Flavor flavor,
  String apiBase = 'https://api.breakdown.rs',
  String oidcIss = 'https://idp.example',
  String devAuthSub = '',
  String devIdpInsecure = '',
  String oidcClientId = 'client',
  String oidcRedirectUri = 'breakdown://redirect',
}) => AppConfig(
  flavor: flavor,
  apiBase: apiBase,
  oidcIss: oidcIss,
  devAuthSub: devAuthSub,
  oidcAudience: 'aud',
  oidcClientId: oidcClientId,
  oidcRedirectUri: oidcRedirectUri,
  devIdpInsecure: devIdpInsecure,
);

void main() {
  group('AppConfig.devAuthMode (Task 5.1 — backend ADR-018 D6 parity)', () {
    test('true only when dev AND no OIDC_ISS AND DEV_AUTH_SUB set', () {
      const dev = Flavor.dev;
      expect(
        _config(flavor: dev, oidcIss: '', devAuthSub: 'u').devAuthMode,
        isTrue,
      );
      // Any leg missing → real OIDC mode, not dev auth.
      expect(
        _config(
          flavor: dev,
          oidcIss: 'https://idp',
          devAuthSub: 'u',
        ).devAuthMode,
        isFalse,
      );
      expect(
        _config(flavor: dev, oidcIss: '', devAuthSub: '').devAuthMode,
        isFalse,
      );
      // Structurally impossible in prod: isDev is required.
      expect(
        _config(flavor: Flavor.prod, oidcIss: '', devAuthSub: 'u').devAuthMode,
        isFalse,
      );
    });
  });

  group('AppConfig.devIdpHttpAllowed (D1 exception)', () {
    test('requires dev flavor AND the flag; release guard is in bootstrap', () {
      expect(
        _config(flavor: Flavor.dev, devIdpInsecure: '1').devIdpHttpAllowed,
        isTrue,
      );
      expect(
        _config(flavor: Flavor.dev, devIdpInsecure: '').devIdpHttpAllowed,
        isFalse,
      );
      // Prod can never relax IdP pinning via the flag.
      expect(
        _config(flavor: Flavor.prod, devIdpInsecure: '1').devIdpHttpAllowed,
        isFalse,
      );
    });
  });

  group('validateStartupConfig (fail-closed guards)', () {
    test('a fully configured prod build is valid', () {
      expect(validateStartupConfig(_config(flavor: Flavor.prod)), isNull);
    });

    test('DEV_IDP_INSECURE=1 under a non-dev flavor is rejected (D1)', () {
      final reason = validateStartupConfig(
        _config(flavor: Flavor.prod, devIdpInsecure: '1'),
      );
      expect(reason, contains('DEV_IDP_INSECURE'));
    });

    test('DEV_AUTH_SUB in prod is rejected (Task 5.1 build-time guard)', () {
      final reason = validateStartupConfig(
        _config(flavor: Flavor.prod, devAuthSub: 'dev-user'),
      );
      expect(reason, contains('DEV_AUTH_SUB'));
    });

    test('a non-dev-auth build without OIDC configuration is rejected', () {
      final reason = validateStartupConfig(
        _config(flavor: Flavor.dev, oidcIss: '', devAuthSub: ''),
      );
      expect(reason, contains('OIDC configuration invalid'));
    });

    test('dev-auth mode build (dev, no iss, sub set) is valid', () {
      expect(
        validateStartupConfig(
          _config(
            flavor: Flavor.dev,
            oidcIss: '',
            devAuthSub: 'dev-user',
            oidcClientId: '',
            oidcRedirectUri: '',
          ),
        ),
        isNull,
      );
    });
  });
}
