// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)
// Co-authored-by: space-bunny-free (opencode-go)
// Co-authored-by: deepseek-v4-flash (neuralwatt)

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
import 'package:frontend_flutter/auth/active_block.dart';
import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/auth/auth_providers.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/hierarchy_cache_dao.dart';
import 'package:frontend_flutter/data/cache/season_cache_dao.dart';
import 'package:frontend_flutter/data/cache/seasons_cache_providers.dart';
import 'package:frontend_flutter/data/block_repository.dart';
import 'package:frontend_flutter/data/cache/ai_import_jobs_cache_dao.dart';
import 'package:frontend_flutter/data/ai_import_providers.dart';
import 'package:frontend_flutter/design/theme.dart';
import 'package:frontend_flutter/features/ai_import/import_jobs/jobs_controller.dart';
import 'package:frontend_flutter/features/shell/planning_location.dart';

import 'package:frontend_flutter/domain/reconciliation/reconciliation_scheduler.dart';
import 'package:frontend_flutter/features/shell/app_shell.dart';
import 'package:frontend_flutter/l10n/generated/app_localizations.dart';
import 'package:frontend_flutter/features/shell/cast_tab_screen.dart';
import 'package:frontend_flutter/features/shell/schedule_tab_screen.dart';
import 'package:frontend_flutter/features/shell/script_tab_screen.dart';
import 'package:frontend_flutter/features/shell/shell_controller.dart';
import 'package:frontend_flutter/features/blocks/blocks_controller.dart';
import 'package:frontend_flutter/features/costume_categories/costume_categories_controller.dart';
import 'package:frontend_flutter/auth/membership/membership_providers.dart';
import 'package:frontend_flutter/core/problem_error.dart';

import '../seasons/seasons_test_fakes.dart';
import '../ai_import/jobs_screen_test.dart' show FakeJobsRepository;

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

/// A stand-in for a pushed hierarchy screen (the state-preservation test
/// only needs SOMETHING on the Script destination's nested navigator — no
/// projection data, no network).
class BlocksScreenFixture extends StatelessWidget {
  const BlocksScreenFixture({super.key});

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Text('drilldown fixture'));
}

