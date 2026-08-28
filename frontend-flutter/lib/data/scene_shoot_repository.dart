// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: longcat-2.0 (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';

import '../core/result.dart';
import 'base_repository.dart';

/// Repository for the `SceneShoot` aggregate boundary — Soll/Ist reports
/// (planned vs actual, moved/missing/skipped/reshot flags) and the report-PDF
/// generation endpoints.
///
/// NOTE: the report-PDF methods ([dispoReportPdf], [plannedVsActualReportPdf],
/// [shootDayReportPdf]) currently take NO path parameter in the generated
/// client because the backend OpenAPI spec declares `{id}` on the route without
/// defining it (tracked as a backend spec defect). They are wrapped faithfully
/// here as the generated client exposes them; once the spec defines the
/// parameter, the generated signature (and this wrapper) will gain the `id`.
class SceneShootRepository extends BaseRepository {
  const SceneShootRepository(super.api);

  Future<Result<int>> schedule(String id, ScheduleSceneRequest request) => run(
    () => api.getHandlersApi().scheduleSceneOnShootingDay(
      id: id,
      scheduleSceneRequest: request,
    ),
  );

  Future<Result<int>> unschedule(String id, String shootingDayId) => run(
    () => api.getHandlersApi().unscheduleSceneFromShootingDay(
      id: id,
      shootingDayId: shootingDayId,
    ),
  );

  Future<Result<void>> dispoReportPdf() =>
      run(() => api.getHandlersApi().dispoReportPdf());

  Future<Result<void>> plannedVsActualReportPdf() =>
      run(() => api.getHandlersApi().plannedVsActualReportPdf());

  Future<Result<void>> shootDayReportPdf() =>
      run(() => api.getHandlersApi().shootDayReportPdf());

  Future<Result<void>> manualArchiveReports() =>
      run(() => api.getHandlersApi().manualArchiveReports());
}
