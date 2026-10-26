// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (neuralwatt)

import 'dart:async';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:built_collection/built_collection.dart';
import 'package:flutter/foundation.dart'
    show immutable, listEquals, visibleForTesting;
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

/// How ONE dependency check of the backend's readiness report answered
/// (issue #730).
///
/// Deliberately a client-side enum (not the generated wire enum): the
/// widget layer renders per-check statuses without importing
/// `package:breakdown_api`, so the generated DTOs stay behind the probe
/// seam (`data/`-style boundary, AGENTS.md §1/§3). The three members are
/// the backend's `HealthStatus` vocabulary.
enum BackendHealthCheckStatus {
  /// The check passed.
  healthy,

  /// The dependency answers but is impaired (e.g. a token lookup that
  /// could not be verified).
  degraded,

  /// The dependency is broken (unreachable, invalid credential, …).
  unhealthy,
}

/// One dependency check from `GET /v1/health` as the client renders it
/// (issue #730).
///
/// [name] is the backend's stable check key (`postgres`, `sierradb`,
/// `vault`, `garage`, …). The widget layer NEVER renders it: it maps the
/// known keys to functional, topology-free localized labels and falls back
/// to a generic one for unknown keys — the backend's own `description`
/// text is intentionally NOT carried over (localized copy only, AGENTS.md
/// §5 / §9).
@immutable
final class BackendHealthCheck {
  const BackendHealthCheck({required this.name, required this.status});

  /// Stable check key from the report's `entries` map.
  final String name;

  /// Outcome of that check.
  final BackendHealthCheckStatus status;

  @override
  bool operator ==(Object other) =>
      other is BackendHealthCheck &&
      other.name == name &&
      other.status == status;

  @override
  int get hashCode => Object.hash(name, status);

  @override
  String toString() => 'BackendHealthCheck($name: ${status.name})';
}

/// Everything ONE probe measured (issue #730): the coarse aggregate
/// [tier] the drawer pill renders PLUS the per-dependency [checks] the
/// detail sheet lists.
///
/// One value object instead of two providers: the probe, the poll schedule
/// and the battery rules live in exactly one place, and a consumer that
/// only needs the tier selects it ([BackendHealthSnapshot.tier]) without
/// rebuilding on per-check changes.
@immutable
final class BackendHealthSnapshot {
  const BackendHealthSnapshot({required this.tier, this.checks = const []});

  /// The coarse tier (what the drawer pill shows).
  final BackendHealthTier tier;

  /// Per-dependency results in the order the backend reported them. EMPTY
  /// for the offline tier (nothing was measured) and for a backend that
  /// answers without entries; the detail sheet renders an explanatory body
  /// for both cases instead of an empty list.
  final List<BackendHealthCheck> checks;

  @override
  bool operator ==(Object other) =>
      other is BackendHealthSnapshot &&
      other.tier == tier &&
      listEquals(other.checks, checks);

  @override
  int get hashCode => Object.hash(tier, Object.hashAll(checks));

  @override
  String toString() => 'BackendHealthSnapshot(${tier.name}, $checks)';
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
  const BackendHealthReported(this.status, {this.checks = const []});

  /// Aggregate status from the report body (`Healthy`, `Degraded`,
  /// `Unhealthy`) — the body, not the HTTP status code, is the source of
  /// truth (a 503 carries the same report shape).
  final HealthStatus status;

  /// Per-dependency results from the report's `entries` map (issue #730).
  final List<BackendHealthCheck> checks;
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

/// Maps the report's `entries` map onto the client's per-check model
/// (issue #730). Pure and `@visibleForTesting` so the wire → view mapping is
/// asserted without a live backend.
///
/// The backend's `description` (static, sanitized, English) is deliberately
/// dropped: the detail sheet renders localized copy keyed on the check name
/// and status, never server-authored sentences (AGENTS.md §5 / §9).
@visibleForTesting
List<BackendHealthCheck> backendHealthChecksFromEntries(
  BuiltMap<String, HealthEntry> entries,
) {
  // The generated wire status is a built_value `EnumClass`, not a Dart enum,
  // so a switch STATEMENT (no exhaustiveness proof required) maps it — the
  // same shape the controller's aggregate mapping uses.
  BackendHealthCheckStatus map(HealthStatus status) {
    switch (status) {
      case HealthStatus.healthy:
        return BackendHealthCheckStatus.healthy;
      case HealthStatus.degraded:
        return BackendHealthCheckStatus.degraded;
      case HealthStatus.unhealthy:
        return BackendHealthCheckStatus.unhealthy;
    }
    // Unreachable for the three wire members; a future backend status must
    // not silently claim health, so it reads as broken.
    return BackendHealthCheckStatus.unhealthy;
  }

  return [
    for (final entry in entries.entries)
      BackendHealthCheck(name: entry.key, status: map(entry.value.status)),
  ];
}

/// Orders checks for the detail sheet: broken dependencies first, then
/// degraded, then healthy, so the reason a `Degraded`/`Unhealthy` report
/// exists is the FIRST row the user reads (issue #730).
///
/// Stable by construction (three explicit passes instead of `List.sort`,
/// whose comparator leaves equal elements unordered): checks keep the
/// order the backend reported them within one severity bucket.
List<BackendHealthCheck> backendHealthChecksBySeverity(
  Iterable<BackendHealthCheck> checks,
) {
  final ordered = <BackendHealthCheck>[];
  for (final status in const [
    BackendHealthCheckStatus.unhealthy,
    BackendHealthCheckStatus.degraded,
    BackendHealthCheckStatus.healthy,
  ]) {
    for (final check in checks) {
      if (check.status == status) ordered.add(check);
    }
  }
  return ordered;
}

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
      return BackendHealthReported(
        report.status,
        checks: backendHealthChecksFromEntries(report.entries),
      );
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
/// [BackendHealthTier] for the drawer's health pill PLUS the per-dependency
/// [BackendHealthCheck] list its detail sheet renders (issue #730).
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
/// 5. AutoDispose by design (CodeRabbit #662): the pill is the provider's
///    only listener, so the whole poll loop dies with the closed drawer —
///    no background health traffic while nothing is visible. Reopening
///    restarts from the null state (fresh first probe) instead of serving
///    a cached tier as if it were current; the empty slot for the ~one
///    round-trip is the same honest "not measured yet" presentation as on
///    the very first open.
///
/// Issue #730 consequence: the detail sheet is a modal sheet over the
/// STILL-OPEN drawer (never after a drawer pop), so the pill stays mounted
/// underneath and this controller keeps polling while the sheet is open —
/// the sheet shows live per-dependency data instead of a frozen snapshot.
@Riverpod()
class BackendHealthController extends _$BackendHealthController {
  /// Monotonic generation: any rebuild, connectivity change, or new chain
  /// step invalidates every in-flight continuation from earlier generations.
  int _generation = 0;

