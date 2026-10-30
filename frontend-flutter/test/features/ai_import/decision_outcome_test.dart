// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

// Tier-1/Tier-2 tests for the Decision Model outcome surface (issue #767).
//
// The defect: a configured Decision Model produced no star ratings and no
// explanation, because four different causes (never configured, client
// unavailable, scoring failed, nothing to score) all rendered the same empty
// space. These tests pin the two replacements — the job-level header line and
// the per-row failure note — and, just as importantly, that a job WITHOUT a
// recorded outcome keeps rendering nothing at all (never a guessed class,
// never a fabricated rating).

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/features/ai_import/import_jobs/decision_outcome.dart';
import 'package:frontend_flutter/l10n/generated/app_localizations_de.dart';
import 'package:frontend_flutter/l10n/generated/app_localizations_en.dart';

DecisionTelemetry _telemetry({
  DecisionOutcome outcome = DecisionOutcome.ran,
  LlmProvider? provider = LlmProvider.neuralwatt,
  String? model = 'glm-5.3',
  int failedRows = 0,
}) => DecisionTelemetry(
  (b) => b
    ..outcome = outcome
    ..failedRows = failedRows
    ..model = model
    ..provider = provider,
);

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  await tester.pump();
}

void main() {
  group('aiDecisionSummary — the outcome classes (issue #767)', () {
    final de = AppLocalizationsDe();
    final en = AppLocalizationsEn();

    test('ran names the effective Decision Model (both locales)', () {
      final telemetry = _telemetry();
      expect(
        aiDecisionSummary(de, telemetry).label,
        'Bewertet mit neuralwatt / glm-5.3.',
      );
      expect(
        aiDecisionSummary(en, telemetry).label,
        'Scored with neuralwatt / glm-5.3.',
      );
      expect(aiDecisionSummary(en, telemetry).tone, AiDecisionTone.info);
    });

    test('skipped_no_config states the absence instead of showing stars', () {
      final telemetry = _telemetry(
        outcome: DecisionOutcome.skippedNoConfig,
        provider: null,
        model: null,
      );
      expect(
        aiDecisionSummary(de, telemetry).label,
        'Ohne Entscheidungsmodell ausgeführt – keine Sternchen '
        '(kein Modell konfiguriert).',
      );
      expect(aiDecisionSummary(en, telemetry).tone, AiDecisionTone.warning);
    });

    test('client_unavailable names the CONFIGURED pair — the difference '
        'between "never configured" and "configured but unbuildable"', () {
      final telemetry = _telemetry(
        outcome: DecisionOutcome.clientUnavailable,
        model: 'clef-flash',
      );
      expect(
        aiDecisionSummary(en, telemetry).label,
        'Decision model neuralwatt / clef-flash unavailable — the preview was '
        'created without scoring.',
      );
      expect(aiDecisionSummary(en, telemetry).tone, AiDecisionTone.warning);
    });

    test('scoring_failed counts the affected rows and pluralizes', () {
      String label(int rows) => aiDecisionSummary(
        en,
        _telemetry(outcome: DecisionOutcome.scoringFailed, failedRows: rows),
      ).label;

      expect(
        label(1),
        'Scoring failed — 1 row without stars (neuralwatt / glm-5.3).',
      );
      expect(
        label(3),
        'Scoring failed — 3 rows without stars (neuralwatt / glm-5.3).',
      );
      expect(
        aiDecisionSummary(
          de,
          _telemetry(outcome: DecisionOutcome.scoringFailed, failedRows: 2),
        ).label,
        'Bewertung fehlgeschlagen – 2 Zeilen ohne Sternchen '
        '(neuralwatt / glm-5.3).',
      );
      expect(
        aiDecisionSummary(
          en,
          _telemetry(outcome: DecisionOutcome.scoringFailed, failedRows: 2),
        ).tone,
        AiDecisionTone.failed,
      );
    });

    test('skipped_not_applicable is informational, not a failure', () {
      final telemetry = _telemetry(
        outcome: DecisionOutcome.skippedNotApplicable,
        provider: null,
        model: null,
      );
      expect(
        aiDecisionSummary(en, telemetry).label,
        'This import needed no scoring.',
      );
      expect(aiDecisionSummary(en, telemetry).tone, AiDecisionTone.info);
    });

    test('a partially named pair degrades to the part the wire carries', () {
      expect(aiDecisionPairLabel(en, _telemetry(model: null)), 'neuralwatt');
      expect(
        aiDecisionPairLabel(en, _telemetry(provider: null, model: 'glm-5.3')),
        'glm-5.3',
      );
      expect(
        aiDecisionPairLabel(en, _telemetry(provider: null, model: null)),
        'unnamed model',
      );
      expect(
        aiDecisionPairLabel(de, _telemetry(provider: null, model: null)),
        'unbenanntes Modell',
      );
    });
  });

  group('AiDecisionOutcomeText — the header / cost-card line', () {
    testWidgets('renders the localized outcome of a recorded job', (
      tester,
    ) async {
      await _pump(
        tester,
        AiDecisionOutcomeText(
          telemetry: _telemetry(outcome: DecisionOutcome.skippedNoConfig),
        ),
      );
      expect(find.byKey(const Key('ai-decision-outcome')), findsOneWidget);
      expect(
        find.text(
          'Ran without a decision model — no stars (no model configured).',
        ),
        findsOneWidget,
      );
    });

    testWidgets('renders NOTHING when the job recorded no outcome (pre-#767 '
        'rows are never guessed into a class)', (tester) async {
      await _pump(tester, const AiDecisionOutcomeText(telemetry: null));
      expect(find.byKey(const Key('ai-decision-outcome')), findsNothing);
      expect(find.byType(Text), findsNothing);
    });
  });

  group('AiScoringFailedNote — the per-row degradation (issue #767)', () {
    testWidgets('states the failure instead of unexplained empty space', (
      tester,
    ) async {
      await _pump(tester, AiScoringFailedNote(draftRef: 'draft-1'));
      expect(
        find.byKey(const Key('ai-preview-scoring-failed-draft-1')),
        findsOneWidget,
      );
      expect(find.text('Scoring failed — no stars.'), findsOneWidget);
      // The failure state NEVER renders a rating: the star widget stays
      // silent because there is no score to show.
      expect(find.byKey(const Key('ai-score-stars')), findsNothing);
      expect(find.byIcon(Icons.star), findsNothing);
    });
  });
}
