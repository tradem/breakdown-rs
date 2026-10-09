// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)
// Co-authored-by: space-bunny-free (opencode-go)
// Co-authored-by: deepseek-v4-flash (neuralwatt)

// The app-menu tests, MIGRATED to the per-view PROFILE affordance (issue
// #610): the dissolved Mehr destination's entries (identity, About,
// Settings, Sign out) now live in the profile sheet every view root
// carries in its app bar. Issue #613 owns the final top-bar design; this
// change only moves the entries off the dissolved destination.
//
// Entry path: tap `profile-menu-button`, then the labeled sheet entry.
// Costume categories are deliberately NOT here (they live with the costume
// content in the Cast view) — asserted below.

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
import 'package:frontend_flutter/data/ai_import_providers.dart';
import 'package:frontend_flutter/data/cache/ai_import_jobs_cache_dao.dart';
import 'package:frontend_flutter/data/cache/season_cache_dao.dart';
import 'package:frontend_flutter/data/cache/seasons_cache_providers.dart';
import 'package:frontend_flutter/features/ai_import/import_jobs/jobs_controller.dart';
import 'package:frontend_flutter/features/seasons/seasons_controller.dart';

import '../seasons/seasons_test_fakes.dart';
import '../ai_import/jobs_screen_test.dart' show FakeJobsRepository;

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
        // The production overview's active-jobs summary row (issue #547):
        // stub the AI-import jobs repository + fetch seam (no client needed
        // here — the shell mounts all three views, none of which fetches
        // jobs at their root).
        aiImportRepositoryProvider.overrideWithValue(
          FakeJobsRepository(BreakdownApi(), AiImportJobsCacheDao(db)),
        ),
        aiImportJobsFetchProvider.overrideWith(
          (ref) async => Right(<AiImportJob>[]),
        ),
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

  /// Opens the profile sheet (bottom sheet animation needs real frames —
  /// no wall-clock budget, just enough pumps for the entrance).
  Future<void> openProfile(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('profile-menu-button')));
    await pumpFrames(tester, n: 30);
  }

  group('profile menu (issue #610, migrated from the Mehr destination)', () {
    testWidgets('shows the authenticated identity', (tester) async {
      await setupDevAuth();
      await pumpApp(tester);
      await openProfile(tester);

      expect(find.byKey(const Key('profile-identity')), findsOneWidget);
      expect(find.text('dev-user'), findsOneWidget);
      expect(find.byKey(const Key('profile-about')), findsOneWidget);
      expect(find.byKey(const Key('profile-settings')), findsOneWidget);
      expect(find.byKey(const Key('profile-signout')), findsOneWidget);
      // Hard acceptance criterion of issue #610: the costume-category
      // vocabulary never lives with the user settings.
      expect(find.text('Costume categories'), findsNothing);
      expect(find.byKey(const Key('profile-categories')), findsNothing);
    });

    testWidgets('sign out returns to login: no refetch, cache emptied once', (
      tester,
    ) async {
      await setupDevAuth();
      await pumpApp(tester);
      // Issue #610: the shell boots into the Cast view, which does NOT read
      // the seasons projection until a season scope is opened — so the
      // "no refetch after sign-out" contract is asserted as "the fetch
      // count never grows during the sign-out", whatever it started at.
      final fetchesBeforeSignOut = fetchCalls;

      await openProfile(tester);
      await tester.tap(find.byKey(const Key('profile-signout')));
      await pumpFrames(tester, n: 30);

      // Root recomposed to LoginScreen; no post-signout projection render.
      expect(find.byKey(const Key('login-continue-button')), findsOneWidget);
      expect(find.byKey(const Key('shell-navigation-bar')), findsNothing);
      expect(fetchCalls, fetchesBeforeSignOut);
      // Cache emptied exactly once, rows really gone.
      expect(repo.clearCacheCalls, 1);
      expect(await SeasonCacheDao(db).readAll(), isEmpty);
    });

    testWidgets('about opens the info dialog', (tester) async {
      await setupDevAuth();
      await pumpApp(tester);

      await openProfile(tester);
      await tester.tap(find.byKey(const Key('profile-about')));
      await pumpFrames(tester);

      expect(find.byKey(const Key('info-dialog')), findsOneWidget);
      expect(find.byKey(const Key('info-version')), findsOneWidget);
      expect(find.byKey(const Key('info-license')), findsOneWidget);
      expect(find.byKey(const Key('info-ai-notice')), findsOneWidget);
    });

    testWidgets('settings opens the settings screen (no dialog)', (
      tester,
    ) async {
      await setupDevAuth();
      await pumpApp(tester);

      await openProfile(tester);
      await tester.tap(find.byKey(const Key('profile-settings')));
      await pumpFrames(tester);

      // Issue #516: a pushed full screen, not a dialog.
      expect(find.byKey(const Key('settings-screen')), findsOneWidget);
      expect(find.byKey(const Key('settings-appbar')), findsOneWidget);
      expect(find.byKey(const Key('settings-uri-field')), findsOneWidget);
      expect(find.byKey(const Key('settings-easter-eggs')), findsOneWidget);
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
          aiImportRepositoryProvider.overrideWithValue(
            FakeJobsRepository(BreakdownApi(), AiImportJobsCacheDao(db)),
          ),
          aiImportJobsFetchProvider.overrideWith(
            (ref) async => Right(<AiImportJob>[]),
          ),
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
      await openProfile(tester);
      await tester.tap(find.byKey(const Key('profile-signout')));
      await pumpFrames(tester, n: 30);

      // Fail-closed: the shell is gone, LoginScreen carries the error copy.
      expect(find.byKey(const Key('shell-navigation-bar')), findsNothing);
      expect(find.byKey(const Key('login-error-banner')), findsOneWidget);
      expect(find.textContaining('Something went wrong'), findsOneWidget);
    });
  });
}
