// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

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

import 'seasons_test_fakes.dart';

/// Pumps a bounded number of frames (never `pumpAndSettle` while an
/// indeterminate spinner may be on screen — that would hang the settle loop).
Future<void> pumpFrames(WidgetTester tester, {int n = 6}) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

void main() {
  late CacheDatabase db;
  late FakeSeasonRepository repo;
  late FakeTokenStore tokens;
  late int fetchCalls;
  late ProviderContainer container;

  /// Full app under a dev-auth session with one seeded season row.
  Future<void> setupDevAuth() async {
    db = CacheDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    repo = FakeSeasonRepository(BreakdownApi(), SeasonCacheDao(db));
    tokens = FakeTokenStore(null);
    fetchCalls = 0;
    final holder = ValueNotifier<Result<List<SeasonView>>>(
      Right([season('m1', number: 1, title: 'Menu Season')]),
    );
    container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        appConfigProvider.overrideWithValue(devAuthConfig),
        tokenStoreProvider.overrideWithValue(tokens),
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
    // Dev-auth boots at the gate; Continue like the login screen offers.
    await container.read(authSessionControllerProvider.notifier).signIn();
  }

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const App()),
    );
    await pumpFrames(tester);
  }

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('seasons-menu-button')));
    await tester.pumpAndSettle();
  }

  group('Shell menu (task 4.1/4.3)', () {
    testWidgets('shows the authenticated identity', (tester) async {
      await setupDevAuth();
      await pumpApp(tester);
      await openMenu(tester);

      expect(find.byKey(const Key('menu-identity')), findsOneWidget);
      expect(find.text('dev-user'), findsOneWidget);
      expect(find.byKey(const Key('menu-about')), findsOneWidget);
      expect(find.byKey(const Key('menu-settings')), findsOneWidget);
      expect(find.byKey(const Key('menu-signout')), findsOneWidget);
    });

    testWidgets('sign out returns to login: no refetch, cache emptied once', (
      tester,
    ) async {
      await setupDevAuth();
      await pumpApp(tester);
      expect(find.text('Menu Season'), findsOneWidget);
      final fetchesBeforeSignOut = fetchCalls;
      expect(fetchesBeforeSignOut, greaterThanOrEqualTo(1));

      await openMenu(tester);
      await tester.tap(find.byKey(const Key('menu-signout')));
      await pumpFrames(tester);

      // Root recomposed to LoginScreen; no post-signout projection render.
      expect(find.byKey(const Key('login-continue-button')), findsOneWidget);
      expect(find.byKey(const Key('seasons-list')), findsNothing);
      expect(fetchCalls, fetchesBeforeSignOut);
      // Cache emptied exactly once, rows really gone.
      expect(repo.clearCacheCalls, 1);
      expect(await SeasonCacheDao(db).readAll(), isEmpty);
    });

    testWidgets('about opens the info dialog', (tester) async {
      await setupDevAuth();
      await pumpApp(tester);

      await openMenu(tester);
      await tester.tap(find.byKey(const Key('menu-about')));
      await pumpFrames(tester);

      expect(find.byKey(const Key('info-dialog')), findsOneWidget);
      expect(find.byKey(const Key('info-version')), findsOneWidget);
      expect(find.byKey(const Key('info-license')), findsOneWidget);
      expect(find.byKey(const Key('info-ai-notice')), findsOneWidget);
    });

    testWidgets('settings opens the settings dialog', (tester) async {
      await setupDevAuth();
      await pumpApp(tester);

      await openMenu(tester);
      await tester.tap(find.byKey(const Key('menu-settings')));
      await pumpFrames(tester);

      expect(find.byKey(const Key('settings-dialog')), findsOneWidget);
      expect(find.byKey(const Key('settings-uri-field')), findsOneWidget);
    });

    testWidgets('failed sign-out leaves the gate, error surfaced', (
      tester,
    ) async {
      db = CacheDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      repo = FakeSeasonRepository(BreakdownApi(), SeasonCacheDao(db));
      tokens = FakeTokenStore(null);
      container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          appConfigProvider.overrideWithValue(devAuthConfig),
          tokenStoreProvider.overrideWithValue(tokens),
          cacheDatabaseProvider.overrideWithValue(db),
          seasonRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);
      // Dev-auth skips the token wipe — fail the CACHE clear instead so the
      // Err path renders: main-app content unreachable, error surfaced.
      repo.clearCacheResult = const Left(
        ProblemError(code: 'cache.clear_failed'),
      );
      await container.read(authSessionControllerProvider.notifier).signIn();
      await pumpApp(tester);
      expect(find.text('Seasons'), findsOneWidget);

      await openMenu(tester);
      await tester.tap(find.byKey(const Key('menu-signout')));
      await pumpFrames(tester);

      // Fail-closed: seasons gone, LoginScreen carries the error copy.
      expect(find.byKey(const Key('seasons-list')), findsNothing);
      expect(find.byKey(const Key('login-error-banner')), findsOneWidget);
      expect(find.textContaining('cache.clear_failed'), findsOneWidget);
    });
  });
}
