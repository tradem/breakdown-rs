<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4-flash (neuralwatt) -->

# Proposal: sweep remaining aggregates off generic 422 `Aggregate-version-mismatch` onto 409 `concurrency.version-mismatch` (issue #488)

## Why

Issue #478 (PR #487) fixed the costume aggregate's optimistic-concurrency guard
so a stale version renders 409 `concurrency.version-mismatch` (typed
`VersionMismatch { expected, actual }`) instead of the generic 422
`domain.validation`. The same defect class remains in five other aggregates,
whose `handle` guards still return
`ValidationError("Aggregate version mismatch")`:

- `character` (2 guards: `UpdateMeasurements`, `UpdateContactInfo`)
- `scene` (5 guards: `UpdateSceneDetails`, `AssignCharacter`, `RemoveCharacter`,
  `ScheduleSceneOnShootingDay`, `UnscheduleSceneFromShootingDay`)
- `block` (1 guard: `UpdateBlockTimeSpan`)
- `episode` (1 guard: `RenameEpisode`)
- `season` (1 guard: `RenameSeason`)

The Flutter client branches on the stable problem `code` (RFC 9457, ADR-031).
Stale-version writes to these aggregates still surface the generic 422
`domain.validation` — wire-indistinguishable from genuine validation failures —
so the client cannot render the distinct "changed elsewhere — pull to refresh"
retry narrative (keyed on `concurrency.version-mismatch` since #473).

## Change

Backend only — no spec/main changes, no schema drift:

1. Each error enum (`CharacterError`, `SceneError`, `BlockError`,
   `EpisodeError`, `SeasonError`) gains a `VersionMismatch { expected:
   AggregateVersion, actual: AggregateVersion }` variant, mirroring
   `costume` / `costume_category` / `scene_shoot` / `shooting_day` / `photo`.
2. Every `cmd.version != self.version` guard in those aggregates returns the
   typed variant (10 guards total) instead of
   `ValidationError("Aggregate version mismatch")`.
3. Each `From<XError> for DomainError` mapping translates it to
   `DomainError::VersionConflict`, whose existing rendering already produces
   409 `concurrency.version-mismatch` with the typed extensions.
4. Regression coverage: `crates/core/tests/*_aggregate.rs` stale-version tests
   assert the typed variant; `crates/api/src/problems/mod.rs` gains a wire-level
   test asserting 409 + extensions for all five aggregates.

## Out of scope

No new problem codes (the shared `concurrency.version-mismatch` code already
exists), no command/event shape changes, no openapi.yaml/schema drift.

## Version bumps

None — additive `core` error variants; rides with the open `0.11.0` MINOR
(same no-crate-bump convention as #478/#409/#422/#423). See the version-bump
table in the PR body / implementation report.
