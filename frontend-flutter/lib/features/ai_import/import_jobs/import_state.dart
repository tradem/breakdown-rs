// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)
// Co-authored-by: deepseek-v4-flash (neuralwatt)
// Co-authored-by: space-bunny-free (opencode-go)

import 'dart:typed_data';

import 'package:breakdown_api/breakdown_api.dart';

import '../../../core/problem_error.dart';
import '../../../data/ai_import_repository.dart';
import '../../../l10n/generated/app_localizations.dart';

/// The submitted document (task 3.1): a picked file (bytes/text plus its
/// declared source). PDFs travel as raw bytes.
class AiImportDocument {
  AiImportDocument._({required this.body, required this.source, this.fileName});

  /// A picked CSV file (`text/csv`).
  factory AiImportDocument.csv(String text, {String? fileName}) =>
      AiImportDocument._(
        body: text,
        source: AiScheduleSource.csv,
        fileName: fileName,
      );

  /// A picked PDF file (`application/pdf`) — raw bytes.
  factory AiImportDocument.pdf(Uint8List bytes, {String? fileName}) =>
      AiImportDocument._(
        body: bytes,
        source: AiScheduleSource.pdf,
        fileName: fileName,
      );

  final Object body;
  final AiScheduleSource source;

  /// The picked file's own name (issue #763), forwarded to the upload as the
  /// percent-encoded `X-Document-Filename` header so the jobs list can show
  /// which document a row belongs to. `null` for a body that never had a file
  /// (pasted text) — no name is invented.
  final String? fileName;
}

/// Which document kind the user is submitting.
enum AiImportKind { schedule, script }

/// Localized client-side copy for an upload failure, keyed on the stable
/// problem `code` (never the server `detail`). The 403 arm matches BOTH the
/// scoped server wire code `ai-import.forbidden` (upload block-scope denial,
/// issue #470) and the client pre-gate deny code `ai_import.forbidden` from
/// `membership_gate.dart` — different provenance, one narrative. The 415 arm
/// keys on the scoped server code `ai-import.unsupported-media-type` (issue
/// #481) AND the client-internal 415 code `ai_import.unsupported_media_type`
/// fabricated by the script pre-gate (a non-PDF source under the script kind
/// is rejected device-side) — same narrative, different provenance. The 413
/// arm stays on the generic `http.payload-too-large`: the shared body-limit
/// extractor rejects an oversized body before the handler runs, so the AI
/// route's wire surface is the generic code.
String aiUploadErrorCopy(AppLocalizations l10n, ProblemError error) =>
    switch (error.code) {
      'http.payload-too-large' => l10n.aiUploadTooLarge,
      'ai-import.unsupported-media-type' ||
      'ai_import.unsupported_media_type' => l10n.aiUploadUnsupported,
      'ai-import.forbidden' ||
      'ai_import.forbidden' => l10n.pieceErrorForbidden,
      'ai-import.disabled' => l10n.aiUploadDisabled,
      'ai_import.scope_missing' => l10n.aiUploadScopeMissing,
      // Issue #771: the server refused a declared season that does not own the
      // active block (and the client refuses the same contradiction locally,
      // with the scoped server code so one narrative covers both provenances).
      'ai-import.scope-mismatch' ||
      'ai_import.scope_mismatch' => l10n.aiImportScopeMismatch,
      // Issue #829: the two target states a block-less import can reach. Both
      // are branchable server codes, rendered as copy — never as an internal
      // error, and never as a retry prompt (retrying cannot change either).
      'ai-import.target-missing' ||
      'ai_import.target_missing' => l10n.aiImportTargetMissing,
      'ai-import.target-immutable' ||
      'ai_import.target_immutable' => l10n.aiImportTargetImmutable,
      'authz.denied' || 'membership.pending' => l10n.aiUploadPermissions,
      _ when error.code.startsWith('transport.') => l10n.aiUploadNetwork,
      _ => l10n.aiUploadGeneric(error.code),
    };

