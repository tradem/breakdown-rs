// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

import 'reconciliation_scheduler.dart';

/// One row of a freshly refetched read projection, reduced to the two fields
/// the shared reconciliation runner reasons about.
///
/// The runner stays aggregate-agnostic: it never reads a DTO, it only asks
/// "does the projection carry this id, and at which aggregate version". Each
/// controller's refetch seam maps its own projection rows into these
/// (issue #916 replaced a bare id list with this shape, because a
/// single-intent update needs the version to detect a lagging projector).
class ProjectedRow {
  const ProjectedRow({required this.id, required this.version});

  /// Server-assigned row id — the overlay-reconciliation key.
  final String id;

  /// The aggregate `version` the projection currently carries for this row
  /// (the value the next optimistic-locking command must echo).
  final int version;
}

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
/// - an **overlay-less** pass (single-intent update / archive, no optimistic
///   row) retries on the acknowledged aggregate version instead of on id
///   presence, so a lagging projector cannot leave a stale `version` behind
///   (issue #916);
/// - late acknowledgements during a pass get a dedicated follow-up pass so
///   every acknowledgement gets a post-ack projection fetch.
///
/// The runner is deliberately decoupled from the overlay store type: each
/// controller wires its own (family or global) overlay notifier through the
/// plain callbacks below, so per-aggregate notifiers stay independent (no
/// global overlay store) while sharing one tested retry implementation.
class ReconciliationCoordinator {
  ReconciliationCoordinator({
    required this._refetchProjection,
    required this._hasOverlays,
    required this._markAllReconciling,
    required this._dropProjectedIds,
    required this._markAllStale,
    required this._scheduler,
    required this._isAlive,
  });

  /// Re-runs the injected list-fetch seam (which writes Drift on success,
  /// never on failure) and returns the fresh projection rows, or `null` on
  /// `Err`.
  final Future<List<ProjectedRow>?> Function() _refetchProjection;

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

  /// Acknowledgement generation counter: bumped on every acknowledgement
  /// (overlay insert *and* overlay-less version echo). A pass captures the
  /// value it started at and, on completion, runs a dedicated follow-up if a
  /// later acknowledgement arrived mid-pass.
  int _ackGeneration = 0;

  /// The acknowledgement an overlay-less pass still has to confirm: the row
  /// the command acted on and the aggregate version its 2xx body returned.
  ///
  /// `null` means nothing is pending — a plain refresh, or a command whose
  /// overlay already carries the completion signal.
  ({String id, int version})? _pendingAck;

  /// Records an acknowledgement (call after every 2xx-gated command) so a
  /// late acknowledgement during an in-flight pass triggers a dedicated
  /// follow-up pass.
  ///
  /// [id] + [version] are the acted-on row and the aggregate version the 2xx
  /// body returned. They are required for every **overlay-less** command —
  /// a single-intent update (`reschedule`, `rename`, `reorder`, `unschedule`,
  /// a category/contact correction) or an archive, i.e. anything that inserts
  /// no optimistic row because the row is already projected. Such a command
  /// has no id to wait for, so without the version the pass stops after one
  /// fetch, the projection keeps the OLD row *and its old `version`*, and the
  /// next command built from that row fails with
  /// `409 concurrency.version-mismatch` although nothing conflicts
  /// (issue #916).
  ///
  /// Overlay-creating commands call it without arguments and keep their
  /// existing id-based completion signal.
  void ackReceived({String? id, int? version}) {
    if (id != null && version != null) {
      _pendingAck = (id: id, version: version);
    }
    _ackGeneration++;
  }

  /// Bounded-retry reconciliation pass: refetch the projection up to
  /// [kMaxReconcileAttempts] times, dropping overlays whose id the
  /// projection now carries (or, for an overlay-less acknowledgement, whose
  /// version has caught up). On exhaustion the overlays are retained and
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
    final arrivedLate = generationAtStart != _ackGeneration;
    // An overlay-less acknowledgement leaves no overlay behind, so it needs
    // its own trigger (issue #916).
    if (arrivedLate && (_hasOverlays() || _pendingAck != null)) {
      return reconcile();
    }
  }

  Future<void> _runPass() async {
    // Every ref-touching step is liveness-guarded: the owner may have been
    // recycled across an async gap (watch-triggered invalidation), in which
    // case this stale pass aborts quietly and the live instance carries on.
    if (!_isAlive()) return;
    if (!_hasOverlays()) {
      await _runOverlaylessPass();
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
      final rows = await _refetchProjection();
      if (!_isAlive()) return;
      if (rows != null) {
        _dropProjectedIds(rows.map((row) => row.id).toSet());
      }
      if (!_hasOverlays()) return;
    }
    if (!_isAlive()) return;
    _markAllStale(kReconcileStaleWarningCode);
  }

  /// Overlay-less pass (issue #916): a single-intent update or archive inserts
  /// no optimistic row, so "does the projection carry the id" is already true
  /// before the fetch and cannot be the completion signal. The pass compares
  /// the acknowledged aggregate version with the fetched row's version and
  /// re-fetches within the SAME [kMaxReconcileAttempts] budget — never a new
  /// one, never a wall-clock loop: the injectable [ReconciliationScheduler]
  /// drives every tick, so the retries stay deterministic in tests.
  Future<void> _runOverlaylessPass() async {
    final ack = _pendingAck;
    if (ack == null) {
      // Nothing acknowledged (screen open, pull-to-refresh, post-archive
      // refresh): one fetch is the whole pass, exactly as before.
      await _refetchProjection();
      return;
    }
    for (var attempt = 0; attempt < kMaxReconcileAttempts; attempt++) {
      if (!_isAlive()) return;
      if (attempt > 0) {
        await _scheduler().tick(attempt);
      }
      if (!_isAlive()) return;
      final rows = await _refetchProjection();
      if (!_isAlive()) return;
      // A failed fetch (`null`) is not evidence of lag OR of freshness — the
      // attempt is spent and the next one asks again.
      if (rows != null) {
        final projected = _versionOf(rows, ack.id);
        // A row at (or beyond) the acknowledged version has caught up; a row
        // the projection no longer carries at all was archived/deleted by the
        // command. Both end the pass.
        if (projected == null || projected >= ack.version) {
          _consumeAck(ack);
          return;
        }
      }
    }
    // Budget spent: the older row the last fetch wrote stays in place — Drift
    // keeps the stale projection, nothing is discarded silently (D3) and the
    // row's stale `version` is exactly what the next command will echo, which
    // is why the 409 path (`ShootingDaysController` re-reads the projection on
    // `concurrency.version-mismatch`) stays as the last resort. Consuming the
    // acknowledgement here keeps one lag from slowing every later refresh: the
    // next pull-to-refresh starts a fresh bounded pass.
    if (!_isAlive()) return;
    _consumeAck(ack);
  }

  /// Clears [ack] as consumed, unless a newer acknowledgement already
  /// replaced it while this pass was in flight (it owns the next pass).
  void _consumeAck(({String id, int version}) ack) {
    if (_pendingAck == ack) _pendingAck = null;
  }

  /// The aggregate version the projection carries for [id], or `null` when it
  /// does not carry the row at all.
  static int? _versionOf(List<ProjectedRow> rows, String id) {
    for (final row in rows) {
      if (row.id == id) return row.version;
    }
    return null;
  }
}
