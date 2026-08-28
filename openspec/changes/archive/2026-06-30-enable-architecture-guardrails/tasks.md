## 1. Dependency-level enforcement (cargo-deny)

- [x] 1.1 Create `deny.toml` at workspace root (`backend/deny.toml`) with `[bans.deny]` rules banning `sqlx`, `axum`, `redis`, `sierradb-client`, and `tokio` from `breakdown_core`
- [x] 1.2 Add `[graph]` section with `all-features = true` and `multiple-versions = "deny"`
- [x] 1.3 Run `cargo deny check bans` locally and verify it passes against the current workspace state
- [x] 1.4 Verify test catches forbidden dependency (verified via `core_cargo_toml_must_not_list_forbidden_dependencies` — see task 5.5)

## 2. Source-level enforcement (rust_arkitect)

- [x] 2.1 Update `crates/architecture/Cargo.toml`: replace the commented-out `arch_test` dependency with `rust_arkitect` (dev-dependency), keep path deps on `breakdown_core`, `api`, `infra`
- [x] 2.2 Rename `crates/architecture/tests/architecture_tests.rs.disabled` → `architecture_tests.rs`
- [x] 2.3 Rewrite the test using the `rust_arkitect` API:
  - Use `Project::from_current_workspace()` for workspace discovery
  - Define `ArchitecturalRules::define().rules_for_crate("breakdown_core").it_must_not_depend_on(&["sqlx", "axum", "redis", "sierradb_client", "breakdown_infra", "api"])`
  - Build rules and assert `Arkitect::ensure_that(project).complies_with(rules)` is Ok
  - Add SPDX header and comments referencing ADR-017 and Issue #27
- [x] 2.4 Uncomment `crates/architecture` in the workspace `Cargo.toml` `members` list
- [x] 2.5 Run `cargo test -p architecture_tests` and verify it passes against the current codebase (2 tests pass: Cargo.toml check + rust_arkitect)
- [x] 2.6 Verify the test catches forbidden `use` statements (compiler catches unresolved import; rust_arkitect catches remaining cases when crate is in dependency tree)

## 3. CI integration

- [x] 3.1 Add a `cargo-deny` job to the CI workflow (`.github/workflows/`) that runs `cargo deny check bans`
- [x] 3.2 Add `cargo test -p architecture_tests` to the existing CI test job (or create a dedicated architecture-check job)
- [x] 3.3 Verify the CI workflow file references the correct Rust toolchain and working directory

## 4. Documentation

- [x] 4.1 Create `docs/architecture/adrs/ADR-017-architecture-testing-strategy.md`:
  - Follow the ADR template (Status: Accepted)
  - Document the two-layer strategy (cargo-deny + rust_arkitect)
  - Explain why `rust_arkitect` was chosen over `arch_test_core` / `arch_validation_core`
  - Reference Issue #27
  - List the specific rules enforced
- [x] 4.2 Create `docs/architecture/adrs/ADR-001-hexagonal-architecture.md` (did not exist previously):
  - Contains `crates/architecture → Architecture tests (see ADR-017)`
  - Contains "Architecture tests in `crates/architecture` enforce the rules using `rust_arkitect` and `cargo-deny` (see ADR-017)"
- [x] 4.3 Update `AGENTS.md` §4 (Testing & Guardrails):
  - Replaced "We use `arch_test` to enforce boundary rules" with "We use `rust_arkitect` (source-level) and `cargo-deny` (dependency-level) to enforce boundary rules"
  - Replaced "Run `cargo test -p architecture_tests`" with "Run `cargo test -p architecture_tests` and `cargo deny check bans`"
- [x] 4.4 Create `docs/architecture/arc42-typst/10-quality-requirements.typ` (did not exist previously):
  - Scenario 2 references `cargo deny check bans` in addition to `cargo test -p architecture_tests`
- [x] 4.5 Create `docs/architecture/adrs/README.md` (did not exist previously):
  - Includes ADR-017 in the table

## 5. Validation

- [x] 5.1 Run `cargo test -p architecture_tests` — must pass (2 tests pass)
- [x] 5.2 Run `cargo deny check bans` — must pass (bans ok)
- [x] 5.3 Run `cargo test` (full workspace) — must pass (48 passed, 0 failed)
- [x] 5.4 Run `cargo mutants --in-diff` — no surviving mutants in changed code (0 mutants found; architecture_tests crate has no production code)
- [x] 5.5 Verify violation messages are clear by temporarily introducing a forbidden dependency and confirming the output identifies the file, the dependency, and the rule (verified: `sqlx` added to Cargo.toml → "Forbidden dependencies found in crates/core/Cargo.toml: ["sqlx"]")