/// Localized copy for a job status (the status matrix, task 3.2). Primary
/// copy is keyed on the status; `last_error` renders as secondary detail
/// only. `failed` is retryable — the copy says "retry scheduled".
String jobStatusCopy(AppLocalizations l10n, JobStatus status) =>
    switch (status) {
      JobStatus.pending => l10n.jobStatusPending,
      JobStatus.running => l10n.jobStatusRunning,
      JobStatus.succeeded => l10n.jobStatusSucceeded,
      JobStatus.failed => l10n.jobStatusFailed,
      JobStatus.deadLetter => l10n.jobStatusDeadLetter,
      JobStatus.payloadUnavailable => l10n.jobStatusPayloadUnavailable,
      // A future backend status the client does not know: honest copy
      // keyed on the stable enum name, never a guessed meaning.
      _ => l10n.jobStatusUnknown(status.name),
    };

/// True when [status] shows the indeterminate progress affordance
/// (pending/running — the backend exposes no percentage and fabricating a
/// determinate value is a dark pattern).
bool jobStatusInProgress(JobStatus status) =>
    status == JobStatus.pending || status == JobStatus.running;

/// True when [status] renders the terminal error card.
bool jobStatusTerminalError(JobStatus status) =>
    status == JobStatus.deadLetter || status == JobStatus.payloadUnavailable;

/// Localized client-side copy for an extraction stage (issue #664). `null`
/// (job carries no progress yet) falls back to the plain running copy the
/// status matrix already provides — never a fabricated stage.
String aiJobStageCopy(AppLocalizations l10n, AiImportStage? stage) =>
    switch (stage) {
      AiImportStage.extractingText => l10n.aiJobStageExtractingText,
      AiImportStage.extracting => l10n.aiJobStageExtracting,
      AiImportStage.merging => l10n.aiJobStageMerging,
      AiImportStage.storingPreview => l10n.aiJobStageStoringPreview,
      // A future backend stage the client does not know: honest copy keyed
      // on the stable enum name, never a guessed meaning.
      _ => l10n.aiJobStageUnknown(stage?.name ?? ''),
    };

/// The LLM provider's own transient failure (issue #822): the ONLY code the
/// LLM chat client emits for HTTP 429/5xx and transport timeout/connect, so it
/// is the single stable signal that attributes a failed attempt to the
/// provider.
///
/// It replaces nothing: `domain.service-unavailable` still covers the mapping
/// DB, the pricing read model, payload storage and the catalog, so folding that
/// generic code into a provider narrative would name the wrong dependency.
const String aiLlmProviderUnavailableCode =
    'ai-import.llm-provider-unavailable';

/// How many CONSECUTIVE provider-attributed attempts make the provider
/// "degraded" rather than merely blipping (issue #822).
///
/// One provider failure is a transient defect of a single attempt and keeps the
/// per-attempt narrative; two in a row is the observed outage shape (three 503s
/// over 17 minutes) and is what the reviewer needs to read as an upstream
/// condition instead of counting identical rows.
const int aiProviderDegradationThreshold = 2;

/// One contiguous run of provider-attributed failures at the head of a job's
/// attempt history (issue #822).
///
/// Derived from the job's OWN history — never from `last_error`, which is
/// free-form log text and not an error identity (AGENTS.md §5). The run is
/// judged newest-first and stops at the first attempt with any other code, so
/// an intervening storage/database failure ends it instead of being absorbed.
class AiProviderDegradation {
  const AiProviderDegradation({
    required this.failedAttempts,
    required this.firstFailureAt,
    required this.lastFailureAt,
    required this.nextAttemptAt,
    required this.retryBudgetSpent,
  });

  /// Attempts in the contiguous provider-attributed run (`>= 2`).
  final int failedAttempts;

  /// The window: when the first and the newest failure of that run were
  /// recorded (server clock, as the attempt rows carry it).
  final DateTime firstFailureAt;
  final DateTime lastFailureAt;

  /// The job's `next_attempt_at` — `null` when the backend schedules none
  /// (or the job is terminal); the caller renders no invented time.
  final DateTime? nextAttemptAt;

  /// True at `dead_letter`: the retry budget is spent and no further attempt is
  /// planned, so no copy may promise a next attempt.
  final bool retryBudgetSpent;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AiProviderDegradation &&
          other.failedAttempts == failedAttempts &&
          other.firstFailureAt == firstFailureAt &&
          other.lastFailureAt == lastFailureAt &&
          other.nextAttemptAt == nextAttemptAt &&
          other.retryBudgetSpent == retryBudgetSpent;

