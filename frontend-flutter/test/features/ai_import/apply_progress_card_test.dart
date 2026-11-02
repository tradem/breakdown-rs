// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

// Tier-1 fold tests for the apply-run states and Tier-2 widget + golden tests
// for the card that renders them (issue #762) plus a Tier-1 check that the
// apply SSE frame decodes through the same `standardSerializers` instance the
// generated client uses.
//
// The card is fed by a stream, so every case pushes frames explicitly — no
// sleeps, no polling, deterministic clock.

import 'dart:async';
import 'dart:convert';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/core/result.dart';
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

AiApplyRunRunning _running({
  required DateTime startedAt,
  int applied = 4,
  int total = 10,
  ApplyStage stage = ApplyStage.applying,
  DateTime? updatedAt,
}) => AiApplyRunRunning(
  _run(
    startedAt: startedAt,
    applied: applied,
    total: total,
    stage: stage,
    updatedAt: updatedAt,
  ),
);

void main() {
  test(
    'the apply SSE frame decodes via standardSerializers',
    _expectFrameDecodes,
  );

  late StreamController<AiApplyRunState> states;
  late DateTime now;

  setUp(() {
    states = StreamController<AiApplyRunState>.broadcast();
    now = DateTime.utc(2026, 11, 2, 12);
  });

  Future<void> pump(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clockProvider.overrideWithValue(Clock(() => now)),
          aiApplyRunProvider(_jobId).overrideWith((ref) => states.stream),
        ],
        child: MaterialApp(
          locale: locale,
          supportedLocales: const [Locale('en'), Locale('de')],
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

  // --- Tier 1: the fold that decides what the card renders ----------------

  group('foldApplyRun', () {
    Future<List<AiApplyRunState>> fold(List<Result<ApplyProgress?>> events) =>
        foldApplyRun(Stream.fromIterable(events)).toList();

    test('a progress frame is a running state', () async {
      final progress = _run(startedAt: now, applied: 3);
      final out = await fold([Right(progress)]);
      expect(out, hasLength(1));
      expect(out.single, isA<AiApplyRunRunning>());
      expect((out.single as AiApplyRunRunning).progress.applied, 3);
    });

    test(
      'the end frame after a run KEEPS the run (never "nothing started")',
      () async {
        final progress = _run(startedAt: now, applied: 7);
        final out = await fold([Right(progress), const Right(null)]);
        expect(out, hasLength(2));
        expect(out.first, isA<AiApplyRunRunning>());
        expect(out.last, isA<AiApplyRunFinished>());
        expect(
          (out.last as AiApplyRunFinished).last.applied,
          7,
          reason: 'the ended run must keep its last counters for the card',
        );
      },
    );

    test('a null frame BEFORE any run stays idle', () async {
      final out = await fold([const Right(null)]);
      expect(out.single, isA<AiApplyRunIdle>());
    });

    test(
      'a stream failure is surfaced, carrying what the run reached',
      () async {
        final progress = _run(startedAt: now, applied: 5);
        final out = await fold([
          Right(progress),
          const Left(ProblemError(code: 'ai_import.watch_exhausted')),
        ]);
        expect(out.last, isA<AiApplyRunFailed>());
        final failed = out.last as AiApplyRunFailed;
        expect(failed.error.code, 'ai_import.watch_exhausted');
        expect(failed.last?.applied, 5);
      },
    );

    test('a failure before any frame carries no counters', () async {
      final out = await fold([
        const Left(ProblemError(code: 'domain.forbidden', status: 403)),
      ]);
      expect((out.single as AiApplyRunFailed).last, isNull);
    });
  });

  // --- Tier 2: the card ----------------------------------------------------

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

  testWidgets('an idle state renders the indeterminate line', (tester) async {
    await pump(tester);
    states.add(const AiApplyRunIdle());
    await tester.pump();
    expect(find.byKey(const Key('ai-apply-progress-pending')), findsOneWidget);
  });

  testWidgets('a pushed run renders rows, a determinate bar and a coarse ETA', (
    tester,
  ) async {
    await pump(tester);
    // 4 of 10 rows in 4 minutes → 1 min/row → 6 min left. The latest frame
    // is fresh, otherwise the stall rule correctly withholds the number.
    states.add(
      _running(
        startedAt: now.subtract(const Duration(minutes: 4)),
        updatedAt: now,
      ),
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
    states.add(
      _running(
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

  testWidgets('a NEW apply run does not inherit the previous run cadence', (
    tester,
  ) async {
    await pump(tester);
    // Run 1: 4 of 10 rows in 4 minutes → 1 min/row → 6 min left.
    states.add(
      _running(
        startedAt: now.subtract(const Duration(minutes: 4)),
        updatedAt: now,
      ),
    );
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const Key('ai-apply-progress-eta'))).data,
      'About 6 min left',
    );

    // A second apply of the same preview starts fresh: 5 of 10 rows in 10 s is
    // a completely different cadence, and smoothing it against run 1 would keep
    // showing minutes.
    states.add(
      _running(
        startedAt: now.subtract(const Duration(seconds: 10)),
        applied: 5,
        updatedAt: now,
      ),
    );
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const Key('ai-apply-progress-eta'))).data,
      'Almost done …',
      reason: 'a new run must not inherit the previous run\'s rate',
    );
  });

  testWidgets(
    'the estimate is anchored to the run frame stamp, not the clock',
    (tester) async {
      await pump(tester);
      // Run time = updated_at − started_at = 2 min. A client-clock anchor would
      // read 3 min and inflate every figure by 50 % (58 min vs 87 min).
      states.add(
        _running(
          startedAt: now.subtract(const Duration(minutes: 3)),
          applied: 2,
          total: 60,
          updatedAt: now.subtract(const Duration(minutes: 1)),
        ),
      );
      await tester.pump();
      expect(
        tester
            .widget<Text>(find.byKey(const Key('ai-apply-progress-eta')))
            .data,
        'About 58 min left',
      );
    },
  );

  testWidgets(
    'the finalizing stage replaces the row counter and drops the ETA',
    (tester) async {
      await pump(tester);
      states.add(
        _running(
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
      expect(
        find.byKey(const Key('ai-apply-progress-eta')),
        findsNothing,
        reason:
            'no row work is left in the finalizing stage, so no estimate may '
            'claim "almost done" next to a finished row counter',
      );
    },
  );

  testWidgets('a silent run drops its estimate ("delayed")', (tester) async {
    await pump(tester);
    states.add(
      _running(
        // 4 of 10 rows in one hour → a 15-min cadence, so the stall window is
        // 45 min. The newest frame is an hour old: well past it.
        startedAt: now.subtract(const Duration(hours: 2)),
        updatedAt: now.subtract(const Duration(hours: 1)),
      ),
    );
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const Key('ai-apply-progress-eta'))).data,
      'Delayed – no reliable estimate.',
    );
  });

  testWidgets(
    'the end-of-run frame keeps the finishing state, not the waiting line',
    (tester) async {
      await pump(tester);
      states.add(
        _running(
          startedAt: now.subtract(const Duration(minutes: 4)),
          updatedAt: now,
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('ai-apply-progress')), findsOneWidget);

      // The server's final `null` frame arrives while the apply POST is still
      // out: the card may not claim the run never started. The run reached its
      // plan (10 of 10), so the completion copy is the truthful one.
      states.add(
        AiApplyRunFinished(
          _run(
            startedAt: now.subtract(const Duration(minutes: 4)),
            applied: 10,
            updatedAt: now,
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('ai-apply-progress-pending')), findsNothing);
      expect(
        find.byKey(const Key('ai-apply-progress-finished')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('ai-apply-progress-stage')))
            .data,
        'All rows applied – finishing up …',
        reason: 'a started run that ended is closing out, never "not started"',
      );
      expect(
        find.byKey(const Key('ai-apply-progress-eta')),
        findsNothing,
        reason: 'nothing is left to estimate once the run ended',
      );
    },
  );

  testWidgets('a failed stream is surfaced with a retry affordance', (
    tester,
  ) async {
    await pump(tester);
    states.add(
      const AiApplyRunFailed(ProblemError(code: 'ai_import.watch_exhausted')),
    );
    await tester.pump();
    expect(find.byKey(const Key('ai-apply-progress-error')), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('ai-apply-progress-error')))
          .data,
      'Row progress could not be loaded (ai_import.watch_exhausted). '
      'The apply keeps running on the server.',
      reason: 'code-keyed copy, never the server detail',
    );
    expect(find.byKey(const Key('ai-apply-progress-retry')), findsOneWidget);
    expect(
      find.byKey(const Key('ai-apply-progress-pending')),
      findsNothing,
      reason: 'a failed watch must not masquerade as "not started yet"',
    );
  });

  testWidgets('a failed stream keeps the last counters visible', (
    tester,
  ) async {
    await pump(tester);
    states.add(
      AiApplyRunFailed(
        const ProblemError(code: 'transport.receiveTimeout'),
        last: _run(
          startedAt: now.subtract(const Duration(minutes: 4)),
          applied: 6,
          updatedAt: now,
        ),
      ),
    );
    await tester.pump();
    expect(
      find.byKey(const Key('ai-apply-progress-finished')),
      findsOneWidget,
      reason: 'the counters the run reached stay on screen',
    );
    expect(find.byKey(const Key('ai-apply-progress-error')), findsOneWidget);
  });

  testWidgets('a run that ended before its last row keeps the row counter', (
    tester,
  ) async {
    await pump(tester);
    // A failed apply also ends with a frame (the worker clears the run), so the
    // completion copy would be a lie for a partial run.
    states.add(
      AiApplyRunFinished(
        _run(
          startedAt: now.subtract(const Duration(minutes: 4)),
          applied: 6,
          total: 10,
          updatedAt: now,
        ),
      ),
    );
    await tester.pump();
    expect(
      tester
          .widget<Text>(find.byKey(const Key('ai-apply-progress-stage')))
          .data,
      'Row 6 of 10 applied',
      reason: '6 of 10 is not "all rows applied"',
    );
    expect(
      tester
          .widget<LinearProgressIndicator>(
            find.byKey(const Key('ai-apply-progress-bar')),
          )
          .value,
      closeTo(0.6, 0.001),
    );
  });

  testWidgets('an AUTHZ-GATE denial renders the localized 403', (tester) async {
    await pump(tester);
    states.add(
      const AiApplyRunDenied(
        ProblemError(code: 'ai_import.forbidden', status: 403),
      ),
    );
    await tester.pump();
    expect(
      tester
          .widget<Text>(find.byKey(const Key('ai-apply-progress-denied')))
          .data,
      'You do not have access to this AI import job.',
    );
    expect(
      find.byKey(const Key('ai-apply-progress-pending')),
      findsNothing,
      reason: 'a resolved denial is not a pending gate',
    );
    expect(
      find.byKey(const Key('ai-apply-progress-retry')),
      findsNothing,
      reason: 'a denial is not a transport failure — membership decides',
    );
  });

  testWidgets('a pending gate keeps the waiting line, never the 403 copy', (
    tester,
  ) async {
    await pump(tester);
    states.add(
      const AiApplyRunDenied(ProblemError(code: 'membership.pending')),
    );
    await tester.pump();
    expect(find.byKey(const Key('ai-apply-progress-pending')), findsOneWidget);
    expect(
      find.byKey(const Key('ai-apply-progress-denied')),
      findsNothing,
      reason: 'a pending membership disables, it never denies (D3)',
    );
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

  // --- Tier 2: goldens (AGENTS.md §6 — a stateful widget that renders domain
  // state gets a golden per state; German is the template locale) -----------

  testWidgets('golden: pending state', (tester) async {
    await pump(tester, locale: const Locale('de'));
    await expectLater(
      find.byType(AiApplyProgressCard),
      matchesGoldenFile('goldens/apply_progress_pending_de.png'),
    );
  });

  testWidgets('golden: running state', (tester) async {
    await pump(tester, locale: const Locale('de'));
    states.add(
      AiApplyRunRunning(
        _run(
          startedAt: now.subtract(const Duration(minutes: 4)),
          updatedAt: now,
        ),
      ),
    );
    await tester.pump();
    await expectLater(
      find.byType(AiApplyProgressCard),
      matchesGoldenFile('goldens/apply_progress_running_de.png'),
    );
  });

  testWidgets('golden: finalizing state', (tester) async {
    await pump(tester, locale: const Locale('de'));
    states.add(
      AiApplyRunRunning(
        _run(
          startedAt: now.subtract(const Duration(minutes: 10)),
          applied: 10,
          stage: ApplyStage.finalizing,
          updatedAt: now,
        ),
      ),
    );
    await tester.pump();
    await expectLater(
      find.byType(AiApplyProgressCard),
      matchesGoldenFile('goldens/apply_progress_finalizing_de.png'),
    );
  });

  testWidgets('golden: ended run (the end frame while the POST is out)', (
    tester,
  ) async {
    await pump(tester, locale: const Locale('de'));
    states.add(
      AiApplyRunFinished(
        _run(
          startedAt: now.subtract(const Duration(minutes: 4)),
          applied: 10,
          updatedAt: now,
        ),
      ),
    );
    await tester.pump();
    await expectLater(
      find.byType(AiApplyProgressCard),
      matchesGoldenFile('goldens/apply_progress_finished_de.png'),
    );
  });

  testWidgets('golden: failed stream with a retry affordance', (tester) async {
    await pump(tester, locale: const Locale('de'));
    states.add(
      const AiApplyRunFailed(ProblemError(code: 'ai_import.watch_exhausted')),
    );
    await tester.pump();
    await expectLater(
      find.byType(AiApplyProgressCard),
      matchesGoldenFile('goldens/apply_progress_failed_de.png'),
    );
  });

  testWidgets('golden: AUTHZ-GATE denial', (tester) async {
    await pump(tester, locale: const Locale('de'));
    states.add(
      const AiApplyRunDenied(
        ProblemError(code: 'ai_import.forbidden', status: 403),
      ),
    );
    await tester.pump();
    await expectLater(
      find.byType(AiApplyProgressCard),
      matchesGoldenFile('goldens/apply_progress_denied_de.png'),
    );
  });
}
