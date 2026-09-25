// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)
// Co-authored-by: glm-5.3-flash (neuralwatt)
// Co-authored-by: space-bunny-free (opencode-go)
// Co-authored-by: deepseek-v4-flash (neuralwatt)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_providers.dart';
import '../../core/problem_error.dart';
import '../../l10n/app_localizations_provider.dart';
import '../../l10n/generated/app_localizations.dart';
import '../scenes/scenes_screen.dart';
import '../shooting_days/shooting_days_screen.dart';
import 'create_episode_sheet.dart';
import 'episodes_controller.dart';
import 'episodes_state.dart';
import 'widgets/episodes_widgets.dart';

/// Localized client-side copy for a create-episode failure, keyed on the
/// stable problem `code` (never the server's localized `detail`).
String episodeCreateErrorCopy(AppLocalizations l10n, ProblemError error) =>
    switch (error.code) {
      // Real backend code first (issue #443); legacy aliases kept for
      // stale fixtures.
      'episode.number-already-exists' ||
      'episodes.conflict' ||
      'episode.conflict' => l10n.episodesCreateErrorExists,
      'authz.denied' || 'auth.session_required' => l10n.blocksCreateErrorSignIn,
      _ when error.code.startsWith('transport.') =>
        l10n.episodesCreateErrorNetwork,
      _ => l10n.episodesCreateErrorGeneric(error.code),
    };

/// `EpisodesScreen` — the tapped block's episodes via the server-side
/// filter (`GET /v1/episodes?block_id=…`, backend issue #335).
///
/// Pushed with the parent [BlockView] as navigation context; episode rows
/// push `ScenesScreen` with the `EpisodeView`.
class EpisodesScreen extends ConsumerWidget {
  const EpisodesScreen({super.key, required this.block});

  final BlockView block;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 7.2: sign-out mid-navigation returns to the login gate (see
    // BlocksScreen for the rationale).
    ref.listen(authSessionControllerProvider, (_, session) {
      final signedOut =
          (session is AsyncData && session.value == null) ||
          session is AsyncError;
      if (signedOut && context.mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    });
    final state = ref.watch(
      episodesControllerProvider(block.id, block.seasonId),
    );
    final controller = ref.read(
      episodesControllerProvider(block.id, block.seasonId).notifier,
    );
    final rows = state.rows;
    final notFound = state.notFound;
    final l10n = l10nOf(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.blockTileLabel('${block.number}'))),
      body: Column(
        children: [
          if (state.commandError case final error?)
            _Banner(
              key: const Key('episode-create-error-banner'),
              text: episodeCreateErrorCopy(l10n, error),
              onDismiss: controller.dismissCommandError,
            ),
          if (state.isStale && notFound == null)
            _Banner(
              key: const Key('episodes-stale-banner'),
              text: l10n.episodesStaleBanner,
            ),
          Expanded(
            child: notFound != null
                ? EpisodesNotFoundView(
                    code: notFound.code,
                    onBack: () => Navigator.of(context).pop(),
                  )
                : RefreshIndicator(
                    onRefresh: controller.refresh,
                    child: switch (state.projected) {
                      AsyncLoading() when rows.isEmpty => const Center(
                        child: CircularProgressIndicator(
                          key: Key('episodes-loading'),
                        ),
                      ),
                      AsyncError(:final error) when rows.isEmpty =>
                        _FetchErrorView(
                          code: error is ProblemError ? error.code : 'unknown',
                          onRetry: () => controller.refresh(),
                        ),
                      _ =>
                        rows.isEmpty
                            ? ListView(
                                key: const Key('episodes-list'),
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: [
                                  const SizedBox(height: 160),
                                  EpisodesEmptyView(
                                    canCreate: _canCreate(ref),
                                    onCreate: () => showCreateEpisodeSheet(
                                      context,
                                      ref,
                                      block,
                                    ),
                                  ),
                                ],
                              )
                            : ListView.builder(
                                key: const Key('episodes-list'),
                                physics: const AlwaysScrollableScrollPhysics(),
                                itemCount: rows.length,
                                itemBuilder: (context, i) {
                                  final row = rows[i];
                                  return Row(
                                    children: [
                                      Expanded(
                                        child: EpisodeTile(
                                          row: row,
                                          onTap: row is ProjectedEpisodeRow
                                              ? () => Navigator.of(context)
                                                    .push(
                                                      MaterialPageRoute<void>(
                                                        builder: (_) =>
                                                            ScenesScreen(
                                                              episode:
                                                                  row.episode,
                                                              seasonId: block
                                                                  .seasonId,
                                                            ),
                                                      ),
                                                    )
                                              : null,
                                        ),
                                      ),
                                      // Episode context entry (design §4):
                                      // shooting-days list for this episode.
                                      if (row is ProjectedEpisodeRow)
                                        IconButton(
                                          key: Key(
                                            'episode-shooting-days-${row.episode.id}',
                                          ),
                                          icon: const Icon(
                                            Icons.calendar_month_outlined,
                                          ),
                                          tooltip: l10n.navShootingDays,
                                          onPressed: () => Navigator.of(context)
                                              .push(
                                                MaterialPageRoute<void>(
                                                  builder: (_) =>
                                                      ShootingDaysScreen(
                                                        episode: row.episode,
                                                      ),
                                                ),
                                              ),
                                        ),
                                    ],
                                  );
                                },
                              ),
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: _canCreate(ref)
          ? FloatingActionButton(
              key: const Key('episode-add-fab'),
              onPressed: () => showCreateEpisodeSheet(context, ref, block),
              tooltip: l10n.episodesAddFab,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  bool _canCreate(WidgetRef ref) {
    final session = ref.watch(authSessionControllerProvider);
    return session is AsyncData && session.value != null;
  }
}

class _FetchErrorView extends StatelessWidget {
  const _FetchErrorView({required this.code, this.onRetry});

  final String code;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => ListView(
    key: const Key('episodes-error'),
    physics: const AlwaysScrollableScrollPhysics(),
    children: [
      const SizedBox(height: 160),
      Center(child: Text(l10nOf(context).episodesFetchError(code))),
      const SizedBox(height: 8),
      Center(
        child: FilledButton.tonal(
          key: const Key('episodes-retry'),
          onPressed: onRetry,
          child: Text(l10nOf(context).commonRetry),
        ),
      ),
    ],
  );
}

class _Banner extends StatelessWidget {
  const _Banner({super.key, required this.text, this.onDismiss});

  final String text;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
            if (onDismiss != null)
              IconButton(
                onPressed: onDismiss,
                color: scheme.onErrorContainer,
                tooltip: l10nOf(context).episodesDismiss,
                icon: const Icon(
                  Icons.close,
                  key: Key('episode-create-error-dismiss'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
