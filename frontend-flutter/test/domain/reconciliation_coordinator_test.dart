// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/domain/reconciliation/overlay_store.dart';
import 'package:frontend_flutter/domain/reconciliation/reconcile_coordinator.dart';
import 'package:frontend_flutter/domain/reconciliation/reconciliation_scheduler.dart';

/// Controllable backoff (deterministic-tests rule): each [tick] parks on a
/// completer until the test calls [advanceAll].
class _ManualScheduler extends ReconciliationScheduler {
  final List<Completer<void>> _pending = [];
  int ticks = 0;

  @override
  Future<void> tick(int attempt) {
    ticks++;
    final completer = Completer<void>();
    _pending.add(completer);
    return completer.future;
  }

  void advanceAll() {
    for (final c in List.of(_pending)) {
      c.complete();
    }
    _pending.clear();
  }
}

class _TestOverlay implements ReconciliationOverlay {
  const _TestOverlay({
    required this.id,
    required this.acknowledgedVersion,
    required this.status,
    this.warning,
  });

  @override
  final String id;

  /// `null` for a create overlay (id presence completes it), the acked
  /// aggregate version for an update overlay (version fence, issue #917).
  @override
  final int? acknowledgedVersion;

  @override
  final OverlayStatus status;

  @override
  final String? warning;

  @override
  _TestOverlay copyWithStatus({
    OverlayStatus? status,
    String? warning,
    bool clearWarning = false,
  }) => _TestOverlay(
    id: id,
    acknowledgedVersion: acknowledgedVersion,
    status: status ?? this.status,
    warning: clearWarning ? null : (warning ?? this.warning),
  );
}

class _Harness {
  _Harness({Map<String, int>? projected, this.fetchError = false, this.script})
    : projected = projected ?? {};

  /// id -> aggregate version the projection currently carries.
  Map<String, int> projected;

  /// Optional scripted sequence of projection snapshots: each fetch takes the
  /// next entry (the last one repeats), so a test can let the projector catch
  /// up between attempts without a wall clock.
  final List<Map<String, int>>? script;
  bool fetchError;
  bool alive = true;

  /// The overlay store, with the REAL generic helpers under test: a create
  /// overlay (`acknowledgedVersion == null`) completes on id presence, an
  /// update overlay only on the version fence (issue #917).
  final overlays = <String, _TestOverlay>{};
  final scheduler = _ManualScheduler();
  int refetches = 0;
  int _scriptCursor = 0;

  late final ReconciliationCoordinator coordinator = ReconciliationCoordinator(
    refetchProjection: () async {
      refetches++;
      if (fetchError) return null;
      final rows = _nextProjection();
      return [
        for (final row in rows.entries)
          ProjectedRow(id: row.key, version: row.value),
      ];
    },
    hasOverlays: () => overlays.isNotEmpty,
    markAllReconciling: () =>
        _replace(overlayMarkAllReconciling(overlays.values.toList())),
    dropProjectedRows: (rows) =>
        _replace(overlayDropProjectedRows(overlays.values.toList(), rows)),
    markAllStale: (warning) =>
        _replace(overlayMarkAllStale(overlays.values.toList(), warning)),
    scheduler: () => scheduler,
    isAlive: () => alive,
  );

  void _replace(List<_TestOverlay> next) {
    overlays
      ..clear()
      ..addEntries(next.map((o) => MapEntry(o.id, o)));
  }

  Map<String, int> _nextProjection() {
    final scripted = script;
    if (scripted == null) return projected;
    final snapshot = scripted[min(_scriptCursor, scripted.length - 1)];
    _scriptCursor++;
    return snapshot;
  }

  /// A create overlay: its id only appears in the projection once the create
  /// reached the read model, so id presence is the completion signal.
  void ack(String id) {
    overlays[id] = _TestOverlay(
      id: id,
      acknowledgedVersion: null,
      status: OverlayStatus.acknowledged,
    );
    coordinator.ackReceived();
  }

  /// An UPDATE overlay: the row is already projected, so only the acked
  /// version can confirm it (issue #917).
  void ackUpdate(String id, {required int version}) {
    overlays[id] = _TestOverlay(
      id: id,
      acknowledgedVersion: version,
      status: OverlayStatus.acknowledged,
    );
    coordinator.ackReceived();
  }

  void carry(String id) => projected = {...projected, id: 1};

  /// Drives the manual scheduler until [pass] completes (bounded, no
  /// wall-clock gating).
  Future<void> drain(Future<void> pass) async {
    var done = false;
    pass.then((_) => done = true);
    for (var i = 0; i < kMaxReconcileAttempts * 4 && !done; i++) {
      scheduler.advanceAll();
      await pumpEventQueue();
    }
    await pass;
  }
}

