# Photo SSE-C Encryption

## Purpose

Defines Vault-custodied customer-provided encryption for Garage photo objects and the fail-closed behavior of photo storage when the encryption key is unavailable.

## Requirements

### Requirement: Photo bucket key is Vault-custodied
The system SHALL use one stable 256-bit customer-provided encryption key for the `costume-photos` bucket. The key SHALL be generated through Vault Transit's datakey endpoint, persist only as a Transit-wrapped value in Vault KV-v2, and use the fixed non-secret key identifier `photo-sse-c`. The plaintext key SHALL be returned to the API only in memory for OpenDAL operator construction.

#### Scenario: First boot provisions the bucket key
- **WHEN** the photo SSE-C key record does not exist and Vault is reachable
- **THEN** the Vault adapter ensures the `photo-sse-c` Transit key exists
- **AND** obtains a random 32-byte plaintext DEK plus its Transit-wrapped ciphertext
- **AND** stores only the wrapped ciphertext and key identifier in the dedicated KV-v2 record
- **AND** configures photo storage with the plaintext DEK without persisting or logging it

#### Scenario: Existing boot unwraps the bucket key
- **WHEN** the dedicated KV-v2 record exists and Vault is reachable
- **THEN** the adapter reads the wrapped DEK and asks Vault Transit to decrypt it
- **AND** validates that the decoded plaintext is exactly 32 bytes
- **AND** does not generate or replace the existing DEK

#### Scenario: Concurrent first boot is deterministic
- **WHEN** two API processes provision the missing bucket key concurrently
- **THEN** KV-v2 compare-and-set allows exactly one candidate record to win
- **AND** the losing process discards its candidate plaintext and loads the committed record
- **AND** both processes configure the same customer key

### Requirement: Photo OpenDAL operations use SSE-C
The production photo storage adapter SHALL configure the OpenDAL S3 operator with `AES256` SSE-C using the Vault-derived bucket key. Reads, HEAD/stat operations, writes, copies, and other operations requiring S3 customer-key headers SHALL use that configuration. The adapter SHALL never use a plaintext or SSE-S3 fallback.

#### Scenario: Upload sends customer-key encryption
- **WHEN** the API stores an original or generated photo variant
- **THEN** the S3 request contains the AES256 SSE-C algorithm, customer-key, and customer-key-MD5 headers
- **AND** Garage stores the object as SSE-C ciphertext

#### Scenario: Download requires the customer key
- **WHEN** an authorised API request fetches a photo variant
- **THEN** the S3 read/HEAD requests include the SSE-C customer-key headers
- **AND** the API returns the original bytes after Garage decrypts them

#### Scenario: Direct access without the key fails
- **WHEN** a direct S3 client reads an SSE-C object without the matching customer key
- **THEN** Garage rejects the request
- **AND** no plaintext photo bytes are returned

### Requirement: Vault outage fails closed for photos
The API SHALL remain bootable when Vault is unavailable, but SHALL construct an explicitly unavailable photo storage adapter rather than a plaintext-capable operator. All photo storage operations SHALL return a dependency-unavailable error until the key can be loaded by a subsequent restart. Photo HTTP endpoints SHALL map that error to HTTP 503.

#### Scenario: Vault is unavailable at API boot
- **WHEN** the API cannot reach Vault or cannot read the app token/key record
- **THEN** the API starts without an SSE-C photo operator
- **AND** no photo bytes can be written or read
- **AND** photo endpoints return HTTP 503 rather than storing plaintext

#### Scenario: Vault recovers after restart
- **WHEN** Vault becomes reachable and the API is restarted
- **THEN** the API loads the existing wrapped key
- **AND** photo storage operations use SSE-C without changing the key record

### Requirement: Photo key material is excluded from durable application data
The system SHALL NOT place the plaintext photo key in environment variables, source-controlled files, OpenAPI schemas, SierraDB events, Postgres projections, Garage user metadata, tracing fields, or error messages. Temporary decoded key buffers SHALL be zeroized where ownership ends, and `Debug` output SHALL expose configuration state only.

#### Scenario: Logs and audit data are inspected
- **WHEN** photo storage or Vault operations are logged or audited
- **THEN** logs and audit rows contain at most the non-secret identifier `photo-sse-c`
- **AND** they contain neither plaintext key bytes nor wrapped-key response bodies

#### Scenario: Operator debug output is rendered
- **WHEN** the photo storage adapter is formatted with `Debug`
- **THEN** the output contains no endpoint credentials, customer key, base64 key, or key digest

### Requirement: Bucket key rotation is operationally safe
The system SHALL document rotation as a two-key migration: create a candidate wrapped DEK, preserve every old ciphertext in a durable rollback copy with a manifest, rewrite and verify staged candidate objects, promote the candidate by writing it to `kv/data/photo-sse-c` with KV-v2 `options.cas` set to the expected active version, and restart photo workers. A CAS conflict SHALL leave the winning active record untouched and require reconciliation. Staging objects, the rollback copy, manifest, and candidate record SHALL remain available until the migration outcome and rollback retention complete. Before destroying any bucket Transit key, all API/photo workers SHALL be stopped or quiesced and release of every OpenDAL operator SHALL be explicitly verified. Destroying the bucket Transit key SHALL be documented as whole-bucket crypto-shredding followed by restart verification.

#### Scenario: Rotation completes successfully

- **WHEN** an operator has rewritten and verified all photo variants with a candidate key
- **AND** the candidate is written to `kv/data/photo-sse-c` with the expected active-version CAS
- **THEN** the CAS succeeds and the candidate becomes the active KV-v2 record
- **AND** a restarted API reads all migrated objects with the new key
- **AND** the old key is retained only for the documented rollback window

#### Scenario: Rotation is interrupted

- **WHEN** a rewrite or verification fails before promotion, or the CAS promotion conflicts
- **THEN** the old or winning KV-v2 record remains active
- **AND** the candidate key is not used by normal photo workers
- **AND** canonical objects can be restored from the durable rollback copy
- **AND** staging objects, the rollback copy, manifest, and candidate record remain until the outcome is known

#### Scenario: Crypto-shredding is requested

- **WHEN** all API/photo workers are stopped or quiesced
- **AND** release of every OpenDAL operator is explicitly verified
- **AND** the `photo-sse-c` Transit key is intentionally destroyed
- **THEN** all objects encrypted with the bucket key become permanently undecryptable
- **AND** after restart the API cannot reload the DEK and photo operations return HTTP 503
- **AND** the operation is treated as a deliberate whole-bucket photo purge
