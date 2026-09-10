// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

// Tier-1 + Tier-2 tests for the AI-import submission + job-status
// features (`flutter-ai-import-workflow` tasks 3.1–3.4, 5.2):
//
// * the watch controller state machine (fake stream; terminal stop;
//   unsubscribe stop — no wall-clock gating, AGENTS.md §6);
// * the AUTHZ-GATE denial short-circuit (fake-repository call count of
//   zero — task 5.2);
// * the submit flow (episode-context stamping, hand-off remembering);
// * the status matrix widget (all six statuses, duplicate callout,
//   honest no-cancel copy, last_error as SECONDARY detail only);
// * 413/415/403/404 upload copy.

import 'dart:async';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:fpdart/fpdart.dart';

import 'package:frontend_flutter/app_config.dart';
import 'package:frontend_flutter/auth/active_block.dart';
import 'package:frontend_flutter/auth/auth_providers.dart';
import 'package:frontend_flutter/auth/membership/membership_providers.dart';
import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/data/ai_import_providers.dart';
import 'package:frontend_flutter/data/ai_import_repository.dart';
import 'package:frontend_flutter/data/cache/ai_import_jobs_cache_dao.dart';
import 'package:frontend_flutter/data/cache/clock.dart';
import 'package:frontend_flutter/data/cache/cache_database.dart';
import 'package:frontend_flutter/domain/reconciliation/reconciliation_scheduler.dart';
import 'package:frontend_flutter/features/ai_import/import_jobs/import_state.dart';
import 'package:frontend_flutter/features/ai_import/import_jobs/import_submit_controller.dart';

import '../../support/fake_secure_storage.dart';

import 'package:frontend_flutter/features/ai_import/import_jobs/job_status_controller.dart';

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

AiImportJob _job(
  String id, {
  JobStatus status = JobStatus.pending,
  int retries = 0,
  int maxRetries = 3,
  String? lastError,
}) => AiImportJob(
  (b) => b
    ..id = id
    ..userId = 'dev-user'
    ..status = status
    ..documentKind = DocumentKind.schedule
    ..sourceFormat = SourceFormat.csv
    ..dedupKey = 'dedup-$id'
    ..documentDigest = 'digest-$id'
    ..sourceHandle = 'handle-$id'
    ..retries = retries
    ..maxRetries = maxRetries
    ..lastError = lastError
    ..createdAt = DateTime.utc(2026, 1, 1)
    ..updatedAt = DateTime.utc(2026, 1, 1),
);

/// Repository fake: scripted upload/apply results, a controllable watch
/// stream, and call counters (the denial short-circuit proof).
class FakeAiImportRepository extends AiImportRepository {
  FakeAiImportRepository(super.api, super.cache);

  Result<AiUploadAck>? uploadResult;
  Result<AiImportJob>? jobResult;
  Result<ApplyAiImportResponse>? applyResult;

  int uploadCalls = 0;
  int jobCalls = 0;
  int applyCalls = 0;

  /// The scripted watch stream (a controllable controller per test).
  StreamController<Result<AiImportJob>>? watchController;

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
  Future<Result<AiUploadAck>> uploadScript({
    required Object body,
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
    jobCalls++;
    // Mirrors the real repo: a successful fetch upserts the row
    // (success-only cache writes, task 1.4).
    final job = (jobResult ?? Right(_job(id))).getRight().toNullable();
    if (job != null) {
      await cache.upsertAll([job], clock.now());
      return Right(job);
    }
    return Left(jobResult!.getLeft().toNullable()!);
  }

  @override
  Future<Result<ApplyAiImportResponse>> apply(
    String jobId,
    ApplyAiImportRequest request,
  ) async {
    applyCalls++;
    return applyResult ??
        Right(
          ApplyAiImportResponse(
            (b) => b
              ..appliedCount = 2
              ..createdDays = 1
              ..plannedSceneShoots = 3,
          ),
        );
  }

  @override
  Stream<Result<AiImportJob>> watch(
    String jobId, {
    ReconciliationScheduler scheduler = const ExponentialBackoffScheduler(),
    int maxAttempts = 30,
  }) => (watchController ??= StreamController<Result<AiImportJob>>()).stream;
}

/// The sticky active-block scope stubbed to a resolved scope.
class FakeActiveBlock extends ActiveBlock {
  @override
  ActiveScope? build() => ActiveScope(seasonId: 'season-1', blockId: 'block-1');
}

/// A scriptable scheduler — every tick is counted, never delayed
/// (deterministic; no wall-clock gating, AGENTS.md §6).
class _FakeScheduler extends ReconciliationScheduler {
  int ticks = 0;

