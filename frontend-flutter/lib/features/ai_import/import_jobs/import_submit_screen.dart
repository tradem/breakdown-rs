// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)
// Co-authored-by: space-bunny-free (opencode-go)
// Co-authored-by: glm-5.3-flash (opencode-go)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

import 'dart:convert';
import 'dart:typed_data';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/active_block.dart';
import '../../../l10n/app_localizations_provider.dart';
import '../../blocks/active_block_gate.dart';
import '../../blocks/blocks_controller.dart';
import '../../blocks/create_block_sheet.dart';
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
import '../../../design/components/breakdown_app_bar.dart';

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
      appBar: BreakdownAppBar(
        title: l10nOf(context).aiImportTitle,
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
            _SubmitButton(
              seasonId: targetSeasonId,
              target: target,
              // Issue #829 follow-up: a season with no block at all leaves the
              // block-less dispatch as the ONLY target that exists, so it needs
              // no extra tap — the card has just said that the block comes from
              // the script.
              seasonHasNoBlock: resolution?.value?.isEmpty ?? false,
            ),
          ],
        ),
      ),
    );
  }
}

/// File picker row: `file_picker` at point of use only (FOSS; the picked
/// bytes are read immediately into the pending document — nothing is
/// persisted client-side beyond the in-flight upload).
///
/// The displayed name is DERIVED from the pending document (code review), never
/// remembered locally: the document already carries the file's own name
/// (`AiImportDocument.fileName`, issue #763), so once the provider is cleared —
/// a kind switch, or a successful submit (issue #831) — the name goes with it
/// and the row falls back to its localized "no file picked" state instead of
/// naming a file the dispatch no longer carries.
class _FilePickRow extends ConsumerWidget {
  const _FilePickRow({super.key, required this.kind});

  final AiImportKind kind;

