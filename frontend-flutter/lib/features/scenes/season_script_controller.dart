// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: space-bunny (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:fpdart/fpdart.dart';
import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../auth/active_block.dart';
import '../../core/problem_error.dart';
import '../../core/result.dart';
import '../blocks/blocks_controller.dart';
import '../episodes/episodes_controller.dart';
import 'scenes_controller.dart';

part 'season_script_controller.g.dart';

/// One episode's contribution to the season-wide script: the scenes read for
/// it together with the hierarchy DTOs the row label and the detail push
/// need. Keeping the parent DTOs here is the CQRS boundary — the Script view
/// never re-reads block/episode projections to fill in navigation context.
@immutable
class ScriptEpisodePart {
  const ScriptEpisodePart({
    required this.block,
    required this.episode,
    required this.scenes,
  });

  final BlockView block;
  final EpisodeView episode;
  final List<SceneView> scenes;
}

/// One row of the chronological script: a scene plus the DTOs the row label
/// and the scene-detail push consume.
@immutable
class ScriptSceneRow {
  const ScriptSceneRow({
    required this.scene,
    required this.block,
    required this.episode,
  });

  final SceneView scene;
  final BlockView block;
  final EpisodeView episode;
}

/// The season-wide script composition (issue #610, view "Script").
///
/// [rows] is the merged, `scene_number`-ordered overview. [failedEpisodes]
/// names the episodes whose scenes could NOT be read and [failedBlocks] the
/// blocks whose EPISODE list could not be read (everything below such a
/// block is unknown, not empty) — the honest degradation signal at BOTH
/// levels of the composition: a partially loaded script is rendered with a
/// notice, never silently presented as the season's complete script.
@immutable
class SeasonScript {
  const SeasonScript({
    required this.rows,
    this.failedEpisodes = const [],
    this.failedBlocks = const [],
  });

  const SeasonScript.empty()
    : rows = const [],
      failedEpisodes = const [],
      failedBlocks = const [];

  final List<ScriptSceneRow> rows;

  /// Ids of the episodes whose scene read failed.
  final List<String> failedEpisodes;

  /// Ids of the blocks whose episode read failed. Tracked at its own level:
  /// the scenes below such a block are UNKNOWN, not empty, and block ids
  /// must not be counted as episodes the user never saw.
  final List<String> failedBlocks;

  bool get isPartial => failedEpisodes.isNotEmpty || failedBlocks.isNotEmpty;

  bool get isEmpty => rows.isEmpty;
}

/// Merges the per-episode parts into one chronological overview.
///
/// Pure and side-effect free (unit-tested directly, no Riverpod container):
/// scenes sort by their projected `scene_number`, with the episode number as
/// the stable tie-breaker so two scenes sharing a number (a projector race
/// the server resolves on the next refresh) keep a deterministic order. A
/// scene without a projected number sorts last rather than first — an
/// unnumbered scene must not jump the queue of the numbered script.
List<ScriptSceneRow> mergeScriptParts(Iterable<ScriptEpisodePart> parts) {
  final rows = <ScriptSceneRow>[
    for (final part in parts)
      for (final scene in part.scenes)
        ScriptSceneRow(scene: scene, block: part.block, episode: part.episode),
  ];
  rows.sort((a, b) {
    final an = a.scene.sceneNumber;
    final bn = b.scene.sceneNumber;
    if (an == null && bn == null) {
      return a.episode.number.compareTo(b.episode.number);
    }
    if (an == null) return 1;
    if (bn == null) return -1;
    if (an != bn) return an.compareTo(bn);
    return a.episode.number.compareTo(b.episode.number);
  });
  return rows;
}

/// Composes the active season's chronological script view (issue #610).
///
/// The scene read model is episode-scoped (`GET /v1/scenes` requires
/// `episode_id`), so the season-wide overview is a READ-ONLY client
/// composition: blocks of the season → their episodes → their scenes, each
/// level through the existing authenticated fetch seams (which own the Drift
/// cache discipline). No new backend route, no new cache table.
///
/// Failure semantics:
/// - the season's blocks cannot be read → `Left` (the whole view errors);
/// - one block's episodes or one episode's scenes fail → `Right` with the
///   respective [SeasonScript.failedBlocks] / [SeasonScript.failedEpisodes]
///   entry set, so the UI states the partial truth. A block whose episode
///   read failed contributes NO scenes, and saying so is the whole point:
///   silently omitting them would present a short list as the season's
///   complete script.
///
/// A sticky block scope for THIS season narrows the composition to that
/// block — the scope chip's promise ("what filters your requests") holds for
/// the Script view too. A scope belonging to another season is ignored here
/// (the same reuse rule the block chip renders as "gilt hier nicht").
@riverpod
Future<Result<SeasonScript>> seasonScriptFetch(
  Ref ref,
  SeasonView season,
) async {
  final scope = ref.watch(activeBlockProvider);
  final blocksResult = await ref.watch(
    blocksListFetchProvider(season.id).future,
  );
  return blocksResult.match(
    (error) async => Left<ProblemError, SeasonScript>(error),
    (blocks) async {
      final scoped = scope != null && scope.seasonId == season.id;
      final relevantBlocks = scoped
          ? blocks.where((block) => block.id == scope.blockId).toList()
          : blocks;

      final parts = <ScriptEpisodePart>[];
      final failedEpisodes = <String>[];
      final failedBlocks = <String>[];
      for (final block in relevantBlocks) {
        final episodesResult = await ref.watch(
          episodesListFetchProvider(block.id, season.id).future,
        );
        // A block whose episodes could NOT be read is recorded as a failed
        // scope: its scenes are UNKNOWN, not empty — saying so is the point
        // of this composition.
        final episodes = episodesResult.match((_) {
          failedBlocks.add(block.id);
          return const <EpisodeView>[];
        }, (rows) => rows);
        for (final episode in episodes) {
          final scenesResult = await ref.watch(
            scenesListFetchProvider(episode.id).future,
          );
          scenesResult.match(
            (_) => failedEpisodes.add(episode.id),
            (scenes) => parts.add(
              ScriptEpisodePart(block: block, episode: episode, scenes: scenes),
            ),
          );
        }
      }

      return Right<ProblemError, SeasonScript>(
        SeasonScript(
          rows: mergeScriptParts(parts),
          failedEpisodes: failedEpisodes,
          failedBlocks: failedBlocks,
        ),
      );
    },
  );
}
