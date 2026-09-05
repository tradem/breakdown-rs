// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:flutter/material.dart';

import '../../../domain/reconciliation/reconciliation_scheduler.dart';
import '../scenes_state.dart';

/// Pure presentation trees for `ScenesScreen`: plain data + callbacks in,
/// widgets out — no Riverpod imports, theme roles only, semantic labels for
/// `find.text`-paired tests.
///
/// Scene detail data (mood, location, summary, script day, schedule flag,
/// character / shooting-day counts) renders read-only in Phase 1b.
class SceneTile extends StatelessWidget {
  const SceneTile({super.key, required this.row});

  final SceneRow row;

  @override
  Widget build(BuildContext context) => switch (row) {
    ProjectedSceneRow(:final scene) => Semantics(
      label: 'Scene ${scene.sceneNumber ?? scene.id}',
      child: ListTile(
        key: Key('scene-${scene.id}'),
        minTileHeight: 48,
        title: Text(
          scene.summary?.isNotEmpty == true
              ? scene.summary!
              : 'Scene ${scene.sceneNumber ?? ''}',
        ),
        subtitle: Text(
          [
            if (scene.mood case final mood?) 'Mood: $mood',
            if (scene.location case final location?) 'Loc: $location',
            if (scene.scriptDay case final day?) 'Day: $day',
            scene.isScheduleSet ? 'Scheduled' : 'Unscheduled',
            '${scene.assignedCharacters.length} characters',
            '${scene.shootingDayIds.length} shooting days',
          ].join(' · '),
        ),
      ),
    ),
    OptimisticSceneRow(:final overlay) => ListTile(
      key: Key('overlay-${overlay.id}'),
      minTileHeight: 48,
      title: Text(
        overlay.summary?.isNotEmpty == true
            ? overlay.summary!
            : 'Scene ${overlay.sceneNumber ?? ''}',
      ),
      subtitle: Text(
        overlay.status == OverlayStatus.stale
            ? (overlay.warning ?? kReconcileStaleWarning)
            : 'Just created — syncing…',
      ),
      trailing: overlay.status == OverlayStatus.stale
          ? const Icon(Icons.cloud_off, key: Key('overlay-warning'))
          : const SizedBox(
              key: Key('overlay-spinner'),
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
    ),
  };
}

class ScenesEmptyView extends StatelessWidget {
  const ScenesEmptyView({super.key, required this.canCreate, this.onCreate});

  final bool canCreate;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'No scenes yet',
          key: const Key('scenes-empty'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (canCreate)
          FilledButton.tonal(
            key: const Key('scenes-empty-create'),
            onPressed: onCreate,
            child: const Text('Create the first scene'),
          ),
      ],
    ),
  );
}

class ScenesNotFoundView extends StatelessWidget {
  const ScenesNotFoundView({super.key, required this.code, this.onBack});

  final String code;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      key: const Key('scenes-not-found'),
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.search_off, size: 48),
        const SizedBox(height: 8),
        Text(
          'This episode no longer exists ($code).',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        FilledButton.tonal(
          key: const Key('scenes-not-found-back'),
          onPressed: onBack,
          child: const Text('Back to episodes'),
        ),
      ],
    ),
  );
}
