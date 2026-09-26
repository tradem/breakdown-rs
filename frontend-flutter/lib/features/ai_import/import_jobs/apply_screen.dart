// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)
// Co-authored-by: deepseek-v4-flash (neuralwatt)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/problem_error.dart';
import '../../../data/cache/hierarchy_cache_dao.dart';
import '../../../l10n/app_localizations_provider.dart';
import '../../../data/cache/seasons_cache_providers.dart';
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
                  final picked = await showEpisodePicker(context, ref);
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
          l10nOf(context).aiApplyOutcome(
            '${outcome.appliedCount}',
            '${outcome.createdDays}',
            '${outcome.plannedSceneShoots}',
          ),
        ),
      ),
      const SizedBox(height: 12),
      OutlinedButton(
        key: const Key('ai-apply-open-episode'),
        onPressed: () {
          // The apply flow carries only the episode id (no BlockView
          // navigation context), so a deep push into the episode's
          // screens is not available here — the button is honest about
          // returning to the app start, where the episode is reachable
          // through the hierarchy navigation.
          Navigator.of(context).popUntil((route) => route.isFirst);
        },
        child: Text(l10nOf(context).aiApplyBackToStart),
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
/// path): episodes from the season's read DTOs — ids never guessed.
Future<EpisodeView?> showEpisodePicker(BuildContext context, WidgetRef ref) {
  // The picker lists the CACHED episodes of every block; the job's
  // remembered season (if any) scopes the read. Fresh-job AND
  // remembered-job entry both reach here (design §2.3).
  return showModalBottomSheet<EpisodeView>(
    context: context,
    builder: (sheetContext) => Consumer(
      builder: (context, sheetRef, _) {
        final episodes = sheetRef.watch(_cachedEpisodesProvider);
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

/// The cached episode rows across blocks (the picker's source): a pure
/// read-only Drift projection over `episode_cache_rows` — the picked
/// episode id becomes the apply command's own payload (`episode_id`),
/// never a second projection lookup for audit context (CQRS boundary).
final _cachedEpisodesProvider = FutureProvider<List<EpisodeView>>((ref) async {
  final db = ref.watch(cacheDatabaseProvider);
  // A read racing a sign-out clear renders an empty picker (the next
  // open re-reads) — no cross-identity rows are reachable because
  // SessionReset clears the table wholesale (identity-scoped, §3).
  return EpisodeCacheDao(db).readAllEpisodes();
}, name: 'aiEpisodePickerRows');
