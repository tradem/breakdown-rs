<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3-flash (opencode-go) -->

# add-omni-search — implementation tasks

## 1. Search core logic (Tier-1, pure)

- [ ] 1.1 Create `lib/features/omni_search/` feature folder; define the pure search model: facet enum (scene/character/costume/shooting_day), query state (active facets + text prefilter), and result-group types with the canonical group order (scenes → roles → costumes → shooting days per design D3)
- [ ] 1.2 Implement the pure diacritics-folding function for the name prefilter (case-fold + `ä→ae`, `ö→oe`, `ü→ue`, `ß→ss`, accents stripped) with table-driven unit tests (including the spec's "Wohnung"/"Woehnung" boundary case)
- [ ] 1.3 Implement per-facet matchers over cached read DTO field sets — pin the exact fields per spec: scene (number prefix + synopsis), character (name), costume (description + category only), shooting day (label/date) — pure functions, unit tested, no Flutter imports

## 2. Cache access (DAO reuse)

- [ ] 2.1 Add read-only DAO methods for facet input data (reuse existing `hierarchy_cache`, costume-domains, scene-shoot, seasons tables — add queries only; no schema change unless §2.4 triggers it)
- [ ] 2.2 Measure at implementation whether prefilter runs in SQL (normalized column / `LIKE`) or Dart-side on materialized lists; document the decision per design D2 in the DAO doc comments
- [ ] 2.3 Unit tests: DAO queries return exactly the active-season scope (season scoping respected, no cross-season rows leak); empty/unfetched cache yields the distinguishable not-yet-fetched state (zero-match vs. cold cache)
- [ ] 2.4 Only if SQL-side filtering requires normalized columns: Drift schema bump + migration steps per the cache DB's migration discipline (no other trigger)

## 3. Search UI surface

- [ ] 3.1 Build the OmniSearch surface widget: top-bar-search-triggered route (per #613 slot), facet chip row in shipped German copy "Szene" / "Rolle" / "Kostüm" / "Drehtag" (all active by default), text field, grouped result list (localized group headers in D3 order)
- [ ] 3.2 Result rows: per-type context labeling ("Szene 12 · Wohnung — Zoe" style), keyed test targets, tap → deep link via the shared `SearchDestination` mapping (design D4) that resolves to the same routes/screens the #610 nav views use
- [ ] 3.3 States per spec: initial empty state, zero-match state (echoing the active facets), error state (storage failure → localized problem copy + retry, `Result`/`ProblemError` conventions), no-active-season empty state
- [ ] 3.4 Staleness honesty: reuse the established stale indicators for cache-derived views on hit groups; bounded-retry refetch on surface open / user retry (no new freshness semantics)

## 4. Shell integration

- [ ] 4.1 Top-bar search entry point in `lib/features/shell/` (both morphologies: bottom `NavigationBar` and wide `NavigationRail`), consuming the #613 slot; entry opens the surface, is NOT a bottom-bar destination tab
- [ ] 4.2 Wire active-season watch from the shell (ActiveScopeChip-consistent scoping); season switch while surface open re-computes over the new season only (spec scenario)
- [ ] 4.3 Accessibility: semantic labels for the search affordance, facet chips toggle states, and result rows (de/en)

## 5. AI-import exclusion guard

- [ ] 5.1 Add a regression test asserting AI-import draft/preview data (unapplied `draft_ref` surfaces) can never appear in results — guard against future accidental inclusion of the AI cache tables in the facet queries

## 6. Localization

- [ ] 6.1 l10n keys (de/en) in `app_de.arb`/`app_en.arb`: group headers, chips, all three surface states, deep-link row labels; regenerate localized classes
- [ ] 6.2 Confirm no Fluent/problem-code coupling is needed (search is client-local; error copy reuses the settings-screen error issuance pattern)

## 7. Tests & integration

- [ ] 7.1 Widget tests: facet toggling restricts groups per spec scenario ("Kostüm"-only yields costume rows only), default = all four facets, deep links open the correct destination screens, zero-match/error/empty states render per copy
- [ ] 7.2 Deep-link contract test: the `SearchDestination` mapping is exercised against every referenced route/screen — fails on target renames/removals during the #610 redesign (per spec requirement)
- [ ] 7.3 Gherkin feature file (`features-spec/`): "search across the season from the top bar" happy path + one facet-restriction scenario, wired to the on-device keys
- [ ] 7.4 Offline scenario test: search works fully from cache with connectivity stubs off

## 8. Sequence & governance

- [ ] 8.1 Coordinate landing order with the #610 redesign: if this change lands first, keep the `SearchDestination` mapping single-pointed so the redesign overlays it; if after, wire directly to the new screens
- [ ] 8.2 Cross-link in GitHub issue #613 (concept captured here; close the "concept needed" thread against this change)
- [ ] 8.3 Verify spec compliance pass: walk all `flutter-omni-search` scenarios against the implementation before marking change complete
- [ ] 8.4 Record the fundus-search follow-up as its own future change (`flutter-fundus-search`, depending on #534 repertoire aggregate; ADR-035) in the OpenSpec backlog notes — explicitly NOT part of this change's tasks
