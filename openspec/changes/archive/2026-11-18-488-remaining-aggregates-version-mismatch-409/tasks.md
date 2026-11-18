<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4-flash (neuralwatt) -->

# Tasks — Sweep remaining aggregates onto 409 `concurrency.version-mismatch` (issue #488)

## Done

- **Error enums** (`crates/core/src/{character,scene,block,episode,season}/error.rs`):
  each gains a typed `VersionMismatch { expected: AggregateVersion, actual:
  AggregateVersion }` variant (mirroring `costume`/#478,
  `costume_category`, `scene_shoot`, `shooting_day`, `photo`).
- **Aggregates** (`crates/core/src/{character,scene,block,episode,season}/aggregate.rs`):
  all 10 `cmd.version != self.version` guards now return
  `VersionMismatch { expected: cmd.version, actual: self.version }` instead of
  `ValidationError("Aggregate version mismatch")` (character ×2, scene ×5,
  block ×1, episode ×1, season ×1).
- **`crates/core/src/error.rs`**: each `From<XError> for DomainError` mapping
  translates `VersionMismatch { expected, actual }` → `DomainError::VersionConflict {
  expected, current: actual }` (existing rendering: 409
  `concurrency.version-mismatch` + typed extensions).
- **Tests** (`crates/core/tests/*_aggregate.rs`): updated
  `*_wrong_version` tests to assert the typed variant (`expected: 99`,
  `actual: INITIAL`) for `character` (×2), `scene`, `block`, `episode`, `season`;
  added `test_all_mutating_commands_reject_stale_version_as_version_mismatch`
  in `scene_aggregate.rs` covering all five scene commands.
- **Wire test** (`crates/api/src/problems/mod.rs`):
  `remaining_aggregate_version_mismatches_render_concurrency_code` asserts all
  five aggregates render 409 `concurrency.version-mismatch` with
  `expected_version` / `current_version` extensions.
- **Attribution**: `// Co-authored-by: deepseek-v4-flash (neuralwatt)` on the new
  OpenSpec artifacts.
- **`crates/core/CHANGELOG.md`**: `### Fixed — remaining aggregates sweep
  stale-version writes onto 409 concurrency.version-mismatch (issue #488)`
  under the open `[0.11.0]` MINOR.

## Verify

- `openapi.yaml` deliberately left untouched: `cargo test -p api --test
  openapi_drift` passes (no utoipa/schema change — pure error-variant change).
- `cargo test -p breakdown_core`: 330 passed; `cargo test -p api --lib`: 52
  passed; `cargo clippy -p breakdown_core -p api --all-targets`: clean.
- No crate version bump; the open `0.11.0` MINOR carries the additive variants.

## Follow-ups

None required. No aggregate still guards optimistic concurrency with the generic
`ValidationError("Aggregate version mismatch")` string.
