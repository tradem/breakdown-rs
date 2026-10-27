// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)
// Co-authored-by: glm-5.3-flash (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

library;

import 'package:breakdown_api/breakdown_api.dart';

/// Tier-1 pure model of the OmniSearch facet search (OpenSpec change
/// `add-omni-search`, tasks §1.1).
///
/// No Flutter imports, no Drift, no Riverpod: the facet vocabulary, the
/// cached-data inputs and the matched-result types. The canonical result
/// group order IS the enum declaration order (design D3): scenes → roles
/// (characters) → costumes → shooting days. Dart guarantees enum `index`
/// follows declaration order, so the UI sort needs no separate order table.
///
/// All fields a user is allowed to search are pinned by the spec
/// (`flutter-omni-search`, name-prefilter requirement) and enforced by the
/// matchers in `omni_search_matcher.dart`:
/// - scene: scene number prefix + summary (synopsis),
/// - character: name,
/// - costume: notes (description) + category name ONLY (design open
///   question 2: no `details`/`photos` creep),
/// - shooting day: label or date.
///
/// The AI-import cache tables are deliberately absent from the input types
/// — regression-tested in `omni_search_cache_dao_test.dart` (tasks §5.1).

/// A type-erased hit. The sealed class hierarchy keeps the deep-link
/// destination switch exhaustive (compile-checked — a new facet cannot
/// forget its destination mapping).
sealed class OmniSearchHit {
  const OmniSearchHit();
}

/// One searchable entity type. The chip labels (de) ship from the l10n
/// catalog ("Szene", "Rolle", "Kostüm", "Drehtag"); this enum is the
/// machine identity behind them and also the display order (D3).
enum OmniSearchFacet { scene, character, costume, shootingDay }

/// All four facets active by default (spec: no mixed single list, four
/// toggleable chips with the shipped German copy).
const Set<OmniSearchFacet> kAllOmniSearchFacets = <OmniSearchFacet>{
  OmniSearchFacet.scene,
  OmniSearchFacet.character,
  OmniSearchFacet.costume,
  OmniSearchFacet.shootingDay,
};

/// Whether a facet's cache source is considered "loaded" (has delivered a
/// complete projection snapshot) from the search surface's point of view.
///
/// The search reads the client cache only (D1); the DAO cannot distinguish
/// "genuinely empty" from "never fetched" for an empty cache (snapshot
/// replaces leave no marker rows). The controller therefore tracks which
/// sources a completed bounded prefresh pass has refreshed — a facet that
/// was refreshed and still has no rows is genuinely empty (zero-match
/// applies), one that was never refreshed is
/// [OmniSearchFacetLoad.notYetFetched].
enum OmniSearchFacetLoad {
  /// Somethings was loaded for this facet (even if that snapshot was empty):
  /// zero-match copy applies, not a loading notice.
  loaded,

  /// No data source has delivered a snapshot for this facet yet: the
  /// distinct "not yet loaded" note is shown (never zero-match copy).
  notYetFetched,
}

/// Facet-scoped freshness/staleness verdict computed at DAO time from the
/// client-only `cachedAt` columns (TTL semantics — no new freshness
/// semantics, task 3.4 / design D1).
///
/// Per-facet: the scene/shooting-day facets are hierarchy-backed (their
/// rows join through `episode`/`block`), so staleness considers EVERY
/// involved table's `cachedAt` of the season path; characters/costumes
/// cover their own table.
class OmniSearchFacetState {
  const OmniSearchFacetState({required this.facet, required this.stale});

  final OmniSearchFacet facet;

  /// True when any `cachedAt` of the facet's contributing cache rows is
  /// older than the cache TTL (`cache_ttl.dart` semantics).
  final bool stale;
}

/// One scene hit with the hierarchy DTOs the row display AND the deep-link
/// push consume (same contract as `ScriptSceneRow`: no second projection
/// lookup to fill in navigation context).
class SceneOmniHit extends OmniSearchHit {
  const SceneOmniHit({
    required this.scene,
    required this.episode,
    required this.block,
  });

  final SceneView scene;
  final EpisodeView episode;
  final BlockView block;
}

/// One character (role) hit.
class CharacterOmniHit extends OmniSearchHit {
  const CharacterOmniHit({required this.character});

  final CharacterView character;
}

/// One costume hit.
class CostumeOmniHit extends OmniSearchHit {
  const CostumeOmniHit({required this.costume});

  final PieceView costume;
}

/// One shooting-day hit with the parent episode/block DTOs.
class ShootingDayOmniHit extends OmniSearchHit {
  const ShootingDayOmniHit({
    required this.day,
    required this.episode,
    required this.block,
  });

  final ShootingDayView day;
  final EpisodeView episode;
  final BlockView block;
}

/// The cached search universe of ONE active season (read-only composition
/// over the existing projection-cache tables — no new cache schema).
class OmniSearchInputs {
  const OmniSearchInputs({
    required this.seasonId,
    required this.scenes,
    required this.characters,
    required this.costumes,
    required this.shootingDays,
    required this.facetStates,
    required this.hasHierarchyRows,
    required this.hasCharacterRows,
    required this.hasCostumeRows,
  });

  final String seasonId;

  /// Season's scenes in script order (scene number, episode tie-breaker)
  /// with their parent hierarchy DTOs.
  final List<SceneOmniHit> scenes;

  /// Season's characters in cache snapshot order.
  final List<CharacterOmniHit> characters;

  /// Season's costumes (the costume scope is the seasonal snapshot; the
  /// repertoire cross-season dimension is a fundus NON-goal — proposal).
  final List<CostumeOmniHit> costumes;

  /// Season's shooting days in server order (`order_key ASC` — the client
  /// never re-sorts) with parent DTOs.
  final List<ShootingDayOmniHit> shootingDays;

  /// Per-facet TTL staleness verdicts.
  final List<OmniSearchFacetState> facetStates;

  /// Whether the season's hierarchy cache currently holds ANY block rows.
  ///
  /// NOT a "was fetched" flag: a valid empty block snapshot deletes all
  /// block rows and is thus indistinguishable from "never fetched" at the
  /// cache level (snapshot-replace leaves no marker). The controller
  /// resolves the transient case by marking a facet `loaded` after a
  /// completed bounded prefresh pass (`OmniSearchSourceRefresher`) — zero
  /// rows then mean genuinely empty, and the zero-match copy applies
  /// instead of the not-yet-loaded note.
  final bool hasHierarchyRows;

  /// Whether the characters cache holds any rows for the season (see
  /// [hasHierarchyRows] for the honest semantics limit).
  final bool hasCharacterRows;

  /// Whether the costume cache holds any rows for the season (see
  /// [hasHierarchyRows] for the honest semantics limit).
  final bool hasCostumeRows;

  OmniSearchFacetState facetState(OmniSearchFacet facet) =>
      facetStates.firstWhere((s) => s.facet == facet);

  bool get isEmpty =>
      scenes.isEmpty &&
      characters.isEmpty &&
      costumes.isEmpty &&
      shootingDays.isEmpty;

  bool get anyStale => facetStates.any((s) => s.stale);
}

/// One result group of the grouped result list (D3): a facet type plus its
/// matched hits in canonical order. Group classes are the tier of data the
/// widget list renders; empty groups are ABSENT (spec: "absent, not merely
/// empty").
class OmniSearchGroup {
  const OmniSearchGroup({required this.facet, required this.hits});

  final OmniSearchFacet facet;

  final List<OmniSearchHit> hits;

  bool get isEmpty => hits.isEmpty;
}
