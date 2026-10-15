// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

// Tier-2 widget tests for the job-status screen
// (`flutter-ai-import-workflow` tasks 3.4 + D3/D5): all six statuses
// rendered honestly (pending/running indeterminate — never a fabricated
// percentage), the retryable failed budget, the terminal error cards
// with `last_error` as SECONDARY detail only, the duplicate callout, the
// honest no-cancel copy, and goldens {light,dark}×{android,macos}.

import 'dart:async';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:frontend_flutter/app_config.dart';
import 'package:frontend_flutter/auth/auth_providers.dart';
import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/l10n/generated/app_localizations.dart';
import 'package:drift/native.dart';
import 'package:frontend_flutter/data/ai_import_providers.dart';
import 'package:frontend_flutter/data/ai_import_repository.dart';
import 'package:frontend_flutter/data/cache/ai_import_jobs_cache_dao.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/clock.dart';
import 'package:frontend_flutter/data/cache/seasons_cache_providers.dart';
import 'package:frontend_flutter/domain/reconciliation/reconciliation_scheduler.dart';
import 'package:frontend_flutter/features/ai_import/import_jobs/job_status_screen.dart';

AiImportJob _job(
  JobStatus status, {
  int retries = 0,
  int maxRetries = 3,
  String? lastError,
  DateTime? nextAttemptAt,
  List<AiImportAttempt> attempts = const [],
}) => AiImportJob(
  (b) => b
    ..id = 'job-1'
    ..userId = 'dev-user'
    ..status = status
    ..documentKind = DocumentKind.schedule
    ..sourceFormat = SourceFormat.csv
    ..dedupKey = 'dedup'
    ..documentDigest = 'digest'
    ..sourceHandle = 'handle'
    ..retries = retries
    ..maxRetries = maxRetries
    ..lastError = lastError
    ..nextAttemptAt = nextAttemptAt
    ..attempts.addAll(attempts)
    ..createdAt = DateTime.utc(2026, 1, 1)
    ..updatedAt = DateTime.utc(2026, 1, 1),
);

/// One recorded attempt for the history (issue #637/#639). `code` is the
/// stable problem identity the UI localizes on; `errorSummary` is the raw
/// free-form text that must never render as identity.
AiImportAttempt _attempt(
  int attemptNo, {
  String? code,
  String? errorSummary,
  bool retryable = true,
  JobStatus status = JobStatus.failed,
}) => AiImportAttempt(
  (b) => b
    ..attemptNo = attemptNo
    ..code = code
    ..errorSummary = errorSummary
    ..retryable = retryable
    ..status = status
    ..createdAt = DateTime.utc(2026, 1, 1),
);

const devAuthConfig = AppConfig(
  flavor: Flavor.dev,
  apiBase: 'http://10.0.2.2:3000',
  oidcIss: '',
  devAuthSub: 'dev-user',
  oidcAudience: '',
  oidcClientId: '',
  oidcRedirectUri: '',
  devIdpInsecure: '',
  appVersion: '1.0.0+1',
  defaultProjectId: 'series-1',
);

