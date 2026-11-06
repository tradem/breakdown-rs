// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)
// Co-authored-by: omen-alpha (opencode-go)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

import 'dart:convert';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:dio/dio.dart';
import 'package:fpdart/fpdart.dart';

import '../core/problem_error.dart';
import '../src/network/active_block_interceptor.dart';
import '../core/result.dart';
import '../domain/reconciliation/reconciliation_scheduler.dart';
import 'base_repository.dart';
import 'cache/ai_import_jobs_cache_dao.dart';
import 'cache/cache_database.dart';
import 'cache/clock.dart';
import 'sse_event_parser.dart';

/// Bounded attempt budget for the apply reconciliation (task 1.2): an
/// ambiguous-timeout apply re-reads the job first, then retries — never
/// blind re-dispatch (server-side idempotency per backend issue #338 /
/// PR #351 makes the bounded retry safe).
const int kMaxApplyAttempts = 3;

/// Bounded reconnect budget of the SSE job watch (issue #664): each
/// attempt opens one `GET /v1/ai-import/jobs/{id}/events` connection;
/// the first frame is always a fresh snapshot, so a reconnect converges
/// without catch-up polling.
const int kMaxJobWatchAttempts = 30;

/// Bounded budget of **idle** reconnects of the apply-run watch (issue #762).
///
/// The server closes an apply stream that saw no run within
/// `SSE_APPLY_IDLE_TICKS × SSE_APPLY_TICK_SECS` (2 min) — a deliberate bound, so
/// a client that subscribes a moment before its `POST` lands is not answered
/// with an endless connection. Such a close is **not** a failure: nothing was
/// lost, no frame was missed, and the `POST` is still out. Counting it against
/// [kMaxJobWatchAttempts] would let a slow-to-start apply exhaust the failure
/// budget after ~an hour of idle windows and paint a stream error onto a run
/// that is merely early. Idle closes therefore get their own, deliberately
/// generous bound (30 × 2 min ≈ 1 h of idle windows, with the scheduler's
/// backoff on top); the watch still ends when the card unmounts, i.e. when the
/// `POST` returns.
const int kMaxApplyIdleReconnects = 30;

/// Read-idle watchdog of the SSE connection (issue #664, ADR-038 D5):
/// strictly above 2× the server's 30 s `: keep-alive` cadence, so a silent
/// middlebox/NAT drop (half-open socket) is detected and triggers the
/// bounded `Last-Event-ID` reconnect instead of hanging the watch.
const Duration kSseReceiveTimeout = Duration(seconds: 65);

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

/// The wire header carrying the picked document's name (issue #763).
const String kDocumentFileNameHeader = 'X-Document-Filename';

/// The wire header carrying the season the client resolved as the import
/// target (issue #771).
///
/// The write target stays the ambient `X-Active-Block` header. This declaration
/// exists so a contradiction (`the screen shows season B, the request carries
/// season A's block`) is refused by the server with 409
/// `ai-import.scope-mismatch` instead of silently importing into the wrong
/// season — the reported defect. A raw-body upload cannot carry it in the body
/// (the body IS the document), so it travels as a header like the name.
const String kDeclaredSeasonHeader = 'X-Declared-Season';

/// Percent-encodes a file name for [kDocumentFileNameHeader].
///
/// HTTP header values are ASCII, so a UTF-8 name (`Erlösung Skript.pdf`) must
/// be escaped; the server percent-decodes it before sanitizing. Every byte
/// outside the RFC 3986 unreserved set is encoded, which keeps the value free
/// of the separators, quotes and whitespace a header must not carry.
String encodeDocumentFileName(String name) {
  final buffer = StringBuffer();
  for (final byte in utf8.encode(name)) {
    final isUnreserved =
        (byte >= 0x41 && byte <= 0x5a) || // A-Z
        (byte >= 0x61 && byte <= 0x7a) || // a-z
        (byte >= 0x30 && byte <= 0x39) || // 0-9
        byte == 0x2d || // -
        byte == 0x2e || // .
        byte == 0x5f || // _
        byte == 0x7e; // ~
    buffer.write(
      isUnreserved
          ? String.fromCharCode(byte)
          : '%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}',
    );
  }
  return buffer.toString();
}

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

