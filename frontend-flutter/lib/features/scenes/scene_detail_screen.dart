// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: space-bunny-free (opencode-go)
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)
// Co-authored-by: deepseek-v4-flash (neuralwatt)
// Co-authored-by: qwen3.8-flash (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_providers.dart';
import '../../core/problem_error.dart';
import '../../design/components/ai_provenance_badge.dart';
import '../../design/material_icons.dart';
import '../../domain/ai_provenance.dart';
import '../../l10n/app_localizations_provider.dart';
import '../../l10n/generated/app_localizations.dart';
import '../characters/characters_controller.dart';
import '../costumes/costume_identity.dart';
import '../costumes/costumes_controller.dart';
import '../costumes/widgets/costumes_widgets.dart';
import '../scene_shoots/scene_shoots_screen.dart';
import '../shell/planning_location.dart';
import '../shooting_days/shooting_days_controller.dart';
import 'pick_costume_sheet.dart';
import 'scene_beats.dart';
import 'scenes_controller.dart';
import 'scenes_state.dart';

/// `SceneDetailScreen` — collapsible sections layout (design §4).
///
/// The Phase 1 scenes screen gains two sections here:
/// * **Characters** (5.2): assigned characters resolved from
///   `SceneView.assignedCharacters` ids via the characters projection
///   (read-DTO join only — never aggregate reconstruction); assign (picker
///   over the season's characters, scene `version` from the acted-on
///   `SceneView`) and unassign (DELETE), optimistic-after-2xx on the scene
///   row's id list.
/// * **Shooting days** (6.2): scheduled days from
///   `SceneView.shootingDayIds` via the episode's day projection; schedule
///   (picker over the parent episode's not-yet-archived days, scene
///   version echo) and unschedule (DELETE), optimistic-after-2xx.
///
/// Any Soll/Ist affordance is absent rather than stubbed (D6 — the
/// follow-up `flutter-shoot-day-execution` owns it).
///
/// Pushed with the navigation-stack context ([seasonId] + [episodeId] +
/// [sceneId]); all ids come from the read DTOs the user acted on (never a
/// second projection lookup to fill in command context — CQRS boundary).
class SceneDetailScreen extends ConsumerWidget {
  const SceneDetailScreen({
    super.key,
    required this.seasonId,
    required this.episodeId,
    required this.sceneId,
  });

  final String seasonId;
  final String episodeId;
  final String sceneId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(authSessionControllerProvider, (_, session) {
      final signedOut =
          (session is AsyncData && session.value == null) ||
          session is AsyncError;
      if (signedOut && context.mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    });
    final scenesState = ref.watch(scenesControllerProvider(episodeId));
    final scene = _resolveScene(scenesState);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          scene == null
              ? l10nOf(context).sceneDetailTitleFallback
              : (scene.summary?.isNotEmpty == true
                    ? scene.summary!
                    : l10nOf(context)
                          .sceneTileLabel('${scene.sceneNumber ?? ''}')),
        ),
      ),
      body: switch ((scene, scenesState.projected)) {
        // Resolved scene with its collapsible sections.
        (final s?, _) => RefreshIndicator(
          onRefresh: () =>
              ref.read(scenesControllerProvider(episodeId).notifier).refresh(),
          child: ListView(
            key: Key('scene-detail-$sceneId'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              _SceneSummary(scene: s),
              const SizedBox(height: 8),
              _SceneCharactersSection(
                seasonId: seasonId,
                episodeId: episodeId,
                scene: s,
              ),
              const SizedBox(height: 8),
              _SceneCostumesSection(
                seasonId: seasonId,
                episodeId: episodeId,
                scene: s,
              ),
              const SizedBox(height: 8),
              _SceneShootingDaysSection(
                seasonId: seasonId,
                episodeId: episodeId,
                scene: s,
              ),
            ],
          ),
        ),
        // First snapshot still in flight.
        (null, AsyncLoading()) => const Center(
          child: CircularProgressIndicator(key: Key('scene-detail-loading')),
        ),
        // Settled with an error and no retained row: retry affordance.
        (null, AsyncError(:final error)) => _SceneDetailErrorView(
          code: error is ProblemError ? error.code : 'unknown',
          onRetry: () =>
              ref.read(scenesControllerProvider(episodeId).notifier).refresh(),
        ),
        // Settled without the scene (deleted): unavailable, not a spinner.
        (null, _) => _SceneDetailGoneView(
          onBack: () => Navigator.of(context).pop(),
        ),
      },
    );
  }

  SceneView? _resolveScene(ScenesScreenState state) {
    for (final s in state.cachedRows) {
      if (s.id == sceneId) return s;
    }
    return null;
  }
}

