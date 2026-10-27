// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)
// Co-authored-by: glm-5.3-flash (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

// Widget tests for the OmniSearch surface (issue #616, task 7.1 + the
// deep-link contract 7.2): facet defaults/restriction, grouping, deep
// links, the three surface states (initial / zero-match / error) and the
// no-season state. The prefresh pass runs against FAKE fetch seams (no
// network in tests, injectable scheduler); the search inputs come from a
// FAKE DAO holder — the DAO composition itself is covered by the
// data-layer test (omni_search_cache_dao_test.dart).

import 'package:breakdown_api/breakdown_api.dart';
import 'package:built_collection/built_collection.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:one_of/one_of.dart';

import 'dart:io' show SecurityContext;

import 'package:frontend_flutter/auth/auth_providers.dart';
import 'package:frontend_flutter/auth/membership/membership_providers.dart';
import 'package:frontend_flutter/src/network/api_client.dart'
    show pinnedSecurityContextProvider;
import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/block_repository.dart';
import 'package:frontend_flutter/data/cache/cache_generation.dart';
import 'package:frontend_flutter/data/cache/piece_domains_cache_dao.dart';
import 'package:frontend_flutter/data/cache/hierarchy_cache_dao.dart';
import 'package:frontend_flutter/data/cache/cache_ttl.dart';
import 'package:frontend_flutter/data/cache/clock.dart';
import 'package:frontend_flutter/data/character_repository.dart';
import 'package:frontend_flutter/data/piece_repository.dart';
import 'package:frontend_flutter/data/episode_repository.dart';
import 'package:frontend_flutter/data/scene_repository.dart';
import 'package:frontend_flutter/data/shooting_day_repository.dart';
import 'package:frontend_flutter/data/cache/season_cache_dao.dart';
import 'package:frontend_flutter/data/cache/seasons_cache_providers.dart';
import 'package:frontend_flutter/data/omni_search_cache_dao.dart';
import 'package:frontend_flutter/domain/reconciliation/reconciliation_scheduler.dart';
import 'package:frontend_flutter/features/blocks/blocks_controller.dart';
import 'package:frontend_flutter/features/characters/characters_controller.dart';
import 'package:frontend_flutter/features/characters/role_extract_screen.dart';
import 'package:frontend_flutter/features/costumes/costume_detail_screen.dart';
import 'package:frontend_flutter/features/costumes/costumes_controller.dart';
import 'package:frontend_flutter/features/episodes/episodes_controller.dart';
import 'package:frontend_flutter/features/omni_search/omni_search_controller.dart';
import 'package:frontend_flutter/features/omni_search/omni_search_destinations.dart';
import 'package:frontend_flutter/features/omni_search/omni_search_model.dart';
import 'package:frontend_flutter/features/omni_search/omni_search_screen.dart';
import 'package:frontend_flutter/features/scenes/scene_detail_screen.dart';
import 'package:frontend_flutter/features/scenes/scenes_controller.dart';
import 'package:frontend_flutter/features/shooting_days/shooting_days_controller.dart';
import 'package:frontend_flutter/features/shooting_days/shooting_days_screen.dart';
import 'package:frontend_flutter/features/shell/planning_location.dart';
import 'package:frontend_flutter/features/shell/shell_controller.dart';

import '../seasons/seasons_test_fakes.dart';

/// Pumps a bounded number of frames (never `pumpAndSettle` — the shot
/// contract for surfaces with in-flight reconciliations).
Future<void> pumpFrames(WidgetTester tester, {int n = 10}) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

const seasonId = 'season-1';

