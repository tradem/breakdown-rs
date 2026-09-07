// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'dart:convert';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/serializer.dart';
import 'package:drift/drift.dart';

import 'cache_database.dart';
import 'cache_ttl.dart';
import 'clock.dart';
import 'costume_domains_cache.dart';

/// Serializers shim: the generated `breakdown_api` package exposes the
/// standard `serializers` object for wire (de)serialization of nested
/// projection snapshots (`details`, `photos`, `source`).
///
/// Costume `details`/`photos` ride the costume row as JSON snapshots because
/// there is no detail/photo list route — they refresh with the costume row.

/// Encodes a built list to JSON-serializable wire data.
///
/// The generated `breakdown_api` serializers emit EITHER alternating
/// key/value lists (custom serializers return `.toList()`) OR maps,
/// depending on the model. This helper preserves whatever form
/// `serializeWith` returns (both survive `jsonEncode`), and
/// [_decodeBuiltList] feeds the decoded form straight back to
/// `deserializeWith` — never reinterpreting the shape.
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

// --- Costumes -----------------------------------------------------------------

/// Data-access object for [CostumeCacheRows].
///
/// Same discipline as [SeasonCacheDao]: snapshot writes go through
/// [CacheDatabase.transaction] (upsert-all + delete-missing-ids in one txn),
/// rows map to/from the generated `CostumeView` DTO, the server `updatedAt`
/// is preserved unchanged while `cachedAt` records the client-only write
/// time, and TTL is computed from `cachedAt` only.
class CostumeCacheDao {
  const CostumeCacheDao(this._db);

  final CacheDatabase _db;

  CostumeCacheRowsCompanion _companion(
    String seasonId,
    CostumeView view,
    DateTime cachedAt,
    int snapshotIndex,
  ) => CostumeCacheRowsCompanion.insert(
    id: view.id,
    seasonId: seasonId,
    characterId: Value(view.characterId),
    notes: view.notes,
    detailsJson: jsonEncode(
      _encodeBuiltList(view.details, CostumeDetailView.serializer),
    ),
    photosJson: jsonEncode(
      _encodeBuiltList(view.photos, CostumePhotoView.serializer),
    ),
    updatedAt: view.updatedAt,
    version: view.version,
    cachedAt: cachedAt,
    snapshotIndex: snapshotIndex,
  );

  CostumeView _toView(String seasonId, CostumeCacheRow row) => CostumeView((b) {
    b
      ..id = row.id
      ..characterId = row.characterId
      ..notes = row.notes
      ..details.replace(
        _decodeBuiltList(row.detailsJson, CostumeDetailView.serializer),
      )
      ..photos.replace(
        _decodeBuiltList(row.photosJson, CostumePhotoView.serializer),
      )
      ..updatedAt = row.updatedAt.toUtc()
      ..version = row.version;
    assert(seasonId.isNotEmpty, 'season scope must be non-empty');
  });

  /// Single-row upsert preserving the existing snapshot ordinal (a
  /// refetched row keeps its list position; brand-new rows append after
  /// the current season maximum so they never jump ahead of the snapshot
  /// order).
  Future<void> upsert(
    String seasonId,
    CostumeView view,
    DateTime cachedAt,
  ) async {
    final existing =
        await (_db.select(
              _db.costumeCacheRows,
            )..where((t) => t.id.equals(view.id) & t.seasonId.equals(seasonId)))
            .getSingleOrNull();
    var index = existing?.snapshotIndex;
    index ??= await _seasonMaxIndex(seasonId);
    await _db
        .into(_db.costumeCacheRows)
        .insertOnConflictUpdate(
          _companion(seasonId, view, cachedAt, (index ?? -1) + 1),
        );
  }

  Future<int?> _seasonMaxIndex(String seasonId) async {
    final row =
        await (_db.select(_db.costumeCacheRows)
              ..where((t) => t.seasonId.equals(seasonId))
              ..orderBy([(t) => OrderingTerm.desc(t.snapshotIndex)])
              ..limit(1))
            .getSingleOrNull();
    return row?.snapshotIndex;
  }

  /// Snapshot-replace scoped to one season: upserts every [views] row by id
  /// and deletes cached rows of [seasonId] absent from [views], in ONE
  /// transaction. Rows of other seasons are never touched.
  Future<void> applySnapshotForSeason(
    String seasonId,
    List<CostumeView> views,
    DateTime cachedAt,
  ) {
    return _db.transaction(() async {
      final ids = views.map((v) => v.id).toSet();
      for (var i = 0; i < views.length; i++) {
        await _db
            .into(_db.costumeCacheRows)
            .insertOnConflictUpdate(
              _companion(seasonId, views[i], cachedAt, i),
            );
      }
      if (ids.isEmpty) {
        await (_db.delete(
          _db.costumeCacheRows,
        )..where((t) => t.seasonId.equals(seasonId))).go();
      } else {
        await (_db.delete(
          _db.costumeCacheRows,
        )..where((t) => t.seasonId.equals(seasonId) & t.id.isNotIn(ids))).go();
      }
    });
  }

