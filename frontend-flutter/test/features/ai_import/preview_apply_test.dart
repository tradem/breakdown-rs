// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

// Tier-1 + Tier-2 tests for the preview + apply features
// (`flutter-ai-import-workflow` tasks 4.3/4.4): the typed-preview
// rendering (script/schedule/merged + unknown-`kind` degraded + empty),
// the mapping-request builder (Create / Update-from-picked-DTO / skip;
// verbatim `draft_ref`s), the apply round-trip against a fake (incl. the
// ambiguous-timeout reconciliation), the episode context for fresh-job
// AND remembered-job entry (incl. the missing-context → picker-required
// path), 409/403 branches, and goldens.

import 'package:breakdown_api/breakdown_api.dart';
import 'package:drift/native.dart';
import 'package:frontend_flutter/data/cache/clock.dart';
import 'package:built_collection/built_collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:one_of/one_of.dart';

import 'package:frontend_flutter/app_config.dart';
import 'package:frontend_flutter/auth/auth_providers.dart';
import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/data/ai_import_providers.dart';
import 'package:frontend_flutter/data/ai_import_repository.dart';
import 'package:frontend_flutter/data/cache/ai_import_jobs_cache_dao.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/domain/reconciliation/reconciliation_scheduler.dart';
import 'package:frontend_flutter/features/ai_import/import_jobs/apply_controller.dart';
import 'package:frontend_flutter/features/ai_import/import_jobs/job_status_controller.dart';
import 'package:frontend_flutter/features/ai_import/import_jobs/preview_screen.dart';
import 'package:frontend_flutter/features/scenes/scenes_controller.dart';

// --- Fixtures ---------------------------------------------------------------

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
  defaultSeriesId: 'series-1',
);

DraftScene _draft(String ref, {int? number}) => DraftScene(
  (b) => b
    ..draftRef = ref
    ..sceneNumber = number
    ..summary = 'Scene $ref'
    ..characters.replace(const <String>['ch-1']),
);

SceneView _scene(String id, {int version = 1, int? number}) => SceneView(
  (b) => b
    ..id = id
    ..episodeId = 'ep-1'
    ..assignedCharacters.replace(const <String>[])
    ..isScheduleSet = false
    ..sceneNumber = number
    ..shootingDayIds.replace(const <String>[])
    ..summary = 'Existing $id'
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = version,
);

ShootingScheduleRow _scheduleRow(String ref) => ShootingScheduleRow(
  (b) => b
    ..rowRef = ref
    ..sceneNumber = 12
    ..order = 1,
);

AiPreviewPayload _scriptPayload() => AiPreviewPayload(
  (b) => b
    ..oneOf =
        OneOf.fromValue3<
          AiPreviewPayloadOneOf,
          AiPreviewPayloadOneOf1,
          AiPreviewPayloadOneOf2
        >(
          value: AiPreviewPayloadOneOf(
            (b) => b
              ..kind = AiPreviewPayloadOneOfKindEnum.script
              ..data.replace(
                ScriptContext(
                  (b) => b
                    ..title = 'Pilot'
                    ..scenes.replace([_draft('draft-1'), _draft('draft-2')])
                    ..uncertainties.replace([
                      Uncertainty(
                        (u) => u
                          ..field = 'location'
                          ..note = 'Unknown stage'
                          ..sceneIndex = 1,
                      ),
                    ]),
                ),
              ),
          ),
        ),
);

AiPreviewPayload _mergedPayload() => AiPreviewPayload(
  (b) => b
    ..oneOf =
        OneOf.fromValue3<
          AiPreviewPayloadOneOf,
          AiPreviewPayloadOneOf1,
          AiPreviewPayloadOneOf2
        >(
          value: AiPreviewPayloadOneOf2(
            (b) => b
              ..kind = AiPreviewPayloadOneOf2KindEnum.merged
              ..data.replace(
                MergedPreview(
                  (b) => b
                    ..scenes.replace([
                      MergedScene(
                        (m) => m
                          ..scene.replace(_scene('sc-1', number: 12))
                          ..scheduleRows.replace([_scheduleRow('row-1')]),
                      ),
                    ])
                    ..unmatchedScheduleRows.replace([_scheduleRow('row-x')])
                    ..unmatchedScriptScenes.replace(
                      BuiltList(const <SceneView>[]),
                    ),
                ),
              ),
          ),
        ),
);

