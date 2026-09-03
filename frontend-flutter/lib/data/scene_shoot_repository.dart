// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: longcat-2.0 (opencode-go)
// Co-authored-by: hy4-preview (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';

import '../core/result.dart';
import 'base_repository.dart';

/// Repository for the `SceneShoot` aggregate boundary — Soll/Ist reports
/// (planned vs actual, moved/missing/skipped/reshot flags) and the report-PDF
/// generation endpoints.
///
/// Every report/archive endpoint is shooting-day-scoped, so each generated
/// method takes a required `id` that the wrappers below forward unchanged.
/// (Until issue #333 declared the path parameter in the backend OpenAPI spec,
/// the generated client had no `id` argument and emitted a literal `{id}` in
/// the request URL.)
class SceneShootRepository extends BaseRepository {
  const SceneShootRepository(super.api);

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
