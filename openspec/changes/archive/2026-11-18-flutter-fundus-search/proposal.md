<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (neuralwatt) -->

# Fundus search — cross-season repertoire browsing (issue #625)

## Why

The OmniSearch v1 (`add-omni-search`, issue #616) is contractually
**active-season-scoped** and carries **exactly four** facet chips
(Szene · Rolle · Kostüm · Drehtag). The costume **fundus** (repertoire) is
the one dimension that is **cross-season by definition**: a costume built
for season 1 is carried into season 2 and possibly 3 (ADR-035, the
`repertoire seasons ∪ character's season` domain scope). With the
repertoire now real aggregate state (issue #534 — `CostumeView.season_ids`,
`projection_costume_season` truly m:n), the client finally holds a
first-class repertoire surface, so the fundus can be searched as its own
capability without stretching the OmniSearch contract.

## What Changes

- **New separate fundus browsing surface** (not a fifth OmniSearch chip):
  the OmniSearch chip set stays exactly four and its active-season scope
  rule is untouched; the fundus gets its own screen reached from the Cast
  view (where the costume surface lives).
- **Project-scoped, cross-season scope:** the active season supplies the
  `project_id`; the fundus searches every costume of that project whose
  repertoire intersects the project's seasons.
- **Facet/chip model for the fundus dimension:** a season chip per season
  of the active project (default: whole fundus) plus a name prefilter over
  the pinned costume fields (notes/description + category name — same
  fields OmniSearch's costume facet pins, no details/photos creep).
- **Client cache of the project-scoped repertoire read model:** the
  existing `GET /v1/costumes?project_id=…` route feeds a dedicated
  project-scoped Drift slice; the search runs client-side over that slice.
  **No new backend route, no OpenAPI regeneration, no drift-check run.**
- **Explicit exclusions by contract:** AI-import draft/preview data never
  appears; non-costume entities (scenes, characters, shooting days) never
  appear; costumes of a foreign project never appear; costumes without a
  repertoire binding are excluded (they are not fundus data).
- **Repertoire season names** on each row, resolved from the seasons
  projection cache; deep links reuse the existing costume detail screen.

## Capabilities

### New Capabilities

- `flutter-fundus-search`: the cross-season costume-fundus browsing
  surface — Cast-view entry point, project-scoped cache slice, season
  chips + name prefilter, repertoire-aware rows, deep links, cache
  staleness honesty, and the AI-import/non-repertoire exclusions.

### Modified Capabilities

- None — `flutter-omni-search`'s four-chip set and active-season scope are
  explicitly **not** modified (the fundus is a separate surface). The
  `flutter-offline-scope` Drift-cache discipline is consumed (a new
  project-scoped read-projection slice), not changed.

## Impact

- **Code (frontend only):**
  - `frontend-flutter/lib/data/cache/` — new `FundusCostumeCacheRows`
    table + `FundusCostumeCacheDao`, Drift migration v14 (create table).
  - `frontend-flutter/lib/data/fundus_repository.dart` — project-scoped
    fetch (`GET /v1/costumes?project_id=`) + snapshot-replace.
  - `frontend-flutter/lib/features/fundus/` — pure model + matcher,
    controller, screen, entry wiring in `features/shell/`.
  - `frontend-flutter/lib/l10n/app_{de,en}.arb` + generated localizations.
  - `docs/design/screens/fundus.md` + glossary rows (screen-spec workflow).
- **No backend/API changes** (`backend/openapi.yaml` untouched → no Dart
  client regeneration, no drift-check run). The project-scoped list route
  already exists and is generated in `vendor/breakdown_api/`.
- **Testing:** Tier-1 matcher/scope unit tests, Drift DAO scope tests
  (cross-project isolation, repertoire exclusion), widget + golden tests
  on the surface, Err-branch assertions on the repository.

## Non-goals

- **Not** a fifth OmniSearch chip; the four-chip contract stands.
- **Not** a backend fundus search route — the project-scoped list route
  already exists; a route is a clean follow-up only if cohort data grows
  beyond cache-fit.
- **Not** costume write/repertoire management — the fundus surface is
  read-only browsing; repertoire add/remove stays on the costume detail
  panel (issue #534).
- **Not** a full-text/ranking engine — dictionary-folded substring
  prefilter at domain scale, the same contract as OmniSearch.
