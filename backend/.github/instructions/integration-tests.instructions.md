---
description: Integration tests - tiers, local execution, troubleshooting, gotchas, CI prerequisites.
applyTo:
  - "crates/integration-tests/**"
---

### Integration tests

End-to-end, black-box integration tests live in the dedicated workspace member `crates/integration-tests`. They exercise the full `command → event → event-store → projector → projection` chain against ephemeral containers managed by [`testcontainers`](https://crates.io/crates/testcontainers).

- **Tiers 1–3 (Postgres-only)**: projector and repository tests against an ephemeral PostgreSQL container.
- **Tier 4 (full round-trip, ADR-016)**: `command → SierraDB event persisted → PostgresProcessor catches up → read via *Repository adapter asserts the projection row`, against ephemeral SierraDB (`tqwewe/sierradb:0.3.1`) **and** Postgres containers, with bounded-retry eventual-consistency handling. A second variant verifies projector idempotency under redelivery.
- **How to run locally**: See [Local development](#local-development-integration-tests) below.
- **Boundary**: The crate consumes only the `pub` API of `core` and `infra`. It is excluded from the `cargo-mutants` surface — only whitebox `#[cfg(test)]` modules are mutated.
- **CI trigger**: The integration-test workflow runs on pull requests and pushes to main. The main job runs the Vault fixture, the Postgres-only tests, and the SierraDB round-trip group; a second `ai-import-integration-tests` job runs the heavy Postgres-only AI import/payload suites (issue #226). CI starts the Postgres and SierraDB containers; the photo and AI payload tests additionally start a Garage (S3) container, and the workflow pre-pulls Postgres, SierraDB, Garage and Vault images with retries.
- **Container policy**: Each test gets fresh containers by default. Optional local container reuse is documented in the harness module docs, but CI always uses fresh containers.
- **Flaky-test mitigation**: CI pre-pulls Docker images with retries before running tests to handle transient network failures.

### Local development (integration tests)

#### Prerequisites
- Docker (or a compatible container runtime) must be running
- Network access to Docker Hub (for pulling `tqwewe/sierradb:0.3.1`, `postgres:16-alpine`, `hashicorp/vault:1.17` and `dxflrs/garage:v1.0.1` — Vault for the vault fixture, Garage for the photo and AI payload tests that start an S3 container)
- Rust toolchain installed

#### Running all integration tests
```bash
cargo test -p integration-tests
```

#### Running specific test tiers
```bash
# Tier 1-3: Postgres-only tests (faster, no SierraDB needed)
cargo test -p integration-tests -- projector_tests

# Tier 4: Full round-trip tests (requires SierraDB)
cargo test -p integration-tests -- sierradb_round_trip
```

#### Running with container reuse (faster iteration)
```bash
TESTCONTAINERS_REUSE=1 cargo test -p integration-tests
```
When `TESTCONTAINERS_REUSE=1`, testcontainers will reuse containers across test runs instead of creating new ones. This significantly speeds up iteration but requires manual cleanup:
```bash
# List testcontainers
docker ps --filter "label=org.testcontainers"

# Stop all testcontainers
docker stop $(docker ps -q --filter "label=org.testcontainers")
```

#### Debugging test failures
```bash
# Enable verbose logging
RUST_LOG=debug cargo test -p integration-tests -- --nocapture

# Run a specific failing test
cargo test -p integration-tests -- test_name -- --nocapture
```

### Troubleshooting flaky integration tests

#### Docker image pull failures
**Symptom**: Tests fail with errors like `pull access denied` or `timeout while pulling image`.

**Cause**: Transient network issues or Docker Hub rate limiting.

**Fix**: The fixtures include automatic retry logic (3 attempts). If tests still fail:
1. Pre-pull images manually: `docker pull tqwewe/sierradb:0.3.1 && docker pull postgres:16-alpine`
2. Check Docker Hub status: https://status.docker.com/
3. Verify network connectivity: `curl -I https://registry-1.docker.io/v2/`

#### Container startup timeout
**Symptom**: Tests fail with `SierraDB did not become ready` or similar timeout errors.

**Cause**: Container is slow to start (resource constraints, heavy load).

**Fix**: The startup timeout is 120 seconds. If consistently failing:
1. Check system resources: `docker stats`
2. Close other Docker containers to free resources
3. Increase timeout in `fixtures.rs` (`with_startup_timeout(Duration::from_secs(180))`)

#### Eventual consistency flakes
**Symptom**: Tests fail intermittently with "projection lag" errors.

**Cause**: Projector hasn't caught up within the 15-second deadline.

**Fix**: This is usually a sign of slow CI runners. The polling interval is 150ms with a 15-second deadline. If consistently failing:
1. Check if SierraDB/Postgres are healthy: `docker logs <container_id>`
2. Increase `PROJECTION_DEADLINE` in the test file
3. Check for projector panics in logs

#### FK violation errors
**Symptom**: Tests fail with `foreign key violation` or `violates foreign key constraint`.

**Cause**: Missing parent rows for FK-constrained tables.

**Fix**: See Integration-test Gotcha #1 below. Always seed parent rows before testing child entities.

### Integration-test Gotchas

When writing Tier-4 integration tests that emit events directly via `eappend`
instead of through the command pipeline, keep these pitfalls in mind:

1. **Missing projectors cause FK violations.** The `projection_costume` table
   has `character_id UUID REFERENCES projection_character(id)`. If a test writes
   a `CharacterCreated` event but does not spawn a character projector, the
   costume projector's INSERT fails silently (the transaction rolls back, the
   supervisor restarts, budget is exhausted). Always spawn projectors for every
   entity type referenced by FK constraints.

2. **Events on the same stream are separate transactions.** A `CostumeCreated`
   event (0 details) and a subsequent `DetailAdded` event are processed in
   different worker transactions. A helper like `await_costume_found` that
   returns on the first successful read may see the row before the detail is
   projected. Use `await_costume_with_details` or equivalent polling helpers
   that check the full expected state, not just existence.

3. **`await_costume_detail_category_name` must retry on `NotFound`.** When the
   costume-category projector hasn't caught up yet, `find_by_id` returns
   `NotFound`. Propagating this as an immediate failure causes flaky tests.
   Always retry on `NotFound` within the deadline, matching the pattern used by
   `await_costume_found`.

### CI prerequisites

The integration-test workflow (`.github/workflows/integration-tests.yml`, ADR-014 / ADR-016) runs on `ubuntu-latest` and requires:

- **Docker** (or a compatible container runtime) available on the runner. The workflow verifies `docker info` and fails loudly if it is missing.
- **Network access to Docker Hub** — the workflow pre-pulls `tqwewe/sierradb:0.3.1` and `postgres:16-alpine` with retries before running tests. This prevents flaky failures from transient network issues.
- **Rust caching** — the workflow uses `Swatinem/rust-cache` to speed up builds on repeat runs.
- **Concurrency control** — concurrent runs on the same branch are automatically cancelled to avoid Docker resource contention.
- No service containers are declared in the workflow — `testcontainers` provisions both tiers per test, so the only host prerequisite is Docker + Hub connectivity.

