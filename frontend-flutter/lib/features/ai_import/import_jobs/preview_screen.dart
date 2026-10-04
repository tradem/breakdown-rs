// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)
// Co-authored-by: glm-5.3-flash (neuralwatt)
// Co-authored-by: deepseek-v4-flash (neuralwatt)

import 'dart:async';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:built_collection/built_collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/problem_error.dart';
import '../../../l10n/app_localizations_provider.dart';
import 'apply_controller.dart';
import 'apply_screen.dart';
import 'job_status_controller.dart';

/// The preview screen (`flutter-ai-import-workflow` task 4.1): typed
/// `AiImportPreviewResponse` / `AiPreviewPayload` rendering
/// (`kind`/`data`: script → `ScriptContext`, schedule →
/// `ShootingSchedule`, merged → `MergedPreview`).
///
/// D1 discipline: rows render FROM the typed payload — never retyped
/// DTOs, never silent coercion. An unknown future `kind` (the generated
/// oneOf rejects it) surfaces as the explicit degraded error card with
/// the stable `ai_import.preview_kind_unknown` code; a 404 (no preview)
/// is the explicit "no preview available" state with the path back to
/// the job's terminal status. No fabricated rows, ever.
class AiPreviewScreen extends ConsumerWidget {
  const AiPreviewScreen({required this.jobId, super.key});

  final String jobId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preview = ref.watch(aiPreviewProvider(jobId));

    return Scaffold(
      appBar: AppBar(title: Text(l10nOf(context).aiPreviewTitle)),
      body: ListView(
        key: const Key('ai-preview-screen'),
        padding: const EdgeInsets.all(16),
        children: [
          switch (preview) {
            AsyncData(:final value) => value.match(
              (err) => _DegradedCard(error: err),
              (response) => _TypedPreviewBody(jobId: jobId, response: response),
            ),
            AsyncError(:final error) => _DegradedCard(
              error: error is ProblemError
                  ? error
                  : ProblemError(code: 'unknown', detail: '$error'),
            ),
            _ => const SizedBox(
              key: Key('ai-preview-loading'),
              height: 48,
              child: Center(child: CircularProgressIndicator()),
            ),
          },
        ],
      ),
    );
  }
}

/// The degraded error card, keyed on the stable problem `code` — unknown
/// kinds, missing previews and transport faults each render their honest
/// state; nothing is guessed.
class _DegradedCard extends StatelessWidget {
  const _DegradedCard({required this.error});

  final ProblemError error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final degraded = error.code == 'ai_import.preview_kind_unknown';
    return Card(
      key: const Key('ai-preview-degraded'),
      color: degraded ? scheme.tertiaryContainer : scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (degraded)
              Text(
                key: const Key('ai-preview-kind-unknown'),
                l10nOf(context).aiPreviewKindUnknown,
              )
            else if (error.code == 'ai_import.preview_missing' ||
                error.status == 404)
              Text(
                key: const Key('ai-preview-missing'),
                l10nOf(context).aiPreviewMissing,
              )
            else
              Text(l10nOf(context).aiPreviewLoadError(error.code)),
          ],
        ),
      ),
    );
  }
}

/// The typed preview body: dispatches on the payload's `kind`/`data`
/// variant and renders rows from the typed DTOs. Also seeds the apply
/// controller with the actionable rows (verbatim `draft_ref`s).
class _TypedPreviewBody extends ConsumerStatefulWidget {
  const _TypedPreviewBody({required this.jobId, required this.response});

  final String jobId;
  final AiImportPreviewResponse response;

  @override
  ConsumerState<_TypedPreviewBody> createState() => _TypedPreviewBodyState();
}

class _TypedPreviewBodyState extends ConsumerState<_TypedPreviewBody> {
  /// The payload the apply rows were last seeded from. A provider
  /// refresh rebuilds this widget with a NEW response while Flutter
  /// reuses the element — the seed must follow the payload identity,
  /// otherwise `AiApplySection` builds mappings from stale `draft_ref`s
  /// and refreshed rows never reach the apply request.
  AiImportPreviewResponse? _seededResponse;