  Future<void> _pick(BuildContext context, WidgetRef ref) async {
    // file_picker 12.x: the single-file picker is static; the bytes are
    // read explicitly at point of use (nothing is persisted client-side
    // beyond the in-flight upload).
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: kind == AiImportKind.schedule
          ? const ['csv', 'pdf']
          : const ['pdf'],
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return;
    ref
        .read(pendingDocumentProvider.notifier)
        .set(
          documentFromBytes(kind, bytes, file.extension, fileName: file.name),
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A pending body without a name (a pasted body — no UI path today) renders
    // the same neutral line rather than inventing a file name.
    final pickedName = ref.watch(pendingDocumentProvider)?.fileName;
    return Row(
      children: [
        OutlinedButton(
          key: const Key('ai-import-pick-file'),
          onPressed: () => _pick(context, ref),
          child: Text(
            kind == AiImportKind.schedule
                ? l10nOf(context).aiImportPickCsvPdf
                : l10nOf(context).aiImportPickPdf,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            pickedName ?? l10nOf(context).aiImportNoFile,
            key: const Key('ai-import-picked-name'),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
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

  /// The card's body while "Block extrahieren" is active (issue #898).
  ///
  /// The line states the season with the block as UNKNOWN, and the hint says
  /// where the block will come from — the previously resolved block is
  /// deliberately not repeated, because the dispatch no longer carries it (a
  /// card saying `Block 1` beside a block-less dispatch is exactly the drift
  /// issue #771 exists to forbid). The line keeps the shared
  /// `ai-import-target-line` key, so "one target line" stays one node.
  Widget _deferredTargetBody(BuildContext context, String? seasonNumber) {
    final l10n = l10nOf(context);
    final theme = Theme.of(context);
    return Column(
      key: const Key('ai-import-target-deferred'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.aiImportTargetLine(
            seasonNumber == null
                ? l10n.aiImportTargetUnknownSeason
                : l10n.blockSeasonNumber(seasonNumber),
            l10n.aiImportTargetUnknownBlock,
          ),
          key: const Key('ai-import-target-line'),
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          // What happens AFTER the upload, with both possible outcomes: at
          // submit time neither the number nor the season's block list can
          // decide between them, so the card must not imply one.
          l10n.aiImportTargetExtractHint,
          key: const Key('ai-import-target-extract-hint'),
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = l10nOf(context);
    final theme = Theme.of(context);
    final resolved = aiImportResolvedScope(resolution);
    // Issue #898: "Block extrahieren" — the dispatch takes its target block
    // from the script instead of the active block. Read here so the card and
    // the dispatch cannot disagree about it.
    final extracting = ref.watch(aiImportExtractBlockProvider);
    final seasonNumber = seasonId == null
        ? null
        : ref.watch(aiImportSeasonNumberProvider(seasonId!)).value;
    // Issue #828: the season's blocks as the list route publishes them — the
    // candidate source of the explicit "switch block" action. A resolved scope
    // carries only the ONE acted-on block, so switching in the `ready` arm needs
    // this list. The fetch reports a failure as a `Left` INSIDE the data (the
    // repositories return `Result`, never throw), so both shapes are unwrapped:
    // rows for the switch, the problem for the honest retry surface below.
    final fetch = seasonId == null
        ? null
        : ref.watch(blocksListFetchProvider(seasonId!));
    final blocks = fetch?.value?.match(
      (_) => const <BlockView>[],
      (rows) => rows,
    );
    final blockListProblem = switch (fetch) {
      null => null,
      AsyncError(:final error) => error,
      AsyncData(:final value) => value.match<Object?>(
        (err) => err,
        (_) => null,
      ),
      _ => null,
    };
    // Review (#828): with the sticky scope already matching the season the
    // resolution is `ready` even when the block-list fetch FAILED, so the switch
    // action would vanish with no explanation — and leaving the screen for the
    // block pill is the very defect this card fixes. Surface the failure with
    // its retry; the `AsyncError` resolution arm already renders the same
    // narrative, so this only covers the arms that are `data`.
    final listError = resolution is AsyncError ? null : blockListProblem;

    // Issue #829: a block-less dispatch has no block to show, so the card
    // states exactly that. It is the SEASON's fact (no block exists), never a
    // choice the user has to make — see the submit affordance below.
    final Widget body;
    // Issue #828 affordances: which of the two a state can honestly offer.
    var canSwitch = false;
    var canCreate = false;
    // Issue #898: the third choice (take the block from the script).
    var canExtract = false;
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
        AsyncData(:final value) when value.isEmpty => Column(
          key: const Key('ai-import-target-no-blocks'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The deferred target, stated as such: the season is known and IS
            // the authorization scope, the block comes from the script (#827).
            Text(
              l10n.aiImportTargetLine(
                seasonNumber == null
                    ? l10n.aiImportTargetUnknownSeason
                    : l10n.blockSeasonNumber(seasonNumber),
                l10n.aiImportTargetUnknownBlock,
              ),
              key: const Key('ai-import-target-line'),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(l10n.aiImportTargetNoBlocks),
            const SizedBox(height: 4),
            Text(
              l10n.aiImportTargetBlockLess,
              key: const Key('ai-import-target-blockless-hint'),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        AsyncData(:final value) when value.candidates != null => Column(
          key: const Key('ai-import-target-picker'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.aiImportTargetPickBlock),
            const SizedBox(height: 4),
            for (final block in value.candidates!)
              _ImportTargetBlockTile(
                key: Key('ai-import-target-pick-${block.id}'),
                block: block,
                selected: false,
                contentPadding: EdgeInsets.zero,
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
      // A RESOLVED target always offers a way forward (issue #828): switching
      // needs the season's blocks, creating never does. The inline candidate
      // picker IS the switch for the `needsPick` arm, so it never renders both.
      final resolvedValue = resolution!.value;
      final alreadyPicking = resolvedValue?.candidates != null;
      canSwitch =
          resolvedValue != null &&
          !alreadyPicking &&
          (blocks?.isNotEmpty ?? false);
      canCreate = resolvedValue != null;
      // Issue #898: extracting needs no block list at all — only a season that
      // HAS a block to extract away from. In the empty arm the block-less
      // dispatch is already the only target that exists (and applies without a
      // tap), so a second way to say the same thing is not offered.
      canExtract = resolvedValue != null && !resolvedValue.isEmpty;
    }

    // Issue #898: while the choice is active the card must not name a block the
    // dispatch will not send — issue #771's single seam, applied to the line.
    final displayBody = extracting && canExtract
        ? _deferredTargetBody(context, seasonNumber)
        : body;

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
            displayBody,
            if (listError != null)
              Row(
                key: const Key('ai-import-target-list-error'),
                children: [
                  Expanded(
                    child: Text(
                      l10n.blocksFetchError(blockScopeErrorCode(listError)),
                    ),
                  ),
                  TextButton(
                    key: const Key('ai-import-target-list-retry'),
                    onPressed: () =>
                        ref.invalidate(blocksListFetchProvider(seasonId!)),
                    child: Text(l10n.commonRetry),
                  ),
                ],
              ),
            if (canSwitch || canCreate || canExtract)
              _ImportTargetActions(
                onSwitch: canSwitch
                    ? () => _switchImportBlock(
                        context,
                        ref,
                        seasonId: seasonId!,
                        blocks: blocks ?? const <BlockView>[],
                        currentBlockId: resolved?.blockId,
                      )
                    : null,
                onCreate: canCreate
                    ? () => _createImportBlock(context, ref, seasonId!)
                    : null,
                onExtract: canExtract
                    ? () => ref
                          .read(aiImportExtractBlockProvider.notifier)
                          .set(!extracting)
                    : null,
                extracting: extracting,
              ),
          ],
        ),
      ),
    );
  }
}

/// One block row of the target card (issue #828): the inline candidate picker
/// and the explicit switch sheet render the SAME row, so a block looks and
/// behaves identically in both paths. Presentation only — the caller owns the
/// selection seam.
class _ImportTargetBlockTile extends StatelessWidget {
  const _ImportTargetBlockTile({
    super.key,
    required this.block,
    required this.selected,
    required this.onTap,
    this.contentPadding = EdgeInsets.zero,
  });

  final BlockView block;

  /// `true` for the block the scope already points at (the switch sheet's
  /// "you are here" marker): a picker that cannot tell you the current target
  /// invites a pointless round-trip.
  final bool selected;

  final VoidCallback onTap;
  final EdgeInsetsGeometry contentPadding;

  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    contentPadding: contentPadding,
    title: Text(l10nOf(context).blockTileLabel('${block.number}')),
    trailing: Icon(selected ? Icons.check : Icons.chevron_right),
    onTap: onTap,
  );
}

/// The target card's actions (issue #828): "Block wechseln" and "Block
/// anlegen" as VISIBLE text buttons (glossary "visible labels" rule — no
/// icon-only affordance). Which one is rendered is the card's decision; this
/// widget only lays them out.
///
/// Issue #898 adds the third choice, "Block extrahieren": the import takes its
/// block from the script instead of the active block. While that choice is
/// active the same control is its undo — one toggle, and the label always names
/// the action the tap will perform.
class _ImportTargetActions extends StatelessWidget {
  const _ImportTargetActions({
    this.onSwitch,
    this.onCreate,
    this.onExtract,
    this.extracting = false,
  });

  final VoidCallback? onSwitch;
  final VoidCallback? onCreate;

  /// Toggles "take the block from the script" for this dispatch.
  final VoidCallback? onExtract;

  /// `true` while the choice is active — the label flips to its undo.
  final bool extracting;

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    return Wrap(
      spacing: 8,
      children: [
        if (onSwitch != null)
          TextButton(
            key: const Key('ai-import-target-switch'),
            onPressed: onSwitch,
            child: Text(l10n.aiImportTargetSwitchBlock),
          ),
        if (onCreate != null)
          TextButton(
            key: const Key('ai-import-target-create'),
            onPressed: onCreate,
            child: Text(l10n.aiImportTargetCreateBlock),
          ),
        if (onExtract != null)
          TextButton(
            key: const Key('ai-import-target-extract'),
            onPressed: onExtract,
            child: Text(
              extracting
                  ? l10n.aiImportTargetExtractBlockUndo
                  : l10n.aiImportTargetExtractBlock,
            ),
          ),
      ],
    );
  }
}

/// Opens the target season's block list as a sheet (issue #828).
///
/// The card could already switch blocks in ONE state only (the candidate
/// picker, while the sticky scope did not match the season); a resolved target
/// had no switch affordance at all, so changing it meant leaving the screen for
/// the shell's block pill. Resolves to the picked block, `null` on dismissal.
Future<BlockView?> _showImportTargetBlockSheet(
  BuildContext context, {
  required List<BlockView> blocks,
  required String? currentBlockId,
}) {
  final l10n = l10nOf(context);
  return showModalBottomSheet<BlockView>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        key: const Key('ai-import-target-switch-sheet'),
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              l10n.aiImportTargetPickBlock,
              style: Theme.of(sheetContext).textTheme.titleMedium,
            ),
          ),
          for (final block in blocks)
            _ImportTargetBlockTile(
              key: Key('ai-import-target-switch-${block.id}'),
              block: block,
              selected: block.id == currentBlockId,
              onTap: () => Navigator.of(sheetContext).pop(block),
            ),
        ],
      ),
    ),
  );
}

/// Switches the import target (issue #828).
///
/// The pick goes through [activeBlockProvider] — the SAME seam the inline
/// picker and the shell's block pill use — so the visible target line, the
/// declared season and the `X-Active-Block` header stay one value (issue #771's
/// single seam). Sending a block id with the upload instead would be refused by
/// the dispatch's `ai_import.scope_mismatch` guard, by design.
Future<void> _switchImportBlock(
  BuildContext context,
  WidgetRef ref, {
  required String seasonId,
  required List<BlockView> blocks,
  required String? currentBlockId,
}) async {
  final picked = await _showImportTargetBlockSheet(
    context,
    blocks: blocks,
    currentBlockId: currentBlockId,
  );
  if (picked == null) return;
  // Issue #898: an explicit block choice countermands a pending "Block
  // extrahieren" — the user just named the block they want, so the dispatch
  // must carry it instead of deferring to the script.
  ref.read(aiImportExtractBlockProvider.notifier).set(false);
  ref
      .read(activeBlockProvider.notifier)
      .set(seasonId: seasonId, blockId: picked.id, blockNumber: picked.number);
}

/// Creates the block the import needs, from the target card (issue #828).
///
/// The reported dead end was a season without blocks: the card printed "no
/// blocks" as plain text and left the user to find the Blocks screen. The
/// SHARED create-block form is reused (never a second form), and the block it
/// acknowledges becomes the active scope — the create route answers with an id
/// only, so the number the user typed rides back from the form ([CreatedBlock])
/// rather than being re-derived from a projection that has not reconciled yet.
///
/// A NEWER explicit selection wins: the form opens after an awaited row read
/// (cache hit is instant, a miss is a round-trip) and the scope can legitimately
/// change while this future is in flight — a sign-in restore, or the shell's
/// block pill. Re-pointing the target at the block this form created would then
/// silently contradict the choice the user just made, so the scope captured at
/// the start of the interaction must still be current.
Future<void> _createImportBlock(
  BuildContext context,
  WidgetRef ref,
  String seasonId,
) async {
  final l10n = l10nOf(context);
  final selectionBefore = ref.read(activeBlockProvider);
  final season = await ref.read(aiImportSeasonViewProvider(seasonId).future);
  if (!context.mounted) return;
  if (season == null) {
    // The shared form pre-fills its ids from the season row (CQRS boundary),
    // so an unreadable row is reported instead of opening a form it cannot
    // fill with a guessed id.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: const Key('ai-import-target-season-unavailable'),
        content: Text(l10n.aiImportTargetSeasonUnavailable),
      ),
    );
    return;
  }
  final created = await showCreateBlockSheet(context, ref, season);
  if (created == null) return;
  // Issue #898: same countermand as the switch above — a block the user just
  // created is the one they want, not the script's.
  ref.read(aiImportExtractBlockProvider.notifier).set(false);
  if (ref.read(activeBlockProvider) != selectionBefore) return;
  ref
      .read(activeBlockProvider.notifier)
      .set(
        seasonId: seasonId,
        blockId: created.id,
        blockNumber: created.number,
      );
}

