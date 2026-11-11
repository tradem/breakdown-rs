// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)
// Co-authored-by: deepseek-v4-flash (neuralwatt)
// Co-authored-by: space-bunny-free (opencode-go)
// Co-authored-by: glm-5.3-flash (opencode-go)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

// Tier-2 widget tests for the AI-import submission screen
// (`flutter-ai-import-workflow` tasks 3.1 + 3.4): the kind picker, the
// paste field, the document precondition of the submit affordance (issue
// #831: disabled until a file is picked, and the in-dispatch guard kept as a
// backstop), the 202 → job-status
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
import 'package:frontend_flutter/features/shell/active_season_store.dart';
import 'package:frontend_flutter/features/ai_import/import_jobs/import_submit_screen.dart';
import 'package:frontend_flutter/features/ai_import/import_jobs/job_status_screen.dart';
import 'package:frontend_flutter/l10n/generated/app_localizations.dart';

import '../../support/fake_secure_storage.dart';
import '../seasons/setup/setup_wizard_test_fakes.dart' show FakeBlockRepository;

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

/// A block-list fetch failure as the transport layer reports it (review of
/// #828: the resolved target must state it instead of hiding the switch).
const _networkDown = ProblemError(code: 'transport.connectionError');

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

  /// Whether the last dispatch suppressed the ambient `X-Active-Block`
  /// (issue #829) — `true` for a block-less upload.
  bool lastSendActiveBlock = true;

  @override
  Future<Result<AiUploadAck>> uploadSchedule({
    required Object body,
    required AiScheduleSource source,
    String? fileName,
    String? declaredSeasonId,
    void Function(int, int)? onSendProgress,
    bool sendActiveBlock = true,
  }) async {
    uploadCalls++;
    lastUploadBody = body;
    lastUploadSource = source;
    lastFileName = fileName;
    lastDeclaredSeasonId = declaredSeasonId;
    lastSendActiveBlock = sendActiveBlock;
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

/// One season row as the cache/list route would carry it — the shared
/// create-block form pre-fills its ids from it (issue #828).
SeasonView seasonView(String id, {int number = 2}) => SeasonView(
  (b) => b
    ..id = id
    ..number = number
    ..projectId = 'project-1'
    ..title = 'Season'
    ..archived = false
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
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
  late FakeBlockRepository blockRepo;
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
    // Review (#828): a scripted SEQUENCE for the block-list fetch, so a failure
    // followed by a successful retry is expressible.
    Future<Result<List<BlockView>>> Function()? blocksFetch,
    // Issue #828 knobs: the create action needs the season ROW (the shared
    // create-block form takes a `SeasonView`) and a scriptable create ack.
    SeasonView? season,
    bool blockCreate = false,
    // The season the SHELL carries as its active season (the season chip's
    // pick) — the import target's fallback when no block scope is set. Only
    // overridden when given, so every existing case keeps the real (empty)
    // resolution.
    SeasonView? shellActiveSeason,
  }) async {
    db = CacheDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    repo = FakePipelineRepository(BreakdownApi(), AiImportJobsCacheDao(db))
      ..uploadResult = uploadResult
      ..jobResult = jobResult;
    blockRepo = FakeBlockRepository(db);
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
        if (seasonId != null && blocksFetch != null)
          blocksListFetchProvider(seasonId)
              .overrideWith((ref) => blocksFetch()),
        if (seasonId != null && blocks != null && blocksFetch == null)
          blocksListFetchProvider(seasonId).overrideWith((ref) async => blocks),
        // Issue #828: the season row the create action pre-fills its command
        // from. Overridden for EVERY season-scoped case (default `null`), so no
        // test reaches the network through the repository fallback.
        if (seasonId != null)
          aiImportSeasonViewProvider(seasonId)
              .overrideWith((ref) async => season),
        if (blockCreate) blockRepositoryProvider.overrideWithValue(blockRepo),
        if (shellActiveSeason != null)
          activeSeasonResolutionProvider.overrideWith(
            (ref) async => shellActiveSeason,
          ),
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
    testWidgets('a season picked in the SHELL is the import target — no block '
        'scope required, so the submit affordance can actually enable', (
      tester,
    ) async {
      // Regression: every non-wizard entry (the shell's Import action, the
      // production overview's AI-import row, the jobs screen's plus) pushes the
      // plain screen and relied on the ambient BLOCK scope alone. Picking a
      // season in the season chip sets no block, so the card claimed "no
      // season selected" for a season the chip plainly showed — and the submit
      // affordance could never be enabled, whatever file was picked.
      await setupContainer(
        realActiveBlock: true,
        seasonId: 'season-b',
        seasonNumber: '2',
        blocks: Right([blockView('block-b', seasonId: 'season-b', number: 7)]),
        shellActiveSeason: seasonView('season-b'),
        jobResult: Right(_job('job-1', JobStatus.pending)),
      );
      // The entry passes NO season of its own — the fallback is the seam under
      // test.
      await pumpScreen(tester);

      expect(find.byKey(const Key('ai-import-target-missing')), findsNothing);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('ai-import-target-line')))
            .data,
        'Season 2 · Block 7',
        reason: 'the season the chip shows is the season the card names',
      );
      // The resolution's single block was adopted, so the request carries the
      // block the line shows.
      expect(container.read(activeBlockProvider)?.blockId, 'block-b');
      // Issue #831: a resolved target is only half the predicate.
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('ai-import-submit')))
            .onPressed,
        isNull,
        reason: 'no document yet → still no dispatch',
      );

      container
          .read(aiImportSubmitControllerProvider.notifier)
          .selectKind(AiImportKind.schedule);
      container
          .read(pendingDocumentProvider.notifier)
          .set(AiImportDocument.csv('day,scene\n1,12'));
      await tester.ensureVisible(find.byKey(const Key('ai-import-submit')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('ai-import-submit')))
            .onPressed,
        isNotNull,
        reason: 'season + block + document → the dispatch is reachable',
      );

      await tester.tap(find.byKey(const Key('ai-import-submit')));
      await tester.pumpAndSettle();

      expect(repo.uploadCalls, 1);
      expect(
        repo.lastDeclaredSeasonId,
        'season-b',
        reason: 'the dispatch declares the season the card showed',
      );
    });

    test(
      'the ambient block scope outranks the shell\'s active season',
      () async {
        // The scope is what the request carries as `X-Active-Block`. A chip
        // season must never silently re-target a dispatch that still acts in
        // another season's block — that is the `ai_import.scope_mismatch` case.
        await setupContainer(
          seasonId: 'season-b',
          shellActiveSeason: seasonView('season-b'),
        );

        expect(
          container.read(aiImportSeasonContextProvider(null)),
          'season-1',
          reason: 'FakeActiveBlock carries season-1',
        );
      },
    );

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
      // Issue #828: the inline candidate list IS the switch in this arm, so the
      // card never renders a second switch affordance beside it — but the
      // create action is there (a season whose existing blocks are all wrong).
      expect(find.byKey(const Key('ai-import-target-switch')), findsNothing);
      expect(find.byKey(const Key('ai-import-target-create')), findsOneWidget);
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
      // Issue #831: a resolved target is not the whole predicate — the
      // affordance also needs a picked document.
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('ai-import-submit')))
            .onPressed,
        isNull,
        reason: 'no document yet → still no dispatch',
      );
      container
          .read(pendingDocumentProvider.notifier)
          .set(AiImportDocument.csv('day,scene\n1,12'));
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('ai-import-submit')))
            .onPressed,
        isNotNull,
      );
      await tester.pump();
    });

    testWidgets('a RESOLVED target offers "Block wechseln", lists the target '
        'season\'s blocks and re-targets the import without leaving the screen '
        '(issue #828)', (tester) async {
      await setupContainer(
        seasonId: 'season-1',
        blocks: Right([
          blockView('block-1', seasonId: 'season-1', number: 3),
          blockView('block-9', seasonId: 'season-1', number: 9),
        ]),
      );
      await pumpScreen(tester);

      // `ready`: the sticky scope already matched, so nothing used to offer a
      // switch at all — the target card was a read-only line.
      expect(
        tester
            .widget<Text>(find.byKey(const Key('ai-import-target-line')))
            .data,
        'Season 2 · Block 3',
      );
      expect(find.byKey(const Key('ai-import-target-switch')), findsOneWidget);
      expect(find.byKey(const Key('ai-import-target-create')), findsOneWidget);

      await tester.tap(find.byKey(const Key('ai-import-target-switch')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('ai-import-target-switch-sheet')),
        findsOneWidget,
        reason: 'the sheet lists the target season\'s blocks',
      );
      await tester.tap(
        find.byKey(const Key('ai-import-target-switch-block-9')),
      );
      await tester.pumpAndSettle();

      // The pick goes through the ONE seam (the active-block scope), so the
      // shown line and the header follow it — never a block id sent beside it.
      expect(container.read(activeBlockProvider)?.blockId, 'block-9');
      expect(container.read(activeBlockProvider)?.seasonId, 'season-1');
      expect(
        tester
            .widget<Text>(find.byKey(const Key('ai-import-target-line')))
            .data,
        'Season 2 · Block 9',
      );

      // Single source of truth: the switched target is what the dispatch
      // declares, and the mismatch guard therefore cannot trip.
      container
          .read(aiImportSubmitControllerProvider.notifier)
          .selectKind(AiImportKind.schedule);
      container
          .read(pendingDocumentProvider.notifier)
          .set(AiImportDocument.csv('day,scene\n1,12'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('ai-import-submit')));
      await tester.tap(find.byKey(const Key('ai-import-submit')));
      await tester.pumpAndSettle();

      expect(repo.uploadCalls, 1);
      expect(repo.lastDeclaredSeasonId, 'season-1');
      expect(
        container.read(activeBlockProvider)?.blockNumber,
        9,
        reason:
            'the scope carries the block the line names — X-Active-Block '
            'and the visible target cannot drift',
      );
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

    testWidgets('a season without blocks offers the BLOCK-LESS upload, and the '
        'dispatch declares its season while suppressing the ambient block '
        '(issue #829)', (tester) async {
      await setupContainer(
        realActiveBlock: true,
        seasonId: 'season-b',
        seasonNumber: '2',
        blocks: const Right([]),
      );
      await pumpScreen(tester, seasonId: 'season-b');
      repo.uploadResult = Right(AiUploadAck(jobId: 'job-1', duplicate: false));

      // The empty state is no longer a dead end: it explains that the block is
      // chosen after extraction and offers exactly that.
      expect(
        find.byKey(const Key('ai-import-target-blockless')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('ai-import-submit')))
            .onPressed,
        isNull,
        reason:
            'nothing is dispatched until the user either creates a block '
            'or explicitly chooses the block-less path',
      );

      // The kind switch CLEARS the block-less choice (`selectKind` resets it),
      // so it is selected first and the block-less decision after it.
      container
          .read(aiImportSubmitControllerProvider.notifier)
          .selectKind(AiImportKind.schedule);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('ai-import-target-blockless')));
      await tester.pumpAndSettle();

      // The card now states the deferred block, with a way back.
      expect(
        find.byKey(const Key('ai-import-target-blockless-undo')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('ai-import-target-line')))
            .data,
        contains('Block unknown'),
        reason: 'the deferred block is stated as unknown, never invented',
      );

      // Pick a document the same way the other dispatch tests do: the pending
      // document provider is what both kinds write.
      container
          .read(pendingDocumentProvider.notifier)
          .set(AiImportDocument.csv('day,scene\n1,12'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('ai-import-submit')));
      await tester.tap(find.byKey(const Key('ai-import-submit')));
      await tester.pumpAndSettle();

      expect(repo.uploadCalls, 1);
      expect(
        repo.lastSendActiveBlock,
        isFalse,
        reason:
            'a block-less upload must not carry the ambient X-Active-Block — '
            'the server would pin the job to a block the user never chose',
      );
      expect(
        repo.lastDeclaredSeasonId,
        'season-b',
        reason: 'the declared season IS the upload authorization scope',
      );
    });

    testWidgets('the block-less choice cannot enable a dispatch without a '
        'season (review of #857)', (tester) async {
      // The choice lives in a provider, so it can outlive the scope that made it
      // (sign-out, backend switch, dev data reset). A dispatch in that state
      // could only answer `ai_import.scope_missing`, so the button must not be
      // enabled by the flag alone.
      // `realActiveBlock: true` is what leaves the screen WITHOUT a season
      // context (which is the state this test is about).
      await setupContainer(realActiveBlock: true);
      await pumpScreen(tester);
      container
          .read(aiImportSubmitControllerProvider.notifier)
          .selectKind(AiImportKind.schedule);
      // Set AFTER the kind switch: `selectKind` clears the choice by design.
      container.read(blockLessImportProvider.notifier).set(true);
      container
          .read(pendingDocumentProvider.notifier)
          .set(AiImportDocument.csv('day,scene\n1,12'));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('ai-import-submit')))
            .onPressed,
        isNull,
        reason: 'a block-less dispatch still needs the season that scopes it',
      );
    });

    testWidgets('a stale block-less choice never drops the block the card '
        'showed (review finding)', (tester) async {
      // The choice lives in a session provider; coming back to a season that HAS
      // a block must not turn the dispatch block-less behind the user's back.
      await setupContainer(seasonId: 'season-1', seasonNumber: '2');
      await pumpScreen(tester, seasonId: 'season-1');
      repo.uploadResult = Right(AiUploadAck(jobId: 'job-1', duplicate: false));

      container
          .read(aiImportSubmitControllerProvider.notifier)
          .selectKind(AiImportKind.schedule);
      // A leftover from an earlier visit (selectKind clears it, so set it last).
      container.read(blockLessImportProvider.notifier).set(true);
      container
          .read(pendingDocumentProvider.notifier)
          .set(AiImportDocument.csv('day,scene\n1,12'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('ai-import-submit')));
      await tester.tap(find.byKey(const Key('ai-import-submit')));
      await tester.pumpAndSettle();

      expect(repo.uploadCalls, 1);
      expect(
        repo.lastSendActiveBlock,
        isTrue,
        reason: 'a resolved block wins over a stale block-less choice',
      );
      await tester.pump();
    });

    testWidgets('a season without blocks offers "Block anlegen", opens the '
        'SHARED create form and adopts the created block as the target '
        '(issue #828)', (tester) async {
      await setupContainer(
        realActiveBlock: true,
        seasonId: 'season-b',
        seasonNumber: '2',
        blocks: const Right([]),
        season: seasonView('season-b'),
        blockCreate: true,
      );
      await pumpScreen(tester, seasonId: 'season-b');

      expect(
        find.byKey(const Key('ai-import-target-no-blocks')),
        findsOneWidget,
      );
      // The reported dead end: the empty state printed plain text and left the
      // user to find the Blocks screen. It now carries the create action, and no
      // switch (there is nothing to list).
      expect(find.byKey(const Key('ai-import-target-switch')), findsNothing);
      expect(find.byKey(const Key('ai-import-target-create')), findsOneWidget);

      await tester.tap(find.byKey(const Key('ai-import-target-create')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('create-block-number')),
        findsOneWidget,
        reason: 'the shared create-block form, never a second form',
      );

      await tester.enterText(find.byKey(const Key('create-block-number')), '4');
      await tester.tap(find.byKey(const Key('create-block-submit')));
      await tester.pumpAndSettle();

      expect(blockRepo.createCalls, 1);
      // The command names the season the card shows (CQRS boundary: the ids
      // come from the read DTO acted on).
      final request = blockRepo.lastCreateRequests.single;
      expect(request.seasonId, 'season-b');
      expect(request.number, 4);

      // The acknowledged block becomes the target: the create route answers
      // with an id only, so the typed number rides back from the form instead of
      // being re-derived from a not-yet-reconciled projection.
      final target = container.read(activeBlockProvider);
      expect(target?.seasonId, 'season-b');
      expect(target?.blockId, 'nb1');
      expect(target?.blockNumber, 4);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('ai-import-target-line')))
            .data,
        'Season 2 · Block 4',
      );
      await tester.pump();
    });

    testWidgets('an unreadable season row reports it instead of opening a form '
        'it cannot fill (issue #828)', (tester) async {
      await setupContainer(
        realActiveBlock: true,
        seasonId: 'season-b',
        blocks: const Right([]),
      );
      await pumpScreen(tester, seasonId: 'season-b');

      await tester.tap(find.byKey(const Key('ai-import-target-create')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('ai-import-target-season-unavailable')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('create-block-number')),
        findsNothing,
        reason: 'no form with a guessed id',
      );
      await tester.pump();
    });

    testWidgets('a failed block-list fetch surfaces on a RESOLVED target with '
        'a retry that brings the switch back (review of #828)', (tester) async {
      // The sticky scope matches the season, so the resolution is `ready` even
      // though the list fetch fails: without an explicit narrative the switch
      // action would just disappear.
      var calls = 0;
      await setupContainer(
        seasonId: 'season-1',
        blocksFetch: () async {
          calls++;
          if (calls == 1) return const Left(_networkDown);
          return Right([
            blockView('block-1', seasonId: 'season-1', number: 3),
            blockView('block-9', seasonId: 'season-1', number: 9),
          ]);
        },
      );
      await pumpScreen(tester);

      // The target is still resolved and named …
      expect(
        tester
            .widget<Text>(find.byKey(const Key('ai-import-target-line')))
            .data,
        'Season 2 · Block 3',
      );
      // … the switch is honestly unavailable …
      expect(find.byKey(const Key('ai-import-target-switch')), findsNothing);
      // … and the failure is stated with a retry instead of vanishing.
      expect(
        find.byKey(const Key('ai-import-target-list-error')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('ai-import-target-create')), findsOneWidget);

      await tester.tap(find.byKey(const Key('ai-import-target-list-retry')));
      await tester.pumpAndSettle();

      expect(calls, 2, reason: 'the retry re-runs the same season\'s fetch');
      expect(
        find.byKey(const Key('ai-import-target-list-error')),
        findsNothing,
      );
      expect(find.byKey(const Key('ai-import-target-switch')), findsOneWidget);

      // The recovered list is usable without leaving the screen.
      await tester.tap(find.byKey(const Key('ai-import-target-switch')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('ai-import-target-switch-block-9')),
      );
      await tester.pumpAndSettle();
      expect(container.read(activeBlockProvider)?.blockId, 'block-9');
      expect(
        tester
            .widget<Text>(find.byKey(const Key('ai-import-target-line')))
            .data,
        'Season 2 · Block 9',
      );
    });

    testWidgets('a newer block selection taken while the create form is open '
        'is not clobbered by the created block (review of #828)', (
      tester,
    ) async {
      await setupContainer(
        realActiveBlock: true,
        seasonId: 'season-b',
        blocks: const Right([]),
        season: seasonView('season-b'),
        blockCreate: true,
      );
      await pumpScreen(tester, seasonId: 'season-b');

      await tester.tap(find.byKey(const Key('ai-import-target-create')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('create-block-number')), findsOneWidget);

      // The scope can change while this future is in flight (a restore, or the
      // shell's block pill). The newer explicit choice must win.
      container
          .read(activeBlockProvider.notifier)
          .set(seasonId: 'season-b', blockId: 'block-newer', blockNumber: 8);
      await tester.pump();

      await tester.enterText(find.byKey(const Key('create-block-number')), '4');
      await tester.tap(find.byKey(const Key('create-block-submit')));
      await tester.pumpAndSettle();

      expect(blockRepo.createCalls, 1, reason: 'the block WAS created');
      expect(
        container.read(activeBlockProvider)?.blockId,
        'block-newer',
        reason: 'the created block must not overwrite a newer selection',
      );
      expect(container.read(activeBlockProvider)?.blockNumber, 8);
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

  testWidgets('the submit affordance stays disabled until a document is '
      'picked — zero upload calls, and the pick row explains why (issue '
      '#831)', (tester) async {
    await setupContainer();
    await pumpScreen(tester);

    // The picked file lives in `pendingDocumentProvider`; nothing was picked
    // yet, so a dispatch must be impossible (it used to be ONE tap away, and
    // the tap only produced an error snackbar).
    expect(container.read(pendingDocumentProvider), isNull);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('ai-import-submit')))
          .onPressed,
      isNull,
      reason: 'no document → no dispatch',
    );
    // The disabled state is explained: the pick row states that no file is
    // chosen.
    expect(find.text('No file picked'), findsOneWidget);
    expect(repo.uploadCalls, 0);

    // Picking a document enables the dispatch …
    container
        .read(pendingDocumentProvider.notifier)
        .set(AiImportDocument.csv('day,scene\n1,12'));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('ai-import-submit')))
          .onPressed,
      isNotNull,
    );

    // … and the schedule flow gates the same way (one button, one predicate
    // for both kinds).
    container.read(pendingDocumentProvider.notifier).set(null);
    await tester.tap(find.text('Schedule'));
    await tester.pumpAndSettle();
    expect(find.text('Schedules: pick a CSV or PDF file.'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('ai-import-submit')))
          .onPressed,
      isNull,
    );
    await tester.pump();
  });

  testWidgets('the file row drops the picked name when the pending document is '
      'cleared — a kind switch or a finished submit (issue #831 review)', (
    tester,
  ) async {
    await setupContainer();
    await pumpScreen(tester);

    Text pickedName() =>
        tester.widget<Text>(find.byKey(const Key('ai-import-picked-name')));

    expect(pickedName().data, 'No file picked');

    container
        .read(pendingDocumentProvider.notifier)
        .set(AiImportDocument.csv('day,scene\n1,12', fileName: 'plan.csv'));
    await tester.pump();
    expect(pickedName().data, 'plan.csv');

    // A successful submit clears the provider (and a kind switch clears it too).
    // The row derives its name from that state, so it returns to its localized
    // "no file picked" line instead of naming a file the dispatch no longer
    // carries.
    container.read(pendingDocumentProvider.notifier).set(null);
    await tester.pump();
    expect(pickedName().data, 'No file picked');
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
