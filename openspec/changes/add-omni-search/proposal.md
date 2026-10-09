<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3-flash (opencode-go) -->

## Why

The redesigned navigation (bottom bar with **Cast**, **Script**, **Schedule/Dispo** views, see GitHub issue #610) gives users three fast task-oriented views, but there is **no way to ask "where is X?"** across them: finding which scenes contain character "Zoe", which scene wears costume "Marineblau", or which shooting day scenes 12–14 sit on currently requires browsing each view and filtering manually. A central search field at the top of the app — the PO's "OmniSearch" — closes that gap. The UX-industry term for this pattern is a **global search with universal (grouped) results**; "OmniSearch" stays our internal product name.

Importantly, the PO's follow-up questions pinned this down to a **facet-driven search, not free-form full-text**: users pick a *type* (scene, character, costume, shooting day) and prefilter with a quick name fragment. That concretely shapes the solution: the app already caches the complete season read-model data client-side (Drift/SQLite), so a fully working v1 is achievable **client-only** — no backend search infrastructure needed.

## What Changes

- **New top-bar search entry point** in the client: a search affordance in the top bar (bar placement per GitHub issue #613) opening the search surface.
- **Facet-driven search over the active season's client cache**: type chips (Scene · Role · Costume · Shooting day) + quick text prefilter over cached read DTOs (Drift). Results grouped by type, each row deep-links into the corresponding destination screen of the redesigned navigation.
- **Scope rule: the active season only** (season scoping already threads through the shell; the ActiveScopeChip pattern from `flutter-hierarchy-navigation` is the reference).
- **Explicit non-goals (PO-confirmed):**
  - **No AI-import draft surfaces in results** — only data that is actually part of the domain (imported *and applied*, or manually created).
  - **No action execution** ("new scene" etc.) in the search field — data search only. Future command-driven access (voice / integrated LLM prompting) may come later, out of scope here.
  - **No full-text/fuzzy/trigram backend infrastructure** — phase 2 necessity dissolved by the facet decision; if later needed, a slim backend query route is a follow-up change.
- **Costume fundus (repertoire) search is NOT part of this change** (PO decision): the fundus is cross-season (costume repertoire per ADR-035, aggregate work tracked in GitHub issue #534). It is anchored here as a *future capability* (`flutter-fundus-search`, feeding on the repertoire read models) so the search concept names it without dragging its scope into this change's tasks.

## Capabilities

### New Capabilities

- `flutter-omni-search`: the client search surface — top-bar entry, facet chips (Scene/Role/Costume/Shooting day), name-prefilter over the active season's cached read DTOs, grouped results with deep links, projector-lag/staleness honesty (cached-data caveat), and localization (de/en).

### Modified Capabilities

- None — no existing spec-level behavior changes. (`flutter-hierarchy-navigation`'s season scoping and the cache stack are consumed, not modified. The top-bar placement overlaps GitHub issue #613's profile/settings work; that issue remains the design carrier for the bar, this change consumes the slot.)

## Impact

- **Code (frontend only):** `frontend-flutter/lib/features/` (new search feature folder per the one-screen-per-query convention), `lib/data/cache/*` (read-only DAO reuse; no schema change expected for filtering on cached DTO fields), shell/top-bar integration in `lib/features/shell/`, l10n ARBs (`app_de.arb`/`app_en.arb` + generated localizations).
- **No backend/API changes** in this change (`backend/openapi.yaml` untouched → no Dart client regeneration, no drift-check run).
- **Navigation integration risk:** deep links from results into destination screens interact with the #610 navigation redesign; this change must be sequenced with it (deep-link targets = that change's screens), noted in design/tasks.
- **Testing:** widget tests on the search surface (facets, grouping, deep links, stale-cache banner), Drift DAO query tests; no new integration-test tier needed (client-only).
