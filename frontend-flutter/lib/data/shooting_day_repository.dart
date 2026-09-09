// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: longcat-2.0 (opencode-go)
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)
// Co-authored-by: omen-alpha (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:dio/dio.dart';
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

  /// Single-intent unschedule — the explicit `date: null` clear
  /// (wire body `{"version": N, "date": null}`).
  ///
  /// The generated [UpdateShootingDayRequest] serializer omits null fields
  /// (built_value cannot represent present-but-null), so the typed path
  /// serializes `date` as *absent* — which the backend rejects with 422
  /// since #372 made absence mean "no update". The raw [Dio] call bypasses
  /// the typed serializer (precedent: `PhotoRepository.upload`).
  Future<Result<int>> unschedule(String id, {required int version}) =>
      _patchExplicitNull(id, <String, Object?>{
        'version': version,
        'date': null,
      });

  /// Single-intent rename-to-null — the explicit `label: null` clear
  /// (wire body `{"version": N, "label": null}`), same serializer
  /// limitation as [unschedule].
  Future<Result<int>> renameToNull(String id, {required int version}) =>
      _patchExplicitNull(id, <String, Object?>{
        'version': version,
        'label': null,
      });

  /// Raw `PATCH /v1/shooting-days/{id}` with a literal JSON map, bypassing
  /// the typed request serializer so present-but-null fields reach the wire.
  /// Returns the echoed aggregate version from the 200 body. Never throws:
  /// transport/handler failures map to `Left(ProblemError)` (RFC 9457 `code`,
  /// never `detail`), a missing or non-int body maps to `shooting_day.dto_invalid`.
  Future<Result<int>> _patchExplicitNull(
    String id,
    Map<String, Object?> body,
  ) async {
    try {
      final response = await api.dio.patch<Object>(
        '/v1/shooting-days/$id',
        data: body,
        options: Options(
          contentType: 'application/json',
          responseType: ResponseType.json,
        ),
      );
      final version = response.data;
      if (version is! int) {
        return const Left(ProblemError(code: 'shooting_day.dto_invalid'));
      }
      return Right(version);
    } on DioException catch (e) {
      return Left(problemErrorFromDio(e));
    }
  }

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

/// Builds a single-intent rename request (non-null label + version echo).
///
/// A `null` label (rename-to-null) cannot be expressed by the typed request
/// (built_value omits null fields) — route it to [ShootingDayRepository.renameToNull]
/// instead, which sends the explicit `{"version": N, "label": null}` body
/// the backend requires since #372.
UpdateShootingDayRequest buildRenameRequest({
  required String label,
  required int version,
}) => UpdateShootingDayRequest(
  (b) => b
    ..label = label
    ..version = version,
);
