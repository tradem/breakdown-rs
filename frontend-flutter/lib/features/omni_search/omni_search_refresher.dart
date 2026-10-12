// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)
// Co-authored-by: glm-5.3-flash (neuralwatt)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/reconciliation/reconciliation_scheduler.dart';
import '../blocks/blocks_controller.dart';
import '../characters/characters_controller.dart';
import '../costumes/costumes_controller.dart';
import '../episodes/episodes_controller.dart';
import '../scenes/scenes_controller.dart';
import '../shooting_days/shooting_days_controller.dart';
import 'omni_search_controller.dart';
import 'omni_search_model.dart';

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
/// episodes, per-episode scenes AND days plus characters and costumes —
/// each via the same providers the read screens consume (which own the
/// Drift cache-write discipline, fence included). After the pass the search
/// inputs provider is invalidated so the surface re-reads the cache.
///
/// The QUERY path never goes through here (spec: "No network call SHALL be
/// issued by the search itself"): typing and matching run purely over the
/// cache. The pass exists so a temporarily-behind cache catches up while
/// the user looks at the surface — failures are honest degradation, never
/// the surface's error state (that one is reserved for storage failures,
/// spec "Storage failure" scenario).
///
/// Single-flight: a concurrent retry joins the in-flight pass (the same
/// rule the ReconciliationCoordinator applies to the read screens).
@riverpod
OmniSearchSourceRefresher omniSearchSourceRefresher(Ref ref) =>
    OmniSearchSourceRefresher(ref);

class OmniSearchSourceRefresher {
  OmniSearchSourceRefresher(this._ref);

  final Ref _ref;
  Future<void>? _inFlight;

  /// Runs (or joins) the bounded prefresh pass for [seasonId]. The
  /// single-flight future is RETURNED (never discarded — breakdown_lints
  /// `discard_result`), so a joining caller awaits the same pass.
  Future<void> prefresh(String seasonId) => _inFlight ??= _run(seasonId);

  Future<void> _run(String seasonId) async {
    try {
      var loaded = const <OmniSearchFacet>{};
      for (var attempt = 0; attempt < kOmniSearchPrefreshAttempts; attempt++) {
        if (attempt > 0) {
          // Injectable seam — tests stay deterministic (AGENTS.md §6).
          await _ref.read(reconciliationSchedulerProvider).tick(attempt);
        }
        loaded = await _runPass(seasonId, loaded);
        if (_ref.mounted) {
          _ref
              .read(omniSearchFacetLoadsProvider(seasonId).notifier)
              .markLoaded(loaded);
        }
        // A pass whose every source answered stops retrying — bounded.
        if (loaded.length == OmniSearchFacet.values.length) break;
      }
    } finally {
      _inFlight = null;
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
  ) async {
    final loaded = {...alreadyLoaded};
    final charactersOk = await _characterSeam(seasonId);
    final costumeOk = await _costumeSeam(seasonId);
    final hierarchyOk = await _hierarchySeam(seasonId);
    if (charactersOk) loaded.add(OmniSearchFacet.character);
    if (costumeOk) loaded.add(OmniSearchFacet.costume);
    if (hierarchyOk) {
      loaded
        ..add(OmniSearchFacet.scene)
        ..add(OmniSearchFacet.shootingDay);
    }
    return loaded;
  }

  Future<bool> _characterSeam(String seasonId) async {
    _ref.invalidate(charactersListFetchProvider(seasonId));
    final res = await _ref.read(charactersListFetchProvider(seasonId).future);
    return res.isRight();
  }

  Future<bool> _costumeSeam(String seasonId) async {
    _ref.invalidate(costumesListFetchProvider(seasonId));
    final res = await _ref.read(costumesListFetchProvider(seasonId).future);
    return res.isRight();
  }

  /// The hierarchy chain: blocks of the season → their episodes → each
  /// episode's scenes AND days. A failing level answers `false` and leaves
  /// the facet NOT loaded (its correctness is unknown, not empty — the
  /// same partial-truth honesty as the season-script composition); the
  /// next pass retries.
  Future<bool> _hierarchySeam(String seasonId) async {
    _ref.invalidate(blocksListFetchProvider(seasonId));
    final blocks = await _ref.read(blocksListFetchProvider(seasonId).future);
    // A failed blocks read is the whole chain unanswered — tried again on
    // the next pass, never silently counted as "loaded, empty".
    final blockRows = blocks.match((_) => const <BlockView>[], (rows) => rows);
    if (blocks.isLeft()) return false;

    var allRight = true;
    for (final block in blockRows) {
      _ref.invalidate(episodesListFetchProvider(block.id, seasonId));
      final episodes = await _ref.read(
        episodesListFetchProvider(block.id, seasonId).future,
      );
      allRight = allRight && episodes.isRight();
      if (episodes.isLeft()) continue;
      final episodeRows = episodes.match(
        (_) => const <EpisodeView>[],
        (rows) => rows,
      );
      for (final episode in episodeRows) {
        _ref.invalidate(scenesListFetchProvider(episode.id));
        final scenes = await _ref.read(
          scenesListFetchProvider(episode.id).future,
        );
        allRight = allRight && scenes.isRight();
        _ref.invalidate(shootingDaysListFetchProvider(episode.id));
        final days = await _ref.read(
          shootingDaysListFetchProvider(episode.id).future,
        );
        allRight = allRight && days.isRight();
      }
    }
    return allRight;
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
