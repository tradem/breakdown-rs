// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)
// Co-authored-by: glm-5.3-flash (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

// Tier-1 tests for the per-facet matchers and the grouped composition
// (issue #616, task 1.3): exact field pinning per spec (scene = number
// prefix + synopsis, character = name, costume = description + category
// ONLY, shooting day = label/date), OR over a facet's own fields, D3
// canonical group order, and active-facet restriction. No Flutter imports.

import 'package:breakdown_api/breakdown_api.dart';
import 'package:built_collection/built_collection.dart';
import 'package:one_of/one_of.dart';
import 'package:test/test.dart';

import 'package:frontend_flutter/features/omni_search/name_prefilter.dart';
import 'package:frontend_flutter/features/omni_search/omni_search_matcher.dart';
import 'package:frontend_flutter/features/omni_search/omni_search_model.dart';

void main() {
  // Folded-needle helpers: the call sites fold exactly once (the matcher
  // contract), then the facet matcher receives the folded value.
  String f(String raw) => foldForSearch(raw);

  group('scene facet (number prefix + synopsis)', () {
    test('numeric query matches the scene number at its PREFIX', () {
      final hit = sceneHit(sceneNumber: 112, summary: 'Andere');
      expect(sceneMatches(hit, f('11')), isTrue); // prefix
      expect(sceneMatches(hit, f('12')), isFalse); // no sub-match inside
    });

    test('numeric query still matches the synopsis (OR semantics)', () {
      final hit = sceneHit(sceneNumber: 3, summary: 'Boot lagerung');
      expect(sceneMatches(hit, f('lager')), isTrue);
    });

    test('text query matches the synopsis, diacritics-insensitive', () {
      final hit = sceneHit(sceneNumber: 12, summary: 'Wohnung Zoe');
      expect(sceneMatches(hit, f('Wohnung')), isTrue);
      expect(sceneMatches(hit, f('wohnung')), isTrue);
      // Lineup sub-matches inside the typed text are fine (there the char
      // sequence occurs in the synopsis directly).
      expect(sceneMatches(hit, f('ZOE')), isTrue);
    });

    test('unnumbered scene matches only via the synopsis', () {
      final hit = sceneHit(sceneNumber: null, summary: 'Probenräume');
      expect(sceneMatches(hit, f('probenrae')), isTrue);
      expect(sceneMatches(hit, f('123')), isFalse);
    });

    test('empty query matches nothing (no universe listing)', () {
      final hit = sceneHit(sceneNumber: 1, summary: 'Wohnung');
      expect(sceneMatches(hit, ''), isFalse);
    });

    test('the number field never SUB-matches — only its prefix counts', () {
      final hit = sceneHit(sceneNumber: 112, summary: 'Andere');
      expect(sceneMatches(hit, f('1')), isTrue); // prefix of the number
      expect(sceneMatches(hit, f('2')), isFalse); // inside the number only
    });

    test('the summary legitimately sub-matches numeric queries', () {
      // OR semantics: "112" inside the synopsis IS a substring hit.
      final hit = sceneHit(sceneNumber: 8, summary: '112 Anbau');
      expect(sceneMatches(hit, f('112')), isTrue);
    });
  });

  group('character facet (name only)', () {
    test('substring match over the name', () {
      final hit = characterHit('Zoe Zimmermann');
      expect(characterMatches(hit, f('zoe')), isTrue);
      expect(characterMatches(hit, f('mann')), isTrue);
      expect(characterMatches(hit, f('zimmermann')), isTrue);
    });

    test('NO field creep: category or contact is never searched', () {
      final hit = characterHit('Zoe'); // category main_cast, contact a@b.c
      expect(characterMatches(hit, f('main')), isFalse);
      expect(characterMatches(hit, f('b.c')), isFalse);
      expect(characterMatches(hit, ''), isFalse);
    });
  });

  group('costume facet (description + category ONLY)', () {
    test('matches the notes and the category name', () {
      final hit = costumeHit(notes: 'Marineblau', categoryName: 'Trachten');
      expect(costumeMatches(hit, f('marineblau')), isTrue);
      expect(costumeMatches(hit, f('trachten')), isTrue);
    });

    test('design Q2 pin: details/photos/character id never participate', () {
      final hit = costumeHit(
        notes: 'Blau',
        categoryName: null,
        detailText: 'Samt',
        photoId: 'photo-portal',
      );
      expect(costumeMatches(hit, f('samt')), isFalse);
      expect(costumeMatches(hit, f('portal')), isFalse);
    });

    test('empty query matches nothing', () {
      final hit = costumeHit(notes: 'Blau');
      expect(costumeMatches(hit, ''), isFalse);
    });
  });

  group('shooting-day facet (label or date)', () {
    test('matches the label', () {
      final hit = dayHit(label: 'Erster Drehtag Block');
      expect(shootingDayMatches(hit, f('drehtag')), isTrue);
    });

    test('matches the ISO date string', () {
      final hit = dayHit(label: null, date: '2026-05-12');
      expect(shootingDayMatches(hit, f('2026-05')), isTrue);
      expect(shootingDayMatches(hit, f('12.05')), isFalse);
    });

    test('field pin: order key and wrapped state never participate', () {
      final hit = dayHit(label: 'Tag', orderKey: 'momentum');
      expect(shootingDayMatches(hit, f('momentum')), isFalse);
    });

    test('archived days still surface (readable inventory)', () {
      // The spec does not exclude archived days from the search hit set;
      // the day board remains their read surface.
      final hit = dayHit(label: 'Nachdrehtage');
      expect(shootingDayMatches(hit, f('nachdreh')), isTrue);
    });
  });

  group('composeOmniSearchResults', () {
    test('groups in D3 canonical order over all facets', () {
      final results = composeOmniSearchResults(
        workload(),
        'wo',
        kAllOmniSearchFacets,
      );
      expect(results.groups.map((g) => g.facet).toList(), [
        OmniSearchFacet.scene,
        OmniSearchFacet.character,
        OmniSearchFacet.costume,
        OmniSearchFacet.shootingDay,
      ]);
    });

    test('single active facet: only that group is absent-filtered', () {
      final results = composeOmniSearchResults(workload(), 'wo', {
        OmniSearchFacet.costume,
      });
      expect(results.groups, hasLength(1));
      expect(results.groups.single.facet, OmniSearchFacet.costume);
    });

    test('empty groups are dropped — absent, not merely empty', () {
      final results = composeOmniSearchResults(
        workload(),
        'marineblau',
        kAllOmniSearchFacets,
      );
      expect(results.groups.map((g) => g.facet).toList(), [
        OmniSearchFacet.costume,
      ]);
    });

    test('the empty facet set yields no groups at all', () {
      final results = composeOmniSearchResults(
        workload(),
        'wo',
        const <OmniSearchFacet>{},
      );
      expect(results.groups, isEmpty);
    });

    test(
      'a whitespace-only query matches nothing (trimmed before folding)',
      () {
        // CodeRabbit review: " " is non-empty after folding and would match
        // every field containing a space — it degrades to no groups (the
        // initial state), interior spacing still matching normally.
        final results = composeOmniSearchResults(
          workload(),
          '   ',
          kAllOmniSearchFacets,
        );
        expect(results.groups, isEmpty);
        final padded = composeOmniSearchResults(
          workload(),
          '  wo  ',
          kAllOmniSearchFacets,
        );
        expect(padded.groups.map((g) => g.facet), kAllOmniSearchFacets);
      },
    );

    test('hits keep the input order inside their group', () {
      final results = composeOmniSearchResults(workload(), 'wo', {
        OmniSearchFacet.scene,
      });
      expect(results.groups.single.hits, hasLength(2));
    });
  });
}

