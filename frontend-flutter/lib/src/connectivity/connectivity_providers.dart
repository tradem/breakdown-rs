// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (neuralwatt)

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../auth/auth_providers.dart';

part 'connectivity_providers.g.dart';

/// Connectivity status exposed by [ConnectivityController] (issue #654).
///
/// - [online]: pill hidden. The passive OS signal reports a carrier and the
///   last confirmation probe (if any) succeeded.
/// - [offline]: the passive OS signal reports no carrier (NetworkCallback
///   `onLost`) — pill visible.
/// - [degraded]: the OS reports a carrier but the HTTP confirmation probe
///   failed (captive portal / dead route) — pill stays visible, re-probes
///   run on the exponential-backoff schedule.
enum ConnectivityStatus { online, offline, degraded }

/// Whether the offline pill (issue #654) is visible for [status].
///
/// Only `online` hides the pill; `degraded` keeps it visible because the
/// OS-reported carrier does not guarantee a usable route to the backend.
bool connectivityShowsPill(ConnectivityStatus status) =>
    status != ConnectivityStatus.online;

/// Exponential backoff for the secondary HTTP down-check (issue #654).
///
/// Conservative schedule: 15 s base, doubling per consecutive failure,
/// capped at 10 minutes — deliberately NOT a fixed short-interval
/// heartbeat (the issue's battery requirement). Pure and `@visibleForTesting`
/// so tests assert the schedule analytically against the budget instead of
/// sleeping (deterministic-tests hard rule).
@visibleForTesting
Duration connectivityProbeBackoff(int consecutiveFailures) {
  const baseSeconds = 15;
  const maxDelaySeconds = 10 * 60;
  if (consecutiveFailures <= 1) return const Duration(seconds: baseSeconds);
  // Clamp the shift so the shift cannot overflow for absurd counts; the
  // `min` against the cap does the real limiting.
  final shift = (consecutiveFailures - 1).clamp(0, 20);
  final seconds = baseSeconds * (1 << shift);
  return Duration(
    seconds: seconds > maxDelaySeconds ? maxDelaySeconds : seconds,
  );
}

/// Passive OS connectivity signal source seam (issue #654): the ONLY
/// connectivity surface [ConnectivityController] consumes.
///
/// Production delegates to `connectivity_plus` — on Android this is the
/// `ConnectivityManager` NetworkCallback, i.e. a passive OS push with no
/// polling loop. Tests provide a fake that emits into controllable
/// `StreamController`s (deterministic-tests hard rule).
abstract interface class PassiveConnectivitySource {
  /// Passive carrier-change signals. A list containing any non-`none`
  /// result means the OS reports at least one usable carrier; an empty
  /// list or `[none]` means no carrier.
  Stream<List<ConnectivityResult>> get onConnectivityChanged;
}

/// Production [PassiveConnectivitySource] backed by `connectivity_plus`.
final class ConnectivityPlusSource implements PassiveConnectivitySource {
  const ConnectivityPlusSource();

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      Connectivity().onConnectivityChanged;
}

/// Secondary HTTP liveness probe seam (issue #654): returns `true` when ANY
/// HTTP response arrived from the API base (even 404/401 — the wire is
/// proven usable), `false` on transport failure or timeout.
typedef ConnectivityHttpProbe = Future<bool> Function();

/// Injectable delay seam (deterministic tests): the default delegates to
/// [Future.delayed]; tests record the requested durations instead of
/// sleeping.
typedef ConnectivityDelay = Future<void> Function(Duration duration);

@Riverpod(keepAlive: true)
PassiveConnectivitySource passiveConnectivitySource(Ref ref) =>
    const ConnectivityPlusSource();

@Riverpod(keepAlive: true)
ConnectivityHttpProbe connectivityHttpProbe(Ref ref) {
  final apiBase = ref.watch(appConfigProvider).apiBase;
  return () async {
    // Bare Dio WITHOUT the auth interceptor: a liveness probe never
    // carries tokens. `validateStatus: (_) => true` accepts EVERY status:
    // 404/401/503 from the API all prove the route is usable — Dio's
    // default predicate would throw `badResponse` for 4xx/5xx and mask a
    // working connection as offline (CodeRabbit #660). Only transport
    // errors/timeout mean the route is NOT usable.
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
        validateStatus: (_) => true,
      ),
    );
    try {
      await dio.getUri<void>(Uri.parse(apiBase));
      return true;
    } on DioException {
      return false;
    } finally {
      // Each probe owns its client: close it on BOTH paths so repeated
      // degraded retries never accumulate sockets (CodeRabbit #660).
      dio.close(force: true);
    }
  };
}

