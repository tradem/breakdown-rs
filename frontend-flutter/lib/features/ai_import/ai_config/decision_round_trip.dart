// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

/// Client-side round-trip verification of the Decision Model triple
/// (issue #769).
///
/// The defect this closes: the app presented a configured Decision Model as
/// saved while the backend had no such state — the AI-config aggregate held no
/// `decision_*` payload, the projection columns were NULL, and the import
/// worker therefore resolved `decision: None` (no scoring pass, no stars). A
/// successful `POST`/`PATCH` acknowledgement is **not** evidence that the
/// triple was persisted, so the client re-reads the authoritative view
/// (`GET /v1/ai-import/config/{id}`) and compares it against what it submitted.
///
/// This file is pure Dart (no Flutter imports) so the matcher is unit-testable
/// in the fast tier, independent of any widget or network double.
library;

import 'package:breakdown_api/breakdown_api.dart';

/// The problem code the screen surfaces when the read-back disagrees with the
/// submission. Client-detected — no server problem document carries it, so the
/// UI localizes its own copy keyed on this code (AGENTS.md §5: branch on the
/// stable `code`, never on `detail`).
const String decisionNotPersistedCode = 'ai_config.decision_not_persisted';

/// The Decision Model slot as it appears on both sides of the round trip.
///
/// All three parts are `null` together when scoring is disabled — that is a
/// legitimate configuration, and clearing it must be verified just like
/// setting it (a swallowed "clear" is the same class of silent loss).
class DecisionTriple {
  const DecisionTriple({this.providerKey, this.modelId, this.vaultKeyId});

  /// The provider as the generated enum's Dart name (`eURouter`). Both sides
  /// of the comparison derive it from the SAME generated enum, so the check
  /// never depends on the wire spelling — it compares identity, not text.
  final String? providerKey;

  /// The curated decision model id (`clef-flash`).
  final String? modelId;

  /// The opaque vault key reference the decision client authenticates with.
  /// For same-key reuse this equals the extraction config's `vaultKeyId`.
  final String? vaultKeyId;

  /// The triple as the server stored it ([AiConfigView]).
  factory DecisionTriple.fromView(AiConfigView view) => DecisionTriple(
    providerKey: view.decisionProvider?.name,
    modelId: view.decisionModel,
    vaultKeyId: view.decisionVaultKeyId,
  );

  /// True when scoring is disabled (all three parts absent).
  bool get isCleared =>
      providerKey == null && modelId == null && vaultKeyId == null;

  @override
  bool operator ==(Object other) =>
      other is DecisionTriple &&
      other.providerKey == providerKey &&
      other.modelId == modelId &&
      other.vaultKeyId == vaultKeyId;

  @override
  int get hashCode => Object.hash(providerKey, modelId, vaultKeyId);

  @override
  String toString() =>
      'DecisionTriple(providerKey: $providerKey, modelId: $modelId, '
      'vaultKeyId: $vaultKeyId)';
}

/// A disagreement between the submitted and the stored Decision Model triple.
///
/// Carries both sides so tests and log lines can distinguish "never stored"
/// (stored is cleared) from "stored with a different binding" (e.g. a
/// remembered key silently replaced the stored one).
class DecisionRoundTripMismatch {
  const DecisionRoundTripMismatch({
    required this.submitted,
    required this.stored,
    required this.configId,
  });

  final DecisionTriple submitted;
  final DecisionTriple stored;
  final String configId;

  @override
  String toString() =>
      'DecisionRoundTripMismatch(config: $configId, submitted: $submitted, '
      'stored: $stored)';
}

/// Compares the triple the client **submitted** with the triple the server
/// **stored** (read back via `GET /v1/ai-import/config/{id}`).
///
/// Returns `null` when the read-back confirms the submission — the only state
/// in which the configuration may be reported as active.
DecisionRoundTripMismatch? verifyDecisionRoundTrip({
  required String configId,
  required DecisionTriple submitted,
  required AiConfigView stored,
}) {
  final storedTriple = DecisionTriple.fromView(stored);
  if (storedTriple == submitted) return null;
  return DecisionRoundTripMismatch(
    submitted: submitted,
    stored: storedTriple,
    configId: configId,
  );
}