// --- local DTO builders ----------------------------------------------------

int _uidSeq = 0;
String _nextUid() => '${++_uidSeq}';

SceneOmniHit sceneHit({int? sceneNumber, String? summary}) => SceneOmniHit(
  scene: SceneView(
    (b) => b
      ..id = 'scene-${_nextUid()}'
      ..episodeId = 'ep-1'
      ..sceneNumber = sceneNumber
      ..summary = summary
      ..assignedCharacters.replace(BuiltList<String>())
      ..shootingDayIds.replace(BuiltList<String>())
      ..isScheduleSet = false
      ..updatedAt = DateTime.utc(2026, 1, 1)
      ..version = 1,
  ),
  episode: _episode(),
  block: _block(),
);

CharacterOmniHit characterHit(String name) => CharacterOmniHit(
  character: CharacterView(
    (b) => b
      ..id = 'char-1'
      ..seasonId = 'season-1'
      ..name = name
      ..category = serializers.deserializeWith(
        CharacterCategory.serializer,
        'main_cast',
      )!
      ..measurements.replace(CharacterMeasurements((m) => m..height = '180'))
      ..contact.replace(ContactInfo((c) => c..email = 'a@b.c'))
      ..updatedAt = DateTime.utc(2026, 1, 1)
      ..version = 1,
  ),
);

