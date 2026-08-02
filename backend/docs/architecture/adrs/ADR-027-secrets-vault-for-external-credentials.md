# ADR-027: Secrets Vault for External Credentials (GDrive, AI Tokens)

**Status**: Proposed
**Date**: 2026-08-01
**Author**: Tobias Rademacher (@tradem); glm-5.2 (neuralwatt)
**Related**: ADR-002 (event sourcing), ADR-010 (OIDC), ADR-023 (at-rest crypto),
ADR-024 (in-transit TLS), ADR-026 (host hardening), ADR-028 (settings authz),
ADR-029 (GDPR erasure / crypto-shredding)

---

## Context

A privileged role — the **Costume Designer** (`Role::CostumeDesigner`, serde
`costume_designer`) — owns external-integration
credentials: Google Drive access data today, and AI-backend access tokens in
future. The **Costume Assistant** (`Role::CostumeAssistant`, serde
`costume_assistant`) also needs the ability to save such credentials (GDrive /
AI tokens etc.) in support of the designer's external-integration work. Both
roles are the legitimate credential owners for this ADR set. These credentials
must be reachable from an admin/settings panel and are
modelled as domain "Settings Aggregates". The event store is the system of
record and is **append-only and immutable** (ADR-002).

Hard requirements (prompt):

- The **EventStore must NOT carry raw secrets.** It carries only non-sensitive
  references (e.g. a vault key/id) that point to a secrets vault.
- The vault must be **open-source and run inside `docker-compose`**. No paid
  SaaS, no manual user-side setup of external systems.
- Vault lifecycle (provisioning, key wrapping, rotation) must be **transparent
  to the end user** — the backend handles it automatically; the user must
  never configure the vault manually.
- `.env` is acceptable **only** to bootstrap the vault's own root key on first
  boot.
- Store no plaintext or reversibly-encrypted secrets in events, source, logs,
  backups, or OpenAPI specs.

## Decision

**Recommended primary: HashiCorp Vault** (OSS binary, file storage backend)
run as a `docker-compose` service. Vault is chosen because it ships
**Transit** (envelope encryption / key management): the application can encrypt
secrets without ever holding the master key, and **crypto-shredding** (key
destruction) is a first-class operation — which is the load-bearing
requirement for GDPR Art. 17 (ADR-029).

### Reference pattern (the "Settings Aggregate" secret lifecycle)

1. **Vault bootstrap (one-time, transparent).** On first boot a one-shot
   bootstrap reads the vault **root key / unseal key** from the `.env`-provided
   boot secret (the only allowed `.env` use), unseals Vault, enables the
   `transit` and `kv-v2` engines, writes an **app token** with a minimal policy
   (`transit: encrypt/decrypt/rewind/datakey`, `kv: read/write` on the
   `settings-secrets` path), and then **discards the root token**. The root
   unseal key thereafter lives only on the LUKS-protected volume + an offline
   backup (ADR-023). The operator (let alone the end user) never types a vault
   password into the app.
2. **Per credential, on creation.** When a Costume Designer or Costume
   Assistant submits a GDrive
   or AI credential via the settings panel:
   - The API asks Vault Transit for a **dedicated data-encryption key** (DEK)
     for this credential: `transit/datakey/plaintext/<cred-key-id>` returns
     both a ciphertext-wrapped DEK (stored by Vault) and the plaintext DEK
     (used in-memory only to encrypt the raw credential).
   - The API encrypts the raw credential with the DEK and stores the
     **ciphertext** in the vault `kv` store under
     `settings-secrets/<settings-aggregate-id>`, returning *only* the
     `cred-key-id` / `kv-version` reference to the caller.
   - The **EventStore** persists a `SettingsAggregate` event carrying nothing
     but the **non-sensitive reference** (`vault_key_id`,
     `settings_aggregate_id`), never the secret bytes.
