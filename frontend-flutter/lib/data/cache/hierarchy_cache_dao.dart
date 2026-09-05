// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'dart:convert';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:drift/drift.dart';

import 'cache_database.dart';
import 'cache_ttl.dart';
import 'clock.dart';
import 'hierarchy_cache.dart';

/// Data-access objects for the hierarchy projection tables
/// ([BlockCacheRows], [EpisodeCacheRows], [SceneCacheRows],
/// [CostumeCategoryCacheRows]).
///
/// Same discipline as [SeasonCacheDao]: all snapshot writes go through
/// [CacheDatabase.transaction] (upsert-all + delete-missing-ids in one txn),
/// rows map to/from the generated `*View` DTOs, the server `updatedAt` is
/// preserved unchanged while `cachedAt` records the client-only write time,
/// and TTL is computed from `cachedAt` only.
class BlockCacheDao {
  const BlockCacheDao(this._db);

  final CacheDatabase _db;

  BlockCacheRowsCompanion _companion(BlockView view, DateTime cachedAt) =>
      BlockCacheRowsCompanion.insert(
        id: view.id,
        number: view.number,
        seasonId: view.seasonId,
        seriesId: view.seriesId,
        startDate: view.startDate,
        endDate: view.endDate,
        updatedAt: view.updatedAt,
        version: view.version,
        cachedAt: cachedAt,
      );

  Future<void> upsert(BlockView view, DateTime cachedAt) => _db
      .into(_db.blockCacheRows)
      .insertOnConflictUpdate(_companion(view, cachedAt));

  /// Snapshot-replace scoped to one season: upserts every [views] row by id
  /// and deletes cached rows of [seasonId] absent from [views], in ONE
  /// transaction. Rows of other seasons are never touched (scoped delete —
  /// a season snapshot must not orphan sibling seasons).
  Future<void> applySnapshotForSeason(
    String seasonId,
    List<BlockView> views,
    DateTime cachedAt,
  ) {
    return _db.transaction(() async {
      final ids = views.map((v) => v.id).toSet();
      for (final view in views) {
        await _db
            .into(_db.blockCacheRows)
            .insertOnConflictUpdate(_companion(view, cachedAt));
      }
      if (ids.isEmpty) {
        await (_db.delete(
          _db.blockCacheRows,
        )..where((t) => t.seasonId.equals(seasonId))).go();
      } else {
        await (_db.delete(
          _db.blockCacheRows,
        )..where((t) => t.seasonId.equals(seasonId) & t.id.isNotIn(ids))).go();
      }
    });
  }

  Future<List<BlockView>> readBySeason(String seasonId) async {
    final rows = await (_db.select(
      _db.blockCacheRows,
    )..where((t) => t.seasonId.equals(seasonId))).get();
    return rows.map(_toBlockView).toList();
  }

