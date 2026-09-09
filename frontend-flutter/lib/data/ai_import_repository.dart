// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:dio/dio.dart';
import 'package:fpdart/fpdart.dart';

import '../core/problem_error.dart';
import '../core/result.dart';
import '../domain/reconciliation/reconciliation_scheduler.dart';
import 'base_repository.dart';
import 'cache/ai_import_jobs_cache_dao.dart';
import 'cache/cache_database.dart';
import 'cache/clock.dart';

/// Bounded attempt budget for the job watch (design D5): the first fetch
/// runs immediately, later attempts back off via the shared scheduler.
/// Foreground-only — the watching screen's provider disposal cancels the
/// subscription, which ends the loop (no background polling/wake-ups).
const int kMaxJobWatchAttempts = 30;

/// Bounded attempt budget for the apply reconciliation (task 1.2): an
/// ambiguous-timeout apply re-reads the job first, then retries — never
/// blind re-dispatch (server-side idempotency per backend issue #338 /
/// PR #351 makes the bounded retry safe).
const int kMaxApplyAttempts = 3;

/// The declared raw-body content types the schedule upload accepts
/// (backend `upload_ai_schedule` contract; anything else is a 415).
enum AiScheduleSource { csv, pdf, plainText }

/// The raw-body content type for a script upload (PDF only, per contract).
const String kScriptContentType = 'application/pdf';

/// Wire content type for an [AiScheduleSource].
String scheduleContentType(AiScheduleSource source) => switch (source) {
  AiScheduleSource.csv => 'text/csv',
  AiScheduleSource.pdf => 'application/pdf',
  AiScheduleSource.plainText => 'text/plain',
};

/// The upload acknowledgement (task 1.2): both 202 (enqueued) and 200
/// (digest-duplicate) are first-class happy paths — [duplicate] drives the
/// submission screen's explicit "already imported (duplicate)" callout.
class AiUploadAck {
  const AiUploadAck({required this.jobId, required this.duplicate});

  /// The job id (202's fresh job or 200's existing job).
  final String jobId;

  /// True when the backend answered 200 — the document was already
  /// imported; nothing implies a second job was created.
  final bool duplicate;
}

/// The reconciled outcome of an ambiguous apply dispatch (task 1.2).
sealed class ApplyReconciliation {
  const ApplyReconciliation();
}

/// The apply 200'd (first attempt or a reconciled retry).
class ApplySucceeded extends ApplyReconciliation {
  const ApplySucceeded(this.response);

  final ApplyAiImportResponse response;
}

/// The job re-read after an ambiguous timeout proves the apply cannot
/// proceed (job gone / not succeeded / preview missing) — the surfaced
/// error, never a blind re-dispatch.
class ApplyBlocked extends ApplyReconciliation {
  const ApplyBlocked(this.error);

  final ProblemError error;
}

/// The reconciliation budget exhausted with the outcome still unknown —
/// surfaced honestly; the user re-checks the job status (the server-side
/// apply is idempotent, so a manual re-apply is safe).
class ApplyUnresolved extends ApplyReconciliation {
  const ApplyUnresolved(this.error);

  final ProblemError error;
}

/// Read/write repository for the AI-import **workflow** boundary
/// (`flutter-ai-import-workflow` tasks 1.2/1.4).
///
/// Route contract (design §1): raw-body uploads (`POST /v1/ai-import/
/// schedules|scripts`) with the declared `Content-Type`; 202 enqueued /
/// 200 duplicate → the JSON-string job id; job status `GET /v1/ai-import/
/// jobs/{id}`; the typed preview `GET /v1/ai-import/jobs/{id}/preview`
/// (NEVER cached — regenerable, design §3); the apply command `POST
/// /v1/ai-import/jobs/{id}/apply`.
///
/// The uploads go through [BreakdownApi.dio] directly instead of the
/// generated `uploadAiSchedule`/`uploadAiScript` methods for one reason:
/// the generated methods pin `Options.contentType` (`text/plain` /
/// `application/pdf`), and a Dio `Options.contentType` overrides a
/// caller-set `Content-Type` header — the declared CSV/PDF schedule types
/// would be silently clobbered and the backend would 415 (or worse, route
/// the bytes down the wrong extraction path). The wire request is
/// unchanged: same path, same raw body, same declared media type; the
/// response is the same JSON-string job id the generated `Response<String>`
/// surfaces. All other routes use the generated client exclusively.
///
/// Cache-write discipline (task 1.4, design §3): job rows upsert into
/// Drift on successful fetches only (merge — the jobs list is a windowed
/// newest-first list, so snapshot-delete would evict remembered jobs and
/// their persisted episode context); a failed fetch never mutates the
/// cache. The preview is never cached.
class AiImportRepository extends BaseRepository {
  const AiImportRepository(super.api, this.cache);

