// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3 (opencode)
// Co-authored-by: omen-alpha (opencode-go)

import 'dart:io';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:built_collection/built_collection.dart';
import 'package:dio/dio.dart';
import 'package:fpdart/fpdart.dart';

import '../core/problem_error.dart';
import '../core/result.dart';
import 'base_repository.dart';
import 'cache/cache_generation.dart';
import 'cache/cache_ttl.dart';
import 'cache/clock.dart';
import 'cache/scene_shoot_cache_dao.dart';
import 'report_cache.dart';
import 'report_models.dart';

/// Repository for the `SceneShoot` aggregate boundary — Soll/Ist execution
/// (plan/replan/get/list, start, actual-order, finish, skip, notes,
/// continuity link/list/unlink, day wrap) plus the Soll/Ist report-PDF
/// endpoints.
///
/// Every method consumes the generated Dart client exclusively (never-retype
/// rule, D1): ids travel in the path, `version` echoes come from the
/// acted-on read DTO, and commands dispatch with the
/// optimistic-after-2xx + bounded-retry reconciliation discipline of the
/// reference pattern (`SeasonsScreen`).
///
/// `PlanSceneShootRequest` carries `{ planned_order }` only — `day_id` /
/// `scene_id` are path-authoritative (backend issue #346).
///
/// Continuity calls (link/list/unlink) are transport only here: the
/// client-side capability check lives at the command-DISPATCH layer
/// (features/domain, `currentMembershipProvider` +
/// `canUploadContinuityPhotos`), annotated `// AUTHZ-GATE:` there per
/// `scripts/check-authz-gates.sh` (lib/data/ is deliberately exempt — it
/// holds no Riverpod refs). Callers MUST gate before invoking
/// [linkContinuityPhoto], [listContinuityPhotos], or
/// [unlinkContinuityPhoto]; a local denial issues zero network calls.
class SceneShootRepository extends BaseRepository {
  SceneShootRepository(super.api, this.cache);

  final SceneShootCacheDao cache;

  /// Per-day fetch sequence: every [listByDay] call takes the next number
  /// and only the latest call may write its snapshot. The initial load
  /// (view-controller build) runs outside the shared reconciliation
  /// coordinator, so it can complete AFTER a command-triggered refetch;
  /// without sequencing, the older snapshot would replace newer rows and
  /// delete rows the newer snapshot added. Superseded calls still return
  /// their rows (callers render) but never touch the cache.

  final Map<String, int> _daySeq = {};

  // -- Day board projection -------------------------------------------------

  /// Day-board fetch + snapshot-replace (`GET
  /// /v1/shooting-days/{day_id}/scenes/{scene_id}/scene-shoots`).
  ///
  /// The route carries `{scene_id}` but the backend lists by day
  /// (`list_by_shooting_day`, `ORDER BY COALESCE(actual_order,
  /// planned_order) ASC` — the Ist-aware board sequence), so the snapshot
  /// replaces per [dayId] and reads reproduce the server order via the
  /// persisted snapshot ordinal (the client never re-sorts).
  ///
  /// On [Right] applies the day-scoped snapshot and returns the rows. On
  /// [Left] returns the error without touching the cache. Honors [fence]
  /// like every other collection fetch, plus the per-day sequence: a
  /// response superseded by a newer [listByDay] call returns its rows
  /// without writing (stale snapshots never replace or delete).
  Future<Result<List<SceneShootView>>> listByDay(
    String dayId,
    String sceneId, {
    Clock clock = Clock.system,
    CacheWriteFence? fence,
  }) async {
    final seq = (_daySeq[dayId] ?? 0) + 1;
    _daySeq[dayId] = seq;
    final Result<List<SceneShootView>> fetched = await runList(
      () =>
          api.getHandlersApi().listSceneShoots(dayId: dayId, sceneId: sceneId),
      dtoInvalidCode: 'scene_shoot.dto_invalid',
    );
    return fetched.match(
      (err) async => Left<ProblemError, List<SceneShootView>>(err),
      (rows) async {
        if (fence != null && !fence.isCurrentGeneration(fence.generation)) {
          return Right(rows);
        }
        if (_daySeq[dayId] != seq) {
          // Superseded by a newer fetch: rows still flow to the caller,
          // but the cache keeps the newer snapshot.
          return Right(rows);
        }
        try {
          await cache.applySnapshotForDay(dayId, rows, clock.now());
        } on Object {
          return const Left(ProblemError(code: 'cache.write_failed'));
        }
        return Right(rows);
      },
    );
  }