/// The dispatch was refused because **another run of this job** owns the
/// progress slot (`409 ai-import.apply-in-flight`, issues #800/#805).
///
/// Not a failure and not an unknown outcome: the block is *named*, so the UI
/// can say which one it is instead of rendering the generic unresolved card.
/// [age] is how long the owning run had been silent when the server refused
/// (the S1 `apply_run_age_seconds` extension; `null` when that run published
/// nothing yet), and [staleAfter] is the server's own window
/// (`stale_after_seconds`) — the client never mirrors it.
///
/// `age >= staleAfter` means the run is **dead by the server's predicate**:
/// the next apply steals the slot. That is the user's call, so this outcome
/// never re-dispatches by itself.
class ApplyInFlight extends ApplyReconciliation {
  const ApplyInFlight(
    this.error, {
    required this.age,
    required this.staleAfter,
  });

  final ProblemError error;

  /// The owning run's silence at the moment of the refusal; `null` when it
  /// has published no progress yet (nothing to age — never invented as zero).
  final Duration? age;

  /// The window after which the server lets the next claim steal the slot.
  final Duration staleAfter;
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
  /// [fileName] is the picked document's own name (issue #763) and travels as
  /// the percent-encoded UTF-8 `X-Document-Filename` header — never inside the
  /// body, which stays the document itself, and never as a guess: a pasted
  /// body has no name and sends no header.
  ///
  /// // AUTHZ-GATE: callers check the season piece-dept membership via
  /// `currentMembershipProvider` BEFORE invoking; denial issues zero calls.
  Future<Result<AiUploadAck>> uploadSchedule({
    required Object body,
    required AiScheduleSource source,
    String? fileName,
    String? declaredSeasonId,
    bool sendActiveBlock = true,
    void Function(int count, int total)? onSendProgress,
  }) => _upload(
    '/v1/ai-import/schedules',
    body,
    scheduleContentType(source),
    fileName,
    declaredSeasonId,
    sendActiveBlock,
    onSendProgress,
  );

  /// `POST /v1/ai-import/scripts` — raw bytes body, `application/pdf` only
  /// (per the content-type contract; a non-PDF script upload is a client
  /// bug, not a 415 retry case).
  ///
  /// [fileName] carries the picked document's name for the same reason as
  /// [uploadSchedule] (issue #763).
  ///
  /// // AUTHZ-GATE: same membership pre-gate as the schedule upload.
  Future<Result<AiUploadAck>> uploadScript({
    required Object body,
    String? fileName,
    String? declaredSeasonId,
    bool sendActiveBlock = true,
    void Function(int count, int total)? onSendProgress,
  }) => _upload(
    '/v1/ai-import/scripts',
    body,
    kScriptContentType,
    fileName,
    declaredSeasonId,
    sendActiveBlock,
    onSendProgress,
  );

