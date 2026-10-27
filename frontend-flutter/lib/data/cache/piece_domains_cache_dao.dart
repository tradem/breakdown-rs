// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)
// Co-authored-by: glm-5.3-flash (neuralwatt)

import 'dart:convert';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/serializer.dart';
import 'package:drift/drift.dart';

import 'cache_database.dart';
import 'cache_ttl.dart';
import 'clock.dart';
import 'hierarchy_cache_dao.dart' show blockViewOf, episodeViewOf;
import 'piece_domains_cache.dart';

/// Serializers shim: the generated `breakdown_api` package exposes the
/// standard `serializers` object for wire (de)serialization of nested
/// projection snapshots (`details`, `photos`, `source`).
///
/// Piece `details`/`photos` ride the piece row as JSON snapshots because
/// there is no detail/photo list route — they refresh with the piece row.

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

// --- Pieces -----------------------------------------------------------------

/// Data-access object for [PieceCacheRows].
///
/// Same discipline as [SeasonCacheDao]: snapshot writes go through
/// [CacheDatabase.transaction] (upsert-all + delete-missing-ids in one txn),
/// rows map to/from the generated `PieceView` DTO, the server `updatedAt`
/// is preserved unchanged while `cachedAt` records the client-only write
/// time, and TTL is computed from `cachedAt` only.
class PieceCacheDao {
  const PieceCacheDao(this._db);

  final CacheDatabase _db;

  PieceCacheRowsCompanion _companion(
    String seasonId,
    PieceView view,
    DateTime cachedAt,
    int snapshotIndex,
  ) => PieceCacheRowsCompanion.insert(
    id: view.id,
    seasonId: seasonId,
    name: view.name,
    categoryId: Value(view.categoryId),
    categoryName: Value(view.categoryName),
    notes: view.notes,
    detailsJson: jsonEncode(
      _encodeBuiltList(view.details, PieceDetailView.serializer),
    ),
    photosJson: jsonEncode(
      _encodeBuiltList(view.photos, PiecePhotoView.serializer),
    ),
    seasonIdsJson: Value(jsonEncode(view.seasonIds.toList())),
    updatedAt: view.updatedAt,
    version: view.version,
    cachedAt: cachedAt,
    snapshotIndex: snapshotIndex,
  );

  PieceView _toView(String seasonId, PieceCacheRow row) => PieceView((b) {
    b
      ..id = row.id
      ..name = row.name
      ..categoryId = row.categoryId
      ..categoryName = row.categoryName
      ..notes = row.notes
      ..details.replace(
        _decodeBuiltList(row.detailsJson, PieceDetailView.serializer),
      )
      ..photos.replace(
        _decodeBuiltList(row.photosJson, PiecePhotoView.serializer),
      )
      ..updatedAt = row.updatedAt.toUtc()
      ..version = row.version;
    // Issue #534: the repertoire survives the cache. Pre-#534 rows carry
    // NULL — the cache predates the field and maps to an empty list until
    // the next TTL snapshot-replace fills it.
    if (row.seasonIdsJson case final json? when json.isNotEmpty) {
      final decoded = jsonDecode(json);
      if (decoded is List) {
        // Tolerant decode (CodeRabbit review): a corrupt stored value must
        // not throw out of a `data/` read — non-string elements are dropped
        // and a `FormatException` is caught by `readCached`
        // (cache.read_failed), the same shape the NULL-from-older-cache
        // case maps to.
        b.seasonIds.replace(BuiltList<String>(decoded.whereType<String>()));
      }
    }
    assert(seasonId.isNotEmpty, 'season scope must be non-empty');
  });

  /// Single-row upsert preserving the existing snapshot ordinal (a
  /// refetched row keeps its list position; brand-new rows append after
  /// the current season maximum so they never jump ahead of the snapshot
  /// order).
  Future<void> upsert(
    String seasonId,
    PieceView view,
    DateTime cachedAt,
  ) async {
    final existing =
        await (_db.select(
              _db.pieceCacheRows,
            )..where((t) => t.id.equals(view.id) & t.seasonId.equals(seasonId)))
            .getSingleOrNull();
    var index = existing?.snapshotIndex;
    index ??= await _seasonMaxIndex(seasonId);
    await _db
        .into(_db.pieceCacheRows)
        .insertOnConflictUpdate(
          _companion(seasonId, view, cachedAt, (index ?? -1) + 1),
        );
  }