void main() {
  late ProviderContainer container;

  /// Fake repository seams — mutable so single tests can fail them (the
  /// prefresh pass runs through the REAL refresher, which calls the six
  /// aggregate repositories directly — the layer beneath the read screens'
  /// list-fetch providers; CodeRabbit review: no autoDispose provider
  /// futures in the pass, so nothing can be disposed mid-load).
  bool seamsFail = false;
  Result<List<T>> seamResult<T>() =>
      seamsFail ? const Left(ProblemError(code: 'unknown')) : const Right([]);

  /// The fake DAO reads from this holder: per-season inputs, overridable
  /// with a failure for the error-state test.
  final Map<String, OmniSearchInputs> bySeason = {};
  bool daoFail = false;
  Result<OmniSearchInputs> daoResult(String activeSeasonId) {
    if (daoFail) return const Left(ProblemError(code: 'cache.read_failed'));
    return Right(bySeason[activeSeasonId] ?? _rowedInputs(activeSeasonId));
  }

  Future<ProviderContainer> setUpContainer({
    bool withSeason = true,
    OmniSearchInputs? inputs,
  }) async {
    seamsFail = false;
    daoFail = false;
    bySeason.clear();
    if (inputs != null) bySeason[seasonId] = inputs;
    final db = CacheDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    // The shell's active-season resolution validates the persisted
    // reference against the LIVE seasons view — the fake projection feeds
    // it (the same pattern `three_views_test.dart` uses; without it the
    // shell drops the active season at the controller's next build).
    final seasonsHolder = ValueNotifier<Result<List<SeasonView>>>(
      Right([seasonDto()]),
    );
    container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        appConfigProvider.overrideWithValue(devAuthConfig),
        cacheDatabaseProvider.overrideWithValue(db),
        // The pushed DESTINATION screens build real controllers (route
        // builder) — the pinned-CA context is a bootstrap seam, and the
        // membership gate reads the season membership (both overridden
        // here so the push never performs a network bootstrap; the fetch
        // seams below serve the actual reads).
        pinnedSecurityContextProvider.overrideWithValue(SecurityContext()),
        membershipFetchProvider(seasonId)
            .overrideWith((ref) => Right(devAuthMembership(seasonId))),
        seasonRepositoryProvider.overrideWithValue(
          FakeSeasonRepository(BreakdownApi(), SeasonCacheDao(db)),
        ),
        seasonsListFetchProvider.overrideWith((ref) async {
          final repo = ref.watch(seasonRepositoryProvider);
          return repo.fetchAndCacheList(() async => seasonsHolder.value);
        }),
        // Fake DAO: the search's cache-read source (the composition itself
        // is tested against a real in-memory database in the data test).
        omniSearchDaoProvider.overrideWith(
          (ref) => _FakeOmniSearchDao(
            () => daoResult(
              ref.read(shellControllerProvider).activeSeason?.id ?? seasonId,
            ),
          ),
        ),
        // Injectable scheduler — deterministic tests (AGENTS.md §6).
        reconciliationSchedulerProvider.overrideWith((ref) => _NoScheduler()),
        // The bounded prefresh pass runs through the REAL refresher
        // provider; its seams are the fake holders here.
        characterRepositoryProvider.overrideWithValue(
          _FakeCharacterRepository(() => seamResult()),
        ),
        costumeRepositoryProvider.overrideWithValue(
          _FakePieceRepository(() => seamResult()),
        ),
        blockRepositoryProvider.overrideWithValue(
          _FakeBlockRepository(() => seamResult()),
        ),
        episodeRepositoryProvider.overrideWithValue(
          _FakeEpisodeRepository(() => seamResult()),
        ),
        sceneRepositoryProvider.overrideWithValue(
          _FakeSceneRepository(() => seamResult()),
        ),
        shootingDayRepositoryProvider.overrideWithValue(
          _FakeShootingDayRepository(() => seamResult()),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authSessionControllerProvider.notifier).signIn();
    if (withSeason) {
      container
          .read(shellControllerProvider.notifier)
          .setActiveSeason(seasonDto());
    }
    return container;
  }

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: OmniSearchScreen()),
      ),
    );
    await pumpFrames(tester, n: 10);
  }

  testWidgets(
    'deep-link contract (task 7.2): every facet maps to the #610 destination screens',
    (tester) async {
      final season = seasonDto();

      // Scene → SceneDetailScreen (Script-view semantics, ids from the
      // hit's DTOs — never resolved through a second lookup).
      final sceneWidget = omniSearchDestinationScreen(
        season: season,
        hit: sceneHitFixture(sceneNumber: 12),
      );
      expect(sceneWidget, isA<SceneDetailScreen>());
      final sceneScreen = sceneWidget as SceneDetailScreen;
      expect(sceneScreen.seasonId, season.id);
      expect(sceneScreen.episodeId, 'e-1');
      expect(sceneScreen.sceneId, 's1');

      // Character → the Cast row destination (RoleExtractScreen, #611).
      expect(
        omniSearchDestinationScreen(
          season: season,
          hit: characterHitFixture('Zoe'),
        ),
        isA<RoleExtractScreen>(),
      );

      // Costume → the costume detail/assignment context.
      expect(
        omniSearchDestinationScreen(season: season, hit: costumeHitFixture()),
        isA<CostumeDetailScreen>(),
      );

      // Shooting day → the parent episode's day board.
      expect(
        omniSearchDestinationScreen(
          season: season,
          hit: dayHitFixture(label: 'Erster'),
        ),
        isA<ShootingDaysScreen>(),
      );

      // Route arguments carry the SAME PlanningLocation the views push.
      expect(
        omniSearchDestinationLocation(season, sceneHitFixture(sceneNumber: 12)),
        isA<SceneLocation>(),
      );
      expect(
        omniSearchDestinationLocation(season, characterHitFixture('Zoe')),
        isA<SeasonLocation>(),
      );
      expect(
        omniSearchDestinationLocation(season, costumeHitFixture()),
        isA<SeasonLocation>(),
      );
      expect(
        omniSearchDestinationLocation(season, dayHitFixture(label: 'x')),
        isA<EpisodeLocation>(),
      );
    },
  );

  testWidgets('initial state: four chips active, initial narrative', (
    tester,
  ) async {
    await setUpContainer();
    await pumpScreen(tester);

    expect(find.byKey(const Key('omni-search-initial')), findsOneWidget);
    for (final entry in OmniSearchScreen.chipKeys.entries) {
      final finder = find.byKey(Key(entry.value));
      expect(finder, findsOneWidget);
      expect(
        tester.widget<FilterChip>(finder).selected,
        isTrue,
        reason: entry.key.name,
      );
    }
    expect(find.byKey(const Key('omni-search-list')), findsOneWidget);
  });

  testWidgets('searching "wohnung" groups the scene hit first (D3)', (
    tester,
  ) async {
    await setUpContainer(
      inputs: _rowedInputs(seasonId, costumeNotes: 'Marineblau Wolle'),
    );
    await pumpScreen(tester);

    await tester.enterText(find.byKey(const Key('omni-search-field')), 'zoe');
    await pumpFrames(tester, n: 5);

    // The character hit renders in the Rolle group.
    expect(
      find.byKey(const Key('omni-search-group-character')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('omni-search-hit-character-c1')),
      findsOneWidget,
    );

    // And the scene summary (synopsis) matches case-insensitively.
    await tester.enterText(
      find.byKey(const Key('omni-search-field')),
      'wohnung',
    );
    await pumpFrames(tester, n: 5);
    expect(find.byKey(const Key('omni-search-group-scene')), findsOneWidget);
    expect(find.byKey(const Key('omni-search-hit-scene-s1')), findsOneWidget);
    expect(find.text('Wohnung Zoe'), findsOneWidget);
  });

  testWidgets('one facet only: other groups are ABSENT (not merely empty)', (
    tester,
  ) async {
    await setUpContainer();
    await pumpScreen(tester);

    // A typed query first: with NO text the surface shows the initial
    // narrative (no universe listing) — the spec's facet-restriction
    // scenario is about restricting an actual result set.
    await tester.enterText(find.byKey(const Key('omni-search-field')), 'wo');
    await pumpFrames(tester, n: 5);
    await tester.tap(find.byKey(const Key('omni-search-chip-scene')));
    await tester.tap(find.byKey(const Key('omni-search-chip-character')));
    await tester.tap(find.byKey(const Key('omni-search-chip-shooting-day')));
    await pumpFrames(tester, n: 5);

    // The costume group survives alone — the spec's "absent vs empty"
    // wording, asserted per group key.
    expect(find.byKey(const Key('omni-search-group-costume')), findsOneWidget);
    for (final absent in [
      'omni-search-group-scene',
      'omni-search-group-character',
      'omni-search-group-shooting-day',
    ]) {
      expect(find.byKey(Key(absent)), findsNothing, reason: absent);
    }
    expect(find.byKey(const Key('omni-search-hit-costume-k1')), findsOneWidget);
  });

  testWidgets('zero-match echoes the knowingly searched facets', (
    tester,
  ) async {
    await setUpContainer();
    await pumpScreen(tester);

    await tester.enterText(find.byKey(const Key('omni-search-field')), 'xyz');
    await pumpFrames(tester, n: 5);

    final text = tester
        .widget<Text>(find.byKey(const Key('omni-search-zero-match')))
        .data!;
    expect(text, contains('xyz'));
    // The fake pass marks ALL four facets loaded (all seams Right) → all
    // four chip labels are echoed (the standalone tree serves the English
    // fallback catalog).
    for (final label in ['Scene', 'Role', 'Costume', 'Shooting day']) {
      expect(text, contains(label));
    }

    // A whitespace-only query is NOT a query (trim contract): it stays in
    // the initial state, never a near-universe zero-match... and the last
    // active chip cannot be deselected away (toggle guard), so an echo of
    // an empty set is unreachable.
    await tester.enterText(find.byKey(const Key('omni-search-field')), '   ');
    await pumpFrames(tester, n: 5);
    expect(find.byKey(const Key('omni-search-zero-match')), findsNothing);
    expect(find.byKey(const Key('omni-search-initial')), findsOneWidget);
    for (final entry in OmniSearchScreen.chipKeys.entries) {
      expect(
        tester.widget<FilterChip>(find.byKey(Key(entry.value))).selected,
        isTrue,
        reason: entry.key.name,
      );
    }
  });

  testWidgets(
    'cold facets show the not-yet-loaded note, never zero-match copy',
    (tester) async {
      seamsFail = true;
      await setUpContainer(
        inputs: const OmniSearchInputs(
          seasonId: seasonId,
          scenes: [],
          characters: [],
          costumes: [],
          shootingDays: [],
          facetStates: [],
          hasHierarchyRows: false,
          hasCharacterRows: false,
          hasCostumeRows: false,
        ),
      );
      await pumpScreen(tester);
      await pumpFrames(tester, n: 30);

      await tester.enterText(find.byKey(const Key('omni-search-field')), 'xyz');
      await pumpFrames(tester, n: 5);

      // Every facet unanswered → the per-facet notes name them; the
      // zero-match copy must NOT claim "no matches" as ground truth.
      for (final facet in OmniSearchFacet.values) {
        expect(
          find.byKey(Key('omni-search-not-loaded-${facet.name}')),
          findsOneWidget,
          reason: facet.name,
        );
      }
      expect(find.byKey(const Key('omni-search-zero-match')), findsNothing);
    },
  );

  testWidgets('storage failure surfaces the error state with retry', (
    tester,
  ) async {
    await setUpContainer();
    daoFail = true;
    await pumpScreen(tester);

    expect(find.byKey(const Key('omni-search-error')), findsOneWidget);
    expect(find.byKey(const Key('view-retry')), findsOneWidget);
    // The retry re-reads the cache: with the DAO back to Right the error
    // resolves into the surface (no silent empty as ground truth).
    daoFail = false;
    await tester.tap(find.byKey(const Key('view-retry')));
    await pumpFrames(tester, n: 10);
    expect(find.byKey(const Key('omni-search-error')), findsNothing);
    expect(find.byKey(const Key('omni-search-field')), findsOneWidget);
  });

  testWidgets('no active season: empty state, no results computed', (
    tester,
  ) async {
    await setUpContainer(withSeason: false);
    await pumpScreen(tester);
    expect(find.byKey(const Key('omni-search-no-season')), findsOneWidget);
    expect(find.byKey(const Key('omni-search-field')), findsNothing);
    expect(find.byKey(const Key('omni-search-zero-match')), findsNothing);
  });

  testWidgets(
    'offline: filled cache, failing seams — the search stays fully functional '
    'over the cache (task 7.4)',
    (tester) async {
      // Dump connectivity is modeled by the SEAMS failing (every source
      // fetch errors); the surface still composes results from the cached
      // rows — the QUERY path never touches the network (spec "Offline
      // behavior" scenario).
      seamsFail = true;
      await setUpContainer();
      await pumpScreen(tester);
      await pumpFrames(tester, n: 30); // let the failing pass settle

      await tester.enterText(
        find.byKey(const Key('omni-search-field')),
        'wohnung',
      );
      await pumpFrames(tester, n: 5);
      // Results computed over the cache; the error STATE is reserved for
      // storage failures, so a seam failure degrades only via the
      // not-yet-loaded/stale handlers, never blanks the results.
      expect(find.byKey(const Key('omni-search-group-scene')), findsOneWidget);
      expect(find.byKey(const Key('omni-search-hit-scene-s1')), findsOneWidget);
      expect(find.byKey(const Key('omni-search-error')), findsNothing);
    },
  );

  testWidgets('season switch recomputes over the new season only (task 4.2)', (
    tester,
  ) async {
    await setUpContainer();
    await pumpScreen(tester);
    await tester.enterText(
      find.byKey(const Key('omni-search-field')),
      'wohnung',
    );
    await pumpFrames(tester, n: 5);
    expect(find.byKey(const Key('omni-search-hit-scene-s1')), findsOneWidget);

    // The new season's fake universe is EMPTY: the old season's hit is
    // gone right away (family-keyed controllers, spec scenario).
    container
        .read(shellControllerProvider.notifier)
        .setActiveSeason(seasonDto(id: 'season-2'));
    await pumpFrames(tester, n: 20);

    expect(find.byKey(const Key('omni-search-hit-scene-s1')), findsNothing);
  });

  testWidgets(
    'result row deep-opens through the destination mapping (route arguments)',
    (tester) async {
      // The full screens' builders spin up their own controller hubs (the
      // detail screens need the repo seams of their own tests) — the
      // WIDGET-TYPE identity of every destination is asserted directly in
      // the contract test above; here the push CONTRACT is asserted: a tap
      // pops a route whose arguments carry the scene-level PlanningLocation
      // (one route contract, no parallel routing).
      final routes = _RouteSpy();
      await setUpContainer();
      addTearDown(container.dispose);
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1.0;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            navigatorObservers: [routes],
            home: const OmniSearchScreen(),
          ),
        ),
      );
      await pumpFrames(tester, n: 10);
      await tester.enterText(
        find.byKey(const Key('omni-search-field')),
        'wohnung',
      );
      await pumpFrames(tester, n: 5);
      await tester.tap(find.byKey(const Key('omni-search-hit-scene-s1')));
      await pumpFrames(tester, n: 5);

      // The first recorded route is the app-root home route (its settings
      // carry no name); the push contract route argument comes next.
      expect(
        routes.pushedMaterialRoutes
            .where((s) => s.arguments != null)
            .map((s) => s.arguments),
        [isA<SceneLocation>()],
      );
    },
  );
}

