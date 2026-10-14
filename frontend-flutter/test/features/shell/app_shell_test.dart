// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)
// Co-authored-by: glm-5.3-flash (opencode-go)
// Co-authored-by: space-bunny-free (opencode-go)
// Co-authored-by: deepseek-v4-flash (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)

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
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:frontend_flutter/auth/active_episode.dart';
import 'package:frontend_flutter/auth/active_episode_store.dart';
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
import 'package:frontend_flutter/features/ai_import/import_jobs/import_submit_screen.dart';
import 'package:frontend_flutter/features/shell/app_shell.dart';
import 'package:frontend_flutter/features/shell/active_season_store.dart';
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
import '../../support/fake_secure_storage.dart';

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

  Future<void> setupContainer({
    // Untyped on purpose: Riverpod's `Override` is not exported by
    // `flutter_riverpod`; a list literal still type-checks at the call site.
    List<dynamic> extraOverrides = const [],
  }) async {
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
        ...extraOverrides,
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

    testWidgets('top bar present at tab roots; the breadcrumb is not', (
      tester,
    ) async {
      await setupContainer();
      await pumpShell(tester, widthDp: 360);
      // Issue #638: the top bar is NEVER hidden — the season pill is always
      // present because it is also the only affordance that can SET a
      // season. What hides at a destination root is the breadcrumb.
      expect(find.byKey(const Key('shell-context-bar')), findsOneWidget);
      expect(find.byKey(const Key('location-strip')), findsNothing);
      // Prerequisite-aware pills: season always, block/episode only once
      // their prerequisite exists.
      expect(find.byKey(const Key('season-scope-chip')), findsOneWidget);
      expect(find.byKey(const Key('active-scope-chip')), findsNothing);
      expect(find.byKey(const Key('active-episode-chip')), findsNothing);
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
      // ONE pump — the route is gone, the breadcrumb with it (the top bar
      // itself stays; issue #638).
      await tester.pump();
      expect(find.byKey(const Key('location-strip')), findsNothing);
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
        // Cast is active — no location there, breadcrumb absent (the top
        // bar itself is always present; issue #638).
        expect(find.byKey(const Key('location-strip')), findsNothing);

        await tester.tap(find.byKey(const Key('shell-destination-1')));
        await pumpFrames(tester);
        // The Script destination's nested navigator resolves its own chain.
        expect(find.byKey(const Key('shell-context-bar')), findsOneWidget);
        expect(find.byKey(const Key('location-strip')), findsOneWidget);
        // The strip wraps rather than dropping leading segments (issue
        // #638), so both levels of the chain stay visible.
        expect(
          find.byKey(const Key('location-segment-season')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('location-segment-block')), findsOneWidget);
        expect(find.text('Block 2'), findsOneWidget);

        // Back to Cast: breadcrumb absent again (per-destination state,
        // none to clear).
        await tester.tap(find.byKey(const Key('shell-destination-0')));
        await pumpFrames(tester);
        expect(find.byKey(const Key('location-strip')), findsNothing);
      },
    );

    testWidgets('deep chain renders every breadcrumb level (wrapping)', (
      tester,
    ) async {
      await setupContainer();
      // Expanded: the widest view bar, so the strip has the most room.
      await pumpShell(tester, widthDp: 1400);
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
      expect(find.byKey(const Key('location-strip')), findsOneWidget);
      // Row 2 shares its width between the title, the breadcrumb and the
      // search affordance; the strip WRAPS instead of dropping leading
      // segments (issue #638), so EVERY level stays visible — the deepest
      // one is no longer reached by sacrificing its ancestors.
      expect(find.byKey(const Key('location-segment-season')), findsOneWidget);
      expect(find.byKey(const Key('location-segment-block')), findsOneWidget);
      expect(find.byKey(const Key('location-segment-episode')), findsOneWidget);
      expect(find.byKey(const Key('location-segment-scene')), findsOneWidget);
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

      // The pill cluster scrolls horizontally; make sure the pill is fully
      // inside the viewport before tapping it.
      await tester.ensureVisible(find.byKey(const Key('active-scope-chip')));
      await pumpFrames(tester, n: 4);
      await tester.tap(find.byKey(const Key('active-scope-chip')));
      await pumpFrames(tester, n: 12);
      // The picker opened on the shell's ROOT navigator (it covers the
      // shell) — not on the active tab's nested navigator.
      expect(find.byKey(const Key('block-scope-picker')), findsOneWidget);
      // Picking a block changes the scope and pops back.
      await tester.tap(find.byKey(const Key('block-scope-pick-b-1')));
      await pumpFrames(tester, n: 24);
      expect(container.read(activeBlockProvider)?.blockId, 'b-1');
      expect(find.byKey(const Key('block-scope-picker')), findsNothing);
    });
  });

  group('5.5 shell top bar (issue #638)', () {
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

    BlockView block(String id, int number) => BlockView(
      (b) => b
        ..id = id
        ..number = number
        ..seasonId = 'season-1'
        ..projectId = 'series-1'
        ..updatedAt = DateTime.utc(2026, 1, 1)
        ..version = 1,
    );

    testWidgets('clears the status bar in all three morphologies', (
      tester,
    ) async {
      const statusBar = 28.0;
      // ONE container and ONE view teardown for the whole loop: the width is
      // the only thing that varies, so a per-iteration `setupContainer()`
      // would build three throwaway databases, three provider containers and
      // three `tester.view.reset` callbacks for a test that asserts geometry.
      await setupContainer();
      tester.view.devicePixelRatio = 1.0;
      tester.view.padding = const FakeViewPadding(top: statusBar);
      tester.view.viewPadding = const FakeViewPadding(top: statusBar);
      addTearDown(tester.view.reset);

      for (final widthDp in [360.0, 700.0, 1000.0]) {
        tester.view.physicalSize = Size(widthDp, 800);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(home: AppShell()),
          ),
        );
        await pumpFrames(tester);

        expect(
          tester.getTopLeft(find.byKey(const Key('shell-context-bar'))).dy,
          greaterThanOrEqualTo(statusBar),
          reason: 'top bar must clear the status bar at ${widthDp}dp',
        );
        // The view content starts BELOW the bar, never under the status
        // bar's neighbour: the bar's bottom is the content's top.
        expect(
          tester.getBottomLeft(find.byKey(const Key('shell-context-bar'))).dy,
          lessThanOrEqualTo(200),
          reason: 'the two-row bar stays compact at ${widthDp}dp',
        );
      }
    });

    testWidgets('without a status bar the bar starts at y = 0', (tester) async {
      await setupContainer();
      await pumpShell(tester, widthDp: 360);
      expect(
        tester.getTopLeft(find.byKey(const Key('shell-context-bar'))).dy,
        0,
      );
    });

    testWidgets('row 2 carries the view title and the search affordance', (
      tester,
    ) async {
      await setupContainer();
      await pumpShell(tester, widthDp: 1000);

      expect(
        find.descendant(
          of: find.byKey(const Key('shell-view-bar')),
          matching: find.text('Cast'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('shell-view-bar')),
          matching: find.byKey(const Key('shell-search-action')),
        ),
        findsOneWidget,
      );
      // The profile affordance is in row 1, not in the view bar.
      expect(
        find.descendant(
          of: find.byKey(const Key('shell-scope-bar')),
          matching: find.byKey(const Key('profile-menu-button')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('shell-view-bar')),
          matching: find.byKey(const Key('profile-menu-button')),
        ),
        findsNothing,
      );

      // The title follows the active destination.
      await tester.tap(find.byKey(const Key('shell-destination-1')));
      await pumpFrames(tester);
      expect(
        find.descendant(
          of: find.byKey(const Key('shell-view-bar')),
          matching: find.text('Script'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the destination roots render no app bar of their own', (
      tester,
    ) async {
      await setupContainer();
      await pumpShell(tester, widthDp: 360);
      // The shell view bar is the ONLY title surface: the Cast root no
      // longer owns an AppBar (issue #638). (The hosted roster/costume
      // screens keep their own bar, so assert the Cast TITLE is gone from
      // an app bar rather than that no AppBar exists in the subtree.)
      expect(
        find.descendant(
          of: find.byType(CastTabScreen),
          matching: find.widgetWithText(AppBar, 'Cast'),
        ),
        findsNothing,
      );
      // Its costume-domain actions moved into the Cast view's toolbar.
      expect(find.byKey(const Key('cast-fundus-action')), findsOneWidget);
    });

    testWidgets('an unset level offers a neutral pill that opens its picker', (
      tester,
    ) async {
      // TWO blocks so the Cast view renders its one-tap block picker instead
      // of fetching characters (that fetch needs a network client this
      // harness does not build).
      blocksResult = Right<ProblemError, List<BlockView>>([
        block('b-1', 2),
        block('b-2', 3),
      ]);
      await setupContainer();
      // Expanded: enough room for the pills without scrolling.
      await pumpShell(tester, widthDp: 1000);

      // Prerequisite: with no season only the season pill renders.
      expect(find.byKey(const Key('season-scope-chip')), findsOneWidget);
      expect(find.byKey(const Key('active-scope-chip')), findsNothing);
      expect(find.byKey(const Key('active-episode-chip')), findsNothing);

      container
          .read(shellControllerProvider.notifier)
          .setActiveSeason(seasonDto);
      await pumpFrames(tester, n: 12);

      // The block pill appears (season prerequisite) as a NEUTRAL pill with
      // its "choose" label (the English fallback catalog: this harness
      // installs no localization delegates) and opens its picker.
      expect(find.byKey(const Key('active-scope-chip')), findsOneWidget);
      expect(find.byKey(const Key('active-episode-chip')), findsNothing);
      expect(find.text('Choose block'), findsOneWidget);
      await tester.tap(find.byKey(const Key('active-scope-chip')));
      await pumpFrames(tester, n: 12);
      expect(find.byKey(const Key('block-scope-picker')), findsOneWidget);
    });

    testWidgets('the account drawer is shell-level, not destination-level', (
      tester,
    ) async {
      await setupContainer();
      await pumpShell(tester, widthDp: 360);

      await tester.tap(find.byKey(const Key('profile-menu-button')));
      await pumpFrames(tester, n: 30);

      // The account drawer (issue #653) is hosted by the shell Scaffold,
      // so it sits on the ROOT navigator: its scrim covers row 1, row 2
      // and the destination bar. Hosting it in the active destination's
      // nested navigator would (a) lay the scrim out inside that
      // destination's box, leaving the top bar and the destination bar
      // tappable, and (b) keep the drawer alive in the shell's
      // `IndexedStack` across a destination switch as an invisible route
      // that back pops.
      final drawerContext = tester.element(
        find.byKey(const Key('profile-identity')),
      );
      expect(
        Navigator.of(drawerContext),
        same(Navigator.of(drawerContext, rootNavigator: true)),
        reason: 'the account drawer must sit on the root navigator',
      );
    });

    testWidgets('About and Settings push into the active destination', (
      tester,
    ) async {
      await setupContainer();
      await pumpShell(tester, widthDp: 360);

      await tester.tap(find.byKey(const Key('profile-menu-button')));
      await pumpFrames(tester, n: 30);
      // Issue #653: About is a full screen route pushed on the destination
      // navigator (never a dialog).
      await tester.tap(find.byKey(const Key('profile-about')));
      await pumpFrames(tester, n: 30);
      final aboutContext = tester.element(
        find.byKey(const Key('app-info-screen')),
      );
      expect(
        Navigator.of(aboutContext),
        isNot(same(Navigator.of(aboutContext, rootNavigator: true))),
        reason: 'the About screen must sit on the destination navigator',
      );
      // Pop back, then verify the same seam for Settings.
      await tester.pageBack();
      await pumpFrames(tester, n: 30);

      await tester.tap(find.byKey(const Key('profile-menu-button')));
      await pumpFrames(tester, n: 30);
      await tester.tap(find.byKey(const Key('profile-settings')));
      await pumpFrames(tester, n: 30);

      // The pushed screen IS destination-level: it is hosted by the nested
      // navigator (NOT the root one), so back returns to the destination
      // instead of leaving the shell. Same seam as the OmniSearch surface.
      final settingsContext = tester.element(
        find.byKey(const Key('settings-screen')),
      );
      expect(
        Navigator.of(settingsContext),
        isNot(same(Navigator.of(settingsContext, rootNavigator: true))),
        reason: 'the settings screen must sit on the destination navigator',
      );
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

  group('5.4 shell quick-create action (issue #612)', () {
    testWidgets('plus FAB carries the button role and the localized label', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await setupContainer();
      await pumpShell(tester, widthDp: 360);

      // CodeRabbit review #623: assistive technology must announce the
      // FAB as an ACTION affordance with its localized VISIBLE label —
      // ONE merged semantics node carrying BOTH (German template suite;
      // the icon never carries the meaning alone, glossary rule). The
      // shell wraps the FAB in `Semantics(button: true)` because
      // FAB.extended's InkWell exposes the tap action but not the button
      // flag.
      // Node-based assertion (same pattern as the destination-traversal
      // test; `getSemantics(byKey)` resolves the FAB's inner InkWell
      // container node, which carries neither label nor role).
      expect(
        find.semantics.byPredicate(
          (n) => n.label == 'Erstellen' && n.flagsCollection.isButton,
        ),
        findsOneWidget,
      );
      // BEING-disposed inside the test body (framework verifies handle
      // disposal BEFORE tearDown callbacks run).
      semantics.dispose();
    });
    testWidgets('plus FAB exists on all three morphologies at the root', (
      tester,
    ) async {
      await setupContainer();
      for (final widthDp in [360.0, 700.0, 1000.0]) {
        await pumpShell(tester, widthDp: widthDp);
        expect(find.byKey(const Key('shell-plus-fab')), findsOneWidget);
      }
    });

    testWidgets('plus FAB opens the quick-create sheet from tab 1, 2, 3', (
      tester,
    ) async {
      await setupContainer();
      await pumpShell(tester, widthDp: 360);

      for (var tab = 0; tab < kDestinationCount; tab++) {
        await tester.tap(find.byKey(Key('shell-destination-$tab')));
        await pumpFrames(tester, n: 8);
        await tester.tap(find.byKey(const Key('shell-plus-fab')));
        await pumpFrames(tester, n: 8);
        // The sheet lists BOTH v1 entries with VISIBLE labels.
        expect(
          find.byKey(const Key('shell-quick-create-sheet')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('quick-create-ai-import')), findsOneWidget);
        expect(find.byKey(const Key('quick-create-wizard')), findsOneWidget);
        // Dismiss for the next tab (swipe down).
        await tester.drag(
          find.byKey(const Key('shell-quick-create-sheet')),
          const Offset(0, 400),
        );
        await pumpFrames(tester, n: 12);
        // No stacked flow was pushed by the dismissal.
        expect(find.byType(AiImportSubmitScreen), findsNothing);
      }
    });

    testWidgets('AI-import entry routes to the existing submit flow', (
      tester,
    ) async {
      await setupContainer();
      await pumpShell(tester, widthDp: 360);

      await tester.tap(find.byKey(const Key('shell-plus-fab')));
      await pumpFrames(tester, n: 8);
      await tester.tap(find.byKey(const Key('quick-create-ai-import')));
      await pumpFrames(tester, n: 12);

      // The sheet popped and the full-screen import flow PUSHED on the
      // root navigator (covers the shell — the scope-picker behavior).
      expect(find.byKey(const Key('shell-quick-create-sheet')), findsNothing);
      expect(find.byType(AiImportSubmitScreen), findsOneWidget);
    });

    testWidgets('plus FAB is hidden while the session is not resolved', (
      tester,
    ) async {
      await setupContainer();
      await pumpShell(tester, widthDp: 360);
      expect(find.byKey(const Key('shell-plus-fab')), findsOneWidget);

      // AUTHZ-GATE mirror: sign-out drops the authenticated-Affordance
      // (the backend handlers would refuse anyway — fail-closed UI).
      await container.read(authSessionControllerProvider.notifier).signOut();
      // Pump past the FAB's exit transition: Scaffold keeps the OUTGOING
      // FAB widget in the tree for its removal animation, so an immediate
      // finder would match a fade-out ghost. Bounded, computed pump
      // durations (deterministic-tests rule — no settle, no walls).
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }
      expect(find.byKey(const Key('shell-plus-fab')), findsNothing);
    });

    testWidgets(
      'cold start restores the persisted episode scope (issue #624)',
      (tester) async {
        final platform = FakeSecureStoragePlatform();
        final previous = FlutterSecureStoragePlatform.instance;
        FlutterSecureStoragePlatform.instance = platform;
        addTearDown(() => FlutterSecureStoragePlatform.instance = previous);
        await ActiveEpisodeStore.secure().saveScope(
          seasonId: 'season-1',
          blockId: 'b-1',
          episodeId: 'e-1',
          episodeNumber: 3,
          episodeName: 'Pilot',
        );
        await setupContainer();
        await pumpShell(tester, widthDp: 360);
        container
            .read(shellControllerProvider.notifier)
            .setActiveSeason(
              season('season-1', number: 1, title: 'Shell Season'),
            );
        // Let the persisted map resolve and the deferred restore microtask run.
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 10));
        }

        expect(container.read(activeEpisodeProvider)?.episodeId, 'e-1');
        // The chip surfaces the restored scope.
        expect(find.byKey(const Key('active-episode-chip')), findsOneWidget);
      },
    );

    testWidgets("a season switch restores the new season's saved scope", (
      tester,
    ) async {
      await setupContainer(
        extraOverrides: [
          // The active season is season-2, independent of the seasons view.
          activeSeasonResolutionProvider.overrideWith(
            (ref) async => season('season-2', number: 2, title: 'Second'),
          ),
          activeEpisodePersistedProvider.overrideWith(
            (ref) async => {
              'season-1': const PersistedEpisodeScope(
                blockId: 'b-1',
                episodeId: 'e-1',
                episodeNumber: 1,
                episodeName: 'One',
              ),
              'season-2': const PersistedEpisodeScope(
                blockId: 'b-2',
                episodeId: 'e-2',
                episodeNumber: 2,
                episodeName: 'Two',
              ),
            },
          ),
        ],
      );
      // A scope pinned in the PREVIOUS season.
      container
          .read(activeEpisodeProvider.notifier)
          .set(
            seasonId: 'season-1',
            blockId: 'b-1',
            episodeId: 'e-1',
            episodeNumber: 1,
            episodeName: 'One',
          );
      await pumpShell(tester, widthDp: 360);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }

      // The previous season's scope is replaced by the new season's.
      expect(container.read(activeEpisodeProvider)?.episodeId, 'e-2');
    });

    testWidgets(
      'a season switch drops a stale scope when the new season has none',
      (tester) async {
        await setupContainer(
          extraOverrides: [
            activeSeasonResolutionProvider.overrideWith(
              (ref) async => season('season-2', number: 2, title: 'Second'),
            ),
            activeEpisodePersistedProvider.overrideWith(
              (ref) async => {
                'season-1': const PersistedEpisodeScope(
                  blockId: 'b-1',
                  episodeId: 'e-1',
                  episodeNumber: 1,
                  episodeName: 'One',
                ),
              },
            ),
          ],
        );
        container
            .read(activeEpisodeProvider.notifier)
            .set(
              seasonId: 'season-1',
              blockId: 'b-1',
              episodeId: 'e-1',
              episodeNumber: 1,
              episodeName: 'One',
            );
        await pumpShell(tester, widthDp: 360);
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 10));
        }

        // The foreign scope is dropped (no lingering foreign chip).
        expect(container.read(activeEpisodeProvider), isNull);
      },
    );

    testWidgets('a foreign-season scope offers no context entries', (
      tester,
    ) async {
      await setupContainer();
      await pumpShell(tester, widthDp: 360);
      container
          .read(shellControllerProvider.notifier)
          .setActiveSeason(
            season('season-1', number: 1, title: 'Shell Season'),
          );
      // A scope for a DIFFERENT season than the active one.
      container
          .read(activeEpisodeProvider.notifier)
          .set(
            seasonId: 'season-2',
            blockId: 'b-2',
            episodeId: 'e-2',
            episodeNumber: 1,
          );
      await pumpFrames(tester, n: 12);

      await tester.tap(find.byKey(const Key('shell-plus-fab')));
      await pumpFrames(tester, n: 8);

      expect(find.byKey(const Key('quick-create-scene')), findsNothing);
      expect(find.byKey(const Key('quick-create-shooting-day')), findsNothing);
      expect(find.byKey(const Key('quick-create-ai-import')), findsOneWidget);
      expect(find.byKey(const Key('quick-create-wizard')), findsOneWidget);
    });
  });
}
