// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

// Tier-1 pure matcher tests for the fundus browse (issue #625, tasks §1.2).
// No Flutter imports: the repertoire scope rule, the season filter and the
// name prefilter are all pure.

import 'package:breakdown_api/breakdown_api.dart';
import 'package:built_collection/built_collection.dart';
import 'package:test/test.dart';

import 'package:frontend_flutter/features/fundus/fundus_model.dart';

void main() {
  PieceView piece({
    required String id,
    required List<String> repertoire,
    String notes = '',
    String? categoryName,
  }) => PieceView(
    (b) => b
      ..name = 'Fundus-Piece'
      ..id = id
      ..notes = notes
      ..categoryName = categoryName
      ..details.replace(BuiltList<PieceDetailView>())
      ..photos.replace(BuiltList<PiecePhotoView>())
      ..seasonIds.replace(BuiltList<String>(repertoire))
      ..updatedAt = DateTime.utc(2026, 1, 1)
      ..version = 1,
  );

  List<String> ids(List<PieceView> rows) => [for (final c in rows) c.id];

  test('whole fundus by default: every repertoire piece of the project', () {
    final rows = matchFundus(
      pieces: [
        piece(id: 'k1', repertoire: ['s1']),
        piece(id: 'k2', repertoire: ['s1', 's2']),
      ],
      projectSeasonIds: {'s1', 's2'},
      selectedSeasonIds: const {},
      text: '',
    );
    expect(ids(rows), ['k1', 'k2']);
  });

  test('season chip narrows to repertoire intersection', () {
    final rows = matchFundus(
      pieces: [
        piece(id: 'k1', repertoire: ['s1']),
        piece(id: 'k2', repertoire: ['s2']),
        piece(id: 'k3', repertoire: ['s1', 's2']),
      ],
      projectSeasonIds: {'s1', 's2'},
      selectedSeasonIds: {'s2'},
      text: '',
    );
    expect(ids(rows), ['k2', 'k3']);
  });

  test('non-repertoire piece is excluded', () {
    final rows = matchFundus(
      pieces: [
        piece(id: 'k1', repertoire: const []),
        piece(id: 'k2', repertoire: ['s1']),
      ],
      projectSeasonIds: {'s1'},
      selectedSeasonIds: const {},
      text: '',
    );
    expect(ids(rows), ['k2']);
  });

  test('foreign-project piece is excluded even if cached', () {
    final rows = matchFundus(
      pieces: [
        piece(id: 'k1', repertoire: ['other-season']),
        piece(id: 'k2', repertoire: ['s1']),
      ],
      projectSeasonIds: {'s1'},
      selectedSeasonIds: const {},
      text: '',
    );
    expect(ids(rows), ['k2']);
  });

  test('name prefilter matches notes, case- and diacritics-insensitive', () {
    final rows = matchFundus(
      pieces: [
        piece(id: 'k1', repertoire: ['s1'], notes: 'Lederjacke'),
        piece(id: 'k2', repertoire: ['s1'], notes: 'Abendkleid'),
      ],
      projectSeasonIds: {'s1'},
      selectedSeasonIds: const {},
      text: 'lederJACKE',
    );
    expect(ids(rows), ['k1']);
  });

  test('name prefilter folds German umlauts (dictionary folding)', () {
    final rows = matchFundus(
      pieces: [
        piece(id: 'k1', repertoire: ['s1'], notes: 'Mütze'),
      ],
      projectSeasonIds: {'s1'},
      selectedSeasonIds: const {},
      text: 'muetze',
    );
    expect(ids(rows), ['k1']);
  });

  test('name prefilter also matches the category name', () {
    final rows = matchFundus(
      pieces: [
        piece(id: 'k1', repertoire: ['s1'], categoryName: 'Accessoires'),
        piece(id: 'k2', repertoire: ['s1'], categoryName: 'Schuhe'),
      ],
      projectSeasonIds: {'s1'},
      selectedSeasonIds: const {},
      text: 'access',
    );
    expect(ids(rows), ['k1']);
  });

  test('empty query keeps every repertoire piece', () {
    final rows = matchFundus(
      pieces: [
        piece(id: 'k1', repertoire: ['s1'], notes: 'Lederjacke'),
      ],
      projectSeasonIds: {'s1'},
      selectedSeasonIds: const {},
      text: '   ',
    );
    expect(ids(rows), ['k1']);
  });
}
