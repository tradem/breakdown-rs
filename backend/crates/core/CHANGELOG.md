<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4-flash (opencode-go) -->

# Changelog

All notable changes to the `core` crate are documented here. Versioning
follows per-crate Semantic Versioning (ADR-020 D2); this changelog is the
crate-level companion to the release notes generated from conventional
commits (ADR-020 D5).

## [0.6.0] - Unreleased

### Added — fallible authorization policy checks (issue #175)

- New defaulted `AuthorizationPolicy` methods `authorize_season_result` and
  `authorize_credential_role` in `membership::policy`: both are *fallible*
  (`Result<PolicyDecision, DomainError>`) so API handlers on
  `Authenticated`-only privileged routes can route their authorization gates
  through the policy while keeping read-model failures visible as mapped
  server errors instead of silently becoming a `403`. Defaults return
  `Ok(PolicyDecision::Deny)`, so existing policy implementations are
  unaffected.

## [0.5.0] - Unreleased

### Added — CQRS-safe merge input type (issue #172)

- New `MergeInput` struct in `ai::preview`: an immutable blob carrying the
  `ShootingSchedule` and pre-loaded `SceneView` slices, prepared at the
  authorized API/query boundary and stored before the merge job is claimed.
  The write-side merge worker reads only this blob — never a read-model
  projection (CQRS boundary, AGENTS.md §1).
- New `merge_from_input(input: &MergeInput) -> Result<MergedPreview, DomainError>`
  pure function: CQRS-safe entry point that performs the deterministic
  schedule-to-scene join against the pre-loaded scenes.

## [0.4.0] - 2026-08-07

### Changed — AI import telemetry apply-state contract (issue #171)

- `Telemetry` no longer carries `accept_as_is: Option<bool>` and
  `edit_distance: u32` as independent fields. They are replaced by a single
  `apply_state: TelemetryApplyState` discriminator:
  - `TelemetryApplyState::NotApplied` — the job never reached apply; its
    `edit_distance` is explicitly NULL, not a misleading `0`.
  - `TelemetryApplyState::Applied { accept_as_is: bool, edit_distance: u32 }`
    — an applied outcome; zero user edits stays `edit_distance = 0` and is
    distinguishable from a never-applied job.
- New public enum `TelemetryApplyState` (serde `snake_case`, `ToSchema`,
  `Default` = `NotApplied`) with accessor helpers `accept_as_is()` and
  `edit_distance()` returning `Option<T>` for persistence.
- **Breaking change under major-zero semver** (released as MINOR, ADR-020 D2):
  `Telemetry`'s removed pub fields change any construction site; acceptance
  and edit-rate calculations SHALL exclude `NotApplied` jobs. This is the
  first `core` release (per-crate tag `core-v0.4.0`).
