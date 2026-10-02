// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: qwen3.8-flash (opencode-go)
// Co-authored-by: glm-5.3-flash (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';

import '../../core/problem_error.dart';

/// Per-day finality on the report index, read DIRECTLY from the day's own
/// `ShootingDayView.wrappedAt` (server-derived — the same field the
/// day-scoped report's `final` banner derives from, spec
/// `flutter-reports-index`). The client never re-computes, infers or
/// aggregates finality: there is NO episode-, season- or scene-level
/// verdict anywhere in this state shape.
enum ReportDayFinality {
  /// `wrapped_at` present → `abschließend`.
  wrapped,

  /// `wrapped_at` null → `offen`.
  open,
}

/// Derives the per-day finality from the day's own DTO — the ONE place
/// this mapping exists (`wrappedAt` present → final, null → open).
ReportDayFinality reportDayFinality(ShootingDayView day) =>
    day.wrappedAt == null ? ReportDayFinality.open : ReportDayFinality.wrapped;

/// One row rendered by `ReportsIndexScreen`: the projected
/// [ShootingDayView] plus its derived per-day finality.
class ReportsIndexRow {
  const ReportsIndexRow({required this.day});

  /// The generated read DTO (`breakdown_api` `ShootingDayView`);
  /// authoritative, in the day list's server order (`order_key ASC` —
  /// never re-sorted client-side).
  final ShootingDayView day;

  /// Per-day finality derived from [day] `wrappedAt` in exactly one place
  /// ([reportDayFinality]) — never recomputed at a call site.
  ReportDayFinality get finality => reportDayFinality(day);
}

/// Controller state shape for the report index (seasons reference
/// pattern).
class ReportsIndexScreenState {
  const ReportsIndexScreenState({
    required this.rows,
    this.isLoading = false,
    this.hasPendingOverlay = false,
    this.isStale = false,
    this.commandError,
    this.gateDenial,
  });

  /// One row per PROJECTED shooting day, in the day list's server order
  /// (`order_key ASC`). Optimistic overlay rows are excluded: an
  /// unprojected day carries no server-derived `wrappedAt`, so it has no
  /// honest finality to render (the day list stays the place to watch the
  /// overlay reconcile).
  final List<ReportsIndexRow> rows;

  /// The day list's initial projection fetch is still in flight. An empty
  /// [rows] here means "not loaded yet", NOT "this scope has no days" — the
  /// screen renders a progress indicator instead of the confirmed-empty
  /// message (spec `flutter-reports-index`: the empty state is for a scope
  /// whose day list resolved empty).
  final bool isLoading;

  /// The day list holds at least one optimistic (unprojected) day.
  /// Such a day is never listed on the index (it has no server-derived
  /// `wrappedAt`, so no honest finality), but the index must show the day
  /// list's pending indicator rather than claiming the scope is empty or
  /// current.
  final bool hasPendingOverlay;

  /// The day list's stale indicator, inherited when a refresh fails while
  /// cached rows stay visible (projection-lag semantics, unchanged).
  final bool isStale;

  /// The day list's fetch failure keyed on the stable problem `code`.
  final ProblemError? commandError;

  /// The client-side AUTHZ-GATE denial (`report.forbidden` on a resolved
  /// denial, `membership.pending` / `membership.unavailable` while the
  /// membership is unresolved) — rendered with ZERO requests on denial.
  /// `null` when the gate passes.
  final ProblemError? gateDenial;

  /// `false` while the gate is denied or unresolved: pull-to-refresh, the
  /// error-view retry and row navigation are all disabled, so a denied
  /// scope issues no request and never enters a day report (spec: the gate
  /// runs BEFORE the user navigates into a day report).
  bool get gateOpen => gateDenial == null;
}
