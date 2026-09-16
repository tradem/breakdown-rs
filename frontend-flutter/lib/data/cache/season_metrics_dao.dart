// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';

import '../../core/problem_error.dart';
import '../../core/result.dart';
// Layering note: `SeasonMetrics` is the season feature's view-model type
// (task 2.1 fixes its home in seasons_state.dart); the aggregation DAO
// produces exactly that shape, so it imports the feature type rather
// than duplicating a parallel DTO (no import cycle — seasons_state.dart
// imports neither data/ nor this file).
import '../../features/seasons/seasons_state.dart';
import 'cache_database.dart';
import 'cache_ttl.dart';
import 'clock.dart';

/// One season's grouped count from a contributing cache table: how many
/// rows and the OLDEST cache-write time in the group (unix ms).
class _SeasonCount {
  const _SeasonCount(this.count, this.oldestMs);

  final int count;
  final int oldestMs;
}

/// Read-only aggregation DAO for the season-card metadata
/// (`redesign-seasons-home` task 2.2, team decision 4).
///
/// Counts blocks / scenes / costumes per season from the EXISTING cache
/// tables — no new fetch calls, no schema change (no migration rule
/// triggered; the change's target is: none). Writes stay owned by the
/// per-projection DAOs; this class only reads.
///
/// Semantics per `SeasonMetrics` (features/seasons/seasons_state.dart):
/// * a season with no rows in any contributing table has NO map entry —
///   the card omits its metadata line (never fabricated counts);
/// * `cachedAt` is the OLDEST contributing source's cache-write time and
///   `isStale` its TTL verdict per the injectable [clock] — the metadata
///   is only as fresh as its oldest source (conservative staleness: a
///   fresh costume cache never masks an expired hierarchy cache).
class SeasonMetricsDao {
  const SeasonMetricsDao(this._db);

  final CacheDatabase _db;

  /// Aggregates cached counts per season (across ALL seasons present in
  /// the cache — the screen filters to the rows it renders by id).
  Future<Result<Map<String, SeasonMetrics>>> readAll({
    Duration ttl = kCacheTtl,
    Clock clock = Clock.system,
  }) async {
    try {
      final blocks = await _grouped(
        'SELECT season_id AS season_id, COUNT(*) AS c, '
        'MIN(cached_at) AS oldest FROM block_cache_rows '
        'GROUP BY season_id',
        readsFrom: {_db.blockCacheRows},
      );
      // Scenes hang off episodes which hang off blocks — the season scope
      // comes from the join chain (same rows the hierarchy reads serve).
      final scenes = await _grouped(
        'SELECT b.season_id AS season_id, COUNT(*) AS c, '
        'MIN(s.cached_at) AS oldest '
        'FROM scene_cache_rows s '
        'JOIN episode_cache_rows e ON s.episode_id = e.id '
        'JOIN block_cache_rows b ON e.block_id = b.id '
        'GROUP BY b.season_id',
        readsFrom: {
          _db.sceneCacheRows,
          _db.episodeCacheRows,
          _db.blockCacheRows,
        },
      );
      // Costumes are season-scoped (snapshot rows carry `season_id`).
      final costumes = await _grouped(
        'SELECT season_id AS season_id, COUNT(*) AS c, '
        'MIN(cached_at) AS oldest FROM costume_cache_rows '
        'GROUP BY season_id',
        readsFrom: {_db.costumeCacheRows},
      );

      final seasonIds = {...blocks.keys, ...scenes.keys, ...costumes.keys};
      return Right({
        for (final id in seasonIds)
          id: _metricsFor(
            id,
            blocks: blocks[id],
            scenes: scenes[id],
            costumes: costumes[id],
            ttl: ttl,
            clock: clock,
          ),
      });
    } on Object {
      // A cache read failure is a transport-level fault, not a server
      // problem; surfaced as a value (AGENTS.md §5: no throw in data/).
      return const Left(ProblemError(code: 'cache.read_failed'));
    }
  }

  /// Runs one grouped COUNT query and maps its rows to season id → count.
  Future<Map<String, _SeasonCount>> _grouped(
    String sql, {
    required Set<TableInfo> readsFrom,
  }) async {
    final rows = await _db.customSelect(sql, readsFrom: readsFrom).get();
    return {
      for (final row in rows)
        row.read<String>('season_id'): _SeasonCount(
          row.read<int>('c'),
          row.read<int>('oldest'),
        ),
    };
  }

  /// Combines one season's per-source counts into the view-model metrics
  /// (pure, injectable-clock TTL verdict per `SeasonMetrics`' contract).
  SeasonMetrics _metricsFor(
    String seasonId, {
    _SeasonCount? blocks,
    _SeasonCount? scenes,
    _SeasonCount? costumes,
    required Duration ttl,
    required Clock clock,
  }) {
    final sources = [?blocks, ?scenes, ?costumes];
    // At least one source exists by construction (the id came from a
    // contributing table's group).
    final oldestMs = sources
        .map((s) => s.oldestMs)
        .reduce((a, b) => a < b ? a : b);
    final cachedAt = DateTime.fromMillisecondsSinceEpoch(
      oldestMs * 1000,
      isUtc: true,
    );
    return SeasonMetrics(
      blockCount: blocks?.count,
      sceneCount: scenes?.count,
      costumeCount: costumes?.count,
      cachedAt: cachedAt,
      isStale: clock.now().difference(cachedAt) > ttl,
    );
  }
}
