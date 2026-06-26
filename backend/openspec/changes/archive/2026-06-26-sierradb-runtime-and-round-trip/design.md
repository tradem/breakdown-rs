# Design: SierraDB Runtime & Round-Trip

## Context

`persistence-layer-v1` left the following runtime questions open:

- Does SierraDB publish an official container image? If not, how do we build it from source?
- What is the recommended RESP3/Redis-compatible client connection string for dev and production?
- How do we verify the full `command → SierraDB event store → PostgresProcessor → Postgres projection` chain?

## Goals

1. Provide a runnable dev compose that adds SierraDB alongside the existing Postgres-only dev compose.
2. Document production-grade runtime concerns (tag pinning, persistence, backups, monitoring) as a follow-up spec, not necessarily code in v1.
3. Add a Tier-4 integration test that issues a command through `SceneCommandsImpl` (or similar) against a live SierraDB container and asserts the resulting projection row.

## Non-Goals

- Rewriting v1 projections, ports, or adapters.
- Implementing authentication/authorization (ADR-010) or observability wiring (ADR-011) beyond runtime-compose references.

## Decisions

- **Container image source:** First task is to verify whether `sierradb/sierradb` (or similar) exists on Docker Hub / GHCR. If not, build from the upstream source and publish build instructions.
- **Dev compose:** Extend v1's `docker-compose.dev.yml` with a second `sierradb` service, reachable at `redis://sierradb:6379`, and update `main.rs` defaults to point both services at the compose network.
- **Round-trip test:** Add `crates/integration-tests/tests/sierradb_round_trip.rs` that:
  1. starts a Postgres testcontainer (existing `infra::testing::spawn_postgres`),
  2. starts a SierraDB testcontainer (new harness helper),
  3. builds a `CommandService` connected to SierraDB,
  4. spawns the four projectors,
  5. issues a `CreateScene` command,
  6. polls `projection_scene` until the row appears,
  7. asserts `version` and `updated_at`.

## Risks / Trade-offs

- SierraDB container availability is unknown; this may require building from source.
- Eventual consistency means the test must poll, not assume synchronous projection.