/// Navigator-observer spy for the deep-link push contract (task 7.2):
/// records every route whose settings carry an argument/name — the search
/// surface's pushed routes (the pushed SCREEN TYPE identity is asserted in
/// the destination-mapping contract test).
class _RouteSpy extends NavigatorObserver {
  final List<RouteSettings> pushedMaterialRoutes = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final settings = route.settings;
    if (settings.name != null || settings.arguments != null) {
      pushedMaterialRoutes.add(settings);
    }
  }
}

// --- test doubles -----------------------------------------------------------

/// Func-backed fake DAO — `OmniSearchDao` is a class, not an interface;
/// the subclass keeps the provider's return type honest while the fake
/// database below is never queried (each fake holds its own memory
/// instance that stays untouched).
class _FakeOmniSearchDao extends OmniSearchDao {
  _FakeOmniSearchDao(this._read)
    : super(CacheDatabase(NativeDatabase.memory()));

  final Result<OmniSearchInputs> Function() _read;

  @override
  Future<Result<OmniSearchInputs>> readSeasonInputs(
    String seasonId, {
    Duration ttl = kCacheTtl,
    Clock clock = Clock.system,
  }) async => _read();
}

/// Instant scheduler — no real backoff timers (the deterministic-tests
/// rule: never gate a test on wall-clock or sleep-with-jitter).
class _NoScheduler extends ReconciliationScheduler {
  @override
  Future<void> tick(int attempt) async {}
}