3. **Read path.** A command that needs the credential looks up the reference
   from its aggregate state, fetches the ciphertext from Vault `kv`, and asks
   Transit to decrypt the DEK + (in memory) decrypts the credential. The
   plaintext lives only in transient memory for the duration of the external
   call and is zeroised on drop.
4. **Rotation.** Vault Transit supports `rewind`/versioned keys. Per-credential
   DEK rotation re-encrypts the DEK under a new key version without touching
   the stored ciphertext reference; secret material can also be re-encrypted
   on an operator schedule. Rotation is backend-initiated and transparent.
5. **Revocation / offboarding.** Destroying the Transit key
   `/<cred-key-id>` (or its current version) makes the stored ciphertext
   permanently un-decryptable = **crypto-shredding**; this is the GDPR exit
   ramp (ADR-029). Revocation of an *upstream* OAuth token (GDrive/AI) is a
   separate act: the backend deletes/rotates via the provider's revoke
   endpoint and records a `SettingsAggregate` event marking the binding
   `Revoked`; the vault key may be retained until the defensible retention
   window closes, then destroyed.

### Photo SSE-C bucket key (Issue #159)

The photo object-store encryption path uses the same Vault custody pattern but
has a deliberately separate, bucket-scoped record. The fixed Transit key id is
`photo-sse-c`; the API requests one random 256-bit datakey, stores only its
Transit-wrapped ciphertext in KV-v2 at `photo-sse-c`, and loads the plaintext
only at API boot to configure the OpenDAL S3 operator with AES256 SSE-C. The
plaintext key is never an environment variable, event field, projection,
Garage metadata value, log field, or API response.

The bucket scope is a conscious OpenDAL 0.52.0 limitation: its SSE-C support
is configured on the S3 operator rather than per request. Per-photo or
per-season crypto-shredding is therefore a follow-up that requires a safe
per-request header seam and a new rotation/concurrency design. Before
destroying `photo-sse-c`, stop all API/photo workers; if a quiescence procedure
is used instead, explicitly verify release of every OpenDAL operator. After
restart, verify that the API cannot reload the DEK and photo operations return
503.
Destroying `photo-sse-c` then renders the entire `costume-photos` bucket
undecryptable and is an intentional whole-bucket purge, not ordinary photo
deletion.

If Vault is unavailable at boot, the API still serves unrelated routes, but
constructs an unavailable photo adapter. HTTP photo handlers map its typed
dependency-unavailable error to HTTP 503. Sagas and GC do not produce HTTP
responses; they surface the same typed failure to their supervisors, which
retry or log a visible failure according to the worker policy. The code never
falls back to plaintext S3. Bucket-key rotation is a two-key operational
backfill: preserve the old ciphertext in a durable rollback copy with a
manifest, and store both wrapped DEKs in least-privilege KV-v2 rotation
records: `kv/data/photo-sse-c-rotation/<rotation-id>/candidate` and
`/rollback`. The rollback record also stores the old active version so Transit
can recreate the old operator after promotion. Rewrite and verify staged
candidate objects, promote the candidate by writing the same KV-v2 path with
the expected active-version CAS, then restart the API. A CAS conflict leaves
the winning record active and requires reconciliation. The rollback copy,
manifest, candidate record, and rollback-DEK record remain available until the
migration outcome and rollback window are complete; cleanup uses the narrowly
scoped KV-v2 metadata delete capability.

### Compatibility with event sourcing

The aggregate's **events store only references** (`vault_key_id`,
`settings_aggregate_id`, `binding_state`). Replay rebuilds references; the
secret never enters the event log. This preserves the CQRS/event-sourcing
invariants of ADR-002 and the CQRS-boundary rule (AGENTS §1) naturally, because
vault I/O happens at the **adapter edge** (API handler → vault), not inside the
write-side command/existence path. The Settings Aggregate's `apply()` is pure
and reference-only; no secret material crosses the CQRS boundary.

### Graceful degradation when the vault is offline at boot

- The API starts normally; everything that does **not** need secrets works
  (projectors, read queries, costume/scene CRUD, OIDC auth).
