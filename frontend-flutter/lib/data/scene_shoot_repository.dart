// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark (pi)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:built_collection/built_collection.dart';

import '../core/result.dart';
import 'base_repository.dart';

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
  const SceneShootRepository(super.api);

  // -- Day board projection -------------------------------------------------

  /// Day-board projection refetch
  /// (`GET /v1/shooting-days/{day_id}/scenes/{scene_id}/scene-shoots`,
  /// server order — the client never re-sorts).
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

  // -- Legacy: schedule + reports -------------------------------------------

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

  Future<Result<void>> dispoReportPdf(String id) =>
      run(() => api.getHandlersApi().dispoReportPdf(id: id));

  Future<Result<void>> plannedVsActualReportPdf(String id) =>
      run(() => api.getHandlersApi().plannedVsActualReportPdf(id: id));

  Future<Result<void>> shootDayReportPdf(String id) =>
      run(() => api.getHandlersApi().shootDayReportPdf(id: id));

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
