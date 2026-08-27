## Context

The workspace mandates hexagonal architecture (ADR-001): `crates/core` must have zero dependencies on infrastructure crates (`sqlx`, `axum`, `redis`, `sierradb-client`) and must not import from `crates/infra` or `crates/api`. These rules were supposed to be enforced by `crates/architecture` using a crate called `arch_test`, but:

- `arch_test` does not exist on crates.io
- The test file is renamed to `.disabled`
- The crate is commented out of the workspace `Cargo.toml`

As a result, the boundary is enforced only by convention and code review — neither of which is reliable in a spec-driven, LLM-assisted development workflow. This design replaces the dead guardrail with a two-layer enforcement strategy using actively maintained tools.

### Stakeholders

- Developers contributing to the workspace
- CI pipeline (GitHub Actions)
- LLM coding agents operating under `AGENTS.md`

## Goals / Non-Goals

**Goals:**
- Enforce that `breakdown_core` has no Cargo dependency on `sqlx`, `axum`, `redis`, `sierradb-client`, or `tokio`
- Enforce that `breakdown_core` source files do not `use` items from `sqlx`, `axum`, `redis`, `sierradb_client`, `infra`, or `api`
- Run enforcement in CI and locally via standard `cargo test` / `cargo deny`
- Provide clear, actionable violation messages
- Document the tooling decision as ADR-017

**Non-Goals:**
- Enforce rules within `crates/core` sub-modules (e.g., "scene may only access shared and error") — out of scope for v1; the initial guardrail covers crate-level boundaries only
- Enforce rules for `crates/api` or `crates/infra` (e.g., "api must not directly access the database") — their structure is simpler and less at risk of erosion
- Replace `cargo-mutants` or other existing testing tools

## Decisions

### Decision 1: Use `rust_arkitect` for source-level enforcement

**Choice**: `rust_arkitect` v0.3.7 over `arch_test_core` v0.1.5 / `arch_validation_core` v0.2.3.

**Rationale**:

| Factor | `rust_arkitect` | `arch_test_core` |
|---|---|---|
| Parser | `syn` (de-facto standard, actively maintained) | `ra_ap_syntax` (depends on `rowan v0.13.0-pre.6` — a pre-release) |
| Maintenance | Last commit Jan 2025, crate updated May 2026 | Last commit Jul 2023 |
| Workspace support | `Project::from_current_workspace()` auto-discovers members | Manual `ModuleTree::new("path/to/lib.rs")` per crate |
| DSL | Fluent typestate builder: `.rules_for_crate("x").it_must_not_depend_on(&[...])` | Builder with `MayNotAccess::new(...)` rule objects |
| Custom rules | Trait-based (`Rule` trait) | Not easily extensible |
| License | MIT | AGPL-3.0 |

`rust_arkitect` is a small codebase (~600 lines + `syn`). If abandoned, it can be vendored in an afternoon. The pre-release dependency risk in `arch_test_core` is unacceptable for a CI-critical guardrail.

**Alternatives considered**:
- `arch_validation_core` (fork): Same `ra_ap_syntax` + `rowan` dependency issues; not materially better than the original
- Custom `syn`-based test: More work to build and maintain than adopting `rust_arkitect`; no compelling reason to reinvent
- `cargo-modules` + grep: Not designed for rule enforcement; would require fragile output parsing

### Decision 2: Use `cargo-deny` for dependency-level enforcement

**Choice**: `cargo-deny` with `[bans.deny]` rules banning `sqlx`, `axum`, `redis`, `sierradb-client`, and `tokio` from `breakdown_core`.

**Rationale**: `cargo-deny` is the standard Rust tool for dependency policy enforcement. It operates at the `Cargo.toml` level and catches the most common erosion vector: a developer (or LLM agent) adding a forbidden crate to `core`'s dependencies. It complements `rust_arkitect` which catches `use` statements that might compile through transitive dependencies.

`cargo-deny` runs as a standalone binary in CI, not as a crate dependency — no impact on build times or dependency graph.

