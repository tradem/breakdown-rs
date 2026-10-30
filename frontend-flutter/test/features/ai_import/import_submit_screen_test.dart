// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)
// Co-authored-by: deepseek-v4-flash (neuralwatt)
// Co-authored-by: space-bunny-free (opencode-go)
// Co-authored-by: glm-5.3-flash (opencode-go)

// Tier-2 widget tests for the AI-import submission screen
// (`flutter-ai-import-workflow` tasks 3.1 + 3.4): the kind picker, the
// paste field, the missing-document guard, the 202 → job-status
// navigation and the 200-duplicate navigation with the callout. The
// file-picker path is exercised on-device (integration smoke) — the
// paste path is fully covered here.

import 'dart:convert';
import 'dart:typed_data';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:dio/dio.dart' show CancelToken;
import 'package:built_collection/built_collection.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:fpdart/fpdart.dart';

import 'package:frontend_flutter/app_config.dart';
import 'package:frontend_flutter/auth/active_block.dart';
import 'package:frontend_flutter/auth/auth_providers.dart';
import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/data/ai_import_providers.dart';
import 'package:frontend_flutter/data/ai_import_repository.dart';
import 'package:frontend_flutter/data/cache/ai_import_jobs_cache_dao.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/clock.dart';
import 'package:frontend_flutter/domain/reconciliation/reconciliation_scheduler.dart';
import 'package:frontend_flutter/features/ai_import/import_jobs/import_submit_controller.dart';
import 'package:frontend_flutter/features/ai_import/import_jobs/import_target.dart';
import 'package:frontend_flutter/features/blocks/blocks_controller.dart';
import 'package:frontend_flutter/features/ai_import/import_jobs/import_submit_screen.dart';
import 'package:frontend_flutter/features/ai_import/import_jobs/job_status_screen.dart';
import 'package:frontend_flutter/l10n/generated/app_localizations.dart';

import '../../support/fake_secure_storage.dart';

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

AiImportJob _job(String id, JobStatus status) => AiImportJob(
  (b) => b
    ..id = id
    ..userId = 'dev-user'
    ..status = status
    ..documentKind = DocumentKind.schedule
    ..sourceFormat = SourceFormat.csv
    ..dedupKey = 'dedup'
    ..documentDigest = 'digest'
    ..sourceHandle = 'handle'
    ..retries = 0
    ..maxRetries = 3
    ..createdAt = DateTime.utc(2026, 1, 1)
    ..updatedAt = DateTime.utc(2026, 1, 1),
);

class FakePipelineRepository extends AiImportRepository {
  FakePipelineRepository(super.api, super.cache);

  Result<AiUploadAck>? uploadResult;
  Result<AiImportJob>? jobResult;
  int uploadCalls = 0;
  Object? lastUploadBody;
  AiScheduleSource? lastUploadSource;

  /// The document name the last upload carried (issue #763).
  String? lastFileName;

  /// The season the last upload DECLARED as its target (issue #771) —
  /// `null` when the dispatch sent no `X-Declared-Season` header.
  String? lastDeclaredSeasonId;

  @override
  Future<Result<AiUploadAck>> uploadSchedule({
    required Object body,
    required AiScheduleSource source,
    String? fileName,
    String? declaredSeasonId,
    void Function(int, int)? onSendProgress,
  }) async {
    uploadCalls++;
    lastUploadBody = body;
    lastUploadSource = source;
    lastFileName = fileName;
    lastDeclaredSeasonId = declaredSeasonId;
    return uploadResult ?? Right(AiUploadAck(jobId: 'job-1', duplicate: false));
  }

  @override
  Future<Result<AiImportJob>> getJobAndCache(
    String id, {
    Clock clock = Clock.system,
  }) async {
    final job =
        jobResult?.getRight().toNullable() ?? _job(id, JobStatus.pending);
    await cache.upsertAll([job], clock.now());
    return Right(job);
  }

  @override
  Stream<Result<AiImportJob>> watch(
    String jobId, {
    ReconciliationScheduler scheduler = const ExponentialBackoffScheduler(),
    int maxAttempts = 30,
    Duration? receiveTimeout,
    CancelToken? cancelToken,
  }) async* {
    yield Right(_job(jobId, JobStatus.succeeded));
  }
}

