<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3-flash-flex (neuralwatt) -->
<!-- Co-authored-by: glm-5.3-flash (neuralwatt) -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

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
tag. Never edit a released entry afterwards. The **release body** is a
reviewed prose file at `backend/RELEASE-NOTES/<tag>.md`; the
tag-push workflow attaches it together with the arc42 PDF/HTML artifacts
(`.github/workflows/docs.yml`), and falls back to GitHub's generated notes
when no file exists for the tag.

## [Unreleased]

## [api-v0.71.0] – Released 2026-11-21

- Shipped artifact: `ghcr.io/<owner>/<repo>:api-v0.71.0` (immutable,
  SHA-pinned digest) plus the moving tags `api-v0.71` and `api-v0`.
- Companion crate versions at this release: `core 0.75.0`,
  `infra 0.86.0`, `api 0.71.0`.
- Covers everything since the last tagged image release `api-v0.14.0`;
  28 additive Postgres migrations ship with this image.
- **Client compatibility:** the read model and the wire contract say
  `project_id` (29 OpenAPI properties), the wardrobe is `Piece` +
  `Outfit`, and an AI-import apply is asynchronous (`202` + run). A client
  built against the `api-v0.14.0` read models is not compatible.

### Added

- **AI import is a durable, resumable operation (issues #800, #805, #863,
  #864, #899, #911, #912):** `POST /v1/ai-import/jobs/{id}/apply`
  dispatches (`202`) instead of running the row loop inside the request. A
  run has an identity, a liveness signal and a single-flight gate, renews
  its lease while it executes, and a refused apply names the run that
  blocks it. A run that died before its first progress frame no longer
  blocks the next apply, and a completed apply can no longer lose its
  target-episode summary.
- **AI import — provider breaker, held jobs and an honest retry policy
  (issues #822, #871, #925, #926, #927, #942, #945):** a deployment-wide
  `(provider, model)` circuit breaker with held jobs that persist the
  failure that parked them; one retry core shared by the five
  provider-HTTP call sites; a provider's own `Retry-After` /
  `X-RateLimit-*` is honoured as a **minimum** delay in all four
  schedulers (never while a concurrency permit is held); a quota-exhausted
  `402`/`429` is terminal and carries its own
  `ai-import.provider-quota-exhausted` code instead of the outage code,
  with a provider health/budget read beside it; a failed attempt carries
  the code-keyed failure reason and its next-retry ETA (issue #639);
  chunk-level resume with a derived cursor and a measured ETA; and an
  empty completion is a provider failure, not a validation failure.
- **AI-import cost and telemetry (issues #675, #767, #834, #887, #888,
  #900, #909, #910, #923, #924):** per-import cost transparency;
  Decision-Model token
  and energy usage priced on the Decision Model's own rate card with the
  energy cap applied per provider request; Decision-Model scene scores
  persisted (`projection_scene_scores`) and exposed on the wire; and the
  apply's own numbers — Postgres time attributed (pool wait vs.
  statement), append count and `WRONGVER` conflicts per run, plus a
  dedicated read-model pool so an apply no longer queues behind its own
  projection backlog.
- **Event-store append cost (issue #901):** the append tail is named (the
  `1 + N` fsync path), the SierraDB idle sync interval is pinned to 4 ms in
  both compose runtimes, and an append baseline is committed.
- **Apply throughput (issues #887, #888):** the mapping table is read once
  per apply run instead of per aggregate, and draft rows are applied
  concurrently against a measured bound.
- **Per-config `reasoning_effort` (issues #946, #948, #949):** `AiConfig`
  gains an optional `reasoning_effort` — additive and optional by design,
  `None` sends no field — plus a curated per-`(provider, model)` default,
  the per-config override, and a nightly probe that prices the
  output-token/wall-clock trade.
- **AI-import targets (issues #763, #771, #827, #829):** an upload may
  target a **season** instead of a block, a block-less import receives its
  target block later, the target is frozen once the review commits, a
  contradictory target is refused, and a job identifies itself by uploaded
  file name and imported episode(s). The import also reads and publishes
  the script's own **block** instead of whichever block happens to be
  active.
- **Extraction coverage (issues #581, #677, #695, #706; OpenSpec changes
  `ai-import-outfit-and-pieces`, `ai-import-decision-outfit-continuity`):**
  the script import extracts episodes, shooting days (preview, apply and
  scene→day scheduling), character categories and `DraftOutfit`s with
  derived `DraftPiece`s, plus a second pass that keeps outfits continuous
  across scenes. Cross-row character-category conflicts surface as
  extraction uncertainties instead of a silent merge; scene `(OT)`/`Ep.`
  markers, set-shorthand moods, the Dispo TL;DR and the
  `Episode.Scene` schedule syntax are parsed rather than guessed (issues
  #721, #826), and the extraction schema is hardened for strict Structured
  Outputs (issue #726).
- **ES-native reservation streams (issue #586, ADR-036):** the four
  cross-aggregate uniqueness invariants (episode/season/block numbering per
  `(series_id, number)` and `scene_shoot` pair-uniqueness) claim a synthetic
  `reservation-*` stream (`ExpectedVersion::Empty`) **before** the aggregate
  append, so a racing command answers the invariant's registered `409` with
  no losing aggregate event. Claim → append → compensate: a handle-rejected
  command releases inline, an unknown append state is left to the reaper,
  and the reaper resolves candidates strictly against the event store
  (realized → consumed, crash orphan → released).
- **Project-scoped costume roles** (OpenSpec change
  `project-scoped-membership`): a costume-department role is held
  block-scoped **or** project-scoped (`projection_project_membership`, one
  stream per project, bootstrapped on season creation), and every
  season-scoped check resolves the effective role fail-closed through
  `MembershipRepository::effective_costume_role_in_season` instead of
  re-implementing the precedence.
- **Per-character appearances read model (issue #621):** `GET
  /v1/characters/{id}/appearances` serves every scene the character appears
  in, in script order, with that character's own ordered costume beats
  (backing the Cast view's "Ring binder per role", issue #611).
- **Provider discovery wire (issues #732, #736):** `AiProviderInfo` gains
  an additive decision capability, and a dedicated image-generation model
  catalog is served by
  `GET /v1/ai-import/providers/{provider}/image-models`.
- **Wardrobe split — `Piece` (fundus) and `Outfit` (character look)**
  (OpenSpec change `separate-piece-and-outfit-domain`): one `Costume`
  aggregate becomes a fundus garment with one optional category and a
  character's composed, layered look with `variant_of` forks; scenes cast
  outfits, never bare pieces.
- **`SeriesId` → `ProjectId`, layers 1–3 (issues #591, #599, ADR-035):**
  the tenant container is a `Project`, the projection columns and indexes
  say `project_id` (migration `20261008000001_projection_project_id` with
  an exact inverse), and the 29 OpenAPI `series_id` properties and
  `?series_id=` parameters are `project_id`. Persisted event payloads keep
  `series_id`, deliberately and permanently.
- **Season lifecycle and repertoire (issues #533, #534, #535):**
  `ArchiveSeason` + `SeasonArchived` + `archived` in `projection_season`;
  season repertoire as real aggregate state (`AddCostumeToSeason` /
  `RemoveCostumeFromSeason`); series-level costume-photo authorization.
- **Reports, meta and operations:** season-/episode-scoped aggregated
  Soll-Ist reports (issue #571); `GET /v1/meta/versions` (issue #656) and
  `GET /v1/meta/credits` (issue #655); `GET /v1/me/capabilities` with an
  exact pre-tap credential gate (issue #816); a descriptive, configurable
  `User-Agent` on the provider HTTP clients (issue #521); streamed
  AI-import progress with a cadence-based ETA (issue #762).
- **Episodes, characters and job hygiene:** create-or-assign recovery on
  `episode.number-already-exists` (issue #665); cross-block episode-number
  conflicts that name their location and offer a navigable recovery
  (issue #705); resolvable `field_ambiguity` uncertainties with dedicated
  apply-gate problem codes (issue #663); editable character role type via
  `PATCH /v1/characters/{id}/category` (issue #678); and
  `DELETE /v1/ai-import/jobs/{id}` (issue #671).
- **Dev runtime and build hygiene:** a safe, repeatable dev data reset that
  preserves the configuration (issue #770); `scripts/reclaim-disk.sh`
  (AGENTS.md §8 / issue #631); a repairable lapsed Vault app token; and no
  incremental compilation in the dev/test profiles.

### Fixed

- **AI import:** a script import can no longer lose scenes silently (issue
  #758); Word→PDF export artifacts and the `SCRIPT REPORT` text column no
  longer break scene recognition or the scene numbers; the inline `(OT)`
  marker and the `Ep.`-suffix rules resolve in the prompt (issue #826); the
  deterministic meta-summary guard holds (issue #668) and the outline-block
  summary boilerplate is suppressed at the prompt source (issue #607); one
  acknowledgement per `(scene_index, field)` pair (issue #821); preview
  rows no longer render "?" for a number the document states; and a
  finished import no longer shows "Vorschau wird gespeichert …" forever.
- **Vault and dev tooling:** Vault auth failures are classified, the app
  token is renewed and the retry path is observable (issue #637), and the
  keep-list export refuses an empty export, verifies the replay and
  self-restores (issue #810).
- **Decision Model:** the System One wire contract was wrong in both
  directions, the scoring pass reaches EURouter again, and the round trip
  is verified before success is reported (issues #767, #769).
- **Reconciliation:** the overlay drop is version-fenced for update
  overlays (issue #917), and the projection pass retries when the fetched
  row lags the acked version (issue #916).
- **Authorization:** handler-internal `AUTHZ-GATE` predicate errors surface
  as `500` instead of a swallowed `403` across all 19 membership gates
  (issue #537), and a leftover `DEV_AUTH_SUB` no longer defuses
  `AUTHZ_ENFORCE` (issue #935).
- **Reports:** PDF downloads work again — real font discovery instead of a
  flat `ttf`-only scan with no silent empty-renderer fallback (issue #642),
  no `500` for any non-empty report (issue #764), and Soll-Ist rows render
  values instead of a model dump (issue #766).
- **Dev:** the dev reset no longer dies on a stale dev schema, and a
  `business` reset no longer destroys the preserved configuration.
- **Security:** `rustls 0.23.46` and `hickory-proto 0.26.3` close the
  advisories published since the last cut; `cargo deny check advisories`
  is green without a workspace ignore.

### Changed

- **BREAKING (internal Rust API): `jiff` replaces `chrono` —
  `RUSTSEC-2026-0543` (issue #929, ADR-040).** `chrono` was unmaintained for
  every published version with no safe upgrade, and it serialized every
  persisted aggregate timestamp. The workspace now uses `jiff` 1.x, with
  `jiff-sqlx` as the `timestamptz`/`date` bridge in the new
  `infra::db_time` module and `utoipa`'s `jiff_0_2` feature on the schema
  side. **No wire contract moved:** `jiff`'s serde rendering is
  byte-identical to chrono's, `openapi.yaml` is unchanged, and
  `pre_migration_timestamps_round_trip_byte_identically` +
  `legacy_offset_spellings_still_replay` replay pre-migration spellings
  through JSON **and** CBOR. The `RUSTSEC-2026-0543` ignore is removed.
- **Version bumps (ADR-020 D9, dependency-order lockstep):**
  `core 0.16.1 → 0.75.0`, `infra 0.20.1 → 0.86.0`,
  `api 0.14.1 → 0.71.0` — the accumulated per-PR bumps since
  `api-v0.14.0`; this cut ships whatever the tree carries.
- **Dependencies:** `rustls 0.23.46`, `hickory-proto 0.26.3`,
  `redis 1.8.1`, `utoipa`'s `jiff_0_2` feature, plus the assorted
  Dependabot cargo/actions group bumps; the workspace MSRV was raised
  (issue #605).
- **Docs and tooling:** the arc42 documentation was refreshed and reworded
  per ASD-STE100 (issue #934); SPDX headers are enforced by `--check` in CI
  and the pre-commit hook (issue #814); code-aware discovery (the
  `codebase-memory` graph) is documented as the default path for meaning
  questions.

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
