// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:fpdart/fpdart.dart';

import '../core/problem_error.dart';
import '../core/result.dart';
import 'base_repository.dart';
import 'cache/cache_generation.dart';
import 'cache/cache_ttl.dart';
import 'cache/clock.dart';
import 'cache/hierarchy_cache_dao.dart';

/// Read/write repository for the `Block` aggregate boundary (scoped to a
/// Season).
///
/// Wraps the generated [BreakdownApi] calls (never throws, returns [Result])
/// and owns the Drift write path through [BlockCacheDao] — the same
/// discipline as [SeasonRepository]: a successful fetch upserts inside one
/// transaction (scoped snapshot-replace per season), a fetch [Left] returns
/// the error without mutating the cache.
class BlockRepository extends BaseRepository {
  const BlockRepository(super.api, this.cache);

  final BlockCacheDao cache;

  /// Creates a new block. Ids (`series_id`, `season_id`) come from the
  /// `SeasonView` read DTO the user acted on (CQRS boundary — never from a
  /// second projection lookup).
  Future<Result<IdVersionResponse>> create(CreateBlockRequest request) =>
      run(() => api.getHandlersApi().createBlock(createBlockRequest: request));

  /// Collection fetch + scoped snapshot-replace: `GET /v1/blocks?season_id=…`.
  ///
  /// On [Right] applies the season-scoped snapshot (upsert-all + delete
  /// missing ids of this season, one transaction) and returns the rows. On
  /// [Left] returns the error without touching the cache.
  ///
  /// When [fence] is given, a write whose generation went stale while the
  /// fetch was in flight is discarded: rows are still returned, never
  /// persisted.
  Future<Result<List<BlockView>>> listBySeason(
    String seasonId, {
    Clock clock = Clock.system,
    CacheWriteFence? fence,
  }) async {
    final Result<List<BlockView>> fetched = await runList(
      () => api.getHandlersApi().listBlocks(seasonId: seasonId),
      dtoInvalidCode: 'block.dto_invalid',
    );
    return fetched.match(
      (err) async => Left<ProblemError, List<BlockView>>(err),
      (rows) async {
        if (fence != null && !fence.isCurrentGeneration(fence.generation)) {
          return Right(rows);
        }
        try {
          await cache.applySnapshotForSeason(seasonId, rows, clock.now());
        } on Object {
          return const Left(ProblemError(code: 'cache.write_failed'));
        }
        return Right(rows);
      },
    );
  }

  /// Pure Drift read (no network) of the season's cached blocks.
  Future<Result<List<BlockView>>> readCached(String seasonId) async {
    try {
      return Right(await cache.readBySeason(seasonId));
    } on Object {
      return const Left(ProblemError(code: 'cache.read_failed'));
    }
  }

  /// Returns `true` when any cached row of the season is older than [ttl].
  Future<bool> isCacheStale(
    String seasonId, {
    Clock clock = Clock.system,
    Duration ttl = kCacheTtl,
  }) => cache.isSeasonExpired(seasonId, ttl, clock: clock);

  /// Empties the season's block rows (sign-out / backend-switch resets).
  /// Errors are values, never throws.
  Future<Result<void>> clearCache(String seasonId) async {
    try {
      await cache.clearSeason(seasonId);
      return const Right<ProblemError, void>(null);
    } on Object {
      return const Left(ProblemError(code: 'cache.clear_failed'));
    }
  }
}
