// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)
// Co-authored-by: glm-5.3-flash (neuralwatt)

/// Tier-1 pure per-facet matchers over cached read DTO fields (tasks §1.3).
///
/// The searched fields are PINNED by the spec (`flutter-omni-search`,
/// name-prefilter requirement) and enforced HERE — the only place where DTO
/// field names participate in the match:
/// - scene: scene number PREFIX (string startsWith on the number, only
///   meaningful for numeric queries) and the `summary` (synopsis) substring,
/// - character: `name` substring,
/// - costume: `notes` (description) + `categoryName` substring ONLY
///   (design open question 2: `details`/`photos` never participating),
/// - shooting day: `label` or the ISO date string substring.
///
/// Matching is OR over the facet's own fields. A text query can therefore
/// still match the scene's summary while the number doesn't (and vice
/// versa).
library;

import 'name_prefilter.dart';
import 'omni_search_model.dart';

/// One composed search execution: which facets the query ran over and the
/// grouped hits in D3 canonical order.
class OmniSearchResults {
  const OmniSearchResults({required this.groups, required this.activeFacets});

  final List<OmniSearchGroup> groups;

  final Set<OmniSearchFacet> activeFacets;

  bool get isEmpty => groups.every((g) => g.isEmpty);
}

/// Runs the prefilter over the season's cached inputs for [activeFacets]
/// and returns the grouped hits in the ONE canonical order (D3: scenes →
/// characters → costumes → shooting days).
///
/// Pure: no I/O, no clock, no Riverpod — unit tested directly (tasks 1.3).
/// Empty groups are dropped here already ("absent, not merely empty").
OmniSearchResults composeOmniSearchResults(
  OmniSearchInputs inputs,
  String rawQuery,
  Set<OmniSearchFacet> activeFacets,
) {
  // Trim BEFORE folding (CodeRabbit review): a whitespace-only query must
  // not turn into a non-empty folded needle that matches every field with
  // a space in it — it degrades to the initial state. INTERIOR spacing
  // stays untouched (the dictionary-folding contract).
  final folded = foldForSearch(rawQuery.trim());
  final seenFacets = <OmniSearchFacet>{};
  final groups = <OmniSearchGroup>[];

  void addGroupIfHits(OmniSearchFacet facet, List<OmniSearchHit> hits) {
    if (!activeFacets.contains(facet)) return;
    seenFacets.add(facet);
    if (hits.isEmpty) return;
    groups.add(OmniSearchGroup(facet: facet, hits: hits));
  }

  addGroupIfHits(OmniSearchFacet.scene, [
    for (final hit in inputs.scenes)
      if (sceneMatches(hit, folded)) hit,
  ]);
  addGroupIfHits(OmniSearchFacet.character, [
    for (final hit in inputs.characters)
      if (characterMatches(hit, folded)) hit,
  ]);
  addGroupIfHits(OmniSearchFacet.costume, [
    for (final hit in inputs.costumes)
      if (costumeMatches(hit, folded)) hit,
  ]);
  addGroupIfHits(OmniSearchFacet.shootingDay, [
    for (final hit in inputs.shootingDays)
      if (shootingDayMatches(hit, folded)) hit,
  ]);

  return OmniSearchResults(groups: groups, activeFacets: seenFacets);
}

/// Scene facet: number prefix (only for numeric queries — a non-numeric
/// query can never prefix a digit string) OR summary substring.
bool sceneMatches(SceneOmniHit hit, String folded) {
  if (folded.isEmpty) return false;
  final scene = hit.scene;
  final number = scene.sceneNumber;
  if (number != null && looksNumeric(folded)) {
    if ('$number'.startsWith(folded)) return true;
  }
  final summary = scene.summary;
  if (summary != null && foldForSearch(summary).contains(folded)) {
    return true;
  }
  return false;
}

/// Character facet: the name only.
bool characterMatches(CharacterOmniHit hit, String folded) =>
    foldForSearch(hit.character.name).contains(folded) && folded.isNotEmpty;

/// Costume facet: notes + category name ONLY (design open question 2).
bool costumeMatches(CostumeOmniHit hit, String folded) {
  if (folded.isEmpty) return false;
  final costume = hit.costume;
  if (foldForSearch(costume.notes).contains(folded)) return true;
  final category = costume.categoryName;
  return category != null && foldForSearch(category).contains(folded);
}

/// Shooting-day facet: label or ISO date.
bool shootingDayMatches(ShootingDayOmniHit hit, String folded) {
  if (folded.isEmpty) return false;
  final day = hit.day;
  final label = day.label;
  if (label != null && foldForSearch(label).contains(folded)) return true;
  final date = day.date;
  if (date != null && foldForSearch(date.toString()).contains(folded)) {
    return true;
  }
  return false;
}

/// Whether [folded] is a (possibly partial) plain digit run — the signal
/// the scene number can only match as a PREFIX on.
bool looksNumeric(String folded) {
  for (final c in folded.runes) {
    final ch = String.fromCharCode(c);
    if (ch.compareTo('0') < 0 || ch.compareTo('9') > 0) return false;
  }
  return true;
}
