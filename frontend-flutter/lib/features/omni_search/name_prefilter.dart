// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)
// Co-authored-by: glm-5.3-flash (neuralwatt)

/// Tier-1 pure name prefilter folding for the OmniSearch (tasks §1.2,
/// spec: case-insensitive + diacritics-insensitive substring match —
/// dictionary folding, NOT fuzzy matching).
///
/// The folding table contract (task 1.2):
/// - case folding: ASCII lower case,
/// - German umlauts fold to their *dictionary* expansions: `ä→ae`,
///   `ö→oe`, `ü→ue`, `ß→ss`,
/// - remaining Latin accents are stripped to the base letter (`é→e`).
///
/// Because the SAME function folds query and field, searching "wohnung"
/// matches a synopsis containing "Wohnung" but NOT one containing only
/// "Woehnung" (the expansion changes the string — the spec's explicit
/// boundary case is table-tested in `name_prefilter_test.dart`).
///
/// No packages: the accent table is a hand-rolled const map over the
/// characters the production data can realistically contain (German,
/// Latin-script names). A character outside the table passes through
/// unchanged, so an unlisted letter can never produce a false match.
library;

/// The exact folding expansion each input character maps to.
///
/// HELD in one map so the "one pure function" contract (design risk table)
/// has a single source; the matcher tests pin every entry.
const Map<String, String> _foldTable = <String, String>{
  'ä': 'ae',
  'ö': 'oe',
  'ü': 'ue',
  'ß': 'ss',
  // Accented Latin letters → base letter (post-umlaut; case already
  // folded). Includes the common romantic-script names found in cast/
  // piece data (José, Zoé, Chloé, François, Loïc …).
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'å': 'a',
  'ç': 'c',
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
  'ñ': 'n',
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o',
  'ù': 'u', 'ú': 'u', 'û': 'u',
  'ý': 'y', 'ÿ': 'y',
  'œ': 'oe', 'æ': 'ae',
};

/// Folds [input] to the search-normalized form.
///
/// `toLowerCase` FIRST (uppercase accented letters — `Ä`, `É` — fold
/// correctly as an artifact of Dart's locale-independent lowercasing), then
/// character-wise table expansion. Whitespace is NOT normalized: a query's
/// interior spacing must match the field's spacing (dictionary folding).
String foldForSearch(String input) {
  final lowered = input.toLowerCase();
  if (lowered.isEmpty) return lowered;

  final buffer = StringBuffer();
  for (final char in lowered.runes) {
    buffer.write(
      _foldTable[String.fromCharCode(char)] ?? String.fromCharCode(char),
    );
  }
  return buffer.toString();
}

/// Case- and diacritics-insensitive substring test.
///
/// Both arguments are folded once per search call site (the query and the
/// pre-folded field), so this helper takes ALREADY-folded values — the
/// fold happens exactly once per call site, never per row comparison.
bool foldedContains(String foldedHaystack, String foldedNeedle) =>
    foldedHaystack.contains(foldedNeedle);