  final AiImportJobsCacheDao cache;

  // --- Submission (raw-body upload) ------------------------------------------

  /// `POST /v1/ai-import/schedules` — raw body with the declared
  /// [source] content type (`text/csv` | `application/pdf` |
  /// `text/plain`). CSV/paste bodies travel as UTF-8 [String]; a picked
  /// PDF travels as raw [Uint8List] bytes (a String body would be UTF-8
  /// re-encoded and corrupt the PDF). Branches on the response status:
  /// 202 enqueued, 200 digest-duplicate.
  ///
  /// // AUTHZ-GATE: callers check the season costume-dept membership via
  /// `currentMembershipProvider` BEFORE invoking; denial issues zero calls.
  Future<Result<AiUploadAck>> uploadSchedule({
    required Object body,
    required AiScheduleSource source,
    void Function(int count, int total)? onSendProgress,
  }) => _upload(
    '/v1/ai-import/schedules',
    body,
    scheduleContentType(source),
    onSendProgress,
  );

  /// `POST /v1/ai-import/scripts` — raw bytes body, `application/pdf` only
  /// (per the content-type contract; a non-PDF script upload is a client
  /// bug, not a 415 retry case).
  ///
  /// // AUTHZ-GATE: same membership pre-gate as the schedule upload.
  Future<Result<AiUploadAck>> uploadScript({
    required Object body,
    void Function(int count, int total)? onSendProgress,
  }) => _upload(
    '/v1/ai-import/scripts',
    body,
    kScriptContentType,
    onSendProgress,
  );

  /// Raw-body upload via the client Dio. Never throws; maps every error to
  /// a [ProblemError] keyed on the backend problem `code` (413/415/403/404
  /// all arrive as RFC 9457 problem+json — AGENTS.md §5). [body] is a
  /// [String] (UTF-8 text) or [Uint8List] (raw bytes, e.g. PDFs).
  Future<Result<AiUploadAck>> _upload(
    String path,
    Object body,
    String contentType,
    void Function(int count, int total)? onSendProgress,
  ) async {
    try {
      final response = await api.dio.post<String>(
        path,
        data: body,
        options: Options(
          contentType: contentType,
          // Default JSON response type: the backend returns the job id as a
          // JSON string (`"<uuid>"`), which the transformer decodes to the
          // plain String the generated `Response<String>` surfaces.
          // Both 200 (duplicate) and 202 (enqueued) are acknowledged —
          // the branch happens on the status code below.
          validateStatus: (status) => status == 200 || status == 202,
        ),
        onSendProgress: onSendProgress,
      );
      final jobId = response.data?.trim() ?? '';
      if (jobId.isEmpty) {
        return const Left(ProblemError(code: 'ai_import.dto_invalid'));
      }
      return Right(
        AiUploadAck(jobId: jobId, duplicate: response.statusCode == 200),
      );
    } on DioException catch (e) {
      return Left(problemErrorFromDio(e));
    }
  }

  // --- Job status ------------------------------------------------------------

  /// `GET /v1/ai-import/jobs/{id}` → [AiImportJobResponse]. On success the
  /// row upserts into Drift (success-only cache writes, preserving the
  /// client-local episode context).
  Future<Result<AiImportJob>> getJobAndCache(
    String id, {
    Clock clock = Clock.system,
  }) async {
    final fetched = await run(
      () => api.getHandlersApi().getAiImportJob(id: id),
      dtoInvalidCode: 'ai_import.dto_invalid',
    );
    return fetched.match((err) async => Left<ProblemError, AiImportJob>(err), (
      response,
    ) async {
      try {
        await cache.upsertAll([response.job], clock.now());
      } on Object {
        return const Left(ProblemError(code: 'cache.write_failed'));
      }
      return Right(response.job);
    });
  }

