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
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/core/problem_error.dart';
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

  group('AiDecisionOutcomeLine — a failed read is surfaced (AGENTS.md §4)', () {
    // The reported defect: `aiJobDecisionTelemetry` mapped an `Err` to `null`
    // exactly like "no outcome recorded", so a transient snapshot failure
    // looked like a pre-#767 job — and nothing invalidated the provider, so
    // the silent gap survived every rebuild. These tests pin the opposite: the
    // failure is an `AsyncError` rendered as the localized unavailable line
    // WITH the retry that re-reads the job.
    Future<List<int>> pumpLine(
      WidgetTester tester, {
      required Future<DecisionTelemetry?> Function() read,
    }) async {
      final reads = <int>[];
      var calls = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            aiJobDecisionTelemetryProvider.overrideWith((ref, jobId) {
              calls++;
              reads.add(calls);
              return read();
            }),
          ],
          child: const MaterialApp(
            home: Scaffold(body: AiDecisionOutcomeLine(jobId: 'job-1')),
          ),
        ),
      );
      await tester.pump();
      return reads;
    }

    testWidgets('an Err renders the unavailable line, not silence', (
      tester,
    ) async {
      await pumpLine(
        tester,
        read: () async => throw const ProblemError(code: 'http.500'),
      );
      expect(
        find.byKey(const Key('ai-decision-outcome-unavailable')),
        findsOneWidget,
      );
      expect(find.text('Scoring outcome could not be read.'), findsOneWidget);
      // The failure state never fabricates an outcome line or a rating.
      expect(find.byKey(const Key('ai-decision-outcome')), findsNothing);
      expect(find.byIcon(Icons.star), findsNothing);
    });

    testWidgets('the retry affordance re-reads the job and shows the outcome', (
      tester,
    ) async {
      var attempt = 0;
      await pumpLine(
        tester,
        read: () async {
          attempt++;
          if (attempt == 1) throw const ProblemError(code: 'http.500');
          return _telemetry();
        },
      );
      await tester.tap(find.byKey(const Key('ai-decision-outcome-retry')));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(
        find.byKey(const Key('ai-decision-outcome-unavailable')),
        findsNothing,
      );
      expect(find.byKey(const Key('ai-decision-outcome')), findsOneWidget);
      expect(find.text('Scored with neuralwatt / glm-5.3.'), findsOneWidget);
      expect(attempt, 2);
    });

    testWidgets('a successful read recording NO outcome stays silent (the '
        'unreadable case is the only one that speaks)', (tester) async {
      await pumpLine(tester, read: () async => null);
      expect(
        find.byKey(const Key('ai-decision-outcome-unavailable')),
        findsNothing,
      );
      expect(find.byKey(const Key('ai-decision-outcome')), findsNothing);
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
