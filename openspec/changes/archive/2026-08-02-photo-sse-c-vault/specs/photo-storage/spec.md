## MODIFIED Requirements

### Requirement: PhotoStorage port abstracts byte storage
The system SHALL define a `PhotoStorage` trait in `crates/core` with four operations: `store` (write bytes for a photo_id + variant), `fetch` (read bytes for a photo_id + variant), `delete_all` (delete all variants for a photo_id), and `list` (enumerate photo_ids present in storage, for GC). The port is type-safe over `PhotoId` and `PhotoVariant` and SHALL NOT expose storage keys (key layout is an adapter detail in `crates/infra`). The v1 adapter (`OpenDalPhotoStorage`) SHALL use OpenDAL's S3 service against Garage and, in production, SHALL use the Vault-derived bucket-scoped AES256 SSE-C configuration. The production adapter SHALL fail closed when that configuration is unavailable and SHALL never silently fall back to plaintext or SSE-S3.

#### Scenario: Port is storage-key-agnostic
- **WHEN** the `PhotoStorage` port is invoked
- **THEN** the caller passes only `PhotoId` and `PhotoVariant` (never a raw key string)
- **AND** the OpenDAL key layout (`{photo_id}/{variant}`) is constructed entirely inside `OpenDalPhotoStorage`

#### Scenario: Port supports variant-aware operations
- **WHEN** a variant is stored or fetched
- **THEN** the caller passes `PhotoVariant` (`Original`, `Thumb`, or `Medium`)
- **AND** the adapter resolves the storage key for that variant

#### Scenario: Adding a variant does not change the port signature
- **WHEN** a future change adds a `Large` variant
- **THEN** only the `PhotoVariant` enum gains a variant and the saga gains a generation step
- **AND** the `PhotoStorage` trait method signatures are unchanged

#### Scenario: Production storage is SSE-C-only
- **WHEN** the API composition root constructs `OpenDalPhotoStorage`
- **THEN** it supplies the 32-byte key loaded from Vault
- **AND** all S3 byte operations use the AES256 SSE-C headers
- **AND** an unavailable Vault produces a service-unavailable adapter instead of a plaintext operator
