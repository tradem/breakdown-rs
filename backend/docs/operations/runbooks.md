# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: deepseek-v4-flash (opencode-go)

# Breakdown RS operations runbooks

> **Releasing a crate or the `api` image?** See
> [release-runbook.md](release-runbook.md) — per-crate semver flow, `api-v*`
> image tags, the 8-week API deprecation window, and the read-model
> additivity rule (ADR-020 / ADR-021).

Runtime tiers (ADR-015 / ADR-016 / ADR-025 / ADR-024):

| Tier           | Image                                  | Port      | Role                                            | Volume               |
|----------------|----------------------------------------|-----------|-------------------------------------------------|----------------------|
| Postgres       | `postgres:16-alpine`                   | 5432      | CQRS read-model projections (native TLS)        | `postgres_data`      |
| SierraDB       | `tqwewe/sierradb:0.3.1`                | 9090      | RESP3 event store (write model), internal-only  | `sierradb_data`      |
| stunnel        | `dweomer/stunnel` (digest-pinned)      | 9091      | TLS sidecar fronting SierraDB (ADR-024)         | —                    |
| step-ca        | `smallstep/step-ca:0.28.4` (digest)    | 9000      | Internal CA, short-TTL certs (ADR-024)          | `step_ca_data`       |
| tls-provision  | `smallstep/step-ca:0.28.4` (digest)    | —         | Cert provision loop for the internal mesh       | `tls_data` (shared)  |
| Garage         | `dxflrs/garage:v1.0.1`                 | 3900      | S3 photo storage, internal-only (TLS via Caddy) | `garage_data`        |
| Caddy          | `caddy:2.9.1-alpine` (digest)          | 80 / 443  | HTTPS edge / ACME (ADR-025) + internal :9443    | `caddy_data`         |
| Vault          | `hashicorp/vault:1.20.4` (digest)      | 8200      | Internal Transit + KV-v2 credential vault       | `vault_data`         |
| Vault bootstrap | same Vault image (one-shot)             | —         | Unseal + engines + least-privilege app token    | `vault_unseal`, `vault_app_token` |

Runtime compose files:

- `backend/docker-compose.dev.yml` — minimal dev surface (no `api` service).
- `backend/docker-compose.prod.yml` — production (adds the `api` service, restart
  policies, OTEL env, `depends_on` health gating, the `caddy` HTTPS edge, and
  the internal TLS mesh: `step-ca` + `tls-provision` + `stunnel` sidecar,
  ADR-024).
- `backend/docker-compose.caddy.yml` — dev-only HTTPS edge overlay (ADR-025);
  pairs with `backend/Caddyfile.dev` (prod edge: `backend/Caddyfile`).
- `backend/docker-compose.idp.yml` — dev-only OIDC overlay (ADR-010).

## 0. In-transit TLS (ADR-024 / issue #156)

Every DB / event-store / object-store link is TLS-encrypted and pinned to the
internal `step-ca` root:

| Link                | Mechanism                                                                                 |
|---------------------|-------------------------------------------------------------------------------------------|
| API ↔ Postgres      | native TLS (`ssl=on`), `sslmode=verify-full` + `sslrootcert=/certs/root_ca.crt`           |
| migrator ↔ Postgres | same URL params on `MIGRATOR_DATABASE_URL` (validated at startup)                          |
| API ↔ SierraDB      | `rediss://stunnel:9091` — stunnel sidecar terminates TLS, plaintext RESP3 only to SierraDB |
| API ↔ Garage (S3)   | `https://caddy:9443` — Caddy internal site terminates TLS, OpenDAL pins the root           |

First boot bootstraps the CA automatically from `STEP_CA_PASSWORD` (the one
allowed `.env` bootstrap secret, ADR-027); `tls-provision` then issues 24h
leaf certs (postgres, stunnel, caddy) into the `tls_data` volume and renews
them every 12h. Old certs stay valid until their TTL, so rotating servers
never break clients; Postgres picks up the renewed server cert on
`pg_ctl reload` / restart (a documented ops step — clients keep trusting the
old cert until its TTL either way).

The API refuses plaintext prod URLs when `REQUIRE_IN_TRANSIT_TLS=true` (set by
`docker-compose.prod.yml`): missing `sslmode=verify-full`, a `redis://`
`SIERRADB_URL`, or an `http://` `S3_ENDPOINT` fail startup fast.

## 1. Boot / shutdown

```bash
# Production (DOMAIN + STEP_CA_PASSWORD are required — see §0 and § HTTPS edge below)
POSTGRES_PASSWORD=... STEP_CA_PASSWORD=... DOMAIN=api.breakdown.example \
  docker compose -f docker-compose.prod.yml up -d
docker compose -f docker-compose.prod.yml down       # keep volumes
docker compose -f docker-compose.prod.yml down -v    # DESTROY volumes (incl. CA key!)
```

