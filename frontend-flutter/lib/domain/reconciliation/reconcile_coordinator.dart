// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'reconciliation_scheduler.dart';

/// Shared single-flight + acknowledgement-generation reconciliation runner
/// (`flutter-hierarchy-navigation` D2, extracted verbatim-in-behavior from
/// `features/seasons/seasons_controller.dart`).
///
/// Rules preserved for every aggregate:
/// - overlay only after 2xx; controller state only (never Drift);
/// - bounded retries ([kMaxReconcileAttempts], injectable scheduler — tests
///   stay deterministic);
/// - exhaustion retains the overlay with a stale indicator +
///   pull-to-refresh (never silently discarded);
/// - late acknowledgements during a pass get a dedicated follow-up pass so
///   every overlay gets a post-ack projection fetch.
///
/// The runner is deliberately decoupled from the overlay store type: each
/// controller wires its own (family or global) overlay notifier through the
/// plain callbacks below, so per-aggregate notifiers stay independent (no
/// global overlay store) while sharing one tested retry implementation.
class ReconciliationCoordinator {
  ReconciliationCoordinator({
    required this._refetchProjectedIds,
    required this._hasOverlays,
    required this._markAllReconciling,
    required this._dropProjectedIds,
    required this._markAllStale,
    required this._scheduler,
    required this._isAlive,
  });

  /// Re-runs the injected list-fetch seam (which writes Drift on success,
  /// never on failure) and returns the fresh projected ids, or `null` on
  /// `Err`.
  final Future<List<String>?> Function() _refetchProjectedIds;

  /// Overlay bookkeeping of the owning controller (resolved fresh on every
  /// access so a disposed/rebuilt notifier is never cached across passes).
  final bool Function() _hasOverlays;
  final void Function() _markAllReconciling;
  final void Function(Set<String> ids) _dropProjectedIds;
  final void Function(String warning) _markAllStale;

  /// Resolves the (injectable, fakeable) backoff scheduler.
  final ReconciliationScheduler Function() _scheduler;

  /// Whether the owning controller is still alive. A rebuild recycles the
  /// owner's `Ref`; a pass started before the rebuild must die quietly on
  /// its next step instead of throwing on the detached ref — the fresh
  /// instance owns reconciliation from then on.
  final bool Function() _isAlive;

  /// Single-flight guard so concurrent create/refresh calls join one
  /// bounded reconciliation pass instead of storming the projection.
  Future<void>? _inFlight;

  /// Acknowledgement generation counter: bumped on every optimistic overlay
  /// insert. A pass captures the value it started at and, on completion,
  /// runs a dedicated follow-up if a later acknowledgement arrived mid-pass.
  int _ackGeneration = 0;

  /// Records an optimistic overlay insert (call after every 2xx-gated
  /// insert) so a late acknowledgement during an in-flight pass triggers a
  /// dedicated follow-up pass.
  void ackReceived() => _ackGeneration++;

  /// Bounded-retry reconciliation pass: refetch the projection up to
  /// [kMaxReconcileAttempts] times, dropping overlays whose id the
  /// projection now carries. On exhaustion the overlays are retained and
  /// marked `stale` — Drift still contains no unprojected row.
  ///
  /// Also used by pull-to-refresh: a stale overlay gets a fresh bounded
  /// pass. Single-flight: concurrent callers join the in-flight pass.
  Future<void> reconcile() => _inFlight ??= _runWithFollowUp();

  /// Runs one bounded retry pass and, if a later acknowledgement arrived
  /// while it was in flight, chains a dedicated follow-up pass. The
  /// follow-up is returned from the `.then` callback so the single-flight
  /// future the caller awaits includes it; the guard is cleared in an arrow
  /// `whenComplete` to keep the result handled (breakdown_lints
  /// `discard_result`).
  Future<void> _runWithFollowUp() async {
    final generationAtStart = _ackGeneration;
    try {
      await _runPass();
    } finally {
      // Cleared in `finally` (not after the follow-up check) so concurrent
      // callers join exactly one pass; the result is handled via `await`
      // (breakdown_lints `discard_result`).
      _inFlight = null;
    }
    if (!_isAlive()) return;
    if (generationAtStart != _ackGeneration && _hasOverlays()) {
      return reconcile();
    }
  }

  Future<void> _runPass() async {
    // Every ref-touching step is liveness-guarded: the owner may have been
    // recycled across an async gap (watch-triggered invalidation), in which
    // case this stale pass aborts quietly and the live instance carries on.
    if (!_isAlive()) return;
    if (!_hasOverlays()) {
      await _refetchProjectedIds();
      return;
    }
    if (!_isAlive()) return;
    _markAllReconciling();
    for (var attempt = 0; attempt < kMaxReconcileAttempts; attempt++) {
      if (!_isAlive()) return;
      if (attempt > 0) {
        await _scheduler().tick(attempt);
      }
      if (!_isAlive()) return;
      final ids = await _refetchProjectedIds();
      if (!_isAlive()) return;
      if (ids != null) {
        _dropProjectedIds(ids.toSet());
      }
      if (!_hasOverlays()) return;
    }
    if (!_isAlive()) return;
    _markAllStale(kReconcileStaleWarning);
  }
}
