<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4-flash (neuralwatt) -->

# Tasks — Costume stale-version writes emit 409 `concurrency.version-mismatch` (issue #478)

## Done

- **`crates/core/src/costume/error.rs`**: added `CostumeError::VersionMismatch {
  expected: AggregateVersion, actual: AggregateVersion }` (typed optimistic-
  concurrency variant mirroring `shooting_day` / `costume_category`).
- **`crates/core/src/costume/aggregate.rs`**: all seven mutating command guards
  (`UpdateCostumeNotes`, `AssignCostumeToCharacter`, `UnassignCostume`,
  `AddDetail`, `RemoveDetail`, `LinkPhoto`, `UnlinkPhoto`) now return
  `VersionMismatch { expected: cmd.version, actual: self.version }` instead of
  `ValidationError("Aggregate version mismatch")`.
- **`crates/core/src/error.rs`**: `From<CostumeError> for DomainError` maps
  `VersionMismatch { expected, actual }` → `DomainError::VersionConflict {
  expected, current: actual }` (existing rendering: 409
  `concurrency.version-mismatch` + typed extensions).
- **Tests** (`crates/core/tests/costume_aggregate.rs`): updated
  `test_update_costume_notes_wrong_version` to assert the typed variant
  (`expected: 99`, `actual: INITIAL`); added
  `test_all_mutating_commands_reject_stale_version_as_version_mismatch`
  covering all seven commands.
- **Wire test** (`crates/api/src/problems/mod.rs`):
  `structured_domain_variants_use_per_context_codes_and_extensions` now asserts
  `CostumeError::VersionMismatch` renders 409 `concurrency.version-mismatch`
  with `expected_version` / `current_version` extensions.
- **Attribution**: `// Co-authored-by: deepseek-v4-flash (neuralwatt)` appended
  to the four hand-authored source/test files.

## Verify

- `openapi.yaml` deliberately left untouched: `cargo test -p api --test
  openapi_drift` passes (no utoipa/schema change — pure error-variant change).
- No crate version bump; `crates/core/CHANGELOG.md` gains a `### Fixed —
  costume stale-version writes surface 409 concurrency.version-mismatch
  (issue #478)` entry under the open `[0.11.0]` MINOR.

## Follow-ups

None required. A same-class sweep of the remaining generic guards
(`character`, `scene`, `block`, `episode`, `season`) was deliberately left out
of scope per the issue (candidate follow-up).