void main() {
  CacheDatabase? db;
  ProviderContainer? container;
  late ValueNotifier<Result<AiImportJob>> job;
  // Injectable clock (issue #639): the retry ETA reads `clockProvider`, so a
  // mutable `now` lets a test advance time and assert the live copy without
  // sleeping. Goldens keep it fixed.
  var now = DateTime.utc(2026, 1, 1, 12);

  setUp(() {
    // Every test starts from a fixed instant; the ETA test advances it
    // explicitly and goldens stay deterministic (deterministic-tests rule).
    now = DateTime.utc(2026, 1, 1, 12);
  });

  Future<void> setupContainer(Result<AiImportJob> initial) async {
    // A re-setup (the two-status loop) disposes the previous container
    // FIRST — riverpod's 0ms disposal timers must not be pending when
    // the fake_async test body ends.
    final previous = container;
    if (previous != null) previous.dispose();
    db = CacheDatabase(NativeDatabase.memory());
    addTearDown(db!.close);
    job = ValueNotifier(initial);
    container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(devAuthConfig),
        clockProvider.overrideWithValue(Clock(() => now)),
        aiImportRepositoryProvider.overrideWithValue(
          _StubRepository(BreakdownApi(), AiImportJobsCacheDao(db!))
            ..jobNotifier = job,
        ),
      ],
    );
    addTearDown(() {
      try {
        container?.dispose();
      } on StateError {
        // Already disposed by the test body — fine.
      }
    });
    await container!.read(authSessionControllerProvider.notifier).signIn();
  }

  Future<void> pumpScreen(
    WidgetTester tester, {
    bool duplicate = false,
    ThemeMode mode = ThemeMode.light,
    TargetPlatform? platform,
  }) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // Restore, don't clear: pumpScreen does not own the platform
    // override — the golden helpers set it around the capture (review).
    final previousOverride = debugDefaultTargetPlatformOverride;
    try {
      if (platform != null) {
        debugDefaultTargetPlatformOverride = platform;
      }
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container!,
          child: MaterialApp(
            theme: ThemeData.light(),
            darkTheme: ThemeData.dark(),
            themeMode: mode,
            locale: const Locale('en'),
            supportedLocales: const [Locale('en'), Locale('de')],
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            // Goldens must be deterministic (AGENTS.md §6): the Karl
            // Kleiderbügel excited wobble is time-driven, so the golden
            // pumps freeze animations — the static excited pose is
            // exactly the remove-animations rendering (spec
            // `flutter-easter-eggs`).
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            ),
            home: AiJobStatusScreen(jobId: 'job-1', duplicate: duplicate),
          ),
        ),
      );
      // The controller's watch subscription delivers via microtasks.
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
    } finally {
      debugDefaultTargetPlatformOverride = previousOverride;
    }
  }

  testWidgets('pending/running render the indeterminate affordance — no '
      'fabricated percentage', (tester) async {
    await setupContainer(Right(_job(JobStatus.pending)));
    await pumpScreen(tester);
    expect(find.byKey(const Key('ai-job-in-progress')), findsOneWidget);
    expect(find.byKey(const Key('ai-job-indeterminate')), findsOneWidget);
    expect(find.textContaining('Queued'), findsOneWidget);

    job.value = Right(_job(JobStatus.running));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(find.textContaining('Processing your document'), findsOneWidget);
    await tester.pump();
  });

  testWidgets('retryable failed shows the retry budget (retries/'
      'max_retries), not a terminal card', (tester) async {
    await setupContainer(
      Right(_job(JobStatus.failed, retries: 1, maxRetries: 4)),
    );
    await pumpScreen(tester);
    expect(find.byKey(const Key('ai-job-retryable')), findsOneWidget);
    expect(find.textContaining('retry is scheduled'), findsOneWidget);
    expect(find.byKey(const Key('ai-job-retry-budget')), findsOneWidget);
    expect(find.textContaining('Retry 2 of 5'), findsOneWidget);
    await tester.pump();
  });

  testWidgets('retryable failed shows a LIVE next-retry ETA derived from '
      'next_attempt_at (issue #639)', (tester) async {
    now = DateTime.utc(2026, 1, 1, 12);
    await setupContainer(
      Right(
        _job(
          JobStatus.failed,
          retries: 1,
          maxRetries: 4,
          nextAttemptAt: now.add(const Duration(minutes: 4)),
          attempts: [_attempt(1, code: 'domain.service-unavailable')],
        ),
      ),
    );
    await pumpScreen(tester);
    expect(find.byKey(const Key('ai-job-next-retry')), findsOneWidget);
    expect(find.textContaining('Retry in ~4 min'), findsOneWidget);

    // Time advances past a bucket; the bounded ticker refreshes the copy
    // without a per-frame rebuild.
    now = now.add(const Duration(minutes: 2));
    await tester.pump(const Duration(seconds: 31));
    expect(find.textContaining('Retry in ~2 min'), findsOneWidget);
    await tester.pump();
  });

  testWidgets('retryable failed without next_attempt_at degrades honestly — '
      'no fabricated countdown (issue #639)', (tester) async {
    await setupContainer(
      Right(
        _job(
          JobStatus.failed,
          attempts: [_attempt(1, code: 'dependency.auth-failed')],
        ),
      ),
    );
    await pumpScreen(tester);
    expect(find.byKey(const Key('ai-job-next-retry')), findsOneWidget);
    expect(find.textContaining('Retry scheduled'), findsOneWidget);
    // No "~<n>" bucket copy is rendered when the due time is unknown.
    expect(find.textContaining('Retry in ~'), findsNothing);
    await tester.pump();
  });

  testWidgets('retryable failed shows the newest attempt reason keyed on the '
      'problem code, never the raw summary (issue #639)', (tester) async {
    await setupContainer(
      Right(
        _job(
          JobStatus.failed,
          attempts: [
            _attempt(
              2,
              code: 'dependency.auth-failed',
              errorSummary:
                  'dependency authentication failed: KV read '
                  'returned 403 Forbidden',
            ),
            _attempt(1, code: 'domain.service-unavailable'),
          ],
        ),
      ),
    );
    await pumpScreen(tester);
    expect(find.byKey(const Key('ai-job-failure-reason')), findsOneWidget);
    expect(find.textContaining('credential was rejected'), findsOneWidget);
    // The raw backend summary never renders as identity on the retryable card.
    expect(find.textContaining('KV read returned 403'), findsNothing);
    await tester.pump();
  });

  testWidgets('an absent or unknown attempt code renders the generic '
      'localized reason (issue #639)', (tester) async {
    await setupContainer(
      Right(
        _job(
          JobStatus.failed,
          attempts: [
            _attempt(
              1,
              code: 'some.future-code',
              errorSummary: 'raw backend detail',
            ),
          ],
        ),
      ),
    );
    await pumpScreen(tester);
    // The generic arm echoes the stable code (an identifier, not `detail`).
    expect(find.textContaining('some.future-code'), findsOneWidget);
    expect(find.textContaining('raw backend detail'), findsNothing);

    // Absence branch: no code at all.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await setupContainer(
      Right(
        _job(
          JobStatus.failed,
          attempts: [_attempt(1, errorSummary: 'raw backend detail')],
        ),
      ),
    );
    await pumpScreen(tester);
    expect(find.textContaining('unknown reason'), findsOneWidget);
    expect(find.textContaining('raw backend detail'), findsNothing);
    await tester.pump();
  });

  testWidgets('terminal card adds the per-attempt history with code-keyed '
      'reasons, keeping last_error as secondary detail (issue #639)', (
    tester,
  ) async {
    await setupContainer(
      Right(
        _job(
          JobStatus.deadLetter,
          lastError: 'the raw last error',
          attempts: [
            _attempt(2, code: 'dependency.auth-failed'),
            _attempt(1, code: 'domain.service-unavailable'),
          ],
        ),
      ),
    );
    await pumpScreen(tester);
    expect(find.byKey(const Key('ai-job-attempt-history')), findsOneWidget);
    expect(find.byKey(const Key('ai-job-attempt-2')), findsOneWidget);
    expect(find.byKey(const Key('ai-job-attempt-1')), findsOneWidget);
    expect(find.textContaining('Attempt 2:'), findsOneWidget);
    expect(find.textContaining('credential was rejected'), findsOneWidget);
    expect(find.byKey(const Key('ai-job-last-error')), findsOneWidget);
    await tester.pump();
  });

  testWidgets('terminal error cards: status-keyed primary copy, '
      'last_error as SECONDARY detail only (dead_letter + '
      'payload_unavailable)', (tester) async {
    for (final (status, copy) in [
      (JobStatus.deadLetter, 'gave up after repeated failures'),
      (JobStatus.payloadUnavailable, 'no longer available on the server'),
    ]) {
      // Unmount the previous tree BEFORE its container is disposed (the
      // unmount path schedules riverpod's 0ms disposal timer).
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await setupContainer(
        Right(_job(status, lastError: 'LLM provider exploded at step 3')),
      );
      await pumpScreen(tester);
      expect(find.byKey(const Key('ai-job-terminal-error')), findsOneWidget);
      // The primary copy is the STATUS copy (keyed on the status)…
      expect(find.textContaining(copy), findsOneWidget);
      // …and the raw error string renders ONLY as the secondary detail.
      final detail = tester.widget<Text>(
        find.byKey(const Key('ai-job-last-error')),
      );
      expect(detail.data, 'LLM provider exploded at step 3');
      await tester.pump();
    }
  });

  testWidgets('succeeded opens the preview path', (tester) async {
    await setupContainer(Right(_job(JobStatus.succeeded)));
    await pumpScreen(tester);
    expect(find.byKey(const Key('ai-job-succeeded')), findsOneWidget);
    expect(find.byKey(const Key('ai-job-open-preview')), findsOneWidget);
    await tester.pump();
  });

  testWidgets('the duplicate callout renders and nothing implies a second '
      'import; the honest no-cancel notice is always present', (tester) async {
    await setupContainer(Right(_job(JobStatus.running)));
    await pumpScreen(tester, duplicate: true);
    expect(find.byKey(const Key('ai-job-duplicate-callout')), findsOneWidget);
    expect(find.textContaining('No second import was created'), findsOneWidget);
    expect(find.byKey(const Key('ai-job-no-cancel')), findsOneWidget);
    expect(find.textContaining('there is no cancel'), findsOneWidget);
    await tester.pump();
  });

  testWidgets('a STREAM error from repo.watch maps into the error state — '
      'the error card renders with the re-arm affordance instead of an '
      'eternal spinner or an unhandled zone error (review)', (tester) async {
    await setupContainer(Right(_job(JobStatus.pending)));
    (container!.read(
      aiImportRepositoryProvider,
    ) as _StubRepository).errorToEmit = StateError(
      'watch generator fault',
    );
    await pumpScreen(tester);
    // The initial delivery lands, then the stream fault (microtask) —
    // mapped into the state, never left spinning.
    expect(find.byKey(const Key('ai-job-watch-error')), findsOneWidget);
    await tester.pump();
  });

  group('AiJobStatusScreen goldens (3.4): {light,dark}×{android,macos}', () {
    Future<void> pumpGolden(
      WidgetTester tester, {
      required String golden,
      required ThemeMode mode,
      required TargetPlatform platform,
    }) async {
      try {
        debugDefaultTargetPlatformOverride = platform;
        await pumpScreen(tester, mode: mode, platform: platform);
        await expectLater(
          find.byType(AiJobStatusScreen),
          matchesGoldenFile('goldens/$golden'),
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }

    testWidgets('golden light android (running + duplicate callout)', (
      tester,
    ) async {
      await setupContainer(Right(_job(JobStatus.running)));
      await pumpGolden(
        tester,
        golden: 'ai_job_status_light_android.png',
        mode: ThemeMode.light,
        platform: TargetPlatform.android,
      );
    });

    testWidgets('golden dark android (running + duplicate callout)', (
      tester,
    ) async {
      await setupContainer(Right(_job(JobStatus.running)));
      await pumpGolden(
        tester,
        golden: 'ai_job_status_dark_android.png',
        mode: ThemeMode.dark,
        platform: TargetPlatform.android,
      );
    });

    testWidgets('golden light macos (running + duplicate callout)', (
      tester,
    ) async {
      await setupContainer(Right(_job(JobStatus.running)));
      await pumpGolden(
        tester,
        golden: 'ai_job_status_light_macos.png',
        mode: ThemeMode.light,
        platform: TargetPlatform.macOS,
      );
    });

    testWidgets('golden dark macos (running + duplicate callout)', (
      tester,
    ) async {
      await setupContainer(Right(_job(JobStatus.running)));
      await pumpGolden(
        tester,
        golden: 'ai_job_status_dark_macos.png',
        mode: ThemeMode.dark,
        platform: TargetPlatform.macOS,
      );
    });

    // Retryable-with-ETA (issue #639): the live "next retry in …" and the
    // code-keyed reason, {light,dark}×{android,macos}.
    for (final (mode, platform, suffix) in [
      (ThemeMode.light, TargetPlatform.android, 'light_android'),
      (ThemeMode.dark, TargetPlatform.android, 'dark_android'),
      (ThemeMode.light, TargetPlatform.macOS, 'light_macos'),
      (ThemeMode.dark, TargetPlatform.macOS, 'dark_macos'),
    ]) {
      testWidgets('golden $suffix (retryable with ETA)', (tester) async {
        await setupContainer(
          Right(
            _job(
              JobStatus.failed,
              retries: 1,
              maxRetries: 4,
              nextAttemptAt: DateTime.utc(2026, 1, 1, 12, 4),
              attempts: [
                _attempt(
                  2,
                  code: 'domain.service-unavailable',
                  errorSummary: 'service unavailable: upstream 503',
                ),
                _attempt(1, code: 'domain.service-unavailable'),
              ],
            ),
          ),
        );
        await pumpGolden(
          tester,
          golden: 'ai_job_status_retryable_$suffix.png',
          mode: mode,
          platform: platform,
        );
      });

      testWidgets('golden $suffix (retryable, unknown ETA)', (tester) async {
        await setupContainer(
          Right(
            _job(
              JobStatus.failed,
              retries: 1,
              maxRetries: 4,
              attempts: [_attempt(1, code: 'dependency.auth-failed')],
            ),
          ),
        );
        await pumpGolden(
          tester,
          golden: 'ai_job_status_retryable_unknown_eta_$suffix.png',
          mode: mode,
          platform: platform,
        );
      });
    }
  });
}

/// A stub repository: the job read serves the scripted [jobNotifier]
/// value; the watch emits that value once and stops (the state machine
/// is covered at the controller tier — the screen tests pin RENDERING).
class _StubRepository extends AiImportRepository {
  _StubRepository(super.api, super.cache);

  late ValueNotifier<Result<AiImportJob>> jobNotifier;

  @override
  Future<Result<AiImportJob>> getJobAndCache(
    String id, {
    Clock clock = Clock.system,
  }) async => jobNotifier.value;

  @override
  Stream<Result<AiImportJob>> watch(
    String jobId, {
    ReconciliationScheduler scheduler = const ExponentialBackoffScheduler(),
    int maxAttempts = 30,
  }) {
    late StreamController<Result<AiImportJob>> controller;
    void onChange() => controller.add(jobNotifier.value);
    controller = StreamController<Result<AiImportJob>>(
      onListen: () {
        jobNotifier.addListener(onChange);
        controller.add(jobNotifier.value);
        // A fault INSIDE the watch generator (deserialization failure,
        // an exception escaping the Result mapping) surfaces as a stream
        // error (review: the controller must map it into the state).
        final err = errorToEmit;
        if (err != null) {
          scheduleMicrotask(() => controller.addError(err));
        }
      },
      onCancel: () => jobNotifier.removeListener(onChange),
    );
    return controller.stream;
  }

  /// When set, the fake watch emits this as a STREAM error on listen.
  Object? errorToEmit;
}