/// The submit dispatch for the picked file. Shows linear progress while the
/// upload is in flight; on a 200 duplicate the status screen opens with the
/// duplicate callout; on a 202 the plain status screen opens.
class _SubmitButton extends ConsumerStatefulWidget {
  const _SubmitButton({
    this.seasonId,
    this.target,
    this.seasonHasNoBlock = false,
  });

  final String? seasonId;

  /// The resolved target block (issue #771). `null` while the target is still
  /// unresolved (loading, pending picker, no block, fetch failure): the submit
  /// affordance stays DISABLED so a dispatch can never carry a block the user
  /// was not shown. The controller re-checks the same fact before the network
  /// call, because a widget guard alone cannot cover the wizard path whose
  /// season has no block yet.
  final ActiveScope? target;

  /// `true` when the target season has **no block at all** (issue #829
  /// follow-up). Then the block-less dispatch is not a choice to opt into: it
  /// is the only target that exists, and the card has already stated that the
  /// block comes from the script — so requiring a tap only read as "create a
  /// block first", which is exactly what sent the reporter back to the block
  /// form. A season WITH blocks keeps the explicit paths (pick / create).
  final bool seasonHasNoBlock;

  @override
  ConsumerState<_SubmitButton> createState() => _SubmitButtonState();
}

