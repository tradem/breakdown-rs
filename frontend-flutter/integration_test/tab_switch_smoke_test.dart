// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

// Tier-4 integration smoke (`redesign-app-shell-navigation` task 5.6,
// on device/emulator, dev-auth): login → Season tab → Planen drilldown →
// Kleidung (active-season scope from the drilldown) → Mehr. Runs against
// scriptable fakes (no backend): the device exercises the real shell,
// adaptive navigation, per-tab nested navigators and the active-season
// hand-off. Not part of the headless `flutter test` pass.

import 'package:breakdown_api/breakdown_api.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:integration_test/integration_test.dart';

import 'package:frontend_flutter/app.dart';
import 'package:frontend_flutter/auth/auth_providers.dart';
import 'package:frontend_flutter/auth/membership/membership_providers.dart';
import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/data/block_repository.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/hierarchy_cache_dao.dart';
import 'package:frontend_flutter/data/cache/season_cache_dao.dart';
import 'package:frontend_flutter/data/cache/seasons_cache_providers.dart';
import 'package:frontend_flutter/domain/reconciliation/reconciliation_scheduler.dart';
import 'package:frontend_flutter/features/blocks/blocks_controller.dart';
import 'package:frontend_flutter/features/blocks/blocks_screen.dart';
import 'package:frontend_flutter/features/costume_categories/costume_categories_controller.dart';
import 'package:frontend_flutter/features/seasons/seasons_screen.dart';
import 'package:frontend_flutter/features/shell/production_overview_screen.dart';
import 'package:frontend_flutter/features/shell/schedule_tab_screen.dart';
import 'package:frontend_flutter/features/shell/script_tab_screen.dart';
import 'package:frontend_flutter/features/shell/shell_controller.dart';
import 'package:frontend_flutter/features/shell/window_size_class.dart';

import '../test/features/seasons/seasons_test_fakes.dart';

SeasonView _season() => SeasonView(
  (b) => b
    ..id = 'season-1'
    ..number = 1
    ..projectId = 'series-e2e'
    ..title = 'E2E Season'
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'tab-switch smoke: login → Season → Planen drilldown → Kleidung → Mehr',
    (tester) async {
      final db = CacheDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = FakeSeasonRepository(BreakdownApi(), SeasonCacheDao(db));
      final holder = ValueNotifier<Result<List<SeasonView>>>(
        Right([_season()]),
      );
      final container = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(devAuthConfig),
          cacheDatabaseProvider.overrideWithValue(db),
          seasonRepositoryProvider.overrideWithValue(repo),
          reconciliationSchedulerProvider.overrideWith(
            (ref) => const ImmediateReconciliationScheduler(),
          ),
          seasonsListFetchProvider.overrideWith((ref) async {
            final r = ref.watch(seasonRepositoryProvider);
            return r.fetchAndCacheList(() async => holder.value);
          }),
          // Planen drilldown / Mehr categories fetch seams (no network).
          blockRepositoryProvider.overrideWithValue(
            BlockRepository(BreakdownApi(), BlockCacheDao(db)),
          ),
          blocksListFetchProvider('season-1')
              .overrideWith((ref) async => const Right([])),
          costumeCategoriesListFetchProvider('season-1')
              .overrideWith((ref) async => const Right([])),
          membershipFetchProvider('season-1')
              .overrideWith((ref) async => const Left(ProblemError(code: 'x'))),
        ],
      );
      addTearDown(container.dispose);

      // COMPACT viewport: the smoke asserts the bottom NavigationBar and
      // the `shell-destination-<n>` tap targets of the compact morphology
      // (800dp wide would render the rail instead — CodeRabbit review fix).
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const App()),
      );
      await tester.pumpAndSettle();

      // Gate → Continue → shell Season tab (compact: bottom NavigationBar).
      await tester.tap(find.byKey(const Key('login-continue-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('shell-navigation-bar')), findsOneWidget);
      // Cast is the initial destination (issue #610) — without a season
      // scope it renders its season-selection empty state.
      expect(find.byKey(const Key('cast-empty')), findsOneWidget);

      // Season scope: the picker on the shell's context bar is the one
      // surface that SETS the active season (the Season tab is dissolved).
      await tester.tap(find.byKey(const Key('cast-pick-season-cta')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('season-scope-list')), findsOneWidget);
      // Season management entry → the seasons overview (create/manage).
      await tester.tap(find.byKey(const Key('season-scope-manage-seasons')));
      await tester.pumpAndSettle();
      expect(find.byType(SeasonsScreen), findsOneWidget);
      expect(find.text('E2E Season'), findsOneWidget);

      // Season row → the production overview (the re-homed Planen content):
      // the card tap sets the active season from the acted-on DTO (D5) and
      // opens the hierarchy spine.
      await tester.tap(find.byKey(const Key('season-1')));
      await tester.pumpAndSettle();
      expect(find.byType(ProductionOverviewScreen), findsOneWidget);
      expect(
        container.read(shellControllerProvider).activeSeason?.id,
        'season-1',
      );
      // The AI-import entry lives with the production structure.
      expect(find.byKey(const Key('production-ai-import')), findsOneWidget);

      // Production overview → BlocksScreen.
      await tester.tap(find.byKey(const Key('production-blocks-entry')));
      await tester.pumpAndSettle();
      expect(find.byType(BlocksScreen), findsOneWidget);

      // Back to the shell: the Cast destination renders the roster now that
      // a season scope is set (issue #610: costumes/characters live here).
      await tester.tap(find.byKey(const Key('shell-destination-0')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('season-scope-chip')), findsOneWidget);
      expect(find.byKey(const Key('cast-surface-switch')), findsOneWidget);

      // Script destination: the season's chronological scene overview.
      await tester.tap(find.byKey(const Key('shell-destination-1')));
      await tester.pumpAndSettle();
      expect(find.byType(ScriptTabScreen), findsOneWidget);

      // Schedule/Dispo destination: the season's shooting days.
      await tester.tap(find.byKey(const Key('shell-destination-2')));
      await tester.pumpAndSettle();
      expect(find.byType(ScheduleTabScreen), findsOneWidget);
      expect(
        container.read(shellControllerProvider).selectedIndex,
        kScheduleTabIndex,
      );

      // Profile affordance (issue #610): the dissolved Mehr tab's entries.
      await tester.tap(find.byKey(const Key('profile-menu-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('profile-signout')), findsOneWidget);
      // Costume categories never live in the profile/settings surface.
      expect(find.byKey(const Key('profile-categories')), findsNothing);
      // The smoke exercises the COMPACT morphology throughout.
      expect(resolveWindowSizeClass(360), WindowSizeClass.compact);
    },
  );
}
