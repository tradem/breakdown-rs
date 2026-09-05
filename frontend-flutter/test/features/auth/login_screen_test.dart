// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:frontend_flutter/auth/auth_providers.dart';
import 'package:frontend_flutter/auth/oidc_client.dart';
import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/design/theme.dart';
import 'package:frontend_flutter/features/auth/login_screen.dart';

import '../../auth/oidc_test_fakes.dart';
import '../seasons/seasons_test_fakes.dart';

/// Pumps a bounded number of frames (never `pumpAndSettle` while an
/// indeterminate spinner may be on screen — that would hang the settle loop).
Future<void> pumpFrames(WidgetTester tester, {int n = 6}) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

void main() {
  late FakeTokenStore tokens;
  late ProviderContainer container;

  /// LoginScreen under a real session controller: [ui] drives the platform
  /// leg, the token endpoint is stubbed. [brightness] selects the golden
  /// variant — each test pumps a FRESH tree (see `theme_test.dart`: the
  /// framework caches view MediaQuery data across `pumpWidget`).
  Future<void> pumpLogin(
    WidgetTester tester,
    AuthorizationUi ui, {
    Brightness brightness = Brightness.light,
  }) async {
    tokens = FakeTokenStore(null);
    final uiClient = clientFor(ui);
    container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        appConfigProvider.overrideWithValue(realOidcConfig),
        tokenStoreProvider.overrideWithValue(tokens),
        oidcClientProvider.overrideWithValue(
          AsyncValue.data(Right<ProblemError, OidcClient>(uiClient)),
        ),
      ],
    );
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MediaQuery(
          data: MediaQueryData(platformBrightness: brightness),
          child: MaterialApp(
            theme: AppThemes.light(),
            darkTheme: AppThemes.dark(),
            themeMode: ThemeMode.system,
            home: const LoginScreen(),
          ),
        ),
      ),
    );
    await pumpFrames(tester);
  }

  group('LoginScreen behavior (task 3.6)', () {
    testWidgets('happy: sign-in stores the session, no error shown', (
      tester,
    ) async {
      final ui = FakeAuthorizationUi(
        Right(Uri.parse('breakdown://redirect?code=abc123')),
      );
      await pumpLogin(tester, ui);

      expect(find.byKey(const Key('login-signin-button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('login-signin-button')));
      await pumpFrames(tester);

      expect(find.byKey(const Key('login-error-banner')), findsNothing);
      final session = await container.read(
        authSessionControllerProvider.future,
      );
      expect(session?.sub, 'user-1');
      expect(tokens.tokens?.accessToken, 'at-new');
    });

    testWidgets('in-flight: action disabled with progress', (tester) async {
      final ui = DeferredAuthorizationUi();
      await pumpLogin(tester, ui);

      await tester.tap(find.byKey(const Key('login-signin-button')));
      await pumpFrames(tester, n: 2);

      expect(find.byKey(const Key('login-spinner')), findsOneWidget);
      expect(
        tester
            .widget<ElevatedButton>(
              find.byKey(const Key('login-signin-button')),
            )
            .enabled,
        isFalse,
      );

      ui.complete(Right(Uri.parse('breakdown://redirect?code=abc123')));
      await pumpFrames(tester);
      expect(find.byKey(const Key('login-spinner')), findsNothing);
    });

    testWidgets('error: keyed copy plus retry recovers', (tester) async {
      final ui = FakeAuthorizationUi(
        const Left(ProblemError(code: 'oidc.browser_launch_failed')),
      );
      await pumpLogin(tester, ui);

      await tester.tap(find.byKey(const Key('login-signin-button')));
      await pumpFrames(tester);

      expect(find.byKey(const Key('login-error-banner')), findsOneWidget);
      expect(find.textContaining('oidc.browser_launch_failed'), findsOneWidget);

      ui.scripted = Right(Uri.parse('breakdown://redirect?code=abc123'));
      await tester.tap(find.byKey(const Key('login-error-retry')));
      await pumpFrames(tester);

      expect(find.byKey(const Key('login-error-banner')), findsNothing);
      final session = await container.read(
        authSessionControllerProvider.future,
      );
      expect(session?.sub, 'user-1');
    });

    testWidgets('dev-auth: notice plus Continue resolves the session', (
      tester,
    ) async {
      tokens = FakeTokenStore(null);
      container = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(devAuthConfig),
          tokenStoreProvider.overrideWithValue(tokens),
        ],
      );
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppThemes.light(),
            darkTheme: AppThemes.dark(),
            themeMode: ThemeMode.system,
            home: const LoginScreen(),
          ),
        ),
      );
      await pumpFrames(tester);

      expect(find.byKey(const Key('login-dev-notice')), findsOneWidget);
      expect(
        find.text('Dev authentication in effect — continuing as dev-user.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('login-signin-button')), findsNothing);

      await tester.tap(find.byKey(const Key('login-continue-button')));
      await pumpFrames(tester);

      final session = await container.read(
        authSessionControllerProvider.future,
      );
      expect(session?.sub, 'dev-user');
    });
  });

  group('LoginScreen goldens (task 3.6)', () {
    Future<void> golden(
      WidgetTester tester,
      String name, {
      required AuthorizationUi ui,
      required Brightness brightness,
      Future<void> Function()? arrange,
    }) async {
      await pumpLogin(tester, ui, brightness: brightness);
      if (arrange != null) await arrange();
      await pumpFrames(tester);
      expect(find.text('Breakdown'), findsOneWidget);
      await expectLater(
        find.byType(LoginScreen),
        matchesGoldenFile('goldens/login_$name.png'),
      );
    }

    testWidgets('happy light', (tester) async {
      await golden(
        tester,
        'happy_light',
        ui: FakeAuthorizationUi(
          Right(Uri.parse('breakdown://redirect?code=abc123')),
        ),
        brightness: Brightness.light,
      );
    });

    testWidgets('happy dark', (tester) async {
      await golden(
        tester,
        'happy_dark',
        ui: FakeAuthorizationUi(
          Right(Uri.parse('breakdown://redirect?code=abc123')),
        ),
        brightness: Brightness.dark,
      );
    });

    testWidgets('error light', (tester) async {
      await golden(
        tester,
        'error_light',
        ui: FakeAuthorizationUi(
          const Left(ProblemError(code: 'oidc.browser_launch_failed')),
        ),
        brightness: Brightness.light,
        arrange: () async {
          await tester.tap(find.byKey(const Key('login-signin-button')));
        },
      );
    });

    testWidgets('error dark', (tester) async {
      await golden(
        tester,
        'error_dark',
        ui: FakeAuthorizationUi(
          const Left(ProblemError(code: 'oidc.browser_launch_failed')),
        ),
        brightness: Brightness.dark,
        arrange: () async {
          await tester.tap(find.byKey(const Key('login-signin-button')));
        },
      );
    });

    testWidgets('in-flight light', (tester) async {
      await golden(
        tester,
        'inflight_light',
        ui: DeferredAuthorizationUi(),
        brightness: Brightness.light,
        arrange: () async {
          await tester.tap(find.byKey(const Key('login-signin-button')));
          await pumpFrames(tester, n: 3);
        },
      );
    });

    testWidgets('in-flight dark', (tester) async {
      await golden(
        tester,
        'inflight_dark',
        ui: DeferredAuthorizationUi(),
        brightness: Brightness.dark,
        arrange: () async {
          await tester.tap(find.byKey(const Key('login-signin-button')));
          await pumpFrames(tester, n: 3);
        },
      );
    });

    testWidgets('dev-auth light', (tester) async {
      tokens = FakeTokenStore(null);
      container = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(devAuthConfig),
          tokenStoreProvider.overrideWithValue(tokens),
        ],
      );
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppThemes.light(),
            darkTheme: AppThemes.dark(),
            themeMode: ThemeMode.system,
            home: const LoginScreen(),
          ),
        ),
      );
      await pumpFrames(tester);
      await expectLater(
        find.byType(LoginScreen),
        matchesGoldenFile('goldens/login_devauth_light.png'),
      );
    });

    testWidgets('dev-auth dark', (tester) async {
      tokens = FakeTokenStore(null);
      container = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(devAuthConfig),
          tokenStoreProvider.overrideWithValue(tokens),
        ],
      );
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MediaQuery(
            data: const MediaQueryData(platformBrightness: Brightness.dark),
            child: MaterialApp(
              theme: AppThemes.light(),
              darkTheme: AppThemes.dark(),
              themeMode: ThemeMode.system,
              home: const LoginScreen(),
            ),
          ),
        ),
      );
      await pumpFrames(tester);
      await expectLater(
        find.byType(LoginScreen),
        matchesGoldenFile('goldens/login_devauth_dark.png'),
      );
    });
  });
}
