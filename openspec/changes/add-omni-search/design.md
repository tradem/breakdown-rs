<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3-flash (opencode-go) -->

## Context

The MiniOmnisearch idea originates in GitHub issues #613 (top-bar slot, "concept needed first") and #610 (three-view navigation redesign: Cast / Script / Schedule-Dispo). PO questions during explore crystallized it into a **facet-driven, active-season-scoped data search** — not free-form full-text. Verified facts:

- **No backend search exists** (`backend/openapi.yaml` has no search routes; verified) — and with facets, none is needed for v1.
- **The client already caches the universe to search:** `lib/data/cache/` (Drift/SQLite) holds hierarchy (scenes), characters, costume domains, scene-shoots, seasons and shell state — the same DTOs the read screens consume. A search over these rows is exactly "search what you already see".
- **Season scoping threads through the shell** (ActiveScopeChip pattern in `flutter-hierarchy-navigation`); consuming it is a read of the shell's active-season state, not a second projection call (CQRS mirror rule respected).
- Data sizes per season are small (≈ 40 scenes, dozens of characters/costumes/shooting days) — client SQL filtering is trivially fast; no ranking/index infrastructure is justified.

## Goals / Non-Goals

**Goals:**
- One search surface per the `flutter-omni-search` spec: top-bar entry, four facet chips ("Szene", "Rolle", "Kostüm", "Drehtag"), name prefilter, grouped results with deep links into the #610 destination screens.
- Full v1 **client-only** — offline-capable, zero backend work, zero OpenAPI client regeneration.
- Honest cache-staleness treatment reusing existing patterns (no new freshness semantics).
- German/English localization of all search surface copy.

**Non-Goals:**
- AI-import drafts in results (PO-confirmed exclusion — drafts are not domain data yet).
- Action execution in the search field (deferred; future voice/LLM prompting is a separate exploration — PO remark).
- Backend search routes or full-text/trigram/index infrastructure (phase-2 necessity dissolved by the facet decision; revisit only if cohort data grows beyond cache-fit, or the fundus needs it).
- **Costume fundus (repertoire) search** — per PO decision it is anchored as a *future capability* (`flutter-fundus-search`), cross-season by definition and dependent on the repertoire aggregate work (GitHub issue #534, ADR-035 "repertoire seasons ∪ character's season"). It gets its own change; this design only pins the seam: the fundus facet is deliberately absent from the four chips.

## Decisions

### D1 — Search runs over the Drift cache, not the network
**Decision:** v1 filters cached read DTOs via Drift DAOs (SQL `LIKE` on normalized columns or Dart-side filtering on materialized lists — measured at implementation; both single-digit-ms at domain scale).
**Why:** the searched universe *is* the cached universe — the user cannot logically expect to find entities their app surface has never rendered. Offline-first as a free side effect; no new API surface, no authz re-verification (cache only holds authorized views).
**Alternative rejected: backend composite `/v1/search`** — server truth, seemingly "fresher"; but (a) requires a new route + OpenAPI regen + drift-check + authz policy across projections, (b) violates nothing but buys freshness the screens themselves don't promise (they show cached data with stale indicators too). If that asymmetry ever bites, a slim backend route is a clean follow-up change — the spec's deep-link and grouping contracts don't change.

### D2 — Facets are type chips, the text field is a name prefilter
**Decision:** the four chips set which entity types are searched; the typed text filters within them (case/diacritics-insensitive substring on naming fields).
**Why:** PO-confirmed facet model. Deliberately not: natural-language queries, ranking, fuzzy/typo tolerance (Obsidian-Omnisearch-style BM25) — at 40 scenes/silo those are complexity without payoff; the domain's own vocabularies are what users type.
**Normalization approach:** store/compare on a diacritics-folded projection of the naming field or fold in Dart (`é→e`, `ä→ae` per the prefilter contract in the spec) — implementation detail measured into the DAO tests; no hardcoding beyond the folding table.

### D3 — Results group canonical order scenes → roles → costumes → shooting days
**Decision:** fixed, localized group headers in that order. Rationale: the Schedule/Dispo thinking dominates day-to-day planning flow; scenes are the organizing unit; the groups mirror the three nav views plus costume content.
**Alternative:** result-type mix by "best match" — rejected: no ranking inputs exist (no click model, no weights), so a mix adds arbitrary ordering without meaning.

### D4 — Deep links reuse the #610 destination screens exactly
**Decision:** result rows navigate through the same route providers/screens the nav views use; `RouteSettings`-based shell context (the existing `PlanningLocation` pattern) as needed. No parallel "search result" routing.
**Sequencing note:** this change consumes the route map produced by #610 — implement the deep-link wiring against those screens; if landed before the redesign, wire to current screens and keep the mapping in one place (a small `SearchDestination` function) so the redesign overlays it.

### D5 — No new backend artifact in this change
`backend/openapi.yaml`, problem codes, and OpenAPI drift discipline are untouched. Interaction with `OPENAPI regen` pipeline: none. Backend teams need not review, beyond confirming the non-goal carve-outs (see Open Questions).

## Risks / Trade-offs

- [Phase-1 results lag the server (only cached entities searchable)] → Mitigation: staleness honesty is a spec requirement; reconcile-on-open uses the bounded-retry refetch pattern already used by read screens. The fundus/phase-2 backend route remains the escape hatch.
- [Cache coverage gap: a facet with cold/never-fetched data returns empty] → Mitigation: search surface refreshes the facet's data source on open (bounded retry, same as screen entry), and zero-match vs. not-yet-fetched states are distinct in UI copy decisions (see tasks).
- [Deep-link churn during #610] → Mitigation: D4's single `SearchDestination` mapping point; deep-link tests fail loudly on route renames.
- [Diacritics folding table drift (ä/ae, ß/ss …)] → Mitigation: folding lives in one pure function with Tier-1 table tests; German compound handling (Woehnung vs Wohnung) documented as exact-match concern, not fuzzy.
- [Scope creep: "just search fundus too this change"] → Mitigation: proposal lists fundus as future capability by explicit PO decision; the chip set is contractually exactly four.

## Migration Plan

Client-only — deploy ships with the app. No data migration (read-only over existing cache schema; if a normalized search column proves necessary, a Drift schema bump + `MIGRATION` steps land in the cache DB per its existing migration discipline, in tasks). Rollback = feature removal at composition root (no persisted state besides cache reuse).

## Open Questions

1. Prefresh-on-open vs. pure-cache-first render when entering the search surface (bounded retry exists either way) — settle during implementation perf measurement; does not change the spec.
2. Compression of the costume facet's naming field: costume descriptions are long; confirm the prefilter only matches on the costume's `description` and category — no summary/notes creep (tasks pin the exact fields).
3. Future voice/LLM command surface (PO idea): track as its own exploration someday; no architectural hook reserved here beyond keeping the search surface pure-data.
