// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)
// Co-authored-by: omen-alpha (opencode-go)
// Co-authored-by: glm-5.3-flash (neuralwatt)
// Co-authored-by: deepseek-v4-flash (neuralwatt)
// Co-authored-by: glm-5.3-flash (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../auth/active_block.dart';
import '../../../auth/auth_providers.dart';
import '../../../core/problem_error.dart';
import '../../../data/ai_import_providers.dart';
import '../../../data/cache/hierarchy_cache_dao.dart';
import '../../../l10n/app_localizations_provider.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../data/cache/seasons_cache_providers.dart';
import '../../episodes/episodes_controller.dart';
import '../../scenes/scenes_controller.dart';
import 'apply_controller.dart';
import 'import_submit_screen.dart';
import 'job_status_controller.dart';
import '../naming_line.dart';

part 'apply_screen.g.dart';

/// The apply section (`flutter-ai-import-workflow` task 4.2): the
/// persisted episode context (or the REQUIRED explicit episode picker),
/// the accept-as-is / edit-distance readout, the apply dispatch with the
/// ambiguous-timeout reconciliation, and the outcome summary card with
/// deep navigation.
///
/// `apply_as_is` + `edit_distance` come from the REAL selection state —
/// never invented (the controller reports them; the backend rejects
/// `accept_as_is` with a non-zero `edit_distance`).
///
/// The apply dispatch is gated behind an explicit review acknowledgement
/// (EU AI Act Art. 50, issue #538): the checkbox is widget state (ephemeral
/// acknowledgement, not domain state), the submit button stays disabled
/// until it is checked — together with the existing context gate.
///
/// [reviewToken] ties the acknowledgement to the PAYLOAD it was given for:
/// a refreshed preview reseeds the controller rows at the same element
/// position, so a stale acknowledgement would otherwise carry over and let
/// the replacement rows be applied unreviewed. A new token resets the
/// checkbox (the acknowledged content is gone, the acknowledgement with it).
class EpisodeGroupHeader extends ConsumerWidget {
  const EpisodeGroupHeader({
    required this.jobId,
    required this.groupRef,
    super.key,
  });

  final String jobId;
  final String? groupRef;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(aiApplyControllerProvider(jobId));
    final ref_ = groupRef;
    if (ref_ == null) {
      final target = state.context?.episodeId;
      return _groupHeaderCard(
        context,
        key: const Key('ai-preview-ungrouped-header'),
        title: target == null
            ? l10nOf(context).aiApplyUngroupedHeadingNoTarget
            : l10nOf(context).aiApplyUngroupedHeading(target),
      );
    }
    final episode = state.episodeOfGroup(ref_);
    final label = episode == null
        ? ref_
        : draftEpisodeLabel(l10nOf(context), episode.number, episode.title);
    return _groupHeaderCard(
      context,
      key: Key('ai-preview-group-header-$ref_'),
      title: label,
      subtitle: groupTargetLabel(l10nOf(context), state.targetFor(ref_)),
      trailing: TextButton(
        key: Key('ai-preview-group-target-change-$ref_'),
        onPressed: () => showGroupTargetSheet(context, ref, jobId, ref_),
        child: Text(l10nOf(context).aiApplyGroupTargetChange),
      ),
    );
  }

  Widget _groupHeaderCard(
    BuildContext context, {
    required Key key,
    required String title,
    String? subtitle,
    Widget? trailing,
  }) => Card(
    key: key,
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    margin: const EdgeInsets.only(top: 8),
    child: ListTile(
      dense: true,
      title: Text(title, style: Theme.of(context).textTheme.titleSmall),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: trailing,
    ),
  );
}

