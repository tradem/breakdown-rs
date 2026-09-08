// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark (pi)

import 'dart:convert';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/serializer.dart';
import 'package:drift/drift.dart';

import 'cache_database.dart';
import 'cache_ttl.dart';
import 'clock.dart';
import 'scene_shoot_cache.dart';

/// Encodes a built list to JSON-serializable wire data (same contract as the
/// costume DAO: preserves whatever form `serializeWith` returns, both forms
/// survive `jsonEncode`).
List<Object?> _encodeBuiltList<T>(
  BuiltList<T> items,
  Serializer<T> serializer,
) => [for (final e in items) serializers.serializeWith(serializer, e)!];

BuiltList<T> _decodeBuiltList<T>(String json, Serializer<T> serializer) {
  final decoded = jsonDecode(json);
  if (decoded is! List) return BuiltList<T>();
  return BuiltList<T>([
    for (final raw in decoded) serializers.deserializeWith(serializer, raw)!,
  ]);
}

/// Data-access object for [SceneShootCacheRows].
///
/// Same discipline as [CostumeCacheDao]: snapshot writes go through
/// [CacheDatabase.transaction] (upsert-all + delete-missing-ids in one txn)
/// scoped to one shooting day, rows map to/from the generated
/// `SceneShootView` DTO, the server `updatedAt` is preserved unchanged while
/// `cachedAt` records the client-only write time, and TTL is computed from
/// `cachedAt` only. Reads reproduce the server
/// `ORDER BY COALESCE(actual_order, planned_order) ASC` sequence via the
/// persisted [SceneShootCacheRows.snapshotIndex] — the client never re-sorts.
class SceneShootCacheDao {
  const SceneShootCacheDao(this._db);

  final CacheDatabase _db;

  SceneShootCacheRowsCompanion _companion(
    SceneShootView view,
    DateTime cachedAt,
    int snapshotIndex,
  ) => SceneShootCacheRowsCompanion.insert(
    id: view.id,
    shootingDayId: view.shootingDayId,
    sceneId: view.sceneId,
    plannedOrder: view.plannedOrder,
    actualOrder: Value(view.actualOrder),
    status:
        serializers.serializeWith(SceneShootStatus.serializer, view.status)!
            as String,
    startDt: Value(view.startDt),
    endDt: Value(view.endDt),
    notesJson: jsonEncode(
      _encodeBuiltList(view.notes, SerializedNote.serializer),
    ),
    continuityPhotoIdsJson: jsonEncode(view.continuityPhotoIds.toList()),
    updatedAt: view.updatedAt,
    version: view.version,
    cachedAt: cachedAt,
    snapshotIndex: snapshotIndex,
  );

  SceneShootView _toView(SceneShootCacheRow row) => SceneShootView((b) {
    final status = serializers.deserializeWith(
      SceneShootStatus.serializer,
      row.status,
    )!;
    final photoIds = (jsonDecode(row.continuityPhotoIdsJson) as List)
        .map((e) => e as String)
        .toList();
    b
      ..id = row.id
      ..shootingDayId = row.shootingDayId
      ..sceneId = row.sceneId
      ..plannedOrder = row.plannedOrder
      ..actualOrder = row.actualOrder
      ..status = status
      ..startDt = row.startDt?.toUtc()
      ..endDt = row.endDt?.toUtc()
      ..notes.replace(
        _decodeBuiltList(row.notesJson, SerializedNote.serializer),
      )
      ..continuityPhotoIds.replace(BuiltList<String>(photoIds))
      ..updatedAt = row.updatedAt.toUtc()
      ..version = row.version;
  });

  /// Single-row upsert preserving the existing snapshot ordinal (a
  /// refetched row keeps its board position; brand-new rows append after
  /// the current day maximum so they never jump ahead of the snapshot
  /// order).
  Future<void> upsert(SceneShootView view, DateTime cachedAt) async {
    final existing =
        await (_db.select(_db.sceneShootCacheRows)..where(
              (t) =>
                  t.id.equals(view.id) &
                  t.shootingDayId.equals(view.shootingDayId),
            ))
            .getSingleOrNull();
    var index = existing?.snapshotIndex;
    index ??= await _dayMaxIndex(view.shootingDayId);
    await _db
        .into(_db.sceneShootCacheRows)
        .insertOnConflictUpdate(_companion(view, cachedAt, (index ?? -1) + 1));
  }

  Future<int?> _dayMaxIndex(String dayId) async {
    final row =
        await (_db.select(_db.sceneShootCacheRows)
              ..where((t) => t.shootingDayId.equals(dayId))
              ..orderBy([(t) => OrderingTerm.desc(t.snapshotIndex)])
              ..limit(1))
            .getSingleOrNull();
    return row?.snapshotIndex;
  }

  /// Snapshot-replace scoped to one shooting day: upserts every [views] row
  /// by id and deletes cached rows of [dayId] absent from [views], in ONE
  /// transaction. Rows of other days are never touched.
  Future<void> applySnapshotForDay(
    String dayId,
    List<SceneShootView> views,
    DateTime cachedAt,
  ) {
    return _db.transaction(() async {
      final ids = views.map((v) => v.id).toSet();
      for (var i = 0; i < views.length; i++) {
        await _db
            .into(_db.sceneShootCacheRows)
            .insertOnConflictUpdate(_companion(views[i], cachedAt, i));
      }
      if (ids.isEmpty) {
        await (_db.delete(
          _db.sceneShootCacheRows,
        )..where((t) => t.shootingDayId.equals(dayId))).go();
      } else {
        await (_db.delete(_db.sceneShootCacheRows)
              ..where((t) => t.shootingDayId.equals(dayId) & t.id.isNotIn(ids)))
            .go();
      }
    });
  }

  /// Reads the day's shoots in snapshot order (`snapshotIndex` ASC
  /// reproduces the server `COALESCE(actual_order, planned_order)` sequence
  /// exactly, including order-key ties that no column ordering could
  /// separate).
  Future<List<SceneShootView>> readByDayOrdered(String dayId) async {
    final rows =
        await (_db.select(_db.sceneShootCacheRows)
              ..where((t) => t.shootingDayId.equals(dayId))
              ..orderBy([(t) => OrderingTerm.asc(t.snapshotIndex)]))
            .get();
    return rows.map(_toView).toList();
  }

  Future<SceneShootView?> readById(String dayId, String id) async {
    final row =
        await (_db.select(_db.sceneShootCacheRows)
              ..where((t) => t.id.equals(id) & t.shootingDayId.equals(dayId)))
            .getSingleOrNull();
    return row == null ? null : _toView(row);
  }

  Future<bool> isDayExpired(
    String dayId,
    Duration ttl, {
    Clock clock = Clock.system,
  }) async {
    final rows = await (_db.select(
      _db.sceneShootCacheRows,
    )..where((t) => t.shootingDayId.equals(dayId))).get();
    if (rows.isEmpty) return false;
    return rows.any((r) => isRowExpired(r.cachedAt, ttl, clock: clock));
  }

  Future<void> clearDay(String dayId) => (_db.delete(
    _db.sceneShootCacheRows,
  )..where((t) => t.shootingDayId.equals(dayId))).go();
}
