// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

// On-device E2E smoke for the AI-import pipeline (`flutter-ai-import`
// task 6.1): submit → job → preview → apply → summary, driven through the
// REAL controllers/screens with the LLM path faked at the REPOSITORY seam
// (deterministic — no network LLM in CI, design §4). The fake pipeline is
// a controllable in-memory double: the upload acks, the job status
// transitions and the preview payload are scripted; the Drift cache, the
// episode-context persistence and the hand-off store run for real.

import 'dart:async';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:built_collection/built_collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:one_of/one_of.dart';

import 'package:frontend_flutter/app_config.dart';
import 'package:frontend_flutter/auth/active_block.dart';
import 'package:frontend_flutter/auth/auth_providers.dart';
import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/data/ai_import_providers.dart';
import 'package:frontend_flutter/data/ai_import_repository.dart';
import 'package:frontend_flutter/data/cache/ai_import_jobs_cache_dao.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/data/cache/clock.dart';
import 'package:frontend_flutter/domain/reconciliation/reconciliation_scheduler.dart';
import 'package:frontend_flutter/features/ai_import/import_jobs/import_submit_controller.dart';
import 'package:frontend_flutter/features/ai_import/import_jobs/import_submit_screen.dart';
import 'package:frontend_flutter/features/ai_import/import_jobs/job_status_screen.dart';
import 'package:frontend_flutter/features/ai_import/import_jobs/preview_screen.dart';

SceneView _scene(String id, int number) => SceneView(
  (b) => b
    ..id = id
    ..episodeId = 'ep-1'
    ..assignedCharacters.replace(const <String>[])
    ..isScheduleSet = false
    ..sceneNumber = number
    ..shootingDayIds.replace(const <String>[])
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

AiImportJob _job(String id, JobStatus status) => AiImportJob(
  (b) => b
    ..id = id
    ..userId = 'dev-e2e'
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
                          ..scene.replace(_scene('sc-1', 12))
                          ..scheduleRows.replace(
                            BuiltList(const <ShootingScheduleRow>[]),
                          ),
                      ),
                    ])
                    ..unmatchedScheduleRows.replace(
                      BuiltList(const <ShootingScheduleRow>[]),
                    )
                    ..unmatchedScriptScenes.replace(
                      BuiltList(const <SceneView>[]),
                    ),
                ),
              ),
          ),
        ),
);

/// The repository-seamed fake pipeline (design §4): the LLM paths are
/// faked; the cache/hand-off writes run for real.
class FakePipelineRepository extends AiImportRepository {
  FakePipelineRepository(super.api, super.cache);

  Result<AiImportJob>? jobResult;
  Result<ApplyAiImportResponse>? applyResult;

  @override
  Future<Result<AiUploadAck>> uploadSchedule({
    required Object body,
    required AiScheduleSource source,
    void Function(int, int)? onSendProgress,
  }) async => Right(AiUploadAck(jobId: 'job-e2e', duplicate: false));

  @override
  Future<Result<AiImportJob>> getJobAndCache(
    String id, {
    Clock clock = Clock.system,
  }) async {
    final view = jobResult!.getRight().toNullable()!;
    await cache.upsertAll([view], clock.now());
    return Right(view);
  }

  @override
  Stream<Result<AiImportJob>> watch(
    String jobId, {
    ReconciliationScheduler scheduler = const ExponentialBackoffScheduler(),
    int maxAttempts = 30,
  }) async* {
    // The fake LLM path: pending → succeeded (one scripted transition,
    // no wall-clock gating).
    yield Right(_job(jobId, JobStatus.pending));
    yield Right(_job(jobId, JobStatus.succeeded));
  }

  @override
  Future<Result<AiImportPreviewResponse>> getPreview(String id) async => Right(
    AiImportPreviewResponse(
      (b) => b
        ..jobId = id
        ..documentKind = DocumentKind.schedule
        ..status = JobStatus.succeeded
        ..preview.replace(_mergedPayload()),
    ),
  );

