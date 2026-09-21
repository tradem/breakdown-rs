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
import 'package:frontend_flutter/features/shell/more_tab_screen.dart';
import 'package:frontend_flutter/features/shell/shell_controller.dart';
import 'package:frontend_flutter/features/shell/window_size_class.dart';

import '../test/features/seasons/seasons_test_fakes.dart';

SeasonView _season() => SeasonView(
  (b) => b
    ..id = 'season-1'
    ..number = 1
    ..seriesId = 'series-e2e'
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
      expect(find.byType(SeasonsScreen), findsOneWidget);
      expect(find.text('E2E Season'), findsOneWidget);

      // Planen tab: the AI-import entry lives at the top of the list
      // (moved from the Mehr tab — the import creates planning entities).
      // Assert it BEFORE the season drilldown: the tab's nested Navigator
      // persists (IndexedStack), and a default finder skips offstage routes
      // behind a pushed BlocksScreen.
      await tester.tap(find.byKey(const Key('shell-destination-1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('planen-ai-import')), findsOneWidget);

      // Season row → BlocksScreen on the Planen navigator.
      await tester.tap(find.byKey(const Key('planen-season-season-1')));
      await tester.pumpAndSettle();
      expect(find.byType(BlocksScreen), findsOneWidget);
      // The drilldown set the active season from the acted-on DTO (D5).
      expect(
        container.read(shellControllerProvider).activeSeason?.id,
        'season-1',
      );

      // Garderobe tab (label renamed from Kleidung; keys kept): season-scoped
      // costume domain entries, no error.
      await tester.tap(find.byKey(const Key('shell-destination-2')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('kleidung-list')), findsOneWidget);
      expect(find.text('Kostüme'), findsOneWidget);
      expect(find.text('Figuren'), findsOneWidget);

      // Mehr tab: labeled secondary entries render (no import entry here
      // anymore — it moved to the Planen tab).
      await tester.tap(find.byKey(const Key('shell-destination-3')));
      await tester.pumpAndSettle();
      expect(find.byType(MoreTabScreen), findsOneWidget);
      expect(find.byKey(const Key('mehr-signout')), findsOneWidget);
      expect(find.byKey(const Key('mehr-ai-import')), findsNothing);

      // Back to Planen: the drilldown position is preserved (IndexedStack).
      await tester.tap(find.byKey(const Key('shell-destination-1')));
      await tester.pumpAndSettle();
      expect(find.byType(BlocksScreen), findsOneWidget);
      expect(
        container.read(shellControllerProvider).selectedIndex,
        kPlanenTabIndex,
      );
      // The smoke exercises the COMPACT morphology throughout.
      expect(resolveWindowSizeClass(360), WindowSizeClass.compact);
    },
  );
}
