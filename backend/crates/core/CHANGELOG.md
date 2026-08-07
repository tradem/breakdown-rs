<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4-flash (opencode-go) -->

# Changelog

All notable changes to the `core` crate are documented here. Versioning
follows per-crate Semantic Versioning (ADR-020 D2); this changelog is the
crate-level companion to the release notes generated from conventional
commits (ADR-020 D5).

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
