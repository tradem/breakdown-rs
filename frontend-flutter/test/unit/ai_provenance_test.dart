// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)

// Tier-1 unit tests for the pure provenance parsing (issue #538, EU AI Act
// Art. 50): every variant of the generated externally-tagged enum resolves
// honestly — `Manual`, `AiExtracted`, absent (`null` wire value, pre-#538
// rows) and unrecognized future variants. No Flutter imports.

import 'package:breakdown_api/breakdown_api.dart';
import 'package:one_of/one_of.dart';
import 'package:test/test.dart';

import 'package:frontend_flutter/domain/ai_provenance.dart';

void main() {
  group('sceneProvenance (SceneView.source_)', () {
    test('null reads as absent — pre-#538 rows carry no invented '
        'attribution', () {
      expect(sceneProvenance(null), AiProvenanceVariant.absent);
    });

    test('the Manual wire arm resolves as manual', () {
      final source = SceneSource(
        (s) => s..oneOf = OneOf.fromValue1<String>(value: 'Manual'),
      );
      expect(sceneProvenance(source), AiProvenanceVariant.manual);
      expect(isAiDerived(sceneProvenance(source)), isFalse);
    });

    test(
      'the AiExtracted arm resolves as aiExtracted with its detail data',
      () {
        final source = SceneSource(
          (s) => s
            ..oneOf = OneOf.fromValue2<String, SceneSourceOneOf>(
              value: SceneSourceOneOf(
                (d) => d
                  ..aiExtracted = SceneSourceOneOfAiExtracted(
                    (d2) => d2
                      ..documentId = 'job-1'
                      ..externalRef = 'draft-1'
                      ..confidence = null,
                  ).toBuilder(),
              ),
            ),
        );
        final variant = sceneProvenance(source);
        expect(variant, AiProvenanceVariant.aiExtracted);
        expect(isAiDerived(variant), isTrue);
        final detail = extractionDetailOf(source.oneOf);
        expect(detail!.documentId, 'job-1');
        expect(detail.externalRef, 'draft-1');
        // Honest confidence: the pipeline measures none (issue #517) —
        // null is carried through, never fabricated into a placeholder.
        expect(detail.confidence, isNull);
      },
    );

    test('an unrecognized future wire arm degrades without any badge', () {
      final source = SceneSource(
        (s) => s..oneOf = OneOf.fromValue1<String>(value: 'SomeFutureVariant'),
      );
      final variant = sceneProvenance(source);
      expect(variant, AiProvenanceVariant.unrecognized);
      expect(badgeCopyOf(variant, () => 'AI'), isNull);
    });
  });

  group('dayProvenance (ShootingDayView.source_)', () {
    test('null reads as absent', () {
      expect(dayProvenance(null), AiProvenanceVariant.absent);
    });

    test('the Manual arm resolves as manual; the badge copy is withheld', () {
      final source = ShootingDaySource(
        (s) => s..oneOf = OneOf.fromValue1<String>(value: 'Manual'),
      );
      final variant = dayProvenance(source);
      expect(variant, AiProvenanceVariant.manual);
      expect(badgeCopyOf(variant, () => 'AI-extracted'), isNull);
    });

    test('the AiExtracted arm resolves as aiExtracted; legacy plain-numeric '
        'confidence reads losslessly as Some(…)', () {
      final source = ShootingDaySource(
        (s) => s
          ..oneOf = OneOf.fromValue2<String, SceneSourceOneOf>(
            value: SceneSourceOneOf(
              (d) => d
                ..aiExtracted = SceneSourceOneOfAiExtracted(
                  (d2) => d2
                    ..documentId = 'job-2'
                    ..confidence = 1.0,
                ).toBuilder(),
            ),
          ),
      );
      final variant = dayProvenance(source);
      expect(variant, AiProvenanceVariant.aiExtracted);
      // Pre-#517 persisted days carry the hard-coded 1.0 — losslessly
      // surfaced as a real value (honest what the wire recorded).
      final detail = extractionDetailOf(source.oneOf);
      expect(detail!.confidence, 1.0);
      // Badge copy resolves exactly one localized string for the AI arm.
      expect(badgeCopyOf(variant, () => 'KI-extrahiert'), 'KI-extrahiert');
    });
  });
}