  /// Pure Drift read (no network) of the day's cached shoots in server
  /// order (`snapshotIndex` ASC).
  Future<Result<List<SceneShootView>>> readCached(String dayId) async {
    try {
      return Right(await cache.readByDayOrdered(dayId));
    } on Object {
      return const Left(ProblemError(code: 'cache.read_failed'));
    }
  }

  /// Returns `true` when any cached row of the day is older than [ttl].
  Future<bool> isCacheStale(
    String dayId, {
    Clock clock = Clock.system,
    Duration ttl = kCacheTtl,
  }) => cache.isDayExpired(dayId, ttl, clock: clock);

  /// Single-shoot fetch + cache: GET shoot, upsert on success (scoped to
  /// [dayId]), no mutation on failure.
  Future<Result<SceneShootView>> getAndCache(
    String dayId,
    String sceneId,
    String shootId, {
    Clock clock = Clock.system,
  }) async {
    final fetched = await run(
      () => api.getHandlersApi().getSceneShoot(
        dayId: dayId,
        sceneId: sceneId,
        shootId: shootId,
      ),
      dtoInvalidCode: 'scene_shoot.dto_invalid',
    );
    return fetched.match(
      (err) async => Left<ProblemError, SceneShootView>(err),
      (view) async {
        try {
          await cache.upsert(view, clock.now());
        } on Object {
          return const Left(ProblemError(code: 'cache.write_failed'));
        }
        return Right(view);
      },
    );
  }

  /// Day-board projection refetch without cache write (transport-only;
  /// prefer [listByDay] for screen state).
  Future<Result<List<SceneShootView>>> listShoots(
    String dayId,
    String sceneId,
  ) => runList(
    () => api.getHandlersApi().listSceneShoots(dayId: dayId, sceneId: sceneId),
    dtoInvalidCode: 'scene_shoot.dto_invalid',
  );

  /// Single-shoot fetch (`GET .../scene-shoots/{shoot_id}`).
  Future<Result<SceneShootView>> getShoot(
    String dayId,
    String sceneId,
    String shootId,
  ) => run(
    () => api.getHandlersApi().getSceneShoot(
      dayId: dayId,
      sceneId: sceneId,
      shootId: shootId,
    ),
    dtoInvalidCode: 'scene_shoot.dto_invalid',
  );

  // -- Plan / replan --------------------------------------------------------

  /// Plans a scene shoot (`POST .../scene-shoots`, body `{ planned_order }`).
  Future<Result<IdVersionResponse>> plan(
    String dayId,
    String sceneId,
    PlanSceneShootRequest request,
  ) => run(
    () => api.getHandlersApi().planSceneShoot(
      dayId: dayId,
      sceneId: sceneId,
      planSceneShootRequest: request,
    ),
  );

  /// Replans a shoot's planned position (`PATCH .../scene-shoots/{shoot_id}`).
  Future<Result<int>> replan(
    String dayId,
    String sceneId,
    String shootId,
    ReplanSceneShootRequest request,
  ) => run(
    () => api.getHandlersApi().replanSceneShoot(
      dayId: dayId,
      sceneId: sceneId,
      shootId: shootId,
      replanSceneShootRequest: request,
    ),
  );

  // -- Execution ------------------------------------------------------------

  /// Starts a shoot (`POST .../start`, version echo).
  Future<Result<int>> start(
    String dayId,
    String sceneId,
    String shootId,
    StartSceneShootRequest request,
  ) => run(
    () => api.getHandlersApi().startSceneShoot(
      dayId: dayId,
      sceneId: sceneId,
      shootId: shootId,
      startSceneShootRequest: request,
    ),
  );

