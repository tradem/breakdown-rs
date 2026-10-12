// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)
// Co-authored-by: glm-5.3-flash (neuralwatt)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:fpdart/fpdart.dart';

import '../core/problem_error.dart';
import '../core/result.dart';
import '../features/omni_search/omni_search_model.dart';
import 'cache/cache_database.dart';
import 'cache/cache_ttl.dart';
import 'cache/clock.dart';
import 'cache/costume_domains_cache_dao.dart';
import 'cache/hierarchy_cache_dao.dart';

/// Data-access object for the OmniSearch season composition (issue #616,
/// tasks §2.1/§2.2).
///
/// READ-ONLY composition over the EXISTING projection-cache tables — no
/// schema change (task §2.4 does NOT trigger): the design D2 decision
/// settled for Dart-side filtering because it is the MORE stable AND MORE
/// extensible choice (documented per design D2):
/// - stability: no normalized-column migration path, no Drift schema bump,
///   no §2.4 trigger; the cache schema (the disk format users already
///   carry) stays byte-identical;
/// - extensibility: the folding table and per-facet field pinning live in
///   pure Dart (`name_prefilter.dart` / `omni_search_matcher.dart`),
///   table-testable in Tier 1, so a later SQL-side port or a backend search
///   route can replace the execution WITHOUT touching the field contract.
/// At domain scale (≈ 40 scenes and dozens of characters/costumes/days per
/// season) single-digit-ms Dart filtering is trivially fast (verified in
/// the matcher tests).
///
/// AI-import exclusion (tasks §5.1): the composition NEVER reads the
/// `ai_import_*` tables — AI-import draft/preview data is a PO-confirmed
/// non-goal with a regression test
/// (`test/data/omni_search_cache_dao_test.dart`), guarding future
/// accidental inclusion.
///
/// Errors are values: any storage failure decodes to
/// `ProblemError(code: 'cache.read_failed')` (the season-metrics DAO
/// convention), never a throw.
class OmniSearchDao {
  OmniSearchDao(this._db)
    : _blockDao = BlockCacheDao(_db),
      _sceneDao = SceneCacheDao(_db),
      _shootingDayDao = ShootingDayCacheDao(_db);

  final CacheDatabase _db;
  final BlockCacheDao _blockDao;
  final SceneCacheDao _sceneDao;
  final ShootingDayCacheDao _shootingDayDao;

  /// Assembles the complete cached search universe of ONE active season.
  ///
  /// Season scoping (task §2.3): characters and costumes are read from
  /// their own per-season tables; scenes and shooting days are scoped by
  /// the block-episode join — cross-season rows CANNOT leak because the
  /// join root is `block.season_id` (regression-tested).
  Future<Result<OmniSearchInputs>> readSeasonInputs(
    String seasonId, {
    Duration ttl = kCacheTtl,
    Clock clock = Clock.system,
  }) async {
    try {
      final blockRows = await _blockDao.readBySeason(seasonId);
      final characterFresh = await CharacterCacheDao(_db)
          .readBySeasonFresh(seasonId, ttl: ttl, clock: clock);
      final costumeFresh = await CostumeCacheDao(_db)
          .readBySeasonFresh(seasonId, ttl: ttl, clock: clock);

      final sceneComposed = await _sceneDao.readBySeasonComposed(
        seasonId,
        ttl: ttl,
        clock: clock,
      );
      final dayComposed = await _shootingDayDao.readBySeasonComposed(
        seasonId,
        ttl: ttl,
        clock: clock,
      );

      final inputs = OmniSearchInputs(
        seasonId: seasonId,
        scenes: _sortScenes(sceneComposed.rows),
        characters: [
          for (final c in characterFresh.rows) CharacterOmniHit(character: c),
        ],
        costumes: [
          for (final c in costumeFresh.rows) CostumeOmniHit(costume: c),
        ],
        shootingDays: [
          for (final (day, episode, block) in dayComposed.rows)
            ShootingDayOmniHit(day: day, episode: episode, block: block),
        ],
        facetStates: [
          OmniSearchFacetState(
            facet: OmniSearchFacet.scene,
            stale: sceneComposed.stale,
          ),
          OmniSearchFacetState(
            facet: OmniSearchFacet.character,
            stale: characterFresh.stale,
          ),
          OmniSearchFacetState(
            facet: OmniSearchFacet.costume,
            stale: costumeFresh.stale,
          ),
          OmniSearchFacetState(
            facet: OmniSearchFacet.shootingDay,
            stale: dayComposed.stale,
          ),
        ],
        hasHierarchyRows: blockRows.isNotEmpty,
        hasCharacterRows: characterFresh.rows.isNotEmpty,
        hasCostumeRows: costumeFresh.rows.isNotEmpty,
      );
      return Right(inputs);
    } on Object catch (e) {
      return Left(ProblemError(code: 'cache.read_failed', detail: '$e'));
    }
  }

  /// Scene hit order = the script composition order (D3's scene dominance
  /// and the season-script comparator): scene number ASC with an
  /// unnumbered scene LAST (never jumping the queue), episode number as
  /// the tie-breaker, scene id as the final stable key.
  List<SceneOmniHit> _sortScenes(
    List<(SceneView, EpisodeView, BlockView)> rows,
  ) {
    final hits = [
      for (final (scene, episode, block) in rows)
        SceneOmniHit(scene: scene, episode: episode, block: block),
    ];
    hits.sort((a, b) {
      final an = a.scene.sceneNumber;
      final bn = b.scene.sceneNumber;
      if (an == null && bn == null) {
        return a.episode.number.compareTo(b.episode.number);
      }
      if (an == null) return 1;
      if (bn == null) return -1;
      if (an != bn) return an.compareTo(bn);
      return a.episode.number.compareTo(b.episode.number);
    });
    return hits;
  }
}
