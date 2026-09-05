// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'dart:async';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:frontend_flutter/app.dart';
import 'package:frontend_flutter/auth/auth_providers.dart';
import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/season_cache_dao.dart';
import 'package:frontend_flutter/data/cache/seasons_cache_providers.dart';
import 'package:frontend_flutter/features/seasons/seasons_controller.dart';

import 'features/seasons/seasons_test_fakes.dart';

/// Pumps a bounded number of frames (never `pumpAndSettle` while an
/// indeterminate spinner may be on screen — that would hang the settle loop).
Future<void> pumpFrames(WidgetTester tester, {int n = 6}) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

/// Scriptable [AuthSessionController]: the gate test drives all four
/// `AsyncValue` states without touching secure storage or the network.
class FakeAuthSessionController extends AuthSessionController {
  FakeAuthSessionController(this._build);

  final Future<AuthSession?> Function() _build;

  @override
  Future<AuthSession?> build() => _build();
}

void main() {
  late CacheDatabase db;
  late FakeSeasonRepository repo;
  late int fetchCalls;

  /// Full container: real-OIDC config (dev-auth auto-session OFF, so the
  /// OIDC login leg renders), fake session controller, holder-driven
  /// seasons projection with a fetch call-counter for the no-network
  /// assertion (task 2.2).
  ProviderContainer setupContainer(
    Future<AuthSession?> Function() sessionBuild, {
    List<SeasonView> initialRows = const [],
  }) {
    db = CacheDatabase(NativeDatabase.memory());
    repo = FakeSeasonRepository(BreakdownApi(), SeasonCacheDao(db));
    fetchCalls = 0;
    final holder = ValueNotifier<Result<List<SeasonView>>>(Right(initialRows));
    final container = ProviderContainer(
      // Deterministic-tests rule (AGENTS.md §6): Riverpod 3 auto-retries a
      // failed build (up to 10 attempts, 200ms→6.4s backoff) unless the
      // throw is an `Error`. A retried `ProblemError` would leave pending
      // backoff timers at teardown ("A Timer is still pending") and push
      // the gate through the retry window instead of the settled state.
      // Production keeps the default retry (transient restore hiccups
      // recover; the gate renders login fail-fast meanwhile — see
      // `AuthGate`); tests pin the settled outcome.
      retry: (_, _) => null,
      overrides: [
        appConfigProvider.overrideWithValue(realOidcConfig),
        authSessionControllerProvider.overrideWith(
          () => FakeAuthSessionController(sessionBuild),
        ),
        cacheDatabaseProvider.overrideWithValue(db),
        seasonRepositoryProvider.overrideWithValue(repo),
        reconciliationSchedulerProvider.overrideWith(
          (ref) => const ImmediateReconciliationScheduler(),
        ),
        seasonsListFetchProvider.overrideWith((ref) async {
          fetchCalls++;
          final r = ref.watch(seasonRepositoryProvider);
          return r.fetchAndCacheList(() async => holder.value);
        }),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(db.close);
    return container;
  }

  Future<void> pumpApp(WidgetTester tester, ProviderContainer container) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const App()),
    );
    await pumpFrames(tester);
  }

  group('App theme wiring (task 1.2)', () {
    testWidgets('MaterialApp carries the theme pair + system themeMode', (
      tester,
    ) async {
      final container = setupContainer(() async => null);
      await pumpApp(tester, container);

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.themeMode, ThemeMode.system);
      expect(app.theme?.colorScheme.brightness, Brightness.light);
      expect(app.darkTheme?.colorScheme.brightness, Brightness.dark);
    });
  });

  group('AuthGate states (task 2.1/2.2)', () {
    testWidgets('loading → splash, never a flash of login', (tester) async {
      final container = setupContainer(() => Completer<AuthSession?>().future);
      await pumpApp(tester, container);

      expect(find.byKey(const Key('splash-spinner')), findsOneWidget);
      expect(find.byKey(const Key('login-signin-button')), findsNothing);
      expect(find.text('Seasons'), findsNothing);
    });

    testWidgets('unauthenticated → LoginScreen, main app makes no network '
        'call', (tester) async {
      final container = setupContainer(() async => null);
      await pumpApp(tester, container);

      expect(find.byKey(const Key('login-signin-button')), findsOneWidget);
      expect(find.byKey(const Key('seasons-list')), findsNothing);
      expect(find.text('Seasons'), findsNothing);
      // The seasons subtree does not exist, so no projection fetch and no
      // command could have run.
      expect(fetchCalls, 0);
      expect(repo.createCalls, 0);
    });

    testWidgets('authenticated → SeasonsScreen', (tester) async {
      final container = setupContainer(
        () async => const AuthSession(sub: 'user-1'),
        initialRows: [season('a', number: 1, title: 'Spring')],
      );
      await pumpApp(tester, container);

      expect(find.text('Seasons'), findsOneWidget);
      expect(find.byKey(const Key('login-signin-button')), findsNothing);
      expect(fetchCalls, greaterThanOrEqualTo(1));
    });

    testWidgets('AsyncError(ProblemError) → LoginScreen with keyed copy', (
      tester,
    ) async {
      final container = setupContainer(() async {
        throw const ProblemError(code: 'transport.connectionError');
      });
      await pumpApp(tester, container);

      expect(find.byKey(const Key('login-signin-button')), findsOneWidget);
      expect(find.byKey(const Key('login-error-banner')), findsOneWidget);
      expect(find.textContaining('Network problem'), findsOneWidget);
      expect(find.text('Seasons'), findsNothing);
    });

    testWidgets(
      'AsyncError(non-ProblemError) → normalized generic, raw text never '
      'rendered',
      (tester) async {
        final container = setupContainer(() async {
          throw StateError('disk blew up');
        });
        await pumpApp(tester, container);

        expect(find.byKey(const Key('login-error-banner')), findsOneWidget);
        expect(find.textContaining('disk blew up'), findsNothing);
        // Neutral generic copy keyed on the stable restore code: actionable,
        // never the raw exception text.
        expect(find.textContaining('sign in again'), findsOneWidget);
      },
    );
  });

  group('textScaler 1.3 no-overflow (task 1.3)', () {
    Future<void> pumpScaled(
      WidgetTester tester,
      ProviderContainer container,
    ) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
            child: const App(),
          ),
        ),
      );
      await pumpFrames(tester);
    }

    testWidgets('splash holds at textScaler 1.3', (tester) async {
      final container = setupContainer(() => Completer<AuthSession?>().future);
      await pumpScaled(tester, container);
      expect(find.byKey(const Key('splash-spinner')), findsOneWidget);
    });

    testWidgets('login holds at textScaler 1.3', (tester) async {
      final container = setupContainer(() async => null);
      await pumpScaled(tester, container);
      expect(find.byKey(const Key('login-signin-button')), findsOneWidget);
    });
  });

  group('normalizeGateError', () {
    test('passes ProblemError through untouched', () {
      const error = ProblemError(code: 'transport.connectionError');
      expect(normalizeGateError(error), same(error));
    });

    test('maps foreign throws to the stable restore code', () {
      final normalized = normalizeGateError(StateError('boom'));
      expect(normalized.code, 'auth.restore_failed');
    });
  });

  group('Splash goldens (task 2.3)', () {
    // Fresh tree per brightness (view MediaQuery data is cached across
    // `pumpWidget` — see `theme_test.dart`). Fixed pump count: the
    // spinner frame is deterministic under fake async.
    Future<void> pumpSplash(WidgetTester tester, Brightness brightness) async {
      final container = setupContainer(() => Completer<AuthSession?>().future);
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MediaQuery(
            data: MediaQueryData(platformBrightness: brightness),
            child: const App(),
          ),
        ),
      );
      await pumpFrames(tester);
    }

    testWidgets('splash light', (tester) async {
      await pumpSplash(tester, Brightness.light);
      expect(find.byKey(const Key('splash-spinner')), findsOneWidget);
      await expectLater(
        find.byType(SplashView),
        matchesGoldenFile('goldens/splash_light.png'),
      );
    });

    testWidgets('splash dark', (tester) async {
      await pumpSplash(tester, Brightness.dark);
      expect(find.byKey(const Key('splash-spinner')), findsOneWidget);
      await expectLater(
        find.byType(SplashView),
        matchesGoldenFile('goldens/splash_dark.png'),
      );
    });
  });
}
