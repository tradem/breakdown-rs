// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:flutter/material.dart';

import '../../../domain/reconciliation/reconciliation_scheduler.dart';
import '../episodes_state.dart';

/// Pure presentation trees for `EpisodesScreen`: plain data + callbacks in,
/// widgets out — no Riverpod imports, theme roles only, semantic labels for
/// `find.text`-paired tests.
class EpisodeTile extends StatelessWidget {
  const EpisodeTile({super.key, required this.row, this.onTap});

  final EpisodeRow row;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => switch (row) {
    ProjectedEpisodeRow(:final episode) => Semantics(
      label: 'Episode ${episode.number}',
      child: ListTile(
        key: Key('episode-${episode.id}'),
        minTileHeight: 48,
        title: Text(episode.name ?? 'Episode ${episode.number}'),
        subtitle: Text('Number ${episode.number}'),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    ),
    OptimisticEpisodeRow(:final overlay) => ListTile(
      key: Key('overlay-${overlay.id}'),
      minTileHeight: 48,
      title: Text(
        overlay.name?.isNotEmpty == true
            ? overlay.name!
            : 'Episode ${overlay.number ?? ''}',
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

class EpisodesEmptyView extends StatelessWidget {
  const EpisodesEmptyView({super.key, required this.canCreate, this.onCreate});

  final bool canCreate;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'No episodes yet',
          key: const Key('episodes-empty'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (canCreate)
          FilledButton.tonal(
            key: const Key('episodes-empty-create'),
            onPressed: onCreate,
            child: const Text('Create the first episode'),
          ),
      ],
    ),
  );
}

class EpisodesNotFoundView extends StatelessWidget {
  const EpisodesNotFoundView({super.key, required this.code, this.onBack});

  final String code;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      key: const Key('episodes-not-found'),
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.search_off, size: 48),
        const SizedBox(height: 8),
        Text(
          'This block no longer exists ($code).',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        FilledButton.tonal(
          key: const Key('episodes-not-found-back'),
          onPressed: onBack,
          child: const Text('Back to blocks'),
        ),
      ],
    ),
  );
}