  @override
  Widget build(BuildContext context) {
    // The generated oneOf carries the variant object; `value` is
    // NULLABLE — a null means the variant never resolved, which is the
    // same honest "kind unknown" degradation as an unrecognized kind
    // (never an `as Object` throw during build).
    final dynamic value = widget.response.preview.oneOf.value;
    if (value == null) {
      return const _DegradedCard(
        error: ProblemError(code: 'ai_import.preview_kind_unknown'),
      );
    }
    final payload = value;

    // Seed the apply controller once per payload (idempotent); the rows
    // carry the payload's verbatim draft_refs and the persisted episode
    // context (design §2.3). Re-seeds when the payload changes (a
    // provider refresh reuses this element — the rows must follow).
    if (!identical(_seededResponse, widget.response)) {
      _seededResponse = widget.response;
      unawaited(() async {
        final context = await ref.read(
          aiJobContextProvider(widget.jobId).future,
        );
        if (!mounted) return;
        ref
            .read(aiApplyControllerProvider(widget.jobId).notifier)
            .seedRows(_actionableRows(this.context, payload), context);
      }());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // AI-extracted banner (EU AI Act Art. 50, issue #538): the AI
        // framing precedes every typed payload; the note states the honest
        // fact that the wire preview carries NO machine-verified confidence
        // values (`confidence` exists only on the applied provenance) —
        // per-row confidence chips would be fabricated, so none render.
        Container(
          key: const Key('ai-preview-ai-banner'),
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.tertiaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.smart_toy_outlined,
                    color: Theme.of(context).colorScheme.tertiary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      key: const Key('ai-preview-ai-banner-title'),
                      l10nOf(context).aiPreviewAiBanner,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                key: const Key('ai-preview-ai-banner-note'),
                l10nOf(context).aiPreviewAiNote,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        _payloadHeader(context, payload),
        const SizedBox(height: 12),
        // The apply action FIRST (issue #581 UX): the reviewer reaches the
        // dispatch — context/picker, per-group target summary, review
        // acknowledgement — without scrolling past the whole preview list.
        // The rows (with their per-group headers and selectors) follow
        // below; the per-group summary lines in the apply card keep the EU
        // AI Act gate intact at the dispatch point.
        AiApplySection(
          jobId: widget.jobId,
          // The reviewed payload identity: a provider refresh delivers a NEW
          // response at the same element position, so the acknowledgement
          // must not carry over to the replacement rows (#538).
          reviewToken: widget.response,
        ),
        const SizedBox(height: 24),
        ..._payloadRows(context, payload),
      ],
    );
  }

