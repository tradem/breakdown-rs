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

/// Read/write repository for the `CostumeCategory` aggregate boundary
/// (scoped to a Season).
///
/// Wraps the generated [BreakdownApi] calls (never throws, returns [Result])
/// and owns the Drift write path through [CostumeCategoryCacheDao] — the
/// same discipline as [SeasonRepository]: a successful fetch upserts inside
/// one transaction (season-scoped snapshot-replace in server
/// `order_key ASC` order), a fetch [Left] returns the error without
/// mutating the cache.
///
/// Rename echoes the `version` of the read row the user acted on
/// (optimistic locking — a 409 surfaces "changed elsewhere — refresh" copy
/// keyed on `code`, never a silent overwrite).
class CostumeCategoryRepository extends BaseRepository {
  const CostumeCategoryRepository(super.api, this.cache);

  final CostumeCategoryCacheDao cache;

  /// Season-scoped fetch + snapshot-replace
  /// (`GET /v1/seasons/{season_id}/costume-categories`, server
  /// `ORDER BY order_key ASC`).
  ///
  /// On [Right] applies the season-scoped snapshot and returns the rows. On
  /// [Left] returns the error without touching the cache. Honors [fence]
  /// like every other collection fetch.
  Future<Result<List<CostumeCategoryView>>> list(
    String seasonId, {
    Clock clock = Clock.system,
    CacheWriteFence? fence,
  }) async {
    final Result<List<CostumeCategoryView>> fetched = await runList(
      () => api.getHandlersApi().listCostumeCategories(seasonId: seasonId),
      dtoInvalidCode: 'costume_category.dto_invalid',
    );
    return fetched.match(
      (err) async => Left<ProblemError, List<CostumeCategoryView>>(err),
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

  /// Pure Drift read (no network) of the season's cached categories in
  /// server order (`order_key ASC`).
  Future<Result<List<CostumeCategoryView>>> readCached(String seasonId) async {
    try {
      return Right(await cache.readBySeasonOrdered(seasonId));
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

  Future<Result<IdVersionResponse>> create(
    String seasonId,
    CreateCostumeCategoryRequest request,
  ) => run(
    () => api.getHandlersApi().createCostumeCategory(
      seasonId: seasonId,
      createCostumeCategoryRequest: request,
    ),
  );

  Future<Result<int>> update(String id, UpdateCostumeCategoryRequest request) =>
      run(
        () => api.getHandlersApi().updateCostumeCategory(
          id: id,
          updateCostumeCategoryRequest: request,
        ),
      );

  /// Renames a category, echoing the `version` of the read row the user
  /// acted on (optimistic locking).
  Future<Result<int>> rename(String id, int version, String name) => update(
    id,
    UpdateCostumeCategoryRequest(
      (b) => b
        ..version = version
        ..name = name,
    ),
  );

  Future<Result<int>> archive(String id, VersionRequest version) => run(
    () => api.getHandlersApi().archiveCostumeCategory(
      id: id,
      versionRequest: version,
    ),
  );

  /// Empties the season's category rows (sign-out / backend-switch resets).
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
