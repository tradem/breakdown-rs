## Why

`persistence-layer-v1` delivered the Postgres projection schema, read adapters, write ports, and API wire-up, but it deliberately did **not** include a runnable SierraDB dev/production runtime or an end-to-end round-trip test that exercises `command → SierraDB → projector → Postgres`. This follow-up owns that gap.

## What Changes

- Investigate the upstream SierraDB container image / build-from-source story.
- Provide a dev `docker-compose.yml` that includes both Postgres and SierraDB.
- Add a production-grade runtime spec (volumes, backups, monitoring, OpenTelemetry hooks per ADR-011) as a separate tracked artifact.
- Implement or wire the live `command → SierraDB → projector → PG` round-trip in `main.rs` and prove it with a Tier-4 integration test.

## Capabilities

- `sierradb-runtime`: runnable SierraDB dev compose and image/build instructions.
- `sierradb-round-trip`: live end-to-end integration test using the existing `kameo_es` `CommandService` + `PostgresProcessor` chain.
- Optional production runtime spec (pinned tags, hardening, volumes, backups).

## Impact

- Replaces the placeholder `SIERRADB_URL` default in `main.rs` with a real, documented connection.
- Unblocks Tier-4 testing in `crates/integration-tests`.
- Keeps v1 unchanged; this is purely additive runtime work.
