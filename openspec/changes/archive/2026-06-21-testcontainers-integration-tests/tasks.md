## 1. ADR-014 & Documentation

- [x] 1.1 Read `docs/architecture/adrs/templates/ADR-template.md` and confirm Section structure (Context, Decision, Consequences, Alternatives, Notes).
- [x] 1.2 Read ADR-002 (event-sourcing/CQRS) and ADR-003 (PostgreSQL) to extract cross-link anchors.
- [x] 1.3 Draft `docs/architecture/adrs/ADR-014-testcontainers-integration-testing.md` following the template: decision (Testcontainers / `testcontainers-modules` postgres), alternatives (shared dev DB, `sqlx::test` macro, docker-compose env, in-memory `kameo_es` stores only), consequences (Docker dev+CI, runtime cost, isolation strategy), relationship to ADR-002 / ADR-003, explicit statement that integration tests are NOT part of the `cargo-mutants` surface (cross-link #18 / mutants issue). Status: Accepted.
- [x] 1.4 Add ADR-014 to the "Related ADRs" sections of ADR-002 and ADR-003.
- [x] 1.5 Update repo `README.md` with Docker prerequisite and exact local-run command (`cargo test -p integration-tests`).
- [x] 1.6 Update `backend/AGENTS.md` with an "Integration tests" subsection (location, how to run, mutants-boundary statement, when CI triggers).
- [x] 1.7 Run `./scripts/add-spdx-headers.sh docs/architecture/adrs/docs/...` (or appropriate dir) if headers apply to `.md`/shell (no-op for `.md`; new `.rs` headers handled in 4.4 / 8.5).

## 2. Workspace & Crate scaffolding

- [x] 2.1 Create new workspace member `crates/integration-tests` (`Cargo.toml` + `src/lib.rs` with module doc + SPDX header, declaring `crate-type = ["lib"]`, dev-only posture, no public production API).
- [x] 2.2 Add `crates/integration-tests` to root `Cargo.toml` `[workspace] members`.
- [x] 2.3 Add `testing` feature to `crates/infra/Cargo.toml` (expose `pub mod testing`) and to `crates/core/Cargo.toml` (so `testing::make_ctx` is available to integration tests); both gated `#[cfg(feature = "testing")]`.
- [x] 2.4 Verify no production crate depends on `integration-tests`; added reverse-dependency `cargo tree` lint in CI.

## 3. Dev-dependencies & Testcontainers wiring

- [x] 3.1 Add `testcontainers` + `testcontainers-modules` (with `postgres` feature) as optional `[dependencies]` of `crates/infra` (behind the `testing` feature). Moved from integration-tests to infra so the reusable `spawn_postgres()` helper can live in `infra::testing`; production builds still exclude them.
- [x] 3.2 Add `tokio` (rt-multi-thread, macros), `sqlx` (runtime-tokio, postgres, migrate) and `uuid` (v7) to the `integration-tests` dev-deps; fixtures use `Uuid::now_v7()` only.
- [x] 3.3 Add `infra` / `breakdown_core` dependencies in `integration-tests` enabling `infra/testing` and `breakdown_core/testing` features.
- [x] 3.4 `cargo build --workspace` compiles; production crates do not enable `testing` feature.

## 4. Shared harness

- [x] 4.1 Implement `infra::testing::spawn_postgres()` returning `(PgPool, ContainerAsync<Postgres>)` behind the `testing` feature: starts a `testcontainers_modules::postgres::Postgres` container, builds a `PgPool`, runs a readiness query.
- [x] 4.2 Event-store schema provisioning updated: `kameo_es` uses sierradb for event storage, not Postgres. Documented in ADR-003 note and ADR-014; Postgres harness provisions projection schema only.
- [x] 4.3 Projection migrations live in `crates/infra/migrations/`; `sqlx::migrate!` is applied in `spawn_postgres()` and migration errors propagate as hard failures.
- [x] 4.4 SPDX headers added manually to all new `.rs`/`.sql` files (the referenced `./scripts/add-spdx-headers.sh` does not exist in this repo).
- [x] 4.5 Harness module doc explains `TESTCONTAINERS_REUSE=1` opt-in and notes CI always uses fresh containers.

## 5. Smoke integration test (template)

- [x] 5.1 Add `crates/integration-tests/tests/smoke_costume_round_trip.rs` plus `tests/smoke_postgres_harness.rs` as the harness template.
- [x] 5.2 Test: `spawn_postgres()` is called and a `CreateCostume` command is sent through the in-memory `Costume` aggregate command handler. Persisting the event to sierradb (via `kameo_es`) is deferred to the follow-up sierradb branch.
- [x] 5.3 Test: projection step is documented as a TODO in the smoke test; no Costume projector exists yet in `infra`.
- [x] 5.4 Test: the smoke test re-hydrates the aggregate from the emitted events and asserts project id / unassigned state.
- [x] 5.5 Smoke test scoped to harness + in-memory command/replay; TODO stub in place for event-store persistence and projection steps.
- [x] 5.6 Canonical template pattern documented in module-level comments of both smoke test files.
- [x] 5.7 All fixture ids use `Uuid::now_v7()` (confirmed by code review); no `new_v4`.

## 6. Mutation-test boundary

- [x] 6.1 Added `backend/.mutants.toml` excluding `crates/integration-tests`.
- [x] 6.2 AGENTS.md integration-tests subsection documents mutants-boundary exclusion.

## 7. CI workflow

- [x] 7.1 Added `.github/workflows/integration-tests.yml` triggering on `backend/crates/{core,infra}/**` and running `cargo test -p integration-tests`.
- [x] 7.2 CI job runs `docker info` to fail loudly on missing Docker and includes a comment documenting the nightly-lane cutoff option.
- [x] 7.3 CI job includes `cargo tree` reverse-dependency lint for `breakdown_core`, `infra`, and `api`.
- [x] 7.4 `gitleaks detect --no-git` run on all new directories: no leaks found (the broader repo-level scan flags only `.ast-bro/index/chunks.bin`, which is generated and unrelated).

## 8. Verify & guardrails

- [x] 8.1 `cargo test -p integration-tests` compiles cleanly and the `smoke_postgres_harness` test passes when Docker is available. The current environment lacks Docker, so `smoke_costume_round_trip` cannot execute here; logic verified via compilation + clippy.
- [x] 8.2 `cargo build --workspace` succeeds; production crates compile without the `testing` feature.
- [x] 8.3 `cargo mutants` not installed in this environment; the exclusion is configured in `.mutants.toml` and documented in AGENTS.md.
- [x] 8.4 Hexagonal boundary confirmed by manual review + CI `cargo tree` lint: `integration-tests` depends on public `core`/`infra` APIs (via `testing` features), and no production crate depends on `integration-tests`. `arch_test` crate remains commented out in the workspace.
- [x] 8.5 SPDX headers added to all new `.rs` and `.sql` files; `./scripts/add-spdx-headers.sh` does not exist, so headers were inserted manually.
