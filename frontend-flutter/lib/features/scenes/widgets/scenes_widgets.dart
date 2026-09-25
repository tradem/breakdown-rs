// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)
// Co-authored-by: space-bunny-free (opencode-go)
// Co-authored-by: deepseek-v4-flash (neuralwatt)

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations_provider.dart';
import '../scenes_state.dart';

/// Pure presentation trees for `ScenesScreen`: plain data + callbacks in,
/// widgets out — no Riverpod imports, theme roles only, semantic labels for
/// `find.text`-paired tests.
///
/// Scene detail data (mood, location, summary, script day, schedule flag,
/// character / shooting-day counts) renders read-only in Phase 1b.
class SceneTile extends StatelessWidget {
  const SceneTile({super.key, required this.row, this.onTap});

  final SceneRow row;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    String tileLabel(Object? identifier) => l10n.sceneTileLabel('$identifier');
    return switch (row) {
      ProjectedSceneRow(:final scene) => Semantics(
        label: tileLabel(scene.sceneNumber ?? scene.id),
        child: ListTile(
          key: Key('scene-${scene.id}'),
          onTap: onTap,
          minTileHeight: 48,
          title: Text(
            scene.summary?.isNotEmpty == true
                ? scene.summary!
                : tileLabel(scene.sceneNumber),
          ),
          subtitle: Text(
            [
              if (scene.mood case final mood?) l10n.sceneMood(mood),
              if (scene.location case final location?) l10n.sceneLoc(location),
              if (scene.scriptDay case final day?) l10n.sceneDay(day),
              scene.isScheduleSet ? l10n.sceneScheduled : l10n.sceneUnscheduled,
              l10n.sceneCharacterCount('${scene.assignedCharacters.length}'),
              l10n.sceneShootingDayCount('${scene.shootingDayIds.length}'),
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
              : tileLabel(overlay.sceneNumber),
        ),
        subtitle: Text(
          overlay.status == OverlayStatus.stale
              ? (overlay.warning ?? l10n.scenesTileSyncingStale)
              : l10n.scenesTileSyncing,
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
          l10nOf(context).scenesEmpty,
          key: const Key('scenes-empty'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (canCreate)
          FilledButton.tonal(
            key: const Key('scenes-empty-create'),
            onPressed: onCreate,
            child: Text(l10nOf(context).scenesCreateFirst),
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
        Text(l10nOf(context).scenesNotFound(code), textAlign: TextAlign.center),
        const SizedBox(height: 8),
        FilledButton.tonal(
          key: const Key('scenes-not-found-back'),
          onPressed: onBack,
          child: Text(l10nOf(context).scenesBackToEpisodes),
        ),
      ],
    ),
  );
}
