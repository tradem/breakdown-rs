## MODIFIED Requirements

### Requirement: Vault outage fails closed for photos
The API SHALL remain bootable when Vault is unavailable, but SHALL construct `OpenDalPhotoStorage::recoverable(...)` with an empty SSE-C operator cache that fails closed rather than a plaintext-capable operator. All photo storage operations SHALL return a dependency-unavailable error until the key can be loaded and the operator is constructed. Photo HTTP endpoints SHALL map that error to HTTP 503.

#### Scenario: Vault is unavailable at API boot
- **WHEN** the API cannot reach Vault or cannot read the app token/key record
- **THEN** the API starts without an SSE-C photo operator
- **AND** no photo bytes can be written or read
- **AND** photo endpoints return HTTP 503 rather than storing plaintext

#### Scenario: Vault recovers without an API restart
- **WHEN** Vault becomes reachable after the API booted while Vault was unavailable
- **THEN** the next photo storage operation lazily resolves the SSE-C key and builds the SSE-C operator
- **AND** photo storage operations use SSE-C without changing the key record and without restarting the API
- **AND** operations issued before Vault recovered continue to return the dependency-unavailable error

#### Scenario: Vault outage after operator construction
- **WHEN** the SSE-C operator was already constructed and Vault becomes unavailable afterwards
- **THEN** photo storage operations continue to work using the cached SSE-C operator
- **AND** no further Vault round-trip is required

## ADDED Requirements

### Requirement: Photo saga work survives transient Vault outages
The photo thumbnail and bytes-cleanup sagas SHALL retry transient dependency-unavailable failures (Vault unreachable) with backoff instead of abandoning the event, so that a transient Vault outage never permanently drops saga work. The event-handler cursor SHALL advance only after successful event processing.

#### Scenario: Thumbnail saga encounters a Vault outage
- **WHEN** the thumbnail saga processes a `PhotoUploaded` event while the SSE-C key cannot be resolved
- **THEN** the saga retries the storage operations with backoff
- **AND** once Vault recovers the saga completes thumbnail generation and variant commands
- **AND** the event is not permanently lost

#### Scenario: Bytes-cleanup saga encounters a Vault outage
- **WHEN** the bytes-cleanup saga processes a `PhotoDeleted` event while the SSE-C key cannot be resolved
- **THEN** the saga retries the deletion with backoff
- **AND** once Vault recovers the object bytes are deleted from storage

#### Scenario: Handler failure does not advance the cursor
- **WHEN** an event handler fails to process an event
- **THEN** the acknowledged SierraDB cursor is not advanced past the failed event
- **AND** a cursor is acknowledged only after the corresponding events were processed successfully
