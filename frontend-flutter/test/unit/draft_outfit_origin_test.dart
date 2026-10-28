// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

// Tier-1 unit test: the generated client must decode every `DraftOutfitOrigin`
// value. Regression guard for the PR #746 review finding — a data-carrying
// origin variant lowered to two identical string alternatives in the oneOf, and
// `built_value` then rejected the COMMON Pass-1 case with
// "more than one match found: (String, String)".
import 'dart:convert';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:test/test.dart';

DraftOutfit decode(String json) => standardSerializers.deserializeWith(
  DraftOutfit.serializer,
  jsonDecode(json),
)!;

Map<String, dynamic> encode(DraftOutfit outfit) => jsonDecode(
  jsonEncode(standardSerializers.serializeWith(DraftOutfit.serializer, outfit)),
) as Map<String, dynamic>;

String row(String origin) => jsonEncode({
  'character_name': 'BEN',
  'name': 'Zivil-Look',
  'source_quote': 'in Zivil',
  'origin': origin,
});

void main() {
  test('every origin value decodes and re-encodes as a plain string', () {
    final expected = <String, DraftOutfitOrigin>{
      'explicit_quote': DraftOutfitOrigin.explicitQuote,
      'derived': DraftOutfitOrigin.derived,
      'continued_from_scene': DraftOutfitOrigin.continuedFromScene,
      'inferred_from_context': DraftOutfitOrigin.inferredFromContext,
    };
    for (final entry in expected.entries) {
      final outfit = decode(row(entry.key));
      expect(
        outfit.origin,
        entry.value,
        reason: 'origin ${entry.key} must decode',
      );
      expect(
        encode(outfit)['origin'],
        entry.key,
        reason: 'and re-encode as the same plain string',
      );
    }
  });

  test('a Pass-1 row carries no provenance', () {
    expect(decode(row('derived')).provenance, isNull);
  });

  test('a continuation carries its source row and confidence', () {
    final outfit = decode(
      jsonEncode({
        'character_name': 'BEN',
        'name': 'Zivil-Look',
        'source_quote': '',
        'origin': 'continued_from_scene',
        'provenance': {
          'source_draft_ref': 'row-4',
          'source_scene_number': 4,
          'confidence': 0.82,
        },
      }),
    );
    expect(outfit.origin, DraftOutfitOrigin.continuedFromScene);
    expect(outfit.provenance?.sourceDraftRef, 'row-4');
    expect(outfit.provenance?.sourceSceneNumber, 4);
    expect(outfit.provenance?.confidence, closeTo(0.82, 1e-6));
  });

  test('a gap uncertainty exposes only the candidates the server sent', () {
    final uncertainty = standardSerializers.deserializeWith(
      Uncertainty.serializer,
      jsonDecode(
        jsonEncode({
          'scene_index': 5,
          'field': 'outfits',
          'note': 'no certain wardrobe state',
          'suggested_value': 'Zivil-Look',
          'kind': 'dropped_row',
          'candidates': [
            {
              'origin': 'continued_from_scene',
              'name': 'Zivil-Look',
              'source_draft_ref': 'row-4',
              'source_scene_number': 4,
              'confidence': 0.6,
            },
          ],
        }),
      ),
    )!;
    expect(uncertainty.candidates, hasLength(1));
    expect(uncertainty.candidates!.single.name, 'Zivil-Look');
    expect(
      uncertainty.candidates!.single.origin,
      DraftOutfitOrigin.continuedFromScene,
    );
  });
}