class _SubmitButtonState extends ConsumerState<_SubmitButton> {
  bool _busy = false;

  /// The block-less dispatch applies when the season has no block to adopt and
  /// none is resolved — the one state in which no block-bearing target exists.
  bool get _seasonHasNothingToAdopt =>
      widget.seasonHasNoBlock && widget.target == null;

  /// Whether this dispatch goes without a target block: either the season has
  /// none to adopt (issue #829), or the user asked for the script's block
  /// (issue #898). Read from the provider rather than a widget field, so the
  /// choice made on the card a frame ago is the one this dispatch sends.
  bool get _isBlockLess =>
      ref.read(aiImportExtractBlockProvider) || _seasonHasNothingToAdopt;

  Future<void> _submit() async {
    // Backstop (issue #831): the button below is disabled until a document
    // exists, so this arm is not reachable from the UI — it stays because a
    // dispatch must never be able to leave without bytes (a programmatic
    // caller, or a future affordance, gets the explicit code-keyed snackbar
    // instead of an upload of nothing).
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
      // A resolved block always wins over the block-less arm (review finding):
      // the dispatch must send the target the card showed.
      final blockLess = _isBlockLess;
      final res = await ref
          .read(aiImportSubmitControllerProvider.notifier)
          .submit(
            document,
            // The resolved block's own season wins over the entry-point hint:
            // the declared header, the AUTHZ gate and the visible line must all
            // name the same season (issue #771).
            seasonId: widget.target?.seasonId ?? widget.seasonId,
            // Issue #829: a deliberate block-less dispatch declares its season
            // and sends no `X-Active-Block`; the target block is attached after
            // extraction.
            blockLess: blockLess,
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
  Widget build(BuildContext context) {
    // Issue #831: a dispatch needs a document, and the picked one lives in
    // `pendingDocumentProvider` (both kinds write it; a kind switch clears it,
    // and a successful submit clears it again). Reading it here makes the
    // affordance state the same fact instead of letting a tap discover it: the
    // button is disabled until a file exists, and disabled again right after
    // the dispatch cleared the provider. The pick row already renders the
    // localized "no file picked" line, so the disabled state has a visible
    // explanation.
    final hasDocument = ref.watch(pendingDocumentProvider) != null;
    // Issue #829: a block-less dispatch is a resolved target too — the season
    // is mandatory and IS the authorization scope, only the block is deferred.
    // It applies exactly when the season has NO block (then there is nothing to
    // pick) and no block is resolved; a season WITH blocks keeps the explicit
    // pick/create paths, so a dispatch never silently drops a block the user
    // could have had. Issue #898 adds the explicit choice: the user may ask for
    // the script's block instead, and then the deferred target is the one the
    // card shows.
    final extractingBlock = ref.watch(aiImportExtractBlockProvider);
    final blockLess = extractingBlock || _seasonHasNothingToAdopt;
    final hasTarget =
        widget.target != null || (blockLess && widget.seasonId != null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_busy)
          // Honest progress: the backend exposes no percentage, so the
          // indicator is indeterminate (never a fabricated determinate bar).
          const LinearProgressIndicator(key: Key('ai-import-progress')),
        const SizedBox(height: 12),
        FilledButton(
          key: const Key('ai-import-submit'),
          onPressed: _busy || !hasTarget || !hasDocument ? null : _submit,
          child: Text(l10nOf(context).aiImportSubmit),
        ),
      ],
    );
  }
}