class _SceneSummary extends StatelessWidget {
  const _SceneSummary({required this.scene});

  final SceneView scene;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (scene.location case final location?)
            Text(l10nOf(context).sceneLoc(location)),
          if (scene.mood case final mood?)
            Text(l10nOf(context).sceneMood(mood)),
          if (scene.scriptDay case final day?)
            Text(l10nOf(context).sceneDetailScriptDay(day)),
          Text(
            scene.isScheduleSet
                ? l10nOf(context).sceneScheduled
                : l10nOf(context).sceneUnscheduled,
            key: Key('scene-schedule-flag-${scene.id}'),
          ),
        ],
      ),
    ),
  );
}

/// Characters section: assigned list (read-DTO join) + assign/remove.
///
/// // AUTHZ-GATE: assign/unassign run the membership capability check
/// inside the characters controller before any network call.
class _SceneCharactersSection extends ConsumerWidget {
  const _SceneCharactersSection({
    required this.seasonId,
    required this.episodeId,
    required this.scene,
  });

  final String seasonId;
  final String episodeId;
  final SceneView scene;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final characters = ref.watch(charactersViewProvider(seasonId));
    final names = {for (final c in characters.rows) c.id: c.name};
    // Defensive dedup (issue #550): the read-model fan-out is fixed backend-
    // side, but a future regression must not render a contradictory screen —
    // count, row keys, and the picker filter all share one distinct list.
    final assigned = scene.assignedCharacters.toSet().toList();
    // Eligible picker candidates (mirrors `_pickCharacter`): the action
    // disables when everybody is already assigned.
    final assignable = assigned.toSet();
    final hasCandidates = characters.rows.any(
      (c) => !assignable.contains(c.id),
    );