Boot order: `step-ca` (CA bootstrap) → `tls-provision` (issues certs) →
`postgres`/`sierradb`/`garage` healthy (garage config rendered by the
`garage-config` one-shot) → `stunnel` → `vault` + the independent
`vault-bootstrap` one-shot (unseal, Transit/KV-v2, app policy/token) → `api`
binary starts (migrations via `sqlx::migrate!` at boot over TLS) → `caddy`
starts. The API does not depend on successful Vault bootstrap: it remains
available while credential routes report `503` and the settings projection
reports `unreachable`.

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

### step-ca / tls_data (internal PKI, ADR-024)
`step_ca_data` holds the CA key material — **the** high-blast-radius volume
(compromise = the whole internal PKI). Back it up alongside the databases and
keep the offline copy separated (ADR-023):
```bash
docker compose -f docker-compose.prod.yml stop step-ca
docker run --rm -v step_ca_data:/data -v "$PWD/backups":/backup alpine \
  tar czf /backup/step_ca_data_$(date +%F).tgz -C /data .
docker compose -f docker-compose.prod.yml start step-ca
```
`tls_data` holds only short-TTL leaf certs (re-issuable) — no backup needed.

## 3. Version pinning

All tiers are pinned (ADR-016 / ADR-024):

- `postgres:16-alpine`
- `tqwewe/sierradb:0.3.1`
- `dxflrs/garage:v1.0.1`
- `dweomer/stunnel` — pinned **by digest** in `docker-compose.prod.yml`
  (issue #156); upstream publishes only `latest`, the digest is the pin.
- `smallstep/step-ca:0.28.4` — pinned **by digest** (issue #156).
- `alpine:3.20` — `garage-config` renderer, pinned **by digest** (issue #156).
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
- SierraDB: RESP3 `PING` over raw TCP via a bash script
  (`scripts/sierradb-healthcheck.sh`, 10s interval; the image ships no
  `redis-cli` — the historical `redis-cli -3 PING` check never worked, fixed
  in issue #156). **Must speak RESP3**; SierraDB does not answer RESP2 `PING`.
- stunnel: `nc -z 127.0.0.1 9091` (TLS listener reachable).
- step-ca: `curl -kfsS https://127.0.0.1:9000/health` (the CA cert has DNS
  SANs only — no IP SAN — so `-k` is required).
- tls-provision: certificate files exist in the `tls_data` volume
  (`root_ca.crt`, `postgres.*`, `stunnel.*`, `caddy.*`).
- Garage: `garage -c /etc/garage/config.toml status` in exec form (the image
  is a bare static binary — no shell, so `CMD-SHELL` healthchecks cannot
  work; fixed in issue #156).
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

1. **Vault bootstrap token** — provide `VAULT_BOOTSTRAP_TOKEN` only as the
   Docker secret consumed by the one-shot `vault-bootstrap` service. It is not
   placed in a container environment and is never passed to `api`. The
   generated app token is stored separately in `vault_app_token` with
   restrictive file permissions. The API runtime image uses uid 1000 to read
   only this separate token volume; it never receives `vault_data`.
2. **Domain + DNS** — point the A/AAAA record(s) of `$DOMAIN` at the VPS and
   open `:80`/`:443` in the host firewall (ADR-026). HTTP-01 requires both
   ports reachable from the internet.
3. **Persistent, encrypted volume** — `caddy_data`/`caddy_config`,
   `vault_data`, `vault_unseal`, and `vault_app_token` must live on the
   LUKS-protected volume (ADR-023), like the DB volumes and `step_ca_data`
   (the CA key). `vault_unseal` must be excluded from routine Vault data
   snapshots and handled as separate encrypted/offline key custody; losing it
   intentionally requires an operator recovery/unseal procedure.
4. **`STEP_CA_PASSWORD`** — the internal CA bootstraps on first boot from this
   env var (the one allowed `.env` bootstrap secret, ADR-027). Rotating it
   later requires re-initialising the CA; keep it in the secrets store.
5. **Swagger UI lockdown** — `/swagger-ui` remains reachable via the edge;
   gating it (basic-auth / allowlist) is a separate deployment concern
   (ADR-025) and not part of this transport change.

### Vault internal TLS and credential custody (ADR-027)

Vault listens on `https://vault:8200` with a short-TTL certificate issued by
`step-ca`; the API pins `/certs/root_ca.crt` through `VAULT_TLS_ROOT_CERT`.
The bootstrap container uses the same pinned root via `VAULT_CACERT`. The
bootstrap seed is mounted as a Docker secret, while the generated unseal key
and app token are stored in separate volumes. The unseal volume is not part of
ordinary Vault data backups.

### Garage photo SSE-C key (Issue #159 / ADR-023)

Photo storage uses one stable 256-bit DEK for the `costume-photos` bucket. The
DEK is generated through Vault Transit key `photo-sse-c`; only its wrapped form
is stored at KV-v2 path `kv/data/photo-sse-c`. The API unwraps it at boot and
passes it to OpenDAL in memory. Never put the plaintext key in `.env`, a shell
argument, a log, an event, a projection, or Garage metadata. The API starts
without photo storage when Vault is unavailable and photo operations return
503; it never falls back to plaintext S3.

#### Initial provisioning and verification

1. Start `vault` and `vault-bootstrap` and verify that the bootstrap job
   completed successfully; do not print the app token or any Vault response.
2. Start the API and inspect only redacted startup status/logs. A healthy photo
   adapter reports configuration state, not key material.
3. In staging, upload one test photo through the API and verify the round trip
   through the API. A direct S3 GET/HEAD using a valid Garage access-key and
   secret-key pair, but omitting all SSE-C headers, must fail with
   `InvalidRequest`/`InvalidArgument`; do not dump the object or key.
4. Keep the Garage volume on the LUKS-protected data volume. SSE-C is defense
   in depth, not a replacement for the LUKS control.

#### Two-key bucket rotation

Changing the bucket DEK before rewriting existing objects makes those objects
unreadable. Perform rotation in a maintenance window with all API/photo
workers stopped or quiesced, and explicitly verify operator release before any
key destruction:

1. Generate a candidate datakey through the Vault Transit `photo-sse-c` key
   and store its wrapped ciphertext at
   `kv/data/photo-sse-c-rotation/<rotation-id>/candidate`. Copy the current
   active wrapped DEK and KV version to
   `kv/data/photo-sse-c-rotation/<rotation-id>/rollback`; this is the rollback
   custody record used to recreate the old operator after promotion. The
   least-privilege app policy permits only these rotation paths. Keep the
   current `kv/data/photo-sse-c` record active. Never export or print either
   plaintext DEK.
2. Create a durable rollback copy of every old original/thumb/medium ciphertext
   plus a manifest mapping canonical keys to rollback objects. Then use two S3
   operators to read old objects and write candidate ciphertext under a staging
   prefix. Read each staged object back with the candidate operator and verify
   content length and digest. Do not rely on retaining the old key alone: the
   old ciphertext must remain recoverable if canonical objects are overwritten.
3. Cut over the canonical objects from the verified staging prefix while the
   rollback copy and manifest remain intact. If cutover fails partway, restore
   canonical objects from the rollback copy and keep the old KV record active.
   After every canonical object is verified with the candidate operator, read
   the active KV-v2 version immediately before promotion and write the candidate
   wrapped DEK to `kv/data/photo-sse-c` with
   `options.cas=<expected-active-version>`. A successful CAS write promotes the
   candidate; restart the API workers and confirm new uploads, thumbnail
   generation, downloads, deletion, and GC all succeed.
4. If the CAS write conflicts, do not overwrite the winner: re-read the active
   record, stop the migration, and reconcile against the winner's manifest. If
   the migration is not accepted, load the old wrapped DEK from the rollback
   KV record, ask Transit to unwrap it, restore canonical objects from the
   durable rollback copy, then restore the old wrapped DEK to
   `kv/data/photo-sse-c` with `options.cas=<promoted-candidate-version>`. Verify
   that CAS write; if it conflicts, stop and reconcile before serving photo
   operations. Keep the staging objects, rollback copy, manifest, candidate
   record, and rollback DEK record until the outcome is known. Delete both KV metadata records and object
   artifacts only after the migration outcome and rollback window are complete.
   Before cleanup, a Vault operator creates a short-lived cleanup policy/token
   with `delete` only on
   `kv/metadata/photo-sse-c-rotation/<rotation-id>/candidate` and
   `/rollback` (never a wildcard), uses it for the two metadata deletes, and
   revokes the token and policy immediately afterward. The long-lived
   `breakdown-app` token cannot delete rotation metadata.
5. Before intentional crypto-shredding, stop the API, photo sagas, and GC
   scheduler and explicitly verify that every OpenDAL operator clone has been
   released. Destroy the active `photo-sse-c` Transit key, restart the API, and
   verify that it cannot reload the DEK and photo operations return 503. Never
   destroy the active key for ordinary rotation.

The repository supplies the SSE-C operator and contract tests; the staging
backfill job must be exercised and signed off before production rotation.
Per-photo/per-season key rotation is not supported until OpenDAL provides a
safe per-request SSE-C header seam.

### Internal TLS mesh (ADR-024)

- The `caddy` service also fronts the Garage S3 API on `:9443`
  (`https://caddy:9443` — see `backend/Caddyfile`, internal site); the `api`
  pins the step-ca root via `S3_TLS_ROOT_CERT` and `S3_ENDPOINT` is the Caddy
  TLS URL. Garage's plaintext `:3900` is never published to the host.
- SierraDB is **not published** in the prod compose; the `stunnel` sidecar is
  the only TLS entry point (`rediss://stunnel:9091`). The upstream image has
  **no native TLS listener** (verified against the upstream sources in
  issue #156 — ADR-024's "assume" is resolved).
- Cert rotation is automatic (24h TTL, 12h renewal loop in `tls-provision`);
  clients reconnect transparently. Postgres serves the renewed server cert
  after `docker compose exec postgres pg_ctl reload` (or a restart) — a
  documented ops step, never a breaking one.

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
  (e.g. `rediss://stunnel:9091/?protocol=resp3` in production, ADR-024; dev:
  `redis://127.0.0.1:9090/?protocol=resp3`).