  /// Sets the actual execution order (`POST .../actual-order`, version echo).
  Future<Result<int>> setActualOrder(
    String dayId,
    String sceneId,
    String shootId,
    SetActualOrderRequest request,
  ) => run(
    () => api.getHandlersApi().setActualOrder(
      dayId: dayId,
      sceneId: sceneId,
      shootId: shootId,
      setActualOrderRequest: request,
    ),
  );

  /// Finishes a started shoot (`POST .../finish`, version echo).
  Future<Result<int>> finish(
    String dayId,
    String sceneId,
    String shootId,
    FinishSceneShootRequest request,
  ) => run(
    () => api.getHandlersApi().finishSceneShoot(
      dayId: dayId,
      sceneId: sceneId,
      shootId: shootId,
      finishSceneShootRequest: request,
    ),
  );

  /// Skips a shoot (`POST .../skip`, version echo).
  Future<Result<int>> skip(
    String dayId,
    String sceneId,
    String shootId,
    SkipSceneShootRequest request,
  ) => run(
    () => api.getHandlersApi().skipSceneShoot(
      dayId: dayId,
      sceneId: sceneId,
      shootId: shootId,
      skipSceneShootRequest: request,
    ),
  );

  // -- Notes ----------------------------------------------------------------

  /// Adds a note to the shoot (`POST .../notes`).
  Future<Result<int>> addNote(
    String dayId,
    String sceneId,
    String shootId,
    AddNoteRequest request,
  ) => run(
    () => api.getHandlersApi().addSceneShootNote(
      dayId: dayId,
      sceneId: sceneId,
      shootId: shootId,
      addNoteRequest: request,
    ),
  );

  /// Updates a note (`PUT .../notes/{note_id}`, version echo in body).
  Future<Result<int>> updateNote(
    String dayId,
    String sceneId,
    String shootId,
    String noteId,
    UpdateNoteRequest request,
  ) => run(
    () => api.getHandlersApi().updateSceneShootNote(
      dayId: dayId,
      sceneId: sceneId,
      shootId: shootId,
      noteId: noteId,
      updateNoteRequest: request,
    ),
  );

  /// Removes a note (`DELETE .../notes/{note_id}?version=` — backend
  /// issue #341 query-param convention).
  Future<Result<int>> removeNote(
    String dayId,
    String sceneId,
    String shootId,
    String noteId,
    VersionRequest request,
  ) => run(
    () => api.getHandlersApi().removeSceneShootNote(
      dayId: dayId,
      sceneId: sceneId,
      shootId: shootId,
      noteId: noteId,
      versionRequest: request,
    ),
  );

  // -- Continuity (AUTHZ-GATE at the dispatch layer) -------------------------

  /// Links an uploaded photo to the shoot (`POST .../continuity-photos`).
  ///
  /// // AUTHZ-GATE: callers check `canUploadContinuityPhotos` via
  /// `currentMembershipProvider` BEFORE invoking; denial issues zero calls.
  Future<Result<int>> linkContinuityPhoto(
    String dayId,
    String sceneId,
    String shootId,
    LinkContinuityPhotoRequest request,
  ) => run(
    () => api.getHandlersApi().linkContinuityPhoto(
      dayId: dayId,
      sceneId: sceneId,
      shootId: shootId,
      linkContinuityPhotoRequest: request,
    ),
  );

  /// Lists the shoot's continuity photo ids (`GET .../continuity-photos`).
  ///
  /// // AUTHZ-GATE: same capability as upload/unlink — a member who may
  /// not manage continuity photos must not enumerate them. Gate BEFORE
  /// invoking; denial issues zero calls.
  Future<Result<List<String>>> listContinuityPhotos(
    String dayId,
    String sceneId,
    String shootId,
  ) => runList(
    () => api.getHandlersApi().listContinuityPhotos(
      dayId: dayId,
      sceneId: sceneId,
      shootId: shootId,
    ),
    dtoInvalidCode: 'scene_shoot.dto_invalid',
  );

