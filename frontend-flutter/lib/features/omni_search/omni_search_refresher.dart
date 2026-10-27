// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)
// Co-authored-by: glm-5.3-flash (neuralwatt)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/cache/cache_generation.dart';
import '../../data/cache/clock.dart';
import '../../domain/reconciliation/reconciliation_scheduler.dart';
import '../blocks/blocks_controller.dart';
import '../characters/characters_controller.dart';
import '../pieces/pieces_controller.dart';
import '../episodes/episodes_controller.dart';
import '../scenes/scenes_controller.dart';
import '../shooting_days/shooting_days_controller.dart';
import 'omni_search_controller.dart';
import 'omni_search_model.dart';
import '../../data/cache/seasons_cache_providers.dart' show clockProvider;

part 'omni_search_refresher.g.dart';

/// How many bounded prefresh passes the search surface runs per user
/// action (tasks §3.4): the first attempt immediately, one retry after the
/// shared backoff seam. The bounded budget is the PASS count — the
/// projection seams INSIDE a pass are the read screens' single-shot
/// list-fetch seams (each writes Drift on success, never on failure), so
/// no retry storm is added on top.
const int kOmniSearchPrefreshAttempts = 2;

/// The bounded source-refresh for the OmniSearch surface (tasks §3.4, spec
/// `flutter-omni-search` "Cached-data honesty").
///
/// On surface open and on user retry the surface runs ONE bounded pass
/// through the ESTABLISHED read seams for the active season — blocks, their
/// episodes, per-episode scenes AND days plus characters and pieces.
/// The seams are the six aggregate REPOSITORIES (the layer beneath the
/// read screens' list-fetch providers — those are thin wrappers over
/// `repo.listBy…` with clock + fence): calling the repositories directly
/// keeps the refresh pass FREE of autoDispose provider-future lifecycle
/// races (CodeRabbit review — a bare `ref.read(provider.future)` holds no
/// listener, so Riverpod may dispose the provider mid-load and complete
/// its pending future with an error; plain repository futures carry no
/// such lifecycle). The cache-write discipline travels with the repos: the
/// same [CacheWriteFence] over the cache generation the fetch providers
/// build, so a base switch / sign-out reset mid-pass discards its writes.
///
/// The QUERY path never goes through here (spec: "No network call SHALL be
/// issued by the search itself"): typing and matching run purely over the
/// cache. The pass exists so a temporarily-behind cache catches up while
/// the user looks at the surface — failures are honest degradation, never
/// the surface's error state (that one is reserved for storage failures,
/// spec "Storage failure" scenario).
///
/// Lifecycle: the refresher is KEEP-ALIVE — a pass started for a season
/// survives a screen close and finishes its cache writes. Single-flight
/// futures are keyed BY SEASON: a pass for season A never satisfies a
/// `prefresh('B')` call, and same-season callers still join exactly one
/// pass. Every ref touch is `mounted`-guarded so a pass stops cleanly once
/// the container is gone — never as an unhandled rejection.
@Riverpod(keepAlive: true)
OmniSearchSourceRefresher omniSearchSourceRefresher(Ref ref) =>
    OmniSearchSourceRefresher(ref);

class OmniSearchSourceRefresher {
  OmniSearchSourceRefresher(this._ref);

  final Ref _ref;

  /// In-flight pass per season (CodeRabbit review: keyed by seasonId — a
  /// season switch must not join the previous season's pass).
  final Map<String, Future<void>> _inFlight = {};

  /// Runs (or joins) the bounded prefresh pass for [seasonId].
  Future<void> prefresh(String seasonId) =>
      _inFlight[seasonId] ??= _run(seasonId);

  /// The cache-write fence the read seams build (same shape as the
  /// list-fetch providers): a generation captured at pass start, valid
  /// only while this refresher's container is alive and the generation is
  /// still current.
  CacheWriteFence _fence() {
    final generation = _ref.read(cacheGenerationProvider);
    return CacheWriteFence(
      generation: generation,
      isCurrentGeneration: (g) =>
          _ref.mounted && _ref.read(cacheGenerationProvider) == g,
    );
  }