/// The per-group target sheet (issue #581): switch the group between an
/// EXISTING episode (the job's block, live-fetched — ids never guessed) and
/// a NEW one (number + name, pre-filled from the heading). The dispatch
/// stays one explicit reviewed apply — this only edits the mapping.
Future<void> showGroupTargetSheet(
  BuildContext context,
  WidgetRef ref,
  String jobId,
  String groupRef,
) async {
  final controller = ref.read(aiApplyControllerProvider(jobId).notifier);
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            key: const Key('ai-group-target-pick-existing'),
            leading: const Icon(Icons.playlist_add_check_outlined),
            title: Text(l10nOf(sheetContext).aiApplyGroupTargetPickExisting),
            onTap: () => Navigator.of(sheetContext).pop('existing'),
          ),
          ListTile(
            key: const Key('ai-group-target-create'),
            leading: const Icon(Icons.add),
            title: Text(l10nOf(sheetContext).aiApplyGroupTargetEditCreate),
            onTap: () => Navigator.of(sheetContext).pop('create'),
          ),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case 'existing':
      final picked = await showEpisodePicker(context, ref, jobId);
      if (picked == null || !context.mounted) return;
      // CodeRabbit review: the picker falls back to the cache-wide read when
      // the job row carries no block id — a picked episode from ANOTHER block
      // would become the apply context episode and the backend cross-block
      // guard would 403 every apply. Validate against the job's block BEFORE
      // adoption. An unavailable anchor means a BLOCK-LESS (legacy/uncached)
      // job — the backend guard is `if let Some(job_block)`, so it permits
      // any episode there and the client must not refuse a server-permitted
      // flow; only a KNOWN job block with a differing episode is refused
      // (mirroring exactly the 403 the backend would answer).
      final blockInfo = await ref.read(aiJobBlockInfoProvider(jobId).future);
      if (!context.mounted) return;
      final jobBlock = blockInfo?.blockId;
      if (jobBlock != null &&
          jobBlock.isNotEmpty &&
          picked.blockId != jobBlock) {
        final current = ref.read(aiApplyControllerProvider(jobId));
        if (current.commandError == null) {
          controller.setCommandError(
            const ProblemError(code: 'ai-import.forbidden'),
          );
        }
        return;
      }
      // Adopt (not just set): the picked episode lives in the job's block,
      // so the apply context moves with it — the cross-block IDOR guard
      // needs a context episode from THAT block.
      final numberLabel = l10nOf(context).episodeTileLabel('${picked.number}');
      final pickedName = picked.name?.trim();
      controller.adoptCreatedEpisode(
        groupRef,
        episodeId: picked.id,
        number: picked.number,
        projectId: picked.projectId,
        label: pickedName == null || pickedName.isEmpty
            ? numberLabel
            : '$numberLabel \u00b7 $pickedName',
      );
    case 'create':
      final state = ref.read(aiApplyControllerProvider(jobId));
      final current = state.targetFor(groupRef);
      final initial = current is CreateEpisodeGroupTarget
          ? current
          : const CreateEpisodeGroupTarget();
      final result = await showGroupCreateDialog(context, initial: initial);
      // The dialog can outlive the notifier (a preview refresh replaced the
      // payload, or navigation disposed the autoDispose provider) — the same
      // guard the existing-episode branch applies after its await.
      if (result == null || !context.mounted) return;
      // The target is only the INTENT — the episode is created RIGHT HERE
      // (in the job's block) and adopted, so "Import anwenden" activates on
      // a resolved episode (user UX rule). On failure fall back to the
      // create target (apply stays disabled; the backend 409 recovery is
      // the backstop).
      controller.setGroupTarget(groupRef, result);
      // CodeRabbit review: the resolution can fail (offline getBlock, disposed
      // notifier) — never leak the exception through the sheet; surface a
      // command error instead so the reviewer sees WHY apply stays disabled.
      bool resolved = false;
      try {
        resolved = await ensureGroupEpisodeResolved(
          ref,
          jobId,
          groupRef,
          result,
        );
      } on Object {
        resolved = false;
      }
      if (!resolved && context.mounted) {
        final current = ref.read(aiApplyControllerProvider(jobId));
        if (current.commandError == null) {
          ref
              .read(aiApplyControllerProvider(jobId).notifier)
              .setCommandError(
                const ProblemError(code: 'ai_import.episode_create_failed'),
              );
        }
      }
  }
}

