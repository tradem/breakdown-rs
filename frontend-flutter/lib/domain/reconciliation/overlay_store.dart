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

  /// Whether this overlay belongs to a **create** (`true`) or to an **update**
  /// of a row that was already projected (`false`).
  ///
  /// The two shapes do not share a completion signal (issue #917):
  ///
  /// * a **create** overlay's id only appears in the projection once the create
  ///   reached the read model, so **id presence completes it** and an absent id
  ///   means "not there yet" → keep it;
  /// * an **update** overlay's row was projected *before* the command, so id
  ///   presence says nothing. It is fenced by [acknowledgedVersion], and an
  ///   **absent** row means the edited row is gone (deleted, or out of the
  ///   fetched scope) → the overlay completes.
  ///
  /// Every implementation states which it is, with the reason at the
  /// declaration: an update overlay that claims `true` regresses to the
  /// flash-the-old-value defect of issue #917, a create overlay that claims
  /// `false` disappears before its row is projected.
  bool get isCreate;

  /// The aggregate version the command's 2xx acknowledgement returned.
  ///
  /// An **update** overlay MUST supply it: the fence keeps the overlay until
  /// the fetched row reaches that version. A **create** overlay may carry it
  /// (its optimistic row echoes it for follow-up commands) — its drop is
  /// decided by id presence, not by this version.
  ///
  /// `null` therefore only appears on create overlays that have no version to
  /// echo (the form-derived types).
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

/// Replaces any overlay with the same `id`, but **keeps the create identity**
/// of a pending create shell (issue #917).
///
/// A follow-up edit can land before the create reached the read model (the
/// detail sheet of a freshly created row is one tap away). Its overlay carries
/// the same id, so [overlayAdd] replaces the shell — and an overlay flagged as
/// an *update* would then be completed by the very next fetch that omits the
/// id, making the new row vanish before its first projection. Preserving the
/// flag keeps the id-presence completion of the shell it replaces.
///
/// [asCreate] rebuilds the overlay flagged as a create; it is only invoked when
/// a pending create overlay with the same id exists.
List<E> overlayAddPreservingCreate<E extends ReconciliationOverlay>(
  List<E> state,
  E overlay,
  E Function(E overlay) asCreate,
) {
  if (overlay.isCreate) return overlayAdd(state, overlay);
  final replacesCreate = state.any((o) => o.id == overlay.id && o.isCreate);
  return overlayAdd(state, replacesCreate ? asCreate(overlay) : overlay);
}

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
/// * a **create** overlay ([ReconciliationOverlay.isCreate]) is kept while the
///   projection does not carry its id (the create has not projected yet) and
///   completes as soon as it does;
/// * an **update** overlay is completed by the row's **absence** — its row is
///   gone, so no later fetch could ever reach the acknowledged version — and
///   otherwise kept until the fetched row reaches
///   [ReconciliationOverlay.acknowledgedVersion]. A **lagging** row
///   (pre-command version) keeps it, so a row-level update never flashes the
///   old value back and its old `version` never becomes the echo of the next
///   command.
///
/// An empty successful fetch is the same rule with no rows at all: every
/// update overlay's row is gone, every create overlay simply has not projected
/// yet. A FAILED fetch never reaches this function (the runner only hands over
/// the rows a successful refetch produced), so absence is evidence, never a
/// transport artifact.
List<E> overlayDropProjectedRows<E extends ReconciliationOverlay>(
  List<E> state,
  List<ProjectedRow> rows,
) {
  final projectedVersions = {for (final row in rows) row.id: row.version};
  return state.where((o) {
    final projected = projectedVersions[o.id];
    // Create: presence completes, absence means "not projected yet".
    if (o.isCreate) return projected == null;
    // Update: absence means the edited row is gone, so the overlay completes.
    if (projected == null) return false;
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
/// Per-aggregate implementations (e.g. `SeasonOverlays`) mix this onto their
/// own notifier with a concrete `E`; there is deliberately no global overlay
/// store — each screen owns its rows. Kept in its own notifier so the overlay
/// survives projection rebuilds (the controller's `build()` re-runs whenever
/// the projection changes; inlining the list there would wipe it).
///
/// A **mixin**, not an `abstract class … extends Notifier`: the per-aggregate
/// stores are `@Riverpod` codegen providers (AGENTS.md §1 / D3), a generated
/// notifier must extend its own generated `_$ClassName` base, and Dart allows
/// only one superclass — a mixin can be applied on top of it without competing.
/// [AnyNotifier] is Riverpod's public notifier root (the supertype of both the
/// hand-written `Notifier` and the generated `$Notifier`), and it supplies the
/// `state` this base mutates. The mixin owns no state initialization, so every
/// concrete store still declares its own `build()` (issue #905).
mixin OverlayStore<E extends ReconciliationOverlay>
    on AnyNotifier<List<E>, List<E>> {
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
