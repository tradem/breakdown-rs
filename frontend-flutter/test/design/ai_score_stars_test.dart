// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)

// Tier-1 (score→stars mapping, filter predicate) + Tier-2 (widget rendering,
// honest null absence, accessibility semantics) tests for the reusable
// Decision Model star-rating indicator (issue #723, design D2).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/design/components/ai_score_stars.dart';

void main() {
  group('aiScoreStarsFor (issue #723 bucket boundaries, design D2)', () {
    test('maps the documented boundaries to 1–5 stars', () {
      expect(aiScoreStarsFor(0.0), 1);
      expect(aiScoreStarsFor(0.29), 1);
      expect(aiScoreStarsFor(0.30), 2);
      expect(aiScoreStarsFor(0.49), 2);
      expect(aiScoreStarsFor(0.50), 3);
      expect(aiScoreStarsFor(0.69), 3);
      expect(aiScoreStarsFor(0.70), 4);
      expect(aiScoreStarsFor(0.84), 4);
      expect(aiScoreStarsFor(0.85), 5);
      expect(aiScoreStarsFor(1.0), 5);
    });

    test('never returns 0 — a rendered rating marks a scored artifact', () {
      expect(aiScoreStarsFor(0.001), 1);
    });
  });

  group('isLowAiScore (issue #723 low-score filter predicate, design D3)', () {
    test('is true strictly below the 3-star boundary (0.70)', () {
      expect(isLowAiScore(0.0), isTrue);
      expect(isLowAiScore(0.69), isTrue);
      expect(isLowAiScore(0.70), isFalse);
      expect(isLowAiScore(1.0), isFalse);
    });

    test('a null score is never low — unscored is unranked', () {
      expect(isLowAiScore(null), isFalse);
    });
  });

  group('AiScoreStars widget (issue #723)', () {
    Future<void> pumpScore(WidgetTester tester, double? score) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(children: [AiScoreStars(score: score)]),
          ),
        ),
      );
    }

    testWidgets('renders 5 filled + 0 outline stars at 0.9', (tester) async {
      await pumpScore(tester, 0.9);
      expect(find.byKey(const Key('ai-score-stars')), findsOneWidget);
      for (var i = 1; i <= 5; i++) {
        expect(find.byKey(Key('ai-score-star-$i')), findsOneWidget);
      }
      final fifth = tester.widget<Icon>(
        find.byKey(const Key('ai-score-star-5')),
      );
      expect(fifth.icon, Icons.star);
      // All five are filled at 0.9 (≥ 0.85 → 5★).
      final first = tester.widget<Icon>(
        find.byKey(const Key('ai-score-star-1')),
      );
      expect(first.icon, Icons.star);
      // The visible label names the bucket ({stars} of 5 stars).
      expect(find.text('5 of 5 stars'), findsOneWidget);
    });

    testWidgets('renders 3 filled + 2 outline stars at 0.55', (tester) async {
      await pumpScore(tester, 0.55);
      expect(
        tester.widget<Icon>(find.byKey(const Key('ai-score-star-3'))).icon,
        Icons.star,
      );
      expect(
        tester.widget<Icon>(find.byKey(const Key('ai-score-star-4'))).icon,
        Icons.star_border,
      );
      expect(find.text('3 of 5 stars'), findsOneWidget);
    });

    testWidgets('renders 1 filled + 4 outline stars at 0.1', (tester) async {
      await pumpScore(tester, 0.1);
      expect(
        tester.widget<Icon>(find.byKey(const Key('ai-score-star-1'))).icon,
        Icons.star,
      );
      expect(
        tester.widget<Icon>(find.byKey(const Key('ai-score-star-2'))).icon,
        Icons.star_border,
      );
      expect(find.text('1 of 5 stars'), findsOneWidget);
    });

    testWidgets('renders NOTHING for a null score — honest absence, '
        'never a fabricated rating', (tester) async {
      await pumpScore(tester, null);
      expect(find.byKey(const Key('ai-score-stars')), findsNothing);
      expect(find.byType(Icon), findsNothing);
      expect(find.byType(SizedBox), findsOneWidget);
    });

    testWidgets('exposes the rating to screen readers via Semantics', (
      tester,
    ) async {
      await pumpScore(tester, 0.55);
      final semantics = tester.widget<Semantics>(
        find.byKey(const Key('ai-score-stars')),
      );
      expect(semantics.properties.label, '3 of 5 stars');
    });
  });
}
