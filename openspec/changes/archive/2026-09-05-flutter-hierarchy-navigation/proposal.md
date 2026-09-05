<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# Proposal: Hierarchy Navigation — Phase 1b

## Why
Phase 1 of the roadmap completes the production hierarchy on the client:
series → (seasons — already the reference screen) → blocks → episodes →
scenes, plus season-scoped costume categories. Today the app dead-ends at
the seasons list: the rows are plain `ListTile`s with no navigation, and
no other read projections are cached or rendered. Costume categories —
explicitly Phase 1 — have full backend routes
(`GET/POST /v1/seasons/{season_id}/costume-categories`,
`PATCH /v1/costume-categories/{id}`, `POST /v1/costume-categories/{id}/archive`)
but no client surface at all.

This change lands the navigation spine and the costume-category feature,
reuses and generalizes the seasons reconciliation machinery for the new
create commands, and introduces the season-membership read used by every
later AUTHZ-GATE.

## What changes
- **Navigation (Navigator-based, no new packages):** season rows become
  tappable and push `BlocksScreen` (season context) → `EpisodesScreen`
  (block context) → `ScenesScreen` (episode context) with platform-typical
  Material 3 transitions and a working Up/back affordance. Documented
  deviation: declarative routing is a separate future change; see D1.
- **New screens (per the seasons reference pattern — ConsumerWidget
  containers, pure widgets under `widgets/`, `@riverpod` family
  controllers keyed by the parent id, Result-typed repositories, Drift
  caches per projection with TTL + on-write invalidation):**
  - `features/blocks/` — `GET /v1/blocks?season_id=…`, create via
    `POST /v1/blocks`
  - `features/episodes/` — block-scoped `GET /v1/episodes?block_id=…`
    (backend issue #335 landed), create via
    `POST /v1/episodes`
  - `features/scenes/` — `GET /v1/scenes?episode_id=…`, scene detail data
    (mood, location, summary, script_day, schedule flag, character /
    shooting-day counts) rendered read-only, create via `POST /v1/scenes`
  - `features/costume_categories/` — list ordered by `order_key`,
    create / rename / archive
- **Membership read:** `auth/season_membership_provider.dart` — family
  provider over `GET /v1/seasons/{id}/membership` returning the strict-
  parsed `SeasonMembershipDto`; surfaced as a capabilities chip in season
  context; single source for all later client-side AUTHZ-GATEs.
- **Command pattern:** create block/episode/scene/category follow the
  first-screen decision set (optimistic overlay only after 2xx, controller-
  state overlay never in Drift, bounded-retry reconciliation, stale
  retention on exhaustion, error copy keyed on `code`). The seasons-local
  overlay/backoff machinery is extracted into `lib/domain/reconciliation/`
  and the seasons screen migrates to it with golden parity (no behavior
  change).
- **CQRS boundary:** every navigation context and every command payload is
  populated from the read DTO the user acts on (e.g. `series_id` + `season_id`
  for `CreateBlockRequest` from the `SeasonView`,`series_id` from the
  `BlockView` for `CreateEpisodeRequest`) — never from a second projection
  lookup.
- **Tests:** unit (repos, reconcile, next-order-key; Ok AND Err branches),
  widget + golden (light + dark; Android + macOS tester variants),
  integration smoke over the full spine.

## Capabilities
- `flutter-hierarchy-navigation` (new)
- `flutter-costume-categories-screen` (new)

## Dependencies
- **Depends on:** `first-screen-seasons` (pattern + machinery to extract),
  `flutter-login-and-app-shell` (gate; every new screen is reachable only
  authenticated — D6 there; design tokens for theming).
- Backend routes verified in the checked-in `backend/openapi.yaml`:
  `/v1/blocks`, `/v1/episodes`, `/v1/scenes`,
  `/v1/seasons/{season_id}/costume-categories`,
  `/v1/costume-categories/{id}[…]`, `/v1/seasons/{id}/membership` — all
  present with the DTOs named above. No OpenAPI change is required or
  performed.

## Non-goals
- No scene-shoot / Soll-Ist execution screens (Phase 2/4), no photo or
  costume domain screens (Phase 2), no AI import (Phase 3).
- No character mutation or scene-character assignment
  (`POST /v1/scenes/{id}/characters` is displayed count-only here).
- No block membership management routes (`/v1/blocks/{id}/members*`) —
  seasons membership display only.
- No pagination UI (limit/offset query params exist; lists are season- or
  episode-scoped and small — documented, revisit if projections grow).
- No declarative routing / URL scheme (own future change).

## Design Decisions
- **D1 — Plain `Navigator.push` navigation.** The constraint set forbids
  new routing packages; per the seasons pattern each list screen pushes
  its child with the parent read DTO as argument. The pushed stack IS the
  hierarchy — back returns to the parent list. A later declarative
  routing change can adopt URLs without changing these requirements.
- **D2 — Shared reconciliation machinery.** The seasons overlay/backoff/
  single-flight/generation logic is extracted verbatim-in-behavior to
  `lib/domain/reconciliation/` and parameterized per aggregate. Screens
  keep per-aggregate overlay notifiers (no global overlay store).
- **D3 — Episodes-by-block server-side filtering (landed).** `GET /v1/episodes` supports `season_id` AND `block_id` (backend issue #335, PR #355). `EpisodesScreen` fetches the tapped block's episodes with the server-side `?block_id=` filter; `groupByBlock` remains as a pure mapper for merged/season renders only — read-projection filtering, allowed by the CQRS boundary rules (no aggregate reconstruction, no cross-projection command backfill).
- **D4 — Costume-category order keys are computed from the read model.**
  `CreateCostumeCategoryRequest` requires `order_key`. The client derives
  the next lexicographic key over existing keys from the SAME season
  projection (`order_key` of the read DTOs the user is acting on) and
  never invents a parallel ordering. Renaming uses the `version` echo
  from the read DTO (optimistic locking, 409 surfaced keyed on `code`).
- **D5 — Deleted-parent (404) navigation behavior.** If a pushed screen's
  GET projection returns `season.not-found` etc., the screen shows a 404
  narrative and pops back on user action; local caches drop the orphaned
  subtree rows on the next successful parent snapshot.
- **D6 — Membership gate.** All hierarchy create commands are
  `Authenticated`-gated server-side (like `create_season`); the client
  mirrors this with a session gate before every command. The
  `SeasonMembershipDto` capabilities v1 values are
  `upload_continuity_photos` and `assign_costumes` (both Phase-2 concerns)
  — so Phase 1 uses the membership read for display (honest chip), not
  for gating; Phase 2 changes will gate on it.
