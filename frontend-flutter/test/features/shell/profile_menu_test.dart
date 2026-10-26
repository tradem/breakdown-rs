// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (neuralwatt)
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)

// The user ACCOUNT DRAWER tests (issue #653): the profile affordance in
// the shell top bar opens a Material 3 NavigationDrawer as a side overlay
// (Spotify-style, scrim included) — explicitly NOT a bottom sheet and NOT
// a dialog. The drawer's entries are the former profile sheet's: identity,
// About (→ FULL SCREEN route), Settings (→ full-screen push) and Sign out
// (→ the OIDC/session-reset flow back to the unauthenticated gate).
//
// Entry path: tap `profile-menu-button`, then the labeled drawer entry.
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
import 'package:frontend_flutter/design/theme.dart';
import 'package:frontend_flutter/features/ai_import/import_jobs/jobs_controller.dart';
import 'package:frontend_flutter/features/app_info/app_info_screen.dart';
import 'package:frontend_flutter/features/seasons/seasons_controller.dart';
import 'package:frontend_flutter/l10n/generated/app_localizations.dart';
import 'package:frontend_flutter/src/health/backend_health_providers.dart';

import '../seasons/seasons_test_fakes.dart';
import '../ai_import/jobs_screen_test.dart' show FakeJobsRepository;

import 'package:frontend_flutter/src/connectivity/connectivity_providers.dart';

