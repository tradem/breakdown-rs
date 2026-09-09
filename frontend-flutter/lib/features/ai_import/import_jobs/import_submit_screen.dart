// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai_config/ai_config_screen.dart';
import 'import_state.dart';

// Re-exported for callers that need the ack/document shapes (task 3.1
// navigation).
export '../../../data/ai_import_repository.dart' show AiUploadAck;
export 'import_state.dart' show AiImportDocument, AiImportKind;
import 'import_submit_controller.dart';
import 'job_status_screen.dart';

/// The AI-import submission screen (`flutter-ai-import-workflow` task
/// 3.1): kind picker (schedule CSV/PDF/plain, script PDF), paste field or
/// `file_picker` document selection, upload with linear progress, and the
/// duplicate callout branch (200 → "already imported (duplicate)").
///
/// A `ConsumerWidget` for the shell; the paste field is a
/// `ConsumerStatefulWidget` carve-out (ephemeral text state).
class AiImportSubmitScreen extends ConsumerWidget {
  const AiImportSubmitScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kind = ref.watch(aiImportSubmitControllerProvider);
    final controller = ref.read(aiImportSubmitControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI import'),
        actions: [
          IconButton(
            key: const Key('ai-import-open-config'),
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Configure AI import',
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
            segments: const [
              ButtonSegment(
                value: AiImportKind.schedule,
                label: Text('Schedule'),
              ),
              ButtonSegment(value: AiImportKind.script, label: Text('Script')),
            ],
            selected: {kind},
            onSelectionChanged: (selection) =>
                controller.selectKind(selection.first),
          ),
          const SizedBox(height: 16),
          if (kind == AiImportKind.schedule)
            const Text(
              'Schedules: paste the CSV/board text, or pick a CSV or PDF '
              'file.',
            )
          else
            const Text('Scripts: pick a PDF file.'),
          const SizedBox(height: 16),
          if (kind == AiImportKind.schedule) ...[
            const _PasteField(),
            const SizedBox(height: 12),
            const Text('— or pick a file —', textAlign: TextAlign.center),
            const SizedBox(height: 12),
          ],
          _FilePickRow(kind: kind),
          const SizedBox(height: 24),
          const _SubmitButton(),
        ],
      ),
    );
  }
}

/// The paste field (schedules only). The text lives in this widget's
/// controller until submit — read at submit time.
class _PasteField extends ConsumerStatefulWidget {
  const _PasteField();

  @override
  ConsumerState<_PasteField> createState() => _PasteFieldState();
}

class _PasteFieldState extends ConsumerState<_PasteField> {
  final _pasteController = TextEditingController();

  @override
  void dispose() {
    _pasteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    key: const Key('ai-import-paste-field'),
    controller: _pasteController,
    onChanged: (text) => ref.read(pendingPasteProvider.notifier).set(text),
    decoration: const InputDecoration(
      labelText: 'Paste the schedule (CSV or plain text)',
      border: OutlineInputBorder(),
    ),
    maxLines: 8,
  );
}

/// The submit-time paste text (transient controller state, cleared after
/// dispatch; it is a document body, not a secret).
class PendingPaste extends Notifier<String> {
  @override
  String build() => '';

  void set(String text) => state = text;

  void clear() => state = '';
}

final pendingPasteProvider = NotifierProvider<PendingPaste, String>(
  PendingPaste.new,
);

/// File picker row: `file_picker` at point of use only (FOSS; the picked
/// bytes are read immediately into the pending document — nothing is
/// persisted client-side beyond the in-flight upload).
class _FilePickRow extends ConsumerStatefulWidget {
  const _FilePickRow({required this.kind});

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
    // CSV → decoded text; PDF → raw bytes (never UTF-8 re-encoded).
    if (file.extension == 'pdf' || widget.kind == AiImportKind.script) {
      ref
          .read(pendingDocumentProvider.notifier)
          .set(AiImportDocument.pdf(bytes));
    } else {
      ref
          .read(pendingDocumentProvider.notifier)
          .set(AiImportDocument.csv(String.fromCharCodes(bytes)));
    }
  }

  @override
  Widget build(BuildContext context) => Row(
    children: [
      OutlinedButton(
        key: const Key('ai-import-pick-file'),
        onPressed: _pick,
        child: Text(
          widget.kind == AiImportKind.schedule
              ? 'Pick CSV or PDF file'
              : 'Pick PDF file',
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Text(
          _pickedName ?? 'No file picked',
          key: const Key('ai-import-picked-name'),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  );
}

/// The pending document (picked file). Cleared after every dispatch.
class PendingDocument extends Notifier<AiImportDocument?> {
  @override
  AiImportDocument? build() => null;

  void set(AiImportDocument? document) => state = document;
}

final pendingDocumentProvider =
    NotifierProvider<PendingDocument, AiImportDocument?>(PendingDocument.new);

/// The submit dispatch: prefers the picked file, falls back to the paste
/// field. Shows linear progress while the upload is in flight; on a 200
/// duplicate the status screen opens with the duplicate callout; on a 202
/// the plain status screen opens.
class _SubmitButton extends ConsumerStatefulWidget {
  const _SubmitButton();

  @override
  ConsumerState<_SubmitButton> createState() => _SubmitButtonState();
}

class _SubmitButtonState extends ConsumerState<_SubmitButton> {
  bool _busy = false;

  Future<void> _submit() async {
    final document =
        ref.read(pendingDocumentProvider) ??
        (ref.read(pendingPasteProvider).isEmpty
            ? null
            : AiImportDocument.pasted(ref.read(pendingPasteProvider)));
    if (document == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          key: Key('ai-import-document-missing'),
          content: Text('Paste the schedule or pick a file first.'),
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
          .submit(document);
      if (!mounted) return;
      res.match(
        (err) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              key: const Key('ai-import-error-snackbar'),
              content: Text(aiUploadErrorCopy(err)),
            ),
          );
        },
        (ack) {
          ref.read(pendingPasteProvider.notifier).clear();
          ref.read(pendingDocumentProvider.notifier).set(null);
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
        child: const Text('Submit for import'),
      ),
    ],
  );
}
