// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (neuralwatt)

// Tier-1 unit tests (issue #654): the connectivity controller's state
// machine — passive-first detection, single-probe confirmation, exponential
// backoff, and generation-based cancellation. All seams (passive stream,
// HTTP probe, delay) are fakes; NO real `Future.delayed` sleeps and no
// wall-clock timing (deterministic-tests hard rule): the backoff schedule
// is asserted analytically from the durations the fake delay recorded.
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:test/test.dart';

import 'package:frontend_flutter/src/connectivity/connectivity_providers.dart';

/// Drains async event delivery (broadcast-stream callbacks, microtasks and
/// zero-duration timers) WITHOUT any wall-clock wait — deterministic.
Future<void> drainEvents() async {
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Fake passive source: a broadcast controller the tests push events into.
final class FakePassiveSource implements PassiveConnectivitySource {
  final controller = StreamController<List<ConnectivityResult>>.broadcast();

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      controller.stream;

  void emit(List<ConnectivityResult> results) => controller.add(results);

  Future<void> close() => controller.close();
}

/// Fake HTTP probe: pops queued outcomes. An EMPTY queue returns a
/// never-completing probe ("no further outcome scheduled") so a degraded
/// retry chain parks instead of looping forever in a microtask cycle —
/// an empty queue in an assertion then surfaces as an unexpected extra
/// `calls` count, not as a hang.
final class FakeProbe {
  final _queue = <bool>[];
  int calls = 0;

  void enqueue(List<bool> outcomes) => _queue.addAll(outcomes);

  Future<bool> call() {
    calls++;
    if (_queue.isEmpty) return Completer<bool>().future;
    return Future<bool>.value(_queue.removeAt(0));
  }
}

/// Controllable delay: records requested durations; completions can be
/// released manually (cancellation tests) or auto-completed (schedule
/// tests) — never a real sleep.
final class FakeDelay {
  final recorded = <Duration>[];
  final _pending = <Completer<void>>[];

  /// When true, every requested delay completes immediately (in a
  /// microtask) — the backoff chain then runs to its queued probes.
  bool autoComplete = true;

  Future<void> call(Duration duration) {
    recorded.add(duration);
    final completer = Completer<void>();
    _pending.add(completer);
    if (autoComplete) {
      scheduleMicrotask(() {
        if (!completer.isCompleted) completer.complete();
      });
    }
    return completer.future;
  }

  /// Completes all pending delays manually (cancellation tests).
  void flush() {
    for (final c in _pending) {
      if (!c.isCompleted) c.complete();
    }
    _pending.clear();
  }
}

({
  ProviderContainer container,
  FakePassiveSource source,
  FakeProbe probe,
  FakeDelay delay,
})
_harness() {
  final source = FakePassiveSource();
  final probe = FakeProbe();
  final delay = FakeDelay();
  final container = ProviderContainer(
    overrides: [
      passiveConnectivitySourceProvider.overrideWithValue(source),
      connectivityHttpProbeProvider.overrideWithValue(probe.call),
      connectivityDelayProvider.overrideWithValue(delay.call),
    ],
  );
  return (container: container, source: source, probe: probe, delay: delay);
}

void main() {
  tearDown(() {});

  group('connectivityProbeBackoff (analytical schedule, issue #654)', () {
    test('starts at the 15 s base and doubles per consecutive failure', () {
      expect(connectivityProbeBackoff(1), const Duration(seconds: 15));
      expect(connectivityProbeBackoff(2), const Duration(seconds: 30));
      expect(connectivityProbeBackoff(3), const Duration(seconds: 60));
      expect(connectivityProbeBackoff(4), const Duration(seconds: 120));
      expect(connectivityProbeBackoff(6), const Duration(seconds: 480));
      expect(
        connectivityProbeBackoff(7),
        const Duration(minutes: 10),
        reason: '15 s × 2⁶ = 16 min exceeds the 10 min cap',
      );
    });

    test('caps at 10 minutes — no unbounded growth', () {
      expect(connectivityProbeBackoff(8), const Duration(minutes: 10));
      expect(connectivityProbeBackoff(50), const Duration(minutes: 10));
      expect(connectivityProbeBackoff(1000), const Duration(minutes: 10));
    });
  });

  group('ConnectivityController state transitions', () {
    test('starts online; the FIRST carrier event runs one confirmation probe '
        '(issue #667 D2), then healthy stays passive (battery rule)', () async {
      final h = _harness();
      addTearDown(h.container.dispose);
      expect(
        h.container.read(connectivityControllerProvider),
        ConnectivityStatus.online,
      );

      // The optimistic `online` was never confirmed — the first passive
      // carrier event confirms the route once (this is the degraded
      // cold-start path that previously never fired).
      h.probe.enqueue([true]);
      h.source.emit([ConnectivityResult.wifi]);
      await drainEvents();

      expect(
        h.container.read(connectivityControllerProvider),
        ConnectivityStatus.online,
      );
      expect(h.probe.calls, 1, reason: 'exactly one bootstrap confirmation');
      expect(h.delay.recorded, isEmpty);

      // Once confirmed, healthy stays passive: no more probes.
      h.source.emit([ConnectivityResult.mobile]);
      await drainEvents();
      expect(
        h.container.read(connectivityControllerProvider),
        ConnectivityStatus.online,
      );
      expect(
        h.probe.calls,
        1,
        reason: 'no probe while the confirmed signal is healthy',
      );
      expect(h.delay.recorded, isEmpty);
    });

    test('cold start, carrier present, probe fails → degraded (pill visible, '
        'issue #667 D2: Wi-Fi on, backend unreachable)', () async {
      final h = _harness();
      addTearDown(h.container.dispose);
      h.container.read(connectivityControllerProvider);
      // Park the backoff chain manually: the assertion is the FIRST
      // failed probe's state + schedule, not the retry loop.
      h.delay.autoComplete = false;

      h.probe.enqueue([false]);
      h.source.emit([ConnectivityResult.wifi]);
      await drainEvents();

      // The on-device test-session defect: Wi-Fi on but the backend
      // stopped — the pill must show (degraded), not stay silently
      // 'online'.
      expect(
        h.container.read(connectivityControllerProvider),
        ConnectivityStatus.degraded,
      );
      expect(h.probe.calls, 1);
      // The exponential-backoff re-probe is scheduled.
      expect(h.delay.recorded, [connectivityProbeBackoff(1)]);
    });

    test('carrier lost → offline immediately, no probe', () async {
      final h = _harness();
      addTearDown(h.container.dispose);
      expect(
        h.container.read(connectivityControllerProvider),
        ConnectivityStatus.online,
      );

      h.source.emit([ConnectivityResult.none]);
      await drainEvents();

      expect(
        h.container.read(connectivityControllerProvider),
        ConnectivityStatus.offline,
      );
      expect(h.probe.calls, 0);
    });

    test('reconnection confirmed by a successful probe → online', () async {
      final h = _harness();
      addTearDown(h.container.dispose);
      h.container.read(connectivityControllerProvider);
      h.source.emit([ConnectivityResult.none]);
      await drainEvents();
      h.probe.enqueue([true]);

      h.source.emit([ConnectivityResult.wifi]);
      await drainEvents();

      expect(
        h.container.read(connectivityControllerProvider),
        ConnectivityStatus.online,
      );
      expect(h.probe.calls, 1);
      expect(
        h.delay.recorded,
        isEmpty,
        reason: 'success never schedules a retry',
      );
    });

    test('failed probe downgrades to degraded; retries back off exponentially then recover', () async {
      final h = _harness();
      addTearDown(h.container.dispose);
      h.container.read(connectivityControllerProvider);
      h.source.emit([ConnectivityResult.none]);
      await drainEvents();
      // Captive portal: carrier present, three probes fail, then success.
      h.probe.enqueue([false, false, false, true]);
      h.delay.autoComplete = false; // step the backoff chain manually

      h.source.emit([ConnectivityResult.wifi]);
      await drainEvents();
      expect(
        h.container.read(connectivityControllerProvider),
        ConnectivityStatus.degraded,
      );
      expect(h.probe.calls, 1);
      expect(h.delay.recorded, [const Duration(seconds: 15)]);

      h.delay.flush();
      await drainEvents();
      expect(
        h.container.read(connectivityControllerProvider),
        ConnectivityStatus.degraded,
      );
      expect(h.delay.recorded, [
        const Duration(seconds: 15),
        const Duration(seconds: 30),
      ]);

      h.delay.flush();
      await drainEvents();
      expect(h.delay.recorded, [
        const Duration(seconds: 15),
        const Duration(seconds: 30),
        const Duration(seconds: 60),
      ], reason: 'one backed-off retry per failure — no fixed heartbeat');

      h.delay.flush();
      await drainEvents();
      expect(
        h.container.read(connectivityControllerProvider),
        ConnectivityStatus.online,
      );
      expect(h.probe.calls, 4);
    });

    test('degraded state keeps the pill visible (captive portal)', () async {
      final h = _harness();
      addTearDown(h.container.dispose);
      h.container.read(connectivityControllerProvider);
      h.source.emit([ConnectivityResult.none]);
      await drainEvents();
      h.probe.enqueue([false]);

      h.source.emit([ConnectivityResult.wifi]);
      await drainEvents();

      expect(
        h.container.read(connectivityControllerProvider),
        ConnectivityStatus.degraded,
      );
      expect(connectivityShowsPill(ConnectivityStatus.degraded), isTrue);
      expect(connectivityShowsPill(ConnectivityStatus.online), isFalse);
      expect(connectivityShowsPill(ConnectivityStatus.offline), isTrue);
    });

    test('carrier lost mid-retry cancels the pending probe chain (no request storms)', () async {
      final h = _harness();
      addTearDown(h.container.dispose);
      h.container.read(connectivityControllerProvider);
      h.source.emit([ConnectivityResult.none]);
      await drainEvents();
      h.probe.enqueue([false]);
      h.delay.autoComplete = false; // hold the first backoff window open

      h.source.emit([ConnectivityResult.wifi]);
      await drainEvents();
      expect(h.probe.calls, 1);
      expect(
        h.container.read(connectivityControllerProvider),
        ConnectivityStatus.degraded,
      );

      // Carrier lost again while the backed-off retry is pending.
      h.source.emit([ConnectivityResult.none]);
      await drainEvents();
      expect(
        h.container.read(connectivityControllerProvider),
        ConnectivityStatus.offline,
      );

      // The held backoff window elapses — the stale chain must NOT probe.
      h.delay.flush();
      await drainEvents();
      expect(
        h.probe.calls,
        1,
        reason: 'generation counter canceled the stale retry',
      );

      // A fresh reconnection runs a fresh confirmation probe.
      h.probe.enqueue([true]);
      h.source.emit([ConnectivityResult.wifi]);
      await drainEvents();
      expect(
        h.container.read(connectivityControllerProvider),
        ConnectivityStatus.online,
      );
      expect(h.probe.calls, 2);
    });

    test('backoff resets after a confirmed reconnection', () async {
      final h = _harness();
      addTearDown(h.container.dispose);
      h.container.read(connectivityControllerProvider);
      h.source.emit([ConnectivityResult.none]);
      await drainEvents();
      h.probe.enqueue([false, true]); // one failure, then recover
      h.source.emit([ConnectivityResult.wifi]);
      await drainEvents();
      await drainEvents();
      expect(
        h.container.read(connectivityControllerProvider),
        ConnectivityStatus.online,
      );

      // Second offline→online cycle: the schedule restarts at the base.
      h.source.emit([ConnectivityResult.none]);
      await drainEvents();
      h.probe.enqueue([false, true]);
      h.source.emit([ConnectivityResult.wifi]);
      await drainEvents();
      await drainEvents();

      expect(h.probe.calls, 4);
      expect(
        h.delay.recorded.last,
        const Duration(seconds: 15),
        reason: 'the failed-attempt counter reset after recovery',
      );
    });
  });
}