  /// Raw-body upload via the client Dio. Never throws; maps every error to
  /// a [ProblemError] keyed on the backend problem `code` (413/415/403/404
  /// all arrive as RFC 9457 problem+json — AGENTS.md §5). [body] is a
  /// [String] (UTF-8 text) or [Uint8List] (raw bytes, e.g. PDFs).
  ///
  /// [declaredSeasonId] is the season the UI resolved as the target (issue
  /// #771) and travels as [`kDeclaredSeasonHeader`]: the server refuses a
  /// declared season that does not own the active block, so this request can
  /// never write into a season the user was not shown. `null` sends no
  /// declaration (the header's own degradation path).
  Future<Result<AiUploadAck>> _upload(
    String path,
    Object body,
    String contentType,
    String? fileName,
    String? declaredSeasonId,
    bool sendActiveBlock,
    void Function(int count, int total)? onSendProgress,
  ) async {
    try {
      final response = await api.dio.post<String>(
        path,
        data: body,
        options: Options(
          contentType: contentType,
          // Issue #763: the document's name rides along as a header. Only
          // `Content-Type` is overridden by `Options.contentType`; a caller
          // header set here survives, so the declared CSV/PDF media type
          // contract above is untouched. Issue #771 adds the declared season
          // to the same map — both are metadata, never part of the body.
          headers: {
            if (fileName != null)
              kDocumentFileNameHeader: encodeDocumentFileName(fileName),
            if (declaredSeasonId != null && declaredSeasonId.isNotEmpty)
              kDeclaredSeasonHeader: declaredSeasonId,
          },
          // Both 200 (duplicate) and 202 (enqueued) are acknowledged —
          // the branch happens on the status code below.
          validateStatus: (status) => status == 200 || status == 202,
          // Issue #829: a block-less upload sends the declaration only. The
          // ambient scope header is suppressed per request — an upload that
          // carries a block would silently be a DIFFERENT import than the one
          // the card showed.
          extra: sendActiveBlock ? null : {kNoActiveBlockExtra: true},
        ),
        onSendProgress: onSendProgress,
      );
      final jobId = _decodeJobId(response.data);
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

  /// Normalizes the upload acknowledgement body into a bare job id.
  ///
  /// The backend answers `POST /v1/ai-import/{scripts,schedules}` with
  /// `Json(id)` — a JSON *string* literal, wire body `"<uuid>"`. Dio’s
  /// default transformer does NOT strip the quotes for a `post<String>`
  /// call: verified against dio 5.11, `response.data` still arrives as
  /// `"01a0…"` (38 characters for a 36-character UUID), because the
  /// generic type is a static cast only and never drives the decode.
  ///
  /// A quoted id is then interpolated into the next path segment
  /// (`/v1/ai-import/jobs/%22<uuid>%22`), the backend's
  /// `Path<AiImportJobId>` extractor rejects it, and every follow-up
  /// poll/preview/apply fails with `400 http.bad-path-param` (issue: AI
  /// import unusable on device). So the JSON literal is decoded here,
  /// explicitly, instead of trusting the transformer.
  ///
  /// A body that is already a bare id (no surrounding quotes) is passed
  /// through unchanged. A body that *starts* a JSON string but does not
  /// parse as one is fail-closed: it yields the empty string so the caller
  /// reports `ai_import.dto_invalid` rather than sending a malformed id
  /// over the wire.
  static String _decodeJobId(String? raw) {
    final trimmed = raw?.trim() ?? '';
    if (trimmed.isEmpty) return '';
    if (!trimmed.startsWith('"')) return trimmed;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is String) return decoded.trim();
    } on FormatException {
      return '';
    }
    return '';
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
      // Cache write is best-effort (the cache is a local optimization —
      // AGENTS.md §8): a locked DB or full disk must NOT discard a
      // successful network read. The fetched job stays authoritative;
      // the next refresh rewrites the row.
      try {
        await cache.upsertAll([response.job], clock.now());
      } on Object {
        // Best-effort: keep the fetched job.
      }
      return Right(response.job);
    });
  }

  /// `PUT /v1/ai-import/jobs/{id}/target` — attach the write target of a
  /// block-less job (issue #829).
  ///
  /// Set-once on the server: repeating the attached block is an idempotent
  /// `200`, a different block answers the registered `409
  /// ai-import.target-immutable` (with `existing_block_id` or `applied: true`),
  /// which the caller renders as copy — never as an internal error. The
  /// response is the updated job, so the caller learns the new block id AND the
  /// target number from one round-trip; `getJobAndCache` would need a second
  /// read to say the same.
  ///
  /// Writing the returned job through the cache here is what makes the
  /// in-preview episode creation work right after an attach: it reads the job's
  /// block anchor from the cached row (`aiJobBlockInfo`), which the upload of a
  /// block-less job left empty.
  ///
  /// // AUTHZ-GATE: callers resolve the season membership via
  /// `currentMembershipProvider` BEFORE invoking; the server re-checks it on the
  /// job's target season and answers `403 ai-import.forbidden`.
  Future<Result<AiImportJob>> attachTarget(
    String jobId, {
    required String blockId,
    Clock clock = Clock.system,
  }) async {
    final attached = await run(
      () => api.getHandlersApi().putAiImportJobTarget(
        id: jobId,
        aiImportTargetRequest: AiImportTargetRequest(
          (b) => b..blockId = blockId,
        ),
      ),
      dtoInvalidCode: 'ai_import.dto_invalid',
    );
    return attached.match((err) async => Left<ProblemError, AiImportJob>(err), (
      response,
    ) async {
      try {
        await cache.upsertAll([response.job], clock.now());
      } on Object {
        // Best-effort, exactly like `getJobAndCache`: a cache fault must never
        // discard a write the server already committed.
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
        // Best-effort cache write (see getJobAndCache): a local storage
        // fault never masks a successful list fetch.
        try {
          await cache.upsertAll(jobs, clock.now());
        } on Object {
          // Best-effort: keep the fetched rows.
        }
        return Right(jobs);
      },
    );
  }

  /// Pure Drift read of the caller's cached job rows, newest-first by
  /// server `updatedAt` (mirrors the list route's ordering).
  ///
  /// Identity-scoped: the read is filtered by the caller's `sub` — a
  /// failed/missed sign-out reset can never leak a previous user's job
  /// rows (`dedupKey`, `documentDigest`, `sourceHandle`) into the next
  /// session. The cache is a local optimization only — it never holds
  /// state the server does not also hold (AGENTS.md §8).
  Future<Result<List<AiImportJobCacheRow>>> readCached(String sub) async {
    try {
      return Right(await cache.readAll(sub));
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

  /// `DELETE /v1/ai-import/jobs/{id}` (backend issue #671): deletes a
  /// **terminal** job (204). The server refuses non-terminal rows with the
  /// registered 409 `ai-import.job-not-deletable` and foreign ones with
  /// 403 `ai-import.forbidden`; the surface is server-owned, the client
  /// only branches on the stable `code`. On success the server freed the
  /// job's dedup key (the same document can be re-uploaded) and removed
  /// its payload objects; the local cache row is evicted best-effort (a
  /// locked DB must not discard a successful command acknowledgement —
  /// the next list refetch converges the cache).
  Future<Result<void>> deleteJob(String id) async {
    try {
      // A 204 has no body: `null` data is success, never `dto.invalid` —
      // same shape as the photo delete.
      await api.getHandlersApi().deleteAiImportJob(id: id);
    } on DioException catch (e) {
      return Left(problemErrorFromDio(e));
    }
    try {
      await cache.deleteById(id);
    } on Object {
      // Best-effort: keep the server acknowledgement.
    }
    return const Right<ProblemError, void>(null);
  }

  /// Watches a job's live state over the push-based SSE stream (issue
  /// #664, ADR-038 D5/D6): `GET /v1/ai-import/jobs/{id}/events` on the
  /// existing pinned-CA Dio client ([`api.dio`] — ADR-024/ADR-032), with
  /// `ResponseType.stream` and a [kSseReceiveTimeout] read-idle watchdog.
  /// NO periodic polling: the server pushes every fenced status/progress
  /// write, and the first frame on every connect/reconnect is a full
  /// snapshot, so no catch-up poll exists anywhere in the loop.
  ///
  /// Reconnect contract: a transient drop or read-idle timeout while the
  /// watch is still alive reconnects via the bounded [scheduler] with the
  /// last received SSE `id` in the `Last-Event-ID` header. After
  /// [maxAttempts] failed opens the watch yields `ai_import.watch_exhausted`
  /// and stops — the UI offers a manual re-arm, it never fabricates state.
  ///
  /// Foreground-only (battery contract, D5): the watching screen's provider
  /// disposal cancels the subscription, which cancels the Dio request
  /// token and closes the HTTP stream — no background wake-ups. Received
  /// job snapshots upsert into Drift (same success-only cache writes as
  /// the snapshot GET).
  Stream<Result<AiImportJob>> watch(
    String jobId, {
    ReconciliationScheduler scheduler = const ExponentialBackoffScheduler(),
    int maxAttempts = kMaxJobWatchAttempts,
    Duration receiveTimeout = kSseReceiveTimeout,
    CancelToken? cancelToken,
  }) async* {
    String? lastEventId;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (attempt > 0) await scheduler.tick(attempt - 1);
      Response<ResponseBody> response;
      try {
        response = await api.dio.get<ResponseBody>(
          '/v1/ai-import/jobs/$jobId/events',
          options: Options(
            // ADR-038 D6: stream the SSE body over the SAME pinned-CA Dio
            // client (SecurityContext withTrustedRoots: false) — never a
            // third-party SSE package with its own unpinned HttpClient.
            responseType: ResponseType.stream,
            // Read-idle watchdog (> 2× the 30 s keep-alive): a silent
            // middlebox drop surfaces as a receiveTimeout DioException and
            // reconnects with Last-Event-ID instead of hanging.
            receiveTimeout: receiveTimeout,
            headers: {
              'Accept': 'text/event-stream',
              'Last-Event-ID': ?lastEventId,
            },
          ),
          cancelToken: cancelToken,
        );
      } on DioException catch (e) {
        // Definitive open failures cannot succeed on retry: 403
        // `ai-import.forbidden`, 404 `ai-import.not-found`, and 404
        // `ai-import.disabled` (the feature gate) are deterministic answers
        // for this identity/job — yield the error and STOP instead of
        // burning the reconnect budget on 30 futile backed-off opens.
        final status = e.response?.statusCode;
        if (status == 403 || status == 404) {
          yield Left(problemErrorFromDio(e));
          return;
        }
        // Transient open failure (5xx/timeout/network): surface it, then
        // reconnect within the bounded budget — the first frame of the
        // next attempt is a fresh snapshot, so nothing is missed.
        yield Left(problemErrorFromDio(e));
        continue;
      }
      var terminal = false;
      try {
        final parser = SseEventParser();
        final lines = response.data!.stream
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter());
        await for (final line in lines) {
          final event = parser.addLine(line);
          // `: keep-alive` comments and frame-interior lines yield null.
          if (event == null) continue;
          if (event.id != null) lastEventId = event.id;
          if (event.event != 'job' || event.data.isEmpty) continue;
          final job = _decodeJobFrame(event.data);
          if (job == null) {
            yield const Left(ProblemError(code: 'ai_import.dto_invalid'));
            continue;
          }
          // Success-only cache write, same discipline as getJobAndCache.
          try {
            await cache.upsertAll([job], Clock.system.now());
          } on Object {
            // Best-effort: keep the pushed job.
          }
          yield Right(job);
          if (isTerminalJobStatus(job.status)) terminal = true;
        }
      } on DioException catch (e) {
        // Mid-stream failure (read-idle timeout / connection reset):
        // surface it, then reconnect with Last-Event-ID.
        yield Left(problemErrorFromDio(e));
      }
      if (terminal) {
        // The server closes the stream after the terminal frame; no
        // reconnect — the watch is done.
        return;
      }
      // Connection ended without a terminal frame (drop / transaction
      // limit): loop to the bounded reconnect.
    }
    yield const Left(ProblemError(code: 'ai_import.watch_exhausted'));
  }

  /// Watches an **apply run**'s progress (issue #762):
  /// `GET /v1/ai-import/jobs/{id}/apply-events`.
  ///
  /// A second stream is necessary, not a convenience: an apply is a `POST`
  /// against a job that is already `succeeded`, and the job stream closes on
  /// the terminal frame — so the apply's own progress cannot ride it.
  ///
  /// Contract, mirroring [watch]:
  /// * same pinned-CA Dio client, `ResponseType.stream`, the read-idle
  ///   watchdog and the SSE parser — no third-party SSE package, no polling;
  /// * the first frame of every connect is the current run snapshot;
  /// * a transient drop reconnects through the bounded [scheduler];
  /// * a frame whose `apply_progress` is `null` is the run's **end**: it
  ///   yields a final `Right(null)` and the loop stops (the server closed the
  ///   stream, nothing is reconnecting);
  /// * an **idle close** (the server ended a connection that delivered no
  ///   frame, i.e. no run had started yet) reconnects without consuming the
  ///   failure budget — see [kMaxApplyIdleReconnects] — because nothing failed
  ///   and the `POST` is still out;
  /// * `403`/`404` are definitive and stop immediately.
  ///
  /// Nothing is cached: an apply run is transient state, and a stale
  /// "applying 12/57" in Drift would outlive its run.
  Stream<Result<ApplyProgress?>> watchApplyProgress(
    String jobId, {
    ReconciliationScheduler scheduler = const ExponentialBackoffScheduler(),
    int maxAttempts = kMaxJobWatchAttempts,
    int maxIdleReconnects = kMaxApplyIdleReconnects,
    Duration receiveTimeout = kSseReceiveTimeout,
    CancelToken? cancelToken,
  }) async* {
    String? lastEventId;
    // Two separate budgets: failures (a drop, a transport error, a close that
    // carried frames but no end signal) exhaust [maxAttempts]; idle closes —
    // the server bounding a connection that had nothing to report — exhaust
    // [maxIdleReconnects] only, so a run that is merely slow to start is never
    // reported as a broken watch (CodeRabbit review of PR #798).
    var failures = 0;
    var idle = 0;
    while (failures < maxAttempts && idle < maxIdleReconnects) {
      if (failures + idle > 0) await scheduler.tick(failures + idle - 1);
      Response<ResponseBody> response;
      try {
        response = await api.dio.get<ResponseBody>(
          '/v1/ai-import/jobs/$jobId/apply-events',
          options: Options(
            responseType: ResponseType.stream,
            receiveTimeout: receiveTimeout,
            headers: {
              'Accept': 'text/event-stream',
              'Last-Event-ID': ?lastEventId,
            },
          ),
          cancelToken: cancelToken,
        );
      } on DioException catch (e) {
        final status = e.response?.statusCode;
        if (status == 403 || status == 404) {
          yield Left(problemErrorFromDio(e));
          return;
        }
        yield Left(problemErrorFromDio(e));
        failures++;
        continue;
      }
      var finished = false;
      // Did THIS connection deliver any apply frame? A connection that carried
      // none was an idle window (the server closes those on purpose), which is
      // not a failure.
      var sawFrame = false;
      try {
        final parser = SseEventParser();
        final lines = response.data!.stream
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter());
        await for (final line in lines) {
          final event = parser.addLine(line);
          // `: keep-alive` comments and frame-interior lines yield null.
          if (event == null) continue;
          if (event.id != null) lastEventId = event.id;
          if (event.event != 'apply' || event.data.isEmpty) continue;
          sawFrame = true;
          final decoded = _decodeApplyProgressFrame(event.data);
          final progress = decoded.fold<ApplyProgress?>((_) => null, (p) => p);
          // A malformed body must not look like "no run": yield the error and
          // keep the stream open (the next frame may be well-formed).
          if (!decoded.isRight()) {
            yield decoded;
            continue;
          }
          yield Right(progress);
          if (progress == null) finished = true;
        }
      } on DioException catch (e) {
        yield Left(problemErrorFromDio(e));
        failures++;
        continue;
      }
      if (finished) {
        // The run ended (or its payload went stale server-side); the server
        // closed the stream — no reconnect.
        return;
      }
      if (!sawFrame) {
        // Idle close: no run had started within the server's idle window. Not
        // a failure — keep waiting for the run the POST is about to start.
        idle++;
        continue;
      }
      // The stream ended without an end frame (drop / process restart):
      // reconnect within the bounded budget; the next snapshot re-states the
      // run.
      failures++;
    }
    yield const Left(ProblemError(code: 'ai_import.watch_exhausted'));
  }

  /// Decodes one `event: apply` SSE data payload (issue #762).
  ///
  /// The frame is `{ "job_id": …, "apply_progress": … }`, and only the nested
  /// progress is needed: the stream is per-job already. Decoding it by hand
  /// keeps a nested `null` distinguishable from a malformed body — the former
  /// is the run's end signal, the latter is `ai_import.dto_invalid`. Same
  /// never-throw discipline as [_decodeJobFrame].
  static Result<ApplyProgress?> _decodeApplyProgressFrame(String data) {
    const malformed = Left<ProblemError, ApplyProgress?>(
      ProblemError(code: 'ai_import.dto_invalid'),
    );
    try {
      final decoded = jsonDecode(data);
      if (decoded is! Map<String, dynamic>) return malformed;
      if (!decoded.containsKey('apply_progress')) return malformed;
      final raw = decoded['apply_progress'];
      if (raw == null) return const Right<ProblemError, ApplyProgress?>(null);
      final progress = standardSerializers.deserializeWith(
        ApplyProgress.serializer,
        raw,
      );
      if (progress == null) return malformed;
      return Right<ProblemError, ApplyProgress?>(progress);
    } on Object {
      return malformed;
    }
  }

  /// Decodes one `event: job` SSE data payload into the generated
  /// [AiImportJob]. A body the serializers reject (unknown future field
  /// shape) is a malformed frame — surfaced as
  /// `ai_import.dto_invalid`, never thrown.
  ///
  /// Uses [standardSerializers] (with `StandardJsonPlugin`), matching the
  /// generated client's decode path: the plugin maps JSON objects to the
  /// pair-list representation the custom built_value serializers expect.
  /// The bare `serializers` instance lacks the plugin and rejects every
  /// frame (map ≠ Iterable cast) — the root cause of the app-side
  /// `ai_import.dto_invalid` on every live job watch.
  static AiImportJob? _decodeJobFrame(String data) {
    try {
      final decoded = jsonDecode(data);
      return standardSerializers
          .deserializeWith(AiImportJobResponse.serializer, decoded)
          ?.job;
    } on Object {
      return null;
    }
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
  /// // AUTHZ-GATE: callers check the season piece-dept membership via
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
  ///
  /// [onAttempt] fires with the 1-based index of every attempt after the
  /// first, **before** that attempt is dispatched: a retry is a NEW
  /// server-side run (the first one's stream has already seen its end
  /// frame), so a live progress view has to re-open its watch to follow it.
  ///
  /// [clock] measures the LOCAL wait after a refusal that named its blocking
  /// run (issue #805 review): the bounded budget may not run past the server's
  /// own window, or a retry would steal an abandoned claim without the user
  /// asking for it. Injected so the bound is testable without waiting.
  Future<ApplyReconciliation> applyWithReconciliation(
    String jobId,
    ApplyAiImportRequest request, {
    ReconciliationScheduler scheduler = const ExponentialBackoffScheduler(),
    int maxAttempts = kMaxApplyAttempts,
    void Function(int attempt)? onAttempt,
    Clock clock = Clock.system,
  }) async {
    ProblemError? lastError;
    // The last refusal that named its owning run (issue #805). A budget that
    // ends on one of these is NOT an unknown outcome: the client knows exactly
    // what blocks it, and who can clear it.
    ApplyInFlight? inFlight;
    // When that refusal was received: the local wait is measured from here, so
    // the loop can stop BEFORE a retry would cross the server's window.
    DateTime? refusedAt;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (attempt > 0) {
        await scheduler.tick(attempt - 1);
        // The WAIT itself can cross the server's window (issue #805 review), so
        // this is checked after the tick and immediately before the dispatch it
        // precedes: waiting long enough is not consent, and a dispatch past the
        // window would be accepted and steal the abandoned claim. `onAttempt` is
        // deliberately not called for a dispatch that never happens (it re-arms
        // the live progress stream). A refusal whose owner published nothing
        // carries no age to age, so this bound cannot apply to it (see
        // [ApplyInFlightWindow.age]); that state has its own escape instead.
        final blocked = inFlight;
        final knownAge = blocked?.age;
        if (blocked != null &&
            refusedAt != null &&
            knownAge != null &&
            knownAge + clock.now().difference(refusedAt) > blocked.staleAfter) {
          return blocked;
        }
        onAttempt?.call(attempt);
      }
      final res = await apply(jobId, request);
      final response = res.getRight().toNullable();
      if (response != null) return ApplySucceeded(response);
      final error = res.getLeft().toNullable()!;
      if (isApplyInFlight(error)) {
        // Issue #800: another run of this job owns the progress slot, so the
        // server refused this dispatch with `409 ai-import.apply-in-flight`.
        // That is not a failure — it is this client's own earlier POST still
        // running (the ambiguous-timeout retry legitimately lands here) or a
        // second device.
        final window = applyInFlightWindow(error);
        final age = window?.age;
        if (window != null && age != null && age > window.staleAfter) {
          // Issue #805: the owning run has been silent for longer than the
          // server's own staleness window, so the server itself considers the
          // payload abandoned and the next claim would steal the slot. Stop
          // consuming the budget: the takeover is a USER decision (the run may
          // be this person's other device, and a blind automatic steal is
          // exactly what the single-flight contract forbids), so the caller
          // gets the classification and offers the explicit re-run.
          //
          // Strictly `>`: the server's predicate is `payload.updated_at <
          // now - STALE_AFTER`, so at exactly the window the claim still refuses
          // and the run is live. `>=` would claim an abandonment the server does
          // not act on.
          return ApplyInFlight(error, age: age, staleAfter: window.staleAfter);
        }
        // A live run (or one with nothing published to age) keeps the bounded
        // budget: once it ends, the next claim goes through and this client's
        // own apply lands. The refusal is remembered so a budget that ends
        // here is reported as "a run is live", never as "outcome unknown".
        lastError = error;
        if (window != null) {
          inFlight = ApplyInFlight(
            error,
            age: window.age,
            staleAfter: window.staleAfter,
          );
          refusedAt = clock.now();
        }
        continue;
      }
      if (!isAmbiguousTimeout(error)) {
        // Definitive failure (403/409/404/validation) — surface it; a
        // re-dispatch would be blind (never allowed, task 1.2).
        return ApplyBlocked(error);
      }
      lastError = error;
      // Issue #805 review: an ambiguous timeout makes the outcome UNKNOWN again,
      // so the earlier refusal no longer describes what blocks this job — a
      // resolved run may have finished, or the dispatch may even have landed.
      // Dropping it keeps the final report honest: a budget that ends on an
      // unknown outcome is `ApplyUnresolved`, not a live-run card with a stale
      // takeover action.
      inFlight = null;
      refusedAt = null;
      // Re-read the job reality BEFORE any re-dispatch. A failed re-read
      // is itself an unknown outcome — keep consuming the budget; only a
      // successful read with a non-succeeded status is a definitive block.
      final job = await getJobAndCache(jobId, clock: clock);
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
    return inFlight ??
        ApplyUnresolved(
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

/// True when the server refused an apply because a **live run** already owns
/// the job's progress slot (issue #800, `409 ai-import.apply-in-flight`).
///
/// A wait, not a failure: the apply is single-flight server-side, and the
/// legitimate way to meet that 409 is the reconciliation retry of an
/// ambiguous timeout — the first POST is still running. The caller keeps its
/// budget and follows the live run's stream instead of rendering the blocking
/// apply-error narrative.
bool isApplyInFlight(ProblemError error) =>
    error.code == 'ai-import.apply-in-flight';

/// The facts a `409 ai-import.apply-in-flight` carries about the run that
/// blocks the dispatch (issue #805, S1 extensions of the registered code).
class ApplyInFlightWindow {
  const ApplyInFlightWindow({required this.age, required this.staleAfter});

  /// How long the owning run had been silent when the server refused, as the
  /// SERVER measured it. `null` when that run has published no progress yet —
  /// no age exists, and inventing one would claim a liveness the server did
  /// not report.
  final Duration? age;

  /// The server's own staleness window (`ApplyProgress::STALE_AFTER`): after
  /// this much silence the server's claim lets the next apply steal the slot.
  final Duration staleAfter;
}

/// Parses [ApplyInFlightWindow] from a refusal, or `null` when [error] is a
/// different code **or** a pre-#805 server that names no window.
///
/// A server that sends no window gets the pre-#805 behaviour from the caller
/// (bounded waiting, generic unresolved copy): the client never guesses a
/// policy the server did not state, and it never mirrors the constant.
ApplyInFlightWindow? applyInFlightWindow(ProblemError error) {
  if (!isApplyInFlight(error)) return null;
  final extensions = error.extensions;
  if (extensions == null) return null;
  final seconds = extensions['stale_after_seconds'];
  if (seconds is! num || seconds <= 0) return null;
  final ageSeconds = extensions['apply_run_age_seconds'];
  return ApplyInFlightWindow(
    age: ageSeconds is num && ageSeconds >= 0
        ? Duration(seconds: ageSeconds.toInt())
        : null,
    staleAfter: Duration(seconds: seconds.toInt()),
  );
}
