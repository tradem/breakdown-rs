# ADR-024: Database Encryption in Transit (TLS for Postgres & SierraDB)

**Status**: Proposed
**Date**: 2026-08-01
**Author**: Tobias Rademacher (@tradem); glm-5.2 (neuralwatt)
**Related**: ADR-003 (PostgreSQL), ADR-015/016 (SierraDB), ADR-025 (edge TLS), ADR-026 (host hardening)

---

## Context

Connections that must be encrypted in transit on the VPS:

- **Axum API ↔ PostgreSQL** (DML app pool, the `breakdown_app` role).
- **Migrator ↔ PostgreSQL** (boot-only, `breakdown_migrator`).
- **Axum API ↔ SierraDB** (`SIERRADB_URL`, RESP3, port 9090).
- **`PostgresProcessor` (projectors) ↔ PostgreSQL** — long-lived subscriber
  connections that update projections.

Although all of these run on a single host today, "Docker network = trusted" is
not an acceptable security baseline: a single compromised container or a
misconfigured published port turns an unencrypted link into a credential
exfiltration path. We treat in-transit encryption as defense-in-depth against
container-to-container lateral movement, accidental port publication, and future
multi-host expansion.

Constraints:

- Self-managed, single VPS, no paid SaaS KMS.
- SierraDB is the upstream image `tqwewe/sierradb:0.3.1`, RESP3 only. Whether
  this image exposes a TLS listener cannot be verified from this repo's
  sources — flagged as **assumed**.
- Postgres 16 supports TLS natively (`ssl=on`, server cert + CA).
- Garage (`dxflrs/garage:v1.0.1`) has **no built-in TLS** on its S3 API
  endpoint (confirmed by the upstream [encryption cookbook](https://garagehq.deuxfleurs.fr/documentation/cookbook/encryption/));
  `S3_ENDPOINT` today is `http://garage:3900` (Docker-internal, plaintext).

## Decision

**Recommended primary: native TLS on every link, with certificates issued by a
self-hosted internal CA (`step-ca`, Smallstep).** `step-ca` is open-source,
self-hostable, runs as a service in `docker-compose`, and supports short-lived
(ACME-style) cert issuance and rotation without external dependencies.

1. **PostgreSQL (API, migrator, projectors).** Enable `ssl=on`; configure a
   server certificate + private key signed by the internal `step-ca` root.
   All clients connect with `sslmode=verify-full` and pin the `step-ca` root.
   `DATABASE_URL`/`MIGRATOR_DATABASE_URL` carry `sslmode=verify-full` and the
   root via `sslrootcert=<path mounted from a read-only config volume>`.
2. **SierraDB (API event-store connection).**
   - *If* the `tqwewe/sierradb:0.3.1` image supports a TLS RESP listener
     (assumed/flagged): configure it with a `step-ca`-issued server cert and
     point `SIERRADB_URL` at the TLS port with `?protocol=resp3` preserved and
     TLS enabled on the redis client.
   - *Fallback / until verified*: terminate TLS in a small **`stunnel`** or
     **`redis-tls`** sidecar that fronts SierraDB. The API connects to the
     sidecar over TLS, the sidecar connects to SierraDB over the loopback /
     Docker internal network only. SierraDB itself is never published and is
     reachable only from the sidecar.
3. **Garage (API photo-storage connection).** Garage ships no TLS listener,
   so the API↔Garage S3 link is encrypted by fronting Garage with the **Caddy**
   reverse proxy (ADR-025) on a Docker-internal TLS port, using a
   `step-ca`-issued server cert. `S3_ENDPOINT` becomes the Caddy TLS URL and
   the OpenDAL S3 client is configured with the pinned `step-ca` root.
   Garage's plaintext `:3900` is bound to the Docker internal network only
   and is never published to the host. (Alternative, listed not chosen: a
   `stunnel` sidecar dedicated to Garage, mirroring the SierraDB pattern; or
   a WireGuard overlay — heavier than reusing the already-present Caddy.)

`step-ca` runs as an additional `docker-compose` service with its own
encrypted volume; its CA private key is provisioned on first boot from the
`.env`-bootstrapped root key (the one allowed use of `.env`, see ADR-027). Cert
TTL is short (e.g. 24h) with automatic renewal; rotation is transparent to the
application because `sqlx` and the RESP3 client pick up renewed certs on
reconnect / pool refresh.

## Consequences

### Positive
- All DB and object-store traffic is encrypted on the wire; a compromised
  container or mispublished port cannot read or replay application traffic.
- Verifiable trust: `verify-full` + pinned root prevents MITM even inside the
  Docker network.
- Short TTL + auto-rotation limits the value of a stolen cert.
- Path to a multi-host deployment is clear (TLS already mandatory).

### Negative
- Additional `step-ca` service to operate and back up (CA key compromise has
  high blast radius; mitigated by ADR-023 LUKS + offline root backup).
- `stunnel` sidecar for SierraDB adds a moving part *if* native RESP3 TLS is
  unavailable — operational surface until the assumption is verified.
- Connection Establishment is slightly more costly; reconnect/storm behaviour
  must be load-tested.
- CA must be highly available at cert-renewal time or clients fail to refresh
  (mitigation: 24h TTL + cached certs survive short CA outages).

## Alternatives Considered

1. **WireGuard / Tailscale mesh between containers** — viable and would
   encrypt-in-transit at L3; but it makes the *network* the trust boundary
   rather than the *links*, scales poorly to per-link auth, and adds a kernel
   dependency. Listed as alternative, not primary.
2. **Self-signed certs without a CA** — rejected: rotation and trust pinning
   become manual and error-prone; `step-ca` removes that cost for ~zero
   extra operational weight.
3. **No in-transit encryption (rely on Docker network isolation)** — rejected
   as the standing posture: acceptable for dev only; fails the
   defense-in-depth and "no data theft" goals.

## Security / Compliance Notes
- All DB connection strings in production must enforce `sslmode=verify-full`
  (Postgres) and TLS-on (SierraDB/sidecar). The OpenDAL S3 client must pin the
  `step-ca` root for the Garage-via-Caddy endpoint. A missing `sslmode`, a
  plaintext `SIERRADB_URL`, or an `http://` `S3_ENDPOINT` should fail a
  startup config check in `main.rs`.
- Cert/key paths are mounted read-only into containers from a single config
  volume; the app never writes certificates itself.
- Open question: confirm whether `tqwewe/sierradb:0.3.1` supports TLS. While
  unverified, ship the `stunnel` sidecar as the documented recommendation;
  downgrade to native TLS only after a verified upstream capability. (Garage
  TLS support is already resolved: **not built-in** — front it with Caddy.)
