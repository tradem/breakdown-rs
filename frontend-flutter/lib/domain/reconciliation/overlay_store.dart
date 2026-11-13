// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'reconcile_coordinator.dart' show ProjectedRow;

/// Reconciliation status of an optimistic overlay row (spec
/// `flutter-first-screen`, Design Decision D2; shared by every hierarchy
/// screen — `flutter-hierarchy-navigation` D2).
///
/// * [acknowledged] — the create `POST` returned 2xx; the row is shown
///   immediately, before the projection catches up.
/// * [reconciling]  — the bounded-retry projection refetch is in flight.
/// * [stale]        — the refetch exhausted its retries; the overlay is
///   retained with a non-fatal warning and pull-to-refresh is offered
///   (never discarded silently, D3).
enum OverlayStatus { acknowledged, reconciling, stale }

/// Minimal shape every per-aggregate overlay entry implements so the shared
/// [OverlayStore] can bookkeep it without knowing the aggregate.
abstract class ReconciliationOverlay {
  /// Server-assigned id (from the command's 2xx acknowledgement).
  String get id;

  /// The aggregate version the command's 2xx acknowledgement returned, or
  /// `null` when the id alone IS the completion signal.
  ///
  /// The two shapes are not interchangeable (issue #917):
  ///
  /// * **Create overlay** — the id appears in the projection only once the
  ///   create reached the read model, so id presence is a real signal and
  ///   `null` is correct. The optimistic fields are display-only values
  ///   carried from the submitted form, not an aggregate version.
  /// * **Update overlay** — the row is already projected, so id presence is
  ///   true *before* the fetch and says nothing. Such an overlay MUST return
  ///   the acknowledged version; the generic [overlayDropProjectedRows] fence
  ///   then keeps it until the fetched row reaches it.
  ///
  /// Every implementation states which of the two it is, with the reason at
  /// the declaration — an update overlay that returns `null` silently
  /// regresses to the flash-the-old-value defect of issue #917.
  int? get acknowledgedVersion;

  /// Current reconciliation status.
  OverlayStatus get status;

  /// Non-fatal warning shown when [status] is [OverlayStatus.stale].
  String? get warning;

  /// Returns a copy with the reconciliation fields replaced.
  ReconciliationOverlay copyWithStatus({
    OverlayStatus? status,
    String? warning,
    bool clearWarning = false,
  });
}

/// Replaces any overlay with the same `id` (a re-acked create).
List<E> overlayAdd<E extends ReconciliationOverlay>(List<E> state, E overlay) =>
    [...state.where((o) => o.id != overlay.id), overlay];

/// Every overlay still awaiting projection confirmation moves to
/// `reconciling` (acknowledged *and* previously-stale rows get another
/// bounded pass on pull-to-refresh).
List<E> overlayMarkAllReconciling<E extends ReconciliationOverlay>(
  List<E> state,
) => [
  for (final o in state)
    o.copyWithStatus(status: OverlayStatus.reconciling) as E,
];

/// Version-fenced drop of every overlay the freshly fetched projection has
/// caught up with (issue #917).
///
/// * the projected row is **absent** → the overlay is kept (a create that has
///   not reached the read model yet);
/// * the overlay carries **no** [ReconciliationOverlay.acknowledgedVersion] →
///   id presence completes it (create overlay: the id only appears once the
///   create is projected);
/// * the overlay carries one → it is dropped only when the fetched row reaches
///   that version. A **lagging** row (pre-command version) keeps the overlay,
///   so a row-level update never flashes the old value back and its old
///   `version` never becomes the echo of the next command.
///
/// Nothing is dropped on a `null` fetch: the caller only invokes this with the
/// rows a successful refetch produced.
List<E> overlayDropProjectedRows<E extends ReconciliationOverlay>(
  List<E> state,
  List<ProjectedRow> rows,
) {
  if (rows.isEmpty) return state;
  final projectedVersions = {for (final row in rows) row.id: row.version};
  return state.where((o) {
    final projected = projectedVersions[o.id];
    if (projected == null) return true;
    final acknowledged = o.acknowledgedVersion;
    if (acknowledged == null) return false;
    return projected < acknowledged;
  }).toList();
}

/// Bounded-retry exhaustion: retain the overlays, marked `stale` with the
/// non-fatal warning (never silently discarded).
List<E> overlayMarkAllStale<E extends ReconciliationOverlay>(
  List<E> state,
  String warning,
) => [
  for (final o in state)
    o.copyWithStatus(status: OverlayStatus.stale, warning: warning) as E,
];

/// Ephemeral optimistic overlay store (D2: controller state, NOT Drift).
///
/// Per-aggregate subclasses (e.g. `SeasonOverlays`) extend this with a
/// concrete `E`; there is deliberately no global overlay store — each
/// screen owns its rows. Kept in its own [Notifier] so the overlay survives
/// projection rebuilds (the controller's `build()` re-runs whenever the
/// projection changes; inlining the list there would wipe it).
abstract class OverlayStore<E extends ReconciliationOverlay>
    extends Notifier<List<E>> {
  @override
  List<E> build() => const [];

  /// Replaces any overlay with the same `id` (a re-acked create).
  void add(E overlay) => state = overlayAdd(state, overlay);

  /// Every overlay still awaiting projection confirmation moves to
  /// `reconciling` (acknowledged *and* previously-stale rows get another
  /// bounded pass on pull-to-refresh).
  void markAllReconciling() => state = overlayMarkAllReconciling(state);

  /// Version-fenced drop against the rows the reconciliation pass just
  /// fetched (D2 + issue #917). A fresh success removes the entry; it is never
  /// marked `stale` on success, and a lagging row never removes it.
  void dropProjectedRows(List<ProjectedRow> rows) {
    state = overlayDropProjectedRows(state, rows);
  }

  /// Bounded-retry exhaustion: retain the overlays, marked `stale` with the
  /// non-fatal warning (D3 — never silently discarded).
  void markAllStale(String warning) =>
      state = overlayMarkAllStale(state, warning);
}
