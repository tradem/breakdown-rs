// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

// Tier-2 widget tests for the apply-run progress card (issue #762) plus a
// Tier-1 check that the apply SSE frame decodes through the same
// `standardSerializers` instance the generated client uses.
//
// The card is fed by a stream, so every case pushes frames explicitly — no
// sleeps, no polling, deterministic clock.

import 'dart:async';
import 'dart:convert';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/data/cache/clock.dart';
import 'package:frontend_flutter/data/cache/seasons_cache_providers.dart';
import 'package:frontend_flutter/features/ai_import/import_jobs/apply_controller.dart';
import 'package:frontend_flutter/features/ai_import/import_jobs/apply_screen.dart';
import 'package:frontend_flutter/features/ai_import/import_jobs/job_eta.dart';
import 'package:frontend_flutter/l10n/generated/app_localizations.dart';

const _jobId = 'job-apply-1';

/// The apply frame the backend emits (`core::ai::ApplyProgressFrame`), decoded
/// through `standardSerializers` — the same instance the generated client and
/// the job-frame decoder use. A frame whose nested `apply_progress` is `null`
/// is the run's end signal.
void _expectFrameDecodes() {
  const frame =
      '{"job_id":"01a14f76-74a8-72c6-a1a3-219586fe487a",'
      '"apply_progress":{"stage":"applying","applied":12,"total":57,'
      '"started_at":"2026-11-02T10:00:00Z",'
      '"updated_at":"2026-11-02T10:00:31Z"}}';
  final decoded = jsonDecode(frame) as Map<String, dynamic>;
  final progress = standardSerializers.deserializeWith(
    ApplyProgress.serializer,
    decoded['apply_progress'],
  );
  expect(progress, isNotNull);
  expect(progress!.applied, 12);
  expect(progress.total, 57);
  expect(progress.stage, ApplyStage.applying);
}

ApplyProgress _run({
  required DateTime startedAt,
  int applied = 4,
  int total = 10,
  ApplyStage stage = ApplyStage.applying,
  DateTime? updatedAt,
}) => ApplyProgress(
  (b) => b
    ..stage = stage
    ..applied = applied
    ..total = total
    ..startedAt = startedAt
    ..updatedAt = updatedAt ?? startedAt,
);

void main() {
  test(
    'the apply SSE frame decodes via standardSerializers',
    _expectFrameDecodes,
  );

  late StreamController<ApplyProgress?> frames;
  late DateTime now;

  setUp(() {
    frames = StreamController<ApplyProgress?>.broadcast();
    now = DateTime.utc(2026, 11, 2, 12);
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clockProvider.overrideWithValue(Clock(() => now)),
          aiApplyRunProvider(_jobId).overrideWith((ref) => frames.stream),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: const [Locale('en')],
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: const Scaffold(
            body: SingleChildScrollView(
              child: AiApplyProgressCard(jobId: _jobId),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('no run yet renders the indeterminate line and no ETA', (
    tester,
  ) async {
    await pump(tester);
    expect(find.byKey(const Key('ai-apply-progress-pending')), findsOneWidget);
    expect(
      find.byKey(const Key('ai-apply-progress-eta')),
      findsNothing,
      reason: 'a run that has not started has nothing to estimate',
    );
    expect(
      tester
          .widget<LinearProgressIndicator>(
            find.byKey(const Key('ai-apply-progress-bar')),
          )
          .value,
      isNull,
      reason: 'indeterminate, never a fabricated percentage',
    );
  });

  testWidgets('a pushed run renders rows, a determinate bar and a coarse ETA', (
    tester,
  ) async {
    await pump(tester);
    // 4 of 10 rows in 4 minutes → 1 min/row → 6 min left. The latest frame
    // is fresh, otherwise the stall rule correctly withholds the number.
    frames.add(
      _run(startedAt: now.subtract(const Duration(minutes: 4)), updatedAt: now),
    );
    await tester.pump();

    expect(find.byKey(const Key('ai-apply-progress')), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('ai-apply-progress-stage')))
          .data,
      'Row 4 of 10 applied',
    );
    expect(
      tester
          .widget<LinearProgressIndicator>(
            find.byKey(const Key('ai-apply-progress-bar')),
          )
          .value,
      closeTo(0.4, 0.001),
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('ai-apply-progress-eta'))).data,
      'About 6 min left',
    );
  });

  testWidgets('fewer than two rows shows "estimating", never a number', (
    tester,
  ) async {
    await pump(tester);
    frames.add(
      _run(
        startedAt: now.subtract(const Duration(minutes: 1)),
        applied: 1,
        updatedAt: now,
      ),
    );
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const Key('ai-apply-progress-eta'))).data,
      'Estimating remaining time …',
    );
  });

  testWidgets('the finalizing stage replaces the row counter', (tester) async {
    await pump(tester);
    frames.add(
      _run(
        startedAt: now.subtract(const Duration(minutes: 10)),
        applied: 10,
        stage: ApplyStage.finalizing,
        updatedAt: now,
      ),
    );
    await tester.pump();
    expect(
      tester
          .widget<Text>(find.byKey(const Key('ai-apply-progress-stage')))
          .data,
      'All rows applied – finishing up …',
    );
  });

  testWidgets('a silent run drops its estimate ("delayed")', (tester) async {
    await pump(tester);
    frames.add(
      _run(
        startedAt: now.subtract(const Duration(minutes: 4)),
        // The last frame is an hour old: the run is not reporting anymore.
        updatedAt: now.subtract(const Duration(hours: 1)),
      ),
    );
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const Key('ai-apply-progress-eta'))).data,
      'Delayed – no reliable estimate.',
    );
  });

  testWidgets('the end-of-run frame falls back to the indeterminate line', (
    tester,
  ) async {
    await pump(tester);
    frames.add(
      _run(startedAt: now.subtract(const Duration(minutes: 4)), updatedAt: now),
    );
    await tester.pump();
    expect(find.byKey(const Key('ai-apply-progress')), findsOneWidget);

    frames.add(null);
    await tester.pump();
    expect(find.byKey(const Key('ai-apply-progress')), findsNothing);
    expect(find.byKey(const Key('ai-apply-progress-pending')), findsOneWidget);
  });

  test('the shared estimator drives both phases identically', () {
    // The apply path and the extraction path must not drift into different
    // honesty rules: same inputs, same estimate.
    final startedAt = now.subtract(const Duration(minutes: 2));
    final fromApply = estimateEtaFrom(
      startedAt: startedAt,
      done: 2,
      total: 8,
      now: now,
    );
    final fromExtraction = estimateAiJobEta(
      progress: AiImportProgress(
        (b) => b
          ..stage = AiImportStage.extracting
          ..chunk = 2
          ..chunksTotal = 8
          ..startedAt = startedAt,
      ),
      now: now,
    );
    expect(fromApply, isNotNull);
    expect(fromApply!.upper, fromExtraction!.upper);
    expect(fromApply.perUnit, fromExtraction.perUnit);
  });
}