  /// Reads the season's costumes in snapshot order (`snapshotIndex`
  /// ASC reproduces the server `ORDER BY updated_at DESC` exactly,
  /// including timestamp ties that no column ordering could separate).
  Future<List<CostumeView>> readBySeason(String seasonId) async {
    final rows =
        await (_db.select(_db.costumeCacheRows)
              ..where((t) => t.seasonId.equals(seasonId))
              ..orderBy([(t) => OrderingTerm.asc(t.snapshotIndex)]))
            .get();
    return rows.map((r) => _toView(seasonId, r)).toList();
  }

  Future<CostumeView?> readById(String seasonId, String id) async {
    final row =
        await (_db.select(_db.costumeCacheRows)
              ..where((t) => t.id.equals(id) & t.seasonId.equals(seasonId)))
            .getSingleOrNull();
    return row == null ? null : _toView(seasonId, row);
  }

  Future<bool> isSeasonExpired(
    String seasonId,
    Duration ttl, {
    Clock clock = Clock.system,
  }) async {
    final rows = await (_db.select(
      _db.costumeCacheRows,
    )..where((t) => t.seasonId.equals(seasonId))).get();
    if (rows.isEmpty) return false;
    return rows.any((r) => isRowExpired(r.cachedAt, ttl, clock: clock));
  }

  Future<void> clearSeason(String seasonId) => (_db.delete(
    _db.costumeCacheRows,
  )..where((t) => t.seasonId.equals(seasonId))).go();
}

// --- Characters ---------------------------------------------------------------

/// Data-access object for [CharacterCacheRows] (flattened measurements +
/// contact; category stored as the wire string for strict-parse fidelity).
class CharacterCacheDao {
  const CharacterCacheDao(this._db);

  final CacheDatabase _db;

  CharacterCacheRowsCompanion _companion(
    CharacterView view,
    DateTime cachedAt,
  ) => CharacterCacheRowsCompanion.insert(
    id: view.id,
    seasonId: view.seasonId,
    name: view.name,
    category:
        serializers.serializeWith(CharacterCategory.serializer, view.category)!
            as String,
    height: view.measurements.height,
    weight: view.measurements.weight,
    chest: view.measurements.chest,
    waist: view.measurements.waist,
    hips: view.measurements.hips,
    shoeSize: view.measurements.shoeSize,
    hatSize: view.measurements.hatSize,
    email: Value(view.contact.email),
    phone: Value(view.contact.phone),
    updatedAt: view.updatedAt,
    version: view.version,
    cachedAt: cachedAt,
  );

  CharacterView _toView(CharacterCacheRow row) => CharacterView(
    (b) => b
      ..id = row.id
      ..seasonId = row.seasonId
      ..name = row.name
      ..category = serializers.deserializeWith(
        CharacterCategory.serializer,
        row.category,
      )!
      ..measurements.replace(
        CharacterMeasurements(
          (m) => m
            ..height = row.height
            ..weight = row.weight
            ..chest = row.chest
            ..waist = row.waist
            ..hips = row.hips
            ..shoeSize = row.shoeSize
            ..hatSize = row.hatSize,
        ),
      )
      ..contact.replace(
        ContactInfo(
          (c) => c
            ..email = row.email
            ..phone = row.phone,
        ),
      )
      ..updatedAt = row.updatedAt.toUtc()
      ..version = row.version,
  );

  Future<void> upsert(CharacterView view, DateTime cachedAt) => _db
      .into(_db.characterCacheRows)
      .insertOnConflictUpdate(_companion(view, cachedAt));

  /// Snapshot-replace scoped to one season.
  Future<void> applySnapshotForSeason(
    String seasonId,
    List<CharacterView> views,
    DateTime cachedAt,
  ) {
    return _db.transaction(() async {
      final ids = views.map((v) => v.id).toSet();
      for (final view in views) {
        await _db
            .into(_db.characterCacheRows)
            .insertOnConflictUpdate(_companion(view, cachedAt));
      }
      if (ids.isEmpty) {
        await (_db.delete(
          _db.characterCacheRows,
        )..where((t) => t.seasonId.equals(seasonId))).go();
      } else {
        await (_db.delete(
          _db.characterCacheRows,
        )..where((t) => t.seasonId.equals(seasonId) & t.id.isNotIn(ids))).go();
      }
    });
  }

  Future<List<CharacterView>> readBySeason(String seasonId) async {
    final rows = await (_db.select(
      _db.characterCacheRows,
    )..where((t) => t.seasonId.equals(seasonId))).get();
    return rows.map(_toView).toList();
  }

