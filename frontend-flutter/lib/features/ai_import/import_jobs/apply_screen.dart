// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)
// Co-authored-by: deepseek-v4-flash (neuralwatt)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
import 'job_status_controller.dart';

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
            const SizedBox(height: 8),
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
            else
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
            const SizedBox(height: 12),
            if (state.commandError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  key: const Key('ai-apply-error'),
                  aiApplyErrorCopy(l10nOf(context), state.commandError!),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (state.outcome != null)
              _OutcomeCard(outcome: state.outcome!)
            else ...[
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
                onPressed: canApply
                    ? () async {
                        final applied = await controller.apply();
                        // Explicitly consumed: Err renders the
                        // code-keyed narrative (controller state); Ok
                        // renders the outcome summary card.
                        applied.match<void>((_) {}, (_) {});
                      }
                    : null,
                child: Text(l10nOf(context).aiApplySubmit),
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
                        seriesId: picked.seriesId,
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
        final episodes = sheetRef.watch(_pickerEpisodesProvider(jobId));
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
/// surfaces the error. A job without a `block_id` falls back to the
/// identity-scoped cache read across blocks — the previous behavior.
final _pickerEpisodesProvider = FutureProvider.family<List<EpisodeView>, String>(
  (ref, jobId) async {
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
  final rows = await repo.readCached(sub);
  String? blockId;
  for (final row in rows.getRight().toNullable() ?? const []) {
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
  return fetch.match(
    (err) async {
      final cached = await EpisodeCacheDao(db).readByBlock(scopedBlock);
      if (cached.isNotEmpty) return cached;
      // Empty cache → surface the failure code (the sheet's error branch).
      throw err;
    },
    (rows) async => rows,
  );
}, name: 'aiEpisodePickerRows');

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
