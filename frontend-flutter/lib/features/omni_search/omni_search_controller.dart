// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)
// Co-authored-by: glm-5.3-flash (neuralwatt)

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/result.dart';
import '../../data/cache/seasons_cache_providers.dart';
import '../../data/omni_search_cache_dao.dart';
import 'omni_search_matcher.dart';
import 'omni_search_model.dart';
import 'omni_search_refresher.dart';

part 'omni_search_controller.g.dart';

/// The search input DAO (tasks §2.1): one read-only composition seam over
/// the existing cache tables, injectable in tests.
@riverpod
OmniSearchDao omniSearchDao(Ref ref) =>
    OmniSearchDao(ref.watch(cacheDatabaseProvider));

/// The seasonal search inputs — THE QUERY PATH (tasks §2.1, D1).
///
/// READ-ONLY cache composition; the search itself NEVER issues a network
/// call (spec: `flutter-omni-search` name-prefilter + offline scenarios).
/// Cache freshness arrives via the bounded prefresh pass
/// (`OmniSearchSourceRefresher`), which is the only seam that may touch the
/// network — on surface open or on explicit user retry.
@riverpod
Future<Result<OmniSearchInputs>> omniSearchInputs(Ref ref, String seasonId) =>
    ref.watch(omniSearchDaoProvider).readSeasonInputs(seasonId);

/// The typed query state: the text prefilter plus the active facets.
///
/// ALL FOUR facets active by default (spec); every change rebuilds the
/// composed results synchronously — no debounce, no network (domain-scale
/// filtering is single-digit-ms, verified in the matcher tests).
class OmniSearchQueryState {
  const OmniSearchQueryState({
    this.text = '',
    this.facets = kAllOmniSearchFacets,
  });

  final String text;
  final Set<OmniSearchFacet> facets;
}

/// Notifier family per active season (task 4.2): the season switch
/// re-computes over the new season only — the family key IS the scope.
@riverpod
class OmniSearchQuery extends _$OmniSearchQuery {
  @override
  OmniSearchQueryState build(String seasonId) => const OmniSearchQueryState();

  void setText(String text) =>
      state = OmniSearchQueryState(text: text, facets: state.facets);

  /// Toggle a facet chip. The LAST active facet cannot be deselected away
  /// to nothing? It can — an empty facet selection is a legitimate surface
  /// state the zero-match copy covers by echoing no chips (spec void
  /// handling: results "always grouped by facet type", so zero facets =
  /// zero groups).
  void toggleFacet(OmniSearchFacet facet) {
    final facets = {...state.facets};
    if (!facets.remove(facet)) facets.add(facet);
    state = OmniSearchQueryState(text: state.text, facets: facets);
  }
}

/// The renderable search surface state (task 3.3): which state is on
/// screen and which groups render. Pure derivation — unit tested directly.
class OmniSearchViewState {
  const OmniSearchViewState({
    required this.text,
    required this.activeFacets,
    required this.groups,
    required this.zeroMatch,
    required this.notLoadedFacets,
    required this.consultedFacets,
    required this.anyStale,
  });

  /// The current prefilter text (the field keeps its own controller; this
  /// mirrors the state the results were composed from).
  final String text;

  final Set<OmniSearchFacet> activeFacets;

  /// Matched groups in D3 canonical order; groups with zero hits are
  /// ABSENT (not merely empty).
  final List<OmniSearchGroup> groups;

  /// Non-empty query, no hits anywhere, AND every active facet's source
  /// has answered (loaded). Zero-match copy then echoes the knowingly
  /// searched facets — facets whose source never answered were not
  /// searched and get the not-yet-loaded note instead.
  final bool zeroMatch;

  /// Active facets whose source has NOT delivered data yet (cold cache):
  /// the "not yet loaded" note names them — never silently empty.
  final Set<OmniSearchFacet> notLoadedFacets;

  /// The KNOWINGLY searched facets: active minus not-loaded — the set the
  /// zero-match echo names. Empty when every queried source is still
  /// unanswered; the surface then renders ONLY the not-yet-loaded notes
  /// (no zero-match sentence claiming ground truth it does not have).
  final Set<OmniSearchFacet> consultedFacets;

  /// TTL staleness across the facet sources backing the CURRENT results
  /// (established cache-generation semantics — same treatment the read
  /// screens give their cache-derived views).
  final bool anyStale;

  bool get hasHitGroups => groups.isNotEmpty;
}