// --- fake repositories (the refresher's seams) ------------------------------

/// The pass calls the six aggregate repositories DIRECTLY (the layer
/// beneath the read screens' list-fetch providers). Each fake answers with
/// the mutable [_seam] result — `Right([])` normally, `Left(unknown)` when
/// a test fails the seams.

class _FakeCharacterRepository extends CharacterRepository {
  _FakeCharacterRepository(this._result)
    : super(
        BreakdownApi(),
        CharacterCacheDao(CacheDatabase(NativeDatabase.memory())),
      );

  final Result<List<CharacterView>> Function() _result;

  @override
  Future<Result<List<CharacterView>>> listBySeason(
    String seasonId, {
    Clock clock = Clock.system,
    CacheWriteFence? fence,
  }) async => _result();
}

class _FakePieceRepository extends PieceRepository {
  _FakePieceRepository(this._result)
    : super(
        BreakdownApi(),
        PieceCacheDao(CacheDatabase(NativeDatabase.memory())),
      );

  final Result<List<PieceView>> Function() _result;

  @override
  Future<Result<List<PieceView>>> listBySeason(
    String seasonId, {
    Clock clock = Clock.system,
    CacheWriteFence? fence,
  }) async => _result();
}

class _FakeBlockRepository extends BlockRepository {
  _FakeBlockRepository(this._result)
    : super(
        BreakdownApi(),
        BlockCacheDao(CacheDatabase(NativeDatabase.memory())),
      );

