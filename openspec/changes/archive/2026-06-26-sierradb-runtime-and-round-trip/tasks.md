## 1. SierraDB image investigation (gates the rest)

- [x] 1.1 Investigate whether the `sierradb` project publishes a Docker image compatible with the pinned `kameo_es` revision (Cargo pin); record the answer.
- [x] 1.2 If no upstream image exists, implement a build-from-source `Dockerfile` that produces a SierraDB image at the pinned tag; document the maintenance cost.
- [x] 1.3 Draft **ADR-016** (or an ADR-015 addendum) recording the chosen image path, the pinned tag, and the decision rationale; supersede ADR-015's "image unknown" note. Cross-link from ADR-014, ADR-015, and `persistence-layer-v1`'s design.

## 2. Dev runtime

- [x] 2.1 Extend (or add) `docker-compose.dev.yml` with a SierraDB service on RESP3 port 9090, alongside v1's Postgres service.
- [x] 2.2 Wire `main.rs` to read the SierraDB connection string from environment and boot a real `CommandService` (live write path) when both containers are up.
- [x] 2.3 Document the local boot sequence (start both tiers → migrate Postgres → run app) in `backend/AGENTS.md` and repo `README.md`.

## 3. Production-grade runtime

- [x] 3.1 Produce the production runtime artifact (docker-compose or k8s manifests — record choice in ADR-016) covering Postgres + SierraDB with pinned tags, persistent volumes, and backup/recovery for both tiers.
- [x] 3.2 Add healthchecks for both SierraDB and Postgres.
- [x] 3.3 Wire OpenTelemetry hooks (ADR-011) for both tiers into the runtime.
- [x] 3.4 Document runbooks for operating two tiers (backups, restore, version pinning, SierraDB RESP3≠Redis caveats from ADR-015).

## 4. Tier-4 round-trip integration test

- [x] 4.1 Extend `crates/integration-tests` with a SierraDB testcontainers helper (upstream module or local `Image` impl per ADR-014's one-harness rule).
- [x] 4.2 Add a Tier-4 round-trip test: `command → SierraDB event persisted → PostgresProcessor catches up → read via *Repository adapter asserts the projection row`, with bounded-retry eventual-consistency handling.
- [x] 4.3 Add a second Tier-4 test variant for a mutation command (e.g. assign/remove) verifying projector idempotency under redelivery against the real tiers.
- [x] 4.4 Confirm the Tier-4 tests are excluded from the `cargo-mutants` surface (mutants config / `--exclude`).

## 5. CI

- [x] 5.1 Extend the ADR-014 integration-test CI workflow to start both containers and run the Tier-4 suite on PRs touching `backend/crates/{core,infra,api,integration-tests}/**`.
- [x] 5.2 Document the Docker + SierraDB prerequisites for CI in the workflow file and `backend/AGENTS.md`.
