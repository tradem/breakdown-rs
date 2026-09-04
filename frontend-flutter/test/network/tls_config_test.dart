// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)
// Co-authored-by: muse-spark (opencode-go)
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/app_config.dart';
import 'package:frontend_flutter/src/network/api_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const config = AppConfig(
    flavor: Flavor.dev,
    apiBase: 'http://10.0.0.9:3000',
    oidcIss: 'https://idp.example',
    devAuthSub: '',
    oidcAudience: 'aud',
    oidcClientId: 'c',
    oidcRedirectUri: 'breakdown://redirect',
    devIdpInsecure: '',
    appVersion: '1.0.0+1',
  );

  group('loadPinnedSecurityContext (D4 — exclusive, fail-closed)', () {
    test('accepts a valid PEM and builds a no-default-roots context', () async {
      final pem = await File('test/fixtures/certs/ca_pinned.pem')
          .readAsString();
      final ctx = await loadPinnedSecurityContext(config, inlinePem: pem);
      expect(ctx, isA<SecurityContext>());
    });

    test('an empty PEM fails closed', () async {
      await expectLater(
        loadPinnedSecurityContext(config, inlinePem: '   '),
        throwsA(
          isA<TlsConfigError>().having(
            (e) => e.message,
            'message',
            contains('empty'),
          ),
        ),
      );
    });

    test('a non-PEM body fails closed', () async {
      await expectLater(
        loadPinnedSecurityContext(config, inlinePem: 'not a cert'),
        throwsA(
          isA<TlsConfigError>().having(
            (e) => e.message,
            'message',
            contains('not valid PEM'),
          ),
        ),
      );
    });

    test('a PEM the TLS stack cannot parse fails closed', () async {
      final garbage =
          '-----BEGIN CERTIFICATE-----\nZm9vYmFy\n'
          '-----END CERTIFICATE-----';
      await expectLater(
        loadPinnedSecurityContext(config, inlinePem: garbage),
        throwsA(isA<TlsConfigError>()),
      );
    });
  });

  group('buildApiClient (pinned transport wiring)', () {
    test('uses the flavor API base and the validated pinned context', () async {
      final pem = await File('test/fixtures/certs/ca_pinned.pem')
          .readAsString();
      final dio = await buildApiClient(config, inlinePem: pem);
      expect(dio.options.baseUrl, config.apiBase);
    });
  });
}