void main() {
  group('ReconciliationCoordinator (shared runner, D2/D3)', () {
    test('no overlays: a plain projection refresh, no ticks', () async {
      final h = _Harness(projected: {'a': 1});
      await h.coordinator.reconcile();
      expect(h.refetches, 1);
      expect(h.scheduler.ticks, 0);
      expect(h.overlays, isEmpty);
    });

    test(
      'success drops the overlay when the projection carries the id',
      () async {
        final h = _Harness();
        h.ack('n1');
        h.carry('n1');
        await h.drain(h.coordinator.reconcile());
        expect(h.overlays, isEmpty);
        // First attempt runs immediately — no backoff tick needed.
        expect(h.scheduler.ticks, 0);
      },
    );

    test(
      'retry exhaustion retains the overlay marked stale + warning',
      () async {
        final h = _Harness(fetchError: true);
        h.ack('n1');
        await h.drain(h.coordinator.reconcile());
        expect(h.overlays.keys, ['n1']);
        expect(h.overlays['n1']?.status, OverlayStatus.stale);
        expect(h.overlays['n1']?.warning, kReconcileStaleWarningCode);
        // Bounded budget: attempts 1..3 each requested one tick.
        expect(h.scheduler.ticks, kMaxReconcileAttempts - 1);
        expect(h.refetches, kMaxReconcileAttempts);
      },
    );

    test(
      'a late acknowledgement triggers a dedicated follow-up pass',
      () async {
        final h = _Harness(fetchError: true);
        h.ack('a');
        final pass = h.coordinator.reconcile();
        h.ack('b');
        await h.drain(pass);
        // Two full bounded passes (not one shared attempt budget).
        expect(h.scheduler.ticks, 2 * (kMaxReconcileAttempts - 1));
        expect(h.overlays.keys, containsAll(['a', 'b']));
      },
    );

    test('concurrent callers join the single in-flight pass', () async {
      final h = _Harness(fetchError: true);
      h.ack('n1');
      final first = h.coordinator.reconcile();
      final second = h.coordinator.reconcile();
      await h.drain(Future.wait([first, second]));
      // One pass only — same generation, no follow-up.
      expect(h.scheduler.ticks, kMaxReconcileAttempts - 1);
    });

    test('a recycled owner aborts its stale pass quietly', () async {
      final h = _Harness(fetchError: true);
      h.ack('n1');
      h.alive = false; // the owner was recycled before the pass ran
      await h.coordinator.reconcile(); // must not throw
      expect(h.overlays['n1']?.status, OverlayStatus.acknowledged);
      expect(h.scheduler.ticks, 0);
    });

    test('a null refetch (Err) never drops overlays', () async {
      final h = _Harness(projected: {'n1': 1}, fetchError: true);
      h.ack('n1');
      await h.drain(h.coordinator.reconcile());
      // Every attempt failed, so the id never arrived via a fetch.
      expect(h.overlays.keys, ['n1']);
    });
  });

  // Issue #916: an overlay-less command (single-intent update / archive) has
  // no optimistic row to wait for, so the pass reconciles on the acknowledged
  // aggregate version instead of id presence.
  group('overlay-less version gate (issue #916)', () {
    test('an in-budget freshening spends a tick per retry and ends up to '
        'date', () async {
      // Attempt 0 and 1 see the pre-command version, attempt 2 has caught up.
      final h = _Harness(
        script: [
          {'d1': 1},
          {'d1': 1},
          {'d1': 2},
        ],
      );
      h.coordinator.ackReceived(id: 'd1', version: 2);
      await h.drain(h.coordinator.reconcile());
      expect(h.refetches, 3);
      expect(h.scheduler.ticks, 2);
      // The row the last fetch produced carries the acknowledged version.
      expect(h._nextProjection()['d1'], 2);
      expect(h.overlays, isEmpty);
    });

    test('a lagging projection keeps the stale row through the whole budget '
        'and retains it without a silent discard', () async {
      final h = _Harness(
        script: [
          {'d1': 1},
        ],
      );
      h.coordinator.ackReceived(id: 'd1', version: 2);
      await h.drain(h.coordinator.reconcile());
      // The existing budget, not a new one, and never a wall-clock loop.
      expect(h.refetches, kMaxReconcileAttempts);
      expect(h.scheduler.ticks, kMaxReconcileAttempts - 1);
      // Nothing was dropped or fabricated: the projection still serves the
      // pre-command row and there is no overlay to show a stale badge on.
      expect(h._nextProjection()['d1'], 1);
      expect(h.overlays, isEmpty);
    });

    test(
      'one exhausted acknowledgement does not slow every later refresh',
      () async {
        final h = _Harness(
          script: [
            {'d1': 1},
          ],
        );
        h.coordinator.ackReceived(id: 'd1', version: 2);
        await h.drain(h.coordinator.reconcile());
        expect(h.refetches, kMaxReconcileAttempts);
        // The acknowledgement was consumed on exhaustion, so the next
        // pull-to-refresh is a single fetch again (a later ack re-arms it).
        h.refetches = 0;
        await h.drain(h.coordinator.reconcile());
        expect(h.refetches, 1);
        expect(h.scheduler.ticks, kMaxReconcileAttempts - 1);
      },
    );

    test('a row the projection no longer carries ends the pass at once '
        '(archive / delete)', () async {
      final h = _Harness(
        script: [
          {'other': 1},
        ],
      );
      h.coordinator.ackReceived(id: 'd1', version: 2);
      await h.drain(h.coordinator.reconcile());
      expect(h.refetches, 1);
      expect(h.scheduler.ticks, 0);
    });

    test('a fetch Err is not evidence that the projection caught up', () async {
      final h = _Harness(fetchError: true);
      h.coordinator.ackReceived(id: 'd1', version: 2);
      await h.drain(h.coordinator.reconcile());
      expect(h.refetches, kMaxReconcileAttempts);
      expect(h.scheduler.ticks, kMaxReconcileAttempts - 1);
    });

    test(
      'a late overlay-less acknowledgement gets its own follow-up pass',
      () async {
        // Both rows stay behind their acknowledged version for the whole
        // script, so each pass spends its full budget.
        final h = _Harness(
          script: [
            {'d1': 1, 'd2': 2},
          ],
        );
        h.coordinator.ackReceived(id: 'd1', version: 2);
        final pass = h.coordinator.reconcile();
        h.coordinator.ackReceived(id: 'd2', version: 3);
        await h.drain(pass);
        // Two bounded passes: the second one belongs to the later ack.
        expect(h.refetches, 2 * kMaxReconcileAttempts);
        expect(h.scheduler.ticks, 2 * (kMaxReconcileAttempts - 1));
      },
    );

    test(
      'an acknowledgement without a version keeps the single-fetch pass',
      () async {
        final h = _Harness(projected: {'d1': 1});
        // The overlay-creating commands keep their id-based signal.
        h.coordinator.ackReceived();
        await h.drain(h.coordinator.reconcile());
        expect(h.refetches, 1);
        expect(h.scheduler.ticks, 0);
      },
    );
  });

  // Issue #917: an UPDATE overlay is the sibling gap of #916. Its id is in the
  // projection BEFORE the fetch, so an id-presence drop discarded it after the
  // first fetch even though the projection still served the pre-command
  // version — the screen fell back to the old value and the old `version`.
  group('update-overlay version fence (issue #917)', () {
    test(
      'a lagging projection keeps the overlay and its value through the whole '
      'budget, then retains it as stale',
      () async {
        final h = _Harness(
          script: [
            {'s1': 1},
          ],
        );
        h.ackUpdate('s1', version: 2);
        await h.drain(h.coordinator.reconcile());
        // The existing budget, not a new one, and never a wall-clock loop.
        expect(h.refetches, kMaxReconcileAttempts);
        expect(h.scheduler.ticks, kMaxReconcileAttempts - 1);
        // Never dropped on a stale row: the optimistic value stays visible
        // and is retained (not discarded) when the budget is spent.
        expect(h.overlays['s1']?.status, OverlayStatus.stale);
        expect(h.overlays['s1']?.warning, kReconcileStaleWarningCode);
        expect(h.overlays['s1']?.acknowledgedVersion, 2);
      },
    );

    test('an in-budget freshening drops the overlay', () async {
      // Attempt 0 sees the pre-command version, attempt 1 has caught up.
      final h = _Harness(
        script: [
          {'s1': 1},
          {'s1': 2},
        ],
      );
      h.ackUpdate('s1', version: 2);
      await h.drain(h.coordinator.reconcile());
      expect(h.refetches, 2);
      expect(h.scheduler.ticks, 1);
      expect(h.overlays, isEmpty);
    });

    test(
      'a row already at the acknowledged version drops on the first fetch',
      () async {
        final h = _Harness(
          script: [
            {'s1': 3},
          ],
        );
        h.ackUpdate('s1', version: 2);
        await h.drain(h.coordinator.reconcile());
        expect(h.refetches, 1);
        expect(h.scheduler.ticks, 0);
        expect(h.overlays, isEmpty);
      },
    );

    test('a create overlay keeps completing on id presence', () async {
      final h = _Harness(
        script: [
          {'c1': 1},
        ],
      );
      // No acknowledged version: the id only appears once the create is
      // projected, so presence IS the signal (issue #917 criteria 2).
      h.ack('c1');
      await h.drain(h.coordinator.reconcile());
      expect(h.refetches, 1);
      expect(h.overlays, isEmpty);
    });

    test('a row the projection does not carry keeps the overlay', () async {
      final h = _Harness(
        script: [
          {'other': 1},
        ],
      );
      h.ackUpdate('s1', version: 2);
      await h.drain(h.coordinator.reconcile());
      expect(h.overlays['s1']?.status, OverlayStatus.stale);
    });
  });
}