    return ExpansionTile(
      key: Key('scene-characters-${scene.id}'),
      initiallyExpanded: true,
      title: Text(
        l10nOf(context).sceneDetailCharactersTitle('${assigned.length}'),
      ),
      children: [
        if (assigned.isEmpty)
          ListTile(
            key: const Key('scene-characters-empty'),
            title: Text(l10nOf(context).sceneDetailNoCharacters),
          )
        else
          for (final id in assigned)
            ListTile(
              key: Key('scene-character-$id'),
              title: Text(
                names[id] ?? l10nOf(context).sceneDetailUnknownCharacter,
              ),
              trailing: IconButton(
                key: Key('scene-character-remove-$id'),
                icon: const Icon(Icons.person_remove_outlined),
                tooltip: l10nOf(context).sceneDetailRemoveCharacterTooltip,
                // Confirm-first (destructive actions confirm-first, §5).
                onPressed: () => _confirmRemove(context, ref, id, names[id]),
              ),
            ),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.tonal(
            key: Key('scene-character-assign-${scene.id}'),
            onPressed: hasCandidates
                ? () => _pickCharacter(context, ref, characters.rows)
                : null,
            child: Text(l10nOf(context).sceneDetailAssignCharacter),
          ),
        ),
      ],
    );
  }

  Future<void> _pickCharacter(
    BuildContext context,
    WidgetRef ref,
    List<CharacterView> characters,
  ) async {
    // Only unassigned characters are eligible: re-picking an assigned one
    // would 409 (`CharacterAlreadyAssigned`) on a request the client can
    // see coming.
    final assigned = scene.assignedCharacters.toSet();
    final candidates = [
      for (final c in characters)
        if (!assigned.contains(c.id)) c,
    ];
    if (candidates.isEmpty) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => AssignCharacterSheet(
        characters: [
          for (final c in candidates)
            (
              id: c.id,
              name: c.name,
              category: serializers
                  .serializeWith(CharacterCategory.serializer, c.category)
                  .toString(),
            ),
        ],
        assignedId: null,
      ),
    );
    if (picked == null || !context.mounted) return;
    final result = await ref
        .read(charactersControllerProvider(seasonId).notifier)
        .assignToScene(
          sceneId: scene.id,
          sceneVersion: scene.version,
          characterId: picked,
        );
    if (result.isRight()) {
      // Optimistic-after-2xx on the scene row's id list: refresh the
      // scene projection so the assigned list reconciles.
      await ref.read(scenesControllerProvider(episodeId).notifier).refresh();
    } else if (context.mounted) {
      // Reconcile the version even on conflict: the next action must echo
      // the current projection version, not the rejected one. The command
      // itself is never re-dispatched automatically.
      await ref.read(scenesControllerProvider(episodeId).notifier).refresh();
      // Navigation or sign-out can unmount while the refresh is pending.
      if (!context.mounted) return;
      result.match(
        (err) => ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(characterErrorCopy(l10nOf(context), err))),
        ),
        (_) {},
      );
    }
  }

  Future<void> _confirmRemove(
    BuildContext context,
    WidgetRef ref,
    String characterId,
    String? name,
  ) {
    final l10n = l10nOf(context);
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.sceneDetailRemoveCharacterTitle),
        content: Text(
          l10n.sceneDetailRemoveCharacterMessage(
            name ?? l10n.sceneDetailThisCharacter,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            key: Key('scene-character-remove-confirm-$characterId'),
            onPressed: () async {
              final result = await ref
                  .read(charactersControllerProvider(seasonId).notifier)
                  .unassignFromScene(
                    sceneId: scene.id,
                    sceneVersion: scene.version,
                    characterId: characterId,
                  );
              // A failed command (non-2xx) leaves the projected id in place
              // — no local edit was made before the ack, so there is nothing
              // to roll back — and surfaces the error keyed on `code`.
              if (result.isRight()) {
                await ref
                    .read(scenesControllerProvider(episodeId).notifier)
                    .refresh();
              } else if (dialogContext.mounted) {
                await ref
                    .read(scenesControllerProvider(episodeId).notifier)
                    .refresh();
                if (!dialogContext.mounted) return;
                result.match(
                  (err) => ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(
                      content: Text(characterErrorCopy(l10nOf(context), err)),
                    ),
                  ),
                  (_) {},
                );
              }
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
            },
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
  }
}

/// Costumes section (issue #546): one row per (character, beat), grouped
/// in the characters' assignment order; multiple beats of a character
/// render as a change sequence (`Kostüm A → Kostüm B`). Common case stays
/// trivial: one row per character, no sequence editor, no drag-and-drop.
///
/// // AUTHZ-GATE: beat commands run the membership capability check inside
/// the scenes controller BEFORE any network call (same send-as-read story
/// as the costume-assign surface).
class _SceneCostumesSection extends ConsumerWidget {
  const _SceneCostumesSection({
    required this.seasonId,
    required this.episodeId,
    required this.scene,
  });