  Future<BlockView?> readById(String id) async {
    final row = await (_db.select(
      _db.blockCacheRows,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _toBlockView(row);
  }

  Future<bool> isSeasonExpired(
    String seasonId,
    Duration ttl, {
    Clock clock = Clock.system,
  }) async {
    final rows = await (_db.select(
      _db.blockCacheRows,
    )..where((t) => t.seasonId.equals(seasonId))).get();
    if (rows.isEmpty) return false;
    return rows.any((r) => isRowExpired(r.cachedAt, ttl, clock: clock));
  }

  Future<void> clearSeason(String seasonId) => (_db.delete(
    _db.blockCacheRows,
  )..where((t) => t.seasonId.equals(seasonId))).go();

  BlockView _toBlockView(BlockCacheRow row) => BlockView(
    (b) => b
      ..id = row.id
      ..number = row.number
      ..seasonId = row.seasonId
      ..seriesId = row.seriesId
      ..startDate = row.startDate
      ..endDate = row.endDate
      ..updatedAt = row.updatedAt.toUtc()
      ..version = row.version,
  );
}

class EpisodeCacheDao {
  const EpisodeCacheDao(this._db);

  final CacheDatabase _db;

  EpisodeCacheRowsCompanion _companion(EpisodeView view, DateTime cachedAt) =>
      EpisodeCacheRowsCompanion.insert(
        id: view.id,
        blockId: view.blockId,
        name: Value(view.name),
        number: view.number,
        seriesId: view.seriesId,
        updatedAt: view.updatedAt,
        version: view.version,
        cachedAt: cachedAt,
      );

  Future<void> upsert(EpisodeView view, DateTime cachedAt) => _db
      .into(_db.episodeCacheRows)
      .insertOnConflictUpdate(_companion(view, cachedAt));

  /// Snapshot-replace scoped to one block (`GET /v1/episodes?block_id=…`
  /// is the block-scoped read; sibling blocks are never touched).
  Future<void> applySnapshotForBlock(
    String blockId,
    List<EpisodeView> views,
    DateTime cachedAt,
  ) {
    return _db.transaction(() async {
      final ids = views.map((v) => v.id).toSet();
      for (final view in views) {
        await _db
            .into(_db.episodeCacheRows)
            .insertOnConflictUpdate(_companion(view, cachedAt));
      }
      if (ids.isEmpty) {
        await (_db.delete(
          _db.episodeCacheRows,
        )..where((t) => t.blockId.equals(blockId))).go();
      } else {
        await (_db.delete(
          _db.episodeCacheRows,
        )..where((t) => t.blockId.equals(blockId) & t.id.isNotIn(ids))).go();
      }
    });
  }

  Future<List<EpisodeView>> readByBlock(String blockId) async {
    final rows = await (_db.select(
      _db.episodeCacheRows,
    )..where((t) => t.blockId.equals(blockId))).get();
    return rows.map(_toEpisodeView).toList();
  }

  Future<EpisodeView?> readById(String id) async {
    final row = await (_db.select(
      _db.episodeCacheRows,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _toEpisodeView(row);
  }

  Future<bool> isBlockExpired(
    String blockId,
    Duration ttl, {
    Clock clock = Clock.system,
  }) async {
    final rows = await (_db.select(
      _db.episodeCacheRows,
    )..where((t) => t.blockId.equals(blockId))).get();
    if (rows.isEmpty) return false;
    return rows.any((r) => isRowExpired(r.cachedAt, ttl, clock: clock));
  }

  Future<void> clearBlock(String blockId) => (_db.delete(
    _db.episodeCacheRows,
  )..where((t) => t.blockId.equals(blockId))).go();

  EpisodeView _toEpisodeView(EpisodeCacheRow row) => EpisodeView(
    (b) => b
      ..id = row.id
      ..blockId = row.blockId
      ..name = row.name
      ..number = row.number
      ..seriesId = row.seriesId
      ..updatedAt = row.updatedAt.toUtc()
      ..version = row.version,
  );
}

class SceneCacheDao {
  const SceneCacheDao(this._db);

  final CacheDatabase _db;

  SceneCacheRowsCompanion _companion(SceneView view, DateTime cachedAt) =>
      SceneCacheRowsCompanion.insert(
        id: view.id,
        episodeId: view.episodeId,
        assignedCharacters: jsonEncode(view.assignedCharacters.toList()),
        isScheduleSet: view.isScheduleSet,
        location: Value(view.location),
        mood: Value(view.mood),
        sceneNumber: Value(view.sceneNumber),
        scriptDay: Value(view.scriptDay),
        shootingDayIds: jsonEncode(view.shootingDayIds.toList()),
        summary: Value(view.summary),
        updatedAt: view.updatedAt,
        version: view.version,
        cachedAt: cachedAt,
      );

  Future<void> upsert(SceneView view, DateTime cachedAt) => _db
      .into(_db.sceneCacheRows)
      .insertOnConflictUpdate(_companion(view, cachedAt));

  /// Snapshot-replace scoped to one episode (`GET /v1/scenes?episode_id=…`).
  Future<void> applySnapshotForEpisode(
    String episodeId,
    List<SceneView> views,
    DateTime cachedAt,
  ) {
    return _db.transaction(() async {
      final ids = views.map((v) => v.id).toSet();
      for (final view in views) {
        await _db
            .into(_db.sceneCacheRows)
            .insertOnConflictUpdate(_companion(view, cachedAt));
      }
      if (ids.isEmpty) {
        await (_db.delete(
          _db.sceneCacheRows,
        )..where((t) => t.episodeId.equals(episodeId))).go();
      } else {
        await (_db.delete(_db.sceneCacheRows)
              ..where((t) => t.episodeId.equals(episodeId) & t.id.isNotIn(ids)))
            .go();
      }
    });
  }

  Future<List<SceneView>> readByEpisode(String episodeId) async {
    final rows = await (_db.select(
      _db.sceneCacheRows,
    )..where((t) => t.episodeId.equals(episodeId))).get();
    return rows.map(_toSceneView).toList();
  }

  Future<SceneView?> readById(String id) async {
    final row = await (_db.select(
      _db.sceneCacheRows,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _toSceneView(row);
  }

  Future<bool> isEpisodeExpired(
    String episodeId,
    Duration ttl, {
    Clock clock = Clock.system,
  }) async {
    final rows = await (_db.select(
      _db.sceneCacheRows,
    )..where((t) => t.episodeId.equals(episodeId))).get();
    if (rows.isEmpty) return false;
    return rows.any((r) => isRowExpired(r.cachedAt, ttl, clock: clock));
  }

  Future<void> clearEpisode(String episodeId) => (_db.delete(
    _db.sceneCacheRows,
  )..where((t) => t.episodeId.equals(episodeId))).go();

  SceneView _toSceneView(SceneCacheRow row) => SceneView(
    (b) => b
      ..id = row.id
      ..episodeId = row.episodeId
      ..assignedCharacters.replace(_stringList(row.assignedCharacters))
      ..isScheduleSet = row.isScheduleSet
      ..location = row.location
      ..mood = row.mood
      ..sceneNumber = row.sceneNumber
      ..scriptDay = row.scriptDay
      ..shootingDayIds.replace(_stringList(row.shootingDayIds))
      ..summary = row.summary
      ..updatedAt = row.updatedAt.toUtc()
      ..version = row.version,
  );

  List<String> _stringList(String json) {
    final decoded = jsonDecode(json);
    if (decoded is! List) return const [];
    return decoded.whereType<String>().toList();
  }
}

class CostumeCategoryCacheDao {
  const CostumeCategoryCacheDao(this._db);

  final CacheDatabase _db;

  CostumeCategoryCacheRowsCompanion _companion(
    CostumeCategoryView view,
    DateTime cachedAt,
  ) => CostumeCategoryCacheRowsCompanion.insert(
    id: view.id,
    seasonId: view.seasonId,
    name: view.name,
    orderKey: view.orderKey,
    archived: view.archived,
    updatedAt: view.updatedAt,
    version: view.version,
    cachedAt: cachedAt,
  );

  Future<void> upsert(CostumeCategoryView view, DateTime cachedAt) => _db
      .into(_db.costumeCategoryCacheRows)
      .insertOnConflictUpdate(_companion(view, cachedAt));

  /// Snapshot-replace scoped to one season (server `ORDER BY order_key
  /// ASC`; the snapshot preserves that order by insertion).
  Future<void> applySnapshotForSeason(
    String seasonId,
    List<CostumeCategoryView> views,
    DateTime cachedAt,
  ) {
    return _db.transaction(() async {
      final ids = views.map((v) => v.id).toSet();
      for (final view in views) {
        await _db
            .into(_db.costumeCategoryCacheRows)
            .insertOnConflictUpdate(_companion(view, cachedAt));
      }
      if (ids.isEmpty) {
        await (_db.delete(
          _db.costumeCategoryCacheRows,
        )..where((t) => t.seasonId.equals(seasonId))).go();
      } else {
        await (_db.delete(
          _db.costumeCategoryCacheRows,
        )..where((t) => t.seasonId.equals(seasonId) & t.id.isNotIn(ids))).go();
      }
    });
  }

  /// Reads the season's categories in server order (`order_key ASC`).
  Future<List<CostumeCategoryView>> readBySeasonOrdered(String seasonId) async {
    final rows =
        await (_db.select(_db.costumeCategoryCacheRows)
              ..where((t) => t.seasonId.equals(seasonId))
              ..orderBy([(t) => OrderingTerm.asc(t.orderKey)]))
            .get();
    return rows.map(_toView).toList();
  }

  Future<CostumeCategoryView?> readById(String id) async {
    final row = await (_db.select(
      _db.costumeCategoryCacheRows,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _toView(row);
  }

  Future<bool> isSeasonExpired(
    String seasonId,
    Duration ttl, {
    Clock clock = Clock.system,
  }) async {
    final rows = await (_db.select(
      _db.costumeCategoryCacheRows,
    )..where((t) => t.seasonId.equals(seasonId))).get();
    if (rows.isEmpty) return false;
    return rows.any((r) => isRowExpired(r.cachedAt, ttl, clock: clock));
  }

  Future<void> clearSeason(String seasonId) => (_db.delete(
    _db.costumeCategoryCacheRows,
  )..where((t) => t.seasonId.equals(seasonId))).go();

  CostumeCategoryView _toView(CostumeCategoryCacheRow row) =>
      CostumeCategoryView(
        (b) => b
          ..id = row.id
          ..seasonId = row.seasonId
          ..name = row.name
          ..orderKey = row.orderKey
          ..archived = row.archived
          ..updatedAt = row.updatedAt.toUtc()
          ..version = row.version,
      );
}

/// Drops orphaned subtree rows when a parent snapshot no longer carries them
/// (D5): after a successful parent snapshot, child rows whose parent id is
/// absent from [liveParentIds] are removed. Invoked on the next successful
/// parent snapshot — never on a failed fetch.
Future<void> pruneOrphanedHierarchyRows(
  CacheDatabase db, {
  required Set<String> liveSeasonIds,
  required Set<String> liveBlockIds,
  required Set<String> liveEpisodeIds,
}) => db.transaction(() async {
  if (liveSeasonIds.isNotEmpty) {
    await (db.delete(
      db.blockCacheRows,
    )..where((t) => t.seasonId.isNotIn(liveSeasonIds))).go();
    await (db.delete(
      db.costumeCategoryCacheRows,
    )..where((t) => t.seasonId.isNotIn(liveSeasonIds))).go();
  }
  if (liveBlockIds.isNotEmpty) {
    await (db.delete(
      db.episodeCacheRows,
    )..where((t) => t.blockId.isNotIn(liveBlockIds))).go();
  }
  if (liveEpisodeIds.isNotEmpty) {
    await (db.delete(
      db.sceneCacheRows,
    )..where((t) => t.episodeId.isNotIn(liveEpisodeIds))).go();
  }
});
