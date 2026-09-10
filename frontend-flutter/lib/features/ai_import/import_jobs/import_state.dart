// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

import 'dart:typed_data';

import 'package:breakdown_api/breakdown_api.dart';

import '../../../core/problem_error.dart';
import '../../../data/ai_import_repository.dart';

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
/// problem `code` (never the server `detail`).
String aiUploadErrorCopy(ProblemError error) => switch (error.code) {
  'ai_import.payload_too_large' => 'The document is too large for AI import.',
  'ai_import.unsupported_media_type' =>
    'This file type is not supported for the selected kind.',
  'ai_import.forbidden' => 'You need an active costume role in this season.',
  'ai_import.disabled' => 'AI import is not enabled on this backend.',
  'ai_import.scope_missing' =>
    'Open a production block first — AI import is block-scoped.',
  'authz.denied' || 'membership.pending' =>
    'Your permissions are still loading — try again in a moment.',
  _ when error.code.startsWith('transport.') =>
    'Network problem — the document was not submitted. Try again.',
  _ => 'The document could not be submitted (${error.code}).',
};

/// Localized copy for a job status (the status matrix, task 3.2). Primary
/// copy is keyed on the status; `last_error` renders as secondary detail
/// only. `failed` is retryable — the copy says "retry scheduled".
String jobStatusCopy(JobStatus status) => switch (status) {
  JobStatus.pending => 'Queued — the backend picked it up.',
  JobStatus.running => 'Processing your document…',
  JobStatus.succeeded => 'Import preview ready.',
  JobStatus.failed => 'Failed — a retry is scheduled.',
  JobStatus.deadLetter => 'Processing gave up after repeated failures.',
  JobStatus.payloadUnavailable =>
    'The extracted data is no longer available on the server.',
  // A future backend status the client does not know: honest copy keyed
  // on the stable enum name, never a guessed meaning.
  _ => 'Status unknown (${status.name}).',
};

/// True when [status] shows the indeterminate progress affordance
/// (pending/running — the backend exposes no percentage and fabricating a
/// determinate value is a dark pattern).
bool jobStatusInProgress(JobStatus status) =>
    status == JobStatus.pending || status == JobStatus.running;

/// True when [status] renders the terminal error card.
bool jobStatusTerminalError(JobStatus status) =>
    status == JobStatus.deadLetter || status == JobStatus.payloadUnavailable;
