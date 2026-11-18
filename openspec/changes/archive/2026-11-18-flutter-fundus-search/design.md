<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (neuralwatt) -->

## Context

Issue #625 anchors the **costume fundus (repertoire)** as a future
capability carved out of `add-omni-search` (PO decision, design D-non-goal:
the OmniSearch chip set is contractually exactly four). The dependency —
issue #534, the repertoire as real aggregate state — has landed:

- `CostumeView.season_ids` is on the wire (`projection_costume_season` is
  truly m:n) and mirrored in the client cache
  (`costume_cache_rows.season_ids_json`, migration v12).
- The backend already exposes `GET /v1/costumes?project_id=…` (in addition
  to `season_id` / `episode_id`), and the generated Dart client carries the
  `projectId` parameter — no OpenAPI work is required.
- The client's `SeasonCacheRows` carries `project_id` (issue #599), so the
  shell's active season yields the active project.

Constraints that shape the design:

- **CQRS on the client:** screens read flattened projection DTOs from the
  Drift cache; commands are never derived from a second projection lookup.
- **Cache discipline (AGENTS.md §8):** a read projection is cached in Drift;
  a DTO-shape change ships its migration in the same PR.
- **OmniSearch contract:** exactly four chips, active-season scope — both
  frozen by the shipped `flutter-omni-search` spec.

## Goals / Non-Goals

**Goals:**
- A separate, cross-season fundus browsing surface: season chips + name
  prefilter, repertoire-aware rows, deep links into the existing costume
  detail screen.
- Project-scoped client cache slice fed by the existing project-scoped list
  route — fully offline-capable, zero backend work, zero OpenAPI drift.
- Honest cache-staleness treatment reusing the established TTL/stale
  patterns; AI-import and non-repertoire data excluded by construction and
  by regression test.

**Non-Goals:**
- A fifth OmniSearch chip, or any change to OmniSearch's four-chip /
  active-season contract.
- A new backend route or any `backend/openapi.yaml` change.
- Costume write/repertoire-management actions on the fundus surface.
- Full-text / fuzzy / ranking infrastructure.

## Decisions

### D1 — Separate fundus surface, not a fifth OmniSearch chip
**Decision:** the fundus is its own screen, reached from the Cast view's
app bar (beside the category vocabulary action); OmniSearch keeps exactly
four chips and its active-season scope.

**Why:** the two dimensions have **different scope rules** — OmniSearch is
"the active season's cached universe", the fundus is "the active project's
repertoire". Folding a project-scoped facet into an active-season-scoped
surface would either silently widen OmniSearch's scope contract or force a
per-chip scope exception into its spec. A separate surface keeps each
contract single-valued and lets the fundus carry season *chips* (its own
facet model) rather than pretending to be a type chip.

**Alternative rejected — fifth chip:** amends the shipped
`flutter-omni-search` "exactly four" requirement and mixes scope rules in
one surface; the PO decision that pinned the four-chip seam explicitly
warned against scope creep here.

### D2 — Scope = the active project's repertoire costumes (cross-season)
**Decision:** the fundus universe is every costume of the **active
project** whose repertoire (`season_ids`) is non-empty and intersects the
project's seasons. The active season supplies the `project_id`.