  @override
  Future<Result<ApplyAiImportResponse>> apply(
    String jobId,
    ApplyAiImportRequest request,
  ) async => Right(
    ApplyAiImportResponse(
      (b) => b
        ..appliedCount = 1
        ..createdDays = 1
        ..plannedSceneShoots = 2,
    ),
  );
}

/// Immediate scheduler (deterministic, no wall-clock on-device).
class _E2eScheduler extends ReconciliationScheduler {
  const _E2eScheduler();

  @override
  Future<void> tick(int attempt) => Future<void>.value();
}

/// Sticky scope stub: the smoke runs in a resolved block context.
class FakeActiveBlock extends ActiveBlock {
  @override
  ActiveScope? build() =>
      ActiveScope(seasonId: 'season-e2e', blockId: 'block-e2e');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const devConfig = AppConfig(
    flavor: Flavor.dev,
    apiBase: 'http://10.0.2.2:3000',
    oidcIss: '',
    devAuthSub: 'dev-e2e',
    oidcAudience: '',
    oidcClientId: '',
    oidcRedirectUri: '',
    devIdpInsecure: '',
    appVersion: '1.0.0+1',
    defaultSeriesId: 'series-e2e',
  );

  testWidgets('submit → job → preview → apply → summary (fake LLM '
      'pipeline, repository-seamed)', (tester) async {
    final db = CacheDatabase();
    addTearDown(db.close);
    final repo = FakePipelineRepository(
      BreakdownApi(),
      AiImportJobsCacheDao(db),
    );
    repo.jobResult = Right(_job('job-e2e', JobStatus.succeeded));
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(devConfig),
        aiImportRepositoryProvider.overrideWithValue(repo),
        reconciliationSchedulerProvider.overrideWith(
          (ref) => const _E2eScheduler(),
        ),
        activeBlockProvider.overrideWith(FakeActiveBlock.new),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authSessionControllerProvider.notifier).signIn();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: AiImportSubmitScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Submit: paste the schedule text and dispatch (the membership
    //    pre-gate runs in dev-auth mode → permissive, no IdP).
    container
        .read(pendingEpisodeProvider.notifier)
        .set(
          EpisodeView(
            (b) => b
              ..id = 'ep-e2e'
              ..number = 1
              ..blockId = 'block-e2e'
              ..seriesId = 'series-e2e'
              ..updatedAt = DateTime.utc(2026, 1, 1)
              ..version = 1,
          ),
        );
    container.read(pendingPasteProvider.notifier).set('day,scene\n1,12\n1,13');
    await tester.tap(find.byKey(const Key('ai-import-submit')));
    await tester.pumpAndSettle();

    // 2. The job status screen pushed with the returned id.
    expect(find.byType(AiJobStatusScreen), findsOneWidget);
    expect(find.byKey(const Key('ai-job-succeeded')), findsOneWidget);

    // 3. Open the typed preview.
    await tester.tap(find.byKey(const Key('ai-job-open-preview')));
    await tester.pumpAndSettle();
    expect(find.byType(AiPreviewScreen), findsOneWidget);
    expect(find.byKey(const Key('ai-preview-row-sc-1')), findsOneWidget);

    // 4. Apply (accept as-is — zero edits, edit_distance 0).
    await tester.tap(find.byKey(const Key('ai-apply-submit')));
    await tester.pumpAndSettle();

    // 5. The outcome summary card reflects the server's counts.
    expect(find.byKey(const Key('ai-apply-outcome')), findsOneWidget);
    expect(find.textContaining('Applied 1 draft(s)'), findsOneWidget);

    // 6. The episode context persisted with the job (design §2.3).
    final rows = await repo.readCached();
    final row = rows.getRight().toNullable()!.single;
    expect(row.episodeId, 'ep-e2e');
    expect(row.seriesId, 'series-e2e');
  });
}
