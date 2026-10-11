// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: space-bunny (opencode-go)

// Tier 1 unit tests for the season-wide chronological script composition
// (issue #610, view "Script"). Pure merge logic first, then the provider
// against fake fetch seams — both the Ok AND the Err/partial branches
// (AGENTS.md §6: an unmatched error path is a visible coverage hole).
// No Flutter imports beyond the test harness.

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/core/result.dart';
import 'package:frontend_flutter/features/blocks/blocks_controller.dart';
import 'package:frontend_flutter/features/episodes/episodes_controller.dart';
import 'package:frontend_flutter/features/scenes/scenes_controller.dart';
import 'package:frontend_flutter/features/scenes/season_script_controller.dart';

BlockView _block(String id, int number) => BlockView(
  (b) => b
    ..id = id
    ..number = number
    ..seasonId = 'season-1'
    ..projectId = 'project-1'
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

EpisodeView _episode(String id, int number, String blockId) => EpisodeView(
  (b) => b
    ..id = id
    ..number = number
    ..blockId = blockId
    ..projectId = 'project-1'
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

SceneView _scene(String id, String episodeId, {int? number, String? summary}) =>
    SceneView(
      (b) => b
        ..id = id
        ..episodeId = episodeId
        ..sceneNumber = number
        ..summary = summary
        ..assignedCharacters.replace(const <String>[])
        ..shootingDayIds.replace(const <String>[])
        ..isScheduleSet = false
        ..updatedAt = DateTime.utc(2026, 1, 1)
        ..version = 1,
    );

SeasonView _season() => SeasonView(
  (b) => b
    ..archived = false
    ..id = 'season-1'
    ..number = 1
    ..projectId = 'project-1'
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

void main() {
  group('mergeScriptParts (pure)', () {
    test('merges episodes into ONE scene_number-ordered list', () {
      final rows = mergeScriptParts([
        ScriptEpisodePart(
          block: _block('b-1', 1),
          episode: _episode('e-2', 2, 'b-1'),
          scenes: [
            _scene('s-13', 'e-2', number: 13),
            _scene('s-14', 'e-2', number: 14),
          ],
        ),
        ScriptEpisodePart(
          block: _block('b-1', 1),
          episode: _episode('e-1', 1, 'b-1'),
          scenes: [
            _scene('s-2', 'e-1', number: 2),
            _scene('s-1', 'e-1', number: 1),
          ],
        ),
      ]);

      expect(rows.map((r) => r.scene.id).toList(), [
        's-1',
        's-2',
        's-13',
        's-14',
      ], reason: 'the script is ONE continuous list, not per-episode groups');
    });

    test('a scene without a projected number sorts LAST', () {
      final rows = mergeScriptParts([
        ScriptEpisodePart(
          block: _block('b-1', 1),
          episode: _episode('e-1', 1, 'b-1'),
          scenes: [_scene('s-none', 'e-1'), _scene('s-3', 'e-1', number: 3)],
        ),
      ]);

      expect(rows.map((r) => r.scene.id).toList(), ['s-3', 's-none']);
    });

    test('equal scene numbers keep a deterministic episode order', () {
      final rows = mergeScriptParts([
        ScriptEpisodePart(
          block: _block('b-1', 1),
          episode: _episode('e-2', 2, 'b-1'),
          scenes: [_scene('s-b', 'e-2', number: 5)],
        ),
        ScriptEpisodePart(
          block: _block('b-1', 1),
          episode: _episode('e-1', 1, 'b-1'),
          scenes: [_scene('s-a', 'e-1', number: 5)],
        ),
      ]);

      expect(rows.map((r) => r.scene.id).toList(), ['s-a', 's-b']);
    });

    test('no parts yields no rows (not a crash)', () {
      expect(mergeScriptParts(const []), isEmpty);
    });
  });

  group('seasonScriptFetchProvider', () {
    late ProviderContainer container;

    Result<List<BlockView>> blocksResult = Right(const []);
    Result<List<EpisodeView>> episodesResult = Right(const []);
    Result<List<SceneView>> scenesResult = Right(const []);

    Future<void> setUpContainer() async {
      container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          blocksListFetchProvider('season-1')
              .overrideWith((ref) async => blocksResult),
          episodesListFetchProvider(
            'b-1',
            'season-1',
          ).overrideWith((ref) async => episodesResult),
          scenesListFetchProvider('e-1')
              .overrideWith((ref) async => scenesResult),
        ],
      );
      addTearDown(container.dispose);
    }

    test('Ok: composes blocks → episodes → scenes into one list', () async {
      blocksResult = Right([_block('b-1', 1)]);
      episodesResult = Right([_episode('e-1', 1, 'b-1')]);
      scenesResult = Right([
        _scene('s-2', 'e-1', number: 2, summary: 'Zweiter'),
        _scene('s-1', 'e-1', number: 1, summary: 'Erster'),
      ]);
      await setUpContainer();

      final result = await container.read(
        seasonScriptFetchProvider(_season()).future,
      );

      expect(result.isRight(), isTrue);
      final script = result.getRight().toNullable()!;
      expect(script.isPartial, isFalse);
      expect(script.rows.map((r) => r.scene.id).toList(), ['s-1', 's-2']);
      // Each row carries the parent DTOs the detail push consumes (CQRS
      // boundary — no second lookup downstream).
      expect(script.rows.first.episode.id, 'e-1');
      expect(script.rows.first.block.id, 'b-1');
    });

    test('Err: an unreadable block list surfaces as Left', () async {
      blocksResult = const Left(ProblemError(code: 'blocks.forbidden'));
      await setUpContainer();

      final result = await container.read(
        seasonScriptFetchProvider(_season()).future,
      );

      expect(result.isLeft(), isTrue);
      expect(result.getLeft().toNullable()!.code, 'blocks.forbidden');
    });

    test('partial: a failing EPISODE-LIST read degrades VISIBLY too', () async {
      // CodeRabbit review (PR #620): a failed `episodesListFetch` used to
      // collapse to `[]`, so the block contributed nothing while the view
      // still claimed a COMPLETE script. Its scenes are unknown, not
      // empty — the composition now records the failed block.
      blocksResult = Right([_block('b-1', 1)]);
      episodesResult = const Left(ProblemError(code: 'episodes.network'));
      await setUpContainer();

      final result = await container.read(
        seasonScriptFetchProvider(_season()).future,
      );

      final script = result.getRight().toNullable()!;
      expect(script.isPartial, isTrue);
      expect(script.failedBlocks, ['b-1']);
      // Block ids must not be counted as episodes.
      expect(script.failedEpisodes, isEmpty);
      expect(script.rows, isEmpty);
    });

    test(
      'partial: a failing episode degrades VISIBLY, never silently',
      () async {
        blocksResult = Right([_block('b-1', 1)]);
        episodesResult = Right([_episode('e-1', 1, 'b-1')]);
        scenesResult = const Left(ProblemError(code: 'scenes.network'));
        await setUpContainer();

        final result = await container.read(
          seasonScriptFetchProvider(_season()).future,
        );

        final script = result.getRight().toNullable()!;
        expect(script.isPartial, isTrue);
        expect(script.failedEpisodes, ['e-1']);
        expect(script.rows, isEmpty);
      },
    );
  });
}