- Endpoints that require a credential (GDrive sync, AI calls) return **503
  Service Unavailable** with a clear error; the settings panel shows the
  credential binding as `Unreachable` but never the secret.
- Critically, the vault being offline does **not** break command/event
  processing, because events carry only references — the aggregate can still be
  written and replayed; only the live secret *use* is blocked.

## Consequences

### Positive
- Event store stays secret-free; replay safety and audit integrity preserved.
- Crypto-shredding is a native primitive — clean GDPR Art. 17 exit.
- Per-credential DEKs limit blast radius: one key compromise ≠ all secrets.
- Transparent to the end user (no manual vault setup); `.env` only seeds the
  root key on first boot.

### Negative
- Vault is a heavyweight additional service on a small VPS; memory budget must
  be planned (mitigation: `vault` in `dev`/file-storage mode is modest, and
  this is a bounded single-host deployment).
- Root-key compromise on the single VPS is high-blast-radius (see edge cases);
  mitigated by ADR-023 LUKS, ADR-026 host hardening, short-lived app tokens,
  and discarding the root token after bootstrap.
- Adds a runtime dependency: a vault outage degrades credential-using features
  (graceful, per above) but never the core domain.

## Alternatives Considered

1. **Infisical** (OSS self-hostable secret manager) — good dev UX and a server
   binary, but lacks a first-class **envelope-encryption / crypto-shredding**
   primitive comparable to Vault Transit; weaker fit for the GDPR requirement.
   Listed as alternative.
2. **SOPS + `age` (file-based, no server)** — minimal and strong, but
   crypto-shredding requires per-secret key files and manual bookkeeping;
   re-encryption and rotation are awkward in an event-sourced, multi-aggregate
   setting, and there is no in-process decrypt-without-app-holding-master-key
   primitive. Listed as alternative only for very small deployments.
3. **Application-managed keys in `.env` / config volume** — rejected outright:
  violates the "no secrets outside the vault" and the "user never configures
  the vault manually" rules.

## Security / Compliance Notes

- **Log hygiene:** the application must never log plaintext secret bytes,
  unwrapped DEK plaintext, or full vault responses. Vault API calls happen in
  a dedicated tracing span with a redacting layer; structured log fields that
  reference a secret use only its `vault_key_id`/version, never the value.
  Field names caught by the redactor include `secret`, `token`, `password`,
  `refresh_token`, `access_token`, `unwrap*`, `dek`, `ciphertext` (logged only
  as a truncated hash for correlation).
- **OpenAPI/Swagger:** request/response schemas for the settings endpoints
  must reference the secret as an opaque `vault_key_id` field and must never
  expose a `value`/`secret` payload field on read — the submit path accepts the
  raw secret and never echoes it back.
- **Backups:** vault `kv` ciphertexts and Transit-wrapped DEKs can be backed
  up freely (they are useless without the Vault master keys); the Vault master
  keys / unseal material are backed up offline, separate from data (ADR-023).
- **Edge case — shared secret by reference across aggregates:** if one vault
  key is referenced by multiple Settings Aggregates, crypto-shredding that key
  affects all of them (scope question). Mitigation: **one DEK per credential
  binding**, never shared across aggregates; if sharing is ever needed, record
  a reference-count in the projection and only destroy when count hits zero.
- **Edge case — upstream token revoked while still referenced:** the aggregate
  stays referenceable; an external call surfaces the provider's 401/revoked
  error and the backend records a `SettingsAggregate` `Revoked`/`Stale` state;
  settings panel prompts re-auth.
- **Edge case — root-key compromise:** blast radius = all `transit`/`kv` secrets
  readable until rotation. Recovery: re-key Transit (create new key versions,
  re-encrypt all credentials using the in-app read path), rotate the app token,
  and rotate the vault unseal key from the offline backup; because credentials
  originate at providers (GDrive/AI), we can also force a re-OAuth and replace
  secret material end-to-end without downtime.
