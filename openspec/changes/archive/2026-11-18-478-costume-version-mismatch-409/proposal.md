<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4-flash (neuralwatt) -->

# Proposal: costume stale-version writes emit 409 `concurrency.version-mismatch` (issue #478)

## Why

The costume aggregate's optimistic-concurrency guard rejects a stale version with
a generic `ValidationError("Aggregate version mismatch")`
(`crates/core/src/costume/error.rs` + `CostumeAggregate::handle`), which renders
as 422 `domain.validation`. Every other aggregate with a version guard
(`costume_category`, `photo`, `scene_shoot`, `shooting_day`, `settings`) uses a
typed `VersionMismatch { expected, actual }` variant that renders as 409
`concurrency.version-mismatch` with the `expected_version` / `current_version`
extensions.

The Flutter client branches on the stable problem `code` (RFC 9457, ADR-031).
A costume version-mismatch surfaces the generic 422 — wire-indistinguishable
from genuine validation failures — so the client cannot render the distinct
"Changed elsewhere — pull to refresh" narrative (issue #473, already keyed on
`concurrency.version-mismatch` since #473 landed) for costume writes.

## Change

Backend only — no spec/main changes, no schema drift:

1. `crates/core/src/costume/error.rs`: add `CostumeError::VersionMismatch {
   expected: AggregateVersion, actual: AggregateVersion }` (mirrors
   `shooting_day` / `costume_category`).
2. `crates/core/src/costume/aggregate.rs`: all seven mutating command guards
   (`UpdateCostumeNotes`, `AssignCostumeToCharacter`, `UnassignCostume`,
   `AddDetail`, `RemoveDetail`, `LinkPhoto`, `UnlinkPhoto`) return
   `CostumeError::VersionMismatch { expected: cmd.version, actual: self.version }`
   instead of `ValidationError("Aggregate version mismatch")`.
3. `crates/core/src/error.rs`: `From<CostumeError> for DomainError` maps the new
   variant to `DomainError::VersionConflict`, whose existing rendering already
   produces 409 `concurrency.version-mismatch` with the typed extensions.

## Out of scope

`character`, `scene`, `block`, `episode`, `season` still use the generic
`ValidationError("Aggregate version mismatch")` guard — the issue names only the
costume aggregate, so a sweep of the remaining aggregates is deliberately NOT
part of this change (candidate follow-up).

## Version bumps

None — additive `core` error variant; rides with the open `0.11.0` MINOR
(no-crate-bump convention #409/#422/#423/#470/#453). See the version-bump table
in the PR body / implementation report.
