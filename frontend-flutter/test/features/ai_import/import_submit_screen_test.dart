// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

// Tier-2 widget tests for the AI-import submission screen
// (`flutter-ai-import-workflow` tasks 3.1 + 3.4): the kind picker, the
// paste field, the missing-document guard, the 202 → job-status
// navigation and the 200-duplicate navigation with the callout. The
// file-picker path is exercised on-device (integration smoke) — the
// paste path is fully covered here.

import 'package:breakdown_api/breakdown_api.dart';
import 'package:drift/native.dart';
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
import 'package:frontend_flutter/features/ai_import/import_jobs/import_submit_screen.dart';
import 'package:frontend_flutter/features/ai_import/import_jobs/job_status_screen.dart';

import '../../unit/ai_import_repositories_test.dart'
    show FakeSecureStoragePlatform;

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

  @override
  Future<Result<AiUploadAck>> uploadSchedule({
    required Object body,
    required AiScheduleSource source,
    void Function(int, int)? onSendProgress,
  }) async {
    uploadCalls++;
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
  }) async* {
    yield Right(_job(jobId, JobStatus.succeeded));
  }
}

class FakeActiveBlock extends ActiveBlock {
  @override
  ActiveScope? build() => ActiveScope(seasonId: 'season-1', blockId: 'block-1');
}

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
        activeBlockProvider.overrideWith(FakeActiveBlock.new),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authSessionControllerProvider.notifier).signIn();
  }

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: AiImportSubmitScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the kind picker switches schedule/script copy; the '
      'paste field exists for schedules only', (tester) async {
    await setupContainer();
    await pumpScreen(tester);
    expect(find.byKey(const Key('ai-import-paste-field')), findsOneWidget);
    expect(find.text('Scripts: pick a PDF file.'), findsNothing);

    await tester.tap(find.text('Script'));
    await tester.pumpAndSettle();
    expect(find.text('Scripts: pick a PDF file.'), findsOneWidget);
    // The paste field disappears for the script kind (PDF only).
    expect(find.byKey(const Key('ai-import-paste-field')), findsNothing);
    await tester.pump();
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

  testWidgets('a 202 upload pushes the job-status screen (no callout)', (
    tester,
  ) async {
    await setupContainer(jobResult: Right(_job('job-1', JobStatus.pending)));
    await pumpScreen(tester);
    await tester.enterText(
      find.byKey(const Key('ai-import-paste-field')),
      'day,scene\n1,12',
    );
    await tester.ensureVisible(find.byKey(const Key('ai-import-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ai-import-submit')));
    await tester.pumpAndSettle();

    expect(repo.uploadCalls, 1);
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
    await tester.enterText(
      find.byKey(const Key('ai-import-paste-field')),
      'same bytes',
    );
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
        ProblemError(code: 'ai_import.payload_too_large', status: 413),
      ),
    );
    await pumpScreen(tester);
    await tester.enterText(
      find.byKey(const Key('ai-import-paste-field')),
      'big',
    );
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