import '../../support/silent_connectivity.dart';

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
  ///
  /// [healthSnapshot] freezes the drawer's backend health controller — the
  /// overridden build never polls (no probe/Dio, no pending timers).
  Future<void> setupDevAuth({
    BackendHealthSnapshot healthSnapshot = const BackendHealthSnapshot(
      tier: BackendHealthTier.healthy,
    ),
  }) async {
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
        // Issue #654: the shell hosts the offline pill whose keep-alive
        // controller must not activate the real connectivity_plus channel
        // in tests (activation error fails goldens via FlutterError).
        passiveConnectivitySourceProvider.overrideWithValue(
          const SilentPassiveSource(),
        ),
        // Issue #657: the drawer hosts the backend health pill. Freeze the
        // controller to a deterministic tier — the overridden build never
        // polls, so no probe/Dio activity and no pending timers in the
        // widget-test environment. The pill's own tiers are covered in
        // backend_health_pill_test.dart.
        backendHealthControllerProvider.overrideWithValue(healthSnapshot),
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

  /// Opens the account drawer (issue #653): the drawer's side-entrance
  /// animation needs real frames — no wall-clock budget, just enough
  /// deterministic pumps for the entrance (246ms Material duration).
  Future<void> openAccountDrawer(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('profile-menu-button')));
    await pumpFrames(tester, n: 30);
  }

  group('account drawer (issue #653): side overlay, not a bottom sheet', () {
    testWidgets('the user icon opens the side NavigationDrawer with entries', (
      tester,
    ) async {
      await setupDevAuth();
      await pumpApp(tester);
      await openAccountDrawer(tester);

      // It is the M3 NavigationDrawer hosted by the shell Scaffold — a
      // side overlay with scrim, NOT a bottom sheet (nothing slides up
      // from the bottom) and NOT a dialog.
      expect(find.byKey(const Key('profile-account-drawer')), findsOneWidget);
      expect(find.byType(NavigationDrawer), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byKey(const Key('profile-identity')), findsOneWidget);
      expect(find.text('dev-user'), findsOneWidget);
      // Issue #657: the health pill leads the drawer header, ABOVE the
      // identity entry, labeled (never color alone).
      expect(find.byKey(const Key('profile-health-pill')), findsOneWidget);
      expect(find.text('Backend ready'), findsOneWidget);
      expect(find.byKey(const Key('profile-about')), findsOneWidget);
      expect(find.byKey(const Key('profile-settings')), findsOneWidget);
      expect(find.byKey(const Key('profile-signout')), findsOneWidget);
      // Hard acceptance criterion of issue #610: the costume-category
      // vocabulary never lives with the user settings.
      expect(find.text('Costume categories'), findsNothing);
      expect(find.byKey(const Key('profile-categories')), findsNothing);
    });

    // Issue #730: the pill is the tap target for the per-dependency detail
    // sheet, and the drawer deliberately STAYS OPEN underneath (the pill is
    // the health controller's only keeping-alive listener).
    testWidgets('tapping the health pill opens the detail sheet over the '
        'still-open drawer', (tester) async {
      await setupDevAuth(
        healthSnapshot: const BackendHealthSnapshot(
          tier: BackendHealthTier.unhealthy,
          checks: [
            BackendHealthCheck(
              name: 'vault',
              status: BackendHealthCheckStatus.unhealthy,
            ),
            BackendHealthCheck(
              name: 'postgres',
              status: BackendHealthCheckStatus.healthy,
            ),
          ],
        ),
      );
      await pumpApp(tester);
      await openAccountDrawer(tester);
      expect(
        find.byKey(const Key('backend-health-detail-sheet')),
        findsNothing,
      );

      await tester.tap(find.byKey(const Key('profile-health-pill')));
      await pumpFrames(tester, n: 30);

      expect(
        find.byKey(const Key('backend-health-detail-sheet')),
        findsOneWidget,
      );
      // Drawer still open → the pill stays mounted → the poll loop lives on.
      expect(find.byKey(const Key('profile-account-drawer')), findsOneWidget);
      expect(find.byKey(const Key('profile-health-pill')), findsOneWidget);
      // Per-dependency rows, broken dependency first (English test locale).
      expect(
        find.byKey(const Key('backend-health-detail-check-vault')),
        findsOneWidget,
      );
      expect(find.text('Secret storage'), findsOneWidget);
      expect(find.text('Database'), findsOneWidget);
    });

    testWidgets('tap-outside (scrim) closes the drawer', (tester) async {
      await setupDevAuth();
      await pumpApp(tester);
      await openAccountDrawer(tester);
      expect(find.byKey(const Key('profile-account-drawer')), findsOneWidget);

      // Tap the scrim: a point right of the drawer, relative to the
      // SCREEN (the drawer's own box may span the full screen width, so
      // its right edge is not a reliable scrim position).
      final screen = tester.view.physicalSize;
      await tester.tapAt(Offset(screen.width - 40, screen.height / 2));
      // Bounded pumps: the drawer exit animation plus the frames the
      // framework needs to finalize the route removal afterwards.
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(find.byKey(const Key('profile-account-drawer')), findsNothing);
    });

    testWidgets('about opens a FULL SCREEN route, never a dialog', (
      tester,
    ) async {
      await setupDevAuth();
      await pumpApp(tester);

      await openAccountDrawer(tester);
      await tester.tap(find.byKey(const Key('profile-about')));
      await pumpFrames(tester, n: 12);

      // Issue #653 hard requirement: a full screen route with app-bar back
      // navigation — no AlertDialog, and the route is a MaterialPageRoute
      // (a screen route), not a popup/dialog route.
      expect(find.byKey(const Key('app-info-screen')), findsOneWidget);
      expect(find.byKey(const Key('app-info-appbar')), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      final route = ModalRoute.of(
        tester.element(find.byKey(const Key('app-info-screen'))),
      );
      expect(route, isA<MaterialPageRoute<void>>());
      expect(route, isNot(isA<PopupRoute<void>>()));
      expect(find.byType(AppInfoScreen), findsOneWidget);
      // Content contract carried over from the former dialog.
      expect(find.byKey(const Key('info-version')), findsOneWidget);
      expect(find.byKey(const Key('info-license')), findsOneWidget);
      expect(find.byKey(const Key('info-ai-notice')), findsOneWidget);
    });

    testWidgets('settings opens the settings screen (no dialog)', (
      tester,
    ) async {
      await setupDevAuth();
      await pumpApp(tester);

      await openAccountDrawer(tester);
      await tester.tap(find.byKey(const Key('profile-settings')));
      // Bounded pumps past the drawer's full exit animation — while the
      // drawer is still sliding out, drag gestures re-engage its gesture
      // handling and never reach the settings list beneath.
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      // The drawer is gone; the settings screen pushed on the destination
      // navigator (issue #516: a pushed full screen, not a dialog).
      expect(find.byKey(const Key('profile-account-drawer')), findsNothing);
      expect(find.byKey(const Key('settings-screen')), findsOneWidget);
      expect(find.byKey(const Key('settings-appbar')), findsOneWidget);
      // Issue #708: the inline egg switches moved to the dedicated
      // Easter-eggs screen — the settings screen opens onto the entry
      // tile instead.
      expect(
        find.byKey(const Key('settings-easter-eggs-entry')),
        findsOneWidget,
      );
      // Issue #644: the AI section grew the list — the dev URI field now
      // sits below the fold at this viewport (the ListView builds lazily,
      // so the key is not even IN the tree until scrolled to).
      await tester.dragUntilVisible(
        find.byKey(const Key('settings-uri-field')),
        find.byKey(const Key('settings-list')),
        const Offset(0, -200),
      );
      await pumpFrames(tester);
      expect(find.byKey(const Key('settings-uri-field')), findsOneWidget);
    });

    testWidgets(
      'AI-import jobs entry (issue #672): visible when authenticated, sits '
      "between Settings and Sign out, opens the jobs screen full-screen "
      'under the named route "ai-import-jobs" (apply-outcome popUntil target)',
      (tester) async {
        await setupDevAuth();
        await pumpApp(tester);

        await openAccountDrawer(tester);
        // The entry exists and sits between Einstellungen and Abmelden
        // (operational entry above the destructive sign-out).
        final aiImports = find.byKey(const Key('profile-ai-imports'));
        expect(aiImports, findsOneWidget);
        expect(find.byKey(const Key('profile-settings')), findsOneWidget);
        expect(
          tester.getTopLeft(aiImports).dy,
          greaterThan(
            tester.getTopLeft(find.byKey(const Key('profile-settings'))).dy,
          ),
        );
        expect(
          tester.getTopLeft(aiImports).dy,
          lessThan(
            tester.getTopLeft(find.byKey(const Key('profile-signout'))).dy,
          ),
        );

        // Tap → jobs screen pushed FULL SCREEN inside the active
        // destination's stack (same seam as Settings; never a dialog),
        // under the named route the apply outcome pops back to.
        await tester.tap(aiImports);
        for (var i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(find.byKey(const Key('profile-account-drawer')), findsNothing);
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.byKey(const Key('ai-jobs-empty')), findsOneWidget);
        final route = ModalRoute.of(
          tester.element(find.byKey(const Key('ai-jobs-empty'))),
        );
        expect(route, isA<MaterialPageRoute<void>>());
        expect(route!.settings.name, 'ai-import-jobs');
      },
    );

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

      await openAccountDrawer(tester);
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
          // See the first container: never activate the connectivity channel
          // in the widget-test environment.
          passiveConnectivitySourceProvider.overrideWithValue(
            const SilentPassiveSource(),
          ),
          // Issue #657: freeze the drawer's health pill (no probe, no
          // timers) — same rationale as the first container.
          backendHealthControllerProvider.overrideWithValue(
            const BackendHealthSnapshot(tier: BackendHealthTier.healthy),
          ),
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
      await openAccountDrawer(tester);
      await tester.tap(find.byKey(const Key('profile-signout')));
      await pumpFrames(tester, n: 30);

      // Fail-closed: the shell is gone, LoginScreen carries the error copy.
      expect(find.byKey(const Key('shell-navigation-bar')), findsNothing);
      expect(find.byKey(const Key('login-error-banner')), findsOneWidget);
      expect(find.textContaining('Something went wrong'), findsOneWidget);
    });
  });

  group('account drawer goldens (issue #653, German template locale)', () {
    Future<void> pumpGolden(
      WidgetTester tester, {
      required String golden,
      required ThemeMode mode,
    }) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppThemes.light(),
            darkTheme: AppThemes.dark(),
            themeMode: mode,
            // AGENTS.md §6: goldens use the German template locale.
            locale: const Locale('de'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: const App(),
          ),
        ),
      );
      await pumpFrames(tester, n: 12);
      await openAccountDrawer(tester);
      expect(find.byKey(const Key('profile-account-drawer')), findsOneWidget);
      await expectLater(find.byType(App), matchesGoldenFile('goldens/$golden'));
    }

    testWidgets('light', (tester) async {
      await setupDevAuth();
      await pumpGolden(
        tester,
        golden: 'account_drawer_light.png',
        mode: ThemeMode.light,
      );
    });

    testWidgets('dark', (tester) async {
      await setupDevAuth();
      await pumpGolden(
        tester,
        golden: 'account_drawer_dark.png',
        mode: ThemeMode.dark,
      );
    });
  });
}