  Future<int?> _seasonMaxIndex(String seasonId) async {
    final row =
        await (_db.select(_db.pieceCacheRows)
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
    List<PieceView> views,
    DateTime cachedAt,
  ) {
    return _db.transaction(() async {
      final ids = views.map((v) => v.id).toSet();
      for (var i = 0; i < views.length; i++) {
        await _db
            .into(_db.pieceCacheRows)
            .insertOnConflictUpdate(
              _companion(seasonId, views[i], cachedAt, i),
            );
      }
      if (ids.isEmpty) {
        await (_db.delete(
          _db.pieceCacheRows,
        )..where((t) => t.seasonId.equals(seasonId))).go();
      } else {
        await (_db.delete(
          _db.pieceCacheRows,
        )..where((t) => t.seasonId.equals(seasonId) & t.id.isNotIn(ids))).go();
      }
    });
  }

  /// Reads the season's pieces in snapshot order (`snapshotIndex`
  /// ASC reproduces the server `ORDER BY updated_at DESC` exactly,
  /// including timestamp ties that no column ordering could separate).
  Future<List<PieceView>> readBySeason(String seasonId) async =>
      (await readBySeasonFresh(seasonId)).rows;

  /// Season-scoped read WITH the TTL staleness verdict (issue #616,
  /// OmniSearch tasks §2.1): the piece scope is the seasonal snapshot
  /// column, so no join is needed. No schema change (§2.4 does not
  /// trigger).
  Future<({List<PieceView> rows, bool stale})> readBySeasonFresh(
    String seasonId, {
    Duration ttl = kCacheTtl,
    Clock clock = Clock.system,
  }) async {
    final raw =
        await (_db.select(_db.pieceCacheRows)
              ..where((t) => t.seasonId.equals(seasonId))
              ..orderBy([(t) => OrderingTerm.asc(t.snapshotIndex)]))
            .get();
    return (
      rows: raw.map((r) => _toView(seasonId, r)).toList(),
      stale: raw.any((r) => isRowExpired(r.cachedAt, ttl, clock: clock)),
    );
  }

  Future<PieceView?> readById(String seasonId, String id) async {
    final row =
        await (_db.select(_db.pieceCacheRows)
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
      _db.pieceCacheRows,
    )..where((t) => t.seasonId.equals(seasonId))).get();
    if (rows.isEmpty) return false;
    return rows.any((r) => isRowExpired(r.cachedAt, ttl, clock: clock));
  }

  Future<void> clearSeason(String seasonId) => (_db.delete(
    _db.pieceCacheRows,
  )..where((t) => t.seasonId.equals(seasonId))).go();
}

// --- Fundus pieces (project scope) ------------------------------------------

/// Data-access object for [FundusPieceCacheRows] (OpenSpec change
/// `flutter-fundus-search`, issue #625).
///
/// Same snapshot discipline as [PieceCacheDao], but the scope key is a
/// PROJECT id (`GET /v1/pieces?project_id=`) instead of a season. The
/// rows mirror `PieceView` faithfully — including pieces whose
/// repertoire is empty; the repertoire-exclusion rule is a pure domain rule
/// applied by the fundus matcher, never a silent drop at the cache layer
/// (so the cache never lies about what the server returned).
class FundusPieceCacheDao {
  const FundusPieceCacheDao(this._db);

  final CacheDatabase _db;

  FundusPieceCacheRowsCompanion _companion(
    String projectId,
    PieceView view,
    DateTime cachedAt,
    int snapshotIndex,
  ) => FundusPieceCacheRowsCompanion.insert(
    id: view.id,
    projectId: projectId,
    name: view.name,
    categoryId: Value(view.categoryId),
    categoryName: Value(view.categoryName),
    notes: view.notes,
    detailsJson: jsonEncode(
      _encodeBuiltList(view.details, PieceDetailView.serializer),
    ),
    photosJson: jsonEncode(
      _encodeBuiltList(view.photos, PiecePhotoView.serializer),
    ),
    seasonIdsJson: Value(jsonEncode(view.seasonIds.toList())),
    updatedAt: view.updatedAt,
    version: view.version,
    cachedAt: cachedAt,
    snapshotIndex: snapshotIndex,
  );

