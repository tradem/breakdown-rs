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

/// Read/write repository for the `Episode` aggregate boundary.
///
/// Wraps the generated [BreakdownApi] calls (never throws, returns [Result])
/// and owns the Drift write path through [EpisodeCacheDao] — the same
/// discipline as [SeasonRepository]: a successful fetch upserts inside one
/// transaction (scoped snapshot-replace per block), a fetch [Left] returns
/// the error without mutating the cache.
///
/// Reads use the server-side `?block_id=` filter (backend issue #335,
/// PR #355 — design.md D3); [groupByBlock] remains as a pure mapper for
/// merged/season renders only.
class EpisodeRepository extends BaseRepository {
  const EpisodeRepository(super.api, this.cache);

  final EpisodeCacheDao cache;

  /// Creates a new episode. Ids (`series_id`, `block_id`) come from the
  /// `BlockView` read DTO the user acted on (CQRS boundary — never from a
  /// second projection lookup).
  Future<Result<IdVersionResponse>> create(CreateEpisodeRequest request) => run(
    () => api.getHandlersApi().createEpisode(createEpisodeRequest: request),
  );

  /// Block-scoped fetch + snapshot-replace via the server-side filter
  /// (`GET /v1/episodes?block_id=…`).
  ///
  /// On [Right] applies the block-scoped snapshot and returns the rows. On
  /// [Left] returns the error without touching the cache. Honors [fence]
  /// like every other collection fetch.
  Future<Result<List<EpisodeView>>> listByBlock(
    String blockId, {
    Clock clock = Clock.system,
    CacheWriteFence? fence,
  }) async {
    final Result<List<EpisodeView>> fetched = await runList(
      () => api.getHandlersApi().listEpisodes(blockId: blockId),
      dtoInvalidCode: 'episode.dto_invalid',
    );
    return fetched.match(
      (err) async => Left<ProblemError, List<EpisodeView>>(err),
      (rows) async {
        if (fence != null && !fence.isCurrentGeneration(fence.generation)) {
          return Right(rows);
        }
        try {
          await cache.applySnapshotForBlock(blockId, rows, clock.now());
        } on Object {
          return const Left(ProblemError(code: 'cache.write_failed'));
        }
        return Right(rows);
      },
    );
  }

  /// Pure Drift read (no network) of the block's cached episodes.
  Future<Result<List<EpisodeView>>> readCached(String blockId) async {
    try {
      return Right(await cache.readByBlock(blockId));
    } on Object {
      return const Left(ProblemError(code: 'cache.read_failed'));
    }
  }

  /// Returns `true` when any cached row of the block is older than [ttl].
  Future<bool> isCacheStale(
    String blockId, {
    Clock clock = Clock.system,
    Duration ttl = kCacheTtl,
  }) => cache.isBlockExpired(blockId, ttl, clock: clock);

  /// Empties the block's episode rows (sign-out / backend-switch resets).
  /// Errors are values, never throws.
  Future<Result<void>> clearCache(String blockId) async {
    try {
      await cache.clearBlock(blockId);
      return const Right<ProblemError, void>(null);
    } on Object {
      return const Left(ProblemError(code: 'cache.clear_failed'));
    }
  }

  /// Pure mapper: groups episode rows by their `block_id` for merged/season
  /// renders. Read-projection grouping only — never aggregate
  /// reconstruction, never command backfill (CQRS boundary).
  static Map<String, List<EpisodeView>> groupByBlock(List<EpisodeView> rows) {
    final grouped = <String, List<EpisodeView>>{};
    for (final row in rows) {
      grouped.putIfAbsent(row.blockId, () => []).add(row);
    }
    return grouped;
  }
}
