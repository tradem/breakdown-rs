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