@Riverpod(keepAlive: true)
ConnectivityDelay connectivityDelay(Ref ref) =>
    (duration) => Future<void>.delayed(duration);

/// Connectivity controller (issue #654): passive-first detection with a
/// conservative HTTP confirmation probe.
///
/// Strategy (battery requirement of issue #654):
/// 1. Passive OS signals (`PassiveConnectivitySource`) are the primary
///    source — no polling loop. `none` → [ConnectivityStatus.offline]
///    immediately.
/// 2. When the OS transitions offline → connected while the app was NOT
///    online, ONE lightweight HTTP probe confirms the route (captive
///    portals report carriers too). Success → [ConnectivityStatus.online];
///    failure → [ConnectivityStatus.degraded] and re-probes run on the
///    [connectivityProbeBackoff] schedule.
/// 3. While healthy (`online`) the controller NEVER probes — passive
///    signals only.
/// 4. A generation counter cancels pending probe chains: a new passive
///    event (e.g. carrier lost again) supersedes any in-flight retry, so
///    a flapping link cannot trigger request storms.
///
/// The initial state is optimistic [ConnectivityStatus.online]: no pill
/// before evidence of offline (a cold-start offline device receives its
/// `none` event within the first passive callbacks). Plugin errors (which
/// occur in widget tests where the method channel is unimplemented) are
/// swallowed by the `onError` handler: without a signal the controller
/// stays `online` — it never invents an offline state it cannot back.
@Riverpod(keepAlive: true)
class ConnectivityController extends _$ConnectivityController {
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  /// Monotonic generation: any new passive event or probe-chain step
  /// invalidates every in-flight continuation from earlier generations.
  int _generation = 0;

  /// Consecutive failed confirmation probes (drives the backoff schedule).
  int _failedAttempts = 0;

  @override
  ConnectivityStatus build() {
    final source = ref.watch(passiveConnectivitySourceProvider);
    // `onError` keeps the controller alive when the platform channel is
    // unavailable (widget tests): state stays online, never invents offline.
    _subscription = source.onConnectivityChanged.listen(
      _onPassiveEvent,
      onError: (Object _) {},
    );
    ref.onDispose(() {
      _generation++;
      unawaited(_subscription?.cancel());
      _subscription = null;
    });
    return ConnectivityStatus.online;
  }

  /// Passive signal handler (primary source, issue #654).
  @visibleForTesting
  void onPassiveEvent(List<ConnectivityResult> results) =>
      _onPassiveEvent(results);

  void _onPassiveEvent(List<ConnectivityResult> results) {
    final connected = results.any((r) => r != ConnectivityResult.none);
    if (!connected) {
      // Cancel any in-flight probe chain, reset the backoff, show the pill.
      _generation++;
      _failedAttempts = 0;
      state = ConnectivityStatus.offline;
      return;
    }
    // OS reports a carrier.
    if (state == ConnectivityStatus.online) {
      // Battery-friendly: while healthy, passive signals only — no probe.
      return;
    }
    // Reconnection from offline/degraded: confirm with ONE HTTP probe.
    // Fire-and-forget by design (a passive event callback cannot await);
    // the chain self-terminates on generation mismatch (see below).
    unawaited(_runConfirmationProbe());
  }

  Future<void> _runConfirmationProbe() async {
    final generation = ++_generation;
    // Unconfirmed (re)connection: keep the pill visible but mark degraded
    // (not offline — the OS reports a carrier).
    state = ConnectivityStatus.degraded;
    final probe = ref.read(connectivityHttpProbeProvider);
    bool reachable = false;
    try {
      reachable = await probe();
    } catch (_) {
      // A throwing probe is a failed probe (issue #654: single failed
      // request downgrades, never throws).
    }
    if (generation != _generation) return; // superseded
    if (reachable) {
      _failedAttempts = 0;
      state = ConnectivityStatus.online;
      return;
    }
    _failedAttempts++;
    state = ConnectivityStatus.degraded;
    // Backed-off re-probe: ONE timer per chain step, exponentially spaced —
    // never a tight heartbeat. Canceled by generation bump on a new event.
    await ref.read(connectivityDelayProvider)(
      connectivityProbeBackoff(_failedAttempts),
    );
    if (generation != _generation) return; // superseded while waiting
    if (state != ConnectivityStatus.degraded) return; // went offline again
    await _runConfirmationProbe();
  }
}