  Future<void> _run(String seasonId) async {
    final clock = _ref.read(clockProvider);
    try {
      var loaded = const <OmniSearchFacet>{};
      for (var attempt = 0; attempt < kOmniSearchPrefreshAttempts; attempt++) {
        if (!_ref.mounted) return;
        if (attempt > 0) {
          // Injectable seam — tests stay deterministic (AGENTS.md §6).
          await _ref.read(reconciliationSchedulerProvider).tick(attempt);
          if (!_ref.mounted) return;
        }
        loaded = await _runPass(seasonId, loaded, clock);
        if (!_ref.mounted) return;
        _ref
            .read(omniSearchFacetLoadsProvider(seasonId).notifier)
            .markLoaded(loaded);
        // A pass whose every source answered stops retrying — bounded.
        if (loaded.length == OmniSearchFacet.values.length) break;
      }
    } finally {
      // Bookkeeping only: the entry is removed; the (now complete or
      // abandoned) future VALUE is intentionally dropped — declared, not
      // discarded, so the discard_result rule sees no thrown-away Future.
      final _ = _inFlight.remove(seasonId);
    }
    // Re-read the cache AFTER the pass: the seams wrote snapshots on
    // success, so the search inputs now serve the fresh rows.
    if (_ref.mounted) {
      _ref.invalidate(omniSearchInputsProvider(seasonId));
    }
  }

  /// One pass: season-scoped seams, per-facet success marking. Returns the
  /// facets that answered `Right` (previously-marked facets stay loaded —
  /// a pass that answered never regresses to not-yet-loaded).
  Future<Set<OmniSearchFacet>> _runPass(
    String seasonId,
    Set<OmniSearchFacet> alreadyLoaded,
    Clock clock,
  ) async {
    final loaded = {...alreadyLoaded};
    final fence = _fence();
    final charactersOk = await _guarded(
      () => _ref
          .read(characterRepositoryProvider)
          .listBySeason(seasonId, clock: clock, fence: fence)
          .then((r) => r.isRight()),
    );
    if (!_ref.mounted) return loaded;
    final pieceOk = await _guarded(
      () => _ref
          .read(pieceRepositoryProvider)
          .listBySeason(seasonId, clock: clock, fence: fence)
          .then((r) => r.isRight()),
    );
    if (!_ref.mounted) return loaded;
    final hierarchyOk = await _guarded(
      () => _hierarchyChain(seasonId, clock, fence),
    );
    if (charactersOk) loaded.add(OmniSearchFacet.character);
    if (pieceOk) loaded.add(OmniSearchFacet.piece);
    if (hierarchyOk) {
      loaded
        ..add(OmniSearchFacet.scene)
        ..add(OmniSearchFacet.shootingDay);
    }
    return loaded;
  }

  /// The hierarchy chain: blocks of the season → their episodes → each
  /// episode's scenes AND days. A failing level answers `false` and leaves
  /// the facet NOT loaded (its correctness is unknown, not empty — the
  /// same partial-truth honesty as the season-script composition); the
  /// next pass retries.
  Future<bool> _hierarchyChain(
    String seasonId,
    Clock clock,
    CacheWriteFence fence,
  ) async {
    final blocks = await _ref
        .read(blockRepositoryProvider)
        .listBySeason(seasonId, clock: clock, fence: fence);
    // A failed blocks read is the whole chain unanswered — tried again on
    // the next pass, never silently counted as "loaded, empty".
    if (blocks.isLeft()) return false;

    var allRight = true;
    for (final block in blocks.match((_) => const <BlockView>[], (r) => r)) {
      final episodes = await _ref
          .read(episodeRepositoryProvider)
          .listByBlock(block.id, clock: clock, fence: fence);
      allRight = allRight && episodes.isRight();
      if (episodes.isLeft()) continue;
      for (final episode in episodes.match(
        (_) => const <EpisodeView>[],
        (rows) => rows,
      )) {
        final scenes = await _ref
            .read(sceneRepositoryProvider)
            .listByEpisode(episode.id, clock: clock, fence: fence);
        allRight = allRight && scenes.isRight();
        final days = await _ref
            .read(shootingDayRepositoryProvider)
            .listByEpisode(episode.id, clock: clock, fence: fence);
        allRight = allRight && days.isRight();
      }
    }
    return allRight;
  }

  /// Runs [body]; a ref used after the container died must never escape as
  /// an unhandled rejection — a torn-down pass reports `false` (the honest
  /// "not answered"), never a throw. The Riverpod teardown race past a
  /// mounted check surfaces as `StateError` ("Cannot use … after dispose").
  Future<bool> _guarded(Future<bool> Function() body) async {
    if (!_ref.mounted) return false;
    try {
      return await body();
    } on StateError {
      return false;
    }
  }
}

/// Which facets have delivered a source snapshot (empty-but-successful
/// counts — the server answered, so a future zero-match is zero-match and
/// not the "not yet loaded" note). The refresher writes; the surface reads.
@riverpod
class OmniSearchFacetLoads extends _$OmniSearchFacetLoads {
  @override
  Set<OmniSearchFacet> build(String seasonId) => const <OmniSearchFacet>{};

  void markLoaded(Set<OmniSearchFacet> facets) => state = {...state, ...facets};
}