  Widget _payloadHeader(BuildContext context, Object payload) {
    final (title, subtitle) = _headerOf(context, payload);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          key: const Key('ai-preview-title'),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        if (subtitle.isNotEmpty)
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  (String, String) _headerOf(BuildContext context, Object payload) =>
      switch (payload) {
        AiPreviewPayloadOneOf() => (
          l10nOf(context).aiPreviewScriptTitle,
          l10nOf(context)
              .aiPreviewScriptSubtitle('${payload.data.scenes.length}'),
        ),
        AiPreviewPayloadOneOf1() => (
          l10nOf(context).aiPreviewScheduleTitle,
          l10nOf(context)
              .aiPreviewScheduleSubtitle('${payload.data.rows.length}'),
        ),
        AiPreviewPayloadOneOf2() => (
          l10nOf(context).aiPreviewMergedTitle,
          l10nOf(context)
              .aiPreviewMergedSubtitle('${payload.data.scenes.length}'),
        ),
        _ => (l10nOf(context).aiPreviewFallbackTitle, ''),
      };

  List<Widget> _payloadRows(
    BuildContext context,
    Object payload,
  ) => switch (payload) {
    // Script rows render GROUPED by their draft episode (issue #581): a
    // group header with the per-group target selector precedes the first
    // row of each group; unmarked rows render under the picked-target
    // header (the single-episode flow).
    AiPreviewPayloadOneOf() => [
      ..._scriptRowsGrouped(context, payload.data.scenes),
      for (final uncertainty in payload.data.uncertainties)
        // A costume the server dropped is reported here rather than vanishing:
        // the reviewer sees a MISSING entry with its reason slug
        // (`ungrounded_quote` / `unlisted_character`) instead of concluding the
        // script named no costuming. Its `kind` is `droppedRow`, which — unlike a
        // field ambiguity — does not block the apply (design D8), so it renders as
        // information, not as a gate error.
        //
        // The note is rendered verbatim, exactly like every other uncertainty:
        // it is server/model prose the client does not parse. The places where the
        // wire carries a typed reason (`UnappliedCostume.reason` on the apply
        // result) are where localized copy is keyed instead.
        _InfoRowCard(
          label: l10nOf(context)
              .aiPreviewUncertainty(uncertainty.field, uncertainty.note),
        ),
    ],
    AiPreviewPayloadOneOf1() => [
      // Pre-merge schedule rows are informative — the merge worker turns
      // them into actionable drafts; no decision chips on this shape.
      for (final row in payload.data.rows)
        _InfoRowCard(
          label: l10nOf(context).aiPreviewRowRef(
            row.rowRef,
            '${row.sceneNumber == null ? '' : 'Szene ${row.sceneNumber} · '}'
            '${row.shootingDayLabel ?? row.date?.toString() ?? l10nOf(context).aiPreviewUnscheduled}',
          ),
        ),
    ],
    AiPreviewPayloadOneOf2() => [
      for (final merged in payload.data.scenes)
        _PreviewRowCard(
          jobId: widget.jobId,
          draftRef: merged.scene.id,
          label: l10nOf(context).aiPreviewSceneWithSummary(
            '${merged.scene.sceneNumber ?? merged.scene.id}',
            '${merged.scene.summary == null ? '' : ' — ${merged.scene.summary}'}'
                '${l10nOf(context).aiPreviewScheduledRowCount('${merged.scheduleRows.length}')}',
          ),
        ),
      // Unmatched rows render as NON-actionable info cards — they are
      // excluded from the decisions and from one-tap accept-all (no
      // silent coercion into fabricated typed rows).
      for (final row in payload.data.unmatchedScheduleRows)
        _InfoRowCard(
          label: l10nOf(context).aiPreviewUnmatchedScheduleRow(row.rowRef),
        ),
      for (final scene in payload.data.unmatchedScriptScenes)
        _InfoRowCard(
          label: l10nOf(context).aiPreviewUnmatchedScriptScene(scene.id),
        ),
    ],
    _ => [_InfoRowCard(label: l10nOf(context).aiPreviewUnrecognizedShape)],
  };

  /// Script rows grouped by draft episode: a [_EpisodeGroupHeader] with the
  /// group's target selector is inserted before the first row of each
  /// group-run (document order — header repetitions in page headers are
  /// harmless, consecutive rows of one group cluster under one header).
  /// Rows without episode metadata cluster under the ungrouped header, which
  /// names the explicitly picked target episode — no selector there, the
  /// target lives in the apply card (the single-episode flow).
  List<Widget> _scriptRowsGrouped(
    BuildContext context,
    BuiltList<DraftScene> scenes,
  ) {
    final widgets = <Widget>[];
    String? lastRef;
    var isFirst = true;
    for (final scene in scenes) {
      final episode = scene.episode;
      final ref = episode == null ? null : draftEpisodeGroupRef(episode);
      if (isFirst || ref != lastRef) {
        lastRef = ref;
        isFirst = false;
        widgets.add(_EpisodeGroupHeader(jobId: widget.jobId, groupRef: ref));
      }
      widgets.add(
        _PreviewRowCard(
          jobId: widget.jobId,
          draftRef: scene.draftRef,
          label: l10nOf(context).aiPreviewSceneWithSummary(
            '${scene.sceneNumber ?? '?'}',
            scene.summary == null ? '' : ' — ${scene.summary}',
          ),
        ),
      );
    }
    return widgets;
  }

  /// The actionable rows (never the info cards): script scenes carry
  /// their `draft_ref`s; merged previews act on the merged scene ids.
  List<PreviewRow> _actionableRows(
    BuildContext context,
    Object payload,
  ) => switch (payload) {
    AiPreviewPayloadOneOf() => [
      for (final scene in payload.data.scenes)
        PreviewRow(
          draftRef: scene.draftRef,
          label: l10nOf(context).sceneTileLabel('${scene.sceneNumber ?? '?'}'),
          // The row's `Ep.:` marker (issue #581) — drives the group the row
          // belongs to and the pre-filled create-new target. `null` keeps the
          // single-episode flow.
          episode: scene.episode,
          // `costumes` is null on a preview stored before the field existed:
          // not a failure, just a row with nothing to decide.
          costumes: [
            for (final (index, costume)
                in (scene.costumes ?? <DraftCostume>[]).indexed)
              PreviewCostume(
                ordinal: index,
                characterName: costume.characterName,
                description: costume.description,
                sourceQuote: costume.sourceQuote,
              ),
          ],
        ),
    ],
    AiPreviewPayloadOneOf2() => [
      for (final merged in payload.data.scenes)
        PreviewRow(
          draftRef: merged.scene.id,
          label: l10nOf(context)
              .sceneTileLabel('${merged.scene.sceneNumber ?? merged.scene.id}'),
        ),
    ],
    // Pre-merge schedule previews expose no actionable drafts yet.
    _ => const <PreviewRow>[],
  };
}

/// One actionable preview row: the verbatim `draft_ref` with its decision
/// chips (Create / Update / skip).
class _PreviewRowCard extends ConsumerWidget {
  const _PreviewRowCard({
    required this.jobId,
    required this.draftRef,
    required this.label,
  });

