// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (neuralwatt)

// Tier-1 unit tests for the pure scene-beat helpers (issue #546): the
// grouping order of `groupSceneBeats` and the tile-identity discipline of
// `sceneBeatCostumeLabel` / `sceneBeatCostumeCategory`. No Flutter imports.

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/features/costumes/costume_identity.dart';
import 'package:frontend_flutter/features/scenes/scene_beats.dart';

SceneCostumeBeatView _beat(
  String characterId,
  int order, {
  String costumeId = 'costume-1',
  String? characterName,
  String? categoryName,
  String? note,
}) => SceneCostumeBeatView(
  (b) => b
    ..characterId = characterId
    ..costumeId = costumeId
    ..characterName = characterName
    ..costumeCategoryName = categoryName
    ..order = order
    ..note = note,
);

CostumeView _costume(
  String id, {
  String? subject,
  String? categoryName,
  String notes = '',
}) => CostumeView(
  (b) => b
    ..id = id
    ..notes = notes
    ..categoryName = categoryName
    ..details.replace([
      // Tile identity: the FIRST detail's subject is the de-facto name.
      CostumeDetailView(
        (d) => d
          ..id = 'detail-1'
          ..subject = subject
          ..text = '',
      ),
    ])
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

void main() {
  group('groupSceneBeats (unit, issue #546)', () {
    test('renders one group per character in assignment order', () {
      final groups = groupSceneBeats(
        assignedCharacters: ['c-2', 'c-1'],
        beats: [
          _beat('c-1', 0),
          _beat('c-2', 0, costumeId: 'costume-2'),
          _beat('c-2', 1, costumeId: 'costume-3'),
        ],
      );
      expect(groups.map((g) => g.characterId), ['c-2', 'c-1']);
      // Beats sort by their dense zero-based order within the character.
      expect(groups[0].beats.map((b) => b.order), [0, 1]);
      expect(groups[1].beats.map((b) => b.order), [0]);
    });

    test('a character WITHOUT beats keeps its empty group (empty state)', () {
      final groups = groupSceneBeats(
        assignedCharacters: ['c-1', 'c-2'],
        beats: [_beat('c-2', 0)],
      );
      expect(groups.map((g) => g.characterId), ['c-1', 'c-2']);
      expect(groups[0].beats, isEmpty);
    });

    test('beat-carrying unknown characters are appended, never dropped', () {
      // Stale projection between AssignCharacter and AddCostumeBeat: the
      // beat references a character the scene's id list does not carry yet.
      final groups = groupSceneBeats(
        assignedCharacters: ['c-1'],
        beats: [_beat('c-9', 0), _beat('c-1', 0)],
      );
      expect(groups.map((g) => g.characterId), ['c-1', 'c-9']);
    });

    test('duplicated assigned ids collapse defensively (issue #550)', () {
      final groups = groupSceneBeats(
        assignedCharacters: ['c-1', 'c-1'],
        beats: [_beat('c-1', 0)],
      );
      expect(groups, hasLength(1));
    });
  });

  group('sceneBeatCostumeLabel (tile-identity discipline)', () {
    test('a projected costume resolves via the SAME tile helper', () {
      final label = sceneBeatCostumeLabel(
        costume: _costume('costume-1', subject: 'Rotkäppchen-Mantel'),
        joinedCategoryName: 'Jacke',
        genericFallback: 'Kostüm',
      );
      // The detail subject (tile identity), NOT the joined category.
      expect(label, 'Rotkäppchen-Mantel');
    });

    test('projection miss falls back to the backend-joined category', () {
      final label = sceneBeatCostumeLabel(
        costume: null,
        joinedCategoryName: 'Jacke',
        genericFallback: 'Kostüm',
      );
      expect(label, 'Jacke');
    });

    test('projection miss without join falls back to the generic label', () {
      final label = sceneBeatCostumeLabel(
        costume: null,
        joinedCategoryName: null,
        genericFallback: 'Kostüm',
      );
      expect(label, 'Kostüm');
    });

    test('icon category prefers the costume, falls back to the join', () {
      expect(
        sceneBeatCostumeCategory(
          costume: _costume('c', categoryName: 'Schuhe'),
          joinedCategoryName: 'Jacke',
        ),
        'Schuhe',
      );
      expect(
        sceneBeatCostumeCategory(costume: null, joinedCategoryName: 'Jacke'),
        'Jacke',
      );
      expect(
        sceneBeatCostumeCategory(costume: null, joinedCategoryName: null),
        isNull,
      );
    });
  });
}
