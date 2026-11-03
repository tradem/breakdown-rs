// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../src/health/backend_health_providers.dart';

part 'ai_config_reachability.g.dart';

/// What the client knows about the backend's reachability BEFORE it claims
/// anything about the AI configuration (issue #809).
///
/// Deliberately two members and no "unknown" member: "unknown" is the
/// `AsyncLoading` state of [aiConfigReachabilityProvider], not a value — the
/// widget layer renders "Zugriff wird geprüft…" for it and never conflates it
/// with either resolved answer.
enum AiConfigBackendReachability {
  /// The backend answered its public health route (healthy, degraded or
  /// unhealthy — any report means the backend is reachable).
  reachable,

  /// No usable answer (transport failure, timeout, unparsable body) — the
  /// same fact [BackendHealthUnreachable] carries for the drawer pill.
  unreachable,
}

/// One-shot reachability probe for the AI-configuration entry points
/// (issue #809).
///
/// Why a probe at all: a configuration surface hidden by "unknown" is
/// indistinguishable from an absent one, and a failed read is NOT the same
/// fact as "no configuration exists". The Settings entry therefore asks the
/// existing health seam whether the backend answers before it renders any
/// configuration claim.
///
/// Reuse, not reinvention: [backendHealthProbeProvider] is the single
/// `GET /v1/health` seam (public route, never throws, maps every failure to
/// [BackendHealthUnreachable]). This provider performs exactly ONE probe per
/// (autoDispose) lifetime — no polling, no backoff schedule; the drawer's
/// health pill owns the periodic poll. A retry is an explicit user action
/// (`ref.invalidate(aiConfigReachabilityProvider)`), which re-runs the probe.
///
/// AutoDispose by design: leaving the Settings screen or the configuration
/// screen drops the state, so the next visit measures again instead of
/// serving a stale "reachable" verdict as if it were current.
@riverpod
Future<AiConfigBackendReachability> aiConfigReachability(Ref ref) async {
  final probe = ref.watch(backendHealthProbeProvider);
  final outcome = await probe();
  return switch (outcome) {
    // Degraded/unhealthy still means the backend ANSWERED: the configuration
    // read may well succeed, so the entry keeps its ordinary subtitle and the
    // server stays authoritative about what it serves.
    BackendHealthReported() => AiConfigBackendReachability.reachable,
    BackendHealthUnreachable() => AiConfigBackendReachability.unreachable,
  };
}
