## Why

Garage currently stores photo objects with only filesystem/LUKS at-rest protection. A compromised S3 credential or a live host process that can read Garage's data directory could therefore obtain plaintext photo bytes. Issue #159 adds defense-in-depth by making the API use Garage SSE-C with customer key material held by the already-provisioned Vault, without placing key bytes in configuration, events, logs, or object storage.

## What Changes

- Add a bucket-scoped, stable 256-bit photo SSE-C key lifecycle backed by Vault Transit and KV-v2.
- Extend the Vault adapter and bootstrap policy to provision/retrieve the wrapped photo DEK without exposing it to Garage.
- Configure the OpenDAL Garage operator with AES256 SSE-C headers for every photo read, write, stat, copy, and delete operation as supported by the backend.
- Make photo storage unavailable rather than plaintext-capable when Vault cannot supply the key; photo endpoints and photo workers surface `503`/dependency errors.
- Add deterministic unit/adapter tests for key lifecycle, SSE-C configuration, redaction, Vault-down behavior, and byte round-trips.
- Document bucket-level crypto-shredding and a key-rotation runbook (re-copy/rewrite existing objects under a new key).
- Explicitly defer per-photo/per-season keys until OpenDAL exposes a safe per-request SSE-C seam.

## Capabilities

### New Capabilities

- `photo-sse-c-encryption`: Vault-custodied bucket-level SSE-C configuration, fail-closed photo storage, rotation, and operational guarantees.

### Modified Capabilities

- `photo-storage`: photo byte operations now require SSE-C and must not silently use plaintext storage when the Vault key is unavailable.

## Impact

- **Infrastructure:** `crates/infra/src/vault.rs`, `crates/infra/src/photo/storage.rs`, S3/TLS builder helpers, API boot wiring, and Vault bootstrap policy.
- **Runtime configuration:** new Vault/photo-key settings and compose/runbook documentation; no raw key environment variable.
- **Tests:** infra unit tests and Garage/Vault contract coverage where the local runtime is available.
- **Security posture:** all existing and new photo variants use one bucket-scoped customer key; destroying the key crypto-shreds the bucket. The key is transiently present only in API memory and is never sent to logs, SierraDB, Postgres, or events.
