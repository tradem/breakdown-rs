<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3-flash (opencode-go) -->

# Costume repertoire as real aggregate state (issue #534)

## Why

`projection_costume_season` is modelled m:n but is effectively 1:n: there is no
command/event for a second season, and the aggregate discards
`CostumeCreated.season_id` in `Apply`. The repertoire is not aggregate state —
the aggregate can neither validate a target season nor answer in which seasons
a costume stands. For ES discipline this is a modelling gap: the projector
merely tracks the binding as a by-product. The real costume lifecycle is
cross-season (built for season 1 → season 1 wrapped → carried into season 2 →
possibly season 3); step 1..2 are covered by #533 (`ArchiveSeason`), steps 3+
need the missing write operations.

## Decisions (resolved with the issue author on 2026-10-07)

1. **Idempotency (issue #515 lesson):** both new commands are state-based
   no-ops — re-adding a present season / removing an absent one emits NO event;
   the caller's version fence still matches and the adapter maps the empty
   event list to an unchanged-version success (`set_category` pattern).
2. **Empty repertoire is legitimate:** removing the last season leaves the
   costume with no repertoire row; the authz scope falls back to the
   character's season (`costume_season_scopes`).
3. **Archived seasons are terminal for the repertoire (#533-consistent):**
   add AND remove against an archived target season answer 409
   `season.archived` (API-edge pre-check).
4. **Authorization:** handler-internal AUTHZ-GATE on the **target** season reusing the existing
   `has_active_costume_role_in_season` predicate (ADR-035 B2: no new
   `*_in_season` variant). The client mirror checks only the local
   capability/session seam — the target-season check stays server-owned
   (frontend AGENTS S5: never deny client-side on the season union).
5. **Wire shape (additive, MINOR):** `CostumeView.season_ids` exposes the
   repertoire populated from `projection_costume_season` by the enrich path;
   the wire-contract fixture carries the field via the additive allowlist
   (`costume_view.season_ids`, default-identical `[]` for pre-#534 clients) and
   the frozen fixtures were regenerated (also capturing the pre-existing #533
   `season_view.archived`, #517 `source`, #546 `costume_beats` drift).

## What changes

- **core:** `CostumeAggregate.seasons: Vec<SeasonId>`;
  `CostumeAddedToSeason`/`CostumeRemovedFromSeason` events;
  `AddCostumeToSeason`/`RemoveCostumeFromSeason` commands; `Apply` maintains
  the list, `CostumeCreated` seeds it (`serde(default)` keeps pre-#453 events
  replayable as an empty list); `CostumeCommands::add_to_season`/
  `remove_from_season` ports; `CostumeView.season_ids`.
- **infra:** command adapters (version fence + no-event mapping); projector
  INSERT/DELETE handlers for the new events (`projection_costume_season`
  becomes truly m:n); read-model enrich (`enrich`/`enrich_many`) populates
  `season_ids` batched; audit-projector exhaustiveness arms.
- **api:** `POST /costumes/{id}/seasons` (`AddCostumeToSeasonRequest`) and
  `DELETE /costumes/{id}/seasons/{season_id}` (`VersionRequest`), both
  returning the aggregate version; middleware-classified `BlockMember` +
  handler-internal AUTHZ-GATE on the target season; pre-checks 404
  `season.not-found` / 409 `season.archived` (existing registry codes — no new
  problem codes); `openapi.yaml` regenerated; route-coverage inventory updated
  (88 → 90 patterns).
- **client (frontend-flutter):** vendor client regenerated
  (`addCostumeToSeason`/`removeCostumeFromSeason`/`seasonIds`); repository
  commands + optimistic overlay edits; controller `addToSeason`/
  `removeFromSeason` with client no-op mirror + AUTHZ-GATE; repertoire
  section on the costume detail panel (resolved season names from the seasons
  projection, confirm-first removal, bottom-sheet picker); Drift cache column
  `season_ids_json` (migration v12, nullable, TTL-filled); ARB copy de/en;
  widget tests + regenerated detail golden.
- **docs:** `domain-model.instructions.md` (repertoire paragraph with the new
  routes), `CHANGELOG.md`, version bumps `core 0.20.0`, `infra 0.24.0`,
  `api 0.18.0` (lockstep re-pins for the test-support crates).

## Tests

- Core: command/event round-trips, idempotency (no event on repeat), version
  chain, legacy `CostumeCreated` without `season_id` deserializes + replays to
  an empty repertoire, stale-version guard for both new commands.
- Infra/projector (integration, SierraDB EAPPEND): repertoire spans two
  season streams and removal leaves one; legacy stream + repertoire events
  settle to an empty repertoire at v3.
- API handler wires: 200/403/404/409 semantics for both routes (fake ports).
- Client: widget tests for render/add/remove/denial/no-op + detail golden
  refresh; controller no-op assertions.

## Non-goals

- No cascade of repertoire bindings into characters or reports; the read
  queries (`list_by_season`, `costumes_by_character`) already join the
  repertoire table.
- No bulk repertoire import/migration of historical bindings; the projector
  seed from `CostumeCreated.season_id` and the new commands are the write
  surface.
- #535 (series-level authz) deliberately untouched: the repertoire stays the
  domain scope resolving *which* project, not an authorization check.
