## Context

Garage currently receives photo bytes through OpenDAL's S3 service without customer-provided encryption. LUKS protects the Garage volume at rest, but does not protect against a leaked valid S3 credential or a live process that can read the Garage data directory. OpenDAL 0.52.0 exposes SSE-C on `services::S3` as an operator-level configuration and automatically adds the required algorithm, customer-key, and customer-key-MD5 headers to S3 operations. It does not expose a safe per-request SSE-C override.

Issue #157 already provides `VaultClient`, Vault Transit/KV-v2 bootstrap, a least-privilege app token, TLS pinning, and lazy unavailability handling. The photo adapter is currently constructed once in `api/src/main.rs` and cloned into handlers, sagas, and the GC scheduler. The design must preserve that composition seam and must not put key material into the core port, event store, projections, logs, or environment variables.

## Goals / Non-Goals

**Goals:**

- Store and retrieve one stable 256-bit SSE-C DEK for the `costume-photos` bucket through Vault.
- Configure every production photo OpenDAL operator with `AES256` SSE-C.
- Fail closed: no plaintext photo operator is constructed when Vault is unavailable or the key is malformed.
- Keep the API process available when Vault is down, while photo operations return a dependency-unavailable error that maps to HTTP 503.
- Keep the key out of tracing, `Debug`, events, Postgres, and Garage metadata.
- Cover first-use provisioning, concurrent first-use behavior, round trips, and Vault-down behavior with tests.
- Document bucket-level crypto-shredding and an operator-controlled rotation/backfill procedure.

**Non-Goals:**

- Per-photo or per-season key granularity. OpenDAL's current backend-level configuration is insufficient for that safely; it is a follow-up spike.
- Encrypting event payloads, projections, report archives, or Garage metadata.
- Replacing LUKS or in-transit TLS.
- Making Vault availability a prerequisite for unrelated API routes or command processing.
- A new public API endpoint for key management.

## Decisions

### 1. One stable bucket DEK, wrapped by Vault Transit

Use the fixed Vault Transit key `photo-sse-c` and store one Transit-wrapped random 32-byte DEK in Vault KV-v2 at `photo-sse-c`. On first use, the adapter creates the Transit key if needed, requests `transit/datakey/plaintext/photo-sse-c`, and stores only the wrapped DEK using KV-v2 compare-and-set (`cas=0`). If another process wins the first-write race, the loser discards its candidate and reads the committed record. On every boot, the client reads the wrapped DEK and asks Transit to decrypt it.

The plaintext DEK is passed directly from `VaultClient` to the S3 builder, remains in the OpenDAL operator for the process lifetime, and is never serialized or logged. The Vault method validates exactly 32 decoded bytes before returning. KV records contain only the key id and wrapped DEK, never plaintext key bytes.

A per-photo or per-season key was rejected for this release because OpenDAL 0.52.0 only configures SSE-C on the S3 backend/operator. A future implementation must first prove a per-request header seam, then address operator caching, key lookup latency, rotation, and concurrency.

### 2. Fail closed without failing the whole API boot

`OpenDalPhotoStorage` gains an explicit unavailable state. `main.rs` constructs `VaultClient` before photo storage, attempts to load/provision the bucket DEK, and constructs an SSE-C operator only on success. If Vault is unavailable, it logs only the dependency error and installs the unavailable adapter. All four `PhotoStorage` operations return `DomainError::ServiceUnavailable`; existing HTTP error mapping exposes 503 for photo endpoints and background jobs retry/fail visibly rather than writing plaintext.

The legacy operator constructors used by tests remain available only for callers that supply an already-configured operator. Production's environment constructor is changed to require the Vault-derived key; it cannot silently create a plaintext S3 operator. Test fixtures explicitly configure a deterministic SSE-C key.

### 3. Keep shared TLS builder behavior unchanged for reports

Add an SSE-C-specific S3 builder helper (or an optional customer-key argument with a non-SSE default for report storage) while preserving the report archival adapter's current behavior. Only the photo boot path supplies the customer key. The helper uses OpenDAL's `server_side_encryption_with_customer_key("AES256", key)` so OpenDAL computes the base64 key and MD5 and marks sensitive headers appropriately.

### 4. Rotation is an explicit two-key operational migration

Rotation is not an in-place Transit version bump: changing the bucket-level DEK makes existing objects unreadable. The runbook therefore requires a maintenance/backfill job that can read with the old operator and write each object with a new operator, verifies the rewritten object, then atomically commits the new wrapped DEK to Vault and restarts/reloads API workers. During the migration, the old key must remain available. A failed backfill leaves the old KV record active and is rolled back by deleting only the uncommitted candidate. The runbook records that destroying `photo-sse-c` before backfill is a deliberate whole-bucket crypto-shred operation.

### 5. Bootstrap policy and secret hygiene

Extend the least-privilege Vault policy with only the paths needed to read/create/update the `photo-sse-c` Transit key, request/decrypt its datakey, and read/write the single KV record. Do not add a raw-key environment variable, API response, event field, or log field. Update ADR-023/027 and the operations runbook with the chosen granularity and rotation limitation.

## Risks / Trade-offs

- **[Bucket-wide crypto-shredding]** Destroying the DEK makes every photo variant unreadable. → This is explicit in ADR/runbook; one DEK per credential/object is deferred until per-request SSE-C is proven.
- **[OpenDAL retains key material in the operator]** The API must hold the key to issue SSE-C requests. → Use Vault as the only durable custody, zeroizing temporary buffers, never format/log the key, and keep the operator `Debug` redacted.
- **[Vault outage]** Existing photo reads/writes fail while the API remains available. → Return a typed `ServiceUnavailable`, preserve the no-plaintext invariant, and document recovery/health checks.
- **[First-boot race]** Multiple API instances could generate different candidates. → Use KV-v2 `cas=0`, discard the losing candidate, and reload the committed record.
- **[Key rotation interruption]** A mixed old/new bucket can be unreadable by one operator. → Require a maintenance window/two-key backfill and verification before committing the new record; keep rollback instructions.
- **[Legacy/test operators]** A manually constructed operator could omit SSE-C. → Production construction is fail-closed and all maintained Garage integration fixtures are changed to use SSE-C; future public constructors should be treated as test seams.
- **[Garage compatibility]** SSE-C behavior depends on Garage's S3 implementation. → Add a real Garage contract test for PUT/HEAD/GET without and with the key; keep LUKS as the baseline if the target runtime rejects SSE-C.

## Migration Plan

1. Deploy the Vault policy and code while the existing bucket is still plaintext/LUKS-backed.
2. Provision `photo-sse-c` and a wrapped bucket DEK. Existing objects are not readable through the new SSE-C operator until they are migrated; stage the rollout with no photo traffic or a maintenance window.
3. Backfill/rewrite existing original/thumb/medium objects with the new SSE-C operator, verify reads, and then enable the SSE-C-only API workers.
4. New uploads and generated variants use SSE-C automatically. Monitor 503s and Garage `InvalidRequest`/`InvalidArgument` errors.
5. For rotation, create a candidate wrapped DEK, run the two-key backfill, verify all objects, commit the candidate KV record, and restart the API. Retain the previous wrapped record only for the documented rollback window.
6. Rollback before migration completion by restoring the old KV record and restarting. Do not destroy the old Transit key until verification and the rollback window have passed.

## Open Questions

- A staging run must verify the exact Garage `v1.0.1` behavior for anonymous/direct GET without the SSE-C key and for HEAD/DELETE semantics; the integration test is the executable answer.
- Per-photo/per-season crypto-shredding remains a follow-up dependent on a safe per-request OpenDAL/S3 header mechanism.
