// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (neuralwatt)

// Tier-1 unit tests (issue #657): the backend health controller's state
// machine — tier mapping from `GET /v1/health` outcomes, the conservative
// 60 s healthy interval, exponential backoff for non-healthy outcomes,
// generation-based cancellation, and the connectivity-offline pause. All
// seams (probe, delay, passive connectivity stream) are fakes; NO real
// `Future.delayed` sleeps and no wall-clock timing (deterministic-tests
// hard rule): the schedule is asserted analytically from the durations the
// fake delay recorded.
import 'dart:async';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:test/test.dart';

import 'package:frontend_flutter/src/connectivity/connectivity_providers.dart';
import 'package:frontend_flutter/src/health/backend_health_providers.dart';

/// Drains async event delivery (broadcast-stream callbacks, microtasks and
/// zero-duration timers) WITHOUT any wall-clock wait — deterministic.
Future<void> drainEvents() async {
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Fake passive connectivity source: a broadcast controller the tests push
/// events into (drives the connectivity controller the health controller
/// watches).
final class FakePassiveSource implements PassiveConnectivitySource {
  final controller = StreamController<List<ConnectivityResult>>.broadcast();

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      controller.stream;

  void emit(List<ConnectivityResult> results) => controller.add(results);

  Future<void> close() => controller.close();
}

/// Fake health probe: pops queued outcomes. An EMPTY queue returns a
/// never-completing probe ("no further outcome scheduled") so a retry chain
/// parks instead of looping forever in a microtask cycle. When [throwWith]
/// is set, the call fails ASYNCHRONOUSLY with that error (the real code
/// path for transport exceptions).
final class FakeProbe {
  final _queue = <BackendHealthOutcome>[];
  int calls = 0;

  Object? throwWith;

  void enqueue(List<BackendHealthOutcome> outcomes) => _queue.addAll(outcomes);

  Future<BackendHealthOutcome> call() {
    calls++;
    if (throwWith != null) return Future.error(throwWith!);
    if (_queue.isEmpty) return Completer<BackendHealthOutcome>().future;
    return Future<BackendHealthOutcome>.value(_queue.removeAt(0));
  }
}

/// Controllable delay: records requested durations; completions can be
/// released manually (cancellation tests) or auto-completed (schedule
/// tests) — never a real sleep.
final class FakeDelay {
  final recorded = <Duration>[];
  final _pending = <Completer<void>>[];

  /// When true, every requested delay completes immediately (in a
  /// microtask) — the poll chain then runs to its queued probes.
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
_harness({
  // Outcomes the FIRST probe call (fired by the harness's own build) pops.
  List<BackendHealthOutcome> initial = const [],
  Object? probeThrows,
  bool autoCompleteDelay = true,
}) {
  final source = FakePassiveSource();
  final probe = FakeProbe();
  final delay = FakeDelay();
  probe.throwWith = probeThrows;
  delay.autoComplete = autoCompleteDelay;
  probe.enqueue(initial);
  final container = ProviderContainer(
    overrides: [
      passiveConnectivitySourceProvider.overrideWithValue(source),
      // The connectivity controller (watched by the health controller) must
      // never reach appConfigProvider in tests: its HTTP confirmation probe
      // is overridden with a never-resolving fake and its delay seam with a
      // never-completing fake (no real timers).
      connectivityHttpProbeProvider.overrideWithValue(
        () => Completer<bool>().future,
      ),
      connectivityDelayProvider.overrideWithValue(
        (duration) => Completer<void>().future,
      ),
      backendHealthProbeProvider.overrideWithValue(probe.call),
      backendHealthDelayProvider.overrideWithValue(delay.call),
    ],
  );
  // An ACTIVE listener makes dependency-change rebuilds eager — the
  // production pill always watches the controller, and without a listener
  // Riverpod defers rebuilds to the next read (which would make probe-call
  // counts order-dependent in the tests).
  container.listen(backendHealthControllerProvider, (_, _) {});
  return (container: container, source: source, probe: probe, delay: delay);
}

void main() {
  group('backendHealthRetryBackoff (analytical schedule, issue #657)', () {
    test('starts at the 15 s base and doubles per consecutive failure', () {
      expect(backendHealthRetryBackoff(1), const Duration(seconds: 15));
      expect(backendHealthRetryBackoff(2), const Duration(seconds: 30));
      expect(backendHealthRetryBackoff(3), const Duration(seconds: 60));
      expect(backendHealthRetryBackoff(4), const Duration(seconds: 120));
      expect(backendHealthRetryBackoff(6), const Duration(seconds: 480));
      expect(
        backendHealthRetryBackoff(7),
        const Duration(minutes: 10),
        reason: '15 s × 2⁶ = 16 min exceeds the 10 min cap',
      );
    });

    test('caps at 10 minutes — no unbounded growth', () {
      expect(backendHealthRetryBackoff(8), const Duration(minutes: 10));
      expect(backendHealthRetryBackoff(50), const Duration(minutes: 10));
      expect(backendHealthRetryBackoff(1000), const Duration(minutes: 10));
    });
  });

  group('BackendHealthController state transitions', () {
    test(
      'initial state is null (no data yet) and parks on a pending probe',
      () async {
        final h = _harness();
        addTearDown(h.container.dispose);
        // First read builds the controller: one probe in flight, no answer.
        expect(h.container.read(backendHealthControllerProvider), isNull);
        expect(h.probe.calls, 1);
        expect(h.delay.recorded, isEmpty);
      },
    );

    test(
      'healthy report → healthy tier; next poll waits the 60 s interval',
      () async {
        final h = _harness(
          initial: const [BackendHealthReported(HealthStatus.healthy)],
          // Park the post-answer interval so the chain cannot race ahead to
          // a second probe before the assertion (deterministic, no clock).
          autoCompleteDelay: false,
        );
        addTearDown(h.container.dispose);

        await drainEvents();

        expect(
          h.container.read(backendHealthControllerProvider),
          BackendHealthTier.healthy,
        );
        expect(h.probe.calls, 1);
        expect(h.delay.recorded, [backendHealthPollInterval]);
      },
    );

    test(
      'degraded report → degraded tier; re-probes back off exponentially',
      () async {
        final h = _harness(
          initial: const [
            BackendHealthReported(HealthStatus.degraded),
            BackendHealthReported(HealthStatus.degraded),
          ],
          autoCompleteDelay: false, // step the backoff chain manually
        );
        addTearDown(h.container.dispose);

        await drainEvents();
        expect(
          h.container.read(backendHealthControllerProvider),
          BackendHealthTier.degraded,
        );
        expect(h.delay.recorded, [const Duration(seconds: 15)]);

        h.delay.flush();
        await drainEvents();
        expect(h.delay.recorded, [
          const Duration(seconds: 15),
          const Duration(seconds: 30),
        ], reason: 'one backed-off retry per non-healthy outcome');
        expect(h.probe.calls, 2);
      },
    );

    test(
      'unhealthy report (HTTP 503 body) → its OWN tier, not offline',
      () async {
        final h = _harness(
          initial: const [BackendHealthReported(HealthStatus.unhealthy)],
        );
        addTearDown(h.container.dispose);

        await drainEvents();

        expect(
          h.container.read(backendHealthControllerProvider),
          BackendHealthTier.unhealthy,
        );
        expect(h.delay.recorded, [const Duration(seconds: 15)]);
      },
    );

    test(
      'unreachable probe → offline tier (deterministic, no crash)',
      () async {
        final h = _harness(initial: const [BackendHealthUnreachable()]);
        addTearDown(h.container.dispose);

        await drainEvents();

        expect(
          h.container.read(backendHealthControllerProvider),
          BackendHealthTier.offline,
        );
        expect(h.delay.recorded, [const Duration(seconds: 15)]);
      },
    );

    test(
      'a THROWING probe is an unreachable probe (never throws upward)',
      () async {
        final h = _harness(
          // Async error: the await suspends, so build() returns null FIRST
          // and the mapping lands in a later microtask — the real path.
          probeThrows: StateError('probe exploded'),
          autoCompleteDelay: false, // park the chain after the mapping
        );
        addTearDown(h.container.dispose);

        expect(h.container.read(backendHealthControllerProvider), isNull);
        await drainEvents();

        expect(
          h.container.read(backendHealthControllerProvider),
          BackendHealthTier.offline,
          reason: 'issue #657: unreachable maps deterministically to offline',
        );
      },
    );

    test(
      'connectivity offline pauses polling and maps to offline directly',
      () async {
        final h = _harness(
          initial: const [BackendHealthReported(HealthStatus.healthy)],
          autoCompleteDelay: false, // hold the post-healthy interval open
        );
        addTearDown(h.container.dispose);

        await drainEvents();
        expect(
          h.container.read(backendHealthControllerProvider),
          BackendHealthTier.healthy,
        );
        expect(h.probe.calls, 1);

        // Device loses connectivity: NO further probe runs, the tier maps to
        // offline directly (battery rule — no request storms).
        h.source.emit([ConnectivityResult.none]);
        await drainEvents();
        expect(
          h.container.read(backendHealthControllerProvider),
          BackendHealthTier.offline,
        );

        // The held interval elapses — the stale chain must NOT probe.
        h.delay.flush();
        await drainEvents();
        expect(
          h.probe.calls,
          1,
          reason: 'generation counter canceled the stale chain while offline',
        );
      },
    );

    test('connectivity back online starts a fresh poll and recovers', () async {
      final h = _harness(
        initial: const [BackendHealthReported(HealthStatus.healthy)],
        autoCompleteDelay: false,
      );
      addTearDown(h.container.dispose);

      await drainEvents();
      expect(
        h.container.read(backendHealthControllerProvider),
        BackendHealthTier.healthy,
      );

      // Offline (no probe), then back online with a fresh successful probe.
      h.source.emit([ConnectivityResult.none]);
      await drainEvents();
      expect(
        h.container.read(backendHealthControllerProvider),
        BackendHealthTier.offline,
      );

      h.probe.enqueue([const BackendHealthReported(HealthStatus.healthy)]);
      h.source.emit([ConnectivityResult.wifi]);
      await drainEvents();
      expect(h.probe.calls, 2, reason: 'reconnection starts a fresh poll');
      expect(
        h.container.read(backendHealthControllerProvider),
        BackendHealthTier.healthy,
      );
    });

    test(
      'the healthy retry counter resets after a recovered outcome',
      () async {
        final h = _harness(
          initial: const [
            BackendHealthUnreachable(),
            BackendHealthReported(HealthStatus.healthy),
            BackendHealthReported(HealthStatus.degraded),
          ],
          autoCompleteDelay: false,
        );
        addTearDown(h.container.dispose);

        await drainEvents(); // unreachable → offline, backoff 15 s
        expect(
          h.container.read(backendHealthControllerProvider),
          BackendHealthTier.offline,
        );

        h.delay.flush();
        await drainEvents(); // healthy → healthy, FULL interval (counter reset)
        expect(
          h.container.read(backendHealthControllerProvider),
          BackendHealthTier.healthy,
        );
        expect(h.delay.recorded.last, backendHealthPollInterval);

        h.delay.flush();
        await drainEvents(); // degraded → degraded, backoff restarts at 15 s
        expect(
          h.container.read(backendHealthControllerProvider),
          BackendHealthTier.degraded,
        );
        expect(
          h.delay.recorded.last,
          const Duration(seconds: 15),
          reason: 'the failed-attempt counter reset after the healthy answer',
        );
      },
    );
  });
}
