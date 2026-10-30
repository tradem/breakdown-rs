// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)
// Co-authored-by: space-bunny-free (opencode-go)
// Co-authored-by: glm-5.3-flash (opencode-go)

import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/active_block.dart';
import '../../../l10n/app_localizations_provider.dart';
import '../../blocks/active_block_gate.dart';
import '../../blocks/blocks_controller.dart';
import '../clippy/clippy_trigger.dart';
import '../clippy/karl_kleiderbuegel_overlay.dart';
import '../ai_config/ai_config_screen.dart';
import 'import_state.dart';
import 'import_target.dart';
import '../naming_line.dart';

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
    // Issue #771: the target is resolved DELIBERATELY, from the one season
    // context the dispatch will also read — never from the ambient scope
    // alone. `null` means the screen has no season at all (no explicit season
    // from the wizard CTA and no ambient scope): the import then has no
    // target and the submit affordance stays disabled.
    final targetSeasonId = ref.watch(aiImportSeasonContextProvider(seasonId));
    final resolution = targetSeasonId == null
        ? null
        : ref.watch(blockScopeResolutionProvider(targetSeasonId));
    final target = aiImportResolvedScope(resolution);

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
      // Karl Kleiderbügel (issue #516): the submit screen is always idle-flow
      // (the upload progress is a dialog-free inline row; job lifecycle
      // reactions live on the jobs/status screens).
      body: KarlKleiderbuegelOverlay(
        flowState: ClippyFlowState.idle,
        child: ListView(
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
            const SizedBox(height: 16),
            // Persistent disclosure card (EU AI Act Art. 50, issue #538):
            // the point of AI interaction names itself BEFORE the submit
            // action, at scroll position above the button — never skippable
            // content below the fold.
            _DisclosureCard(),
            const SizedBox(height: 12),
            // Issue #771: the visible write target. Sits directly above the
            // submit action, next to the disclosure, because it is the one
            // fact that decides where every imported row lands.
            _ImportTargetCard(seasonId: targetSeasonId, resolution: resolution),
            const SizedBox(height: 24),
            _SubmitButton(seasonId: targetSeasonId, target: target),
          ],
        ),
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
        .set(
          documentFromBytes(
            widget.kind,
            bytes,
            file.extension,
            fileName: file.name,
          ),
        );
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
  String? extension, {
  String? fileName,
}) {
  final ext = extension?.toLowerCase();
  if (ext == 'pdf' || kind == AiImportKind.script) {
    return AiImportDocument.pdf(bytes, fileName: fileName);
  }
  return AiImportDocument.csv(
    utf8.decode(bytes, allowMalformed: true),
    fileName: fileName,
  );
}

/// The persistent AI disclosure card (spec `flutter-ai-import-workflow`
/// delta "Point-of-interaction AI disclosure", issue #538): icon + icon
/// surface so the disclosure is visibly distinct, copy keyed on the ARB
/// catalogs (no inline copy), rendered before the submit button. The
/// configured provider/model naming line rides under the body (issue
/// #608): the point of interaction states WHICH configured provider/model
/// the import runs with — honest degradation when unconfigured.
class _DisclosureCard extends ConsumerWidget {
  const _DisclosureCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Card(
    key: const Key('ai-import-disclosure'),
    color: Theme.of(context).colorScheme.tertiaryContainer,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.smart_toy_outlined,
            color: Theme.of(context).colorScheme.tertiary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  key: const Key('ai-import-disclosure-title'),
                  l10nOf(context).aiImportDisclosureTitle,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  key: const Key('ai-import-disclosure-body'),
                  l10nOf(context).aiImportDisclosureBody,
                ),
                const SizedBox(height: 4),
                // "Import runs with provider X / model Y" (issue #608):
                // the configured wire naming until per-job provenance
                // arrives from the backend.
                AiNamingLine(key: const Key('ai-import-naming')),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// The visible import TARGET (issue #771): `Season {n} · Block {n}` above the
/// submit action.
///
/// The reported defect was an import whose write target was invisible ambient
/// state: the season came from `X-Active-Block`, nothing on screen named it, and
/// a freshly created season therefore changed nothing. This card closes that
/// gap and also makes the target RESOLVABLE before dispatch:
///
/// - no season context → the actionable "select a season" state (no target);
/// - resolution pending → the honest "resolving" state (no target);
/// - exactly one block in the season → adopted automatically (the resolution
///   seam sets the sticky scope, so the header follows the line);
/// - several blocks → the inline picker, whose pick sets the sticky scope;
/// - none → "create a block first" (no target);
/// - fetch failure → the code-keyed retry surface.
///
/// The numbers come from read DTOs only: the season number is resolved
/// CACHE-ONLY and degrades to its explicit "unknown" narrative, the block number
/// rides on the resolved scope. Nothing is invented.
class _ImportTargetCard extends ConsumerWidget {
  const _ImportTargetCard({required this.seasonId, required this.resolution});

