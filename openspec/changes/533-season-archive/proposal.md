<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# Season lifecycle — ArchiveSeason (issue #533)

## Why

`Season` is the only aggregate in the production hierarchy without a completion
state (`shooting_day` has `wrapped_at`/`archived`, `costume_category` has
`archived`). "This season is finished being produced" is inexpressible, which
blocks the planned costume-repertoire lifecycle (#534: an archived season keeps
its costume bindings historically while active membership ends).

## Decisions (resolved with the issue author on 2026-xx-xx)

1. **Idempotency:** Reject with 409 `season.archived` on repeat — consistent
   with `ArchiveCostumeCategory` and `ArchiveShootingDay` (idempotent-reject:
   an already-archived aggregate emits no further event).
2. **Children:** Inventory stays fully readable; only the season itself is
   locked. No cascade, no schema/event churn for blocks/episodes/shooting days.
   Clients remove the write affordances on the surface of an archived season.
3. **Authorization:** Reuse `has_active_costume_role_in_season` (handler-internal
   AUTHZ-GATE). ADR-035 B2-compliant: no new `*_in_season` predicate.
4. **Number uniqueness stays untouched (recorded in the issue):** an archived
   season still blocks reuse of its number via
   `idx_projection_season_series_number` — the (series_id, number) key is
   historical identity, and re-issuing a number would silently entangle old
   audit/report references.

## What changes

- **core:** `ArchiveSeason` command + `SeasonArchived` event + `archived` state
  on `SeasonAggregate` + `SeasonError::ArchivedCannotBeMutated` +
  `SEASON_ARCHIVED` registry entry in the `From<SeasonError>` mapping; all other
  season commands reject when archived.
- **infra:** migration `projection_season.archived BOOLEAN NOT NULL DEFAULT
  false`; projector handler (version-guarded, idempotent on redelivery);
  read model adds `archived` to `SeasonView`; `list_seasons` filters `WHERE
  archived = false` by default with explicit `include_archived` opt-in.
- **api:** `POST /seasons/{id}/archive` handler (VersionRequest body), classified
  `Requirement::Authenticated` (already covered by the `/seasons` prefix) with a
  handler-internal AUTHZ-GATE reusing `has_active_costume_role_in_season`;
  Fluent texts de/en; `openapi.yaml` regenerated.
- **client (frontend-flutter):** season repo `archiveSeason` call vendor reload,
  archived badge in the season list/detail, write affordances disabled on
  archived seasons, ARB strings (de+en), widget tests + goldens, Err branch.
- **docs:** domain-model.instructions.md (season paragraph),
  frontend-flutter/AGENTS.md §1.

## Non-goals

- No russe-cascade archiving of children.
- No change to `find_by_series_and_number` (uniqueness pre-check unaffected).
- No un-archive (terminal state, like `costume_category`).