/// The create-new editor: the wire-required number (a marker without one
/// leaves the target incomplete and apply disabled) plus the optional name,
/// both pre-filled from the heading the group was extracted from.
Future<CreateEpisodeGroupTarget?> showGroupCreateDialog(
  BuildContext context, {
  required CreateEpisodeGroupTarget initial,
}) {
  final numberController = TextEditingController(
    text: initial.number?.toString() ?? '',
  );
  final nameController = TextEditingController(text: initial.name ?? '');
  final formKey = GlobalKey<FormState>();
  return showDialog<CreateEpisodeGroupTarget>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const Key('ai-group-create-dialog'),
      title: Text(l10nOf(dialogContext).aiApplyGroupTargetEditCreate),
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: const Key('ai-group-create-number'),
              controller: numberController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: l10nOf(dialogContext).aiApplyGroupCreateNumberLabel,
              ),
              validator: (value) => int.tryParse(value ?? '') == null
                  ? l10nOf(dialogContext).aiApplyGroupNumberInvalid
                  : null,
            ),
            TextFormField(
              key: const Key('ai-group-create-name'),
              controller: nameController,
              decoration: InputDecoration(
                labelText: l10nOf(dialogContext).aiApplyGroupCreateNameLabel,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(l10nOf(dialogContext).commonCancel),
        ),
        FilledButton(
          key: const Key('ai-group-create-save'),
          onPressed: () {
            if (!(formKey.currentState?.validate() ?? false)) return;
            final name = nameController.text.trim();
            Navigator.of(dialogContext).pop(
              CreateEpisodeGroupTarget(
                number: int.parse(numberController.text),
                name: name.isEmpty ? null : name,
              ),
            );
          },
          child: Text(l10nOf(dialogContext).commonSave),
        ),
      ],
    ),
  );
}

/// Non-actionable preview row card (info only — excluded from the
/// decisions and from accept-all).

class AiApplySection extends ConsumerStatefulWidget {
  const AiApplySection({required this.jobId, this.reviewToken, super.key});

  final String jobId;

  /// Identity of the reviewed payload (the preview response instance). `null`
  /// keeps the acknowledgement across rebuilds that carry the same content
  /// (the standalone/integration usages without a preview parent).
  final Object? reviewToken;

  @override
  ConsumerState<AiApplySection> createState() => _AiApplySectionState();
}

class _AiApplySectionState extends ConsumerState<AiApplySection> {
  /// The explicit review acknowledgement (EU AI Act Art. 50, issue #538):
  /// a persistent, per-entry checkbox — the submit button never dispatches
  /// while it is unchecked. Widget state on purpose (ephemeral
  /// acknowledgement, not domain state; resets when the section re-enters,
  /// when the outcome renders, or when [AiApplySection.reviewToken] changes
  /// because a refreshed preview replaced the reviewed rows).
  bool _reviewAcknowledged = false;

  /// Widget-local busy flag: the apply dispatches dozens of commands (one
  /// scene = create + figures + beats) and takes many seconds — without a
  /// visible busy state the reviewer re-tapped the (still enabled) button,
  /// piling up duplicate idempotent dispatches, and navigating away mid-apply
  /// dropped the outcome entirely (autoDispose notifier: no state write, no
  /// cache invalidation). Spinner on the button + disabled while running.
  bool _applying = false;