  /// `GET /v1/ai-import/jobs` — the caller's jobs, newest-first (backend
  /// issue #337, PR #357), paginated through every page. On success the
  /// fetched rows upsert into Drift (merge — never snapshot-delete; see
  /// the class doc).
  Future<Result<List<AiImportJob>>> listJobsAndCache({
    Clock clock = Clock.system,
  }) async {
    final fetched = await fetchAllPages<AiImportJobResponse>(
      ({required int limit, required int offset}) =>
          api.getHandlersApi().listAiImportJobs(limit: limit, offset: offset),
      dtoInvalidCode: 'ai_import.dto_invalid',
    );
    return fetched.match(
      (err) async => Left<ProblemError, List<AiImportJob>>(err),
      (rows) async {
        final jobs = rows.map((r) => r.job).toList();
        try {
          await cache.upsertAll(jobs, clock.now());
        } on Object {
          return const Left(ProblemError(code: 'cache.write_failed'));
        }
        return Right(jobs);
      },
    );
  }

  /// Pure Drift read (no network) of the cached job rows, newest-first.
  Future<Result<List<AiImportJobCacheRow>>> readCached() async {
    try {
      return Right(await cache.readAll());
    } on Object {
      return const Left(ProblemError(code: 'cache.read_failed'));
    }
  }

  /// Empties the job cache (sign-out / backend-switch resets —
  /// identity-scoped, design §3).
  Future<Result<void>> clearCache() async {
    try {
      await cache.clear();
      return const Right<ProblemError, void>(null);
    } on Object {
      return const Left(ProblemError(code: 'cache.clear_failed'));
    }
  }

