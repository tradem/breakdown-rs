// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)
// Co-authored-by: glm-5.3-flash (neuralwatt)

// Tier-1 table tests for the diacritics-folding prefilter (issue #616,
// task 1.2): case folding, the German dictionary expansions (ä→ae, ö→oe,
// ü→ue, ß→ss), accent stripping, and the spec's "Wohnung"/"Woehnung"
// boundary (dictionary folding, NOT fuzzy matching). No Flutter imports.

import 'package:test/test.dart';

import 'package:frontend_flutter/features/omni_search/name_prefilter.dart';

void main() {
  group('foldForSearch', () {
    test('case-folds ASCII', () {
      expect(foldForSearch('Wohnung'), 'wohnung');
      expect(foldForSearch('ZOE'), foldForSearch('zoe'));
    });

    test('German umlauts fold to their dictionary expansions', () {
      expect(foldForSearch('Ärger'), 'aerger');
      expect(foldForSearch('Öl'), 'oel');
      expect(foldForSearch('Übergrößen'), 'uebergroessen');
      expect(foldForSearch('Straße'), 'strasse');
    });

    test('accented Latin letters strip to the base letter', () {
      expect(foldForSearch('José'), 'jose');
      expect(foldForSearch('Zoé'), 'zoe');
      expect(foldForSearch('Chloé'), 'chloe');
      expect(foldForSearch('Loïc'), 'loic');
      expect(foldForSearch('François'), 'francois');
      expect(foldForSearch('Åse'), 'ase');
    });

    test('compound characters fold dictionary-style', () {
      expect(foldForSearch('dæmon'), 'daemon');
      expect(foldForSearch('cœur'), 'coeur');
    });

    test('unlisted characters pass through unchanged (no false folds)', () {
      expect(foldForSearch('Zoe 12'), 'zoe 12');
      expect(foldForSearch('К'), 'к'); // non-Latin untouched (case-folded only)
      expect(foldForSearch(''), '');
    });

    test('interior spacing is preserved (dictionary folding, not fuzzy)', () {
      expect(foldForSearch('Boot Lagerung'), 'boot lagerung');
      expect(
        foldedContains(
          foldForSearch('boot lagerung'),
          foldForSearch('AgErUnG'),
        ),
        isTrue,
      );
    });
  });

  group('foldedContains — the spec boundary', () {
    test('"wohnung" matches synopsis "Wohnung"', () {
      expect(foldedContains(foldForSearch('Wohnung'), 'wohnung'), isTrue);
    });

    test('the spec case: "wohnung" does NOT match synopsis "Woehnung"', () {
      // The dictionary EXPANSION changes the string — folding is exact, not
      // fuzzy: a typed "wohnung" cannot match a synopsis spelled out with
      // "oe" unless it literally contains "wohnung".
      expect(foldedContains(foldForSearch('Woehnung'), 'wohnung'), isFalse);
    });

    test('the reverse: typing "woehnung" matches "Woehnung"', () {
      expect(
        foldedContains(foldForSearch('Woehnung'), foldForSearch('woehnung')),
        isTrue,
      );
    });

    test('"zoe" matches "Zoé" case- and accent-insensitively', () {
      expect(
        foldedContains(foldForSearch('Zoé'), foldForSearch('ZOE')),
        isTrue,
      );
    });
  });
}