  @override
  void didUpdateWidget(AiApplySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reviewToken != widget.reviewToken) {
      // New payload → the reviewed content is replaced: the old
      // acknowledgement must not authorize the new rows.
      _reviewAcknowledged = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final jobId = widget.jobId;

    final state = ref.watch(aiApplyControllerProvider(jobId));
    final controller = ref.read(aiApplyControllerProvider(jobId).notifier);
    final canApply = controller.canApply && _reviewAcknowledged;
    // Issue #705 (CodeRabbit review): the cross-block recovery's job-block
    // source of truth is the CACHED JOB ROW, not the apply context — the
    // missing-context episode picker stores the picked episode + project but
    // drops `blockId`, so an empty context value would hide the scope-switch
    // recovery on a cross-block 409 and leave the 403-bound assign-existing
    // tap visible. The context value stays as fallback (older cached rows).
    final cachedJobBlock = ref.watch(aiJobBlockInfoProvider(jobId)).value;
    final jobBlockId = (cachedJobBlock?.blockId.isNotEmpty ?? false)
        ? cachedJobBlock!.blockId
        : (state.context?.blockId.isNotEmpty ?? false)
        ? state.context!.blockId
        : null;

    return Card(
      key: const Key('ai-apply-section'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10nOf(context).aiApplyTitle,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            // Provider/model labelling line (EU AI Act Art. 50, issue
            // #608): the configured wire naming travels with the section
            // so the reviewer always sees WHICH provider/model the
            // configured import runs with (degraded honestly when
            // unconfigured — until per-job provenance arrives from the
            // backend, the configured value is the honest approximation).
            AiNamingLine(key: const Key('ai-apply-naming')),
            const SizedBox(height: 8),
            // The episode-target area ("Ziel ändern") sits ABOVE the apply
            // button (user UX request, 2026-10-19): the reviewer settles
            // WHO the rows belong to right where they dispatch — each
            // group's episode is created/adopted at this point, and "Ziel
            // ändern" can still swap it afterwards.
            for (final groupRef in state.groupRefs)
              EpisodeGroupHeader(jobId: widget.jobId, groupRef: groupRef),
            if (state.context != null)
              ListTile(
                key: const Key('ai-apply-context'),
                dense: true,
                leading: const Icon(Icons.movie_creation_outlined),
                title: Text(
                  l10nOf(context)
                      .aiApplyContextEpisode(state.context!.episodeId),
                ),
                subtitle: Text(l10nOf(context).aiApplyContextRemembered),
              )
            else if (state.groupRefs.isEmpty ||
                state.rows.any(
                  // CodeRabbit review: a MIXED import (grouped + ungrouped
                  // rows) keeps a null top-level context for the ungrouped
                  // rows even after every group resolved — the notice must
                  // not hide behind the non-empty groupRefs.
                  (row) =>
                      row.episode == null ||
                      draftEpisodeGroupRef(row.episode!) == null,
                ))
              // No episode markers in the document (single-episode flow):
              // the explicit pick is required. WITH groups the episodes are
              // created/assigned automatically above ("Ziel ändern") — the
              // picker tile would be noise (user report, 2026-10-19).
              const _EpisodePickerRequired(),
            const SizedBox(height: 8),
            Text(
              key: const Key('ai-apply-selection-summary'),
              state.acceptAsIs
                  ? l10nOf(context).aiApplyAcceptAsIs
                  : l10nOf(context).aiApplySelectionSummary(
                      '${state.rows.where((r) => r.decision is UpdateDecision).length}',
                      '${state.rows.where((r) => r.decision is SkipDecision).length}',
                      '${state.editDistance}',
                    ),
            ),
            // Per-group target summary (issue #581, EU AI Act review gate):
            // the reviewer sees WHICH episode each draft-episode group (and
            // each to-be-created episode) lands in, right at the dispatch.
            for (final groupRef in state.groupRefs)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  key: Key('ai-apply-group-target-$groupRef'),
                  groupTargetSummaryLine(l10nOf(context), state, groupRef),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 12),
            // Issue #663: blocking uncertainties are resolved IN the apply
            // card — one acknowledge checkbox each. Apply stays disabled
            // until every entry is confirmed, so the gate never produces a
            // surprise 409; the copy says what confirming means.
            if (state.blockingUncertainties.isNotEmpty) ...[
              Text(
                key: const Key('ai-apply-uncertainties-title'),
                l10nOf(context).aiApplyUncertaintiesTitle,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              for (var i = 0; i < state.blockingUncertainties.length; i++)
                Builder(
                  builder: (context) {
                    final uncertainty = state.blockingUncertainties[i];
                    final acknowledged = state.acknowledgedKeys.contains(
                      AiApplyController.acknowledgementKey(
                        uncertainty.sceneIndex,
                        uncertainty.field,
                      ),
                    );
                    return CheckboxListTile(
                      key: Key('ai-apply-uncertainty-ack-$i'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: acknowledged,
                      onChanged: (checked) => controller.acknowledgeUncertainty(
                        uncertainty.sceneIndex,
                        uncertainty.field,
                        checked ?? false,
                      ),
                      title: Text(
                        l10nOf(context).aiPreviewUncertainty(
                          uncertainty.field,
                          uncertainty.note,
                        ),
                      ),
                      subtitle: Text(
                        l10nOf(context).aiApplyAcknowledgeUncertainty,
                      ),
                    );
                  },
                ),
              const SizedBox(height: 4),
            ],
            if (state.commandError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      key: const Key('ai-apply-error'),
                      aiApplyErrorCopy(l10nOf(context), state.commandError!),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    // Issue #663: the server's `blocking_uncertainties`
                    // extension lists exactly what still blocks — render the
                    // items inline so the reviewer can resolve without
                    // leaving the card (the shape is optional wire metadata;
                    // an unrecognized shape degrades to no items).
                    for (final (sceneIndex, field, note)
                        in blockingUncertaintyItems(state.commandError!))
                      Text(
                        key: Key('ai-apply-error-blocker-$sceneIndex-$field'),
                        l10nOf(context).aiPreviewUncertainty(field, note),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    // Issue #665: one-tap recovery from the create-number
                    // collision — flip the affected group(s) to assign-existing
                    // with the id the 409 carried; the retry then lands in the
                    // existing episode (idempotent continuation: the backend
                    // skips already-applied rows). Issue #705: only for a
                    // SAME-BLOCK conflict — an existing episode in another
                    // block would 403 at the apply's cross-block IDOR gate;
                    // the scope-switch button below owns that path.
                    Builder(
                      builder: (context) {
                        final conflict = episodeNumberConflict(
                          state.commandError!,
                        );
                        if (conflict == null) return const SizedBox.shrink();
                        if (crossBlockScopeRecovery(
                              state.commandError!,
                              jobBlockId: jobBlockId,
                            ) !=
                            null) {
                          return const SizedBox.shrink();
                        }
                        // CodeRabbit #690: hide the recovery affordance when
                        // no group's effective create target carries the
                        // colliding number any more (the reviewer changed it
                        // after the 409, or the number belongs to a group
                        // the preview does not carry) — dismissing the error
                        // without changing any target would make the next
                        // apply hit the same 409 with the recovery gone.
                        final matching = groupRefsForCreateNumber(
                          state,
                          conflict.$2,
                        );
                        if (matching.isEmpty) return const SizedBox.shrink();
                        return TextButton(
                          key: const Key('ai-apply-assign-existing-instead'),
                          onPressed: () {
                            final controller = ref.read(
                              aiApplyControllerProvider(jobId).notifier,
                            );
                            final label = l10nOf(context)
                                .episodeTileLabel('${conflict.$2}');
                            for (final groupRef in matching) {
                              controller.setGroupTarget(
                                groupRef,
                                ExistingEpisodeGroupTarget(
                                  episodeId: conflict.$1,
                                  label: label,
                                ),
                              );
                            }
                            // Dismiss only after a target actually changed.
                            controller.dismissCommandError();
                          },
                          child: Text(
                            l10nOf(context).aiApplyAssignExistingInstead,
                          ),
                        );
                      },
                    ),
                    // Issue #705: one-tap recovery from a CROSS-BLOCK number
                    // conflict — switch the sticky scope directly to the
                    // conflicting episode's home season+block (bypassing the
                    // season-scoped chip picker) and land on the upload
                    // screen; the re-upload binds the new job to the home
                    // block, where the number collision resolves through the
                    // adopt-in-job-block branch. The dead-end refusal is
                    // dismissed only after the switch landed.
                    Builder(
                      builder: (context) {
                        final recovery = crossBlockScopeRecovery(
                          state.commandError!,
                          jobBlockId: jobBlockId,
                        );
                        if (recovery == null) return const SizedBox.shrink();
                        return TextButton(
                          key: const Key('ai-apply-switch-scope'),
                          onPressed: () async {
                            final controller = ref.read(
                              aiApplyControllerProvider(jobId).notifier,
                            );
                            final block = await ref
                                .read(episodeRepositoryProvider)
                                .blockById(recovery.blockId);
                            // Disposal mid-await: neither mutate the GLOBAL
                            // scope after the fact (ActiveBlock.set only
                            // guards its persistence callback) nor touch
                            // the autoDispose notifier — the State's
                            // `mounted` owns both gates (CodeRabbit review).
                            if (!mounted || !context.mounted) return;
                            final blockView = block.fold((_) => null, (b) => b);
                            if (blockView == null) return;
                            ref
                                .read(activeBlockProvider.notifier)
                                .set(
                                  seasonId: blockView.seasonId,
                                  blockId: blockView.id,
                                  blockNumber: blockView.number,
                                );
                            controller.dismissCommandError();
                            await Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const AiImportSubmitScreen(),
                              ),
                            );
                          },
                          child: Text(
                            l10nOf(context).aiApplySwitchScopeRecovery,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            if (state.outcome != null)
              _OutcomeCard(outcome: state.outcome!)
            else ...[
              // The EU AI Act transparency panel (issue #608): the same
              // Art. 4/Art. 50 copy as the dedicated About-AI disclosure
              // screen, collapsed by default to keep the review section
              // compact — the expand affordance itself is always visible
              // (transparency, never a blocker in the flow).
              _AiActPanel(),
              CheckboxListTile(
                key: const Key('ai-apply-review-checkbox'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _reviewAcknowledged,
                onChanged: (checked) =>
                    setState(() => _reviewAcknowledged = checked ?? false),
                title: Text(l10nOf(context).aiApplyReviewCheckbox),
              ),
              FilledButton(
                key: const Key('ai-apply-submit'),
                onPressed: (canApply && !_applying)
                    ? () async {
                        setState(() => _applying = true);
                        try {
                          final applied = await controller.apply();
                          // Explicitly consumed: Err renders the
                          // code-keyed narrative (controller state); Ok
                          // renders the outcome summary card.
                          applied.match<void>((_) {}, (_) {});
                        } finally {
                          if (mounted) setState(() => _applying = false);
                        }
                      }
                    : null,
                child: _applying
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10nOf(context).aiApplySubmit),
              ),
              const SizedBox(height: 8),
              // The explicit episode re-pick (also the missing-context
              // path): the picker runs over the season's episodes from
              // the read DTOs — ids never guessed.
              TextButton(
                key: const Key('ai-apply-pick-episode'),
                onPressed: () async {
                  final picked = await showEpisodePicker(context, ref, jobId);
                  if (picked != null) {
                    controller.setContext(
                      AiJobContext(
                        episodeId: picked.id,
                        projectId: picked.projectId,
                      ),
                    );
                  }
                },
                child: Text(l10nOf(context).aiApplyPickEpisode),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The missing-context notice: apply stays DISABLED until an explicit
/// episode is picked (never dispatched with a guessed/empty episode_id).
class _EpisodePickerRequired extends StatelessWidget {
  const _EpisodePickerRequired();

  @override
  Widget build(BuildContext context) => ListTile(
    key: const Key('ai-apply-context-missing'),
    dense: true,
    leading: Icon(
      Icons.warning_amber_outlined,
      color: Theme.of(context).colorScheme.error,
    ),
    title: Text(l10nOf(context).aiApplyNoContextTitle),
    subtitle: Text(l10nOf(context).aiApplyNoContextSubtitle),
  );
}

/// The EU AI Act transparency panel (issue #608): reuses the dedicated
/// disclosure screen's copy keys (`aiDisclosureActTitle`/`aiDisclosureActBody`,
/// de/en) inside a collapsed-by-default `ExpansionTile` — compact review
/// section, always-visible expand affordance, zero new copy to translate.
class _AiActPanel extends StatelessWidget {
  const _AiActPanel();

  @override
  Widget build(BuildContext context) => ExpansionTile(
    key: const Key('ai-apply-act-panel'),
    tilePadding: EdgeInsets.zero,
    childrenPadding: const EdgeInsets.only(bottom: 8),
    leading: Icon(Icons.balance, color: Theme.of(context).colorScheme.tertiary),
    title: Text(l10nOf(context).aiDisclosureActTitle),
    subtitle: Text(
      l10nOf(context).aiDisclosureActBody,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(
          key: const Key('ai-apply-act-body'),
          l10nOf(context).aiDisclosureActBody,
        ),
      ),
    ],
  );
}

/// The 200 outcome summary (`applied_count`, `created_days`,
/// `planned_scene_shoots`) + deep navigation into the affected episode.
class _OutcomeCard extends StatelessWidget {
  const _OutcomeCard({required this.outcome});

  final ApplyAiImportResponse outcome;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        key: const Key('ai-apply-outcome'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          // A script apply that produced figures or costumes reports them
          // explicitly. The schedule wording stays the fallback, so a schedule
          // apply — and a pre-costume server that sends neither field — renders
          // exactly as before instead of showing invented counts.
          outcome.createdCharacters > 0 ||
                  outcome.createdCostumes > 0 ||
                  outcome.unappliedCostumes.isNotEmpty
              ? l10nOf(context).aiApplyOutcomeScript(
                  '${outcome.appliedCount}',
                  '${outcome.createdCharacters}',
                  '${outcome.createdCostumes}',
                )
              : l10nOf(context).aiApplyOutcome(
                  '${outcome.appliedCount}',
                  '${outcome.createdDays}',
                  '${outcome.plannedSceneShoots}',
                ),
        ),
      ),
      // Rows that did NOT become a `Costume` are named with their reason: a
      // partially applied row must never read as a fully applied one (spec
      // `costume-character-binding` — "report the row as partially applied with
      // the reason"). `reason` is a typed wire enum, so this copy is keyed on it
      // and never parsed out of server prose.
      for (final unapplied in outcome.unappliedCostumes)
        Text(
          key: Key(
            'ai-apply-unapplied-costume-${unapplied.draftRef}'
            '-${unapplied.ordinal}',
          ),
          l10nOf(context).aiApplyUnappliedCostume(
            unapplied.characterName,
            unapplied.description,
            aiUnappliedCostumeReasonCopy(l10nOf(context), unapplied.reason),
          ),
          style: TextStyle(
            color: Theme.of(context).colorScheme.error,
            fontSize: 12,
          ),
        ),
      const SizedBox(height: 12),
      OutlinedButton(
        key: const Key('ai-apply-open-episode'),
        onPressed: () {
          // The apply flow carries only the episode id (no BlockView
          // navigation context), so a deep push into the episode's
          // screens is not available here. Return to the AI-import jobs
          // list when it is on the stack (the standard entry — the user
          // can review the job or start the next import); only a preview
          // reached WITHOUT the jobs screen falls back to the app start.
          Navigator.of(context).popUntil(
            (route) => route.isFirst || route.settings.name == 'ai-import-jobs',
          );
        },
        child: Text(l10nOf(context).aiApplyBackToImports),
      ),
    ],
  );
}

/// The Update-target picker: the episode's existing scenes, ids + versions
/// straight from the read DTOs (never invented).
Future<SceneView?> showExistingScenePicker(
  BuildContext context,
  WidgetRef ref,
  String jobId,
) {
  final context_ = ref.read(aiApplyControllerProvider(jobId)).context;
  final episodeId = context_?.episodeId;
  if (episodeId == null) return Future<SceneView?>.value(null);
  return showModalBottomSheet<SceneView>(
    context: context,
    builder: (sheetContext) => Consumer(
      builder: (context, sheetRef, _) {
        final scenes = sheetRef.watch(scenesListFetchProvider(episodeId));
        return SafeArea(
          child: switch (scenes) {
            AsyncData(:final value) => value.match(
              (err) => ListTile(
                key: const Key('ai-scene-picker-error'),
                title: Text(l10nOf(context).aiScenePickerError(err.code)),
              ),
              (rows) => ListView(
                key: const Key('ai-scene-picker'),
                shrinkWrap: true,
                children: [
                  for (final scene in rows)
                    ListTile(
                      key: Key('ai-scene-pick-${scene.id}'),
                      title: Text(
                        scene.sceneNumber == null
                            ? scene.id
                            : l10nOf(context)
                                  .sceneTileLabel('${scene.sceneNumber}'),
                      ),
                      subtitle: Text(scene.summary ?? 'v${scene.version}'),
                      onTap: () => Navigator.of(sheetContext).pop(scene),
                    ),
                  if (rows.isEmpty)
                    ListTile(
                      key: const Key('ai-scene-picker-empty'),
                      title: Text(l10nOf(context).aiScenePickerEmpty),
                    ),
                ],
              ),
            ),
            _ => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          },
        );
      },
    ),
  );
}

/// The explicit episode picker (the missing-context → picker-required
/// path): the JOB'S BLOCK episodes, live-fetched from the read API — ids
/// never guessed, and the list never depends on what the user happened
/// to have visited before (the former cache-only read left fresh
/// installs with an empty picker, so the target episode could not be
/// assigned).
Future<EpisodeView?> showEpisodePicker(
  BuildContext context,
  WidgetRef ref,
  String jobId,
) {
  return showModalBottomSheet<EpisodeView>(
    context: context,
    builder: (sheetContext) => Consumer(
      builder: (context, sheetRef, _) {
        final episodes = sheetRef.watch(aiEpisodePickerRowsProvider(jobId));
        return SafeArea(
          child: SizedBox(
            height: 400,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(l10nOf(context).aiEpisodePickerTitle),
                ),
                Expanded(
                  child: switch (episodes) {
                    // Distinct loading/error branches (review): the
                    // empty-state copy ("open a production block first")
                    // is only TRUE for a successfully-loaded empty
                    // cache — a load failure must render its own state,
                    // never masquerade as guidance.
                    AsyncLoading() => const Center(
                      key: Key('ai-episode-picker-loading'),
                      child: CircularProgressIndicator(),
                    ),
                    AsyncError(:final error) => ListTile(
                      key: const Key('ai-episode-picker-error'),
                      title: Text(
                        l10nOf(context).aiEpisodePickerError(
                          error is ProblemError ? error.code : '$error',
                        ),
                      ),
                    ),
                    AsyncData(:final value) when value.isEmpty => ListTile(
                      key: const Key('ai-episode-picker-empty'),
                      title: Text(l10nOf(context).aiEpisodePickerEmpty),
                    ),
                    AsyncData(:final value) => ListView(
                      key: const Key('ai-episode-picker'),
                      children: [
                        for (final episode in value)
                          ListTile(
                            key: Key('ai-episode-pick-${episode.id}'),
                            title: Text(
                              l10nOf(context)
                                  .episodeTileLabel('${episode.number}'),
                            ),
                            subtitle: Text(episode.name ?? episode.id),
                            onTap: () =>
                                Navigator.of(sheetContext).pop(episode),
                          ),
                      ],
                    ),
                  },
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// The picker's rows for ONE job: the job's `block_id` scopes a LIVE
/// `GET /v1/episodes?block_id=…` fetch through the shared
/// [episodesListFetchProvider] seam (tests override it with a fake;
/// the `seasonId` family slot is unused by the fetch and passed empty).
/// A failed fetch falls back to the block's CACHED rows (offline-first,
/// retained-stale-rows pattern — a transient failure never renders as an
/// empty list while stale rows exist); only a failure with an empty cache
/// surfaces the error. A FAILED cache read surfaces as a picker error —
/// it is never mistaken for "the job has no block", which would fall back
/// to the cache-wide read and offer episodes OUTSIDE the job's block. The
/// cache-wide fallback runs only after a successful lookup establishes
/// that the job carries no `block_id`.
@riverpod
Future<List<EpisodeView>> aiEpisodePickerRows(Ref ref, String jobId) async {
  final db = ref.watch(cacheDatabaseProvider);
  final repo = ref.watch(aiImportRepositoryProvider);

  // The job's block scope from the identity-scoped cache row (the same
  // discipline as `aiJobContext` — never navigation state, never a
  // second projection lookup for the command payload; the picked id IS
  // the apply command's own `episode_id`).
  String sub = '';
  try {
    final session = await ref.read(authSessionControllerProvider.future);
    sub = session?.sub ?? '';
  } on Object {
    sub = '';
  }
  // A failed cache read is a picker ERROR, never a silent "no block":
  // treating it as block-less would widen the picker beyond the job's
  // block and let the apply payload reference a foreign episode.
  final jobRows = switch (await repo.readCached(sub)) {
    Right(:final value) => value,
    Left(:final value) => throw value,
  };
  String? blockId;
  for (final row in jobRows) {
    if (row.id == jobId) {
      blockId = row.blockId;
      break;
    }
  }

  // No block scope (a job id from an older build, or an un-cached job)
  // → the legacy cache-wide read.
  final scopedBlock = blockId;
  if (scopedBlock == null || scopedBlock.isEmpty) {
    return EpisodeCacheDao(db).readAllEpisodes();
  }

  final fetch = await ref.watch(
    episodesListFetchProvider(scopedBlock, '').future,
  );
  return fetch.match((err) async {
    final cached = await EpisodeCacheDao(db).readByBlock(scopedBlock);
    if (cached.isNotEmpty) return cached;
    // Empty cache → surface the failure code (the sheet's error branch).
    throw err;
  }, (rows) async => rows);
}

/// Localized copy for a costume row the apply could not finish, keyed on the
/// stable wire enum. `_ => commonUnknown` is forward-compat, not dead code: the
/// generated enum carries no `$default`, so a reason a future backend adds must
/// not take the whole outcome card down with it.
String aiUnappliedCostumeReasonCopy(
  AppLocalizations l10n,
  UnappliedCostumeReason reason,
) => switch (reason) {
  UnappliedCostumeReason.characterNotPlanned =>
    l10n.aiApplyUnappliedReasonCharacterNotPlanned,
  UnappliedCostumeReason.characterUnavailable =>
    l10n.aiApplyUnappliedReasonCharacterUnavailable,
  UnappliedCostumeReason.createRejected =>
    l10n.aiApplyUnappliedReasonCreateRejected,
  UnappliedCostumeReason.notesRejected =>
    l10n.aiApplyUnappliedReasonNotesRejected,
  UnappliedCostumeReason.bindingRejected =>
    l10n.aiApplyUnappliedReasonBindingRejected,
  UnappliedCostumeReason.beatRejected =>
    l10n.aiApplyUnappliedReasonBeatRejected,
  _ => l10n.commonUnknown,
};