  final String seasonId;
  final String episodeId;
  final SceneView scene;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The costumes projection already serves plain read DTOs (the view
    // selector flattened the overlay rows) — no row unwrapping here.
    final costumeViews = ref.watch(costumesViewProvider(seasonId)).rows;
    final costumesById = {for (final c in costumeViews) c.id: c};
    final characters = ref.watch(charactersViewProvider(seasonId));
    final names = {for (final c in characters.rows) c.id: c.name};
    final groups = groupSceneBeats(
      assignedCharacters: scene.assignedCharacters,
      beats: scene.costumeBeats?.toList() ?? const [],
    );
    final totalBeats = [for (final g in groups) ...g.beats].length;
    // Ephemeral reconciliation indicator for this scene's optimistic
    // beat overlay (reconciling spinner / stale cloud-off + warning).
    final beatOverlay = ref
        .watch(scenesControllerProvider(episodeId))
        .beatOverlays
        .where((o) => o.id == scene.id)
        .firstOrNull;
    final l10n = l10nOf(context);

    return ExpansionTile(
      key: Key('scene-costumes-${scene.id}'),
      initiallyExpanded: true,
      title: Text(l10n.sceneDetailCostumesTitle('$totalBeats')),
      children: [
        if (scene.assignedCharacters.isEmpty)
          ListTile(
            key: const Key('scene-costumes-empty'),
            title: Text(l10n.sceneDetailNoCharacters),
          )
        else ...[
          for (final group in groups) ...[
            for (final beat in group.beats)
              _buildBeatTile(context, ref, group, beat, costumesById, l10n),
            if (group.beats.isEmpty)
              ListTile(
                key: Key('scene-costume-empty-${group.characterId}'),
                title: Text(l10n.sceneDetailNoCostumeInScene),
                trailing: FilledButton.tonal(
                  key: Key('scene-costume-assign-${group.characterId}'),
                  onPressed: () => _pickCostume(
                    context,
                    ref,
                    group.characterId,
                    names[group.characterId],
                    costumeViews,
                  ),
                  child: Text(l10n.sceneDetailAssignCostume),
                ),
              )
            else
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  key: Key('scene-costume-add-change-${group.characterId}'),
                  onPressed: () => _pickCostume(
                    context,
                    ref,
                    group.characterId,
                    names[group.characterId],
                    costumeViews,
                  ),
                  child: Text(l10n.sceneDetailAddChange),
                ),
              ),
          ],
          if (beatOverlay != null &&
              beatOverlay.status != OverlayStatus.acknowledged)
            ListTile(
              key: const Key('scene-costumes-overlay-status'),
              leading: beatOverlay.status == OverlayStatus.stale
                  ? const Icon(
                      Icons.cloud_off,
                      key: Key('scene-costumes-overlay-warning'),
                    )
                  : const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
              title: Text(beatOverlay.warning ?? l10n.reconcileStaleWarning),
            ),
        ],
      ],
    );
  }

  Widget _buildBeatTile(
    BuildContext context,
    WidgetRef ref,
    SceneBeatGroup group,
    SceneCostumeBeatView beat,
    Map<String, CostumeView> costumesById,
    AppLocalizations l10n,
  ) {
    final costume = costumesById[beat.costumeId];
    // Tile-identity discipline: the label NEVER comes from a random
    // detail — same helper as the costume grid tile, with the
    // backend-joined category name as the projection-miss fallback.
    final label = sceneBeatCostumeLabel(
      costume: costume,
      joinedCategoryName: beat.costumeCategoryName,
      genericFallback: l10n.costumeTileLabelFallback,
    );
    final iconCategory = sceneBeatCostumeCategory(
      costume: costume,
      joinedCategoryName: beat.costumeCategoryName,
    );
    return ListTile(
      key: Key('scene-costume-beat-${group.characterId}-${beat.order}'),
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (beat.order > 0)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(
                '→',
                key: Key(
                  'scene-costume-arrow-${group.characterId}-${beat.order}',
                ),
              ),
            ),
          Icon(BreakdownMaterialIcons.forCostumeCategory(iconCategory)),
        ],
      ),
      title: Text(label),
      subtitle: beat.note == null || beat.note!.isEmpty
          ? null
          : Text(beat.note!),
      trailing: IconButton(
        key: Key('scene-costume-remove-${group.characterId}-${beat.order}'),
        icon: const Icon(Icons.delete_outline),
        tooltip: l10n.sceneDetailRemoveCostumeTooltip,
        // Confirm-first (destructive actions confirm-first, §5).
        onPressed: () => _confirmRemove(context, ref, group, beat, label),
      ),
    );
  }

  Future<void> _pickCostume(
    BuildContext context,
    WidgetRef ref,
    String characterId,
    String? characterName,
    List<CostumeView> costumes,
  ) async {
    if (costumes.isEmpty) return;
    final picked = await showPickCostumeSheet(context, costumes);
    if (picked == null || !context.mounted) return;
    final pickedCostumeId = picked.costumeId;
    final costume = ref
        .read(costumesViewProvider(seasonId))
        .rows
        .where((c) => c.id == pickedCostumeId)
        .firstOrNull;
    final result = await ref
        .read(scenesControllerProvider(episodeId).notifier)
        .addCostumeBeat(
          seasonId: seasonId,
          scene: scene,
          characterId: characterId,
          costumeId: picked.costumeId,
          note: picked.note,
          characterName: characterName,
          costumeCategoryName: costume?.categoryName,
        );
    if (result.isRight()) return; // optimistic overlay + reconcile own the UI.
    if (!context.mounted) return;
    // Reconcile the version even on conflict: the next action must echo
    // the current projection version, not the rejected one. The command
    // itself is never re-dispatched automatically.
    await ref.read(scenesControllerProvider(episodeId).notifier).refresh();
    if (!context.mounted) return;
    result.match(
      (err) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(sceneBeatErrorCopy(l10nOf(context), err))),
      ),
      (_) {},
    );
  }

  Future<void> _confirmRemove(
    BuildContext context,
    WidgetRef ref,
    SceneBeatGroup group,
    SceneCostumeBeatView beat,
    String label,
  ) {
    final l10n = l10nOf(context);
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.sceneDetailRemoveCostumeTitle),
        content: Text(l10n.sceneDetailRemoveCostumeMessage(label)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            key: Key(
              'scene-costume-remove-confirm-'
              '${group.characterId}-${beat.order}',
            ),
            onPressed: () async {
              // The controller on this scene (the section is keyed to the
              // episode the scene belongs to).
              final controller = ref.read(
                scenesControllerProvider(episodeId).notifier,
              );
              // The only remaining beat IS the clear-all ("no costume in
              // this scene"); otherwise a single-beat removal.
              final result = group.beats.length <= 1
                  ? await controller.clearCostumeBeats(
                      seasonId: seasonId,
                      scene: scene,
                      characterId: group.characterId,
                    )
                  : await controller.removeCostumeBeat(
                      seasonId: seasonId,
                      scene: scene,
                      characterId: group.characterId,
                      order: beat.order,
                    );
              if (result.isRight()) {
                // Optimistic overlay + reconciliation own the UI.
              } else if (dialogContext.mounted) {
                await ref
                    .read(scenesControllerProvider(episodeId).notifier)
                    .refresh();
                if (!dialogContext.mounted) return;
                result.match(
                  (err) => ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(
                      content: Text(sceneBeatErrorCopy(l10nOf(context), err)),
                    ),
                  ),
                  (_) {},
                );
              }
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
            },
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
  }
}

