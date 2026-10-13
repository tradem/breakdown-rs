// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/active_episode.dart';
import '../../l10n/app_localizations_provider.dart';
import '../blocks/active_block_gate.dart';
import '../episodes/episodes_controller.dart';
import 'planning_location.dart';

/// The episode scope chip (issue #624): says WHICH EPISODE the shell's
/// quick-create entries act on.
///
/// Separate from the block chip by lifetime: the block scope is the sticky
/// request filter (`X-Active-Block`); the episode scope is the sticky
/// create/context target. Both are per-season and persisted.
///
/// Arms:
/// - **no scope** → hidden (`SizedBox.shrink`);
/// - **scoped** → `Episode {n}` (the acted-on name wins when present);
/// - **foreign season** (the scope's season differs from the navigated
///   season in [location]) → the chip says so instead of presenting the
///   foreign episode as if it applied.
///
/// // AUTHZ-GATE: the chip is display + navigation only — it dispatches no
/// command and performs no network call itself (the picker's own read is an
/// `Authenticated` list fetch), so it needs no membership check.
class ActiveEpisodeChip extends ConsumerWidget {
  const ActiveEpisodeChip({
    super.key,
    required this.onOpenPicker,
    this.location,
  });

  /// The active tab's location — only used for the foreign-season check.
  final PlanningLocation? location;

  /// Opens the episode picker for the scope's block (injected so the chip
  /// stays a leaf widget the tests can pump standalone).
  final void Function(String seasonId, String blockId) onOpenPicker;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(activeEpisodeProvider);
    if (scope == null) return const SizedBox.shrink();

    final l10n = l10nOf(context);
    final foreign = location != null && location!.seasonId != scope.seasonId;
    final label = foreign
        ? l10n.scopeChipForeignSeason
        : (scope.episodeName ??
              l10n.episodeTileLabel('${scope.episodeNumber}'));

    return ActionChip(
      key: const Key('active-episode-chip'),
      avatar: Icon(
        Icons.movie_creation_outlined,
        size: 18,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      label: Text(label),
      tooltip: l10n.episodeChipTooltip,
      onPressed: () => onOpenPicker(scope.seasonId, scope.blockId),
    );
  }
}

/// The chip's episode picker: resolves the scope block's episodes through
/// the SAME seam the episodes screen uses (`episodesListFetchProvider`) and
/// sets the sticky scope from the acted-on `EpisodeView` on pick (CQRS
/// boundary — the DTO the user acted on, never a second lookup), then pops.
class EpisodeScopePickerScreen extends ConsumerWidget {
  const EpisodeScopePickerScreen({
    super.key,
    required this.seasonId,
    required this.blockId,
  });

  final String seasonId;
  final String blockId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = l10nOf(context);
    final fetch = ref.watch(episodesListFetchProvider(blockId, seasonId));
    return switch (fetch) {
      AsyncLoading() => BlockScopeLoadingScaffold(
        title: l10n.episodeChipPickTitle,
      ),
      AsyncError(:final error) => BlockScopeErrorScaffold(
        title: l10n.episodeChipPickTitle,
        code: blockScopeErrorCode(error),
        onRetry: () =>
            ref.invalidate(episodesListFetchProvider(blockId, seasonId)),
      ),
      AsyncData(:final value) => value.match(
        (err) => BlockScopeErrorScaffold(
          title: l10n.episodeChipPickTitle,
          code: err.code,
          onRetry: () =>
              ref.invalidate(episodesListFetchProvider(blockId, seasonId)),
        ),
        (rows) => _EpisodePickerScaffold(
          seasonId: seasonId,
          blockId: blockId,
          episodes: rows,
        ),
      ),
    };
  }
}

class _EpisodePickerScaffold extends ConsumerWidget {
  const _EpisodePickerScaffold({
    required this.seasonId,
    required this.blockId,
    required this.episodes,
  });

  final String seasonId;
  final String blockId;
  final List<EpisodeView> episodes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = l10nOf(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.episodeChipPickTitle)),
      body: episodes.isEmpty
          ? Center(
              child: Text(
                l10n.episodeChipEmpty,
                key: const Key('episode-scope-empty'),
                textAlign: TextAlign.center,
              ),
            )
          : ListView.builder(
              key: const Key('episode-scope-picker'),
              itemCount: episodes.length,
              itemBuilder: (context, i) {
                final episode = episodes[i];
                return ListTile(
                  key: Key('episode-scope-pick-${episode.id}'),
                  title: Text(
                    episode.name ?? l10n.episodeTileLabel('${episode.number}'),
                  ),
                  subtitle: episode.name == null
                      ? null
                      : Text(l10n.episodeTileLabel('${episode.number}')),
                  onTap: () {
                    ref
                        .read(activeEpisodeProvider.notifier)
                        .set(
                          seasonId: seasonId,
                          blockId: blockId,
                          episodeId: episode.id,
                          episodeNumber: episode.number,
                          episodeName: episode.name,
                        );
                    Navigator.of(context).pop();
                  },
                );
              },
            ),
    );
  }
}
