// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// Drops overlays whose id is now carried by a projected row — a clean
/// replace-by-id. A fresh reconciliation success removes the entry; it is
/// never marked `stale` on success.
List<E> overlayDropProjectedIds<E extends ReconciliationOverlay>(
  List<E> state,
  Set<String> projectedIds,
) {
  if (projectedIds.isEmpty) return state;
  return state.where((o) => !projectedIds.contains(o.id)).toList();
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

  /// Drops overlays whose id is now carried by a projected row — a clean
  /// replace-by-id (D2). A fresh reconciliation success removes the entry;
  /// it is never marked `stale` on success.
  void dropProjectedIds(Set<String> projectedIds) {
    state = overlayDropProjectedIds(state, projectedIds);
  }

  /// Bounded-retry exhaustion: retain the overlays, marked `stale` with the
  /// non-fatal warning (D3 — never silently discarded).
  void markAllStale(String warning) =>
      state = overlayMarkAllStale(state, warning);
}