  Future<CharacterView?> readById(String id) async {
    final row = await (_db.select(
      _db.characterCacheRows,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _toView(row);
  }

  Future<bool> isSeasonExpired(
    String seasonId,
    Duration ttl, {
    Clock clock = Clock.system,
  }) async {
    final rows = await (_db.select(
      _db.characterCacheRows,
    )..where((t) => t.seasonId.equals(seasonId))).get();
    if (rows.isEmpty) return false;
    return rows.any((r) => isRowExpired(r.cachedAt, ttl, clock: clock));
  }

  Future<void> clearSeason(String seasonId) => (_db.delete(
    _db.characterCacheRows,
  )..where((t) => t.seasonId.equals(seasonId))).go();
}

// --- Shooting days ------------------------------------------------------------

/// Data-access object for [ShootingDayCacheRows].
///
/// Server order is `order_key ASC`; reads preserve it via `ORDER BY`.
/// The client never re-sorts (order fidelity, spec
/// flutter-shooting-days-screen).
class ShootingDayCacheDao {
  const ShootingDayCacheDao(this._db);

  final CacheDatabase _db;

  ShootingDayCacheRowsCompanion _companion(
    ShootingDayView view,
    DateTime cachedAt,
  ) => ShootingDayCacheRowsCompanion.insert(
    id: view.id,
    episodeId: view.episodeId,
    orderKey: view.orderKey,
    sourceJson: jsonEncode(
      serializers.serializeWith(ShootingDaySource.serializer, view.source_),
    ),
    label: Value(view.label),
    date: Value(view.date?.toString()),
    archived: view.archived,
    wrappedAt: Value(view.wrappedAt),
    updatedAt: view.updatedAt,
    version: view.version,
    cachedAt: cachedAt,
  );

  ShootingDayView _toView(ShootingDayCacheRow row) => ShootingDayView(
    (b) => b
      ..id = row.id
      ..episodeId = row.episodeId
      ..orderKey = row.orderKey
      ..source_.replace(
        serializers.deserializeWith(
          ShootingDaySource.serializer,
          jsonDecode(row.sourceJson),
        )!,
      )
      ..label = row.label
      ..date = row.date == null ? null : _parseDate(row.date!)
      ..archived = row.archived
      ..wrappedAt = row.wrappedAt
      ..updatedAt = row.updatedAt.toUtc()
      ..version = row.version,
  );

  /// Parses an ISO-8601 `yyyy-MM-dd` date string (the cache stores
  /// [ShootingDayView.date] as text). Returns `null` on malformed input
  /// rather than throwing (no-throw rule — callers treat it as unscheduled).
  Date? _parseDate(String raw) {
    final parts = raw.split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    return Date(y, m, d);
  }

  Future<void> upsert(ShootingDayView view, DateTime cachedAt) => _db
      .into(_db.shootingDayCacheRows)
      .insertOnConflictUpdate(_companion(view, cachedAt));

  /// Snapshot-replace scoped to one episode, in server order.
  Future<void> applySnapshotForEpisode(
    String episodeId,
    List<ShootingDayView> views,
    DateTime cachedAt,
  ) {
    return _db.transaction(() async {
      final ids = views.map((v) => v.id).toSet();
      for (final view in views) {
        await _db
            .into(_db.shootingDayCacheRows)
            .insertOnConflictUpdate(_companion(view, cachedAt));
      }
      if (ids.isEmpty) {
        await (_db.delete(
          _db.shootingDayCacheRows,
        )..where((t) => t.episodeId.equals(episodeId))).go();
      } else {
        await (_db.delete(_db.shootingDayCacheRows)
              ..where((t) => t.episodeId.equals(episodeId) & t.id.isNotIn(ids)))
            .go();
      }
    });
  }

  /// Reads the episode's days in server order (`order_key ASC` — no
  /// client re-sort).
  Future<List<ShootingDayView>> readByEpisodeOrdered(String episodeId) async {
    final rows =
        await (_db.select(_db.shootingDayCacheRows)
              ..where((t) => t.episodeId.equals(episodeId))
              ..orderBy([(t) => OrderingTerm.asc(t.orderKey)]))
            .get();
    return rows.map(_toView).toList();
  }

  Future<ShootingDayView?> readById(String id) async {
    final row = await (_db.select(
      _db.shootingDayCacheRows,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _toView(row);
  }

  Future<bool> isEpisodeExpired(
    String episodeId,
    Duration ttl, {
    Clock clock = Clock.system,
  }) async {
    final rows = await (_db.select(
      _db.shootingDayCacheRows,
    )..where((t) => t.episodeId.equals(episodeId))).get();
    if (rows.isEmpty) return false;
    return rows.any((r) => isRowExpired(r.cachedAt, ttl, clock: clock));
  }

  Future<void> clearEpisode(String episodeId) => (_db.delete(
    _db.shootingDayCacheRows,
  )..where((t) => t.episodeId.equals(episodeId))).go();
}