  /// Watches a job's status with bounded, foreground-only refetching
  /// (design D5, task 3.2): the first fetch runs immediately, later
  /// attempts wait on the shared bounded-backoff [scheduler]; terminal
  /// statuses (`succeeded`, `dead_letter`, `payload_unavailable`) end the
  /// watch. A cancelled subscription ends the loop at the next suspension
  /// (unsubscribe stop) — no background polling survives the screen.
  ///
  /// Yields `Right(job)` on every successful read and `Left(error)` on a
  /// failed one (transient transport failures are retried within the
  /// budget, not fatal). After [maxAttempts] the watch yields
  /// `ai_import.watch_exhausted` and stops — the UI offers a manual
  /// re-arming, it never fabricates a terminal state.
  Stream<Result<AiImportJob>> watch(
    String jobId, {
    ReconciliationScheduler scheduler = const ExponentialBackoffScheduler(),
    int maxAttempts = kMaxJobWatchAttempts,
  }) async* {
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (attempt > 0) await scheduler.tick(attempt - 1);
      final res = await getJobAndCache(jobId);
      // A cancelled subscription ends the generator at the next yield
      // (unsubscribe stop); the only work between yields is the awaited
      // refetch/tick — no background polling survives the screen.
      yield res;
      final job = res.getRight().toNullable();
      if (job != null && isTerminalJobStatus(job.status)) return;
    }
    yield const Left(ProblemError(code: 'ai_import.watch_exhausted'));
  }

  // --- Preview (never cached) --------------------------------------------------

  /// `GET /v1/ai-import/jobs/{id}/preview` → the typed
  /// [AiImportPreviewResponse] (D1). Never cached (regenerable,
  /// potentially large — design §3); a 404 (no preview) surfaces as
  /// `ai_import.preview_missing` copy in the UI.
  ///
  /// A 200 body the generated client cannot deserialize — an unknown
  /// future `kind` the oneOf variants all reject (D1) — is NOT a
  /// transport fault: the server answered, the payload shape is
  /// unrecognized. It surfaces as the stable `ai_import.preview_kind_unknown`
  /// code so the UI renders the explicit degraded card instead of a
  /// guessed rendering or a generic network error.
  Future<Result<AiImportPreviewResponse>> getPreview(String id) async {
    try {
      final response = await api.getHandlersApi().getAiImportPreview(id: id);
      final data = response.data;
      if (data == null) {
        return const Left(ProblemError(code: 'ai_import.dto_invalid'));
      }
      return Right(data);
    } on DioException catch (e) {
      final err = problemErrorFromDio(e);
      if (e.response != null &&
          e.type == DioExceptionType.unknown &&
          err.code.startsWith('transport.')) {
        return const Left(ProblemError(code: 'ai_import.preview_kind_unknown'));
      }
      return Left(err);
    }
  }

  // --- Apply -------------------------------------------------------------------

  /// `POST /v1/ai-import/jobs/{id}/apply` — the explicit write path (D1:
  /// no preview editing exists server-side). Returns the outcome summary
  /// (`applied_count`, `created_days`, `planned_scene_shoots`).
  ///
  /// // AUTHZ-GATE: callers check the season costume-dept membership via
  /// `currentMembershipProvider` BEFORE invoking; denial issues zero calls.
  Future<Result<ApplyAiImportResponse>> apply(
    String jobId,
    ApplyAiImportRequest request,
  ) => run(
    () => api.getHandlersApi().applyAiImport(
      id: jobId,
      applyAiImportRequest: request,
    ),
    dtoInvalidCode: 'ai_import.dto_invalid',
  );

  /// Apply with the ambiguous-timeout reconciliation (task 1.2, design
  /// §1/§2.3): on a timeout-class failure the job is re-read FIRST — a
  /// still-`succeeded` job with a live preview re-enters the bounded
  /// retry (safe: the server-side apply is idempotent, reserve-before-
  /// create, backend issue #338 / PR #351); any other re-read outcome
  /// surfaces as [ApplyBlocked]; a budget exhausted with the outcome
  /// unknown surfaces as [ApplyUnresolved]. Non-timeout failures
  /// (403/409/…) surface immediately — never retried, never re-dispatched
  /// blindly.
  Future<ApplyReconciliation> applyWithReconciliation(
    String jobId,
    ApplyAiImportRequest request, {
    ReconciliationScheduler scheduler = const ExponentialBackoffScheduler(),
    int maxAttempts = kMaxApplyAttempts,
  }) async {
    ProblemError? lastError;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (attempt > 0) await scheduler.tick(attempt - 1);
      final res = await apply(jobId, request);
      final response = res.getRight().toNullable();
      if (response != null) return ApplySucceeded(response);
      final error = res.getLeft().toNullable()!;
      if (!isAmbiguousTimeout(error)) {
        // Definitive failure (403/409/404/validation) — surface it; a
        // re-dispatch would be blind (never allowed, task 1.2).
        return ApplyBlocked(error);
      }
      lastError = error;
      // Re-read the job reality BEFORE any re-dispatch. A failed re-read
      // is itself an unknown outcome — keep consuming the budget; only a
      // successful read with a non-succeeded status is a definitive block.
      final job = await getJobAndCache(jobId);
      final read = job.getRight().toNullable();
      if (read == null) continue;
      if (read.status != JobStatus.succeeded) {
        return ApplyBlocked(
          ProblemError(
            code: 'ai_import.apply_job_not_succeeded',
            detail: read.status.name,
            status: 409,
          ),
        );
      }
    }
    return ApplyUnresolved(
      lastError ?? const ProblemError(code: 'ai_import.apply_unresolved'),
    );
  }
}

/// True when [status] ends a job watch (design D5). `failed` is retryable
/// (the backend keeps retrying with `retries`/`max_retries`) — the watch
/// continues; `dead_letter` and `payload_unavailable` are terminal.
bool isTerminalJobStatus(JobStatus status) =>
    status == JobStatus.succeeded ||
    status == JobStatus.deadLetter ||
    status == JobStatus.payloadUnavailable;

/// True when [error] is an ambiguous-timeout transport failure (the
/// dispatch may or may not have committed server-side). Only these unlock
/// the apply reconciliation path; every other failure is definitive.
bool isAmbiguousTimeout(ProblemError error) => switch (error.code) {
  'transport.connectionTimeout' ||
  'transport.sendTimeout' ||
  'transport.receiveTimeout' => true,
  _ => false,
};
