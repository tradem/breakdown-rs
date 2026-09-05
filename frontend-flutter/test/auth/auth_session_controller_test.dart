// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:frontend_flutter/auth/auth_providers.dart';
import 'package:frontend_flutter/auth/oidc_client.dart';
import 'package:frontend_flutter/core/problem_error.dart';

import '../features/seasons/seasons_test_fakes.dart';
import 'oidc_test_fakes.dart';

void main() {
  late FakeTokenStore tokens;
  late FakeAuthorizationUi ui;
  late ProviderContainer container;

  void setupContainer() {
    tokens = FakeTokenStore(null);
    ui = FakeAuthorizationUi(
      Right(Uri.parse('breakdown://redirect?code=abc123')),
    );
    container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(realOidcConfig),
        tokenStoreProvider.overrideWithValue(tokens),
        oidcClientProvider.overrideWithValue(
          AsyncValue.data(Right<ProblemError, OidcClient>(clientFor(ui))),
        ),
      ],
    );
    addTearDown(container.dispose);
  }

  group('AuthSessionController.signIn (task 3.5)', () {
    test('starts signed out with an empty store', () async {
      setupContainer();
      final session = await container.read(
        authSessionControllerProvider.future,
      );
      expect(session, isNull);
    });

    test('Ok: stores tokens and resolves the session sub', () async {
      setupContainer();
      await container.read(authSessionControllerProvider.notifier).signIn();

      final session = await container.read(
        authSessionControllerProvider.future,
      );
      expect(session, isNotNull);
      expect(session!.sub, 'user-1');
      expect(session.isDevAuth, isFalse);
      expect(tokens.tokens, isNotNull);
      expect(tokens.tokens!.accessToken, 'at-new');
      // The authorization request went through the platform UI.
      expect(ui.launchedUrl, isNotNull);
      expect(ui.launchedUrl!.queryParameters['response_type'], 'code');
    });

    test(
      'Err per platform failure mode: browser-launch, timeout, capture',
      () async {
        for (final code in [
          'oidc.browser_launch_failed',
          'oidc.redirect_timeout',
          'oidc.redirect_capture_failed',
        ]) {
          setupContainer();
          ui.scripted = Left(ProblemError(code: code));

          final notifier = container.read(
            authSessionControllerProvider.notifier,
          );
          await expectLater(
            notifier.signIn(),
            throwsA(isA<ProblemError>().having((e) => e.code, 'code', code)),
          );
          // Failed sign-in persists nothing and leaves no session.
          expect(tokens.tokens, isNull);
          final session = await container.read(
            authSessionControllerProvider.future,
          );
          expect(session, isNull);
        }
      },
    );

    test('dev-auth boots signed out at the login gate', () async {
      tokens = FakeTokenStore(null);
      container = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(devAuthConfig),
          tokenStoreProvider.overrideWithValue(tokens),
        ],
      );
      addTearDown(container.dispose);

      final session = await container.read(
        authSessionControllerProvider.future,
      );
      expect(session, isNull);
    });

    test('dev-auth Continue resolves the permissive session', () async {
      tokens = FakeTokenStore(null);
      container = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(devAuthConfig),
          tokenStoreProvider.overrideWithValue(tokens),
        ],
      );
      addTearDown(container.dispose);

      await container.read(authSessionControllerProvider.notifier).signIn();
      final session = await container.read(
        authSessionControllerProvider.future,
      );
      expect(session, isNotNull);
      expect(session!.sub, 'dev-user');
      expect(session.isDevAuth, isTrue);
    });
  });
}