  final String? seasonId;
  final AsyncValue<BlockScopeResolution>? resolution;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = l10nOf(context);
    final theme = Theme.of(context);
    final resolved = aiImportResolvedScope(resolution);
    final seasonNumber = seasonId == null
        ? null
        : ref.watch(aiImportSeasonNumberProvider(seasonId!)).value;

    final Widget body;
    if (seasonId == null) {
      body = Text(
        l10n.aiImportTargetNoSeason,
        key: const Key('ai-import-target-missing'),
      );
    } else if (resolution == null) {
      // Unreachable in practice (a null season returns above), but the card
      // never fabricates a target: with no resolution there is nothing to show.
      body = Text(l10n.aiImportTargetNoSeason);
    } else {
      body = switch (resolution!) {
        AsyncLoading() => Text(
          l10n.aiImportTargetLoading,
          key: const Key('ai-import-target-loading'),
        ),
        AsyncError(:final error) => Row(
          key: const Key('ai-import-target-error'),
          children: [
            Expanded(
              child: Text(l10n.blocksFetchError(blockScopeErrorCode(error))),
            ),
            TextButton(
              key: const Key('ai-import-target-retry'),
              onPressed: () =>
                  ref.invalidate(blocksListFetchProvider(seasonId!)),
              child: Text(l10n.commonRetry),
            ),
          ],
        ),
        AsyncData(:final value) when value.isEmpty => Text(
          l10n.aiImportTargetNoBlocks,
          key: const Key('ai-import-target-no-blocks'),
        ),
        AsyncData(:final value) when value.candidates != null => Column(
          key: const Key('ai-import-target-picker'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.aiImportTargetPickBlock),
            const SizedBox(height: 4),
            for (final block in value.candidates!)
              ListTile(
                key: Key('ai-import-target-pick-${block.id}'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.blockTileLabel('${block.number}')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => ref
                    .read(activeBlockProvider.notifier)
                    .set(
                      seasonId: seasonId!,
                      blockId: block.id,
                      blockNumber: block.number,
                    ),
              ),
          ],
        ),
        AsyncData() => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.aiImportTargetLine(
                seasonNumber == null
                    ? l10n.aiImportTargetUnknownSeason
                    : l10n.blockSeasonNumber(seasonNumber),
                resolved?.blockNumber == null
                    ? l10n.aiImportTargetUnknownBlock
                    : l10n.blockTileLabel('${resolved!.blockNumber}'),
              ),
              key: const Key('ai-import-target-line'),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              l10n.aiImportTargetHint,
              key: const Key('ai-import-target-hint'),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      };
    }

    return Card(
      key: const Key('ai-import-target'),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.aiImportTargetTitle,
              key: const Key('ai-import-target-title'),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            body,
          ],
        ),
      ),
    );
  }
}

/// The submit dispatch for the picked file. Shows linear progress while the
/// upload is in flight; on a 200 duplicate the status screen opens with the
/// duplicate callout; on a 202 the plain status screen opens.
class _SubmitButton extends ConsumerStatefulWidget {
  const _SubmitButton({this.seasonId, this.target});

  final String? seasonId;

  /// The resolved target block (issue #771). `null` while the target is still
  /// unresolved (loading, pending picker, no block, fetch failure): the submit
  /// affordance stays DISABLED so a dispatch can never carry a block the user
  /// was not shown. The controller re-checks the same fact before the network
  /// call, because a widget guard alone cannot cover the wizard path whose
  /// season has no block yet.
  final ActiveScope? target;

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
          .submit(
            document,
            // The resolved block's own season wins over the entry-point hint:
            // the declared header, the AUTHZ gate and the visible line must all
            // name the same season (issue #771).
            seasonId: widget.target?.seasonId ?? widget.seasonId,
          );
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
        onPressed: _busy || widget.target == null ? null : _submit,
        child: Text(l10nOf(context).aiImportSubmit),
      ),
    ],
  );
}