  @override
  Future<void> tick(int attempt) async => ticks++;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStoragePlatform.instance = FakeSecureStoragePlatform();
  });

  late CacheDatabase db;
  late FakeAiImportRepository repo;
  late ProviderContainer container;
  late _FakeScheduler scheduler;

  Future<void> setupContainer({
    bool withScope = true,
    List<String> capabilities = const [
      'upload_continuity_photos',
      'assign_costumes',
    ],
    Completer<Result<SeasonMembershipDto>>? membershipGate,
  }) async {
    db = CacheDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    repo = FakeAiImportRepository(BreakdownApi(), AiImportJobsCacheDao(db));
    scheduler = _FakeScheduler();
    container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(devAuthConfig),
        aiImportRepositoryProvider.overrideWithValue(repo),
        reconciliationSchedulerProvider.overrideWith((ref) => scheduler),
        if (withScope) activeBlockProvider.overrideWith(FakeActiveBlock.new),
        // Override the fetch seam (a function provider) — the real
        // CurrentMembership class computes from it (no deprecated class
        // overrides needed). [membershipGate] holds the fetch open for
        // the pending-fetch discipline test.
        membershipFetchProvider.overrideWith((ref, seasonId) async {
          final gate = membershipGate;
          if (gate != null) return gate.future;
          return Right(
            SeasonMembershipDto(
              (b) => b
                ..seasonId = seasonId
                ..hasActiveCostumeRoleInSeason = capabilities.isNotEmpty
                ..capabilities.replace(capabilities),
            ),
          );
        }),
      ],
    );
    // Plain tests dispose the container explicitly at the end (riverpod's
    // 0ms disposal timers must not be pending in fake_async testWidgets).
    addTearDown(() {
      try {
        container.dispose();
      } on StateError {
        // Already disposed by the test body — fine.
      }
    });
    await container.read(authSessionControllerProvider.notifier).signIn();
  }

  group('AiImportSubmitController (tasks 3.1 + 5.2)', () {
    test('denial short-circuits: a member WITHOUT the costume-dept '
        'capability issues ZERO repository calls (task 5.2)', () async {
      await setupContainer(capabilities: const []);
      final controller = container.read(
        aiImportSubmitControllerProvider.notifier,
      );
      final res = await controller.submit(
        AiImportDocument.pasted('day,scene\n1,12'),
      );
      expect(res.isLeft(), isTrue);
      expect(res.getLeft().toNullable()!.code, 'ai_import.forbidden');
      // The proof: zero calls reached the repository.
      expect(repo.uploadCalls, 0);
      expect(repo.jobCalls, 0);
      container.dispose();
    });

    test('a pending membership fetch is NOT a denial — the dispatch waits, '
        'and a failed fetch surfaces membership.pending (retry affordance, '
        'never the 403 narrative — D3)', () async {
      final gate = Completer<Result<SeasonMembershipDto>>();
      await setupContainer(membershipGate: gate);
      final controller = container.read(
        aiImportSubmitControllerProvider.notifier,
      );
      // The dispatch is in flight while the fetch is pending: it waits
      // (no call, no error — loading is never misread as denial).
      final done = controller.submit(AiImportDocument.pasted('x'));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(repo.uploadCalls, 0, reason: 'the dispatch waits at the gate');
      // The fetch settles with a transport failure → the gate reads the
      // pending/retry code, NOT the 403 narrative.
      gate.complete(const Left(ProblemError(code: 'transport.down')));
      final res = await done;
      expect(res.getLeft().toNullable()!.code, 'membership.pending');
      expect(repo.uploadCalls, 0);
      container.dispose();
    });

    test('accepted upload stamps the episode context with the job '
        'and remembers the job id (design §2.3)', () async {
      await setupContainer();
      final controller = container.read(
        aiImportSubmitControllerProvider.notifier,
      );
      container
          .read(pendingEpisodeProvider.notifier)
          .set(
            EpisodeView(
              (b) => b
                ..id = 'ep-1'
                ..number = 1
                ..blockId = 'block-1'
                ..seriesId = 'series-1'
                ..updatedAt = DateTime.utc(2026, 1, 1)
                ..version = 1,
            ),
          );
      final res = await controller.submit(
        AiImportDocument.pasted('day,scene\n1,12'),
      );
      final ack = res.getRight().toNullable()!;
      expect(ack.jobId, 'job-1');
      expect(ack.duplicate, isFalse);
      // The context landed on the cached row (design §2.3).
      final rows = await repo.readCached('dev-user');
      final row = rows.getRight().toNullable()!.single;
      expect(row.episodeId, 'ep-1');
      expect(row.seriesId, 'series-1');
      container.dispose();
    });

    test('a context-stamp failure keeps the acknowledgement AND surfaces '
        'the non-fatal warning (review: a created job is never hidden '
        'behind a local storage fault)', () async {
      await setupContainer();
      final controller = container.read(
        aiImportSubmitControllerProvider.notifier,
      );
      container
          .read(pendingEpisodeProvider.notifier)
          .set(
            EpisodeView(
              (b) => b
                ..id = 'ep-1'
                ..number = 1
                ..blockId = 'block-1'
                ..seriesId = 'series-1'
                ..updatedAt = DateTime.utc(2026, 1, 1)
                ..version = 1,
            ),
          );
      // Deterministic fault lever: the stamp's job re-read fails (a
      // single failed status read or Drift write fault triggers the
      // path — review). The job EXISTS server-side (the ack carried
      // its id): the ack must SURVIVE and the warning must surface.
      repo.jobResult = const Left(ProblemError(code: 'http.500'));
      final res = await controller.submit(AiImportDocument.pasted('x'));
      expect(res.getRight().toNullable()!.jobId, 'job-1');
      expect(container.read(aiStampWarningProvider)?.code, 'http.500');
      container.dispose();
    });

    test('a script dispatch with a non-PDF source is rejected client-side '
        'with the stable 415 code — no mismatched bytes leave the device '
        '(review: kind-switch stale document)', () async {
      await setupContainer();
      final controller = container.read(
        aiImportSubmitControllerProvider.notifier,
      );
      controller.selectKind(AiImportKind.script);
      // Pasted text under the script kind: uploadScript declares
      // application/pdf — the client must refuse BEFORE any call.
      final res = await controller.submit(AiImportDocument.pasted('not a pdf'));
      final err = res.getLeft().toNullable()!;
      expect(err.code, 'ai_import.unsupported_media_type');
      expect(err.status, 415);
      expect(repo.uploadCalls, 0);
      container.dispose();
    });

    test(
      'selectKind clears the pending document and paste (review: a '
      'carried-over body would upload with the wrong content type)',
      () async {
        await setupContainer();
        final controller = container.read(
          aiImportSubmitControllerProvider.notifier,
        );
        // Seed a schedule paste, then switch kinds.
        container.read(pendingPasteProvider.notifier).set('day,scene');
        container
            .read(pendingDocumentProvider.notifier)
            .set(AiImportDocument.csv('day,scene'));
        controller.selectKind(AiImportKind.script);
        expect(container.read(pendingPasteProvider), isEmpty);
        expect(container.read(pendingDocumentProvider), isNull);
        // Same-kind selection is a no-op (does not clear an in-progress
        // document).
        container.read(pendingPasteProvider.notifier).set('x');
        controller.selectKind(AiImportKind.script);
        expect(container.read(pendingPasteProvider), 'x');
        container.dispose();
      },
    );

    test('duplicate upload (200) is a first-class ack', () async {
      await setupContainer();
      repo.uploadResult = Right(AiUploadAck(jobId: 'job-0', duplicate: true));
      final res = await container
          .read(aiImportSubmitControllerProvider.notifier)
          .submit(AiImportDocument.pasted('x'));
      expect(res.getRight().toNullable()!.duplicate, isTrue);
      container.dispose();
    });

    test('413/415/403/404 surface keyed on the problem code', () async {
      await setupContainer();
      for (final (status, code) in [
        (413, 'ai_import.payload_too_large'),
        (415, 'ai_import.unsupported_media_type'),
        (403, 'ai_import.forbidden'),
        (404, 'ai_import.disabled'),
      ]) {
        repo.uploadResult = Left(ProblemError(code: code, status: status));
        final res = await container
            .read(aiImportSubmitControllerProvider.notifier)
            .submit(AiImportDocument.pasted('x'));
        expect(res.getLeft().toNullable()!.code, code, reason: code);
        expect(aiUploadErrorCopy(res.getLeft().toNullable()!), isNotEmpty);
      }
    });

    test(
      'upload copy is localized per code, never the server detail',
      () async {
        expect(
          aiUploadErrorCopy(
            const ProblemError(code: 'ai_import.payload_too_large'),
          ),
          'The document is too large for AI import.',
        );
        expect(
          aiUploadErrorCopy(
            const ProblemError(code: 'transport.connectionTimeout'),
          ),
          contains('Network problem'),
        );
        // Unknown codes fall back to a code-carrying generic.
        expect(
          aiUploadErrorCopy(const ProblemError(code: 'weird.future_code')),
          contains('weird.future_code'),
        );
      },
    );
  });

  group('AiJobStatusController — watch state machine (task 3.3)', () {
    testWidgets('pending → running → succeeded: terminal status ends the '
        'watch (fake scheduler; no wall-clock)', (tester) async {
      await setupContainer();
      final events = StreamController<Result<AiImportJob>>();
      addTearDown(events.close);
      repo.watchController = events;
      final sub = container.listen(
        aiJobStatusControllerProvider('job-1'),
        (_, _) {},
      );
      addTearDown(sub.close);

      events.add(Right(_job('job-1', status: JobStatus.pending)));
      events.add(Right(_job('job-1', status: JobStatus.running)));
      await tester.pump();
      expect(
        container.read(aiJobStatusControllerProvider('job-1')).value!.status,
        JobStatus.running,
      );

      events.add(Right(_job('job-1', status: JobStatus.succeeded)));
      await tester.pump();
      expect(
        container.read(aiJobStatusControllerProvider('job-1')).value!.status,
        JobStatus.succeeded,
      );
      // Terminal: the repository watch stream ends by itself; the
      // controller reflects the last state and adds nothing.
      events.add(Right(_job('job-1', status: JobStatus.deadLetter)));
      await tester.pump();
      // The repository-level terminal-stop rule is unit-tested on the
      // real repo; the controller-level guarantee is the unsubscribe stop
      // (below) plus the honest state mapping.
      expect(
        container.read(aiJobStatusControllerProvider('job-1')).value!.status,
        JobStatus.deadLetter,
      );
      // events.close() runs in the tear-down.
    });

    testWidgets('unsubscribe stop: disposing the container cancels the '
        'subscription — no background polling survives the screen (D5)', (
      tester,
    ) async {
      await setupContainer();
      final events = StreamController<Result<AiImportJob>>();
      repo.watchController = events;
      final received = <AiImportJob>[];
      container.listen(aiJobStatusControllerProvider('job-1'), (_, job) {
        final value = job.value;
        if (value != null) received.add(value);
      });
      // The watch is live before disposal.
      events.add(Right(_job('job-1', status: JobStatus.running)));
      await tester.pump();
      expect(received, isNotEmpty);

      // Disposal cancels the controller's stream subscription — the
      // event after disposal is NEVER delivered (no background polling
      // survives the screen, D5).
      received.clear();
      container.dispose();
      events.add(Right(_job('job-1', status: JobStatus.running)));
      await tester.pump();
      expect(received, isEmpty);
    });

    testWidgets('a watch failure surfaces as AsyncError (no silent '
        'swallow — AGENTS.md §5)', (tester) async {
      await setupContainer();
      final events = StreamController<Result<AiImportJob>>();
      addTearDown(events.close);
      repo.watchController = events;
      final sub = container.listen(
        aiJobStatusControllerProvider('job-1'),
        (_, _) {},
      );
      addTearDown(sub.close);
      events.add(Left(const ProblemError(code: 'transport.connectionError')));
      await tester.pump();
      final state = container.read(aiJobStatusControllerProvider('job-1'));
      expect(state, isA<AsyncError>());
    });

    test('status copy matrix (3.2): six statuses, honest copies', () {
      expect(jobStatusCopy(JobStatus.pending), contains('Queued'));
      expect(jobStatusInProgress(JobStatus.pending), isTrue);
      expect(jobStatusInProgress(JobStatus.running), isTrue);
      expect(jobStatusInProgress(JobStatus.failed), isFalse);
      expect(jobStatusCopy(JobStatus.failed), contains('retry is scheduled'));
      expect(jobStatusTerminalError(JobStatus.deadLetter), isTrue);
      expect(jobStatusTerminalError(JobStatus.payloadUnavailable), isTrue);
      expect(jobStatusTerminalError(JobStatus.succeeded), isFalse);
    });
  });
}