  PieceView _toView(FundusPieceCacheRow row) => PieceView((b) {
    b
      ..id = row.id
      ..name = row.name
      ..categoryId = row.categoryId
      ..categoryName = row.categoryName
      ..notes = row.notes
      ..details.replace(
        _decodeBuiltList(row.detailsJson, PieceDetailView.serializer),
      )
      ..photos.replace(
        _decodeBuiltList(row.photosJson, PiecePhotoView.serializer),
      )
      ..updatedAt = row.updatedAt.toUtc()
      ..version = row.version;
    // Same tolerant decode as [PieceCacheDao._toView]: a corrupt stored
    // value must not throw out of a `data/` read. A NULL (defensive) maps
    // to the empty repertoire the matcher then excludes.
    if (row.seasonIdsJson case final json? when json.isNotEmpty) {
      final decoded = jsonDecode(json);
      if (decoded is List) {
        b.seasonIds.replace(BuiltList<String>(decoded.whereType<String>()));
      }
    }
  });

  /// Single-row upsert preserving the existing snapshot ordinal.
  Future<void> upsert(
    String projectId,
    PieceView view,
    DateTime cachedAt,
  ) async {
    final existing =
        await (_db.select(_db.fundusPieceCacheRows)..where(
              (t) => t.id.equals(view.id) & t.projectId.equals(projectId),
            ))
            .getSingleOrNull();
    var index = existing?.snapshotIndex;
    index ??= await _projectMaxIndex(projectId);
    await _db
        .into(_db.fundusPieceCacheRows)
        .insertOnConflictUpdate(
          _companion(projectId, view, cachedAt, (index ?? -1) + 1),
        );
  }

  Future<int?> _projectMaxIndex(String projectId) async {
    final row =
        await (_db.select(_db.fundusPieceCacheRows)
              ..where((t) => t.projectId.equals(projectId))
              ..orderBy([(t) => OrderingTerm.desc(t.snapshotIndex)])
              ..limit(1))
            .getSingleOrNull();
    return row?.snapshotIndex;
  }

  /// Snapshot-replace scoped to one project: upserts every [views] row by id
  /// and deletes cached rows of [projectId] absent from [views], in ONE
  /// transaction. Rows of other projects are never touched.
  Future<void> applySnapshotForProject(
    String projectId,
    List<PieceView> views,
    DateTime cachedAt,
  ) {
    return _db.transaction(() async {
      final ids = views.map((v) => v.id).toSet();
      for (var i = 0; i < views.length; i++) {
        await _db
            .into(_db.fundusPieceCacheRows)
            .insertOnConflictUpdate(
              _companion(projectId, views[i], cachedAt, i),
            );
      }
      if (ids.isEmpty) {
        await (_db.delete(
          _db.fundusPieceCacheRows,
        )..where((t) => t.projectId.equals(projectId))).go();
      } else {
        await (_db.delete(_db.fundusPieceCacheRows)
              ..where((t) => t.projectId.equals(projectId) & t.id.isNotIn(ids)))
            .go();
      }
    });
  }

  /// Reads the project's pieces in snapshot order, WITH the TTL staleness
  /// verdict (the `cachedAt` column only).
  Future<({List<PieceView> rows, bool stale})> readByProjectFresh(
    String projectId, {
    Duration ttl = kCacheTtl,
    Clock clock = Clock.system,
  }) async {
    final raw =
        await (_db.select(_db.fundusPieceCacheRows)
              ..where((t) => t.projectId.equals(projectId))
              ..orderBy([(t) => OrderingTerm.asc(t.snapshotIndex)]))
            .get();
    return (
      rows: raw.map(_toView).toList(),
      stale: raw.any((r) => isRowExpired(r.cachedAt, ttl, clock: clock)),
    );
  }

  Future<bool> isProjectExpired(
    String projectId,
    Duration ttl, {
    Clock clock = Clock.system,
  }) async {
    final rows = await (_db.select(
      _db.fundusPieceCacheRows,
    )..where((t) => t.projectId.equals(projectId))).get();
    if (rows.isEmpty) return false;
    return rows.any((r) => isRowExpired(r.cachedAt, ttl, clock: clock));
  }

  Future<void> clearProject(String projectId) => (_db.delete(
    _db.fundusPieceCacheRows,
  )..where((t) => t.projectId.equals(projectId))).go();
}

