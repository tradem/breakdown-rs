// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3 (neuralwatt)

// Tier-1 unit tests (no Flutter import) for the PlanningLocation sealed
// ladder (issue #548): every level's labels (incl. the fallbacks), the
// typed deepening, equality, and the argument extraction.

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/features/shell/planning_location.dart';

/// Deterministic fake copy — the production adapter (`L10nPlanningLocationCopy`)
/// is exercised in the widget tests.
class FakeCopy implements PlanningLocationCopy {
  @override
  String seasonLabel(String? title, int number) => title ?? 'S$number';

  @override
  String blockLabel(int number) => 'B$number';

  @override
  String episodeLabel(int number, String? name) => name ?? 'E$number';

  @override
  String sceneLabel(int? sceneNumber, String? summary) =>
      summary?.isNotEmpty == true ? summary! : 'Sc${sceneNumber ?? '-'}';
}

final copy = FakeCopy();

SeasonView _season(String id, {int number = 1, String? title}) => SeasonView(
  (b) => b
    ..archived = false
    ..id = id
    ..number = number
    ..projectId = 'series-1'
    ..title = title
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

BlockView _block(String id, {int number = 2, String seasonId = 's1'}) =>
    BlockView(
      (b) => b
        ..id = id
        ..number = number
        ..seasonId = seasonId
        ..projectId = 'series-1'
        ..updatedAt = DateTime.utc(2026, 1, 1)
        ..version = 1,
    );

EpisodeView _episode(String id, {int number = 3, String? name}) => EpisodeView(
  (b) => b
    ..id = id
    ..number = number
    ..name = name
    ..blockId = 'b1'
    ..projectId = 'series-1'
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

SceneView _scene(String id, {int? sceneNumber = 12, String? summary}) =>
    SceneView(
      (b) => b
        ..id = id
        ..sceneNumber = sceneNumber
        ..summary = summary
        ..episodeId = 'e1'
        ..assignedCharacters.replace(const <String>[])
        ..shootingDayIds.replace(const <String>[])
        ..isScheduleSet = false
        ..updatedAt = DateTime.utc(2026, 1, 1)
        ..version = 1,
    );

void main() {
  final season = _season('s1', number: 1, title: 'Titel');
  final unnamedSeason = _season('s2', number: 2);
  final block = _block('b1');
  final episode = _episode('e1');
  final unnamedEpisode = _episode('e2', number: 4);
  final scene = _scene('sc1', summary: 'Kurzfestlegung');
  final numberedScene = _scene('sc2', sceneNumber: 9, summary: null);

  group('PlanningLocation ladder labels (every level)', () {
    test('season level: title or number fallback', () {
      final loc = PlanningLocation.season(season);
      expect(loc.segments(copy), [(PlanningLevel.season, 'Titel')]);
      expect(PlanningLocation.season(unnamedSeason).segments(copy), [
        (PlanningLevel.season, 'S2'),
      ]);
    });

    test('block level: season + block', () {
      final loc = PlanningLocation.block(unnamedSeason, block);
      expect(loc.segments(copy), [
        (PlanningLevel.season, 'S2'),
        (PlanningLevel.block, 'B2'),
      ]);
      expect(loc.seasonId, 's2');
    });

    test('episode level: episode name or number fallback', () {
      final loc = PlanningLocation.episode(unnamedSeason, block, episode);
      expect(loc.segments(copy).map((s) => s.$2), ['S2', 'B2', 'E3']);
      expect(
        PlanningLocation.episode(
          unnamedSeason,
          block,
          unnamedEpisode,
        ).segments(copy).map((s) => s.$2),
        ['S2', 'B2', 'E4'],
      );
    });

    test('scene level: summary or scene number fallback', () {
      final loc = PlanningLocation.scene(unnamedSeason, block, episode, scene);
      expect(loc.segments(copy).map((s) => s.$2), [
        'S2',
        'B2',
        'E3',
        'Kurzfestlegung',
      ]);
      expect(
        PlanningLocation.scene(
          unnamedSeason,
          block,
          episode,
          numberedScene,
        ).segments(copy).map((s) => s.$2),
        ['S2', 'B2', 'E3', 'Sc9'],
      );
    });

    test('pathLabel flattens for the semantics node', () {
      final loc = PlanningLocation.scene(unnamedSeason, block, episode, scene);
      expect(loc.pathLabel(copy), 'S2 → B2 → E3 → Kurzfestlegung');
    });
  });

  group('typed deepening', () {
    test('the ladder requires the previous step', () {
      // A non-contiguous chain is NOT representable: there is no
      // constructor or factory to build an EpisodeLocation without a
      // BlockLocation — the compile-time shape is the guarantee.
      expect(
        PlanningLocation.episode(unnamedSeason, block, episode),
        isA<EpisodeLocation>(),
      );
    });

    test('withBlock / withEpisode / withScene deepen contiguously', () {
      // The typed subclasses (not the factories) expose the deepening —
      // the static type carries the contiguity guarantee.
      final s = SeasonLocation(season);
      final b = s.withBlock(block);
      expect(b, PlanningLocation.block(season, block));
      final e = b.withEpisode(episode);
      expect(e, PlanningLocation.episode(season, block, episode));
      final sc = e.withScene(scene);
      expect(sc, PlanningLocation.scene(season, block, episode, scene));
    });
  });

  group('equality', () {
    test('levels and DTO identity', () {
      expect(PlanningLocation.season(season), PlanningLocation.season(season));
      expect(
        PlanningLocation.block(season, block),
        isNot(PlanningLocation.season(season)),
      );
      expect(
        PlanningLocation.block(season, block),
        PlanningLocation.block(season, block),
      );
      expect(
        PlanningLocation.scene(season, block, episode, scene),
        isNot(
          PlanningLocation.scene(
            season,
            block,
            episode,
            _scene('sc1', summary: 'andere'),
          ),
        ),
      );
    });
  });

  group('locationFromArguments', () {
    test('returns the location; null for anything else', () {
      final loc = PlanningLocation.season(season);
      expect(locationFromArguments(loc), same(loc));
      expect(locationFromArguments(null), isNull);
      expect(locationFromArguments('a string'), isNull);
      expect(locationFromArguments(season), isNull);
    });
  });
}
