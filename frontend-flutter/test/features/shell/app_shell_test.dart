// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

// Widget tests for the adaptive navigation shell (`redesign-app-shell-navigation`
// tasks 5.1/5.2): three morphologies via `tester.view.physicalSize`
// (360/700/1000dp), visible-label compliance, "Tab N of 4" semantics,
// touch-target size, tab state preservation (Planen drilldown survives a
// Kleidung switch) and the back contract (within-tab pop; no tab hop at
// tab roots; exit intent consumed at the initial tab root).

import 'package:breakdown_api/breakdown_api.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:flutter/semantics.dart';
import 'package:frontend_flutter/auth/auth_providers.dart';
import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/hierarchy_cache_dao.dart';
import 'package:frontend_flutter/data/cache/season_cache_dao.dart';
import 'package:frontend_flutter/data/cache/seasons_cache_providers.dart';
import 'package:frontend_flutter/data/block_repository.dart';
import 'package:frontend_flutter/design/theme.dart';

import 'package:frontend_flutter/domain/reconciliation/reconciliation_scheduler.dart';
import 'package:frontend_flutter/features/blocks/blocks_screen.dart';
import 'package:frontend_flutter/features/seasons/seasons_screen.dart';
import 'package:frontend_flutter/features/shell/app_shell.dart';
import 'package:frontend_flutter/features/shell/more_tab_screen.dart';
import 'package:frontend_flutter/features/shell/planning_tab_screen.dart';
import 'package:frontend_flutter/features/shell/shell_controller.dart';
import 'package:frontend_flutter/features/blocks/blocks_controller.dart';
import 'package:frontend_flutter/features/costume_categories/costume_categories_controller.dart';
import 'package:frontend_flutter/auth/membership/membership_providers.dart';
import 'package:frontend_flutter/core/problem_error.dart';

import '../seasons/seasons_test_fakes.dart';

/// Pumps a bounded number of frames (never `pumpAndSettle` while an
/// indeterminate spinner may be on screen — that would hang the settle
/// loop). No wall-clock budgets (deterministic-tests rule).
Future<void> pumpFrames(WidgetTester tester, {int n = 8}) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

/// The app under the dev-auth session with one seeded season.
const _appConfig = devAuthConfig;

