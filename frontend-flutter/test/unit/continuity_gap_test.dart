// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.4 (opencode-go)

// Tier-1 unit tests for the wardrobe-gap derivation (issue #745, OpenSpec
// `ai-import-decision-outfit-continuity`): the identity mirror the backend
// validates selections against, and the pairing of a Pass-2 gap uncertainty
// with the scene figure it belongs to. Both are pure functions over the wire
// DTOs — no Flutter imports.

import 'package:breakdown_api/breakdown_api.dart';
import 'package:frontend_flutter/features/ai_import/import_jobs/continuity_gap.dart';
import 'package:test/test.dart';

DraftScene _scene(
  String ref, {
  int? number,
  List<String> characters = const [],
  List<DraftOutfit> outfits = const [],
}) => DraftScene(
  (b) => b
    ..draftRef = ref
    ..sceneNumber = number
    ..summary = 'Handlung'
    ..characters.replace([
      for (final name in characters)
        DraftCharacter(
          (c) => c
            ..name = name
            ..category = CharacterCategory.mainCast,
        ),
    ])
    ..outfits.replace(outfits),
);

DraftOutfit _outfit(String character, String name, {String quote = ''}) =>
    DraftOutfit(
      (b) => b
        ..characterName = character
        ..name = name
        ..sourceQuote = quote
        ..origin = DraftOutfitOrigin.explicitQuote,
    );

DraftOutfitCandidate _candidate(
  DraftOutfitOrigin origin,
  String name, {
  required String sourceDraftRef,
  int? sourceSceneNumber,
  double confidence = 0.6,
}) => DraftOutfitCandidate(
  (b) => b
    ..origin = origin
    ..name = name
    ..sourceDraftRef = sourceDraftRef
    ..confidence = confidence
    ..sourceSceneNumber = sourceSceneNumber,
);

Uncertainty _gap(
  int sceneIndex, {
  required String note,
  List<DraftOutfitCandidate> candidates = const [],
  String field = 'outfits',
  UncertaintyKind? kind = UncertaintyKind.droppedRow,
}) => Uncertainty(
  (b) => b
    ..sceneIndex = sceneIndex
    ..field = field
    ..note = note
    ..kind = kind
    ..candidates.replace(candidates),
);

ScriptContext _context(
  List<DraftScene> scenes, {
  List<Uncertainty> uncertainties = const [],
}) => ScriptContext(
  (b) => b
    ..title = 'Pilot'
    ..scenes.replace(scenes)
    ..uncertainties.replace(uncertainties),
);

