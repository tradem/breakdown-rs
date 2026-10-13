// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:fpdart/fpdart.dart';

import '../core/problem_error.dart';
import '../core/result.dart';
import 'base_repository.dart';
import 'cache/cache_generation.dart';
import 'cache/cache_ttl.dart';
import 'cache/clock.dart';
import 'cache/costume_domains_cache_dao.dart';

/// Read repository for the **costume fundus** (OpenSpec change
/// `flutter-fundus-search`, issue #625).
///
/// The fundus is the project's cross-season repertoire: the fetch scope is
/// `GET /v1/costumes?project_id=…` (the route already exists and is
/// generated — design D3; no backend/OpenAPI change), snapshot-replaced
/// into the dedicated project-scoped [FundusCostumeCacheDao] slice. Every
/// method returns [Result] — never throws (AGENTS.md §5).
class FundusRepository extends BaseRepository {
  const FundusRepository(super.api, this.cache);

  final FundusCostumeCacheDao cache;

  /// Project-scoped fetch + snapshot-replace
  /// (`GET /v1/costumes?project_id=…`), paginated through every page so the
  /// snapshot is never truncated (issue #385).
  ///
  /// On [Right] applies the project-scoped snapshot and returns the rows.
  /// On [Left] returns the error without touching the cache. Honors [fence]
  /// like every other collection fetch.
  Future<Result<List<CostumeView>>> listByProject(
    String projectId, {
    Clock clock = Clock.system,
    CacheWriteFence? fence,
  }) async {
    final Result<List<CostumeView>> fetched = await fetchAllPages<CostumeView>(
      ({required int limit, required int offset}) => api
          .getHandlersApi()
          .listCostumes(projectId: projectId, limit: limit, offset: offset),
      dtoInvalidCode: 'costume.dto_invalid',
    );
    return fetched.match(
      (err) async => Left<ProblemError, List<CostumeView>>(err),
      (rows) async {
        if (fence != null && !fence.isCurrentGeneration(fence.generation)) {
          return Right(rows);
        }
        try {
          await cache.applySnapshotForProject(projectId, rows, clock.now());
        } on Object {
          return const Left(ProblemError(code: 'cache.write_failed'));
        }
        return Right(rows);
      },
    );
  }

  /// Pure Drift read (no network) of the project's cached fundus rows WITH
  /// the TTL staleness verdict.
  Future<Result<({List<CostumeView> rows, bool stale})>> readCachedFresh(
    String projectId, {
    Clock clock = Clock.system,
    Duration ttl = kCacheTtl,
  }) async {
    try {
      return Right(
        await cache.readByProjectFresh(projectId, ttl: ttl, clock: clock),
      );
    } on Object {
      return const Left(ProblemError(code: 'cache.read_failed'));
    }
  }

  /// Returns `true` when any cached row of the project is older than [ttl].
  ///
  /// Wrapped in the repository's standard error boundary so a throwing DAO
  /// read cannot escape as a throw (the class's "never throws" contract —
  /// `Result` in, `Result` out, errors as values, AGENTS.md §5).
  Future<Result<bool>> isCacheStale(
    String projectId, {
    Clock clock = Clock.system,
    Duration ttl = kCacheTtl,
  }) async {
    try {
      return Right(await cache.isProjectExpired(projectId, ttl, clock: clock));
    } on Object {
      return const Left(ProblemError(code: 'cache.read_failed'));
    }
  }

  /// Empties the project's fundus rows (sign-out / backend-switch resets).
  Future<Result<void>> clearCache(String projectId) async {
    try {
      await cache.clearProject(projectId);
      return const Right<ProblemError, void>(null);
    } on Object {
      return const Left(ProblemError(code: 'cache.clear_failed'));
    }
  }
}
