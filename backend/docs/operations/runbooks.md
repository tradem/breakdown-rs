# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors

# Breakdown RS operations runbooks

Runtime tiers (ADR-015 / ADR-016 / ADR-025):

| Tier      | Image                        | Port      | Role                                        | Volume              |
|-----------|------------------------------|-----------|---------------------------------------------|---------------------|
| Postgres  | `postgres:16-alpine`         | 5432      | CQRS read-model projections                 | `postgres_data`     |
| SierraDB  | `tqwewe/sierradb:0.3.1`      | 9090      | RESP3 event store (write model)             | `sierradb_data`     |
| Caddy     | `caddy:2.9.1-alpine`         | 80 / 443  | HTTPS edge / ACME TLS termination (ADR-025) | `caddy_data`        |

Runtime compose files:

- `backend/docker-compose.dev.yml` — minimal dev surface (no `api` service).
- `backend/docker-compose.prod.yml` — production (adds the `api` service, restart
  policies, OTEL env, `depends_on` health gating, the `caddy` HTTPS edge).
- `backend/docker-compose.caddy.yml` — dev-only HTTPS edge overlay (ADR-025);
  pairs with `backend/Caddyfile.dev` (prod edge: `backend/Caddyfile`).
- `backend/docker-compose.idp.yml` — dev-only OIDC overlay (ADR-010).

## 1. Boot / shutdown

```bash
# Production (DOMAIN is required — see § HTTPS edge below)
POSTGRES_PASSWORD=... DOMAIN=api.breakdown.example \
  docker compose -f docker-compose.prod.yml up -d
docker compose -f docker-compose.prod.yml down       # keep volumes
docker compose -f docker-compose.prod.yml down -v    # DESTROY volumes
```

Boot order: `postgres`/`sierradb`/`garage` must be healthy, then the `api`
binary starts (migrations via `sqlx::migrate!` at boot), then `caddy` starts.

The `api` container is **Docker-internal only** — it publishes no host port
(issue #155 / ADR-025). The only host-published ports are Caddy's `:80`
(HTTP→HTTPS redirect + ACME HTTP-01 challenge) and `:443` (TLS). The public
internet cannot reach Postgres, SierraDB, Garage, or the API directly.

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

### Caddy (ACME state)
`caddy_data` holds the ACME account key and issued certificates. Losing it is
not data loss, but re-issuing every cert from scratch risks hitting Let's
Encrypt rate limits, so back it up alongside the databases:
```bash
docker compose -f docker-compose.prod.yml stop caddy
docker run --rm -v caddy_data:/data -v "$PWD/backups":/backup alpine \
  tar czf /backup/caddy_data_$(date +%F).tgz -C /data .
docker compose -f docker-compose.prod.yml start caddy
```

## 3. Version pinning

Both tiers are pinned (ADR-016):

- `postgres:16-alpine`
- `tqwewe/sierradb:0.3.1`
- `caddy:2.9.1-alpine` — pinned **by digest** in `docker-compose.prod.yml`
  (issue #155); the dev overlay may use the plain tag.

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
- Caddy: no healthcheck configured. A malformed Caddyfile makes Caddy exit on
  startup (visible in `docker compose logs caddy`; `restart: unless-stopped`
  keeps retrying), so `docker compose config` + a `caddy validate` pass in CI
  are the primary gates (see `.github/workflows/ci.yml`).
- API: served at `https://<host>/` via the Caddy edge (extend with a `/health`
  route in a future hardening change).

## 5. HTTPS edge & certificates (ADR-025)

Caddy is the sole public entry point:

- **Automatic ACME (HTTP-01 by default):** on first boot Caddy obtains a
  Let's Encrypt/ZeroSSL certificate for `$DOMAIN` and rotates it automatically
  in memory — no cert-touching step, no operator action, no restart.
- **HTTP→HTTPS:** plain HTTP on `:80` is redirected; only the ACME challenge
  is answered on `:80`.
- **HSTS:** `Strict-Transport-Security: max-age=31536000; includeSubDomains` on
  all responses (`backend/Caddyfile`).
- **Request-body limit:** the edge rejects uploads above `PHOTO_MAX_SIZE_MB`
  (same default as the API, 20 MB) before they reach Axum.
- **Default-deny:** Caddy serves no static content; unknown Host/SNI gets 404
  from Caddy, unknown paths get 404 from the API's fallback.

Prerequisites before first prod boot:

1. **Domain + DNS** — point the A/AAAA record(s) of `$DOMAIN` at the VPS and
   open `:80`/`:443` in the host firewall (ADR-026). HTTP-01 requires both
   ports reachable from the internet.
2. **Persistent, encrypted volume** — `caddy_data`/`caddy_config` must live on
   the LUKS-protected volume (ADR-023), like the DB volumes.
3. **Swagger UI lockdown** — `/swagger-ui` remains reachable via the edge;
   gating it (basic-auth / allowlist) is a separate deployment concern
   (ADR-025) and not part of this transport change.

DNS-01 (wildcard certs, or when the hoster firewall blocks HTTP-01) is a
**documented follow-up**, not part of this change: it requires a Caddy DNS
provider plugin image and an API token sourced from the vault per ADR-027
(never from `.env`).

## 6. OpenTelemetry hooks (ADR-011)

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

## 7. SierraDB RESP3 ≠ Redis caveats (ADR-015 / ADR-016)

- SierraDB speaks **RESP3 only** (`HELLO 3` / `protocol=resp3`). It does **not**
  negotiate down to RESP2.
- It is **not** a Redis Cluster node: do not point Redis-cluster clients or
  `redis-cli --cluster` tooling at it. Use a plain RESP3 `redis::Client`.
- The supported command surface is the event-store subset (`XADD`-style appends,
  `ESCAN`, subscriptions, `PING`, `HELLO`); arbitrary Redis commands (e.g.
  `SET`/`GET`/`EVAL`) are **not** implemented.
- Connection strings MUST include `?protocol=resp3`
  (e.g. `redis://sierradb:9090/?protocol=resp3`).