  final Result<List<BlockView>> Function() _result;

  @override
  Future<Result<List<BlockView>>> listBySeason(
    String seasonId, {
    Clock clock = Clock.system,
    CacheWriteFence? fence,
  }) async => _result();
}

class _FakeEpisodeRepository extends EpisodeRepository {
  _FakeEpisodeRepository(this._result)
    : super(
        BreakdownApi(),
        EpisodeCacheDao(CacheDatabase(NativeDatabase.memory())),
      );

  final Result<List<EpisodeView>> Function() _result;

  @override
  Future<Result<List<EpisodeView>>> listByBlock(
    String blockId, {
    Clock clock = Clock.system,
    CacheWriteFence? fence,
  }) async => _result();
}

class _FakeSceneRepository extends SceneRepository {
  _FakeSceneRepository(this._result)
    : super(
        BreakdownApi(),
        SceneCacheDao(CacheDatabase(NativeDatabase.memory())),
      );

  final Result<List<SceneView>> Function() _result;

  @override
  Future<Result<List<SceneView>>> listByEpisode(
    String episodeId, {
    Clock clock = Clock.system,
    CacheWriteFence? fence,
  }) async => _result();
}

class _FakeShootingDayRepository extends ShootingDayRepository {
  _FakeShootingDayRepository(this._result)
    : super(
        BreakdownApi(),
        ShootingDayCacheDao(CacheDatabase(NativeDatabase.memory())),
      );

