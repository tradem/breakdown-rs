// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (opencode-go)

# Issue #156 — step-ca internal CA + TLS for DB links (ADR-024)

> Systematic implementation plan + implementation record for issue #156:
> database (and object-store) encryption in transit for Postgres (API,
> migrator, projectors), SierraDB (RESP3) and Garage (S3 photo storage),
> with certificates issued by a self-hosted internal CA (`step-ca`).

## 1. Problem statement

"Docker network = trusted" is not an acceptable baseline (ADR-024): a single
compromised container or a mispublished port turns an unencrypted DB link into
a credential-exfiltration path. Today `DATABASE_URL` carries no `sslmode`,
`SIERRADB_URL` is plaintext `redis://sierradb:9090`, and `S3_ENDPOINT` is
plaintext `http://garage:3900`. This change makes every DB / event-store /
object-store link TLS-encrypted and **pinned to the internal step-ca root**.

## 2. Current-state audit (branch cut from `main`)

| Concern | State on `main` |
|---|---|
| Postgres TLS | none (`ssl` off; connection strings carry no `sslmode`) |
| SierraDB TLS | none (plaintext `redis://`; upstream TLS support **assumed**) |
| Garage S3 TLS | none (plaintext `http://garage:3900`; `:3900` not published) |
| Internal CA / cert rotation | none |
| Startup prod-URL gate | none |
| SierraDB healthcheck | **broken** — `redis-cli` does not exist in the image |
| Garage healthcheck | **broken** — image is a bare binary without a shell |
| Garage config | **missing** — no `config.toml` mounted; garage never started |
| `api` Docker build | **broken** — Dockerfile misses `.patches/` and `config/`, pins rust 1.91 (locked deps need 1.94) |

## 3. Implementation plan

### 3.1 Resolve the ADR-024 "assume" flag (SierraDB TLS)

