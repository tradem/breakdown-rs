# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors

# Breakdown RS operations runbooks

Two-tier runtime (ADR-015 / ADR-016):

| Tier      | Image                   | Port | Role                                   | Volume              |
|-----------|-------------------------|------|----------------------------------------|---------------------|
| Postgres  | `postgres:16-alpine`    | 5432 | CQRS read-model projections            | `postgres_data`     |
| SierraDB  | `tqwewe/sierradb:0.3.1` | 9090 | RESP3 event store (write model)        | `sierradb_data`     |

Runtime compose files:

- `backend/docker-compose.dev.yml` — minimal dev surface (no `api` service).
- `backend/docker-compose.prod.yml` — production (adds the `api` service, restart
  policies, OTEL env, `depends_on` health gating).

## 1. Boot / shutdown

```bash
# Production
POSTGRES_PASSWORD=... docker compose -f docker-compose.prod.yml up -d
docker compose -f docker-compose.prod.yml down       # keep volumes
docker compose -f docker-compose.prod.yml down -v    # DESTROY volumes
```

The `api` service waits for both tiers to report `service_healthy` before
starting. Migrations (`sqlx::migrate!`) run inside the API binary at boot.

## 2. Backups

### Postgres
Logical backup (recommended for v1):
```bash
docker compose -f docker-compose.prod.yml exec postgres \
  pg_dump -U postgres breakdown > backups/postgres_$(date +%F).sql
```
Restore:
```bash
cat backups/postgres_YYYY-MM-DD.sql | \
  docker compose -f docker-compose.prod.yml exec -T postgres psql -U postgres breakdown
```

### SierraDB
SierraDB stores events under `--dir /app/data` (the `sierradb_data` volume).
Take a filesystem-level snapshot / copy while the service is stopped or quiesced
(event-store appends are immutable; a consistent copy of the dir is a valid
backup):
```bash
docker run --rm -v sierradb_data:/data -v "$PWD/backups":/backup alpine \
  tar czf /backup/sierradb_$(date +%F).tgz -C /data .
```
Restore:
```bash
docker compose -f docker-compose.prod.yml stop sierradb
docker run --rm -v sierradb_data:/data -v "$PWD/backups":/backup alpine \
  tar xzf /backup/sierradb_YYYY-MM-DD.tgz -C /data
docker compose -f docker-compose.prod.yml start sierradb
```
Projector idempotency (ADR-015) makes it safe to replay events into a restored
Postgres projection from a restored/older SierraDB checkpoint.

## 3. Version pinning

Both tiers are pinned (ADR-016):

- `postgres:16-alpine`
- `tqwewe/sierradb:0.3.1`

To upgrade SierraDB:

1. Bump the tag in `docker-compose.dev.yml`, `docker-compose.prod.yml`, and the
   testcontainers helper image in `crates/integration-tests`.
2. Re-pin `kameo_es` / `sierradb-client` in `Cargo.toml` if the SierraDB release
   requires a client revision bump; run `cargo update -p kameo_es`.
3. Run the Tier-4 round-trip suite (`cargo test -p integration-tests`) against the
   new tag before merging.
4. Update ADR-016's pinned-tag line.

## 4. Healthchecks

- Postgres: `pg_isready -U postgres` (10s interval).
- SierraDB: `redis-cli -h 127.0.0.1 -p 9090 -3 PING` (10s interval). **Must use
  RESP3** (`-3`); SierraDB does not answer RESP2 `PING`.
- API: served at `http://<host>:3000/` (extend with a `/health` route in a future
  hardening change).

## 5. OpenTelemetry hooks (ADR-011)

The production compose exports the standard OTEL environment contract into the
`api` service (scope of this change is runtime-compose-level wiring per
ADR-016's design; full in-process exporter integration is a separate ADR-011
change):

| Var                              | Default          | Purpose                              |
|----------------------------------|------------------|--------------------------------------|
| `OTEL_SERVICE_NAME`              | `breakdown-rs`   | Service identity for traces/metrics  |
| `OTEL_EXPORTER_OTLP_ENDPOINT`    | _(empty = off)_  | OTLP collector endpoint              |
| `OTEL_EXPORTER_OTLP_PROTOCOL`    | `http/protobuf`  | OTLP transport                       |
| `OTEL_TRACES_EXPORTER`           | `otlp`           | Traces exporter                      |
| `OTEL_METRICS_EXPORTER`          | `otlp`           | Metrics exporter                     |
| `RUST_LOG`                       | `info`           | `tracing` filter                     |

When `OTEL_EXPORTER_OTLP_ENDPOINT` is empty, the API binary falls back to the
`tracing_subscriber::fmt` stdout subscriber (current v1 behaviour). A future
ADR-011 change will add a `tracing-opentelemetry` layer that consumes these env
vars to export spans/metrics for both tiers' traffic.

## 6. SierraDB RESP3 ≠ Redis caveats (ADR-015 / ADR-016)

- SierraDB speaks **RESP3 only** (`HELLO 3` / `protocol=resp3`). It does **not**
  negotiate down to RESP2.
- It is **not** a Redis Cluster node: do not point Redis-cluster clients or
  `redis-cli --cluster` tooling at it. Use a plain RESP3 `redis::Client`.
- The supported command surface is the event-store subset (`XADD`-style appends,
  `ESCAN`, subscriptions, `PING`, `HELLO`); arbitrary Redis commands (e.g.
  `SET`/`GET`/`EVAL`) are **not** implemented.
- Connection strings MUST include `?protocol=resp3`
  (e.g. `redis://sierradb:9090/?protocol=resp3`).