  final String jobId;
  final String draftRef;
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(aiApplyControllerProvider(jobId));
    final controller = ref.read(aiApplyControllerProvider(jobId).notifier);
    RowDecision decision = const CreateDecision();
    for (final row in state.rows) {
      if (row.draftRef == draftRef) {
        decision = row.decision;
        break;
      }
    }
    return Card(
      key: Key('ai-preview-row-$draftRef'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              key: Key('ai-row-decision-$draftRef'),
              segments: [
                ButtonSegment(
                  value: 'create',
                  label: Text(l10nOf(context).aiPreviewCreate),
                ),
                ButtonSegment(
                  value: 'update',
                  label: Text(l10nOf(context).aiPreviewUpdate),
                ),
                ButtonSegment(
                  value: 'skip',
                  label: Text(l10nOf(context).aiPreviewSkip),
                ),
              ],
              selected: {
                switch (decision) {
                  UpdateDecision() => 'update',
                  SkipDecision() => 'skip',
                  _ => 'create',
                },
              },
              onSelectionChanged: (selection) async {
                switch (selection.first) {
                  case 'create':
                    controller.decide(draftRef, const CreateDecision());
                  case 'skip':
                    controller.decide(draftRef, const SkipDecision());
                  case 'update':
                    // The Update target is picked from the episode's
                    // existing aggregates (ids + versions from the read
                    // DTOs — never invented).
                    final picked = await showExistingScenePicker(
                      context,
                      ref,
                      jobId,
                    );
                    if (picked != null) {
                      controller.decide(
                        draftRef,
                        UpdateDecision(
                          aggregateId: picked.id,
                          version: picked.version,
                        ),
                      );
                    }
                }
              },
            ),
            if (decision is UpdateDecision)
              Text(
                key: Key('ai-preview-row-picked-$draftRef'),
                l10nOf(context).aiPreviewUpdatesScene(
                  decision.aggregateId,
                  '${decision.version}',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ..._costumeRows(context, state, controller),
          ],
        ),
      ),
    );
  }

  /// The row's extracted costumes, each individually acceptable/rejectable.
  ///
  /// The quoted source fragment is shown NEXT TO the description on purpose:
  /// the reviewer must be able to verify the extraction against the script
  /// without opening the document (spec `ai-import`), and the server's grounding
  /// check only proves the quote exists — whether it is the right garment is a
  /// human call.
  List<Widget> _costumeRows(
    BuildContext context,
    AiApplyState state,
    AiApplyController controller,
  ) {
    PreviewRow? matched;
    for (final candidate in state.rows) {
      if (candidate.draftRef == draftRef) {
        matched = candidate;
        break;
      }
    }
    final costumes = matched?.costumes ?? const <PreviewCostume>[];
    if (costumes.isEmpty) return const [];
    return [
      const SizedBox(height: 8),
      Text(
        key: Key('ai-preview-costume-heading-$draftRef'),
        l10nOf(context).aiPreviewCostumeHeading('${costumes.length}'),
        style: Theme.of(context).textTheme.labelLarge,
      ),
      for (final costume in costumes)
        Column(
          key: Key('ai-preview-costume-$draftRef-${costume.ordinal}'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Tooltip(
              message: l10nOf(context).aiPreviewCostumeToggleTooltip,
              child: CheckboxListTile(
                key: Key(
                  'ai-preview-costume-toggle-$draftRef-${costume.ordinal}',
                ),
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: costume.accepted,
                onChanged: (value) => controller.decideCostume(
                  draftRef,
                  costume.ordinal,
                  value ?? true,
                ),
                title: Text(
                  l10nOf(context).aiPreviewCostumeFor(
                    costume.characterName,
                    costume.description,
                  ),
                ),
                subtitle: Text(
                  // The quote is read-only evidence, never an editable value: it
                  // is what the server's grounding check verified against the
                  // chunk. Showing it NEXT TO the description is what lets the
                  // reviewer verify the extraction without opening the document
                  // (spec `ai-import`).
                  l10nOf(context).aiPreviewCostumeQuote(costume.sourceQuote),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
            if (!costume.accepted)
              Text(
                key: Key(
                  'ai-preview-costume-rejected-$draftRef-${costume.ordinal}',
                ),
                l10nOf(context).aiPreviewCostumeRejectedStatus,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
          ],
        ),
    ];
  }
}

/// The per-group episode header (issue #581). Grouped rows get the draft
/// episode label from the `Ep.:` marker, the group's CURRENT target, and the
/// change affordance. The ungrouped variant (`groupRef == null`) names the
/// explicitly picked target episode and offers NO selector — those rows
/// follow the apply card's single-episode target (the backward-compatible
/// flow).
class _EpisodeGroupHeader extends ConsumerWidget {
  const _EpisodeGroupHeader({required this.jobId, required this.groupRef});

  final String jobId;
  final String? groupRef;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(aiApplyControllerProvider(jobId));
    final ref_ = groupRef;
    if (ref_ == null) {
      final target = state.context?.episodeId;
      return _headerCard(
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
    return _headerCard(
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

  Widget _headerCard(
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
      final numberLabel = l10nOf(context).episodeTileLabel('${picked.number}');
      final name = picked.name?.trim();
      controller.setGroupTarget(
        groupRef,
        ExistingEpisodeGroupTarget(
          episodeId: picked.id,
          label: name == null || name.isEmpty
              ? numberLabel
              : '$numberLabel \u00b7 $name',
        ),
      );
    case 'create':
      final state = ref.read(aiApplyControllerProvider(jobId));
      final current = state.targetFor(groupRef);
      final initial = current is CreateEpisodeGroupTarget
          ? current
          : const CreateEpisodeGroupTarget();
      final result = await showGroupCreateDialog(context, initial: initial);
      if (result == null) return;
      controller.setGroupTarget(groupRef, result);
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
class _InfoRowCard extends StatelessWidget {
  const _InfoRowCard({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Card(
    key: const Key('ai-preview-info-row'),
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Text(label, style: Theme.of(context).textTheme.bodySmall),
    ),
  );
}
