// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:frontend_flutter/features/ai_import/ai_config/decision_round_trip.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tier-1 coverage for the Decision Model round-trip matcher (issue #769).
///
/// The matcher is the client-side guard against the reported defect: a save was
/// reported as successful while the backend had no decision configuration. It
/// must accept exactly one reading — the read-back equals the submission — and
/// flag every other combination, including a swallowed "clear" (all three parts
/// absent on both sides is a match; submitted-cleared vs stored-set is not).
AiConfigView _view({
  LlmProvider? decisionProvider,
  String? decisionModel,
  String? decisionVaultKeyId,
}) => AiConfigView(
  (b) => b
    ..id = 'config-1'
    ..userId = 'dev-user'
    ..assistantModel = 'mistral-large-3'
    ..provider = LlmProvider.eurouter
    ..vaultKeyId = 'extraction-key'
    ..revoked = false
    ..version = 2
    ..decisionProvider = decisionProvider
    ..decisionModel = decisionModel
    ..decisionVaultKeyId = decisionVaultKeyId,
);

void main() {
  const submitted = DecisionTriple(
    providerKey: 'eurouter',
    modelId: 'clef-flash',
    vaultKeyId: 'extraction-key',
  );

  test('a read-back carrying the submitted triple verifies', () {
    final mismatch = verifyDecisionRoundTrip(
      configId: 'config-1',
      submitted: submitted,
      stored: _view(
        decisionProvider: LlmProvider.eurouter,
        decisionModel: 'clef-flash',
        decisionVaultKeyId: 'extraction-key',
      ),
    );

    expect(mismatch, isNull, reason: 'the stored triple equals the submission');
  });

  test('a read-back with NULL decision columns is a mismatch (the bug)', () {
    final mismatch = verifyDecisionRoundTrip(
      configId: 'config-1',
      submitted: submitted,
      stored: _view(),
    );

    expect(mismatch, isNotNull);
    expect(mismatch!.submitted, submitted);
    expect(
      mismatch.stored.isCleared,
      isTrue,
      reason: 'the reported case stored nothing at all',
    );
    expect(mismatch.configId, 'config-1');
  });

  test('a different stored model is a mismatch', () {
    final mismatch = verifyDecisionRoundTrip(
      configId: 'config-1',
      submitted: submitted,
      stored: _view(
        decisionProvider: LlmProvider.eurouter,
        decisionModel: 'metis',
        decisionVaultKeyId: 'extraction-key',
      ),
    );

    expect(mismatch, isNotNull);
    expect(mismatch!.stored.modelId, 'metis');
  });

  test('a different stored binding is a mismatch (silent key replacement)', () {
    final mismatch = verifyDecisionRoundTrip(
      configId: 'config-1',
      submitted: submitted,
      stored: _view(
        decisionProvider: LlmProvider.eurouter,
        decisionModel: 'clef-flash',
        decisionVaultKeyId: 'other-key',
      ),
    );

    expect(mismatch, isNotNull);
    expect(mismatch!.stored.vaultKeyId, 'other-key');
  });

  test('a different stored provider is a mismatch', () {
    final mismatch = verifyDecisionRoundTrip(
      configId: 'config-1',
      submitted: submitted,
      stored: _view(
        decisionProvider: LlmProvider.openai,
        decisionModel: 'clef-flash',
        decisionVaultKeyId: 'extraction-key',
      ),
    );

    expect(mismatch, isNotNull);
  });

  test('clearing scoring verifies when the server really cleared it', () {
    const cleared = DecisionTriple();

    expect(
      verifyDecisionRoundTrip(
        configId: 'config-1',
        submitted: cleared,
        stored: _view(),
      ),
      isNull,
    );
  });

  test('clearing scoring fails when the server kept the old triple', () {
    final mismatch = verifyDecisionRoundTrip(
      configId: 'config-1',
      submitted: const DecisionTriple(),
      stored: _view(
        decisionProvider: LlmProvider.eurouter,
        decisionModel: 'clef-flash',
        decisionVaultKeyId: 'extraction-key',
      ),
    );

    expect(mismatch, isNotNull);
    expect(mismatch!.submitted.isCleared, isTrue);
    expect(mismatch.stored.isCleared, isFalse);
  });
}