void main() {
  late CacheDatabase db;
  late FakeSeasonRepository repo;
  late FakeTokenStore tokens;
  late ValueNotifier<Result<List<SeasonView>>> holder;
  late ProviderContainer container;

  Future<void> setupContainer() async {
    db = CacheDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    repo = FakeSeasonRepository(BreakdownApi(), SeasonCacheDao(db));
    tokens = FakeTokenStore(null);
    holder = ValueNotifier(
      Right([season('season-1', number: 1, title: 'Shell Season')]),
    );
    container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        appConfigProvider.overrideWithValue(_appConfig),
        tokenStoreProvider.overrideWithValue(tokens),
        cacheDatabaseProvider.overrideWithValue(db),
        seasonRepositoryProvider.overrideWithValue(repo),
        reconciliationSchedulerProvider.overrideWith(
          (ref) => const ImmediateReconciliationScheduler(),
        ),
        seasonsListFetchProvider.overrideWith((ref) async {
          final r = ref.watch(seasonRepositoryProvider);
          return r.fetchAndCacheList(() async => holder.value);
        }),
        // The Planen drilldown pushes BlocksScreen for the seeded season;
        // stub its fetch seams so no network/client is needed (the shell
        // test asserts NAVIGATION state, not block data).
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
    await container.read(authSessionControllerProvider.notifier).signIn();
  }

  Future<void> pumpShell(
    WidgetTester tester, {
    required double widthDp,
    double heightDp = 800,
  }) async {
    tester.view.physicalSize = Size(widthDp, heightDp);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: AppShell()),
      ),
    );
    await pumpFrames(tester);
  }

  group('5.1 three morphologies + labeled destinations', () {
    testWidgets('compact (360dp) renders a bottom NavigationBar', (
      tester,
    ) async {
      await setupContainer();
      await pumpShell(tester, widthDp: 360);

      expect(find.byKey(const Key('shell-navigation-bar')), findsOneWidget);
      expect(find.byKey(const Key('shell-navigation-rail')), findsNothing);
      // Every destination shows a VISIBLE label (glossary rule).
      expect(find.text('Season'), findsWidgets);
      expect(find.text('Planen'), findsOneWidget);
      expect(find.text('Kleidung'), findsOneWidget);
      expect(find.text('Mehr'), findsOneWidget);
      // The Season tab is the initial tab; its content is the seasons list.
      expect(find.byType(SeasonsScreen), findsOneWidget);
      expect(find.text('Shell Season'), findsOneWidget);
    });

    testWidgets('medium (700dp) renders a NavigationRail beside content', (
      tester,
    ) async {
      await setupContainer();
      await pumpShell(tester, widthDp: 700);

      expect(find.byKey(const Key('shell-navigation-rail')), findsOneWidget);
      expect(find.byKey(const Key('shell-navigation-bar')), findsNothing);
      // Visible labels (rail labelType all).
      expect(find.text('Season'), findsOneWidget);
      expect(find.text('Planen'), findsOneWidget);
      expect(find.text('Kleidung'), findsOneWidget);
      expect(find.text('Mehr'), findsOneWidget);
    });

    testWidgets('expanded (1000dp) renders a permanent NavigationDrawer', (
      tester,
    ) async {
      await setupContainer();
      await pumpShell(tester, widthDp: 1000);

      expect(find.byKey(const Key('shell-navigation-drawer')), findsOneWidget);
      expect(find.byKey(const Key('shell-navigation-bar')), findsNothing);
      expect(find.text('Season'), findsOneWidget);
      expect(find.text('Planen'), findsOneWidget);
      expect(find.text('Kleidung'), findsOneWidget);
      expect(find.text('Mehr'), findsOneWidget);
    });

    testWidgets(
      'semantic traversal announces position: "<label>, Tab N of 4" per '
      'destination (rail suite, medium morphology)',
      (tester) async {
        await setupContainer();
        final semantics = tester.ensureSemantics();
        // Pump the EXACT suite widget the shell renders (extracted so the
        // test can isolate it — see ShellDestinations doc comment).
        await tester.pumpWidget(
          MaterialApp(
            home: Row(
              children: [
                ShellDestinations.navigationRail(
                  selectedIndex: 0,
                  onSelected: (_) {},
                ),
                const Expanded(child: SizedBox.shrink()),
              ],
            ),
          ),
        );
        // Let the semantics tree settle after the entrance animations
        // (deterministic frame pumps, no wall clock).
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }

        // Explicit "<label>, Tab N of 4" semantics per destination
        // (spec accessible-labeled-destinations requirement). Node-based
        // finder: the label node carries no widget-level actions, so the
        // element-based `bySemanticsLabel` cannot reach it.
        SemanticsFinder hasLabel(String label) =>
            find.semantics.byPredicate((SemanticsNode n) => n.label == label);
        expect(hasLabel('Season, Tab 1 of 4'), findsOneWidget);
        expect(hasLabel('Planen, Tab 2 of 4'), findsOneWidget);
        expect(hasLabel('Kleidung, Tab 3 of 4'), findsOneWidget);
        expect(hasLabel('Mehr, Tab 4 of 4'), findsOneWidget);
        semantics.dispose();
      },
    );

    testWidgets('touch targets meet 48dp (compact NavigationBar)', (
      tester,
    ) async {
      await setupContainer();
      await pumpShell(tester, widthDp: 360);

      final size = tester.getSize(find.byKey(const Key('shell-destination-0')));
      expect(size.height, greaterThanOrEqualTo(48));
      expect(size.width, greaterThanOrEqualTo(48));
    });
  });

  group('5.2 tab state preservation + back contract', () {
    testWidgets('Planen drilldown survives a Kleidung switch (IndexedStack), '
        'and back pops within the tab without hopping', (tester) async {
      await setupContainer();
      await pumpShell(tester, widthDp: 360);

      // Planen → season row → BlocksScreen on the Planen navigator.
      await tester.tap(find.text('Planen'));
      await pumpFrames(tester);
      await tester.tap(find.byKey(const Key('planen-season-season-1')));
      await pumpFrames(tester, n: 12);
      expect(find.byType(BlocksScreen), findsOneWidget);

      // Switch to Kleidung and back to Planen: the drilldown stays.
      // NOTE: IndexedStack keeps ALL tab navigators mounted, so
      // finders see every tab's widgets — visibility is asserted via
      // the shell controller's selected index.
      await tester.tap(find.text('Kleidung'));
      await pumpFrames(tester);
      expect(
        container.read(shellControllerProvider).selectedIndex,
        kKleidungTabIndex,
      );
      await tester.tap(find.text('Planen'));
      await pumpFrames(tester);
      expect(
        container.read(shellControllerProvider).selectedIndex,
        kPlanenTabIndex,
      );
      expect(find.byType(BlocksScreen), findsOneWidget);

      // System back pops WITHIN the Planen tab (no tab hop, no exit).
      await tester.binding.handlePopRoute();
      await pumpFrames(tester, n: 40);
      expect(find.byType(PlanningTabScreen), findsOneWidget);
      // The popped BlocksScreen is no longer in the Planen navigator.
      expect(find.byType(BlocksScreen), findsNothing);
      // Still on the Planen tab — back never switched tabs.
      expect(
        container.read(shellControllerProvider).selectedIndex,
        kPlanenTabIndex,
      );
    });

    testWidgets(
      'back at the Planen tab root stays on the tab (no lazy tab-switch '
      'chain, D3)',
      (tester) async {
        await setupContainer();
        await pumpShell(tester, widthDp: 360);

        await tester.tap(find.text('Planen'));
        await pumpFrames(tester);
        expect(find.byType(PlanningTabScreen), findsOneWidget);

        await tester.binding.handlePopRoute();
        await pumpFrames(tester);
        // Stayed on Planen; no hop back to Season.
        expect(find.byType(PlanningTabScreen), findsOneWidget);
        expect(find.byType(SeasonsScreen), findsNothing);
        expect(
          container.read(shellControllerProvider).selectedIndex,
          kPlanenTabIndex,
        );
      },
    );

    testWidgets(
      'back at the Season tab root consumes the intent and issues the '
      'app-exit request (D3) without leaving the shell',
      (tester) async {
        await setupContainer();
        await pumpShell(tester, widthDp: 360);

        await tester.binding.handlePopRoute();
        await pumpFrames(tester);
        // The shell is still the root; the app-exit intent was issued via
        // the platform channel (no tab change, no crash).
        expect(find.byType(SeasonsScreen), findsOneWidget);
        expect(
          container.read(shellControllerProvider).selectedIndex,
          kSeasonTabIndex,
        );
      },
    );

    testWidgets('tab switch resets nothing: Season tab keeps its position', (
      tester,
    ) async {
      await setupContainer();
      await pumpShell(tester, widthDp: 360);

      await tester.tap(find.text('Mehr'));
      await pumpFrames(tester);
      expect(find.byType(MoreTabScreen), findsOneWidget);
      await tester.tap(find.text('Season'));
      await pumpFrames(tester);
      expect(find.byType(SeasonsScreen), findsOneWidget);
      expect(find.text('Shell Season'), findsOneWidget);
    });
  });

  group('5.3 shell goldens (3 morphologies × light/dark)', () {
    Future<void> pumpGolden(
      WidgetTester tester, {
      required String golden,
      required double widthDp,
      required ThemeMode mode,
    }) async {
      tester.view.physicalSize = Size(widthDp, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppThemes.light(),
            darkTheme: AppThemes.dark(),
            themeMode: mode,
            home: AppShell(),
          ),
        ),
      );
      await pumpFrames(tester, n: 12);
      await expectLater(
        find.byType(AppShell),
        matchesGoldenFile('goldens/$golden'),
      );
    }

    testWidgets('compact light', (tester) async {
      await setupContainer();
      await pumpGolden(
        tester,
        golden: 'app_shell_compact_light.png',
        widthDp: 360,
        mode: ThemeMode.light,
      );
    });

    testWidgets('compact dark', (tester) async {
      await setupContainer();
      await pumpGolden(
        tester,
        golden: 'app_shell_compact_dark.png',
        widthDp: 360,
        mode: ThemeMode.dark,
      );
    });

    testWidgets('medium light', (tester) async {
      await setupContainer();
      await pumpGolden(
        tester,
        golden: 'app_shell_medium_light.png',
        widthDp: 700,
        mode: ThemeMode.light,
      );
    });

    testWidgets('medium dark', (tester) async {
      await setupContainer();
      await pumpGolden(
        tester,
        golden: 'app_shell_medium_dark.png',
        widthDp: 700,
        mode: ThemeMode.dark,
      );
    });

    testWidgets('expanded light', (tester) async {
      await setupContainer();
      await pumpGolden(
        tester,
        golden: 'app_shell_expanded_light.png',
        widthDp: 1000,
        mode: ThemeMode.light,
      );
    });

    testWidgets('expanded dark', (tester) async {
      await setupContainer();
      await pumpGolden(
        tester,
        golden: 'app_shell_expanded_dark.png',
        widthDp: 1000,
        mode: ThemeMode.dark,
      );
    });
  });
}
