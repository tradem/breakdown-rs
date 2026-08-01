// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (opencode-go)

# Issue #155 — Caddy edge reverse proxy with ACME (ADR-025)

> Systematic implementation plan + implementation record for issue #155:
> HTTPS edge transport via Caddy with automatic ACME certificate
> issuance/rotation, keeping the `api` container Docker-internal only.

## 1. Problem statement

The Axum API (ADR-005) binds `0.0.0.0:3000` and is published directly to the
host (`docker-compose.prod.yml` → `ports: "${API_PORT:-3000}:3000"`). There is
no TLS at the edge, no certificate rotation, and the API is reachable from the
public internet without a proxy in front. ADR-025 decides on **Caddy** as the
edge reverse proxy: single static binary, automatic ACME issuance/rotation,
strong TLS defaults, HSTS — and a clear network boundary (only Caddy on
`:80`/`:443` is public).

## 2. Current-state audit (branch cut from `main`)

| Concern | Current state on `main` |
|---|---|
| API host port publication | `docker-compose.prod.yml` publishes `${API_PORT:-3000}:3000` |
| TLS termination | none — plain HTTP on `:3000` |
| Cert issuance/rotation | none |
| Edge security headers / HSTS | none |
| Version-controlled proxy config | none (no `Caddyfile`) |
| Compose config validation | not gated in CI |
| Gitleaks / secrets in compose | prod compose uses `${VAR:?...}` placeholders only |

## 3. Implementation plan

### 3.1 `backend/Caddyfile` (new — version-controlled prod edge)

- Site block `{$DOMAIN}` (domain placeholder; `DOMAIN` supplied by compose).
- `tls { protocols tls1.2 tls1.3 }` — explicit modern-TLS floor (Caddy defaults
  are already modern; OCSP stapling stays on).
- `header` block: `Strict-Transport-Security: max-age=31536000; includeSubDomains`,
  `X-Content-Type-Options: nosniff`, `-Server`.
- `request_body { max_size {$PHOTO_MAX_SIZE_MB:20}MB }` — edge body ceiling
  aligned with the API's `PHOTO_MAX_SIZE_MB` (compose passes the same value to
  both services).
- `reverse_proxy api:3000` — all paths proxied to the internal API.
- Default-deny posture (documented in-file): no `file_server`, no catch-all
  returning 200; unknown Host/SNI → Caddy's built-in 404, unknown paths → the
  API's own 404 fallback.

### 3.2 `backend/docker-compose.prod.yml`

- Add `caddy` service:
  - `image: caddy:2.9.1-alpine@sha256:b4e395…a534f0` — **pinned by digest**
    (issue #155 scope bullet).
  - Ports `${CADDY_HTTP_PORT:-80}:80` and `${CADDY_HTTPS_PORT:-443}:443` —
    the only host-published ports. Admin API `:2019` stays internal.
  - `volumes`: `./Caddyfile:/etc/caddy/Caddyfile:ro`, `caddy_data:/data`
    (ACME account key + certs), `caddy_config:/config` (runtime config).
  - `environment`: `DOMAIN: ${DOMAIN:?DOMAIN is required}`,
    `PHOTO_MAX_SIZE_MB: ${PHOTO_MAX_SIZE_MB:-20}`.
  - `depends_on: api: condition: service_started`.
- **Remove** `ports:` from the `api` service — Docker-internal only. Comment
  added explaining the boundary (ADR-025 acceptance: API not publicly reachable).
- Add `caddy_data:` / `caddy_config:` named volumes (LUKS volume per ADR-023).

### 3.3 Dev overlay (issue #155: "optionally the dev overlay")

- `backend/Caddyfile.dev` — `tls internal` (Caddy's internal CA, self-signed),
  same HSTS/limit directives, `reverse_proxy host.docker.internal:3000`.
- `backend/docker-compose.caddy.yml` — `caddy:2.9.1-alpine` (**tag**, not
  digest, allowed for dev), `extra_hosts: host.docker.internal:host-gateway`,
  mounts `Caddyfile.dev`. Usage:
  `docker compose -f docker-compose.dev.yml -f docker-compose.caddy.yml up -d`
  then `https://localhost` against the host-run API.

### 3.4 Docs

- `backend/docs/operations/runbooks.md` — Caddy row in the tier table, boot
  prerequisites (`DOMAIN`), api-internal-only note, `caddy_data` backup
  (ACME rate-limit protection), digest-pinning entry, healthcheck note, new
  §5 *HTTPS edge & certificates (ADR-025)* incl. DNS-01 follow-up via the
  vault (ADR-027) and LUKS volume placement (ADR-023).
- `backend/docs/issues/issue-155-caddy-edge-reverse-proxy.md` — this record.

### 3.5 CI guardrail

`.github/workflows/ci.yml` gains a `compose-config` job running
`docker compose config --quiet` for prod + dev + idp + caddy overlay with
placeholder env (daemon-free) — makes the "`docker compose config` validates"
acceptance criterion mechanically enforced.

## 4. Out of scope (per issue)

- `/swagger-ui` production authz lockdown — deployment concern (ADR-025).
- Host firewall rules for `:80`/`:443` — ADR-026 / VPS runbook.
- step-ca / internal DB TLS — ADR-024 (separate issue).
- DNS-01 challenge + Caddy DNS provider plugin — documented follow-up
  (ADR-027 vault sourcing), not shipped.

## 5. Verification (results)

- [x] `docker compose -f docker-compose.prod.yml config` passes (required env
      satisfied by placeholders; api exposes no host port).
- [x] `docker compose -f docker-compose.dev.yml -f docker-compose.caddy.yml
      config` and with `-f docker-compose.idp.yml` pass.
- [x] `caddy validate` passes for `Caddyfile` and `Caddyfile.dev`
      (env placeholders resolved).
- [x] Local HTTPS smoke test (dev overlay + dummy host backend):
      HTTPS 200 with `Strict-Transport-Security: max-age=31536000;
      includeSubDomains` + `nosniff` + no `Server` header; HTTP→HTTPS 308;
      unknown host on `:80` → 404 (explicit catch-all, auto-HTTPS redirect
      unaffected); unknown SNI on `:443` → TLS-level reject; unknown path →
      proxied 404 from the app; 25 MB body → 413, 5 MB body → 200 (edge
      ceiling aligned with `PHOTO_MAX_SIZE_MB`).
- [x] `gitleaks detect` — no leaks found.

> Note: the dev overlay uses `network_mode: host` + `127.0.0.1:3000` because
> host-gateway container→host traffic is dropped on the author's dev host
> (environment quirk, not a compose issue); host networking is also the
> simplest Linux-only choice and matches ADR-026's target platform.
