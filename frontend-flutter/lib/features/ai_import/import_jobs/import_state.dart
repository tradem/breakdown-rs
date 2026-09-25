// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)
// Co-authored-by: deepseek-v4-flash (neuralwatt)

import 'dart:typed_data';

import 'package:breakdown_api/breakdown_api.dart';

import '../../../core/problem_error.dart';
import '../../../data/ai_import_repository.dart';
import '../../../l10n/generated/app_localizations.dart';

/// The submitted document (task 3.1): pasted text (plain) or a picked
/// file (bytes + declared source). PDFs travel as raw bytes.
class AiImportDocument {
  AiImportDocument._({required this.body, required this.source});

  /// Pasted plain text (schedules only — `text/plain`).
  factory AiImportDocument.pasted(String text) =>
      AiImportDocument._(body: text, source: AiScheduleSource.plainText);

  /// A picked CSV file (`text/csv`).
  factory AiImportDocument.csv(String text) =>
      AiImportDocument._(body: text, source: AiScheduleSource.csv);

  /// A picked PDF file (`application/pdf`) — raw bytes.
  factory AiImportDocument.pdf(Uint8List bytes) =>
      AiImportDocument._(body: bytes, source: AiScheduleSource.pdf);

  final Object body;
  final AiScheduleSource source;
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
      'ai_import.forbidden' => l10n.costumeErrorForbidden,
      'ai-import.disabled' => l10n.aiUploadDisabled,
      'ai_import.scope_missing' => l10n.aiUploadScopeMissing,
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