// --- Outfits ------------------------------------------------------------------

/// Data-access object for [OutfitCacheRows] (a character's composed looks).
///
/// Same discipline as [PieceCacheDao]: snapshot writes go through
/// [CacheDatabase.transaction] (upsert-all + delete-missing-ids in one txn),
/// rows map to/from the generated `OutfitView` DTO, and TTL is computed from
/// the client-only `cachedAt` column.
class OutfitCacheDao {
  const OutfitCacheDao(this._db);

  final CacheDatabase _db;

  OutfitCacheRowsCompanion _companion(
    OutfitView view,
    DateTime cachedAt,
    int snapshotIndex,
  ) => OutfitCacheRowsCompanion.insert(
    id: view.id,
    characterId: view.characterId,
    name: view.name,
    variantOf: Value(view.variantOf),
    notes: view.notes,
    piecesJson: jsonEncode(
      _encodeBuiltList(view.pieces, OutfitPieceView.serializer),
    ),
    photosJson: jsonEncode(
      _encodeBuiltList(view.photos, OutfitPhotoView.serializer),
    ),
    updatedAt: view.updatedAt,
    version: view.version,
    cachedAt: cachedAt,
    snapshotIndex: snapshotIndex,
  );

  OutfitView _toView(OutfitCacheRow row) => OutfitView((b) {
    b
      ..id = row.id
      ..characterId = row.characterId
      ..name = row.name
      ..variantOf = row.variantOf
      ..notes = row.notes
      ..pieces.replace(
        _decodeBuiltList(row.piecesJson, OutfitPieceView.serializer),
      )
      ..photos.replace(
        _decodeBuiltList(row.photosJson, OutfitPhotoView.serializer),
      )
      ..updatedAt = row.updatedAt.toUtc()
      ..version = row.version;
  });

  Future<void> upsert(OutfitView view, DateTime cachedAt) async {
    final existing = await (_db.select(
      _db.outfitCacheRows,
    )..where((t) => t.id.equals(view.id))).getSingleOrNull();
    var index = existing?.snapshotIndex;
    index ??= await _characterMaxIndex(view.characterId);
    await _db
        .into(_db.outfitCacheRows)
        .insertOnConflictUpdate(_companion(view, cachedAt, (index ?? -1) + 1));
  }

  Future<int?> _characterMaxIndex(String characterId) async {
    final row =
        await (_db.select(_db.outfitCacheRows)
              ..where((t) => t.characterId.equals(characterId))
              ..orderBy([(t) => OrderingTerm.desc(t.snapshotIndex)])
              ..limit(1))
            .getSingleOrNull();
    return row?.snapshotIndex;
  }

  /// Snapshot-replace scoped to one character: upserts every [views] row by id
  /// and deletes cached rows of [characterId] absent from [views], in ONE
  /// transaction. Rows of other characters are never touched.
  Future<void> applySnapshotForCharacter(
    String characterId,
    List<OutfitView> views,
    DateTime cachedAt,
  ) {
    return _db.transaction(() async {
      final ids = views.map((v) => v.id).toSet();
      for (var i = 0; i < views.length; i++) {
        await _db
            .into(_db.outfitCacheRows)
            .insertOnConflictUpdate(_companion(views[i], cachedAt, i));
      }
      if (ids.isEmpty) {
        await (_db.delete(
          _db.outfitCacheRows,
        )..where((t) => t.characterId.equals(characterId))).go();
      } else {
        await (_db.delete(_db.outfitCacheRows)..where(
              (t) => t.characterId.equals(characterId) & t.id.isNotIn(ids),
            ))
            .go();
      }
    });
  }

  /// Reads the character's outfits in snapshot order, WITH the TTL staleness
  /// verdict (the `cachedAt` column only).
  Future<({List<OutfitView> rows, bool stale})> readByCharacterFresh(
    String characterId, {
    Duration ttl = kCacheTtl,
    Clock clock = Clock.system,
  }) async {
    final raw =
        await (_db.select(_db.outfitCacheRows)
              ..where((t) => t.characterId.equals(characterId))
              ..orderBy([(t) => OrderingTerm.asc(t.snapshotIndex)]))
            .get();
    return (
      rows: raw.map(_toView).toList(),
      stale: raw.any((r) => isRowExpired(r.cachedAt, ttl, clock: clock)),
    );
  }

