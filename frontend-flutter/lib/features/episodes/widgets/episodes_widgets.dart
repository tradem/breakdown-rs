// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)
// Co-authored-by: space-bunny-free (opencode-go)
// Co-authored-by: deepseek-v4-flash (neuralwatt)

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations_provider.dart';
import '../episodes_state.dart';

/// Pure presentation trees for `EpisodesScreen`: plain data + callbacks in,
/// widgets out — no Riverpod imports, theme roles only, semantic labels for
/// `find.text`-paired tests.
class EpisodeTile extends StatelessWidget {
  const EpisodeTile({super.key, required this.row, this.onTap});

  final EpisodeRow row;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    String tileLabel(Object? number) => l10n.episodeTileLabel('$number');
    return switch (row) {
      ProjectedEpisodeRow(:final episode) => Semantics(
        label: tileLabel(episode.number),
        child: ListTile(
          key: Key('episode-${episode.id}'),
          minTileHeight: 48,
          title: Text(episode.name ?? tileLabel(episode.number)),
          subtitle: Text(l10n.episodeNumberPrefix(episode.number.toString())),
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
              : tileLabel(overlay.number),
        ),
        subtitle: Text(
          overlay.status == OverlayStatus.stale
              ? (overlay.warning ?? l10n.episodesTileSyncingStale)
              : l10n.episodesTileSyncing,
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
          l10nOf(context).episodesEmpty,
          key: const Key('episodes-empty'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (canCreate)
          FilledButton.tonal(
            key: const Key('episodes-empty-create'),
            onPressed: onCreate,
            child: Text(l10nOf(context).episodesCreateFirst),
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
          l10nOf(context).episodesNotFound(code),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        FilledButton.tonal(
          key: const Key('episodes-not-found-back'),
          onPressed: onBack,
          child: Text(l10nOf(context).episodesBackToBlocks),
        ),
      ],
    ),
  );
}
