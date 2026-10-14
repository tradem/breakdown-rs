// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (neuralwatt)

import 'dart:async';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../connectivity/connectivity_providers.dart';
import '../../data/cache/seasons_cache_providers.dart';

part 'backend_health_providers.g.dart';

/// Coarse backend health tier rendered by the drawer's health pill
/// (issue #657).
///
/// Four tiers (settled decision on the issue's initial 3-tier proposal):
/// the server-reported `Unhealthy` state (HTTP 503) gets its OWN tier so
/// the label can say "Backend gestört" instead of conflating it with an
/// unreachable backend. Both red tiers share the error color; only the
/// localized label differs.
enum BackendHealthTier {
  /// `Healthy` aggregate report — all dependencies healthy.
  healthy,

  /// `Degraded` aggregate report — at least one dependency degraded.
  degraded,

  /// `Unhealthy` aggregate report (HTTP 503) — server reachable but
  /// reporting a broken dependency.
  unhealthy,

  /// No usable answer: transport failure, timeout, unparsable body — OR the
  /// passive connectivity signal reports the device offline (in which case
  /// no health probe runs at all). Same red family as the #654 offline pill.
  offline,
}

/// Outcome of ONE backend health probe (issue #657).
///
/// Sealed so the controller cannot forget a branch: either the backend
/// answered with a parseable aggregate [BackendHealthReported.status], or it
/// did not ([BackendHealthUnreachable] — transport error, timeout, unexpected
/// status, unparsable body). There is deliberately no "unknown" outcome: an
/// unanswered probe IS the offline tier (no silent failure).
sealed class BackendHealthOutcome {
  const BackendHealthOutcome();
}

/// The backend answered `GET /v1/health` with a parseable [HealthReport].
final class BackendHealthReported extends BackendHealthOutcome {
  const BackendHealthReported(this.status);

  /// Aggregate status from the report body (`Healthy`, `Degraded`,
  /// `Unhealthy`) — the body, not the HTTP status code, is the source of
  /// truth (a 503 carries the same report shape).
  final HealthStatus status;
}

/// The probe produced no usable answer (transport failure, timeout,
/// unexpected response, unparsable body).
final class BackendHealthUnreachable extends BackendHealthOutcome {
  const BackendHealthUnreachable();
}

/// Exponential backoff between health re-probes (issue #657).
///
/// Conservative schedule mirroring `connectivityProbeBackoff` (issue #654):
/// 15 s base, doubling per consecutive non-healthy outcome, capped at
/// 10 minutes — deliberately NOT a fixed short-interval heartbeat. Pure and
/// `@visibleForTesting` so tests assert the schedule analytically instead of
/// sleeping (deterministic-tests hard rule).
@visibleForTesting
Duration backendHealthRetryBackoff(int consecutiveRetries) {
  const baseSeconds = 15;
  const maxDelaySeconds = 10 * 60;
  if (consecutiveRetries <= 1) return const Duration(seconds: baseSeconds);
  // Clamp the shift so the shift cannot overflow for absurd counts; the
  // `min` against the cap does the real limiting.
  final shift = (consecutiveRetries - 1).clamp(0, 20);
  final seconds = baseSeconds * (1 << shift);
  return Duration(
    seconds: seconds > maxDelaySeconds ? maxDelaySeconds : seconds,
  );
}

/// Conservative interval between two polls after a HEALTHY answer
/// (issue #657): the backend already serves container probes on this route,
/// so one tiny GET per minute per device is the deliberate battery/freshness
/// trade-off. Degraded/unhealthy/offline outcomes re-probe on the
/// [backendHealthRetryBackoff] schedule instead.
@visibleForTesting
const Duration backendHealthPollInterval = Duration(seconds: 60);

/// Backend health probe seam (issue #657): the ONLY surface
/// [BackendHealthController] consumes. Returns the parsed aggregate status
/// or [BackendHealthUnreachable] — it NEVER throws.
typedef BackendHealthProbe = Future<BackendHealthOutcome> Function();

/// Production probe over the app's generated client: `GET /v1/health` is
/// public (the auth middleware exempts it), so riding `apiClientProvider`
/// costs no token round-trip while inheriting the pinned-CA transport and
/// the runtime base-URL override. `validateStatus: (_) => true` lets the
/// 503 "unhealthy" answer deserialize into a `HealthReport` instead of
/// throwing like Dio's default predicate would.
@Riverpod(keepAlive: true)
BackendHealthProbe backendHealthProbe(Ref ref) {
  final api = ref.watch(apiClientProvider);
  return () async {
    try {
      final response = await api.getHandlersApi().getHealth(
        validateStatus: (_) => true,
      );
      final report = response.data;
      if (report == null) return const BackendHealthUnreachable();
      return BackendHealthReported(report.status);
    } catch (_) {
      // Any failure (transport, timeout, unparsable body) is a deterministic
      // unreachable — the controller maps it to the offline tier.
      return const BackendHealthUnreachable();
    }
  };
}

