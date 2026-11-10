// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

import 'package:flutter/foundation.dart' show immutable;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../core/result.dart';
import '../data/capabilities_repository.dart';

part 'capabilities.g.dart';

/// The caller's **global** (deployment-scoped) capabilities as the client
/// consumes them (issue #816).
///
/// Deliberately a client-side value, not the generated wire DTO: the widget
/// layer renders these two facts without importing `package:breakdown_api`
/// (the same boundary the health probe keeps on its enums).
///
/// [canManageAiConfig] is the SERVER's `has_active_credential_role` — the
/// predicate the AI-configuration handlers enforce (ADR-027). It replaces the
/// season-scoped approximation #809 had to tolerate, which was a superset
/// (it also admits `wardrobe_supervisor`) and ambient (a stale scope read as a
/// denial). An unknown answer is NOT modelled here: "unknown" is the
/// `AsyncLoading`/`AsyncError` state of [myCapabilitiesProvider], never a
/// `false`, so the client cannot invent a denial out of a failed read.
@immutable
class MyCapabilities {
  const MyCapabilities({
    required this.canManageAiConfig,
    required this.canReadOps,
  });

  /// `has_active_credential_role` — may manage the AI configuration and
  /// external credentials (active `costume_designer` / `costume_assistant` in
  /// any block).
  final bool canManageAiConfig;

  /// `has_active_ops_role` — holds the ops capability (an active `ops_admin`
  /// membership in any block, or a place on the deployment's
  /// `OPS_ADMIN_SUBS` bootstrap allowlist). No client surface consumes it yet;
  /// it is carried so the wire contract is published as a whole (issue #816).
  final bool canReadOps;

  /// A resolved denial of the credential gate — the fact the Settings entry
  /// renders as "Keine Berechtigung".
  bool get isDenied => !canManageAiConfig;

  @override
  bool operator ==(Object other) =>
      other is MyCapabilities &&
      other.canManageAiConfig == canManageAiConfig &&
      other.canReadOps == canReadOps;

  @override
  int get hashCode => Object.hash(canManageAiConfig, canReadOps);
}

/// The capabilities fetch as an injectable seam (issue #816).
///
/// Tests override THIS instead of impersonating the HTTP client, exactly like
/// #809's `backendHealthProbeProvider`: a never-completing future pins the
/// "unknown" state and a failed [Result] the error state, with no wall clock
/// involved (AGENTS.md §6 forbids timing gates).
typedef MyCapabilitiesFetch = Future<Result<MyCapabilities>> Function();

/// Default seam: the real `GET /v1/me/capabilities` read.
///
/// `keepAlive` because this is a stable seam, not state: the same reasoning as
/// `backendHealthProbeProvider` (issue #657), and it keeps a widget test's
/// `overrideWithValue` in force across rebuilds.
@Riverpod(keepAlive: true)
MyCapabilitiesFetch myCapabilitiesFetch(Ref ref) {
  final repository = ref.watch(capabilitiesRepositoryProvider);
  return repository.fetchMyCapabilities;
}

/// The caller's global capabilities — a ONE-SHOT probe, no polling.
///
/// * `AsyncData(true)`  → the credential gate is open;
/// * `AsyncData(false)` → a RESOLVED denial (the entry says "Keine
///   Berechtigung" and the AI-config discovery dispatch is suppressed);
/// * `AsyncLoading` / `AsyncError` → UNKNOWN. Never rendered as a denial: a
///   failed read must not put a permission problem in front of a user whose
///   role is intact, and the server stays authoritative on every gated call.
///
/// AutoDispose by design (same lifetime as #809's reachability probe): the
/// Settings tile keeps watching it while the configuration screen is pushed,
/// and a new Settings visit measures again.
@riverpod
Future<MyCapabilities> myCapabilities(Ref ref) async {
  final result = await ref.watch(myCapabilitiesFetchProvider)();
  // A `Left` becomes the provider's `AsyncError` on purpose: the error branch
  // is "unknown", which the widget layer treats differently from a denial.
  return result.match((error) => throw error, (value) => value);
}
