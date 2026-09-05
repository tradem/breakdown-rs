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

/// Read/write repository for the `Scene` aggregate boundary (scoped to an
/// Episode).
///
/// Wraps the generated [BreakdownApi] calls (never throws, returns [Result])
/// and owns the Drift write path through [SceneCacheDao] — the same
/// discipline as [SeasonRepository]: a successful fetch upserts inside one
/// transaction (scoped snapshot-replace per episode), a fetch [Left] returns
/// the error without mutating the cache.
///
/// Phase 1b renders scene detail data read-only (mood, location, summary,
/// script day, schedule flag, character / shooting-day counts); character
/// mutation and scheduling commands stay on the network-only path below.
class SceneRepository extends BaseRepository {
  const SceneRepository(super.api, this.cache);

  final SceneCacheDao cache;

  /// Creates a new scene (`episode_id` + `details` from the `EpisodeView`
  /// read DTO the user acted on — CQRS boundary).
  Future<Result<IdVersionResponse>> create(CreateSceneRequest request) =>
      run(() => api.getHandlersApi().createScene(createSceneRequest: request));

  /// Episode-scoped fetch + snapshot-replace
  /// (`GET /v1/scenes?episode_id=…`).
  ///
  /// On [Right] applies the episode-scoped snapshot and returns the rows. On
  /// [Left] returns the error without touching the cache. Honors [fence]
  /// like every other collection fetch.
  Future<Result<List<SceneView>>> listByEpisode(
    String episodeId, {
    Clock clock = Clock.system,
    CacheWriteFence? fence,
  }) async {
    final Result<List<SceneView>> fetched = await runList(
      () => api.getHandlersApi().listScenes(episodeId: episodeId),
      dtoInvalidCode: 'scene.dto_invalid',
    );
    return fetched.match(
      (err) async => Left<ProblemError, List<SceneView>>(err),
      (rows) async {
        if (fence != null && !fence.isCurrentGeneration(fence.generation)) {
          return Right(rows);
        }
        try {
          await cache.applySnapshotForEpisode(episodeId, rows, clock.now());
        } on Object {
          return const Left(ProblemError(code: 'cache.write_failed'));
        }
        return Right(rows);
      },
    );
  }

  /// Pure Drift read (no network) of the episode's cached scenes.
  Future<Result<List<SceneView>>> readCached(String episodeId) async {
    try {
      return Right(await cache.readByEpisode(episodeId));
    } on Object {
      return const Left(ProblemError(code: 'cache.read_failed'));
    }
  }

  /// Returns `true` when any cached row of the episode is older than [ttl].
  Future<bool> isCacheStale(
    String episodeId, {
    Clock clock = Clock.system,
    Duration ttl = kCacheTtl,
  }) => cache.isEpisodeExpired(episodeId, ttl, clock: clock);

  /// Empties the episode's scene rows (sign-out / backend-switch resets).
  /// Errors are values, never throws.
  Future<Result<void>> clearCache(String episodeId) async {
    try {
      await cache.clearEpisode(episodeId);
      return const Right<ProblemError, void>(null);
    } on Object {
      return const Left(ProblemError(code: 'cache.clear_failed'));
    }
  }

  Future<Result<SceneView>> get(String id) =>
      run(() => api.getHandlersApi().getScene(id: id));

  Future<Result<int>> updateDetails(
    String id,
    UpdateSceneDetailsRequest request,
  ) => run(
    () => api.getHandlersApi().updateSceneDetails(
      id: id,
      updateSceneDetailsRequest: request,
    ),
  );

  Future<Result<int>> assignCharacter(
    String id,
    AssignCharacterRequest request,
  ) => run(
    () => api.getHandlersApi().assignSceneCharacter(
      id: id,
      assignCharacterRequest: request,
    ),
  );

  Future<Result<int>> removeCharacter(
    String id,
    String characterId,
    int version,
  ) => run(
    () => api.getHandlersApi().removeSceneCharacter(
      id: id,
      characterId: characterId,
      version: version,
    ),
  );

  Future<Result<int>> scheduleOnShootingDay(
    String id,
    ScheduleSceneRequest request,
  ) => run(
    () => api.getHandlersApi().scheduleSceneOnShootingDay(
      id: id,
      scheduleSceneRequest: request,
    ),
  );

  Future<Result<int>> unscheduleFromShootingDay(
    String id,
    String shootingDayId,
    int version,
  ) => run(
    () => api.getHandlersApi().unscheduleSceneFromShootingDay(
      id: id,
      shootingDayId: shootingDayId,
      version: version,
    ),
  );
}
