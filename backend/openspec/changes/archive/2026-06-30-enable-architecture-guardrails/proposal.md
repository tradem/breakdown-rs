## Why

The hexagonal architecture boundary enforced by `crates/architecture` has been dead since inception — the test crate is commented out of the workspace, the test file is renamed to `.disabled`, and the assumed dependency `arch_test` does not exist on crates.io (Issue [#27](https://github.com/tradem/breakdown-rs/issues/27)). CI cannot detect a violation like `use sqlx` or a forbidden Cargo dependency slipping into `crates/core`. With LLM-assisted and spec-driven development, automated enforcement of architectural invariants becomes critical to prevent silent erosion of the core boundary.

## What Changes

- **Replace** the defunct `arch_test`-based guardrail with a two-layer enforcement strategy:
  - Layer 1: `cargo-deny` — bans forbidden crates (`sqlx`, `axum`, `redis`, `sierradb-client`, etc.) from `breakdown_core` at the `Cargo.toml` level
  - Layer 2: `rust_arkitect` — inspects actual `use` statements in source files for module-level boundary violations ("A may not depend on B")
- **Create ADR-017** documenting the tooling decision and the two-layer strategy
- **Update ADR-001** to reference ADR-017 instead of the dead `crates/architecture`
- **Update AGENTS.md §4** to reflect the new tooling (`rust_arkitect` + `cargo-deny` instead of `arch_test`)
- **Update arc42 quality requirements** to match the new test invocation
- **Remove or repurpose** the dead `crates/architecture` crate (was never functional)

## Capabilities

### New Capabilities
- `architecture-testing`: Automated enforcement of hexagonal architecture boundaries via `rust_arkitect` (source-level `use` rules) and `cargo-deny` (dependency-level bans). Runs in CI and locally via `cargo test`.

### Modified Capabilities
<!-- None — this is purely additive infrastructure. No existing spec-level requirements change. -->

## Impact

- **Affected code**: `crates/architecture/` (removed/repurposed), new `deny.toml` at workspace root, new `crates/architecture/` or inline architecture tests
- **Affected specs**: New capability `architecture-testing`
- **Affected documentation**: ADR-001 (update references), new ADR-017, AGENTS.md §4, arc42 `10-quality-requirements.typ`
- **New dependencies**: `rust_arkitect` (MIT, dev-only), `cargo-deny` (CI tool, not a crate dependency)
- **Breaking changes**: None. Pure additive improvement.
