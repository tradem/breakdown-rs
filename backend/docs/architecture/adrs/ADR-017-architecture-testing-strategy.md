# ADR-017: Architecture Testing Strategy

**Status**: Accepted
**Date**: 2026-06-30
**Author**: Tobias Rademacher (@tradem)
**Supersedes**: the defunct `arch_test`-based guardrail (never functional, Issue #27)
**Related**: ADR-001 (Hexagonal Architecture), Issue #27
**Source change**: `openspec/changes/enable-architecture-guardrails`

---

## Context

The workspace mandates hexagonal architecture (ADR-001): `crates/core` must have
zero dependencies on infrastructure crates (`sqlx`, `axum`, `redis`,
`sierradb-client`) and must not import from `crates/infra` or `crates/api`.
These rules were supposed to be enforced by `crates/architecture` using a crate
called `arch_test`, but:

- `arch_test` does not exist on crates.io
- The test file was renamed to `.disabled`
- The crate was commented out of the workspace `Cargo.toml`

As a result, the boundary was enforced only by convention and code review —
neither of which is reliable in a spec-driven, LLM-assisted development workflow.

## Decision

Replace the dead `arch_test` guardrail with a **two-layer enforcement strategy**:

### Layer 1 — Dependency-level: `cargo-deny`

`cargo-deny` operates at the `Cargo.toml` level using `[[bans.deny]]` rules. It
forbids the following crates from being declared as dependencies of
`breakdown_core`:

- `sqlx`
- `axum`
- `redis`
- `sierradb-client`
- `tokio` (core shall not own an async runtime)

The configuration lives at `backend/deny.toml` with `wrappers = ["breakdown_core"]`
so that only `breakdown_core` is subject to the ban. Other workspace members
(`api`, `infra`) are unaffected.

### Layer 2 — Source-level: `rust_arkitect`

`rust_arkitect` inspects actual `use` statements in source files. A standard
`#[test]` function in `crates/architecture/tests/architecture_tests.rs` verifies
that no `.rs` file under `crates/core/src/` imports from:

- `sqlx`
- `axum`
- `redis`
- `sierradb_client`
- `breakdown_infra` (the infra crate)
- `api` (the api crate)

The test uses `Project::from_current_workspace()` for automatic workspace
discovery and the fluent `ArchitecturalRules` DSL.

### Test locations

- **Dependency checks**: `cargo deny check bans` (runs against `backend/deny.toml`)
- **Source checks**: `cargo test -p architecture_tests` (runs the `rust_arkitect` test)

Both commands are integrated into CI (see `.github/workflows/architecture-checks.yml`).

## Alternatives Considered

- **`arch_test_core` / `arch_validation_core`**: Both depend on
  `ra_ap_syntax` and `rowan v0.13.0-pre.6` — a pre-release dependency
  unacceptable for a CI-critical guardrail. Last updated July 2023.
- **Custom `syn`-based test**: More work to build and maintain than adopting
  `rust_arkitect`. No compelling reason to reinvent.
- **`cargo-modules` + grep**: Not designed for rule enforcement; would require
  fragile output parsing.

## Consequences

**Positive:**

- Two-layer defense in depth: Cargo.toml changes are caught by `cargo-deny`,
  source `use` statements are caught by `rust_arkitect`.
- Both tools use standard Cargo commands and integrate naturally into the
  existing CI pipeline.
- `rust_arkitect` (~600 lines + `syn`) is small enough to vendor if abandoned.
- Developers get clear, actionable violation messages identifying the file,
  the forbidden dependency, and the rule.

**Negative:**

- Two tools instead of one means two CI steps and two local commands to
  remember. This is mitigated by documenting both in `AGENTS.md` and the CI
  workflow.
- `rust_arkitect` is maintained by a single contributor (26 stars as of
  adoption). Vendoring is a viable fallback.
- Intra-core module rules (e.g., "commands may not import from views") are not
  enforced in v1. They can be added incrementally as additional
  `rust_arkitect` rules.