/// Injectable delay seam (deterministic tests): the default delegates to
/// [Future.delayed]; tests record the requested durations instead of
/// sleeping.
typedef BackendHealthDelay = Future<void> Function(Duration duration);

@Riverpod(keepAlive: true)
BackendHealthDelay backendHealthDelay(Ref ref) =>
    (duration) => Future<void>.delayed(duration);

/// Backend health controller (issue #657): polls the public
/// `GET /v1/health` on a battery-friendly schedule and exposes the coarse
/// [BackendHealthTier] for the drawer's health pill.
///
/// Strategy:
/// 1. The initial state is `null` (no data yet): the pill slot stays EMPTY
///    until the first probe answers, so the drawer never flashes a wrong
///    tier. The drawer child builds lazily (DrawerController only builds the
///    content when opened), so the first poll starts when the user first
///    opens the drawer — no background traffic before that.
/// 2. After a HEALTHY answer the next poll waits
///    [backendHealthPollInterval] (60 s). Degraded/unhealthy/offline
///    outcomes re-probe on the [backendHealthRetryBackoff] schedule.
/// 3. While the passive connectivity signal (issue #654) reports the device
///    offline, NO health probes run: the tier maps to offline directly and
///    any in-flight chain is canceled (generation counter). When
///    connectivity returns, a fresh poll starts immediately.
/// 4. A generation counter cancels pending chains: a new passive event or a
///    controller rebuild supersedes every in-flight continuation, so a
///    flapping link cannot trigger request storms.
@Riverpod(keepAlive: true)
class BackendHealthController extends _$BackendHealthController {
  /// Monotonic generation: any rebuild, connectivity change, or new chain
  /// step invalidates every in-flight continuation from earlier generations.
  int _generation = 0;

  /// Consecutive non-healthy outcomes (drives the backoff schedule).
  int _retries = 0;

  /// Last tier this controller published. Survives connectivity-driven
  /// rebuilds (the Notifier instance persists across `build()` re-runs) so a
  /// rebuild can return the previously known tier instead of resetting to
  /// null — `state` itself cannot be read inside `build()` before the
  /// initial return.
  BackendHealthTier? _lastTier;

  @override
  BackendHealthTier? build() {
    final connectivity = ref.watch(connectivityControllerProvider);
    // Invalidate any chain from before this (re)build — a connectivity
    // change supersedes everything in flight.
    _generation++;
    if (connectivity == ConnectivityStatus.offline) {
      // Deterministic mapping WITHOUT any probe (battery rule): the device
      // has no usable route, so the backend is unreachable by definition.
      return _lastTier = BackendHealthTier.offline;
    }
    // Fire-and-forget by design (build cannot await); the chain
    // self-terminates on generation mismatch. (Riverpod already runs the
    // previous build's onDispose listeners before this rebuild, and the
    // bump above invalidates every chain from earlier generations.)
    unawaited(_poll());
    return _lastTier;
  }

  Future<void> _poll() async {
    final generation = ++_generation;
    final probe = ref.read(backendHealthProbeProvider);
    BackendHealthOutcome outcome;
    try {
      outcome = await probe();
    } catch (_) {
      // A throwing probe is an unreachable probe (issue #657: never throws
      // into the widget layer).
      outcome = const BackendHealthUnreachable();
    }
    if (generation != _generation) return; // superseded
    switch (outcome) {
      case BackendHealthReported(:final status):
        switch (status) {
          case HealthStatus.healthy:
            _retries = 0;
            state = _lastTier = BackendHealthTier.healthy;
          case HealthStatus.degraded:
            state = _lastTier = BackendHealthTier.degraded;
          case HealthStatus.unhealthy:
            state = _lastTier = BackendHealthTier.unhealthy;
        }
      case BackendHealthUnreachable():
        state = _lastTier = BackendHealthTier.offline;
    }
    // Battery-friendly re-poll: healthy answers wait the full conservative
    // interval; anything else backs off exponentially. Canceled by a
    // generation bump (connectivity change / rebuild) while waiting.
    final delay = ref.read(backendHealthDelayProvider);
    await delay(
      state == BackendHealthTier.healthy
          ? backendHealthPollInterval
          : backendHealthRetryBackoff(++_retries),
    );
    if (generation != _generation) return; // superseded while waiting
    if (ref.read(connectivityControllerProvider) ==
        ConnectivityStatus.offline) {
      return; // device went offline — build() owns the mapping then
    }
    await _poll();
  }
}