class FakeActiveBlock extends ActiveBlock {
  @override
  ActiveScope? build() =>
      ActiveScope(seasonId: 'season-1', blockId: 'block-1', blockNumber: 3);
}

/// One season block as the list route would return it (issue #771 target
/// resolution).
BlockView blockView(
  String id, {
  required String seasonId,
  required int number,
}) => BlockView(
  (b) => b
    ..id = id
    ..seasonId = seasonId
    ..projectId = 'project-1'
    ..number = number
    ..version = 1
    ..updatedAt = DateTime.utc(2026, 1, 1),
);

/// The configured naming fixture the disclosure card's naming line
/// renders (issue #608).
AiConfigView namingConfig() => AiConfigView(
  (b) => b
    ..id = 'config-1'
    ..userId = 'dev-user'
    ..assistantModel = 'assistant-model-1'
    ..provider = LlmProvider.openai
    ..vaultKeyId = 'vk-1'
    ..prompts.replace(BuiltMap<String, String>())
    ..promptKinds.replace(BuiltList<DocumentKind>())
    ..revoked = false
    ..version = 1,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStoragePlatform.instance = FakeSecureStoragePlatform();
  });

  late CacheDatabase db;
  late FakePipelineRepository repo;
  late ProviderContainer container;

  Future<void> setupContainer({
    Result<AiUploadAck>? uploadResult,
    Result<AiImportJob>? jobResult,
    bool naming = true,
    // Issue #771 knobs: `realActiveBlock` leaves the sticky scope UNset (the
    // resolution then has to resolve/adopt one); `blocks` scripts the season's
    // block list (one → auto-adopt, several → picker, empty → blocked).
    bool realActiveBlock = false,
    String? seasonId,
    String? seasonNumber = '2',
    Result<List<BlockView>>? blocks,
  }) async {
    db = CacheDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    repo = FakePipelineRepository(BreakdownApi(), AiImportJobsCacheDao(db))
      ..uploadResult = uploadResult
      ..jobResult = jobResult;
    container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(devAuthConfig),
        aiImportRepositoryProvider.overrideWithValue(repo),
        reconciliationSchedulerProvider.overrideWith(
          (ref) => const _ImmediateScheduler(),
        ),
        if (!realActiveBlock)
          activeBlockProvider.overrideWith(FakeActiveBlock.new),
        if (seasonId != null && seasonNumber != null)
          aiImportSeasonNumberProvider(seasonId)
              .overrideWith((ref) async => seasonNumber),
        if (seasonId != null && blocks != null)
          blocksListFetchProvider(seasonId).overrideWith((ref) async => blocks),
        // The disclosure card renders the configured naming line (issue
        // #608) — a deterministic override keeps the test off the real
        // discovery path; `naming: false` exercises the degraded state.
        configuredAiNamingProvider.overrideWith(
          (ref) => Future.value(naming ? namingConfig() : null),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authSessionControllerProvider.notifier).signIn();
  }

  Future<void> pumpScreen(
    WidgetTester tester, {
    String? seasonId,
    ThemeMode mode = ThemeMode.light,
    Locale? locale,
    TargetPlatform? platform,
  }) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // Restore, don't clear: the golden helpers set the platform override
    // around the capture and own its lifetime (same pattern as the job
    // status screen's goldens).
    final previousOverride = debugDefaultTargetPlatformOverride;
    if (platform != null) debugDefaultTargetPlatformOverride = platform;
    try {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData.light(),
            darkTheme: ThemeData.dark(),
            themeMode: mode,
            // Goldens render the GERMAN template locale (AGENTS.md §9); the
            // default (no locale) keeps the English copy the existing
            // assertions use.
            locale: locale,
            supportedLocales: const [Locale('de'), Locale('en')],
            localizationsDelegates: locale == null
                ? null
                : AppLocalizations.localizationsDelegates,
            // Deterministic host tests (AGENTS.md §6): the Karl Kleiderbügel
            // figure is time-driven, so freeze animations (spec
            // `flutter-easter-eggs`).
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            ),
            home: AiImportSubmitScreen(seasonId: seasonId),
          ),
        ),
      );
      await tester.pumpAndSettle();
    } finally {
      debugDefaultTargetPlatformOverride = previousOverride;
    }
  }

  testWidgets('Script is the default and ordered first; schedule is '
      'file-only with no paste affordance (issue #508)', (tester) async {
    await setupContainer();
    await pumpScreen(tester);

    final picker = tester.widget<SegmentedButton<AiImportKind>>(
      find.byKey(const Key('ai-import-kind-picker')),
    );
    expect(picker.selected, {AiImportKind.script});
    expect(picker.segments.map((segment) => segment.value), [
      AiImportKind.script,
      AiImportKind.schedule,
    ]);
    expect(find.text('Scripts: pick a PDF file.'), findsOneWidget);
    expect(find.byKey(const Key('ai-import-paste-field')), findsNothing);

    await tester.tap(find.text('Schedule'));
    await tester.pumpAndSettle();
    expect(find.text('Schedules: pick a CSV or PDF file.'), findsOneWidget);
    expect(find.byKey(const Key('ai-import-paste-field')), findsNothing);
    expect(find.byKey(const Key('ai-import-pick-file')), findsOneWidget);
  });

  testWidgets('the AI disclosure card precedes the submit action and stays '
      'persistent regardless of the kind pick (issue #538)', (tester) async {
    await setupContainer();
    await pumpScreen(tester);

    final disclosure = find.byKey(const Key('ai-import-disclosure'));
    expect(disclosure, findsOneWidget);
    final disclosureY = tester.getTopLeft(disclosure).dy;
    final submitY = tester
        .getTopLeft(find.byKey(const Key('ai-import-submit')))
        .dy;
    expect(
      disclosureY < submitY,
      isTrue,
      reason:
          'the disclosure is scroll-ordered ABOVE the submit button — '
          'visible before any submission',
    );

    // Persistent: also present after the kind switch (never kind-scoped
    // skippable content).
    await tester.tap(find.text('Schedule'));
    await tester.pumpAndSettle();
    expect(disclosure, findsOneWidget);
  });

  testWidgets('the disclosure names the configured provider/model — '
      'EU AI Act transparency at the point of interaction (issue #608)', (
    tester,
  ) async {
    await setupContainer();
    await pumpScreen(tester);

    final line = find.byKey(const Key('ai-import-naming'));
    expect(line, findsOneWidget);
    final copy = tester
        .widget<Text>(find.descendant(of: line, matching: find.byType(Text)))
        .data;
    expect(
      copy,
      contains('provider'),
      reason: 'the configured naming line names provider AND model',
    );
    expect(copy, contains('model'));
    expect(copy, contains('assistant-model-1'));
    // The naming line sits INSIDE the disclosure card, below its body —
    // part of the same point-of-interaction disclosure.
    expect(
      find.descendant(
        of: find.byKey(const Key('ai-import-disclosure')),
        matching: line,
      ),
      findsOneWidget,
    );
  });

  testWidgets('the naming line degrades honestly when AI is unconfigured '
      '(never an invented name)', (tester) async {
    await setupContainer(naming: false);
    await pumpScreen(tester);

    final line = find.byKey(const Key('ai-import-naming'));
    expect(line, findsOneWidget);
    expect(
      tester
          .widget<Text>(find.descendant(of: line, matching: find.byType(Text)))
          .data,
      'No AI configuration is set up for this account.',
    );
  });

  group('import target — visible and resolved before dispatch (issue #771)', () {
    testWidgets('the target line names the resolved season and block above '
        'the submit action', (tester) async {
      await setupContainer(seasonId: 'season-1');
      await pumpScreen(tester);

      expect(find.byKey(const Key('ai-import-target')), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('ai-import-target-line')))
            .data,
        'Season 2 · Block 3',
      );
      // The target sits ABOVE the submit affordance (never below the fold).
      expect(
        tester.getTopLeft(find.byKey(const Key('ai-import-target'))).dy,
        lessThan(
          tester.getTopLeft(find.byKey(const Key('ai-import-submit'))).dy,
        ),
      );
      // An ambiguous cache-only season number renders the honest narrative
      // rather than a guessed number.
      await tester.pump();
    });

    testWidgets('a wizard entry with ONE block in the season adopts that '
        'block — no manual scope switching, and the dispatch names it', (
      tester,
    ) async {
      await setupContainer(
        realActiveBlock: true,
        seasonId: 'season-b',
        seasonNumber: '2',
        blocks: Right([blockView('block-b', seasonId: 'season-b', number: 7)]),
        jobResult: Right(_job('job-1', JobStatus.pending)),
      );
      await pumpScreen(tester, seasonId: 'season-b');

      // The single block was adopted into the sticky scope (the header and the
      // visible line can therefore never disagree).
      expect(container.read(activeBlockProvider)?.blockId, 'block-b');
      expect(
        tester
            .widget<Text>(find.byKey(const Key('ai-import-target-line')))
            .data,
        'Season 2 · Block 7',
      );

      container
          .read(aiImportSubmitControllerProvider.notifier)
          .selectKind(AiImportKind.schedule);
      container
          .read(pendingDocumentProvider.notifier)
          .set(AiImportDocument.csv('day,scene\n1,12'));
      await tester.ensureVisible(find.byKey(const Key('ai-import-submit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ai-import-submit')));
      await tester.pumpAndSettle();

      expect(repo.uploadCalls, 1);
      expect(
        repo.lastDeclaredSeasonId,
        'season-b',
        reason:
            'the dispatched upload must declare the season the screen '
            'showed, so the server can refuse a contradictory block',
      );
    });

    testWidgets('several blocks in the target season require an explicit '
        'pick — the submit affordance stays disabled until then', (
      tester,
    ) async {
      await setupContainer(
        realActiveBlock: true,
        seasonId: 'season-b',
        seasonNumber: '2',
        blocks: Right([
          blockView('block-b1', seasonId: 'season-b', number: 7),
          blockView('block-b2', seasonId: 'season-b', number: 8),
        ]),
      );
      await pumpScreen(tester, seasonId: 'season-b');

      expect(find.byKey(const Key('ai-import-target-picker')), findsOneWidget);
      expect(find.byKey(const Key('ai-import-target-line')), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('ai-import-submit')))
            .onPressed,
        isNull,
        reason: 'no target → no upload',
      );

      await tester.tap(find.byKey(const Key('ai-import-target-pick-block-b2')));
      await tester.pumpAndSettle();

      expect(container.read(activeBlockProvider)?.blockId, 'block-b2');
      expect(
        tester
            .widget<Text>(find.byKey(const Key('ai-import-target-line')))
            .data,
        'Season 2 · Block 8',
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('ai-import-submit')))
            .onPressed,
        isNotNull,
      );
      await tester.pump();
    });

    testWidgets('a season without any block blocks the upload with actionable '
        'copy', (tester) async {
      await setupContainer(
        realActiveBlock: true,
        seasonId: 'season-b',
        seasonNumber: '2',
        blocks: const Right([]),
      );
      await pumpScreen(tester, seasonId: 'season-b');

      expect(
        find.byKey(const Key('ai-import-target-no-blocks')),
        findsOneWidget,
      );
      expect(find.textContaining('Create a block first'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('ai-import-submit')))
            .onPressed,
        isNull,
      );
      await tester.pump();
    });

    testWidgets('no season context at all renders the select-a-season state '
        'and never dispatches', (tester) async {
      await setupContainer(realActiveBlock: true);
      await pumpScreen(tester);

      expect(find.byKey(const Key('ai-import-target-missing')), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('ai-import-submit')))
            .onPressed,
        isNull,
      );
      expect(repo.uploadCalls, 0);
      await tester.pump();
    });

    // Goldens (AGENTS.md §6): the target card is a non-trivial widget that
    // renders domain state (a resolved block scope, a candidate list, or the
    // absence of one), so a layout regression that keeps the text and the
    // vertical position would otherwise pass. German template locale
    // (AGENTS.md §9).
    group('import target goldens: {resolved, picker, blocked} × android', () {
      Future<void> pumpGolden(
        WidgetTester tester, {
        required String golden,
      }) async {
        await pumpScreen(
          tester,
          seasonId: 'season-b',
          mode: ThemeMode.dark,
          locale: const Locale('de'),
          platform: TargetPlatform.android,
        );
        await expectLater(
          find.byType(AiImportSubmitScreen),
          matchesGoldenFile('goldens/$golden'),
        );
      }

      testWidgets('golden resolved target', (tester) async {
        await setupContainer(
          realActiveBlock: true,
          seasonId: 'season-b',
          seasonNumber: '2',
          blocks: Right([
            blockView('block-b', seasonId: 'season-b', number: 7),
          ]),
        );
        await pumpGolden(tester, golden: 'ai_import_target_resolved_dark.png');
      });

      testWidgets('golden multi-block picker', (tester) async {
        await setupContainer(
          realActiveBlock: true,
          seasonId: 'season-b',
          seasonNumber: '2',
          blocks: Right([
            blockView('block-b1', seasonId: 'season-b', number: 7),
            blockView('block-b2', seasonId: 'season-b', number: 8),
          ]),
        );
        await pumpGolden(tester, golden: 'ai_import_target_picker_dark.png');
      });

      testWidgets('golden blocked (no block in the season)', (tester) async {
        await setupContainer(
          realActiveBlock: true,
          seasonId: 'season-b',
          seasonNumber: '2',
          blocks: const Right([]),
        );
        // The submit affordance must be visibly disabled, not merely dimmed:
        // the golden captures the real `onPressed: null` rendering.
        await pumpGolden(tester, golden: 'ai_import_target_blocked_dark.png');
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('ai-import-submit')))
              .onPressed,
          isNull,
        );
      });
    });
  });

  testWidgets('submit without a document surfaces the guard snackbar — '
      'zero upload calls', (tester) async {
    await setupContainer();
    await pumpScreen(tester);
    await tester.ensureVisible(find.byKey(const Key('ai-import-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ai-import-submit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ai-import-document-missing')), findsOneWidget);
    expect(repo.uploadCalls, 0);
    await tester.pump();
  });

  testWidgets('a picked schedule CSV keeps the upload wire path: UTF-8 body '
      '+ csv source, then a 202 pushes the job-status screen', (tester) async {
    await setupContainer(jobResult: Right(_job('job-1', JobStatus.pending)));
    await pumpScreen(tester);
    container
        .read(aiImportSubmitControllerProvider.notifier)
        .selectKind(AiImportKind.schedule);
    container
        .read(pendingDocumentProvider.notifier)
        .set(
          documentFromBytes(
            AiImportKind.schedule,
            Uint8List.fromList(utf8.encode('day,scene\n1,12')),
            'csv',
          ),
        );
    await tester.ensureVisible(find.byKey(const Key('ai-import-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ai-import-submit')));
    await tester.pumpAndSettle();

    expect(repo.uploadCalls, 1);
    expect(repo.lastUploadBody, 'day,scene\n1,12');
    expect(repo.lastUploadSource, AiScheduleSource.csv);
    expect(find.byType(AiJobStatusScreen), findsOneWidget);
    expect(
      find.byKey(const Key('ai-job-duplicate-callout')),
      findsNothing,
      reason: 'a 202 is a fresh import — no duplicate callout',
    );
    await tester.pump();
  });

  testWidgets('a 200 duplicate navigates WITH the duplicate callout — '
      'nothing implies a second import was created', (tester) async {
    await setupContainer(
      uploadResult: Right(AiUploadAck(jobId: 'job-0', duplicate: true)),
      jobResult: Right(_job('job-0', JobStatus.pending)),
    );
    await pumpScreen(tester);
    container
        .read(aiImportSubmitControllerProvider.notifier)
        .selectKind(AiImportKind.schedule);
    container
        .read(pendingDocumentProvider.notifier)
        .set(AiImportDocument.csv('same bytes'));
    await tester.ensureVisible(find.byKey(const Key('ai-import-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ai-import-submit')));
    await tester.pumpAndSettle();

    expect(find.byType(AiJobStatusScreen), findsOneWidget);
    expect(find.byKey(const Key('ai-job-duplicate-callout')), findsOneWidget);
    await tester.pump();
  });

  testWidgets('an upload error surfaces the code-keyed snackbar and stays '
      'on the screen', (tester) async {
    await setupContainer(
      uploadResult: const Left(
        ProblemError(code: 'http.payload-too-large', status: 413),
      ),
    );
    await pumpScreen(tester);
    container
        .read(aiImportSubmitControllerProvider.notifier)
        .selectKind(AiImportKind.schedule);
    container
        .read(pendingDocumentProvider.notifier)
        .set(AiImportDocument.csv('big'));
    await tester.ensureVisible(find.byKey(const Key('ai-import-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ai-import-submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ai-import-error-snackbar')), findsOneWidget);
    expect(find.textContaining('too large'), findsOneWidget);
    expect(find.byType(AiJobStatusScreen), findsNothing);
    await tester.pump();
  });
}

class _ImmediateScheduler extends ReconciliationScheduler {
  const _ImmediateScheduler();

  @override
  Future<void> tick(int attempt) => Future<void>.value();
}