  /// Consecutive non-healthy outcomes (drives the backoff schedule).
  int _retries = 0;

  /// Last snapshot this controller published. Survives connectivity-driven
  /// rebuilds (the Notifier instance persists across `build()` re-runs) so a
  /// rebuild can return the previously known snapshot instead of resetting
  /// to null — `state` itself cannot be read inside `build()` before the
  /// initial return.
  BackendHealthSnapshot? _last;

  @override
  BackendHealthSnapshot? build() {
    final connectivity = ref.watch(connectivityControllerProvider);
    // Invalidate any chain from before this (re)build — a connectivity
    // change supersedes everything in flight.
    _generation++;
    if (connectivity == ConnectivityStatus.offline) {
      // Deterministic mapping WITHOUT any probe (battery rule): the device
      // has no usable route, so the backend is unreachable by definition —
      // and no dependency was measured, so the previous check list is
      // dropped rather than presented as current.
      return _last = const BackendHealthSnapshot(
        tier: BackendHealthTier.offline,
      );
    }
    // Fire-and-forget by design (build cannot await); the loop
    // self-terminates on generation mismatch or disposal. (Riverpod already
    // runs the previous build's onDispose listeners before this rebuild.)
    unawaited(_poll());
    return _last;
  }

  /// One iterative poll loop (CodeRabbit #662: no self-awaiting recursion,
  /// so a long-lived chain retains exactly ONE frame, not one per interval).
  /// Every `await` is followed by BOTH a disposal check (`ref.mounted` — a
  /// disposed Ref must not be used again, Riverpod 3 throws) and the
  /// generation check (a rebuild/connectivity change supersedes this loop).
  Future<void> _poll() async {
    final generation = ++_generation;
    while (ref.mounted && generation == _generation) {
      BackendHealthOutcome outcome;
      try {
        outcome = await ref.read(backendHealthProbeProvider)();
      } catch (_) {
        // A throwing probe is an unreachable probe (issue #657: never throws
        // into the widget layer).
        outcome = const BackendHealthUnreachable();
      }
      if (!ref.mounted || generation != _generation) {
        return; // disposed/superseded
      }
      switch (outcome) {
        case BackendHealthReported(:final status, :final checks):
          switch (status) {
            case HealthStatus.healthy:
              _retries = 0;
              state = _last = BackendHealthSnapshot(
                tier: BackendHealthTier.healthy,
                checks: checks,
              );
            case HealthStatus.degraded:
              state = _last = BackendHealthSnapshot(
                tier: BackendHealthTier.degraded,
                checks: checks,
              );
            case HealthStatus.unhealthy:
              state = _last = BackendHealthSnapshot(
                tier: BackendHealthTier.unhealthy,
                checks: checks,
              );
          }
        case BackendHealthUnreachable():
          state = _last = const BackendHealthSnapshot(
            tier: BackendHealthTier.offline,
          );
      }
      // Battery-friendly re-poll: healthy answers wait the full conservative
      // interval; anything else backs off exponentially. Canceled by a
      // generation bump (connectivity change / rebuild) or disposal while
      // waiting.
      await ref.read(backendHealthDelayProvider)(
        state?.tier == BackendHealthTier.healthy
            ? backendHealthPollInterval
            : backendHealthRetryBackoff(++_retries),
      );
      if (!ref.mounted || generation != _generation) {
        return; // disposed/superseded while waiting
      }
      if (ref.read(connectivityControllerProvider) ==
          ConnectivityStatus.offline) {
        return; // device went offline — build() owns the mapping then
      }
    }
  }
}
