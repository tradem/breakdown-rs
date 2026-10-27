// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

// Tier-1 unit tests for the pure scene-beat helpers (issue #546): the
// grouping order of `groupSceneBeats` and the tile-identity discipline of
// `sceneBeatPieceLabel` / `sceneBeatPieceCategory`. No Flutter imports.

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/features/pieces/piece_identity.dart';
import 'package:frontend_flutter/features/scenes/scene_beats.dart';

SceneOutfitBeatView _beat(
  String characterId,
  int order, {
  String pieceId = 'piece-1',
  String? categoryName,
  String? note,
}) => SceneOutfitBeatView(
  (b) => b
    ..characterId = characterId
    ..outfitId = pieceId
    ..outfitName = categoryName
    ..order = order
    ..note = note,
);

PieceView _piece(
  String id, {
  String? subject,
  String? categoryName,
  String notes = '',
}) => PieceView(
  (b) => b
    ..name = 'Fundus-Piece'
    ..id = id
    ..notes = notes
    ..categoryName = categoryName
    ..details.replace([
      // Tile identity: the FIRST detail's subject is the de-facto name.
      PieceDetailView(
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
          _beat('c-2', 0, pieceId: 'piece-2'),
          _beat('c-2', 1, pieceId: 'piece-3'),
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
      // Stale projection between AssignCharacter and AddSceneOutfitBeat: the
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

  group('sceneBeatPieceLabel (tile-identity discipline)', () {
    test('a piece resolves via the SAME tile helper', () {
      final label = pieceDisplayName(
        _piece('piece-1', subject: 'Rotkäppchen-Mantel'),
        'Kleidungsstück',
      );
      // `PieceView.name` is the authoritative label, NOT the detail subject.
      expect(label, 'Fundus-Piece');
    });

    test('a blank piece name falls back to the detail subject', () {
      final label = pieceDisplayName(
        _piece(
          'piece-1',
          subject: 'Rotkäppchen-Mantel',
        ).rebuild((b) => b..name = ' '),
        'Kleidungsstück',
      );
      expect(label, 'Rotkäppchen-Mantel');
    });

    test('an outfit beat label is the look name', () {
      expect(
        sceneBeatOutfitLabel(
          outfitName: 'Alltagslook Tag 1',
          genericFallback: 'Kleidungsstück',
        ),
        'Alltagslook Tag 1',
      );
    });

    test('projection miss falls back to the generic label', () {
      expect(
        sceneBeatOutfitLabel(
          outfitName: null,
          genericFallback: 'Kleidungsstück',
        ),
        'Kleidungsstück',
      );
    });

    test('projection miss without join falls back to the generic label', () {
      final label = sceneBeatPieceLabel(
        piece: null,
        joinedCategoryName: null,
        genericFallback: 'Kleidungsstück',
      );
      expect(label, 'Kleidungsstück');
    });

    test('icon category prefers the piece, falls back to the join', () {
      expect(
        sceneBeatPieceCategory(
          piece: _piece('c', categoryName: 'Schuhe'),
          joinedCategoryName: 'Jacke',
        ),
        'Schuhe',
      );
      expect(
        sceneBeatPieceCategory(piece: null, joinedCategoryName: 'Jacke'),
        'Jacke',
      );
      expect(
        sceneBeatPieceCategory(piece: null, joinedCategoryName: null),
        isNull,
      );
    });
  });
}
