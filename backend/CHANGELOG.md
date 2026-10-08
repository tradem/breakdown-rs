<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3-flash (neuralwatt) -->

# Changelog

All notable changes to the Breakdown backend will be documented in this
file. The shipped artifact is the `api` Docker image (ADR-020 D6), tagged
by Git tag `api-vX.Y.Z` where `X.Y.Z` is the `api` crate version at the
release commit; the entry version below is therefore the **api image
release**. Companion crates (`core`, `infra`) carry their own independent
versions per ADR-020 D1; the versions at this release are noted in the
entry.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

**Release policy (ADR-020 D9):** development after a cut accumulates under
`## [Unreleased]` — version bumps land on `main` per PR (at least one crate
version per behaviour change, dependency-order lockstep `core → infra → api`)
and are recorded as a `Changed` bullet. A release means: turn `[Unreleased]`
into a dated `## [api-vX.Y.Z] – Released <date>` section and cut the image
tag. Never edit a released entry afterwards.

## [Unreleased]

### Added

- **Series-level costume-photo authorization — `has_active_costume_role_in_series`
  (issue #535, ADR-035 B2/S2).** The costume-photo gate moves off the
  season-typed predicate: the three photo handlers (`upload_costume_photo`,
  `get_costume_photo_bytes`, `delete_costume_photo`) now resolve the costume's
  owning **series** (character season ∪ repertoire → series, strict at the
  API edge — lookup failures answer 500; a costume with neither answers 422
  `costume.container-unresolved`, new registered problem code + Fluent text)
  and require a costume-dept role (`costume_designer`, `wardrobe_supervisor`,
  `costume_assistant`) in any active block of that series. This is a
  **deliberate authorization-boundary widening**: photo access is series-wide,
  a wardrobe team's role carries across seasons of the same production; the
  documented-behavior-change regression test pins it (role only in season B
  → photos of a season-A costume in the same series → 2xx; role in a
  different series → 403). The genuinely season-scoped costume operations
  (detail editing, category season-match, repertoire target season,
  continuity photos, reports) keep the grandfathered
  `has_active_costume_role_in_season`; no new `*_in_season` predicate was
  added (ADR-035 B2). Client gate mirror: the gated photo flows check the
  backend-computed series predicate before any network call (frontend
  AGENTS §5), served by the new `GET /v1/series/{id}/membership`
  (`SeriesMembershipDto`). Crates: `core` 0.21.0 (new port method + registry
  entry), `infra` 0.25.0 (SQL impl), `api` 0.19.0 (route, DTO, gate).
  `docs/security/security-architecture.md` documents the predicate, the
  widening rationale, and the relationship to the role-agnostic
  `has_active_membership_in_series`.

- **Costume season repertoire as real aggregate state — `AddCostumeToSeason`/
  `RemoveCostumeFromSeason` (issue #534).** `CostumeAggregate` carries
  `seasons: Vec<SeasonId>`: the wardrobe lifecycle carries a costume from one
  season into the next, so the repertoire is m:n over the costume's lifetime.
  `CostumeCreated` seeds the list from its `season_id` (legacy pre-#453 events
  replay to an empty list via `serde(default)` — no panic, no repertoire row).
  Both new commands are **state-based idempotent no-ops** (issue #515 lesson):
  re-adding a present season / removing an absent one emits NO event and keeps
  the caller's version fence valid. API: `POST /v1/costumes/{id}/seasons`
  (`AddCostumeToSeasonRequest` body) and
  `DELETE /v1/costumes/{id}/seasons/{season_id}` (`VersionRequest` body), both
  returning the new aggregate version. Handler-internal AUTHZ-GATE on the
  **target** season reusing the existing `has_active_costume_role_in_season`
  predicate (403 `domain.forbidden` — no new `*_in_season` variant, ADR-035
  B2). API-edge pre-checks: the target season must exist (404
  `season.not-found`) and must not be archived (409 `season.archived`, #533
  terminal-state semantics). Projector: `projection_costume_season` becomes
  truly m:n — `CostumeAddedToSeason` INSERTs (PK-guarded),
  `CostumeRemovedFromSeason` DELETEs; `CostumeView.season_ids` (additive,
  allowlisted in the wire fixtures) exposes the repertoire, and the costume's
  authz scopes now include every repertoire season automatically through
  `costume_season_scopes`.

- **Season lifecycle — `ArchiveSeason` command + `SeasonArchived` event +
  `archived` in `projection_season` (issue #533).** `POST
  /v1/seasons/{id}/archive` (VersionRequest body) soft-archives a season:
  terminal state — `RenameSeason` on an archived season is rejected with 409
  `season.archived` (repeat archive is an idempotent-reject, same pattern as
  `costume-category.archived`); the season's number stays reserved
  (uniqueness untouched by decision) and its inventory (blocks/episodes/
  shooting days) stays readable. Handler-internal AUTHZ-GATE reuses the
  existing `has_active_costume_role_in_season` predicate (403
  `domain.forbidden` on deny — no new `*_in_season` variant, ADR-035 B2).
  Read model: migration `20261004000001_projection_season_archived`
  (`archived BOOLEAN NOT NULL DEFAULT false`), projector handler,
  `SeasonView.archived` on the wire, `list_seasons` defaults to excluding
  archived seasons with an explicit `include_archived` opt-in.

- **Season-/episode-scoped aggregated Soll-Ist report (issue #571, aggregation
  half).** Two new read-only routes — `GET /v1/seasons/{id}/report/soll-ist`
  and `GET /v1/episodes/{id}/report/soll-ist` — plus their `.pdf` twins.
  Rows are the union of the day-scoped diff rows across every non-archived
  shooting day of the scope (one row per scene × day, ordered by the day's
  order key, carrying the day's id and label); `reshot_candidate` is scoped
  to the report scope. `is_final` and the day counts (`total_/wrapped_`) are
  **server-derived** (issue-#571 decision: ≥1 non-archived day AND all
  wrapped; never vacuously final) and must never be recomputed client-side.
  A scope with zero shooting days answers `200` with an empty report; an
  unknown season/episode answers the existing `season.not-found` /
  `episode.not-found` 404 codes. Authz reuses the day reports' handler-
  internal season-membership gate verbatim (no new capability). The new
  `ReportKind` variants `season-soll-ist` / `episode-soll-ist` render through
  two new Typst templates and are deliberately **not** archivable. Flutter
  consumption follows in the frontend change (PR #577 shipped the
  reachability half).

- **AI script import extracts EPISODES — apply creates/assigns episodes
  instead of one hard-picked target (issue #581).** A script's episode
  boundaries (`Ep.: 3 (Titel)` markers — first page and repeated page
  headers) become draft metadata on every preview row, so the reviewer
  sees WHICH episode each row (and each to-be-created episode) lands in.
  The apply request carries per-group targets: an existing episode or a
  NEW one created under the job's block with the marker's number and
  title (API-edge 409 pre-check on taken numbers per the #404 doctrine;
  idempotent create via the `episode` mapping row, same reservation
  protocol as scenes). Rows without episode metadata keep the previous
  single-episode flow. Deterministic `Ep.:` scan first, LLM extraction
  (`episode` prompt field) as fallback for foreign notation. Flutter
  grouped apply screen follows in the frontend PR.

### Fixed

- **Membership AUTHZ-GATE predicate errors now surface as 500 instead of a
  swallowed 403 (issue #537).** All 19 handler-internal membership gates in
  `crates/api/src/handlers/mod.rs` previously wrote their predicate as
  `.unwrap_or(false)` — fail-closed (securely correct), but the error reason
  was swallowed: a membership-projection outage reached the client as a 403
  `domain.forbidden` nobody could explain. The predicates now run through
  one shared helper (`membership_gate` for single-scope gates,
  `membership_gate_any` under `authorize_costume_scoped` for multi-scope
  ones). `Ok(false)` stays a genuine 403 deny (policy unchanged). In a
  single-scope gate a predicate `Err(_)` is logged (`tracing::error!`) and
  propagated as 500 `http.internal-error`. In the multi-scope helper a
  failed scope lookup does **not** deny by itself — the remaining scopes may
  still authorize (`Ok(true)` wins, even with another scope erroring); only
  when **no** scope authorizes does the last lookup error surface as 500
  instead of a 403 masquerading the outage. Fail-closed throughout: no error
  grants access by itself. New fail-closed regression
  tests pin the 500 + no-write behavior per predicate family; the ast-grep
  rule `backend/rules/membership-gate.yml` forbids the pattern from
  creeping back in. The AI-import gates were already on an explicit error
  path (issues #481/#532 lineage) and are untouched.

- **Script import: Word→PDF export artifacts no longer kill scene
  recognition (issue #581 user report).** A production script exported
  from Word arrives with non-breaking spaces (U+00A0/U+202F/U+2007), tabs
  and en/em dashes (U+2011/U+2013/U+2014/U+2212) where the heading grammar
  expected plain ASCII — the detector rejected EVERY heading and the import
  died with "script did not contain an INT./EXT. scene heading". Heading
  detection now runs on a normalized copy of each line; the stored heading
  stays the document's verbatim bytes (grounding identity).
- **Preview rows no longer render "?" for a number the document states.**
  When the model omits `scene_number` although the chunk heading carries a
  leading number, the worker backfills the draft row from the chunk —
  server-side truth, the same doctrine as `stable_draft_ref` overwriting
  the model's `draft_ref`. Backfill is limited to the FIRST scene of a
  chunk (the heading is that scene's heading).

### Changed
- **Layer 3 of the `SeriesId` → `ProjectId` rename: the projection columns and
  the wire contract say `project_id` (issue `#599`, ADR-035 D1/S1/B4/B5 —
  completing issue `#591`).** Issue #591 renamed the Rust type and the Rust
  field names but deliberately left every persisted and published spelling on
  `series_id`; this change finishes it. Same UUIDv7 values, same tenant
  boundary (B1), same audit-journal scope (B3) — only the *spelling* moves.
- **Storage (breaking for the read model, migration
  `20261008000001_projection_project_id` with an exact inverse `down`).**
  `projection_season.series_id`, `projection_block.series_id`,
  `projection_episode.series_id` and `projection_audit.series_id` are renamed
  to `project_id`, together with `idx_projection_season_series_number` →
  `idx_projection_season_project_number`, the two sibling `_series_number`
  indexes, the three `idx_projection_*_series_id` indexes and
  `idx_projection_audit_series` → `idx_projection_audit_project`. Every query,
  projector upsert and the `#404` savepoint-skip classification in
  `crates/infra/src/projectors/invariant_skip.rs` (which matches the constraint
  name Postgres reports) follow. Uniqueness is now keyed
  `(project_id, number)` — **B4 satisfied**.
  *ADR-021 D6 deviation, decided deliberately:* D6 forbids renaming a column
  consumed by an open API version during a deprecation window. No window was
  open — nothing had been released against `/v1`, and `/v1`+`/v2` would be
  served by the same binary, so the read model was never a cross-version
  external contract. The queries consuming these columns are updated in the
  same change.
- **ADR-036 reservation-stream keys are unchanged, deliberately.** The four
  synthetic claim keys (`seasnum-`/`blocknum-`/`epnum-`/`sspair-…`) are
  *value-derived* (`{prefix}-{Uuid::simple(project_id)}-{number}`) and carry
  no literal column name, so renaming the column cannot orphan a live claim —
  a key rename would have. ADR-036's original "the rename sweeps the stream
  ids too" is corrected in the ADR itself.
- **Wire (breaking): the 29 OpenAPI `series_id` properties and the
  `?series_id=` query parameters are now `project_id`.** The
  `#[schema(rename = "series_id")]` / `#[param(rename = "series_id")]` pins
  issue #591 had to add are **removed** — `utoipa` derives the property name
  from the Rust field again, which is exactly the leak the pins were guarding
  against. `SeasonView` / `BlockView` / `EpisodeView` / `AuditEntry` and every
  command request body follow.
- **No `/v2` path version was cut — a recorded deviation from the issue's
  acceptance criteria.** ADR-021 D2/D3/D4 would have required a `/v2` plus an
  8-week concurrent `/v1`+`/v2` window, but neither the backend nor the
  Flutter client had ever been released against `/v1`, so there was no consumer
  to keep serving and no client to migrate: the rename landed in place. The
  deprecation lifecycle stays armed for the first breaking change that meets a
  deployed client (`crates/api/src/versioning.rs` `DeprecationRegistry`).
- **Persisted event payloads keep `series_id`, deliberately and permanently.**
  `SeasonCreated` / `BlockCreated` / `EpisodeCreated` and
  `EventMetadata.project_id` stay pinned with `#[serde(rename = "series_id")]`
  (ADR-002 forbids rewriting history, and `projection_audit.event_key` is
  derived from the *re-serialized* payload — renaming the key would silently
  duplicate every pre-rename audit row on replay). This is now the only
  surviving `series_id` spelling in the system, and the ast-grep rule
  `no-stale-series-id.yml` was extended to also ban the lowercase form as a
  Rust **identifier**, so neither spelling can creep back.
- **Version bumps (issue `#599`).** `core 0.22.0 → 0.23.0` (DTO serde
  property renames), `infra 0.27.0 → 0.28.0` (column/index rename; re-pins
  core), `api 0.20.0 → 0.21.0` (wire contract rename; re-pins core/infra);
  `architecture`, `fuzz-targets`, `integration-tests` and `test_support`
  re-pin. MINOR on all three per ADR-020 D2 — the rename is a breaking
  `pub`-API/wire change, and MINOR is this repo's breaking slot (0.x semver);
  the change is invisible outside the monorepo.
- **`SeriesId` → `ProjectId`: the tenant-level container is now a `Project`
  (issue `#591`, ADR-035 D1/S1 — layers 1 and 2 only).** The tenancy seam is
  renamed from the TV-shaped `Series` to the production-neutral `Project`
  (ADR-035 B1): same UUIDv7 values, same tenant boundary, 1:1 rename — not a
  new level above it. `core::shared` exposes `ProjectId`; **no `SeriesId`
  alias was kept** (`core` is an internal workspace crate with no out-of-tree
  consumers, so an alias would protect nobody), and a new ast-grep rule
  (`backend/rules/no-stale-series-id.yml`, wired into the `error-hygiene` CI
  job and the pre-commit hook over *all* Rust files) now fails on any stale
  `SeriesId`. The four `pub` trait methods follow ADR-035 B3/S2's naming
  (`AuditRepository::list_by_series` → `list_by_project`,
  `has_active_membership_in_series`/`has_active_costume_role_in_series` →
  `…_in_project`, `find_by_series_and_number` → `find_by_project_and_number`).

  **The persisted event payloads and the wire contract are unchanged by
  design** — layer 3 is explicitly out of scope and stays open:
  - event fields (`SeasonCreated`, `BlockCreated`, `EpisodeCreated`) and
    `EventMetadata.project_id` carry `#[serde(rename = "series_id")]`;
  - projection columns (`projection_season/_block/_episode.series_id`,
    `projection_audit.series_id`) and the 32 OpenAPI fields, including the
    `?series_id=` query parameters, keep that spelling;
  - the only OpenAPI delta is the **schema name** `SeriesId` → `ProjectId`,
    which is wire-neutral (both render `type: string, format: uuid`) and
    leaves the generated Dart client's `seriesId` accessor untouched. The
    regen diff is doc-comment-only.

  **The non-obvious hazard this change had to route around** (worth recording,
  because the obvious fix is actively harmful): the tempting
  `#[serde(rename = "project_id", alias = "series_id")]` reads old events
  correctly and therefore *looks* safe, but
  `projection_audit.event_key` is derived from the **re-serialized** payload
  (`write_audit_row`), so an alias changes the key and silently **duplicates
  every pre-rename audit row** on any replay — no compile error, no
  dead-letter, no failing test. Pinning the wire key keeps `event_key`
  byte-stable. Pinned by `crates/integration-tests/tests/project_id_rename_replay.rs`
  (tier-4: hand-built pre-rename CBOR `EAPPEND`ed straight into SierraDB,
  replayed through the real season projector and audit projector, asserting
  exactly one audit row on redelivery).
- **Version bumps (issue `#591`).** `core 0.21.0 → 0.22.0` (`SeriesId` removed,
  `ProjectId` added; four `pub` trait methods renamed),
  `infra 0.26.0 → 0.27.0` (repository/port impls renamed; repins core),
  `api 0.19.1 → 0.20.0` (handler helpers + request DTO field renames; repins
  core/infra); `architecture` re-pins `core`/`infra`/`api`. MINOR on all three
  per ADR-020 D2 — the rename is a `pub`-API break, and MINOR is this repo's
  breaking slot (0.x semver); the change is invisible outside the monorepo.
- **ADR-035 amended (issue `#591`).** S1 marked **RESOLVED**; the **B5 outcome
  is recorded**: layer 3 (projection columns + the 32 OpenAPI fields) remains
  deliberately unmoved and is now a named follow-up requiring its own ADR —
  a breaking ADR-021 `/v2` path version with an 8-week dual-serve window, a
  column/index migration and a Dart regen. Two further traps are documented in
  the ADR: `utoipa` derives schema property names from the **Rust field name**
  (so a renamed field silently renames the OpenAPI field — every wire-visible
  struct now carries an explicit `#[schema(rename = "series_id")]` /
  `#[param(rename = "series_id")]`), and the `event_key` hazard above.
- **ADR-037: SceneShoot AI provenance derives via the pair join — no
  first-class field (issue `#539`, follow-up to `#517`).** Decision record
  only, no code change: the provenance of a `SceneShoot` is the provenance of
  its scene (`SceneCreated.source`), derived via the immutable
  `(scene_id, shooting_day_id)` pair. Forensic "who planned this row"
  questions route through the audit layer (`projection_audit` records the
  human reviewer; import batches remain correlated via
  `ai_import.projection_ai_import_mapping`); the app's #517 disclosures and
  badges serve EU AI Act transparency at the application level (Art. 4
  bears on providers and deployers, Art. 50(1)/(2) rest with the model
  provider — no per-row planner attribution required), so no
  projector migration, OpenAPI change, or Dart regen. The additive
  `SceneShootSource` option stays documented in ADR-037 as the
  only-opening case. Index fix: ADR README table now lists ADR-036 too
  (merged without an index row).
- **Version bumps (issue `#534`).** `core 0.19.0 → 0.20.0` (new repertoire
  commands/events, `CostumeCommands` port methods, `CostumeView.season_ids`),
  `infra 0.23.0 → 0.24.0` (command-adapter methods, projector INSERT/DELETE
  handlers, read-model enrich), `api 0.17.0 → 0.18.0` (new repertoire routes;
  repins core/infra); test-support crates re-pinned in lockstep.
- **Version bumps (issue `#537`).** `api 0.16.0 → 0.16.1` — behavior fix on
  the membership-gate predicate-error surface (500 instead of swallowed
  403), no new public API (the gate helpers are crate-private); `core` and
  `infra` untouched, no re-pins needed.
- **Version bumps (issue `#571`).** Season-/episode-scoped aggregated
  Soll-Ist report: `core 0.17.0 → 0.18.0` (new aggregate DTOs, port
  methods, `ReportKind` variants), `infra 0.21.0 → 0.22.0` (read adapter +
  Typst templates), `api 0.15.0 → 0.16.0` (new routes; repins core/infra
  and the test-support crates: `architecture_tests`, `fuzz-targets`,
  `integration-tests`, `test_support`).

- **Version bumps (post-release development, next image cut picks these
  up):** `core 0.16.0 → 0.16.1`, `infra 0.20.0 → 0.20.1`,
  `api 0.14.0 → 0.14.1`; test-support crates `integration-tests`,
  `test_support`, `architecture`, `fuzz-targets` `0.3.0 → 0.3.1` —
  lockstep re-pins per ADR-020 D3.
- **Version bumps (issue #581):** `core 0.16.1 → 0.17.0`,
  `infra 0.20.1 → 0.21.0`, `api 0.14.1 → 0.15.0` — new public API on all
  three (preview payload, worker ports/request, wire request/response);
  test-support crates `integration-tests`, `test_support`,
  `architecture` `0.3.1 → 0.3.2` (lockstep re-pins per ADR-020 D3).

## [api-v0.14.0] – Released 2026-10-04

- Shipped artifact: `ghcr.io/<owner>/<repo>:api-v0.14.0` (immutable,
  SHA-pinned digest) plus the moving tags `api-v0.14` and `api-v0`.
- Companion crate versions at this release: `core 0.16.0`,
  `infra 0.20.0`, `api 0.14.0`.
- Covers everything since the last tagged image release `api-v0.7.1`.

### Added

- **Scene costume casting (issue #546):** ordered costume beats per
  `(scene, character)` pair — scene-side costume casting with sequence
  ordering, plus the AI-import persistence of the extracted scene
  relation via `AssignCharacter` + `AddCostumeBeat` mapping-row phases.
- **Costume details (issues #544, #545):** create, edit, and delete
  costume details.
- **One costume = one category:** `category_id` moves onto the costume,
  replacing the many-to-many association; costume category picker
  support in the API surface.
- **Season repertoire (issue #453):** unassigned costumes become visible
  in their season's costume stream.
- **AI import:** provider replacement (issue #528); combined input and
  config editing improvements; dedicated `ai-import.disabled` problem
  code for the feature flag; scoped forbidden wire codes.
- **EU AI Act compliance:** Art. 50 AI provenance on scenes and Art. 4/50
  transparency surfaces (point-of-interaction disclosure).
- **Reliability / cross-aggregate invariants (issues #404, #37):**
  uniqueness enforced at the API edge with projector savepoint-skip for
  the authoritative constraints; generic projection dead-letter
  (durable `projection_dead_letter` row, checkpoint advance, health
  signal) so a permanent constraint violation never kills the projector;
  authenticated projector-health ops endpoint.
- **Dev runtime:** Vault overlay + credential-role bootstrap; one-liner
  to enable AI import for the host-run dev API; deterministic
  block-conflict fault injection for the wizard Gherkin suites;
  dev-flavor `DEFAULT_SERIES_ID` bootstrap guard + fault injection.
- **ADR-031:** extraction-rejection regression tests + wizard fail-fast.
- **Tier-4:** DB-backed regression test for the #404 numbering-projector
  path; CommandService-driven CreateScene round-trip restored.

### Fixed

- **Photos:** `photo_thumbnail_saga` no longer crash-loops on aggregate
  misses; the upload 201 response is built from command output instead
  of a projection read; photo commands allowed on repertoire-scoped
  costumes; photo commands gated on character assignment.
- **Settings / credentials:** the binding owner is verified on credential
  rotate/revoke; a `vault_key_id` the caller does not own is rejected.
- **Queries:** scene read-model fan-out deduplicated over joined pivots.
- **Concurrency:** stale-version writes emit `409
  concurrency.version-mismatch` instead of a generic 422
  aggregate-version error across remaining aggregates.
- **Error surface:** AI-import and settings-credential errors key on
  scoped wire codes the backend actually emits; OpenAPI `value_type`
  overrides carry `Option` nullability.

### Changed

- **Dependencies:** utoipa 5 → 6 and utoipa-swagger-ui 9 → 10 in
  lockstep; OpenTelemetry crate family 0.33 in lockstep; opendal 0.59;
  redis 1.7; assorted cargo minor/patch bumps via Dependabot groups.

## [api-v0.7.1] – 2026-08-13

Patch image release; see git history for details.

## [api-v0.7.0] – 2026-08-13

Minor image release; see git history for details.