void main() {
  group('characterIdentity mirrors the backend key', () {
    test('case-folds and collapses whitespace', () {
      expect(characterIdentity('BEN'), 'ben');
      expect(characterIdentity('  Ben  '), 'ben');
      expect(characterIdentity('Dr.   Koch'), 'dr. koch');
      expect(characterIdentity('OP\tSaal\n1'), 'op saal 1');
    });

    test('an all-whitespace or empty name has no identity', () {
      expect(characterIdentity(''), '');
      expect(characterIdentity('   '), '');
    });

    // Parity guard for the backend's `char::is_whitespace()` (Unicode
    // `White_Space`). ECMAScript `\s` — what Dart's `RegExp` implements — is a
    // DIFFERENT set, so the client cannot use it: a mismatch folds a name onto
    // a key the server does not derive and the apply answers 409.
    test('the whitespace set is Unicode White_Space, not ECMAScript \\s', () {
      // U+0085 NEL is White_Space in Rust but NOT ECMAScript whitespace.
      expect(characterIdentity('A\u0085B'), 'a b');
      // U+FEFF BOM is ECMAScript whitespace but NOT White_Space in Rust.
      expect(characterIdentity('A\uFEFFB'), 'a\uFEFFb');
      // Both sides agree on the rest of the property.
      for (final separator in [
        '\u0009',
        '\u000B',
        '\u000C',
        '\u0020',
        '\u00A0',
        '\u1680',
        '\u2000',
        '\u2007',
        '\u200A',
        '\u2028',
        '\u2029',
        '\u202F',
        '\u205F',
        '\u3000',
      ]) {
        expect(
          characterIdentity('A${separator}B'),
          'a b',
          reason: 'U+${separator.codeUnitAt(0).toRadixString(16)} folds',
        );
      }
      // A run of mixed separators collapses to ONE space, like the backend.
      expect(characterIdentity(' \u00A0\u3000 BEN \u202F '), 'ben');
      expect(characterIdentity('Dr.\u00A0\u00A0Koch'), 'dr. koch');
    });

    test('a name without a draft ref is addressed by its position', () {
      expect(draftRowRef(_scene('row-4'), 3), 'row-4');
      expect(draftRowRef(_scene(''), 3), 'scene-3');
    });
  });

  group('continuityGapsOf pairs each gap with its scene figure', () {
    test('a continuation gap resolves through the source row', () {
      final context = _context(
        [
          _scene('row-4', number: 4, outfits: [_outfit('BEN', 'Zivil-Look')]),
          _scene('row-5', number: 5, characters: ['BEN', 'ANNA']),
        ],
        uncertainties: [
          _gap(
            1,
            note: 'no certain wardrobe state for BEN',
            candidates: [
              _candidate(
                DraftOutfitOrigin.continuedFromScene,
                'Zivil-Look',
                sourceDraftRef: 'row-4',
                sourceSceneNumber: 4,
              ),
              _candidate(
                DraftOutfitOrigin.inferredFromContext,
                'Kontext-Look (OP-SAAL)',
                sourceDraftRef: 'row-5',
                sourceSceneNumber: 5,
              ),
            ],
          ),
        ],
      );

      final gaps = continuityGapsOf(context);
      expect(gaps, hasLength(1));
      final gap = gaps.single;
      expect(gap.sceneIndex, 1);
      expect(gap.sceneNumber, 5);
      // The wire key the apply request must send, derived from the scene's own
      // character list — and the scene's verbatim spelling for display.
      expect(gap.characterIdentity, 'ben');
      expect(gap.characterName, 'BEN');
      expect(gap.candidates, hasLength(2));
      expect(gap.continued?.name, 'Zivil-Look');
      expect(gap.inferred?.name, 'Kontext-Look (OP-SAAL)');
      expect(gap.note, 'no certain wardrobe state for BEN');
    });

    test('two undressed figures resolve to the one the source row dresses', () {
      final context = _context(
        [
          _scene('row-4', number: 4, outfits: [_outfit('Ben', 'Zivil-Look')]),
          _scene('row-5', number: 5, characters: ['Anna', 'Ben']),
        ],
        uncertainties: [
          _gap(
            1,
            note: 'gap',
            candidates: [
              _candidate(
                DraftOutfitOrigin.continuedFromScene,
                'Zivil-Look',
                sourceDraftRef: 'row-4',
              ),
            ],
          ),
        ],
      );

      final gap = continuityGapsOf(context).single;
      // The scene spells the figure differently than the source row; the
      // identity key is what pairs them.
      expect(gap.characterIdentity, 'ben');
      expect(gap.characterName, 'Ben');
    });

    test('a figure the scene already dresses is never a gap', () {
      final context = _context(
        [
          _scene('row-4', number: 4, outfits: [_outfit('Ben', 'Zivil-Look')]),
          // Pass 2 attached an inferred look for Ben: the server no longer
          // reports him as a gap, so a leftover notice must not offer a pick.
          _scene(
            'row-5',
            number: 5,
            characters: ['Ben'],
            outfits: [_outfit('Ben', 'Kontext-Look (OP)')],
          ),
        ],
        uncertainties: [
          _gap(
            1,
            note: 'outfit of Ben was inferred from the scene context',
            candidates: [
              _candidate(
                DraftOutfitOrigin.inferredFromContext,
                'Kontext-Look (OP)',
                sourceDraftRef: 'row-5',
              ),
            ],
          ),
        ],
      );

      expect(continuityGapsOf(context), isEmpty);
    });

    test('a gap without candidates stays a plain notice', () {
      final context = _context(
        [
          _scene('row-5', number: 5, characters: ['Ben']),
        ],
        uncertainties: [_gap(1, note: 'no outfit for Ben')],
      );

      expect(continuityGapsOf(context), isEmpty);
    });

    test('a non-outfit field never produces a picker', () {
      final context = _context(
        [
          _scene('row-4', number: 4, outfits: [_outfit('Ben', 'Zivil-Look')]),
          _scene('row-5', number: 5, characters: ['Ben']),
        ],
        uncertainties: [
          _gap(
            1,
            note: 'location',
            field: 'location',
            candidates: [
              _candidate(
                DraftOutfitOrigin.continuedFromScene,
                'Zivil-Look',
                sourceDraftRef: 'row-4',
              ),
            ],
          ),
        ],
      );

      expect(continuityGapsOf(context), isEmpty);
    });

    test('an unknown source row resolves only an unambiguous scene gap', () {
      final ambiguous = _context(
        [
          _scene('row-4', number: 4),
          _scene('row-5', number: 5, characters: ['Ben', 'Anna']),
        ],
        uncertainties: [
          _gap(
            1,
            note: 'gap',
            candidates: [
              _candidate(
                DraftOutfitOrigin.continuedFromScene,
                'Zivil-Look',
                sourceDraftRef: 'row-missing',
              ),
            ],
          ),
        ],
      );
      expect(continuityGapsOf(ambiguous), isEmpty);

      final unambiguous = _context(
        [
          _scene('row-4', number: 4),
          _scene('row-5', number: 5, characters: ['Ben']),
        ],
        uncertainties: [
          _gap(
            1,
            note: 'gap',
            candidates: [
              _candidate(
                DraftOutfitOrigin.continuedFromScene,
                'Zivil-Look',
                sourceDraftRef: 'row-missing',
              ),
            ],
          ),
        ],
      );
      expect(continuityGapsOf(unambiguous).single.characterIdentity, 'ben');
    });

    test('two uncertainties for one gap produce ONE picker', () {
      final context = _context(
        [
          _scene('row-4', number: 4, outfits: [_outfit('Ben', 'Zivil-Look')]),
          _scene('row-5', number: 5, characters: ['Ben']),
        ],
        uncertainties: [
          _gap(
            1,
            note: 'first',
            candidates: [
              _candidate(
                DraftOutfitOrigin.continuedFromScene,
                'Zivil-Look',
                sourceDraftRef: 'row-4',
              ),
            ],
          ),
          _gap(
            1,
            note: 'second',
            candidates: [
              _candidate(
                DraftOutfitOrigin.continuedFromScene,
                'Zivil-Look',
                sourceDraftRef: 'row-4',
              ),
            ],
          ),
        ],
      );

      expect(continuityGapsOf(context), hasLength(1));
      expect(continuityGapsOf(context).single.uncertaintyIndex, 0);
    });

    // The pairing branch that matters when SEVERAL of the scene's gap figures
    // appeared in the source row: the candidate's own look name selects one.
    test('the candidate look name breaks a source-row tie', () {
      final context = _context(
        [
          _scene(
            'row-4',
            number: 4,
            outfits: [
              _outfit('Ben', 'Zivil-Look'),
              _outfit('Anna', 'Dienst-Look'),
            ],
          ),
          _scene('row-5', number: 5, characters: ['Ben', 'Anna']),
        ],
        uncertainties: [
          _gap(
            1,
            note: 'gap',
            candidates: [
              _candidate(
                DraftOutfitOrigin.continuedFromScene,
                'Dienst-Look',
                sourceDraftRef: 'row-4',
              ),
            ],
          ),
        ],
      );

      final gap = continuityGapsOf(context).single;
      expect(gap.characterIdentity, 'anna');
      expect(gap.characterName, 'Anna');
    });

    test('an unrecognised look name never falls through to a wrong figure', () {
      final context = _context(
        [
          _scene(
            'row-4',
            number: 4,
            outfits: [
              _outfit('Ben', 'Zivil-Look'),
              _outfit('Anna', 'Dienst-Look'),
            ],
          ),
          _scene('row-5', number: 5, characters: ['Ben', 'Anna']),
        ],
        uncertainties: [
          _gap(
            1,
            note: 'gap',
            candidates: [
              _candidate(
                DraftOutfitOrigin.continuedFromScene,
                'Unbekannter Look',
                sourceDraftRef: 'row-4',
              ),
            ],
          ),
        ],
      );

      expect(continuityGapsOf(context), isEmpty);
    });

    test('an out-of-range scene index is ignored, never fabricated', () {
      final context = _context(
        [
          _scene('row-5', number: 5, characters: ['Ben']),
        ],
        uncertainties: [
          _gap(
            7,
            note: 'gap',
            candidates: [
              _candidate(
                DraftOutfitOrigin.continuedFromScene,
                'Zivil-Look',
                sourceDraftRef: 'row-5',
              ),
            ],
          ),
        ],
      );

      expect(continuityGapsOf(context), isEmpty);
    });
  });
}