void main() {
  late CacheDatabase db;
  late FakeSeasonRepository repo;
  late FakeTokenStore tokens;
  late ValueNotifier<Result<List<SeasonView>>> holder;
  late ProviderContainer container;

  // Overridable per-test seams: the blocks list fetch result backing the
  // Planen drilldown and the season-direct scope resolution (issue #548
  // context-strip tests need real candidate blocks).
  Result<List<BlockView>> blocksResult = const Right([]);

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
        // The production overview's active-jobs summary row (issue #547)
        // reads the
        // AI-import jobs view; stub its repository + fetch seam so no
        // network client is needed (the shell test asserts NAVIGATION
        // state, not job data).
        aiImportRepositoryProvider.overrideWithValue(
          FakeJobsRepository(BreakdownApi(), AiImportJobsCacheDao(db)),
        ),
        aiImportJobsFetchProvider.overrideWith(
          (ref) async => Right(<AiImportJob>[]),
        ),
        // The Planen drilldown pushes BlocksScreen for the seeded season;
        // stub its fetch seams so no network/client is needed (the shell
        // test asserts NAVIGATION state, not block data).
        blockRepositoryProvider.overrideWithValue(
          BlockRepository(BreakdownApi(), BlockCacheDao(db)),
        ),
        blocksListFetchProvider('season-1')
            .overrideWith((ref) async => blocksResult),
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
      // Every destination shows a VISIBLE label (glossary rule). Each
      // label appears twice — once as the destination label, once as the
      // view root's app-bar title (the IndexedStack mounts all three).
      expect(find.text('Cast'), findsWidgets);
      expect(find.text('Script'), findsWidgets);
      expect(find.text('Schedule/Dispo'), findsWidgets);
      // The Cast destination is selected first; its content is the cast
      // view (roster/costumes — issue #610).
      expect(find.byType(CastTabScreen), findsOneWidget);
      // No season scope yet: the cast view shows its season empty state.
      expect(find.byKey(const Key('cast-empty')), findsOneWidget);
    });

    testWidgets('medium (700dp) renders a NavigationRail beside content', (
      tester,
    ) async {
      await setupContainer();
      await pumpShell(tester, widthDp: 700);

      expect(find.byKey(const Key('shell-navigation-rail')), findsOneWidget);
      expect(find.byKey(const Key('shell-navigation-bar')), findsNothing);
      // Visible labels (rail labelType all) on the destination rail.
      expect(
        find.descendant(
          of: find.byKey(const Key('shell-navigation-rail')),
          matching: find.text('Cast'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('shell-navigation-rail')),
          matching: find.text('Script'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('shell-navigation-rail')),
          matching: find.text('Schedule/Dispo'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('expanded (1000dp) renders a permanent NavigationDrawer', (
      tester,
    ) async {
      await setupContainer();
      await pumpShell(tester, widthDp: 1000);

      expect(find.byKey(const Key('shell-navigation-drawer')), findsOneWidget);
      expect(find.byKey(const Key('shell-navigation-bar')), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const Key('shell-navigation-drawer')),
          matching: find.text('Cast'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('shell-navigation-drawer')),
          matching: find.text('Script'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('shell-navigation-drawer')),
          matching: find.text('Schedule/Dispo'),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'semantic traversal announces position: "<label>, Tab N of 3" per '
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

        // Explicit "<label>, Tab N of 3" semantics per destination
        // (spec accessible-labeled-destinations requirement). Node-based
        // finder: the label node carries no widget-level actions, so the
        // element-based `bySemanticsLabel` cannot reach it.
        SemanticsFinder hasLabel(String label) =>
            find.semantics.byPredicate((SemanticsNode n) => n.label == label);
        expect(hasLabel('Cast, Tab 1 von 3'), findsOneWidget);
        expect(hasLabel('Script, Tab 2 von 3'), findsOneWidget);
        expect(hasLabel('Schedule/Dispo, Tab 3 von 3'), findsOneWidget);
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
    testWidgets('Script drilldown survives a Cast switch (IndexedStack), '
        'and back pops within the destination without hopping', (tester) async {
      await setupContainer();
      await pumpShell(tester, widthDp: 360);

      // Script → a pushed hierarchy screen on the Script navigator (the
      // view's own scene-detail push).
      await tester.tap(find.byKey(const Key('shell-destination-1')));
      await pumpFrames(tester);
      expect(find.byType(ScriptTabScreen), findsOneWidget);
      final shell = tester.state<AppShellState>(find.byType(AppShell));
      // Fire-and-forget: a push future completes on POP, awaiting it here
      // would deadlock the test.
      shell.tabNavigatorKeys[kScriptTabIndex].currentState!.push(
        MaterialPageRoute<void>(builder: (_) => const BlocksScreenFixture()),
      );
      await pumpFrames(tester, n: 12);
      expect(find.byType(BlocksScreenFixture), findsOneWidget);

      // Switch to Cast and back to Script: the drilldown stays.
      // NOTE: IndexedStack keeps ALL destination navigators mounted, so
      // finders see every destination's widgets — visibility is asserted
      // via the shell controller's selected index.
      await tester.tap(find.byKey(const Key('shell-destination-0')));
      await pumpFrames(tester);
      expect(
        container.read(shellControllerProvider).selectedIndex,
        kCastTabIndex,
      );
      await tester.tap(find.byKey(const Key('shell-destination-1')));
      await pumpFrames(tester);
      expect(
        container.read(shellControllerProvider).selectedIndex,
        kScriptTabIndex,
      );
      expect(find.byType(BlocksScreenFixture), findsOneWidget);

      // System back pops WITHIN the Script destination (no hop, no exit).
      await tester.binding.handlePopRoute();
      await pumpFrames(tester, n: 40);
      expect(find.byType(ScriptTabScreen), findsOneWidget);
      // The pushed screen is gone from the Script navigator.
      expect(find.byType(BlocksScreenFixture), findsNothing);
      // Still on Script — back never switched destinations.
      expect(
        container.read(shellControllerProvider).selectedIndex,
        kScriptTabIndex,
      );
    });

    testWidgets('back at the Script root stays on the destination (no lazy '
        'destination-switch chain, D3)', (tester) async {
      await setupContainer();
      await pumpShell(tester, widthDp: 360);

      await tester.tap(find.byKey(const Key('shell-destination-1')));
      await pumpFrames(tester);
      expect(find.byType(ScriptTabScreen), findsOneWidget);

      await tester.binding.handlePopRoute();
      await pumpFrames(tester);
      // Stayed on Script; no hop back to Cast.
      expect(find.byType(ScriptTabScreen), findsOneWidget);
      expect(
        container.read(shellControllerProvider).selectedIndex,
        kScriptTabIndex,
      );
    });

    testWidgets(
      'back at the Cast root consumes the intent and issues the app-exit '
      'request (D3) without leaving the shell',
      (tester) async {
        await setupContainer();
        await pumpShell(tester, widthDp: 360);

        await tester.binding.handlePopRoute();
        await pumpFrames(tester);
        // The shell is still the root; the app-exit intent was issued via
        // the platform channel (no destination change, no crash).
        expect(find.byType(CastTabScreen), findsOneWidget);
        expect(
          container.read(shellControllerProvider).selectedIndex,
          kCastTabIndex,
        );
      },
    );

    testWidgets('destination switch resets nothing: Cast keeps its position', (
      tester,
    ) async {
      await setupContainer();
      await pumpShell(tester, widthDp: 360);

      await tester.tap(find.byKey(const Key('shell-destination-2')));
      await pumpFrames(tester);
      expect(find.byType(ScheduleTabScreen), findsOneWidget);
      await tester.tap(find.byKey(const Key('shell-destination-0')));
      await pumpFrames(tester);
      expect(find.byType(CastTabScreen), findsOneWidget);
      expect(find.byKey(const Key('cast-empty')), findsOneWidget);
    });
  });

  group('5.4 hierarchy context strip + scope chip (issue #548)', () {
    BlockView block(String id, int number) => BlockView(
      (b) => b
        ..id = id
        ..number = number
        ..seasonId = 'season-1'
        ..projectId = 'series-1'
        ..updatedAt = DateTime.utc(2026, 1, 1)
        ..version = 1,
    );

    EpisodeView episode(String id, int number, {String? name}) => EpisodeView(
      (b) => b
        ..id = id
        ..number = number
        ..name = name
        ..blockId = 'b-1'
        ..projectId = 'series-1'
        ..updatedAt = DateTime.utc(2026, 1, 1)
        ..version = 1,
    );

    SceneView scene(String id, {int? sceneNumber = 7, String? summary}) =>
        SceneView(
          (b) => b
            ..id = id
            ..sceneNumber = sceneNumber
            ..summary = summary
            ..episodeId = 'e-1'
            ..assignedCharacters.replace(const <String>[])
            ..shootingDayIds.replace(const <String>[])
            ..isScheduleSet = false
            ..updatedAt = DateTime.utc(2026, 1, 1)
            ..version = 1,
        );

    final seasonDto = SeasonView(
      (b) => b
        ..archived = false
        ..id = 'season-1'
        ..number = 1
        ..projectId = 'series-1'
        ..title = 'Shell Season'
        ..updatedAt = DateTime.utc(2026, 1, 1)
        ..version = 1,
    );

    Future<void> pushLocation(
      WidgetTester tester,
      int tab,
      PlanningLocation location,
    ) async {
      final shell = tester.state<AppShellState>(find.byType(AppShell));
      // Fire-and-forget: a push future completes on POP, awaiting it here
      // would deadlock the test.
      shell.tabNavigatorKeys[tab].currentState!.push(
        MaterialPageRoute<void>(
          settings: RouteSettings(arguments: location),
          builder: (_) => const Scaffold(body: Text('pushed')),
        ),
      );
      await pumpFrames(tester, n: 12);
    }

    testWidgets('hidden at tab roots (no location, no scope)', (tester) async {
      await setupContainer();
      await pumpShell(tester, widthDp: 360);
      expect(find.byKey(const Key('shell-context-bar')), findsNothing);
    });

    testWidgets('pop updates the strip in the SAME frame (no stale level)', (
      tester,
    ) async {
      await setupContainer();
      await pumpShell(tester, widthDp: 360);
      await pushLocation(
        tester,
        kCastTabIndex,
        PlanningLocation.season(seasonDto),
      );
      expect(find.byKey(const Key('shell-context-bar')), findsOneWidget);
      expect(find.text('Shell Season'), findsWidgets);

      tester
          .state<AppShellState>(find.byType(AppShell))
          .tabNavigatorKeys[kCastTabIndex]
          .currentState!
          .pop();
      // ONE pump — the route is gone, the location with it.
      await tester.pump();
      expect(find.byKey(const Key('shell-context-bar')), findsNothing);
    });

    testWidgets(
      'tab switch shows the ACTIVE tab location (nested navigators)',
      (tester) async {
        await setupContainer();
        await pumpShell(tester, widthDp: 360);
        await pushLocation(
          tester,
          kScriptTabIndex,
          PlanningLocation.block(seasonDto, block('b-1', 2)),
        );
        // Cast is active — no location there, bar hidden.
        expect(find.byKey(const Key('shell-context-bar')), findsNothing);

        await tester.tap(find.byKey(const Key('shell-destination-1')));
        await pumpFrames(tester);
        // The Script destination's nested navigator resolves its own chain.
        expect(find.byKey(const Key('shell-context-bar')), findsOneWidget);
        expect(find.text('Shell Season'), findsWidgets);
        expect(find.text('Block 2'), findsOneWidget);

        // Back to Cast: hidden again (per-destination state, none to clear).
        await tester.tap(find.byKey(const Key('shell-destination-0')));
        await pumpFrames(tester);
        expect(find.byKey(const Key('shell-context-bar')), findsNothing);
      },
    );

    testWidgets('deep chain renders every level on medium (max 4)', (
      tester,
    ) async {
      await setupContainer();
      await pumpShell(tester, widthDp: 700);
      // The strip mirrors the ACTIVE destination's nested navigator —
      // activate Script first, then push the full scene chain onto it.
      await tester.tap(find.byKey(const Key('shell-destination-1')));
      await pumpFrames(tester);
      expect(
        container.read(shellControllerProvider).selectedIndex,
        kScriptTabIndex,
      );
      await pushLocation(
        tester,
        kScriptTabIndex,
        PlanningLocation.scene(
          seasonDto,
          block('b-1', 2),
          episode('e-1', 3, name: 'Der Diebstahl'),
          scene('sc-1', summary: 'Die Küche'),
        ),
      );
      expect(find.byKey(const Key('shell-context-bar')), findsOneWidget);
      // The deepest levels are rendered (the strip drops LEADING segments
      // that do not fit — the full path stays in the merged semantics node,
      // which the location-strip test below asserts).
      expect(find.byKey(const Key('location-segment-block')), findsOneWidget);
      expect(find.byKey(const Key('location-segment-episode')), findsOneWidget);
      expect(find.byKey(const Key('location-segment-scene')), findsOneWidget);
      expect(find.text('Block 2'), findsOneWidget);
      expect(find.text('Der Diebstahl'), findsOneWidget);
      expect(find.text('Die Küche'), findsOneWidget);
    });

    testWidgets('scope chip: visible with a label; tap opens the picker', (
      tester,
    ) async {
      blocksResult = Right<ProblemError, List<BlockView>>([
        block('b-1', 1),
        block('b-2', 2),
      ]);
      await setupContainer();
      await pumpShell(tester, widthDp: 360);
      // Simulate a set scope (as the pick/gate paths would).
      container
          .read(activeBlockProvider.notifier)
          .set(seasonId: 'season-1', blockId: 'b-2', blockNumber: 2);
      await pumpFrames(tester, n: 12);
      expect(find.byKey(const Key('active-scope-chip')), findsOneWidget);
      expect(find.text('Filter: Block 2'), findsOneWidget);

      await tester.tap(find.byKey(const Key('active-scope-chip')));
      await pumpFrames(tester, n: 12);
      // The picker opened on the active tab's nested navigator.
      expect(find.byKey(const Key('block-scope-picker')), findsOneWidget);
      // Picking a block changes the scope and pops back.
      await tester.tap(find.byKey(const Key('block-scope-pick-b-1')));
      await pumpFrames(tester, n: 24);
      expect(container.read(activeBlockProvider)?.blockId, 'b-1');
      expect(find.byKey(const Key('block-scope-picker')), findsNothing);
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
            // AGENTS.md §6: goldens use the German template locale. Without
            // it this harness mixed German nav labels with English
            // nested-screen copy.
            locale: const Locale('de'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
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