**Why:** ADR-035 defines the costume's domain scope as *repertoire seasons
∪ character's season*; the project is the stable container above seasons
(#533/#599 dissolved the season as a permanent navigation gate). Requiring
a non-empty repertoire is exactly the "repertoire data" contract — a
costume bound only to a character (no repertoire row) is **not** fundus
data and is excluded. Foreign-project costumes are excluded by the fetch
scope and by the read filter.

**Alternative rejected — all costumes of the project:** includes
character-only costumes that have never entered the fundus; violates the
issue's "non-repertoire data explicitly excluded" criterion.

### D3 — Project-scoped client cache fed by the existing list route
**Decision:** a dedicated project-scoped Drift slice
(`fundus_costume_cache_rows`, PK `{id}`, fetch-scope `project_id`) is
snapshot-replaced from `GET /v1/costumes?project_id=…` (paginated via the
shared `fetchAllPages`). Search runs client-side over the slice.

**Why:** the route already exists and is generated; the client already
caches read projections in Drift. This keeps v1 fully offline-capable and
adds **no** backend surface, no OpenAPI regeneration, and no drift-check
run — consistent with OmniSearch's D1 ("search what you already hold").

**Alternative rejected — new backend search route:** server truth, but a
new authz-gated route + OpenAPI regen + drift discipline for data the
project-scoped list already returns at cache-fit scale; a clean follow-up
only if the fundus outgrows the cache.

**Alternative rejected — reuse `costume_cache_rows` with a synthetic season
scope key:** abuses a season-typed column as a project key and makes the
season-scoped DAO semantics ambiguous; a dedicated table keeps the fetch
scopes honest.

### D4 — Facet model: season chips + name prefilter
**Decision:** one filter chip per season of the active project (all
deselected = the whole fundus), plus a dictionary-folded, case- and
diacritics-insensitive substring prefilter over the **pinned** costume
fields: notes (description) + category name — the same fields OmniSearch's
costume facet pins.

**Why:** the fundus dimension is *season membership*, so seasons are the
natural chips; the text field stays a name prefilter (no ranking, no fuzzy
matching). Pinning the same fields as OmniSearch keeps one field contract
across both search surfaces and avoids `details`/`photos` creep.

### D5 — Repertoire-aware rows; deep links reuse the costume detail screen
**Decision:** each row shows the costume designation, category, and the
names of its repertoire seasons (resolved from the seasons cache). Tapping
opens the existing `CostumeDetailScreen`, scoped to a **project-resident
repertoire season** — the active season when it is in the repertoire, else
the first repertoire season belonging to the project.

**Why:** the costume detail screen is season-scoped; a fundus costume may
come from any season, but issue #534 guarantees it appears in every season
stream of its repertoire, so any repertoire season is a valid controller
scope. Resolving the scope from the row's own repertoire (not a second
projection lookup) respects the CQRS boundary.

### D6 — No new backend artifact
`backend/openapi.yaml`, problem codes, and OpenAPI drift discipline are
untouched. Backend review is limited to confirming the non-goal carve-outs.

## Risks / Trade-offs

- [Fundus cache is a second copy of costume rows] → the dedicated slice is
  project-scoped and small (the project's costumes); it is read-only and
  snapshot-replaced, so it cannot diverge in kind from the season slice.
- [Stale fundus after repertoire edits elsewhere] → TTL staleness drives the
  established stale banner; pull-to-refresh runs a bounded refetch.
- [Cross-season deep link lands on a season the controller must fetch] →
  the costume is in every repertoire season's stream by construction
  (#534), and the detail screen's `getAndCache` re-fetches on demand.
- [Cache coverage gap for a never-fetched project] → the surface runs a
  bounded prefetch on open (same pattern as OmniSearch); zero-match and
  not-yet-loaded states are distinct.
- [Diacritics folding drift] → the fundus reuses the single
  `foldForSearch` function and its table tests; no second folding table.

## Migration Plan

Client-only; ships with the app. Drift schema **v14** adds
`fundus_costume_cache_rows` via `createTable` (no data migration; the next
snapshot-replace fills it). Rollback = feature removal at the entry point;
the table is inert. `backend/openapi.yaml` and the generated client are
untouched.

## Open Questions

1. Prefetch-on-open vs. pure-cache-first render — the bounded prefetch
   exists either way; settle during implementation measurement. Does not
   change the spec.
2. Season-chip default semantics (all-deselected = whole fundus vs. an
   explicit "Alle" chip) — implementation detail; the spec pins "the whole
   fundus is reachable and season filtering narrows it".
