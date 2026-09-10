// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:built_value/serializer.dart';
import 'package:drift/drift.dart';

import 'ai_import_cache.dart';
import 'cache_database.dart';

/// Data-access object for the [AiImportJobCacheRows] table.
///
/// Write discipline (task 1.4):
/// * a **successful** fetch upserts the fetched rows (merge — never
///   snapshot-delete, D1 exception documented on [upsertAll]);
/// * a fetch `Left` never touches the table (the repository only calls the
///   write on `Right`);
/// * the screen reads only through the DAO, never the API client.
///
/// The merge (no delete-missing) is a deliberate deviation from the
/// hierarchy snapshot-replace: the jobs list route is a **windowed,
/// newest-first list** — remembered job ids older than the window (and the
/// per-job episode context written at enqueue time) would be evicted by a
/// snapshot delete. Stale rows are bounded by the bounded-recent-window
/// read (`readRecent`) instead.
class AiImportJobsCacheDao {
  const AiImportJobsCacheDao(this._db);

  final CacheDatabase _db;

  /// Upserts the fetched [jobs] rows, preserving each cached row's existing
  /// client-local episode context when the fetched snapshot has none
  /// (the context is written at enqueue time and the list route does not
  /// carry it). Rows absent from [jobs] are kept (merge, not snapshot).
  Future<void> upsertAll(List<AiImportJob> jobs, DateTime cachedAt) {
    return _db.transaction(() async {
      for (final job in jobs) {
        // Identity-scoped merge read: the context belongs to the row's
        // owning user, never to a same-id row of a previous identity.
        final existing = await readById(job.id, job.userId);
        await _db
            .into(_db.aiImportJobCacheRows)
            .insertOnConflictUpdate(
              _companion(
                job,
                cachedAt,
                episodeId: existing?.episodeId,
                seriesId: existing?.seriesId,
              ),
            );
      }
    });
  }

  /// Upserts one job row with the client-local apply context (called at
  /// enqueue time with the acting episode/series, and on status refreshes).
  Future<void> upsertWithEpisodeContext(
    AiImportJob job,
    DateTime cachedAt, {
    required String episodeId,
    required String seriesId,
  }) => _db
      .into(_db.aiImportJobCacheRows)
      .insertOnConflictUpdate(
        _companion(job, cachedAt, episodeId: episodeId, seriesId: seriesId),
      );

  /// Updates only the client-local apply context of a cached row (remembered
  /// backfill). Scoped by [userId] — a same-id row of a different identity
  /// is never touched. A no-op when the row is absent.
  Future<void> setEpisodeContext(
    String jobId, {
    required String userId,
    required String episodeId,
    required String seriesId,
  }) async {
    final row = await readById(jobId, userId);
    if (row == null) return;
    await (_db.update(
      _db.aiImportJobCacheRows,
    )..where((t) => t.id.equals(jobId))).write(
      AiImportJobCacheRowsCompanion(
        episodeId: Value(episodeId),
        seriesId: Value(seriesId),
      ),
    );
  }

  /// Pure Drift read of every cached job row of [userId], newest-first by
  /// server `updatedAt` (mirrors the list route's ordering).
  ///
  /// Identity-scoped (review): `userId` filtering is enforced at the
  /// query, not by the sign-out reset alone — a failed/missed clear must
  /// never leak a previous user's job rows (`dedupKey`, `documentDigest`,
  /// `sourceHandle`).
  Future<List<AiImportJobCacheRow>> readAll(String userId) =>
      (_db.select(_db.aiImportJobCacheRows)
            ..where((t) => t.userId.equals(userId))
            ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
          .get();

  /// Bounded-recent-window read (merge-cache staleness bound): the newest
  /// [limit] rows of [userId] by server `updatedAt`.
  Future<List<AiImportJobCacheRow>> readRecent(
    String userId, {
    int limit = 50,
  }) =>
      (_db.select(_db.aiImportJobCacheRows)
            ..where((t) => t.userId.equals(userId))
            ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
            ..limit(limit))
          .get();

  /// Pure Drift read of a single cached row by id + [userId], or `null`
  /// (the id alone is not an identity boundary — see [readAll]).
  Future<AiImportJobCacheRow?> readById(String id, String userId) =>
      (_db.select(_db.aiImportJobCacheRows)
            ..where((t) => t.id.equals(id) & t.userId.equals(userId)))
          .getSingleOrNull();

  /// Wipes the table (sign-out / backend-switch resets — identity-scoped).
  Future<void> clear() => _db.delete(_db.aiImportJobCacheRows).go();

  AiImportJobCacheRowsCompanion _companion(
    AiImportJob job,
    DateTime cachedAt, {
    String? episodeId,
    String? seriesId,
  }) => AiImportJobCacheRowsCompanion.insert(
    id: job.id,
    userId: job.userId,
    // Wire enum values (snake_case) via the generated serializers —
    // never the Dart getter names.
    status:
        serializers.serializeWith(JobStatus.serializer, job.status) as String,
    documentKind: serializers.serializeWith(
      DocumentKind.serializer,
      job.documentKind,
    ) as String,
    sourceFormat: serializers.serializeWith(
      SourceFormat.serializer,
      job.sourceFormat,
    ) as String,
    blockId: Value(job.blockId),
    episodeId: Value(episodeId),
    seriesId: Value(seriesId),
    dedupKey: job.dedupKey,
    documentDigest: job.documentDigest,
    sourceHandle: job.sourceHandle,
    lastError: Value(job.lastError),
    previewHandle: Value(job.previewHandle),
    retries: job.retries,
    maxRetries: job.maxRetries,
    createdAt: job.createdAt,
    updatedAt: job.updatedAt,
    cachedAt: cachedAt,
  );
}

/// Parses a cached row's status wire string back to the generated
/// [JobStatus], or `null` for an unknown future status (strict — the UI
/// renders an honest degraded state instead of guessing).
JobStatus? jobStatusFromWire(String wire) =>
    _parseWire(JobStatus.serializer, wire);

/// Parses a cached row's document-kind wire string, or `null` (strict).
DocumentKind? documentKindFromWire(String wire) =>
    _parseWire(DocumentKind.serializer, wire);

/// Parses a cached row's source-format wire string, or `null` (strict).
SourceFormat? sourceFormatFromWire(String wire) =>
    _parseWire(SourceFormat.serializer, wire);

T? _parseWire<T>(Serializer<T> serializer, String wire) {
  try {
    return serializers.deserializeWith(serializer, wire);
  } on Object {
    return null;
  }
}
