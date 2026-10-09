// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: space-bunny (opencode-go)

import 'dart:async' show unawaited;

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations_provider.dart';
import '../scenes/scene_detail_screen.dart';
import '../scenes/season_script_controller.dart';
import 'planning_location.dart';
import 'profile_menu_button.dart';
import 'shell_controller.dart';
import 'view_states.dart';

/// The Script view (issue #610, destination 2): the active season's
/// chronological scene overview, continuously numbered.
///
/// The scene read model is episode-scoped (`GET /v1/scenes?episode_id=`),
/// so the season-wide list is composed client-side by
/// [seasonScriptFetchProvider] (blocks → episodes → scenes, read-only,
/// through the existing authenticated seams). A partially failed
/// composition renders the loaded scenes TOGETHER WITH a notice — the view
/// never presents a shortened script as the season's complete one.
///
/// Tapping a row pushes `SceneDetailScreen` with ids taken from the DTOs
/// the row was built from — the CQRS boundary is unchanged: no second
/// projection lookup fills them in.
class ScriptTabScreen extends ConsumerWidget {
  const ScriptTabScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = l10nOf(context);
    final season = ref.watch(shellControllerProvider).activeSeason;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.navScript),
        actions: const [ProfileMenuButton()],
      ),
      body: season == null
          ? const SeasonRequiredView(emptyKey: Key('script-no-season'))
          : _ScriptBody(season: season),
    );
  }
}

/// The season-script body: loading, error, partial, empty and data states
/// of the composed overview.
class _ScriptBody extends ConsumerWidget {
  const _ScriptBody({required this.season});

  final SeasonView season;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = l10nOf(context);
    final script = ref.watch(seasonScriptFetchProvider(season));
    return script.when(
      loading: () => const Center(
        child: CircularProgressIndicator(key: Key('script-loading')),
      ),
      error: (error, _) => ViewErrorState(
        errorKey: const Key('script-error'),
        message: l10n.scriptFetchError('$error'),
        onRetry: () => ref.invalidate(seasonScriptFetchProvider(season)),
      ),
      data: (result) => result.match(
        (error) => ViewErrorState(
          errorKey: const Key('script-error'),
          message: l10n.scriptFetchError(error.code),
          onRetry: () => ref.invalidate(seasonScriptFetchProvider(season)),
        ),
        (data) {
          // An empty script with no failure is the plain empty state; an
          // empty script WITH failures renders the partial notice — a
          // notice is never swallowed by the empty state (and vice versa).
          if (data.isEmpty && !data.isPartial) {
            return ViewEmptyState(
              emptyKey: const Key('script-empty'),
              message: l10n.scriptNoScenes,
              icon: Icons.menu_book_outlined,
            );
          }
          return RefreshIndicator(
            onRefresh: () =>
                ref.refresh(seasonScriptFetchProvider(season).future),
            child: ListView.builder(
              key: const Key('script-list'),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: data.rows.length + (data.isPartial ? 1 : 0),
              itemBuilder: (context, index) {
                if (data.isPartial && index == 0) {
                  return ViewPartialNotice(
                    noticeKey: const Key('script-partial-notice'),
                    message: l10n.scriptPartialLoad(data.failedEpisodes.length),
                  );
                }
                final rowIndex = index - (data.isPartial ? 1 : 0);
                return _ScriptRowTile(season: season, row: data.rows[rowIndex]);
              },
            ),
          );
        },
      ),
    );
  }
}

/// One scene row: the projected scene number as the visible label, the
/// scene summary as the title and the episode it belongs to as metadata.
class _ScriptRowTile extends StatelessWidget {
  const _ScriptRowTile({required this.season, required this.row});

  final SeasonView season;
  final ScriptSceneRow row;

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    final number = row.scene.sceneNumber;
    final summary = row.scene.summary;
    return ListTile(
      key: Key('script-scene-${row.scene.id}'),
      leading: CircleAvatar(child: Text(number == null ? '–' : '$number')),
      title: Text(
        summary == null || summary.isEmpty
            ? (number == null
                  ? l10n.scriptSceneNumberUnknown
                  : l10n.scriptSceneNumber(number))
            : summary,
      ),
      subtitle: Text(
        l10n.scriptEpisodeLabel(row.episode.name ?? '${row.episode.number}'),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _open(context),
    );
  }

  /// Pushes the scene detail with the hierarchy context chain the row was
  /// composed from (issue #548: the shell's location strip deepens through
  /// Season → Block → Episode → Scene).
  void _open(BuildContext context) {
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          settings: RouteSettings(
            arguments: PlanningLocation.scene(
              season,
              row.block,
              row.episode,
              row.scene,
            ),
          ),
          builder: (_) => SceneDetailScreen(
            seasonId: season.id,
            episodeId: row.episode.id,
            sceneId: row.scene.id,
          ),
        ),
      ),
    );
  }
}
