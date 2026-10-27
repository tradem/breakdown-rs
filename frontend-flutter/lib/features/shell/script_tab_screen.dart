// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: space-bunny (opencode-go)
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)
// Co-authored-by: glm-5.3-flash (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

import 'dart:async' show unawaited;

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/active_episode.dart';
import '../../l10n/app_localizations_provider.dart';
import '../../l10n/generated/app_localizations.dart';
import '../scenes/scene_detail_screen.dart';
import '../scenes/season_script_controller.dart';
import 'planning_location.dart';
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
    final season = ref.watch(shellControllerProvider).activeSeason;

    return Scaffold(
      // Issue #638: no app bar — the shell's sticky view bar carries the
      // title and the search entry.
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
              itemCount: data.rows.length + _noticeCount(data),
              itemBuilder: (context, index) {
                // The notices sit ABOVE the rows: what is missing is stated
                // before what is present. A block whose episode read failed
                // and an episode whose scene read failed are counted at
                // their own level.
                if (index < _noticeCount(data)) {
                  final notice = index == 0 && data.failedBlocks.isNotEmpty
                      ? ViewPartialNotice(
                          noticeKey: const Key('script-partial-blocks-notice'),
                          message: l10n.scriptPartialBlocks(
                            data.failedBlocks.length,
                          ),
                        )
                      : ViewPartialNotice(
                          noticeKey: const Key('script-partial-notice'),
                          message: l10n.scriptPartialLoad(
                            data.failedEpisodes.length,
                          ),
                        );
                  return notice;
                }
                final rowIndex = index - _noticeCount(data);
                return _ScriptRowTile(season: season, row: data.rows[rowIndex]);
              },
            ),
          );
        },
      ),
    );
  }
}

/// One scene row (issue #709): the summary as the single-line ellipsized
/// title, the episode-then-scene-number identity followed by the metadata
/// (shooting day · location · characters · pieces) as the subtitle. The
/// leading avatar keeps the projected scene number (`–` when unnumbered).
class _ScriptRowTile extends ConsumerWidget {
  const _ScriptRowTile({required this.season, required this.row});

  final SeasonView season;
  final ScriptSceneRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        _metadata(l10n),
        // CodeRabbit #713: a default ListTile's subtitle is laid out for a
        // bounded height — an unconstrained long metadata line would wrap
        // into clipping on narrow screens. Two lines with an explicit
        // ellipsis policy keep the row tidy and the tail counts visible.
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _open(context, ref),
    );
  }

  /// The subtitle line (issue #709): episode before scene number, then
  /// shooting day · location · number of characters · number of pieces
  /// (distinct `pieceId`s across the beats — the same piece worn twice
  /// counts once). Absent optional fields (day, location) are omitted; the
  /// two counts always render, because "0 Figuren" is honest, actionable
  /// information for the piece department, not noise.
  String _metadata(AppLocalizations l10n) {
    final episodePart =
        row.episode.name ?? l10n.episodeTileLabel('${row.episode.number}');
    final number = row.scene.sceneNumber;
    final identity = number == null
        ? episodePart
        : l10n.scriptRowEpisodeScene(episodePart, number);
    final day = row.scene.scriptDay;
    final location = row.scene.location;
    final beats = row.scene.outfitBeats;
    final pieces = beats == null
        ? const <String>{}
        : {for (final beat in beats) beat.outfitId};
    return [
      identity,
      if (day != null && day.isNotEmpty) l10n.sceneDay(day),
      if (location != null && location.isNotEmpty) location,
      l10n.scriptRowCharacters(row.scene.assignedCharacters.length),
      l10n.scriptRowOutfits(pieces.length),
    ].join(' · ');
  }

  /// Pushes the scene detail with the hierarchy context chain the row was
  /// composed from (issue #548: the shell's location strip deepens through
  /// Season → Block → Episode → Scene).
  ///
  /// Issue #624: entering an episode's scene sets the sticky active-episode
  /// scope (from the row's acted-on DTOs — CQRS boundary) before the push.
  void _open(BuildContext context, WidgetRef ref) {
    ref
        .read(activeEpisodeProvider.notifier)
        .set(
          seasonId: season.id,
          blockId: row.block.id,
          episodeId: row.episode.id,
          episodeNumber: row.episode.number,
          episodeName: row.episode.name,
        );
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
            episode: row.episode,
            sceneId: row.scene.id,
          ),
        ),
      ),
    );
  }
}

/// How many partial-load notices precede the scene rows: one per failed
/// LEVEL (blocks, episodes) — never one per failure, and never zero when
/// something failed.
int _noticeCount(SeasonScript data) {
  var count = 0;
  if (data.failedBlocks.isNotEmpty) count++;
  if (data.failedEpisodes.isNotEmpty) count++;
  return count;
}