**Result: `tqwewe/sierradb:0.3.1` has NO native TLS listener.** Verified against
the upstream sources (`AppConfig` has no TLS fields; unknown config keys are
silently ignored) and by probing the image. → the **`stunnel` sidecar** is the
shipped mechanism (the ADR's documented fallback).

### 3.2 Rust: client-side TLS + startup gate

- `Cargo.toml` (workspace): `redis` gains `tls-rustls` + `tokio-rustls-comp`
  (powers `rediss://` + `Client::build_with_tls` root pinning).
- `crates/infra/Cargo.toml`: `reqwest` (`rustls-tls`) for the OpenDAL custom
  HTTP client; same version/TLS backend as OpenDAL's.
- `crates/infra/src/tls.rs` (new): `root_cert_from_env` / `from_value` (checked
  PEM path resolution, unit-tested) and `s3_builder` (S3 builder that pins the
  root via `reqwest::ClientBuilder::add_root_certificate` passed through
  `opendal::raw::HttpClient`; region from `S3_REGION`, default `garage`).
- `crates/infra/src/photo/storage.rs` + `reporting/storage.rs`: `from_env` /
  `build_s3_operator` now read `S3_TLS_ROOT_CERT` and use `s3_builder`.
- `crates/api/src/tls_config.rs` (unit-tested via `crates/api/tests/tls_config.rs`, ADR-024): `TlsConfig::violations()`
  enforces `sslmode=verify-full` **and** `sslrootcert=…` on
  `DATABASE_URL`/`MIGRATOR_DATABASE_URL`, `rediss://` on `SIERRADB_URL`,
  `https://` on `S3_ENDPOINT` + `REPORT_BACKUP_*_ENDPOINT`.
- `crates/api/src/main.rs`:
  - Gate: `REQUIRE_IN_TRANSIT_TLS=true` (set by prod compose) runs the
    validation and fails fast with a clear error. Explicitly opt-in — never
    inferred from `OIDC_ISS`, because the local IdP overlay
    (docker-compose.idp.yml) must keep working against plaintext dev URLs.
  - Redis client: when `SIERRADB_TLS_ROOT_CERT` is set, build via
    `RedisClient::build_with_tls` (pinned root); otherwise plain `open` (dev).

### 3.3 docker-compose.prod.yml — internal TLS mesh

- **`step-ca`** (`smallstep/step-ca:0.28.4`, digest-pinned): first-boot CA
  bootstrap from `STEP_CA_PASSWORD` (the one allowed `.env` seed, ADR-027)
  via the image's `DOCKER_STEPCA_INIT_*` entrypoint; CA DNS must include
  `step-ca`; own LUKS-protected volume (ADR-023). Healthcheck via
  `curl -kfsS https://127.0.0.1:9000/health` (CA cert has no IP SAN).
- **`tls-provision`** (same image, digest-pinned, root user, `tls/provision.sh`):
  copies the step-ca root into the shared `tls_data` volume, issues 24h leaf
  certs (`postgres`, `stunnel`, `caddy` — SAN + `localhost`, leaf+intermediate
  chain, `--force` for renewal) and re-issues every 12h. Key permissions:
  postgres key `0:70`/`0640` (postgres:16-alpine runs ssl as uid/gid 70),
  stunnel/caddy keys `0600`. Healthcheck: cert files exist.
- **Postgres**: `ssl=on` + cert/key from `tls_data` (read-only); clients must
  use `sslmode=verify-full&sslrootcert=/certs/root_ca.crt`.
- **`stunnel`** sidecar (`dweomer/stunnel`, digest-pinned, entrypoint
  overridden to `/usr/bin/stunnel`): TLS terminate on `:9091` → plaintext
  RESP3 to `sierradb:9090`. **SierraDB publishes no host port.**
- **Caddy**: internal site `https://caddy:9443` with file-based certs from
  `tls_data` (`/certs/caddy.crt|key`), `reverse_proxy garage:3900`; `api`
  uses `S3_ENDPOINT=https://caddy:9443` + `S3_TLS_ROOT_CERT`.
  File-based (not Caddy-ACME-from-step-ca): step-ca's ACME challenge routing
  inside the Docker network would need DNS/SNI wiring for a hostname that only
  exists on the compose network; the provision loop keeps the short-TTL files
  fresh. (ADR-024's open question re one vs two Caddy instances: **one**, the
  public edge + internal `:9443` site.)
- **`api`**: `DATABASE_URL` with `sslmode=verify-full&sslrootcert=…`,
  `SIERRADB_URL=rediss://stunnel:9091/?protocol=resp3`,
  `SIERRADB_TLS_ROOT_CERT=/certs/root_ca.crt`, `S3_ENDPOINT=https://caddy:9443`,
  `S3_TLS_ROOT_CERT=/certs/root_ca.crt`, `REQUIRE_IN_TRANSIT_TLS=true`,
  `tls_data:/certs:ro`.

### 3.4 Pre-existing blockers fixed along the way (required for the stack to boot)

- **SierraDB healthcheck**: image ships no `redis-cli` → RESP3 PING via a
  bash script (`scripts/sierradb-healthcheck.sh`) — no perl, no inline
  compose commands (dev + prod compose).
- **Garage config + healthcheck**: the `dxflrs/garage` image is a bare static
  binary (no shell, no env-var config, `-c` required). New `garage-config`
  one-shot (alpine, digest-pinned) renders `config.toml` from `$GARAGE_*` via
  `scripts/garage-config.sh` into the `garage_config` volume; garage
  healthcheck is exec-form (`/garage -c /etc/garage/config.toml status`).
- **Long compose commands → scripts** (cleanup): the SierraDB healthcheck and
  the Garage config renderer are the only multi-line shell snippets and both
  live in `scripts/` now — no inline heredocs / inline perl in compose YAML.
- **`api` Docker build**: Dockerfile now copies `.patches/` + `config/`
  (needed by the workspace manifest and the embedded seed TOML) and pins
  `rust:1.94-bookworm` (locked deps — e.g. `sqlx 0.9` — require ≥1.94).
- **OpenDAL region**: the S3 operator never set a region (would fail with
  "region is missing"); `S3_REGION` defaults to `garage` (matches the tests).

### 3.5 CI + docs

- `.github/workflows/ci.yml` `compose-config` job: `STEP_CA_PASSWORD` +
  `GARAGE_METRICS_TOKEN` placeholders; `caddy validate` for the prod Caddyfile
  now mounts throwaway self-signed `/certs` placeholders (internal site).
- `runbooks.md`: tier table (step-ca, stunnel, tls-provision, garage-config),
  §0 in-transit TLS, boot prerequisites (`STEP_CA_PASSWORD`), CA backup,
  healthcheck + pinning notes.
- `AGENTS.md`: new env vars (`REQUIRE_IN_TRANSIT_TLS`, `SIERRADB_TLS_ROOT_CERT`,
  `S3_TLS_ROOT_CERT`, `S3_REGION`), updated `SIERRADB_URL`/`S3_ENDPOINT`.
- `ADR-024`: verification note resolving the SierraDB TLS "assume".
- `docs/issues/issue-156-step-ca-internal-ca-and-tls.md` — this record.

## 4. Out of scope (per issue)

- Host firewall / port hygiene (incl. publishing Postgres) — issue #158.
- LUKS volume under the CA volume — ADR-023 / issue #158.
- Garage at-rest encryption / SSE-C — ADR-023 (separate change).
- Native RESP3 TLS in SierraDB — upstream-tracking follow-up (ADR-024 note).
- Vault (ADR-027) provisioning of the step-ca password — the compose
  bootstraps from `STEP_CA_PASSWORD` directly; vault wiring is a later change.
- `pg_hba` `hostssl`-only enforcement (server-side TLS-required) — follow-up;
  app clients already enforce `verify-full`.

## 5. Verification (results)

- [x] **step-ca**: first-boot CA bootstrap from `STEP_CA_PASSWORD`; healthcheck
      green; root + intermediate issued (10y / 1y).
- [x] **tls-provision**: copies root, issues 24h leaf certs (postgres, stunnel,
      caddy — SANs + chain), `--force` renewal loop; healthcheck green; key
      modes verified (`0640 root:70` for postgres, `0600` others).
- [x] **Postgres TLS**: `psql sslmode=verify-full sslrootcert=…` connects;
      `verify-full` without the pinned root is rejected; plaintext still
      accepted server-side (`ssl=on` — app clients force verify-full).
- [x] **SierraDB via stunnel**: API projectors subscribe over
      `rediss://stunnel:9091` with the pinned root (api boot log: all
      projector streams + sagas spawned); stunnel TLS listener verified.
- [x] **Garage via Caddy**: `curl --cacert root_ca.crt https://caddy:9443/`
      reaches Garage (S3 XML response); without the pinned root the TLS
      handshake fails; Garage `:3900` not published.
- [x] **API boot** (`REQUIRE_IN_TRANSIT_TLS=true`): TLS config validated,
      migrations + app pool over TLS postgres, projectors over rediss,
      photo storage initialised against `https://caddy:9443`, auth dev mode,
      listening on `:3000`; public Caddy edge serves the API (unchanged).
- [x] `docker compose -f docker-compose.prod.yml config` (prod + dev + idp +
      caddy overlays) validates; `caddy validate` passes for both Caddyfiles.
- [x] `cargo build/test/clippy` on the workspace; new unit tests pass
      (`tls_config` 10, `infra::tls` 3).
- [x] `gitleaks detect` — clean (all compose secrets are `${VAR:?}`-style).

> Local smoke-test note: the author's Docker daemon cannot resolve
> `index.crates.io` inside BuildKit (host DNS quirk), so the `api` image was
> built with `docker buildx build --network host` locally; CI runners have
> working DNS and use the plain compose build.