/// Shooting-days section: scheduled list (read-DTO join) + schedule/
/// unschedule pickers over the parent episode's not-yet-archived days.
class _SceneShootingDaysSection extends ConsumerWidget {
  const _SceneShootingDaysSection({
    required this.seasonId,
    required this.episodeId,
    required this.scene,
  });

  final String seasonId;
  final String episodeId;
  final SceneView scene;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final days = ref.watch(shootingDaysViewProvider(episodeId));
    final byId = {for (final d in days.rows) d.id: d};
    // Defensive dedup (issue #550): a duplicated id would inflate the header
    // count and render the day twice while the set-based picker filter saw no
    // candidate — count, list, and picker share one distinct list.
    final scheduled = scene.shootingDayIds.toSet().toList();
    final candidates = [
      for (final d in days.rows)
        if (!d.archived && !scheduled.contains(d.id)) d,
    ];

    return ExpansionTile(
      key: Key('scene-shooting-days-${scene.id}'),
      initiallyExpanded: true,
      title: Text(
        l10nOf(context).sceneDetailShootingDaysTitle('${scheduled.length}'),
      ),
      children: [
        if (scheduled.isEmpty)
          ListTile(
            key: const Key('scene-shooting-days-empty'),
            title: Text(l10nOf(context).sceneDetailNoShootingDays),
            // Report provenance (issue #549): the reports entry lives on the
            // day board, and the day board is reachable only from a
            // scheduled day — so a 0-day scene showed no reports affordance
            // and no reason to expect one. The hint NAMES what becomes
            // available once a day is planned. It invents no report and adds
            // no season-level entry: the report routes are day-scoped in the
            // contract itself, so this stays copy, not an affordance that
            // leads nowhere (`flutter-reports-screen`,
            // Report-Provenance Empty State).
            subtitle: Text(l10nOf(context).sceneDetailNoShootingDaysReportHint),
          )
        else
          for (final id in scheduled)
            ListTile(
              key: Key('scene-shooting-day-$id'),
              // Provenance badge keyed like the day list #538 — the
              // scheduled read-DTO join renders the day's wire source.
              title: switch (byId[id] == null
                  ? AiProvenanceVariant.absent
                  : dayProvenance(byId[id]!.source_)) {
                AiProvenanceVariant.aiExtracted => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AiProvenanceBadge(semanticKey: 'shooting-day-ai-badge-$id'),
                    Flexible(
                      child: Text(
                        byId[id]?.label ??
                            l10nOf(context).sceneShootDayFallback,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                _ => Text(
                  byId[id]?.label ?? l10nOf(context).sceneShootDayFallback,
                ),
              },
              subtitle: byId[id]?.date != null
                  ? Text(l10nOf(context).shootingDayDate('${byId[id]!.date}'))
                  : null,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Day-board entry (`flutter-shoot-day-execution` 2.1):
                  // opens the Soll/Ist execution board with the acted-on
                  // day + scene DTOs (never a second projection lookup).
                  // Gherkin contract key (`open-day-board-<day>`) for the
                  // shoot-day execution critical scenarios.
                  IconButton(
                    key: Key('open-day-board-$id'),
                    icon: const Icon(Icons.view_agenda_outlined),
                    tooltip: l10nOf(context).sceneDetailOpenDayBoard,
                    onPressed: byId[id] == null
                        ? null
                        : () => _openBoard(context, byId[id]!),
                  ),
                  IconButton(
                    key: Key('scene-shooting-day-unschedule-$id'),
                    icon: const Icon(Icons.event_busy),
                    tooltip: l10nOf(context).shootingDayUnscheduleButton,
                    onPressed: () => _unschedule(context, ref, id),
                  ),
                ],
              ),
            ),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.tonal(
            key: Key('scene-shooting-day-schedule-${scene.id}'),
            onPressed: candidates.isEmpty
                ? null
                : () => _pickDay(context, ref, candidates),
            child: Text(l10nOf(context).sceneDetailScheduleOnDay),
          ),
        ),
      ],
    );
  }

  void _openBoard(BuildContext context, ShootingDayView day) {
    // Fire-and-forget navigation (route push has no consumable result).
    // Issue #548: the day board rides on the SAME scene-level location
    // chain (from the route arguments) — display context only, the screen
    // keeps resolving its scene from the acted-on ids.
    final location = locationFromArguments(
      ModalRoute.of(context)?.settings.arguments,
    );
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          settings: RouteSettings(
            arguments: location is SceneLocation ? location : null,
          ),
          builder: (_) =>
              SceneShootsScreen(day: day, scene: scene, seasonId: seasonId),
        ),
      ),
    );
  }

  Future<void> _pickDay(
    BuildContext context,
    WidgetRef ref,
    List<ShootingDayView> candidates,
  ) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l10nOf(context).sceneDetailScheduleTitle,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: candidates.length,
                itemBuilder: (context, i) {
                  final d = candidates[i];
                  return ListTile(
                    key: Key('schedule-day-${d.id}'),
                    // Day picker provenance badge (issue #538): the picker
                    // carries the same AI framing as the day list.
                    title: switch (dayProvenance(d.source_)) {
                      AiProvenanceVariant.aiExtracted => Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AiProvenanceBadge(
                            semanticKey: 'shooting-day-ai-badge-${d.id}',
                          ),
                          Flexible(
                            child: Text(
                              d.label ?? l10nOf(context).shootingDayUntitled,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      _ => Text(d.label ?? l10nOf(context).shootingDayUntitled),
                    },
                    subtitle: d.date != null
                        ? Text(l10nOf(context).shootingDayDate('${d.date}'))
                        : null,
                    onTap: () => Navigator.of(context).pop(d.id),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (picked == null || !context.mounted) return;
    final result = await ref
        .read(shootingDaysControllerProvider(episodeId).notifier)
        .scheduleScene(
          sceneId: scene.id,
          sceneVersion: scene.version,
          shootingDayId: picked,
        );
    if (result.isRight()) {
      // Optimistic-after-2xx on the scene row's id list.
      await ref.read(scenesControllerProvider(episodeId).notifier).refresh();
    } else if (context.mounted) {
      // Reconcile the version even on conflict (never re-dispatch).
      await ref.read(scenesControllerProvider(episodeId).notifier).refresh();
      // Navigation or sign-out can unmount while the refresh is pending.
      if (!context.mounted) return;
      result.match(
        (err) => ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(shootingDayErrorCopy(l10nOf(context), err))),
        ),
        (_) {},
      );
    }
  }

  Future<void> _unschedule(
    BuildContext context,
    WidgetRef ref,
    String shootingDayId,
  ) async {
    final result = await ref
        .read(shootingDaysControllerProvider(episodeId).notifier)
        .unscheduleScene(
          sceneId: scene.id,
          sceneVersion: scene.version,
          shootingDayId: shootingDayId,
        );
    if (result.isRight()) {
      await ref.read(scenesControllerProvider(episodeId).notifier).refresh();
    } else if (context.mounted) {
      // 409 (scene changed elsewhere): the local edit rolls back (nothing
      // was applied before the ack), the projection refreshes so the next
      // action echoes the current version, and conflict copy renders keyed
      // on `code`; no automatic version bump re-dispatch.
      await ref.read(scenesControllerProvider(episodeId).notifier).refresh();
      if (!context.mounted) return;
      result.match(
        (err) => ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(shootingDayErrorCopy(l10nOf(context), err))),
        ),
        (_) {},
      );
    }
  }
}

class _SceneDetailErrorView extends StatelessWidget {
  const _SceneDetailErrorView({required this.code, this.onRetry});

  final String code;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10nOf(context).sceneDetailFetchError(code),
          key: const Key('scene-detail-error'),
        ),
        const SizedBox(height: 8),
        FilledButton.tonal(
          key: const Key('scene-detail-retry'),
          onPressed: onRetry,
          child: Text(l10nOf(context).commonRetry),
        ),
      ],
    ),
  );
}

class _SceneDetailGoneView extends StatelessWidget {
  const _SceneDetailGoneView({this.onBack});

  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10nOf(context).sceneDetailGone,
          key: const Key('scene-detail-gone'),
        ),
        if (onBack != null)
          FilledButton.tonal(
            onPressed: onBack,
            child: Text(l10nOf(context).commonBack),
          ),
      ],
    ),
  );
}