AiPreviewPayload _preMergePayload() => AiPreviewPayload(
  (b) => b
    ..oneOf =
        OneOf.fromValue3<
          AiPreviewPayloadOneOf,
          AiPreviewPayloadOneOf1,
          AiPreviewPayloadOneOf2
        >(
          value: AiPreviewPayloadOneOf1(
            (b) => b
              ..kind = AiPreviewPayloadOneOf1KindEnum.schedule
              ..data.replace(
                ShootingSchedule(
                  (b) => b..rows.replace([_scheduleRow('row-1')]),
                ),
              ),
          ),
        ),
);

AiImportPreviewResponse _previewResponse(AiPreviewPayload payload) =>
    AiImportPreviewResponse(
      (b) => b
        ..jobId = 'job-1'
        ..documentKind = DocumentKind.schedule
        ..status = JobStatus.succeeded
        ..preview.replace(payload),
    );

/// Repository fake with scripted, QUEUED apply outcomes (the
/// reconciliation round-trip driver).
class FakeAiImportRepository extends AiImportRepository {
  FakeAiImportRepository(super.api, super.cache);

  final List<Result<ApplyAiImportResponse>> applyQueue = [];
  final List<ApplyAiImportRequest> applyRequests = [];
  Result<AiImportJob>? jobResult;

  ApplyAiImportRequest? lastRequest;

  @override
  Future<Result<ApplyAiImportResponse>> apply(
    String jobId,
    ApplyAiImportRequest request,
  ) async {
    applyRequests.add(request);
    lastRequest = request;
    return applyQueue.removeAt(0);
  }

  @override
  Future<Result<AiImportJob>> getJobAndCache(
    String id, {
    Clock clock = Clock.system,
  }) async {
    final job = jobResult;
    if (job != null) {
      final view = job.getRight().toNullable();
      if (view != null) {
        await cache.upsertAll([view], clock.now());
        return Right(view);
      }
    }
    return Left(const ProblemError(code: 'ai_import.not_found'));
  }
}

AiImportJob _succeededJob(String id) => AiImportJob(
  (b) => b
    ..id = id
    ..userId = 'dev-user'
    ..status = JobStatus.succeeded
    ..documentKind = DocumentKind.schedule
    ..sourceFormat = SourceFormat.csv
    ..dedupKey = 'dedup-$id'
    ..documentDigest = 'digest-$id'
    ..sourceHandle = 'handle-$id'
    ..retries = 0
    ..maxRetries = 3
    ..createdAt = DateTime.utc(2026, 1, 1)
    ..updatedAt = DateTime.utc(2026, 1, 1),
);