  Future<List<OutfitView>> readByCharacter(String characterId) async =>
      (await readByCharacterFresh(characterId)).rows;

  Future<OutfitView?> readById(String characterId, String id) async {
    final row =
        await (_db.select(_db.outfitCacheRows)..where(
              (t) => t.id.equals(id) & t.characterId.equals(characterId),
            ))
            .getSingleOrNull();
    return row == null ? null : _toView(row);
  }

  Future<bool> isCharacterExpired(
    String characterId,
    Duration ttl, {
    Clock clock = Clock.system,
  }) async {
    final rows = await (_db.select(
      _db.outfitCacheRows,
    )..where((t) => t.characterId.equals(characterId))).get();
    if (rows.isEmpty) return false;
    return rows.any((r) => isRowExpired(r.cachedAt, ttl, clock: clock));
  }

  Future<void> clearCharacter(String characterId) => (_db.delete(
    _db.outfitCacheRows,
  )..where((t) => t.characterId.equals(characterId))).go();
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
    // Nullable since issue #423 (unset measurements serialize as JSON
    // null): wrapped in `Value` so an explicit null is stored, not the
    // column default.
    height: Value(view.measurements.height),
    weight: Value(view.measurements.weight),
    chest: Value(view.measurements.chest),
    waist: Value(view.measurements.waist),
    hips: Value(view.measurements.hips),
    shoeSize: Value(view.measurements.shoeSize),
    hatSize: Value(view.measurements.hatSize),
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

  /// Season-scoped read WITH the TTL staleness verdict (issue #616,
  /// OmniSearch tasks §2.1): same rows as [readBySeason], plus `true` when
  /// any row's client-only `cachedAt` has exceeded [ttl]. One additional
  /// typed-row pass, no schema change (§2.4 does not trigger).
  Future<({List<CharacterView> rows, bool stale})> readBySeasonFresh(
    String seasonId, {
    Duration ttl = kCacheTtl,
    Clock clock = Clock.system,
  }) async {
    final raw = await (_db.select(
      _db.characterCacheRows,
    )..where((t) => t.seasonId.equals(seasonId))).get();
    return (
      rows: raw.map(_toView).toList(),
      stale: raw.any((r) => isRowExpired(r.cachedAt, ttl, clock: clock)),
    );
  }
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

  /// Season-scoped composed read (issue #616, OmniSearch tasks §2.1): one
  /// SELECT joining the shooting-day row with its owning episode AND block,
  /// scoped via `block.season_id` — the day table carries no season column,
  /// so the join IS the season scope. READ-ONLY, no schema change.
  ///
  /// Server order is preserved (`order_key ASC` — no client re-sort); the
  /// staleness verdict covers ALL three involved tables' `cachedAt`.
  Future<({List<(ShootingDayView, EpisodeView, BlockView)> rows, bool stale})>
  readBySeasonComposed(
    String seasonId, {
    Duration ttl = kCacheTtl,
    Clock clock = Clock.system,
  }) async {
    final query =
        _db.select(_db.shootingDayCacheRows).join([
            innerJoin(
              _db.episodeCacheRows,
              _db.episodeCacheRows.id.equalsExp(
                _db.shootingDayCacheRows.episodeId,
              ),
            ),
            innerJoin(
              _db.blockCacheRows,
              _db.blockCacheRows.id.equalsExp(_db.episodeCacheRows.blockId),
            ),
          ])
          ..where(_db.blockCacheRows.seasonId.equals(seasonId))
          ..orderBy([OrderingTerm.asc(_db.shootingDayCacheRows.orderKey)]);
    final joined = await query.get();

    var stale = false;
    final rows = <(ShootingDayView, EpisodeView, BlockView)>[];
    for (final row in joined) {
      final day = row.readTable(_db.shootingDayCacheRows);
      final episode = row.readTable(_db.episodeCacheRows);
      final block = row.readTable(_db.blockCacheRows);
      if (isRowExpired(day.cachedAt, ttl, clock: clock) ||
          isRowExpired(episode.cachedAt, ttl, clock: clock) ||
          isRowExpired(block.cachedAt, ttl, clock: clock)) {
        stale = true;
      }
      rows.add((_toView(day), episodeViewOf(episode), blockViewOf(block)));
    }
    return (rows: rows, stale: stale);
  }
}
