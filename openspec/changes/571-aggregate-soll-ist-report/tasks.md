<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# 571-aggregate-soll-ist-report — Tasks

## 1. Core (domain types + ports)

- [ ] 1.1 Add `AggregateSollIstDiffRow` and `AggregateSollIstReport` to
      `crates/core/src/scene_shoot/views.rs` (utoipa `ToSchema`, serde).
- [ ] 1.2 Add `season_soll_ist_report(SeasonId)` /
      `episode_soll_ist_report(EpisodeId)` to the
      `SceneShootReportRepository` port (Send-future RPIT style, like the
      day-scoped methods).
- [ ] 1.3 Add `ReportKind::SeasonSollIst` / `EpisodeSollIst`
      (`crates/core/src/reporting/mod.rs`) with kebab-case `Display`.

## 2. Infra (read adapter + rendering)

- [ ] 2.1 Implement both port methods in
      `crates/infra/src/queries/reports.rs`: one summary SQL (day counts,
      non-archived, static literal + binds), one row SQL per scope, reshot
      computed from the fetched set, finality in Rust.
- [ ] 2.2 Add `season-soll-ist.typ` / `episode-soll-ist.typ` templates
      (adapted from `planned-vs-actual.typ`: Drehtag column, day-completion
      summary) and register them in `TypstReportRenderer::with_defaults`.
- [ ] 2.3 Handle the new kinds in the archival-facing code paths
      (`SceneShootReportDataLoader` loader match; `jobs.rs` kind-string
      mapping): never archivable, explicit rejection.

## 3. API (handlers, routes, contract)

- [ ] 3.1 Add four handlers (JSON + PDF × season/episode) with
      `// AUTHZ-GATE:` internal gates; 404 via `DomainError::NotFound`
      mapping; no panics.
- [ ] 3.2 Mount the four routes in `handlers::routes`; register the handlers
      in the utoipa `paths(...)` and the new DTOs in `components(schemas(...))`.
- [ ] 3.3 Extend `requirement_for` with the
      `/episodes/{id}/report/soll-ist` → `Authenticated` arm.
- [ ] 3.4 Update the two Fake mock implementors of
      `SceneShootReportRepository` (`test_helpers.rs`,
      `tests/common/mod.rs`) with the new methods.

## 4. Contract + tests

- [ ] 4.1 `UPDATE_OPENAPI=1 cargo test -p api --test openapi_drift` —
      regenerate `openapi.yaml`, review the diff.
- [ ] 4.2 Handler unit tests: 200 empty report (existing scope, no days),
      404 unknown id, 403 non-member, PDF happy path shape, finality flag
      for all-wrapped vs any-unwrapped (where the fake allows).
- [ ] 4.3 `cargo test -p core -p infra -p api -- --test-threads=4` green;
      `cargo clippy -p api -p core -p infra -- -D warnings` clean.
- [ ] 4.4 `cargo test -p architecture_tests` + `cargo deny check bans` green.

## 5. Client + docs

- [ ] 5.1 Regenerate the Dart client via
      `frontend-flutter/scripts/regen-client.sh`; commit the regenerated
      vendor tree.
- [ ] 5.2 Version bumps per dependency lockstep (`core → infra → api`) +
      CHANGELOG `[Unreleased]` entries; record the version-bump table.
- [ ] 5.3 Flutter consumption (aggregate screens, spine entry, tier-3
      Gherkin scenario) — separate commit/PR on this issue if it grows past
      a reviewable diff.