  @override
  int get hashCode => Object.hash(
    failedAttempts,
    firstFailureAt,
    lastFailureAt,
    nextAttemptAt,
    retryBudgetSpent,
  );
}

/// The provider-degraded state of [job], or `null` when it does not apply
/// (issue #822).
///
/// Fires only for a job that can still retry (`failed`) or has spent its budget
/// (`dead_letter`) — a `succeeded` job with past provider failures carries no
/// degraded state, and a `payload_unavailable` job cannot be produced by a
/// provider-attributed run (that status comes from a missing durable payload,
/// which is a storage/not-found classification).
AiProviderDegradation? aiProviderDegradation(AiImportJob job) =>
    aiProviderDegradationOf(
      attempts: job.attempts,
      status: job.status,
      nextAttemptAt: job.nextAttemptAt,
    );

/// The primitive form of [aiProviderDegradation], for the surfaces that read a
/// projected row instead of the wire DTO (the jobs list, issue #822).
///
/// Keeping ONE implementation is the point: a compact row and a status card
/// must never disagree about whether the provider is degraded.
AiProviderDegradation? aiProviderDegradationOf({
  required Iterable<AiImportAttempt>? attempts,
  required JobStatus? status,
  required DateTime? nextAttemptAt,
}) {
  final retryBudgetSpent = status == JobStatus.deadLetter;
  if (status != JobStatus.failed && !retryBudgetSpent) return null;
  final history = attempts?.toList();
  if (history == null || history.length < aiProviderDegradationThreshold) {
    return null;
  }
  var failedAttempts = 0;
  DateTime? newestFailureAt;
  DateTime? oldestFailureAt;
  // Newest first (the wire contract), so a `break` at the first foreign code
  // is exactly "the contiguous run at the head".
  for (final attempt in history) {
    if (attempt.code != aiLlmProviderUnavailableCode) break;
    newestFailureAt ??= attempt.createdAt;
    oldestFailureAt = attempt.createdAt;
    failedAttempts += 1;
  }
  if (failedAttempts < aiProviderDegradationThreshold) return null;
  return AiProviderDegradation(
    failedAttempts: failedAttempts,
    firstFailureAt: oldestFailureAt!,
    lastFailureAt: newestFailureAt!,
    nextAttemptAt: nextAttemptAt,
    retryBudgetSpent: retryBudgetSpent,
  );
}

/// Localized client-side copy for the failure of an AI-import attempt, keyed
/// on the attempt's stable problem `code` (issue #639). The backend
/// `error_summary` is free-form `DomainError` log text and is NEVER used as
/// the error's identity (AGENTS.md §5): only the registry `code` selects the
/// narrative. An absent or unrecognized code degrades to a generic localized
/// message — the generic arm may echo the stable `code` (an identifier, not
/// `detail`), matching `aiUploadGeneric`/`jobWatchGeneric`.
///
/// [retryPossible] is the status guard the issue #822 terminal rule needs: at a
/// terminal status the same transient code must NOT promise "the next attempt
/// may succeed" — the card that renders it can no longer keep that promise.
/// Only the two transient codes have a terminal variant; every other code
/// already speaks about a finished attempt.
String aiJobFailureReason(
  AppLocalizations l10n,
  String? code, {
  bool retryPossible = true,
}) => switch (code) {
  null || '' => l10n.aiJobReasonUnknown,
  'dependency.auth-failed' => l10n.aiJobReasonDependencyAuth,
  aiLlmProviderUnavailableCode =>
    retryPossible
        ? l10n.aiJobReasonLlmProviderUnavailable
        : l10n.aiJobReasonLlmProviderUnavailableTerminal,
  'domain.service-unavailable' =>
    retryPossible
        ? l10n.aiJobReasonServiceUnavailable
        : l10n.aiJobReasonServiceUnavailableTerminal,
  'http.internal-error' => l10n.aiJobReasonInternal,
  _ => l10n.aiJobReasonGeneric(code),
};
