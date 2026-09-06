// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_providers.dart';
import '../characters/characters_controller.dart';
import '../costumes/widgets/costumes_widgets.dart';
import '../shooting_days/shooting_days_controller.dart';
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
              ? 'Scene'
              : (scene.summary?.isNotEmpty == true
                    ? scene.summary!
                    : 'Scene ${scene.sceneNumber ?? ''}'),
        ),
      ),
      body: scene == null
          ? const Center(
              child: CircularProgressIndicator(
                key: Key('scene-detail-loading'),
              ),
            )
          : RefreshIndicator(
              onRefresh: () => ref
                  .read(scenesControllerProvider(episodeId).notifier)
                  .refresh(),
              child: ListView(
                key: Key('scene-detail-$sceneId'),
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  _SceneSummary(scene: scene),
                  const SizedBox(height: 8),
                  _SceneCharactersSection(
                    seasonId: seasonId,
                    episodeId: episodeId,
                    scene: scene,
                  ),
                  const SizedBox(height: 8),
                  _SceneShootingDaysSection(
                    seasonId: seasonId,
                    episodeId: episodeId,
                    scene: scene,
                  ),
                ],
              ),
            ),
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
          if (scene.location case final location?) Text('Location: $location'),
          if (scene.mood case final mood?) Text('Mood: $mood'),
          if (scene.scriptDay case final day?) Text('Script day: $day'),
          Text(
            scene.isScheduleSet ? 'Scheduled' : 'Unscheduled',
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
    final assigned = scene.assignedCharacters.toList();

    return ExpansionTile(
      key: Key('scene-characters-${scene.id}'),
      initiallyExpanded: true,
      title: Text('Characters (${assigned.length})'),
      children: [
        if (assigned.isEmpty)
          const ListTile(
            key: Key('scene-characters-empty'),
            title: Text('No characters assigned yet.'),
          )
        else
          for (final id in assigned)
            ListTile(
              key: Key('scene-character-$id'),
              title: Text(names[id] ?? 'Unknown character'),
              trailing: IconButton(
                key: Key('scene-character-remove-$id'),
                icon: const Icon(Icons.person_remove_outlined),
                tooltip: 'Remove',
                // Confirm-first (destructive actions confirm-first, §5).
                onPressed: () => _confirmRemove(context, ref, id, names[id]),
              ),
            ),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.tonal(
            key: Key('scene-character-assign-${scene.id}'),
            onPressed: characters.rows.isEmpty
                ? null
                : () => _pickCharacter(context, ref, characters.rows),
            child: const Text('Assign character'),
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
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => AssignCharacterSheet(
        characters: [
          for (final c in characters)
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
      result.match(
        (err) =>
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(characterErrorCopy(err)))),
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
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove character?'),
        content: Text(
          '${name ?? 'This character'} is no longer scheduled for this scene.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
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
                result.match(
                  (err) => ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(content: Text(characterErrorCopy(err))),
                  ),
                  (_) {},
                );
              }
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
            },
            child: const Text('Remove'),
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
    final scheduled = scene.shootingDayIds.toList();
    final candidates = [
      for (final d in days.rows)
        if (!d.archived && !scheduled.contains(d.id)) d,
    ];

    return ExpansionTile(
      key: Key('scene-shooting-days-${scene.id}'),
      initiallyExpanded: true,
      title: Text('Shooting days (${scheduled.length})'),
      children: [
        if (scheduled.isEmpty)
          const ListTile(
            key: Key('scene-shooting-days-empty'),
            title: Text('Not scheduled on any shooting day yet.'),
          )
        else
          for (final id in scheduled)
            ListTile(
              key: Key('scene-shooting-day-$id'),
              title: Text(byId[id]?.label ?? 'Shooting day'),
              subtitle: byId[id]?.date != null
                  ? Text('Date: ${byId[id]!.date}')
                  : null,
              trailing: IconButton(
                key: Key('scene-shooting-day-unschedule-$id'),
                icon: const Icon(Icons.event_busy),
                tooltip: 'Unschedule',
                onPressed: () => _unschedule(context, ref, id),
              ),
            ),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.tonal(
            key: Key('scene-shooting-day-schedule-${scene.id}'),
            onPressed: candidates.isEmpty
                ? null
                : () => _pickDay(context, ref, candidates),
            child: const Text('Schedule on day'),
          ),
        ),
      ],
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
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Schedule on shooting day',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                    title: Text(d.label ?? 'Untitled day'),
                    subtitle: d.date != null ? Text('Date: ${d.date}') : null,
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
      result.match(
        (err) => ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(shootingDayErrorCopy(err)))),
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
      // was applied before the ack), conflict copy renders keyed on `code`;
      // no automatic version-bump re-dispatch.
      result.match(
        (err) => ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(shootingDayErrorCopy(err)))),
        (_) {},
      );
    }
  }
}