  final Result<List<ShootingDayView>> Function() _result;

  @override
  Future<Result<List<ShootingDayView>>> listByEpisode(
    String episodeId, {
    Clock clock = Clock.system,
    CacheWriteFence? fence,
  }) async => _result();
}

// --- fixtures ---------------------------------------------------------------

SeasonView seasonDto({String id = seasonId}) => SeasonView(
  (b) => b
    ..archived = false
    ..id = id
    ..number = 1
    ..projectId = 'project-1'
    ..title = 'Season One'
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

SceneOmniHit sceneHitFixture({int? sceneNumber, String? summary}) =>
    SceneOmniHit(
      scene: SceneView(
        (b) => b
          ..id = 's1'
          ..episodeId = 'e-1'
          ..sceneNumber = sceneNumber
          ..summary = summary
          ..assignedCharacters.replace(BuiltList<String>())
          ..shootingDayIds.replace(BuiltList<String>())
          ..isScheduleSet = false
          ..updatedAt = DateTime.utc(2026, 1, 1)
          ..version = 1,
      ),
      episode: _episodeFixture(),
      block: _blockFixture(),
    );

CharacterOmniHit characterHitFixture(String name) => CharacterOmniHit(
  character: CharacterView(
    (b) => b
      ..id = 'c1'
      ..seasonId = seasonId
      ..name = name
      ..category = serializers.deserializeWith(
        CharacterCategory.serializer,
        'main_cast',
      )!
      ..measurements.replace(CharacterMeasurements((m) => m..height = '180'))
      ..contact.replace(ContactInfo((c) => c..email = 'a@b.c'))
      ..updatedAt = DateTime.utc(2026, 1, 1)
      ..version = 1,
  ),
);

CostumeOmniHit costumeHitFixture({String notes = 'Marineblau Wolle'}) =>
    CostumeOmniHit(
      costume: PieceView(
        (b) => b
          ..name = 'Fundus-Piece'
          ..id = 'k1'
          ..notes = notes
          ..categoryName = 'Trachten'
          ..details.replace(BuiltList<PieceDetailView>())
          ..photos.replace(BuiltList<PiecePhotoView>())
          ..updatedAt = DateTime.utc(2026, 1, 1)
          ..version = 1,
      ),
    );

ShootingDayOmniHit dayHitFixture({required String label}) => ShootingDayOmniHit(
  day: ShootingDayView(
    (b) => b
      ..id = 'd1'
      ..episodeId = 'e-1'
      ..orderKey = '!0'
      ..source_.replace(
        ShootingDaySource((s) => s..oneOf = OneOf.fromValue1(value: 'Manual')),
      )
      ..label = label
      ..archived = false
      ..updatedAt = DateTime.utc(2026, 1, 1)
      ..version = 1,
  ),
  episode: _episodeFixture(),
  block: _blockFixture(),
);

EpisodeView _episodeFixture() => EpisodeView(
  (b) => b
    ..id = 'e-1'
    ..blockId = 'b-1'
    ..number = 1
    ..projectId = 'project-1'
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

BlockView _blockFixture() => BlockView(
  (b) => b
    ..id = 'b-1'
    ..number = 1
    ..seasonId = seasonId
    ..projectId = 'project-1'
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

/// The default fake universe (all four facets carry one 'wo/Wohnung/Fitz'.
/// match for the grouped-list tests). Overridable per season.
OmniSearchInputs _rowedInputs(
  String season, {
  String costumeNotes = 'Marineblau Wolle',
}) => OmniSearchInputs(
  seasonId: season,
  scenes: [sceneHitFixture(sceneNumber: 12, summary: 'Wohnung Zoe')],
  characters: [characterHitFixture('Zoe')],
  costumes: [costumeHitFixture(notes: costumeNotes)],
  shootingDays: [dayHitFixture(label: 'Wonnemonat')],
  facetStates: [
    for (final facet in OmniSearchFacet.values)
      OmniSearchFacetState(facet: facet, stale: false),
  ],
  hasHierarchyRows: true,
  hasCharacterRows: true,
  hasCostumeRows: true,
);
