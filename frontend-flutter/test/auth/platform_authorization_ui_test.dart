// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:frontend_flutter/app_config.dart';
import 'package:frontend_flutter/auth/auth_providers.dart';
import 'package:frontend_flutter/auth/platform_authorization_ui.dart';
import 'package:test/test.dart';

import '../features/seasons/seasons_test_fakes.dart';

/// Unit tests for [PlatformAuthorizationUi] (task 3.2, design.md §3).
///
/// The Custom-Tabs browser and the OS deep-link stream do not exist in
/// `flutter test`, so the seams ([LaunchBrowser]/[OpenLinkStream]) stand in
/// for them. Every outcome is scripted — no wall-clock gating: the timeout
/// test's stream never emits, so the timeout wins deterministically whatever
/// the machine load (only the duration, never the outcome, depends on it).
void main() {
  final authUrl = Uri.parse('https://idp.example/authorize?x=1');
  final redirectBase = Uri.parse('breakdown://auth/callback');

  group('PlatformAuthorizationUi', () {
    test('matching redirect completes with the captured URI', () async {
      final launched = <Uri>[];
      final events = <String>[];
      final links = StreamController<Uri>(
        onListen: () => events.add('listen'),
        onCancel: () => events.add('cancel'),
      );
      addTearDown(links.close);
      final ui = PlatformAuthorizationUi(
        redirectUri: redirectBase,
        launchBrowser: (url) async {
          launched.add(url);
          events.add('launch');
          links.add(Uri.parse('breakdown://auth/callback?code=abc&state=s'));
          return true;
        },
        openLinkStream: () => links.stream,
      );

      final result = await ui.launch(authUrl);

      expect(result.isRight(), isTrue);
      expect(
        result.getRight().toNullable().toString(),
        'breakdown://auth/callback?code=abc&state=s',
      );
      expect(launched, [authUrl]);
      // Subscribed before launching (a warm tab may redirect early)…
      expect(events.indexOf('listen') < events.indexOf('launch'), isTrue);
      // …and cancelled once the flow settles (no surviving listener).
      expect(events, contains('cancel'));
    });

    test('unrelated deep links are ignored until the match arrives', () async {
      final links = StreamController<Uri>();
      addTearDown(links.close);
      final ui = PlatformAuthorizationUi(
        redirectUri: redirectBase,
        launchBrowser: (url) async {
          links.add(Uri.parse('otherapp://auth/callback?code=nope'));
          links.add(Uri.parse('breakdown://auth/callback?code=yes'));
          return true;
        },
        openLinkStream: () => links.stream,
      );

      final result = await ui.launch(authUrl);

      expect(result.isRight(), isTrue);
      expect(result.getRight().toNullable()?.queryParameters['code'], 'yes');
    });

    test('same scheme with different host/path/port never completes', () async {
      final links = StreamController<Uri>();
      addTearDown(links.close);
      final ui = PlatformAuthorizationUi(
        redirectUri: redirectBase,
        redirectTimeout: const Duration(milliseconds: 10),
        launchBrowser: (url) async {
          // Same scheme, wrong host / path / port: none may complete the
          // flow — the wait ends in a timeout, not a mismatched capture.
          links.add(Uri.parse('breakdown://other/callback?code=a'));
          links.add(Uri.parse('breakdown://auth/other?code=b'));
          links.add(Uri.parse('breakdown://auth:1234/callback?code=c'));
          return true;
        },
        openLinkStream: () => links.stream,
      );

      final result = await ui.launch(authUrl);

      expect(result.isLeft(), isTrue);
      expect(result.getLeft().toNullable()?.code, 'oidc.redirect_timeout');
    });

    test('launch returning false maps to browser_launch_failed', () async {
      var cancelled = false;
      final links = StreamController<Uri>(onCancel: () => cancelled = true);
      addTearDown(links.close);
      final ui = PlatformAuthorizationUi(
        redirectUri: redirectBase,
        launchBrowser: (_) async => false,
        openLinkStream: () => links.stream,
      );

      final result = await ui.launch(authUrl);

      expect(result.isLeft(), isTrue);
      expect(result.getLeft().toNullable()?.code, 'oidc.browser_launch_failed');
      expect(cancelled, isTrue);
    });

    test('launch throwing maps to browser_launch_failed', () async {
      final ui = PlatformAuthorizationUi(
        redirectUri: redirectBase,
        launchBrowser: (_) => throw StateError('no browser'),
        openLinkStream: () => const Stream.empty(),
      );

      final result = await ui.launch(authUrl);

      expect(result.isLeft(), isTrue);
      expect(result.getLeft().toNullable()?.code, 'oidc.browser_launch_failed');
    });

    test('no redirect within the timeout maps to redirect_timeout', () async {
      var cancelled = false;
      final links = StreamController<Uri>(onCancel: () => cancelled = true);
      addTearDown(links.close);
      final ui = PlatformAuthorizationUi(
        redirectUri: redirectBase,
        redirectTimeout: const Duration(milliseconds: 10),
        launchBrowser: (_) async => true,
        openLinkStream: () => links.stream,
      );

      final result = await ui.launch(authUrl);

      expect(result.isLeft(), isTrue);
      expect(result.getLeft().toNullable()?.code, 'oidc.redirect_timeout');
      expect(cancelled, isTrue);
    });

    test('stream error maps to redirect_capture_failed', () async {
      final links = StreamController<Uri>();
      addTearDown(links.close);
      final ui = PlatformAuthorizationUi(
        redirectUri: redirectBase,
        launchBrowser: (_) async {
          links.addError(StateError('link stream died'));
          return true;
        },
        openLinkStream: () => links.stream,
      );

      final result = await ui.launch(authUrl);

      expect(result.isLeft(), isTrue);
      expect(
        result.getLeft().toNullable()?.code,
        'oidc.redirect_capture_failed',
      );
    });
  });

  group('authorizationUiProvider wiring (spec scenario)', () {
    test('resolves the platform UI when a redirect is configured', () {
      final container = ProviderContainer(
        overrides: [appConfigProvider.overrideWithValue(realOidcConfig)],
      );
      addTearDown(container.dispose);

      final ui = container.read(authorizationUiProvider);
      expect(ui, isA<PlatformAuthorizationUi>());
      expect(
        (ui as PlatformAuthorizationUi).redirectUri.toString(),
        'breakdown://redirect',
      );
    });

    test('falls back to fail-closed without a routable redirect', () {
      const noRedirect = AppConfig(
        flavor: Flavor.dev,
        apiBase: 'http://10.0.2.2:3000',
        oidcIss: 'https://idp.example',
        devAuthSub: '',
        oidcAudience: 'breakdown-api',
        oidcClientId: 'client',
        oidcRedirectUri: '',
        devIdpInsecure: '',
        appVersion: '1.0.0+1',
        defaultSeriesId: '',
      );
      for (final config in [devAuthConfig, noRedirect]) {
        final container = ProviderContainer(
          overrides: [appConfigProvider.overrideWithValue(config)],
        );
        addTearDown(container.dispose);
        expect(
          container.read(authorizationUiProvider),
          isA<NotConfiguredAuthorizationUi>(),
        );
      }
    });
  });
}
