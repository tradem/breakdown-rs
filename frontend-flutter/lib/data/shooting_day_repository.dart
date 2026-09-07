// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: longcat-2.0 (opencode-go)
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:fpdart/fpdart.dart';

import '../core/problem_error.dart';
import '../core/result.dart';
import 'base_repository.dart';
import 'cache/cache_generation.dart';
import 'cache/cache_ttl.dart';
import 'cache/clock.dart';
import 'cache/costume_domains_cache_dao.dart';

/// Read/write repository for the `ShootingDay` aggregate boundary.
///
/// Wraps the generated [BreakdownApi] calls (never throws, returns [Result])
/// and owns the Drift write path through [ShootingDayCacheDao]: a successful
/// fetch applies the episode-scoped snapshot in server `order_key ASC` order
/// (the client never re-sorts), a fetch [Left] returns the error without
/// mutating the cache.
///
/// `UpdateShootingDayRequest` is a one-of command: the UI issues reorder
/// (single new key), reschedule/unschedule (`date`, `date: null` for
/// unschedule), rename — one PATCH per action, never a combined payload.
class ShootingDayRepository extends BaseRepository {
  const ShootingDayRepository(super.api, this.cache);

  final ShootingDayCacheDao cache;

  /// Episode-scoped fetch + snapshot-replace
  /// (`GET /v1/episodes/{episode_id}/shooting-days`, server order).
  Future<Result<List<ShootingDayView>>> listByEpisode(
    String episodeId, {
    Clock clock = Clock.system,
    CacheWriteFence? fence,
  }) async {
    final Result<List<ShootingDayView>> fetched = await runList(
      () => api.getHandlersApi().listShootingDays(episodeId: episodeId),
      dtoInvalidCode: 'shooting_day.dto_invalid',
    );
    return fetched.match(
      (err) async => Left<ProblemError, List<ShootingDayView>>(err),
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

  /// Pure Drift read (no network) of the episode's cached days in server
  /// order (`order_key ASC`).
  Future<Result<List<ShootingDayView>>> readCached(String episodeId) async {
    try {
      return Right(await cache.readByEpisodeOrdered(episodeId));
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

  Future<Result<IdVersionResponse>> create(
    String episodeId,
    CreateShootingDayRequest request,
  ) => run(
    () => api.getHandlersApi().createShootingDay(
      episodeId: episodeId,
      createShootingDayRequest: request,
    ),
  );

  Future<Result<ShootingDayView>> get(String id) =>
      run(() => api.getHandlersApi().getShootingDay(id: id));

  /// Single-intent update: reorder (order_key) / reschedule+unschedule
  /// (date incl. `date: null`) / rename (label) — one PATCH per action.
  Future<Result<int>> update(String id, UpdateShootingDayRequest request) =>
      run(
        () => api.getHandlersApi().updateShootingDay(
          id: id,
          updateShootingDayRequest: request,
        ),
      );

  Future<Result<int>> archive(String id, VersionRequest version) => run(
    () => api.getHandlersApi().archiveShootingDay(
      id: id,
      versionRequest: version,
    ),
  );

  /// Scene scheduling from the scene side: schedule (picker over the parent
  /// episode's not-yet-archived days; `ScheduleSceneRequest.version` is the
  /// scene's version from the acted-on `SceneView`).
  Future<Result<int>> scheduleScene(
    String sceneId,
    ScheduleSceneRequest request,
  ) => run(
    () => api.getHandlersApi().scheduleSceneOnShootingDay(
      id: sceneId,
      scheduleSceneRequest: request,
    ),
  );

  /// Scene scheduling: unschedule (DELETE with `?version=` query parameter,
  /// backend issue #341).
  Future<Result<int>> unscheduleScene(
    String sceneId,
    String shootingDayId,
    int sceneVersion,
  ) => run(
    () => api.getHandlersApi().unscheduleSceneFromShootingDay(
      id: sceneId,
      shootingDayId: shootingDayId,
      version: sceneVersion,
    ),
  );

  /// Empties the episode's day rows (sign-out / backend-switch resets).
  Future<Result<void>> clearCache(String episodeId) async {
    try {
      await cache.clearEpisode(episodeId);
      return const Right<ProblemError, void>(null);
    } on Object {
      return const Left(ProblemError(code: 'cache.clear_failed'));
    }
  }
}

/// Builds a single-intent reorder request (new order_key + version echo).
UpdateShootingDayRequest buildReorderRequest({
  required String orderKey,
  required int version,
}) => UpdateShootingDayRequest(
  (b) => b
    ..orderKey = orderKey
    ..version = version,
);

/// Builds a single-intent reschedule request (date + version echo).
UpdateShootingDayRequest buildRescheduleRequest({
  required Date date,
  required int version,
}) => UpdateShootingDayRequest(
  (b) => b
    ..date = date
    ..version = version,
);

/// Builds a single-intent unschedule request (`date: null` + version echo).
/// `date: null` is the explicit unschedule — distinct from absent.
UpdateShootingDayRequest buildUnscheduleRequest({required int version}) =>
    UpdateShootingDayRequest((b) => b..version = version);

/// Builds a single-intent rename request (label + version echo).
UpdateShootingDayRequest buildRenameRequest({
  required String? label,
  required int version,
}) => UpdateShootingDayRequest(
  (b) => b
    ..label = label
    ..version = version,
);
