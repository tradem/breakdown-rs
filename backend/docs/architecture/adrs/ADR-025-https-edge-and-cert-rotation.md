# ADR-025: HTTPS Edge Transport — Reverse Proxy & Certificate Issuance

**Status**: Proposed
**Date**: 2026-08-01
**Author**: Tobias Rademacher (@tradem); glm-5.2 (neuralwatt)
**Related**: ADR-005 (Axum), ADR-024 (in-transit DB TLS), ADR-026 (host hardening), ADR-010 (OIDC, tokens in browser)

---

## Context

The Axum API (ADR-005) binds `0.0.0.0:3000` by default and must be fronted by a
TLS-terminating reverse proxy for the public edge. Requirements:

- **HTTPS everywhere**; plain HTTP redirected or refused.
- **Automatic certificate issuance and rotation** — no manual cert paths,
  because the team has "limited operations capacity" (ADR-009) and a single
  self-managed VPS.
- **Single-VPS, Docker-based** deployment; the chosen tool must be open-source
  and hostable inside `docker-compose`.
- The frontend (Svelte, ADR-007) and the future mobile client (Flutter) call
  this edge; OIDC tokens (ADR-010) traverse it, so TLS integrity at the edge is
  also an auth-security concern.
- Swagger UI (`/swagger-ui`) must remain reachable only for authorized users in
  production (lockdown is a deployment concern, tracked separately from this
  ADR's transport decision).

Constraints:

- No managed SaaS for certificates beyond the free, open ACME protocol.
- The VPS likely has a single public IPv4/IPv6 and a domain with DNS control.

## Decision

**Recommended primary: Caddy as the edge reverse proxy.** Caddy is open-source,
ships as a single static binary, runs as a `docker-compose` service, and
obtains and rotates Let's Encrypt/ZeroSSL certificates **automatically** via
ACME with on-by-default HTTPS — including wildcard issuance via DNS-01 if a DNS
provider plugin is configured.

Concretely:

1. A `caddy` service fronts the `api` service. Caddy listens on `:80` (HTTP→
   HTTPS redirect) and `:443` (TLS).
2. TLS is issued by ACME (HTTP-01 by default; DNS-01 challenge via a Caddy DNS
   provider plugin for wildcard or behind-only setups). Renewal is automatic;
   Caddy rotates certs in memory without restart.
3. The `api` container is bound to a Docker-internal network only and is never
   published directly to the host; Caddy is the sole public entry point.
4. Optional: Caddy enforces a conservative baseline (modern cipher suites,
   HSTS header, request body size limits aligned with `PHOTO_MAX_SIZE_MB`) and
   can rate-limit `/auth/*` and photo-upload paths.

Certificate issuance and rotation are **transparent to the end user and to the
application**: there is no cert-touching step in `main.rs`, no `.env` env-var
for leaf certs, and no operator action beyond initial DNS + domain config.

## Consequences

### Positive
- Zero-touch HTTPS for a single-domain deployment; certs rotate without ops.
- Single binary, minimal resource footprint — fits the small-VPS target
  (ADR-009).
- Strong defaults out of the box (modern TLS, HSTS, automatic redirects).
- Clear boundary: only Caddy is published; the Axum app and the DB/SierraDB/
  vault are internal.

### Negative
- ACME HTTP-01 requires `:80`/`:443` reachable from the internet; for VPS with
  restrictive firewalls use DNS-01 (needs a DNS provider plugin + API token,
  stored via the vault per ADR-027, not in `.env`).
- Let's Encrypt rate limits can bite in noisy/rapid-redeploy setups; mitigated
  by Caddy's shared ACME state and reuse across restarts.
- Caddy's config language (Caddyfile) is one more thing to review; mitigated
  by keeping it tiny and version-controlled.

## Alternatives Considered

1. **Traefik** — strong, also ACME-capable, label-driven. Rejected as primary
   only on weight: Traefik's dynamic-config surface is larger than the app
   needs for a single backend. Listed as alternative for teams already
   running Traefik.
2. **nginx + certbot (cron-renewed)** — works but requires cron/certbot wiring,
   a reload hook, and manual cert path management; strictly more moving parts
   than Caddy's built-in ACME. Listed as alternative.
3. **Application-level TLS in Axum (`axum-server` + `rustls`)** — rejected:
   pushes cert issuance/rotation into the Rust binary and away from the
   infrastructure boundary; ACME-from-Rust is more fragile and less observable
   than a dedicated proxy. Also complicates request limits and HSTS.

## Security / Compliance Notes
- Caddy's ACME account key and any DNS-01 provider token are *secrets* and
  must be provided via the vault (ADR-027) or the LUKS-protected config volume
  (ADR-023), never checked into the repo.
- HSTS + HTTPS-only must be enabled even for the Swagger UI path.
- In production, `/swagger-ui` should be gated (basic-auth or IP allowlist) as
  a deployment concern; this ADR only fixes the transport, not the authz.
- Pair with ADR-024 so that, even if the proxy and DB happen to be co-located,
  the east-west traffic is also encrypted.