ApplyAiImportResponse _outcome({
  int appliedCount = 2,
  int createdDays = 1,
  int plannedSceneShoots = 3,
}) => ApplyAiImportResponse(
  (b) => b
    ..appliedCount = appliedCount
    ..createdDays = createdDays
    ..plannedSceneShoots = plannedSceneShoots,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AiApplyState — mapping-request builder (task 4.3)', () {
    test('all-Create is accept_as_is with edit_distance 0', () {
      final state = AiApplyState(
        rows: const [
          PreviewRow(draftRef: 'd1', label: 'A'),
          PreviewRow(draftRef: 'd2', label: 'B'),
        ],
      );
      expect(state.acceptAsIs, isTrue);
      expect(state.editDistance, 0);
      final mappings = state.buildMappings();
      expect(mappings, hasLength(2));
      // The draft_ref is VERBATIM.
      expect(mappings.map((m) => m.draftRef), ['d1', 'd2']);
      // Create serializes as the bare "Create" string.
      // Create serializes as the bare "Create" string variant.
      expect(mappings.first.decision.oneOf.value, 'Create');
      expect(mappings.first.draftRef, 'd1');
    });

    test('Update carries the picked aggregate id + version; skip is '
        'EXCLUDED from the mappings', () {
      final state = AiApplyState(
        rows: [
          const PreviewRow(draftRef: 'd1', label: 'A'),
          const PreviewRow(
            draftRef: 'd2',
            label: 'B',
          ).withDecision(const UpdateDecision(aggregateId: 'sc-9', version: 4)),
          const PreviewRow(
            draftRef: 'd3',
            label: 'C',
          ).withDecision(const SkipDecision()),
        ],
      );
      expect(state.acceptAsIs, isFalse);
      expect(state.editDistance, 2, reason: 'update + skip are user edits');
      final mappings = state.buildMappings();
      expect(mappings, hasLength(2), reason: 'the skipped row is excluded');
      // The Update variant carries the externally-tagged decision with
      // the picked aggregate id + version.
      final updateVariant =
          mappings.last.decision.oneOf.value as ApplyMappingDecisionOneOf;
      expect(updateVariant.decisionUpdate.aggregateId, 'sc-9');
      expect(updateVariant.decisionUpdate.version, 4);
    });
  });

  group('Apply round-trip against a fake (task 4.3)', () {
    late CacheDatabase db;
    late FakeAiImportRepository repo;
    late ProviderContainer container;

    setUp(() {
      db = CacheDatabase(NativeDatabase.memory());
      repo = FakeAiImportRepository(BreakdownApi(), AiImportJobsCacheDao(db));
      container = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(devAuthConfig),
          aiImportRepositoryProvider.overrideWithValue(repo),
          reconciliationSchedulerProvider.overrideWith(
            (ref) => const _ImmediateScheduler(),
          ),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(db.close);
    });

    Future<Result<ApplyAiImportResponse>> seedAndApply() async {
      final controller = container.read(
        aiApplyControllerProvider('job-1').notifier,
      );
      controller.seedRows(const [
        PreviewRow(draftRef: 'd1', label: 'A'),
        PreviewRow(draftRef: 'd2', label: 'B'),
      ], const AiJobContext(episodeId: 'ep-1', seriesId: 'series-1'));
      return controller.apply();
    }

    test('immediate 200 → the outcome summary', () async {
      repo.applyQueue.add(Right(_outcome()));
      final res = await seedAndApply();
      expect(res.getRight().toNullable()!.appliedCount, 2);
      // The request echoed the controller-built payload.
      expect(repo.lastRequest!.episodeId, 'ep-1');
    });

    test(
      'definitive 403 surfaces immediately (no retry, no re-read)',
      () async {
        repo.applyQueue.add(
          const Left(ProblemError(code: 'ai_import.forbidden', status: 403)),
        );
        final res = await seedAndApply();
        expect(res.getLeft().toNullable()!.code, 'ai_import.forbidden');
        expect(repo.applyRequests, hasLength(1));
      },
    );

    test('ambiguous timeout re-reads the job FIRST, then bounded-retries '
        '(server-side idempotency — never a blind re-dispatch)', () async {
      repo.applyQueue.addAll([
        const Left(ProblemError(code: 'transport.connectionTimeout')),
        Right(_outcome(appliedCount: 1)),
      ]);
      repo.jobResult = Right(_succeededJob('job-1'));
      final res = await seedAndApply();
      expect(res.getRight().toNullable()!.appliedCount, 1);
      // Request order: apply → job re-read → apply.
      expect(repo.applyRequests, hasLength(2));
    });
  });

  group('Episode context (task 4.3 — fresh-job AND remembered-job entry)', () {
    late CacheDatabase db;
    late AiImportJobsCacheDao dao;
    late ProviderContainer container;

    setUp(() async {
      db = CacheDatabase(NativeDatabase.memory());
      dao = AiImportJobsCacheDao(db);
      container = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(devAuthConfig),
          aiImportRepositoryProvider.overrideWithValue(
            FakeAiImportRepository(BreakdownApi(), dao),
          ),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(db.close);
      await container.read(authSessionControllerProvider.notifier).signIn();
    });

    test('remembered-job entry: the persisted context is read from the '
        'job record, never from the navigation stack', () async {
      await dao.upsertWithEpisodeContext(
        _succeededJob('job-1'),
        DateTime.utc(2026, 1, 1),
        episodeId: 'ep-1',
        seriesId: 'series-1',
      );
      final context = await container.read(
        aiJobContextProvider('job-1').future,
      );
      expect(context!.episodeId, 'ep-1');
      expect(context.seriesId, 'series-1');
    });

    test('missing context (a job id from an older build) → the picker is '
        'REQUIRED; apply never dispatches a guessed episode_id', () async {
      await dao.upsertAll([_succeededJob('job-2')], DateTime.utc(2026, 1, 1));
      final context = await container.read(
        aiJobContextProvider('job-2').future,
      );
      expect(context, isNull);
    });
  });

  group('Preview + apply widget tests (task 4.4)', () {
    late CacheDatabase db;
    late FakeAiImportRepository repo;
    late AiImportJobsCacheDao dao;
    late ValueNotifier<Result<AiImportPreviewResponse>> preview;
    late ValueNotifier<Result<List<SceneView>>> scenes;
    late ProviderContainer container;

    Future<void> setupContainer({
      Result<AiImportPreviewResponse>? previewValue,
      Result<List<SceneView>>? scenesValue,
      bool withPersistedContext = true,
      List<Result<ApplyAiImportResponse>>? applyQueue,
    }) async {
      db = CacheDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      dao = AiImportJobsCacheDao(db);
      repo = FakeAiImportRepository(BreakdownApi(), dao);
      if (applyQueue != null) repo.applyQueue.addAll(applyQueue);
      preview = ValueNotifier(
        previewValue ?? Right(_previewResponse(_scriptPayload())),
      );
      scenes = ValueNotifier(scenesValue ?? Right([_scene('sc-9')]));
      container = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(devAuthConfig),
          aiImportRepositoryProvider.overrideWithValue(repo),
          reconciliationSchedulerProvider.overrideWith(
            (ref) => const _ImmediateScheduler(),
          ),
          aiPreviewProvider.overrideWith((ref, jobId) async => preview.value),
          aiJobContextProvider.overrideWith((ref, jobId) async {
            if (!withPersistedContext) return null;
            return const AiJobContext(episodeId: 'ep-1', seriesId: 'series-1');
          }),
          scenesListFetchProvider.overrideWith((ref, episodeId) async {
            return scenes.value;
          }),
        ],
      );
      addTearDown(container.dispose);
      await container.read(authSessionControllerProvider.notifier).signIn();
      if (withPersistedContext) {
        await dao.upsertWithEpisodeContext(
          _succeededJob('job-1'),
          DateTime.utc(2026, 1, 1),
          episodeId: 'ep-1',
          seriesId: 'series-1',
        );
      }
    }

    Future<void> pumpPreview(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: AiPreviewScreen(jobId: 'job-1')),
        ),
      );
      // Seed is fire-and-forget; pump until the rows land.
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
    }

    testWidgets('script preview renders typed rows + uncertainties; the '
        'missing-context path requires the explicit episode pick (apply '
        'disabled)', (tester) async {
      await setupContainer(withPersistedContext: false);
      await pumpPreview(tester);

      expect(find.text('Script preview'), findsOneWidget);
      expect(find.byKey(const Key('ai-preview-row-draft-1')), findsOneWidget);
      expect(find.byKey(const Key('ai-preview-row-draft-2')), findsOneWidget);
      // The uncertainty is an info row (excluded from the decisions).
      expect(find.textContaining('Uncertainty (location)'), findsOneWidget);
      // The apply section: the missing-context notice + disabled button.
      expect(find.byKey(const Key('ai-apply-context-missing')), findsOneWidget);
      final apply = tester.widget<FilledButton>(
        find.byKey(const Key('ai-apply-submit')),
      );
      expect(apply.onPressed, isNull);
      await tester.pump();
    });

    testWidgets('merged preview: matched rows actionable; unmatched rows '
        'render as excluded info cards (no silent coercion)', (tester) async {
      await setupContainer(
        previewValue: Right(_previewResponse(_mergedPayload())),
      );
      await pumpPreview(tester);

      expect(find.text('Merged preview'), findsOneWidget);
      expect(find.byKey(const Key('ai-preview-row-sc-1')), findsOneWidget);
      expect(
        find.textContaining('Unmatched schedule row: row-x'),
        findsOneWidget,
      );
      // Only the matched row carries a decision control.
      expect(find.byKey(const Key('ai-row-decision-sc-1')), findsOneWidget);
      await tester.pump();
    });

    testWidgets('pre-merge schedule preview: informative rows only (no '
        'decision chips)', (tester) async {
      await setupContainer(
        previewValue: Right(_previewResponse(_preMergePayload())),
      );
      await pumpPreview(tester);

      expect(find.text('Schedule preview (pre-merge)'), findsOneWidget);
      expect(find.byKey(const Key('ai-row-decision-row-1')), findsNothing);
      await tester.pump();
    });

    testWidgets('unknown future kind strict-rejects with the stable '
        'degraded card (no guessed rendering)', (tester) async {
      await setupContainer(
        previewValue: const Left(
          ProblemError(code: 'ai_import.preview_kind_unknown'),
        ),
      );
      await pumpPreview(tester);
      expect(find.byKey(const Key('ai-preview-kind-unknown')), findsOneWidget);
      await tester.pump();
    });

    testWidgets('empty preview (404) renders the explicit no-preview state', (
      tester,
    ) async {
      await setupContainer(
        previewValue: const Left(
          ProblemError(code: 'ai_import.preview_missing', status: 404),
        ),
      );
      await pumpPreview(tester);
      expect(find.byKey(const Key('ai-preview-missing')), findsOneWidget);
      await tester.pump();
    });

    testWidgets('a null oneOf value renders the degraded card — never a '
        'build-time cast throw (review: OneOf.value is nullable)', (
      tester,
    ) async {
      await setupContainer(
        previewValue: Right(
          _previewResponse(
            AiPreviewPayload(
              (b) => b
                ..oneOf =
                    OneOf.fromValue3<
                      AiPreviewPayloadOneOf,
                      AiPreviewPayloadOneOf1,
                      AiPreviewPayloadOneOf2
                    >(value: null, typeIndex: 0),
            ),
          ),
        ),
      );
      await pumpPreview(tester);
      expect(find.byKey(const Key('ai-preview-kind-unknown')), findsOneWidget);
      await tester.pump();
    });

    testWidgets('a refreshed payload RE-SEEDS the apply rows (review: '
        'stale draft_refs after a provider refresh)', (tester) async {
      await setupContainer(withPersistedContext: true);
      await pumpPreview(tester);
      expect(
        container.read(aiApplyControllerProvider('job-1')).rows,
        hasLength(2),
        reason: 'the script payload seeds two draft rows',
      );

      // The provider refresh delivers a NEW response at the SAME element
      // position — the seed must follow the payload identity.
      preview.value = Right(
        _previewResponse(
          AiPreviewPayload(
            (b) => b
              ..oneOf =
                  OneOf.fromValue3<
                    AiPreviewPayloadOneOf,
                    AiPreviewPayloadOneOf1,
                    AiPreviewPayloadOneOf2
                  >(
                    value: AiPreviewPayloadOneOf(
                      (b) => b
                        ..kind = AiPreviewPayloadOneOfKindEnum.script
                        ..data.replace(
                          ScriptContext(
                            (b) => b
                              ..title = 'Pilot (refreshed)'
                              ..scenes.replace([
                                _draft('draft-1'),
                                _draft('draft-2'),
                                _draft('draft-3'),
                              ])
                              ..uncertainties.replace([]),
                          ),
                        ),
                    ),
                  ),
          ),
        ),
      );
      container.invalidate(aiPreviewProvider);
      await pumpPreview(tester);

      // The refreshed row renders AND the apply rows followed (3 rows,
      // incl. the new draft-3) — never the stale 2-row seed.
      expect(find.byKey(const Key('ai-preview-row-draft-3')), findsOneWidget);
      expect(
        container.read(aiApplyControllerProvider('job-1')).rows,
        hasLength(3),
      );
      expect(
        container
            .read(aiApplyControllerProvider('job-1'))
            .rows
            .map((r) => r.draftRef),
        contains('draft-3'),
      );
      await tester.pump();
    });

    testWidgets('mixed decisions: Create + Update-from-picked + skip; the '
        'apply 200 renders the outcome summary', (tester) async {
      await setupContainer(
        previewValue: Right(
          _previewResponse(
            AiPreviewPayload(
              (b) => b
                ..oneOf =
                    OneOf.fromValue3<
                      AiPreviewPayloadOneOf,
                      AiPreviewPayloadOneOf1,
                      AiPreviewPayloadOneOf2
                    >(
                      value: AiPreviewPayloadOneOf(
                        (b) => b
                          ..kind = AiPreviewPayloadOneOfKindEnum.script
                          ..data.replace(
                            ScriptContext(
                              (b) => b
                                ..scenes.replace([
                                  _draft('draft-1'),
                                  _draft('draft-2'),
                                  _draft('draft-3'),
                                ])
                                ..uncertainties.replace(
                                  BuiltList(const <Uncertainty>[]),
                                ),
                            ),
                          ),
                      ),
                    ),
            ),
          ),
        ),
        applyQueue: [Right(_outcome())],
      );
      await pumpPreview(tester);

      // Mark draft-2 as Update (picker over the episode's existing
      // aggregates, ids + versions from the read DTOs).
      await tester.tap(find.byKey(const Key('ai-row-decision-draft-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ai-scene-pick-sc-9')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('ai-preview-row-picked-draft-2')),
        findsOneWidget,
      );
      // Skip draft-3.
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('ai-row-decision-draft-3')),
          matching: find.text('Skip'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('ai-apply-submit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ai-apply-outcome')), findsOneWidget);
      expect(find.textContaining('Applied 2 draft(s)'), findsOneWidget);
      // The request carried exactly the acted-on rows.
      expect(repo.lastRequest!.mappings, hasLength(2));
      await tester.pump();
    });

    testWidgets('apply 403 renders the localized narrative', (tester) async {
      await setupContainer(
        applyQueue: [
          const Left(ProblemError(code: 'ai_import.forbidden', status: 403)),
        ],
      );
      await pumpPreview(tester);
      await tester.tap(find.byKey(const Key('ai-apply-submit')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('You need an active costume role'),
        findsOneWidget,
      );
      await tester.pump();
    });

    testWidgets('apply not-succeeded (409-class) renders the job-status '
        'path copy', (tester) async {
      await setupContainer(
        applyQueue: [
          const Left(
            ProblemError(
              code: 'ai_import.apply_job_not_succeeded',
              status: 409,
            ),
          ),
        ],
      );
      await pumpPreview(tester);
      await tester.tap(find.byKey(const Key('ai-apply-submit')));
      await tester.pumpAndSettle();
      expect(find.textContaining('check the job status'), findsOneWidget);
      await tester.pump();
    });

    group('goldens (4.4): merged preview {light,dark}×{android,macos}', () {
      Future<void> pumpGolden(
        WidgetTester tester, {
        required String golden,
        required ThemeMode mode,
        required TargetPlatform platform,
      }) async {
        try {
          debugDefaultTargetPlatformOverride = platform;
          tester.view.physicalSize = const Size(800, 1400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                theme: ThemeData.light(),
                darkTheme: ThemeData.dark(),
                themeMode: mode,
                home: const AiPreviewScreen(jobId: 'job-1'),
              ),
            ),
          );
          for (var i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 10));
          }
          await expectLater(
            find.byType(AiPreviewScreen),
            matchesGoldenFile('goldens/$golden'),
          );
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      }

      testWidgets('merged golden light android', (tester) async {
        await setupContainer(
          previewValue: Right(_previewResponse(_mergedPayload())),
        );
        await pumpGolden(
          tester,
          golden: 'ai_preview_merged_light_android.png',
          mode: ThemeMode.light,
          platform: TargetPlatform.android,
        );
      });

      testWidgets('merged golden dark android', (tester) async {
        await setupContainer(
          previewValue: Right(_previewResponse(_mergedPayload())),
        );
        await pumpGolden(
          tester,
          golden: 'ai_preview_merged_dark_android.png',
          mode: ThemeMode.dark,
          platform: TargetPlatform.android,
        );
      });

      testWidgets('merged golden light macos', (tester) async {
        await setupContainer(
          previewValue: Right(_previewResponse(_mergedPayload())),
        );
        await pumpGolden(
          tester,
          golden: 'ai_preview_merged_light_macos.png',
          mode: ThemeMode.light,
          platform: TargetPlatform.macOS,
        );
      });

      testWidgets('merged golden dark macos', (tester) async {
        await setupContainer(
          previewValue: Right(_previewResponse(_mergedPayload())),
        );
        await pumpGolden(
          tester,
          golden: 'ai_preview_merged_dark_macos.png',
          mode: ThemeMode.dark,
          platform: TargetPlatform.macOS,
        );
      });
    });
  });
}

class _ImmediateScheduler extends ReconciliationScheduler {
  const _ImmediateScheduler();

  @override
  Future<void> tick(int attempt) => Future<void>.value();
}
