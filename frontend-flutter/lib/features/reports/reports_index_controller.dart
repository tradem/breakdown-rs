// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../auth/membership/capability.dart';
import '../../auth/membership/membership_providers.dart';
import '../../core/problem_error.dart';
import '../shooting_days/shooting_days_controller.dart';
import '../shooting_days/shooting_days_state.dart';
import 'reports_index_state.dart';

part 'reports_index_controller.g.dart';

/// Episode- and season-scoped family key: the episode id addresses the day
/// list the index projects from; the season id scopes the membership gate.
/// Both come from the navigation context the user is acting on (the
/// threaded parent `BlockView.seasonId` and the acted-on `EpisodeView`) —
/// never from a second read to fill in context (client CQRS boundary).
class ReportIndexScope {
  const ReportIndexScope({required this.episodeId, required this.seasonId});

  final String episodeId;
  final String seasonId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReportIndexScope &&
          other.episodeId == episodeId &&
          other.seasonId == seasonId;

  @override
  int get hashCode => Object.hash(episodeId, seasonId);
}

/// Local AUTHZ-GATE decision for the index: the denial code when the
/// destination (the day-scoped report screen) must be refused, or `null`
/// when the gate may pass.
///
/// The check is local and non-fetching (mirrors the day-scoped reports
/// gate): `AsyncLoading`, `AsyncError`, and unknown capability strings all
/// deny locally — `canViewReports` follows the backend-computed
/// `hasActiveCostumeRoleInSeason` flag only, so an unknown capability
/// string never enables the gate. The server remains authoritative on
/// every gated handler.
ProblemError? _indexGate(AsyncValue<SeasonMembershipDto> membership) =>
    switch (membership) {
      AsyncLoading() => const ProblemError(code: 'membership.pending'),
      AsyncError() => const ProblemError(code: 'membership.unavailable'),
      AsyncData(:final value) =>
        value.canViewReports
            ? null
            : const ProblemError(code: 'report.forbidden'),
    };

/// `ReportsIndexController(scope)` — a pure projection of the episode's
/// existing day-list controller state (`shootingDaysControllerProvider`),
/// plus the season-scoped membership gate.
///
/// The index issues ZERO HTTP requests of its own: it watches
/// `shootingDaysControllerProvider(episodeId)` and projects its
/// `ProjectedShootingDayRow`s into index rows — no new fetch, no new Drift
/// table, no new repository (design decision 2). It inherits the day list's
/// projection-lag semantics unchanged: cached rows stay visible and
/// stale-indicated on a failed refresh, `AsyncError` carries the problem
/// `code`, and pull-to-refresh reconciles through the same controller.
// AUTHZ-GATE: the gate is the SAME client-side check the day-scoped report
// screen runs (`currentMembershipProvider` → `canViewReports`), evaluated
// BEFORE pushing that screen; it is a pre-check for the destination — the
// index itself fetches no protected data and issues zero requests on
// denial.
@riverpod
class ReportsIndexController extends _$ReportsIndexController {
  @override
  ReportsIndexScreenState build(ReportIndexScope scope) {
    // AUTHZ-GATE: local non-fetching pre-check over the same membership
    // source the per-day report screen gates on. Rendered keyed on the
    // stable problem `code` with zero requests on denial.
    final gateDenial = _indexGate(
      ref.watch(currentMembershipProvider(scope.seasonId)),
    );

    final dayList = ref.watch(shootingDaysControllerProvider(scope.episodeId));
    // Only PROJECTED days are listed (design decision 4): an optimistic
    // overlay row carries no `ShootingDayView`, therefore no
    // server-derived `wrappedAt` and no honest finality. The screen shows
    // the day list's stale/pending indicator instead.
    final projectedRows = switch (dayList.projected) {
      AsyncData(:final value) =>
        value.map((day) => ReportsIndexRow(day: day)).toList(),
      // While loading/erroring with cached rows present, render the
      // retained rows (identical data, identical stale semantics).
      _ => [
        for (final row in dayList.rows)
          if (row is ProjectedShootingDayRow) ReportsIndexRow(day: row.day),
      ],
    };

    return ReportsIndexScreenState(
      rows: projectedRows,
      isStale: dayList.isStale,
      commandError: switch (dayList.projected) {
        AsyncError(:final error) =>
          error is ProblemError ? error : const ProblemError(code: 'unknown'),
        _ => dayList.commandError,
      },
      gateDenial: gateDenial,
    );
  }

  /// Pull-to-refresh delegates to the SHARED day-list controller — the
  /// index has no fetch of its own (design decision 2).
  Future<void> refresh(String episodeId) async {
    await ref
        .read(shootingDaysControllerProvider(episodeId).notifier)
        .refresh();
  }
}