/// Pure mapping of a facet's load state from the pass marks and the cache
/// row presence (the honest semantics boundary documented in
/// `OmniSearchInputs.hasHierarchyRows`).
OmniSearchFacetLoad omniSearchFacetLoad(
  OmniSearchFacet facet, {
  required OmniSearchInputs inputs,
  required Set<OmniSearchFacet> passLoaded,
}) {
  final cacheHasRows = switch (facet) {
    OmniSearchFacet.scene ||
    OmniSearchFacet.shootingDay => inputs.hasHierarchyRows,
    OmniSearchFacet.character => inputs.hasCharacterRows,
    OmniSearchFacet.costume => inputs.hasCostumeRows,
  };
  return (passLoaded.contains(facet) || cacheHasRows)
      ? OmniSearchFacetLoad.loaded
      : OmniSearchFacetLoad.notYetFetched;
}

/// The search-surface controller (task 3.3/3.4): maps the inputs `Result`
/// into [OmniSearchViewState], never discarding an `Err` (the client analog
/// of the backend `discard-result` rule — storage failure SURFACES as the
/// error state with a retry, never as silent empty ground truth).
@Riverpod(keepAlive: false)
class OmniSearchController extends _$OmniSearchController {
  /// Retained last-good view across INPUT reloads (the retained-rows
  /// pattern the read screens use): the bounded prefresh pass invalidates
  /// the inputs provider, and the surface keeps rendering the composed
  /// previous cache state while the reload is in flight (the stale banner
  /// covers honesty) instead of flashing a full-surface spinner.
  OmniSearchViewState? _retained;

  @override
  AsyncValue<OmniSearchViewState> build(String seasonId) {
    final inputs = ref.watch(omniSearchInputsProvider(seasonId));
    return switch (inputs) {
      AsyncLoading() =>
        _retained == null
            ? const AsyncValue<OmniSearchViewState>.loading()
            : AsyncValue<OmniSearchViewState>.data(_retained!),
      AsyncError(:final error, :final stackTrace) =>
        AsyncValue<OmniSearchViewState>.error(error, stackTrace),
      AsyncData(:final value) => value.match(
        // A storage failure SURFACES as AsyncError; the retained rows stay
        // for the pull-to-refresh path (never silently discarded).
        (error) =>
            AsyncValue<OmniSearchViewState>.error(error, StackTrace.current),
        (data) =>
            AsyncValue<OmniSearchViewState>.data(_retained = _derive(data)),
      ),
    };
  }

  OmniSearchViewState _derive(OmniSearchInputs inputs) {
    final query = ref.watch(omniSearchQueryProvider(seasonId));
    final passLoaded = ref.watch(omniSearchFacetLoadsProvider(seasonId));
    final results = composeOmniSearchResults(inputs, query.text, query.facets);

    final notLoaded = {
      for (final facet in query.facets)
        if (omniSearchFacetLoad(
              facet,
              inputs: inputs,
              passLoaded: passLoaded,
            ) ==
            OmniSearchFacetLoad.notYetFetched)
          facet,
    };
    final consulted = query.facets.difference(notLoaded);
    final staleFacets = {
      for (final state in inputs.facetStates)
        if (state.stale) state.facet,
    };
    return OmniSearchViewState(
      text: query.text,
      activeFacets: query.facets,
      groups: results.groups,
      // Zero-match = a typed query hits nothing anywhere. The copy echoes
      // the KNOWINGLY SEARCHED (loaded) facets (surface
      // `consultedFacets`); surfaces that never answered are named by the
      // not-yet-loaded notes, never swallowed into the zero-match
      // sentence.
      zeroMatch: query.text.isNotEmpty && results.groups.isEmpty,
      notLoadedFacets: notLoaded,
      consultedFacets: consulted,
      anyStale: staleFacets.where((f) => query.facets.contains(f)).isNotEmpty,
    );
  }

  /// Retry after the ERROR state (a storage failure): re-read the cache.
  /// The pass itself is not re-run — the error state is about the cache
  /// being unreadable, so the retry re-reads it; if storage is still
  /// broken the error state stays (honest, never silent empty).
  void retryAfterError() => ref.invalidate(omniSearchInputsProvider(seasonId));

  void setText(String text) =>
      ref.read(omniSearchQueryProvider(seasonId).notifier).setText(text);

  void toggleFacet(OmniSearchFacet facet) =>
      ref.read(omniSearchQueryProvider(seasonId).notifier).toggleFacet(facet);

  /// User retry (pull-to-refresh / stale banner): another bounded pass
  /// through the established seams; a cache re-read flows into this
  /// controller via the invalidated inputs provider.
  Future<void> refresh() =>
      ref.read(omniSearchSourceRefresherProvider).prefresh(seasonId);
}