  /// Unlinks a continuity photo (`DELETE .../continuity-photos/{photo_id}
  /// ?version=`, version echo).
  ///
  /// // AUTHZ-GATE: callers check `canUploadContinuityPhotos` via
  /// `currentMembershipProvider` BEFORE invoking; denial issues zero calls.
  Future<Result<int>> unlinkContinuityPhoto(
    String dayId,
    String sceneId,
    String shootId,
    String photoId,
    int version,
  ) => run(
    () => api.getHandlersApi().unlinkContinuityPhoto(
      dayId: dayId,
      sceneId: sceneId,
      shootId: shootId,
      photoId: photoId,
      version: version,
    ),
  );

  // -- Wrap -----------------------------------------------------------------

  /// Wraps the shooting day (`POST /v1/shooting-days/{id}/wrap`).
  /// Guarded day-level action: the day becomes immutable for execution
  /// (no undo in the contract — the confirm copy says so, D3).
  Future<Result<int>> wrap(String dayId, WrapShootingDayRequest request) => run(
    () => api.getHandlersApi().wrapShootingDay(
      id: dayId,
      wrapShootingDayRequest: request,
    ),
  );

  /// Empties the day's shoot rows (sign-out / backend-switch resets).
  Future<Result<void>> clearCache(String dayId) async {
    // Invalidate the fetch sequence first: an in-flight older snapshot
    // completing after the clear must not resurrect deleted rows.
    _daySeq[dayId] = (_daySeq[dayId] ?? 0) + 1;
    try {
      await cache.clearDay(dayId);
      return const Right<ProblemError, void>(null);
    } on Object {
      return const Left(ProblemError(code: 'cache.clear_failed'));
    }
  }

  // -- Reports: JSON read-model fetches ------------------------------------

  /// Dispo (planned / Soll) rows for the day
  /// (`GET /v1/shooting-days/{id}/report/dispo`, server `planned_order ASC`).
  ///
  /// Pure read-model render input (D2): the client renders rows verbatim and
  /// never recomputes flags or finality. A deserialization failure inside
  /// the generated client (e.g. an unknown enum string from a future
  /// backend) strict-rejects to `report.unknown_status` / `report.unknown_shape`
  /// — never throws (AGENTS.md §5: no throw in `data/`).
  Future<Result<List<DispoRow>>> fetchDispoReport(String id) async {
    try {
      final response = await api.getHandlersApi().dispoReport(id: id);
      final data = response.data;
      if (data == null) {
        return const Left(ProblemError(code: 'report.unknown_shape'));
      }
      return Right(data.toList());
    } on DioException catch (e) {
      return Left(_reportDioError(e));
    } on Object catch (e) {
      return Left(strictParseError(e));
    }
  }

  /// Shoot-day (execution / Ist) rows for the day
  /// (`GET /v1/shooting-days/{id}/report/shoot-day`,
  /// server `actual_order ASC NULLS LAST`). Same strict contract as
  /// [fetchDispoReport].
  Future<Result<List<ShootDayRow>>> fetchShootDayReport(String id) async {
    try {
      final response = await api.getHandlersApi().shootDayReport(id: id);
      final data = response.data;
      if (data == null) {
        return const Left(ProblemError(code: 'report.unknown_shape'));
      }
      return Right(data.toList());
    } on DioException catch (e) {
      return Left(_reportDioError(e));
    } on Object catch (e) {
      return Left(strictParseError(e));
    }
  }

  /// Soll-Ist-Vergleich diff report for the day
  /// (`GET /v1/shooting-days/{id}/report/soll-ist`): planned vs actual rows
  /// with moved/missing/skipped/reshot flags and finality from `wrapped_at`.
  ///
  /// The generated client deserializes the DTO; unknown status/flag strings
  /// from a future backend surface as deserialization failures and are
  /// normalized to `report.unknown_status` here so the screen can render
  /// the standard strict-reject error state instead of guessing a meaning.
  Future<Result<SollIstReport>> fetchSollIstReport(String id) async {
    try {
      final response = await api.getHandlersApi().sollIstReport(id: id);
      final data = response.data;
      if (data == null) {
        return const Left(ProblemError(code: 'report.unknown_shape'));
      }
      return Right(data);
    } on DioException catch (e) {
      return Left(_reportDioError(e));
    } on Object catch (e) {
      // A deserialization failure inside the generated client also arrives
      // here: strict-reject unknown statuses, shape-reject the rest.
      return Left(strictParseError(e));
    }
  }