CostumeOmniHit costumeHit({
  required String notes,
  String? categoryName,
  String? detailText,
  String? photoId,
}) => CostumeOmniHit(
  costume: PieceView(
    (b) => b
      ..name = 'Fundus-Piece'
      ..id = 'costume-1'
      ..notes = notes
      ..categoryName = categoryName
      ..details.replace(
        detailText == null
            ? BuiltList<PieceDetailView>()
            : BuiltList<PieceDetailView>([
                PieceDetailView(
                  (d) => d
                    ..id = 'detail-1'
                    ..text = detailText,
                ),
              ]),
      )
      ..photos.replace(
        photoId == null
            ? BuiltList<PiecePhotoView>()
            : BuiltList<PiecePhotoView>([
                PiecePhotoView(
                  (p) => p
                    ..id = photoId
                    ..contentType = 'image/jpeg'
                    ..sizeBytes = 10
                    ..variants.replace(BuiltList<PhotoVariantView>()),
                ),
              ]),
      )
      ..updatedAt = DateTime.utc(2026, 1, 1)
      ..version = 1,
  ),
);

ShootingDayOmniHit dayHit({
  String? label,
  String? date,
  String orderKey = '!0',
}) => ShootingDayOmniHit(
  day: ShootingDayView(
    (b) => b
      ..id = 'day-1'
      ..episodeId = 'ep-1'
      ..orderKey = orderKey
      ..label = label
      ..date = date == null ? null : _parseDate(date)
      ..source_.replace(
        ShootingDaySource((s) => s..oneOf = OneOf.fromValue1(value: 'Manual')),
      )
      ..archived = false
      ..updatedAt = DateTime.utc(2026, 1, 1)
      ..version = 1,
  ),
  episode: _episode(),
  block: _block(),
);

EpisodeView _episode() => EpisodeView(
  (b) => b
    ..id = 'ep-1'
    ..blockId = 'block-1'
    ..number = 1
    ..projectId = 'project-1'
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

BlockView _block() => BlockView(
  (b) => b
    ..id = 'block-1'
    ..number = 1
    ..seasonId = 'season-1'
    ..projectId = 'project-1'
    ..updatedAt = DateTime.utc(2026, 1, 1)
    ..version = 1,
);

Date _parseDate(String iso) {
  final parts = iso.split('-');
  return Date(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
}

/// One input set where every facet holds a hit matching "wo": the
/// group-order and restriction tests run against identical data.
OmniSearchInputs workload() => OmniSearchInputs(
  seasonId: 'season-1',
  scenes: [
    sceneHit(sceneNumber: 1, summary: 'Wohnung'),
    sceneHit(sceneNumber: 2, summary: 'Wohngemeinschaft'),
  ],
  characters: [characterHit('Wolfgang')],
  costumes: [costumeHit(notes: 'Marineblau Wolle')],
  shootingDays: [dayHit(label: 'Wonnemonat Drehstart')],
  facetStates: [
    for (final facet in OmniSearchFacet.values)
      OmniSearchFacetState(facet: facet, stale: false),
  ],
  hasHierarchyRows: true,
  hasCharacterRows: true,
  hasCostumeRows: true,
);
