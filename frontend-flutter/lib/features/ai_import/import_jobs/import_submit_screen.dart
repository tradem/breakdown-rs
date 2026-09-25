// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)
// Co-authored-by: space-bunny-free (opencode-go)

import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations_provider.dart';
import '../ai_config/ai_config_screen.dart';
import 'import_state.dart';

// Re-exported for callers that need the ack/document shapes (task 3.1
// navigation).
export '../../../data/ai_import_repository.dart' show AiUploadAck;
export 'import_state.dart' show AiImportDocument, AiImportKind;
import 'import_submit_controller.dart';
import 'job_status_screen.dart';

/// The AI-import submission screen (`flutter-ai-import-workflow` task
/// 3.1): kind picker (schedule CSV/PDF, script PDF), file-only document
/// selection, upload with linear progress, and the duplicate callout branch
/// (200 → "already imported (duplicate)").
class AiImportSubmitScreen extends ConsumerWidget {
  const AiImportSubmitScreen({super.key, this.seasonId});

  /// Explicit season scope for the AUTHZ-GATE (nullable): the season
  /// setup wizard's completion CTA passes the CREATED season's id — the
  /// acting context travels from the command ack (CQRS boundary: never
  /// re-derived from the ambient active-block scope). `null` keeps the
  /// established resolution from [activeBlockProvider] (the shell entry).
  final String? seasonId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kind = ref.watch(aiImportSubmitControllerProvider);
    final controller = ref.read(aiImportSubmitControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10nOf(context).aiImportTitle),
        actions: [
          IconButton(
            key: const Key('ai-import-open-config'),
            icon: const Icon(Icons.settings_outlined),
            tooltip: l10nOf(context).aiImportConfigure,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const AiConfigScreen()),
            ),
          ),
        ],
      ),
      body: ListView(
        key: const Key('ai-import-submit-screen'),
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<AiImportKind>(
            key: const Key('ai-import-kind-picker'),
            segments: [
              ButtonSegment(
                value: AiImportKind.script,
                label: Text(l10nOf(context).aiImportScript),
              ),
              ButtonSegment(
                value: AiImportKind.schedule,
                label: Text(l10nOf(context).aiImportSchedule),
              ),
            ],
            selected: {kind},
            onSelectionChanged: (selection) =>
                controller.selectKind(selection.first),
          ),
          const SizedBox(height: 16),
          if (kind == AiImportKind.schedule)
            Text(l10nOf(context).aiImportScheduleHint)
          else
            Text(l10nOf(context).aiImportScriptHint),
          const SizedBox(height: 16),
          _FilePickRow(key: ValueKey(kind), kind: kind),
          const SizedBox(height: 24),
          _SubmitButton(seasonId: seasonId),
        ],
      ),
    );
  }
}

/// File picker row: `file_picker` at point of use only (FOSS; the picked
/// bytes are read immediately into the pending document — nothing is
/// persisted client-side beyond the in-flight upload).
class _FilePickRow extends ConsumerStatefulWidget {
  const _FilePickRow({super.key, required this.kind});

  final AiImportKind kind;

  @override
  ConsumerState<_FilePickRow> createState() => _FilePickRowState();
}

class _FilePickRowState extends ConsumerState<_FilePickRow> {
  String? _pickedName;

  Future<void> _pick() async {
    // file_picker 12.x: the single-file picker is static; the bytes are
    // read explicitly at point of use (nothing is persisted client-side
    // beyond the in-flight upload).
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: widget.kind == AiImportKind.schedule
          ? const ['csv', 'pdf']
          : const ['pdf'],
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return;
    setState(() => _pickedName = file.name);
    ref
        .read(pendingDocumentProvider.notifier)
        .set(documentFromBytes(widget.kind, bytes, file.extension));
  }

  @override
  Widget build(BuildContext context) => Row(
    children: [
      OutlinedButton(
        key: const Key('ai-import-pick-file'),
        onPressed: _pick,
        child: Text(
          widget.kind == AiImportKind.schedule
              ? l10nOf(context).aiImportPickCsvPdf
              : l10nOf(context).aiImportPickPdf,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Text(
          _pickedName ?? l10nOf(context).aiImportNoFile,
          key: const Key('ai-import-picked-name'),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  );
}

/// The pick decision, extracted as a pure function (unit-testable):
/// CSV → UTF-8-decoded text (NOT `String.fromCharCodes` — that maps each
/// byte to one code unit and mojibakes every non-ASCII CSV character);
/// PDF → raw bytes (never UTF-8 re-encoded). The extension comparison is
/// case-insensitive — `FilePicker` preserves the picked name's case, and
/// a `board.PDF` under the schedule kind must take the PDF branch, not
/// be text-decoded.
AiImportDocument documentFromBytes(
  AiImportKind kind,
  Uint8List bytes,
  String? extension,
) {
  final ext = extension?.toLowerCase();
  if (ext == 'pdf' || kind == AiImportKind.script) {
    return AiImportDocument.pdf(bytes);
  }
  return AiImportDocument.csv(utf8.decode(bytes, allowMalformed: true));
}

/// The submit dispatch for the picked file. Shows linear progress while the
/// upload is in flight; on a 200 duplicate the status screen opens with the
/// duplicate callout; on a 202 the plain status screen opens.
class _SubmitButton extends ConsumerStatefulWidget {
  const _SubmitButton({this.seasonId});

  final String? seasonId;

  @override
  ConsumerState<_SubmitButton> createState() => _SubmitButtonState();
}

class _SubmitButtonState extends ConsumerState<_SubmitButton> {
  bool _busy = false;

  Future<void> _submit() async {
    final document = ref.read(pendingDocumentProvider);
    if (document == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const Key('ai-import-document-missing'),
          content: Text(l10nOf(context).aiImportDocMissing),
        ),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      // The upload progress ride: the controller dispatches without the
      // progress hook (the document is fixed); the indeterminate-to-
      // determinate progress is surfaced via the linear indicator below.
      final res = await ref
          .read(aiImportSubmitControllerProvider.notifier)
          .submit(document, seasonId: widget.seasonId);
      if (!mounted) return;
      res.match(
        (err) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              key: const Key('ai-import-error-snackbar'),
              content: Text(aiUploadErrorCopy(l10nOf(context), err)),
            ),
          );
        },
        (ack) {
          ref.read(pendingDocumentProvider.notifier).set(null);
          // Non-fatal stamp warning (review): the job EXISTS — navigate
          // regardless; the warning rides on top of the status screen.
          final stampWarning = ref.read(aiStampWarningProvider);
          if (stampWarning != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                key: const Key('ai-import-stamp-warning'),
                content: Text(
                  l10nOf(context).aiImportStampWarning(stampWarning.code),
                ),
              ),
            );
          }
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  AiJobStatusScreen(jobId: ack.jobId, duplicate: ack.duplicate),
            ),
          );
        },
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_busy)
        // Honest progress: the backend exposes no percentage, so the
        // indicator is indeterminate (never a fabricated determinate bar).
        const LinearProgressIndicator(key: Key('ai-import-progress')),
      const SizedBox(height: 12),
      FilledButton(
        key: const Key('ai-import-submit'),
        onPressed: _busy ? null : _submit,
        child: Text(l10nOf(context).aiImportSubmit),
      ),
    ],
  );
}