  // -- Reports: per-day PDF fetch (stream-to-temp-file) ----------------------

  /// Fetches the dispo PDF for the day, streaming bytes straight to a temp
  /// file (`Result<File>` on success — never an in-memory buffer, never
  /// Drift, never the persistent documents directory).
  ///
  /// Dispatches via the generated per-day client method only (D1 — never a
  /// hand-built `Dio.get` URL). The path-keyed [PdfStreamingInterceptor] on
  /// the pinned-CA Dio sets `ResponseType.stream` (the generated methods
  /// take no `Options`); each chunk is written to the cache/temporary file
  /// while counting bytes, and [PDF_MAX_BYTES] aborts the transfer via
  /// [cancelToken] the moment it is exceeded (partial file deleted, card
  /// back to idle with `pdf.too_large`).
  ///
  /// // AUTHZ-GATE: callers check `canViewReports` via
  /// // `currentMembershipProvider` BEFORE invoking; denial issues zero calls.
  Future<Result<File>> dispoReportPdf(
    String id, {
    required Directory tempDir,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) => _fetchReportPdf(
    kind: ReportPdfKind.dispo,
    dayId: id,
    tempDir: tempDir,
    cancelToken: cancelToken,
    onReceiveProgress: onReceiveProgress,
    call: (token) => api.getHandlersApi().dispoReportPdf(
      id: id,
      cancelToken: token,
      onReceiveProgress: onReceiveProgress,
    ),
  );

  /// Fetches the shoot-day PDF for the day (same streaming contract as
  /// [dispoReportPdf]).
  ///
  /// // AUTHZ-GATE: callers check `canViewReports` via
  /// // `currentMembershipProvider` BEFORE invoking; denial issues zero calls.
  Future<Result<File>> shootDayReportPdf(
    String id, {
    required Directory tempDir,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) => _fetchReportPdf(
    kind: ReportPdfKind.shootDay,
    dayId: id,
    tempDir: tempDir,
    cancelToken: cancelToken,
    onReceiveProgress: onReceiveProgress,
    call: (token) => api.getHandlersApi().shootDayReportPdf(
      id: id,
      cancelToken: token,
      onReceiveProgress: onReceiveProgress,
    ),
  );

  /// Fetches the planned-vs-actual PDF for the day (same streaming contract
  /// as [dispoReportPdf]).
  ///
  /// // AUTHZ-GATE: callers check `canViewReports` via
  /// // `currentMembershipProvider` BEFORE invoking; denial issues zero calls.
  Future<Result<File>> plannedVsActualReportPdf(
    String id, {
    required Directory tempDir,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) => _fetchReportPdf(
    kind: ReportPdfKind.plannedVsActual,
    dayId: id,
    tempDir: tempDir,
    cancelToken: cancelToken,
    onReceiveProgress: onReceiveProgress,
    call: (token) => api.getHandlersApi().plannedVsActualReportPdf(
      id: id,
      cancelToken: token,
      onReceiveProgress: onReceiveProgress,
    ),
  );

  /// Shared streaming executor for the three per-day PDF fetches: runs the
  /// generated call with an explicit [CancelToken] (so the transfer is
  /// cancellable at any point), extracts the streaming payload, and writes
  /// it to the temp file under the byte-cap contract. Never throws.
  Future<Result<File>> _fetchReportPdf({
    required ReportPdfKind kind,
    required String dayId,
    required Directory tempDir,
    required Future<Response<void>> Function(CancelToken token) call,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) async {
    final token = cancelToken ?? CancelToken();
    try {
      final response = await call(token);
      // The generated methods return `Response<void>` (static `data` is
      // `void`), but at runtime the interceptor-switched streaming shape
      // carries a Dio `ResponseBody`. Extract via `dynamic` — the cast is
      // the documented cost of the no-`Options` generated surface (spec).
      final Object? raw = (response as dynamic).data as Object?;
      return await writePdfResponseDataToTemp(
        data: raw,
        tempDir: tempDir,
        fileName: reportShareFileName(dayLabel: dayId, kind: kind),
        cancelToken: token,
      );
    } on DioException catch (e) {
      return Left(normalizeReportError(e));
    }
  }

  /// Maps a report-route [DioException] to its stable code: an RFC 9457
  /// problem body keeps its `code`, anything else normalizes to
  /// `transport.*` / `http.<status>` (never `detail`).
  ProblemError _reportDioError(DioException e) {
    final data = e.response?.data;
    if (data is Map<String, dynamic> && data['code'] is String) {
      return ProblemError.fromJson(data);
    }
    return normalizeReportError(e);
  }

  // -- Legacy: schedule + archive -------------------------------------------

  Future<Result<int>> schedule(String id, ScheduleSceneRequest request) => run(
    () => api.getHandlersApi().scheduleSceneOnShootingDay(
      id: id,
      scheduleSceneRequest: request,
    ),
  );

  Future<Result<int>> unschedule(
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

  Future<Result<void>> manualArchiveReports(String id) =>
      run(() => api.getHandlersApi().manualArchiveReports(id: id));
}

// -- Command-request builders (pure, unit-tested) -----------------------------

/// Builds a plan request (path ids only in the URL, body `{ planned_order }`).
PlanSceneShootRequest buildPlanSceneShootRequest({
  required String plannedOrder,
}) => PlanSceneShootRequest((b) => b..plannedOrder = plannedOrder);

/// Builds a replan request (new planned key + version echo).
ReplanSceneShootRequest buildReplanSceneShootRequest({
  required String plannedOrder,
  required int version,
}) => ReplanSceneShootRequest(
  (b) => b
    ..plannedOrder = plannedOrder
    ..version = version,
);

/// Builds a start request (version echo, optional client start time).
StartSceneShootRequest buildStartSceneShootRequest({
  required int version,
  DateTime? startDt,
}) => StartSceneShootRequest(
  (b) => b
    ..version = version
    ..startDt = startDt,
);

/// Builds an actual-order request (new actual key + version echo).
SetActualOrderRequest buildSetActualOrderRequest({
  required String actualOrder,
  required int version,
}) => SetActualOrderRequest(
  (b) => b
    ..actualOrder = actualOrder
    ..version = version,
);

/// Builds a finish request (version echo, optional client end time).
FinishSceneShootRequest buildFinishSceneShootRequest({
  required int version,
  DateTime? endDt,
}) => FinishSceneShootRequest(
  (b) => b
    ..version = version
    ..endDt = endDt,
);

/// Builds a skip request (version echo).
SkipSceneShootRequest buildSkipSceneShootRequest({required int version}) =>
    SkipSceneShootRequest((b) => b..version = version);

/// Builds an add-note request (free text + optional client note id).
AddNoteRequest buildAddSceneShootNoteRequest({
  required String body,
  String? noteId,
}) => AddNoteRequest(
  (b) => b
    ..body = body
    ..noteId = noteId,
);

/// Builds an update-note request (new body + version echo).
UpdateNoteRequest buildUpdateSceneShootNoteRequest({
  required String body,
  required int version,
}) => UpdateNoteRequest(
  (b) => b
    ..body = body
    ..version = version,
);

/// Builds a version-echo request for note removal.
VersionRequest buildSceneShootNoteRemoveRequest({required int version}) =>
    VersionRequest((b) => b..version = version);

/// Builds a continuity-link request (uploaded photo id + version echo).
LinkContinuityPhotoRequest buildLinkContinuityPhotoRequest({
  required String photoId,
  required int version,
}) => LinkContinuityPhotoRequest(
  (b) => b
    ..photoId = photoId
    ..version = version,
);

/// Builds a wrap request (version echo).
WrapShootingDayRequest buildWrapShootingDayRequest({required int version}) =>
    WrapShootingDayRequest((b) => b..version = version);

// -- Ist-state renderers (pure: read model in, UI state out — never derived) --

/// True when the day is wrapped (`wrapped_at` present) — the board renders
/// read-only finality (D2). The client never derives finality itself.
bool isShootingDayWrapped(ShootingDayView day) => day.wrappedAt != null;

/// Optimistic overlay edit for start (applied ONLY after the 2xx ack).
SceneShootView applyStartOptimistic(SceneShootView row, {DateTime? startDt}) =>
    row.rebuild(
      (b) => b
        ..status = SceneShootStatus.inProgress
        ..startDt = startDt ?? row.startDt,
    );

/// Optimistic overlay edit for actual-order rearrange.
SceneShootView applyActualOrderOptimistic(
  SceneShootView row,
  String actualOrder,
) => row.rebuild((b) => b..actualOrder = actualOrder);

/// Optimistic overlay edit for replan (planned position).
SceneShootView applyReplanOptimistic(SceneShootView row, String plannedOrder) =>
    row.rebuild((b) => b..plannedOrder = plannedOrder);

/// Optimistic overlay edit for finish.
SceneShootView applyFinishOptimistic(SceneShootView row, {DateTime? endDt}) =>
    row.rebuild(
      (b) => b
        ..status = SceneShootStatus.shot
        ..endDt = endDt ?? row.endDt,
    );

/// Optimistic overlay edit for skip.
SceneShootView applySkipOptimistic(SceneShootView row) =>
    row.rebuild((b) => b..status = SceneShootStatus.skipped);

/// Optimistic overlay edit for add-note: appends the new note view.
SceneShootView applyAddNoteOptimistic(
  SceneShootView row,
  SerializedNote note,
) => row.rebuild((b) => b..notes.add(note));

/// Optimistic overlay edit for update-note: replaces the note body,
/// preserving every other row field.
SceneShootView applyUpdateNoteOptimistic(
  SceneShootView row,
  String noteId,
  String body,
) => row.rebuild(
  (b) => b
    ..notes.replace(
      row.notes.map(
        (n) => n.id == noteId
            ? SerializedNote(
                (nb) => nb
                  ..id = n.id
                  ..body = body,
              )
            : n,
      ),
    ),
);

/// Optimistic overlay edit for remove-note: drops the note by id.
SceneShootView applyRemoveNoteOptimistic(SceneShootView row, String noteId) =>
    row.rebuild(
      (b) => b..notes.replace(row.notes.where((n) => n.id != noteId)),
    );

/// Builds an optimistic note placeholder (server id arrives via reconcile).
SerializedNote optimisticNotePlaceholder({
  required String pendingId,
  required String body,
}) => SerializedNote(
  (b) => b
    ..id = pendingId
    ..body = body,
);

/// Version-fence clear condition: the overlay is dropped ONLY when the
/// refetched projection row satisfies `version >= acknowledgedVersion`.
/// A stale projection carrying an older `version` MUST keep the overlay
/// visible (same discipline as `shouldClearCostumeOverlay`).
bool shouldClearSceneShootOverlay({
  required SceneShootView projection,
  required int acknowledgedVersion,
}) => projection.version >= acknowledgedVersion;

/// Merges projected day-board rows with row-level optimistic overlays keyed
/// by shoot id. Overlays whose fence passes are dropped; stale projections
/// retain the overlay until the fence passes.
List<SceneShootView> mergeSceneShootOverlays({
  required List<SceneShootView> projected,
  required Map<String, ({SceneShootView overlay, int acknowledgedVersion})>
  overlays,
}) {
  if (overlays.isEmpty) return projected;
  final byId = {for (final r in projected) r.id: r};
  final merged = <SceneShootView>[];
  for (final row in projected) {
    final pending = overlays[row.id];
    if (pending == null) {
      merged.add(row);
    } else if (shouldClearSceneShootOverlay(
      projection: row,
      acknowledgedVersion: pending.acknowledgedVersion,
    )) {
      merged.add(row);
    } else {
      merged.add(pending.overlay);
    }
  }
  for (final entry in overlays.entries) {
    if (!byId.containsKey(entry.key)) merged.add(entry.value.overlay);
  }
  return merged;
}

/// Extracts the projected ids for the shared reconciliation coordinator.
Set<String> sceneShootProjectedIds(List<SceneShootView> rows) =>
    rows.map((r) => r.id).toSet();

/// Notes list accessor for the overlay placeholder shape above.
BuiltList<SerializedNote> sceneShootNotesOf(SceneShootView view) => view.notes;
