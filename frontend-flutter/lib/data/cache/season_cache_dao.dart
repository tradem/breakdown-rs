// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy3 (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:drift/drift.dart';

import 'cache_database.dart';
import 'cache_ttl.dart';
import 'clock.dart';
import 'season_cache.dart';

/// Data-access object for the [SeasonCacheRows] table.
///
/// All writes go through [CacheDatabase.transaction] so a snapshot replace is
/// atomic (Design Decision D3: upsert-all + delete-missing-ids in one txn).
/// Rows are mapped to/from the generated [SeasonView] DTO; the server
/// `updatedAt` is preserved unchanged while [SeasonCacheRows.cachedAt] records
/// the client-only write time.
class SeasonCacheDao {
  const SeasonCacheDao(this._db);

  final CacheDatabase _db;

  SeasonCacheRowsCompanion _companion(SeasonView view, DateTime cachedAt) =>
      SeasonCacheRowsCompanion.insert(
        id: view.id,
        number: view.number,
        seriesId: view.seriesId,
        title: Value(view.title),
        updatedAt: view.updatedAt,
        version: view.version,
        cachedAt: cachedAt,
      );

  /// Upserts one [SeasonView] by id, stamped with [cachedAt] (D2).
  Future<void> upsert(SeasonView view, DateTime cachedAt) =>
      _db.into(_db.seasonCacheRows).insertOnConflictUpdate(
            _companion(view, cachedAt),
          );

  /// Snapshot-replace (Design Decision D3): upserts every [views] row by id and
  /// deletes any cached row whose id is absent from [views], all in ONE
  /// transaction. A complete, authoritative snapshot must never leave orphan
  /// rows behind; a partial/errored/paginated fetch must NOT delete anything
  /// (callers only invoke this on a successful full snapshot).
  Future<void> applySnapshot(List<SeasonView> views, DateTime cachedAt) {
    return _db.transaction(() async {
      final ids = views.map((v) => v.id).toSet();
      for (final view in views) {
        await _db.into(_db.seasonCacheRows).insertOnConflictUpdate(
              _companion(view, cachedAt),
            );
      }
      // delete-missing-ids: every cached row not present in this snapshot.
      if (ids.isEmpty) {
        await _db.delete(_db.seasonCacheRows).go();
      } else {
        await (_db.delete(_db.seasonCacheRows)
              ..where((t) => t.id.isNotIn(ids)))
            .go();
      }
    });
  }

  /// Pure Drift read (no network) of every cached season, in insertion order.
  Future<List<SeasonView>> readAll() async {
    final rows = await _db.select(_db.seasonCacheRows).get();
    return rows.map(_toSeasonView).toList();
  }

  /// Pure Drift read of a single cached season by id, or `null`.
  Future<SeasonView?> readById(String id) async {
    final row = await (_db.select(_db.seasonCacheRows)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : _toSeasonView(row);
  }

  /// Returns `true` when any cached row is older than [ttl] per [clock] (D2).
  /// TTL is computed from the client-only [SeasonCacheRows.cachedAt], never
  /// the server `updatedAt`, so a failed refetch eventually marks rows stale
  /// rather than serving them forever.
  Future<bool> isAnyExpired(Duration ttl, {Clock clock = Clock.system}) async {
    final rows = await _db.select(_db.seasonCacheRows).get();
    return rows.any((r) => isRowExpired(r.cachedAt, ttl, clock: clock));
  }

  /// Wipes the table (used by on-write-invalidate tests and cold-start resets).
  Future<void> clear() => _db.delete(_db.seasonCacheRows).go();

  SeasonView _toSeasonView(SeasonCacheRow row) => SeasonView(
        (b) => b
          ..id = row.id
          ..number = row.number
          ..seriesId = row.seriesId
          ..title = row.title
          // Drift preserves the instant but decodes DateTime in local time,
          // so normalize to UTC to keep the DTO representation identical to
          // the server's (the `updated_at` wire value is UTC).
          ..updatedAt = row.updatedAt.toUtc()
          ..version = row.version,
      );
}