### Decision 3: Keep `crates/architecture` as the test location

**Choice**: Repurpose the existing `crates/architecture` crate rather than creating a new location.

**Rationale**:
- Matches ADR-001's documented structure: `crates/architecture → Architecture tests`
- Keep tests separate from production code (standard Rust practice for workspace-level tests)
- The crate was always intended for this purpose; it was just never functional
- The test command `cargo test -p architecture_tests` stays valid, preserving the arc42 quality scenario

**Changes to the crate**:
- Replace `arch_test` (dev-)dependency with `rust_arkitect`
- Remove the `.disabled` suffix from the test file
- Rewrite the test using the `rust_arkitect` API
- Add comments linking to ADR-017

### Decision 4: `deny.toml` location and content

**Choice**: Place `deny.toml` at the workspace root (`backend/deny.toml`), configured with:

```toml
[graph]
all-features = true

[bans]
multiple-versions = "deny"

[[bans.deny]]
name = "sqlx"
wrappers = ["breakdown_core"]

[[bans.deny]]
name = "axum"
wrappers = ["breakdown_core"]

[[bans.deny]]
name = "redis"
wrappers = ["breakdown_core"]

[[bans.deny]]
name = "sierradb-client"
wrappers = ["breakdown_core"]

[[bans.deny]]
name = "tokio"
wrappers = ["breakdown_core"]
```

**Rationale**: Workspace root is the standard location for `cargo-deny` configuration. Using `wrappers` targets only `breakdown_core` — other crates (`api`, `infra`) are free to use these dependencies. `multiple-versions = "deny"` is a general hygiene rule that prevents accidental duplicate crate versions.

### Decision 5: ADR and documentation updates

**Choice**: Create ADR-017 documenting the architecture testing strategy, and update ADR-001, AGENTS.md §4, and arc42 quality requirements.

**Rationale**: The shift from `arch_test` (never-functional) to `rust_arkitect` + `cargo-deny` is an architectural decision with rationale that deserves documentation. ADR-017 captures:
- Why the two-layer strategy
- Why `rust_arkitect` over `arch_test_core`
- What rules are enforced
- How to run tests locally and in CI

## Risks / Trade-offs

- **[Risk] `rust_arkitect` is a small project (26 stars, single maintainer) and could be abandoned.** → Mitigation: The library is ~600 lines of Rust plus the `syn` parser. If abandoned, we vendor the relevant parts into `crates/architecture` directly. The `Rule` trait makes the migration surface small.

- **[Risk] `syn` may not parse bleeding-edge Rust syntax.** → Mitigation: `syn` is maintained by David Tolnay and tracks Rust stable releases closely. We pin a specific `rust_arkitect` version and upgrade deliberately. If a parsing issue occurs, it fails at test time, not in production — the architecture test is a dev-only guardrail.

- **[Risk] `cargo-deny` may produce false positives if a crate is renamed or re-exported.** → Mitigation: We ban by exact crate name as published on crates.io. Crates rarely change their published names. The `wrappers` field ensures only `breakdown_core` is checked.

- **[Trade-off] Two tools instead of one.** → Two tools provide defense in depth: `cargo-deny` catches Cargo.toml changes, `rust_arkitect` catches source-level `use` statements. Each tool is simple to configure and reason about. The operational cost is low (two CI steps, two local commands).

- **[Trade-off] We don't enforce intra-core module rules in v1.** → The initial guardrail focuses on the highest-risk boundary: core ↔ infrastructure. Intra-core rules (e.g., "commands may not import from views") can be added incrementally as `rust_arkitect` rules. This keeps the initial configuration simple and avoids over-engineering.

## Open Questions

- Should we add a pre-commit hook for `cargo deny check bans`? (Convenience vs. friction — defer to post-implementation)
- Should `crates/architecture` remain a standalone crate or be merged into `crates/core` as a `#[cfg(test)]` module? (Standalone is cleaner for workspace-level concerns — decided in Decision 3, but worth revisiting if the crate stays sparse)
