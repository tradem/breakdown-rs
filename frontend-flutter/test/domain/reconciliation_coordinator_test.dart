// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

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

class _Harness {
  _Harness({this.projectedIds, this.fetchError = false});

  List<String>? projectedIds;
  bool fetchError;
  bool alive = true;
  final overlays = <String, String>{}; // id -> status
  final scheduler = _ManualScheduler();
  int refetches = 0;

  late final ReconciliationCoordinator coordinator = ReconciliationCoordinator(
    refetchProjectedIds: () async {
      refetches++;
      if (fetchError) return null;
      return projectedIds;
    },
    hasOverlays: () => overlays.isNotEmpty,
    markAllReconciling: () => overlays.updateAll((_, _) => 'reconciling'),
    dropProjectedIds: (ids) =>
        overlays.removeWhere((id, _) => ids.contains(id)),
    markAllStale: (warning) => overlays.updateAll((_, _) => 'stale:$warning'),
    scheduler: () => scheduler,
    isAlive: () => alive,
  );

  void ack(String id) {
    overlays[id] = 'acknowledged';
    coordinator.ackReceived();
  }

  void carry(String id) => projectedIds = [...?projectedIds, id];

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
      final h = _Harness(projectedIds: ['a']);
      await h.coordinator.reconcile();
      expect(h.refetches, 1);
      expect(h.scheduler.ticks, 0);
      expect(h.overlays, isEmpty);
    });

    test(
      'success drops the overlay when the projection carries the id',
      () async {
        final h = _Harness(projectedIds: []);
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
        final h = _Harness(projectedIds: [], fetchError: true);
        h.ack('n1');
        await h.drain(h.coordinator.reconcile());
        expect(h.overlays.keys, ['n1']);
        expect(h.overlays['n1'], 'stale:$kReconcileStaleWarning');
        // Bounded budget: attempts 1..3 each requested one tick.
        expect(h.scheduler.ticks, kMaxReconcileAttempts - 1);
        expect(h.refetches, kMaxReconcileAttempts);
      },
    );

    test(
      'a late acknowledgement triggers a dedicated follow-up pass',
      () async {
        final h = _Harness(projectedIds: [], fetchError: true);
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
      final h = _Harness(projectedIds: [], fetchError: true);
      h.ack('n1');
      final first = h.coordinator.reconcile();
      final second = h.coordinator.reconcile();
      await h.drain(Future.wait([first, second]));
      // One pass only — same generation, no follow-up.
      expect(h.scheduler.ticks, kMaxReconcileAttempts - 1);
    });

    test('a recycled owner aborts its stale pass quietly', () async {
      final h = _Harness(projectedIds: [], fetchError: true);
      h.ack('n1');
      h.alive = false; // the owner was recycled before the pass ran
      await h.coordinator.reconcile(); // must not throw
      expect(h.overlays['n1'], 'acknowledged');
      expect(h.scheduler.ticks, 0);
    });

    test('a null refetch (Err) never drops overlays', () async {
      final h = _Harness(projectedIds: ['n1'], fetchError: true);
      h.ack('n1');
      await h.drain(h.coordinator.reconcile());
      // Every attempt failed, so the id never arrived via a fetch.
      expect(h.overlays.keys, ['n1']);
    });
  });
}
