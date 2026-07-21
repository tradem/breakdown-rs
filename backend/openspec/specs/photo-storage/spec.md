# Photo Storage

## Purpose

Provides the ability to store, serve, and delete costume photo bytes using
an S3-compatible object store (Garage) accessed via OpenDAL. The photo
lifecycle (existence, content-type, size, variant status, deletion) is an
event-sourced `Photo` aggregate tracked in SierraDB; the bytes are a
side-effect stored in Garage.

## Requirements

### Requirement: Photo aggregate is the single source of truth for photo lifecycle
The system SHALL model photo lifecycle (existence, content-type, size, variant generation status, EXIF-stripped flag, deletion) as a `Photo` aggregate (category `"photo"`) tracked in SierraDB. The `PhotoStorage` port (CRUD on bytes via OpenDAL/S3 against Garage) SHALL be a side-effect store: events say bytes should exist; the projector and sagas enforce that. Every projection table for photos (`projection_photo`, `projection_photo_variant`, `projection_photo_gc_run`) SHALL be replay-derived from SierraDB events, so that a Postgres loss is recoverable by replaying events without a bespoke Garage scan.

#### Scenario: Postgres loss is recoverable by event replay
- **WHEN** the Postgres read-model database is lost and SierraDB + Garage are intact
- **THEN** running `sqlx::migrate!` and booting the `PhotoProjector` (and the existing `CostumeProjector`) repopulates `projection_photo`, `projection_photo_variant`, and `projection_costume_photo` by replaying events from SierraDB
- **AND** no bespoke S3-aware reconciliation scan is required

#### Scenario: Garage loss is detectable
- **WHEN** Garage bytes are lost but Postgres + SierraDB are intact
- **THEN** `projection_photo` rows still exist (event-sourced)
- **AND** a `PhotoStorage::fetch` for a photo with no Garage object returns a `NotFound` error
- **AND** the read model honestly reports the photo as existing while fetches fail (404 on the download endpoint)

#### Scenario: Photo aggregate lifecycle events
- **WHEN** a photo is uploaded, normalised, has variants generated, or is deleted
- **THEN** the corresponding `Photo` aggregate events (`PhotoUploaded`, `OriginalNormalized`, `VariantGenerated`, `VariantFailed`, `PhotoDeleted`) are emitted to SierraDB
- **AND** each event is projected by the `PhotoProjector` into `projection_photo` / `projection_photo_variant`

### Requirement: PhotoStorage port abstracts byte storage
The system SHALL define a `PhotoStorage` trait in `crates/core` with four operations: `store` (write bytes for a photo_id + variant), `fetch` (read bytes for a photo_id + variant), `delete_all` (delete all variants for a photo_id), and `list` (enumerate photo_ids present in storage, for GC). The port is type-safe over `PhotoId` and `PhotoVariant` and SHALL NOT expose storage keys (key layout is an adapter detail in `crates/infra`). The v1 adapter (`OpenDalPhotoStorage`) SHALL use OpenDAL's S3 service against Garage.

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

### Requirement: Garage runs Docker-internal-only
The system SHALL run Garage as a Docker container with no host port mapping; only the API binary SHALL be able to reach Garage via the internal docker network. The frontend SHALL never receive a direct Garage URL. Both `docker-compose.dev.yml` and `docker-compose.prod.yml` SHALL include a `garage` service pinned to `dxflrs/garage:v1.0.1` with a persistent named volume, configured via the env vars `S3_ENDPOINT`, `S3_ACCESS_KEY`, `S3_SECRET_KEY`, `S3_BUCKET=costume-photos`.

#### Scenario: Garage is not exposed on the host
- **WHEN** the dev or prod compose is brought up
- **THEN** the `garage` service has no `ports:` mapping to the host
- **AND** a client on the host network cannot reach Garage's S3 API directly

#### Scenario: API reaches Garage internally
- **WHEN** the API binary starts
- **THEN** it reads `S3_ENDPOINT` and connects to Garage on the internal docker network
- **AND** `OpenDalPhotoStorage` operations succeed against the internal S3 endpoint

### Requirement: Proxy upload via the API
The system SHALL accept photo uploads via `POST /costumes/{cid}/photos` where the API receives the bytes (multipart), validates them, stores them in Garage, and dispatches the `UploadPhoto` command on the `Photo` aggregate followed by `LinkPhoto` on the `Costume` aggregate. The frontend SHALL NOT upload directly to Garage.

#### Scenario: Successful proxy upload
- **WHEN** a client POSTs a valid JPEG (≤ size cap) to `/costumes/{cid}/photos` with a valid `photo_id` and authorised user
- **THEN** the API stores the original bytes in Garage via `PhotoStorage::store`
- **AND** dispatches `UploadPhoto` on the `Photo` aggregate (emitting `PhotoUploaded`)
- **AND** dispatches `LinkPhoto` on the `Costume` aggregate (emitting `PhotoLinked`)
- **AND** returns `201 Created` with the `photo_id` and variant statuses (`original`: pending, `thumb`: pending, `medium`: pending)

#### Scenario: Compensating delete on link failure
- **WHEN** `PhotoStorage::store` succeeds but `LinkPhoto` fails (e.g. version conflict)
- **THEN** the API calls `PhotoStorage::delete_all(photo_id)` to remove the stored bytes
- **AND** no `PhotoUploaded` event is emitted (the upload command is not dispatched)
- **AND** no orphaned bytes remain in Garage

### Requirement: Content-type allowlist and size cap
The system SHALL reject uploads whose content-type is not in the allowlist `image/jpeg`, `image/png`, `image/webp` with HTTP `415 Unsupported Media Type`. HEIC/HEIF (`image/heic`, `image/heif`) SHALL be explicitly rejected with an error message instructing the client to convert to JPEG before upload. The maximum upload size SHALL be configurable via `PHOTO_MAX_SIZE_MB` (default 20 MB); uploads exceeding the cap SHALL be rejected with HTTP `413 Payload Too Large` before bytes are stored.

#### Scenario: Accepted content-types upload successfully
- **WHEN** a client uploads a JPEG, PNG, or WebP image within the size cap
- **THEN** the upload proceeds to storage and command dispatch

#### Scenario: HEIC is rejected
- **WHEN** a client uploads an `image/heic` file
- **THEN** the API returns `415 Unsupported Media Type` with a message explaining HEIC is not supported and the client should convert to JPEG before upload
- **AND** no bytes are stored in Garage

#### Scenario: Oversized upload is rejected
- **WHEN** a client uploads an image larger than `PHOTO_MAX_SIZE_MB`
- **THEN** the API returns `413 Payload Too Large` before storing any bytes

### Requirement: Proxy download is authorisation-checked per request
The system SHALL serve photo bytes via `GET /costumes/{cid}/photos/{pid}/bytes?variant={original|thumb|medium}`. The API SHALL validate the caller's JWT and check `SeasonPhotoAccessPolicy` on EVERY download request before fetching bytes from Garage. The response SHALL stream the bytes with `Content-Type`, `Content-Length`, `ETag` (when available), and `Cache-Control: private, max-age=300`. The frontend SHALL NOT receive a presigned Garage URL at any point in v1.

#### Scenario: Authorised download succeeds
- **WHEN** an authorised user GETs `/costumes/{cid}/photos/{pid}/bytes?variant=thumb`
- **THEN** the API validates the JWT, checks `SeasonPhotoAccessPolicy` for the season of costume `cid`, fetches the thumb bytes from Garage via `PhotoStorage::fetch`
- **AND** streams the bytes with `Cache-Control: private, max-age=300` and an `ETag`

#### Scenario: Unauthorised download is rejected
- **WHEN** a user without a costume-dept role in any active block of the costume's season GETs the bytes endpoint
- **THEN** the API returns `403 Forbidden` before fetching any bytes from Garage

#### Scenario: No presigned URLs are issued
- **WHEN** any download flow is exercised
- **THEN** the response never contains a Garage URL
- **AND** Garage is reachable only from the API binary on the internal docker network

### Requirement: Three variants with EXIF stripped everywhere
The system SHALL store three variants per photo: `Original` (re-encoded upright, EXIF stripped, JPEG quality ~95), `Thumb` (~200×200, JPEG quality 80), `Medium` (~800×800, JPEG quality 85). The thumbnail saga SHALL decode the original, read EXIF orientation via `kamadak-exif`, apply the rotation to the decoded `DynamicImage`, and re-encode to JPEG without EXIF. The saga SHALL also re-encode and overwrite the `Original` variant in Garage with the upright, EXIF-stripped version. EXIF stripping is enforced by default in v1; a toggle to disable it is an explicit v2 non-goal.

#### Scenario: Variants are generated after upload
- **WHEN** a `PhotoUploaded` event is emitted
- **THEN** the `PhotoThumbnailSaga` fetches the original bytes from Garage
- **AND** decodes with orientation correction, re-encodes the original upright EXIF-stripped, and overwrites it in Garage
- **AND** generates `Thumb` and `Medium` variants and stores them in Garage
- **AND** dispatches `NormalizeOriginal`, `GenerateVariant(Thumb)`, and `GenerateVariant(Medium)` on the `Photo` aggregate

#### Scenario: Stored original has no EXIF
- **WHEN** the saga completes for an uploaded photo that originally carried EXIF (including GPS)
- **THEN** decoding the stored `Original` bytes with an EXIF reader returns no EXIF data
- **AND** the image is displayed upright (orientation applied)

#### Scenario: Variant generation failure is terminal but non-fatal
- **WHEN** the saga fails to generate a variant (e.g. decode error)
- **THEN** it dispatches `MarkVariantFailed` for that variant
- **AND** the `Photo` aggregate emits `VariantFailed` carrying an error message
- **AND** other variants and the original may still be `Ready`
- **AND** the read model honestly reports the failed variant's status as `failed`

### Requirement: N:M photo ↔ costume link with refcount-driven deletion
The system SHALL support linking one photo to multiple costumes (the link is a `Costume` event: `PhotoLinked` / `PhotoUnlinked`, unchanged). The `PhotoDeletionSaga` SHALL react to `PhotoUnlinked` events, count remaining references via `SELECT count(*) FROM projection_costume_photo WHERE photo_id = $1`, and dispatch `DeletePhoto` on the `Photo` aggregate only when the refcount reaches zero. The `PhotoBytesCleanupSaga` SHALL react to `PhotoDeleted` events and call `PhotoStorage::delete_all` to remove the bytes from Garage.

#### Scenario: Unlink from one of many costumes keeps the bytes
- **WHEN** a photo P is linked to costumes A and B and `PhotoUnlinked` (costume A, photo P) fires
- **THEN** the `PhotoDeletionSaga` counts 1 remaining reference (costume B)
- **AND** does NOT dispatch `DeletePhoto`
- **AND** the bytes for P remain in Garage

#### Scenario: Unlink from the last costume deletes the bytes
- **WHEN** the last `PhotoUnlinked` for photo P fires (refcount reaches 0)
- **THEN** the `PhotoDeletionSaga` dispatches `DeletePhoto` on the `Photo` aggregate
- **AND** the `PhotoBytesCleanupSaga` reacts to the resulting `PhotoDeleted` event and calls `PhotoStorage::delete_all(P)`
- **AND** the Garage objects for P (original + variants) are deleted

#### Scenario: Deletion is idempotent under event redelivery
- **WHEN** the same `PhotoDeleted` event is delivered twice
- **THEN** the second `PhotoBytesCleanupSaga` invocation calls `delete_all` again
- **AND** Garage returns success for deleting already-absent keys (no error)

### Requirement: Periodic orphan GC with advisory lock and history
The system SHALL run a periodic `PhotoGcSweepTask` that reconciles the Garage object listing against `projection_photo` and deletes orphans (photo_ids present in Garage but absent from `projection_photo`) older than `PHOTO_GC_MAX_AGE_SECS`. The sweep SHALL acquire a Postgres advisory lock at start so at most one sweep runs per cycle (multi-replica safe). Each sweep SHALL record a row in `projection_photo_gc_run` (started_at, finished_at, scanned, orphans_found, orphans_deleted, dry_run). The GC config SHALL be read from env at startup in v1: `PHOTO_GC_ENABLED` (default true), `PHOTO_GC_INTERVAL_SECS` (default 3600), `PHOTO_GC_MAX_AGE_SECS` (default 86400), `PHOTO_GC_BATCH_SIZE` (default 1000), `PHOTO_GC_DRY_RUN` (default false).

#### Scenario: Orphan older than the age gate is deleted
- **WHEN** the GC sweep finds a Garage object for photo_id P that has no `projection_photo` row and whose age exceeds `PHOTO_GC_MAX_AGE_SECS`
- **THEN** the sweep calls `PhotoStorage::delete_all(P)`
- **AND** records the deletion in `projection_photo_gc_run.orphans_deleted`

#### Scenario: In-flight upload is not swept
- **WHEN** the GC sweep finds a Garage object for photo_id P with no `projection_photo` row whose age is less than `PHOTO_GC_MAX_AGE_SECS`
- **THEN** the sweep does NOT delete the object (the upload window is seconds; the gate protects it)

#### Scenario: Dry-run logs but does not delete
- **WHEN** `PHOTO_GC_DRY_RUN=true`
- **THEN** the sweep logs orphans it would delete
- **AND** does not call `PhotoStorage::delete_all`
- **AND** records `dry_run=true` and `orphans_deleted=0` in `projection_photo_gc_run`

#### Scenario: Advisory lock prevents concurrent sweeps
- **WHEN** a second sweep attempts to start while another is in progress
- **THEN** the second sweep's `pg_try_advisory_lock` returns false
- **AND** the second sweep skips this cycle without error

#### Scenario: GC run history is recorded
- **WHEN** a sweep completes
- **THEN** a row is written to `projection_photo_gc_run` with started_at, finished_at, scanned count, orphans_found count, orphans_deleted count, and dry_run flag

### Requirement: Garage testcontainers harness
The system SHALL extend `crates/integration-tests` (per ADR-014's one-harness rule) with a Garage testcontainer helper using image `dxflrs/garage:v1.0.1`. The helper SHALL start the container, wait for healthcheck, create a layout, create an access key, create the `costume-photos` bucket, and grant the key permissions on the bucket. Two tiers of tests SHALL be provided: Tier-3 (Postgres + Garage) for `OpenDalPhotoStorage` adapter correctness, and Tier-4 (Postgres + SierraDB + Garage) for the full saga round-trip. Both tiers SHALL be excluded from `cargo-mutants`.

#### Scenario: Tier-3 adapter test
- **WHEN** the `OpenDalPhotoStorage` integration test runs
- **THEN** it starts Garage, exercises `store`, `fetch`, `delete_all`, `store_variant` against real S3 semantics
- **AND** verifies HEAD, overwrite, and listing behaviour against Garage

#### Scenario: Tier-4 full round-trip
- **WHEN** the Tier-4 integration test runs
- **THEN** it starts Postgres + SierraDB + Garage, spawns the `PhotoProjector` + `PhotoThumbnailSaga` + `PhotoDeletionSaga` + `PhotoBytesCleanupSaga`
- **AND** performs a proxy upload, polls `projection_photo_variant` until `Ready`, asserts thumbnail dimensions and EXIF-stripped original
- **AND** performs a proxy download, asserts bytes match
- **AND** unlinks the photo, polls until bytes are gone from Garage
- **AND** exercises the N:M deletion path (link to two costumes, unlink from one — bytes survive; unlink from the second — bytes gone)
- **AND** exercises the GC orphan sweep (write orphan bytes directly, run sweep, assert deletion respects the age gate)

### Requirement: Projection schema for photo lifecycle
The system SHALL create three new Postgres projection tables via a migration: `projection_photo` (photo_id PK, content_type TEXT, size_bytes BIGINT, created_at TIMESTAMPTZ, updated_at TIMESTAMPTZ), `projection_photo_variant` (photo_id UUID, variant TEXT, status TEXT, size_bytes BIGINT, created_at TIMESTAMPTZ, PRIMARY KEY (photo_id, variant)), and `projection_photo_gc_run` (run_id UUID PK, started_at TIMESTAMPTZ, finished_at TIMESTAMPTZ, scanned BIGINT, orphans_found BIGINT, orphans_deleted BIGINT, dry_run BOOLEAN). The existing `projection_costume_photo` table SHALL be reused unchanged as the M:N link. The `CostumePhotoView` SHALL be enriched with `content_type`, `size_bytes`, and `variants: Vec<PhotoVariantView>` (kind, status, size_bytes).

#### Scenario: Migration creates the new tables
- **WHEN** `sqlx::migrate!("./migrations")` runs against an empty Postgres
- **THEN** `projection_photo`, `projection_photo_variant`, and `projection_photo_gc_run` exist with the expected columns and primary keys
- **AND** `projection_costume_photo` is unchanged

#### Scenario: CostumePhotoView carries variant metadata
- **WHEN** the API returns a `CostumeView` for a costume with photos
- **THEN** each `CostumePhotoView` includes `id`, `content_type`, `size_bytes`, and `variants: Vec<PhotoVariantView>` where each variant view has `kind`, `status`, and `size_bytes`

### Requirement: PhotoStorage port is non-CRQS split (CRUD on bytes)
The `PhotoStorage` port SHALL be a CRUD port for byte storage, distinct from the event-sourced command/repository split used by aggregates. It SHALL support both read (`fetch`, `list`) and write (`store`, `delete_all`) operations on the same store. This is intentional: byte storage is a side-effect of photo lifecycle events, not an event-sourced entity itself.

#### Scenario: Port supports both read and write
- **WHEN** the sagas and API invoke the port
- **THEN** the same `PhotoStorage` instance is used for `store` (saga writes original + variants; API writes original on upload), `fetch` (API streams bytes on download; saga reads original to generate variants), `delete_all` (saga deletes on `PhotoDeleted`; GC deletes orphans), and `list` (GC enumerates for reconciliation)

#### Scenario: Port is wired into ProductionPorts
- **WHEN** the API composition root (`main.rs`) builds `ProductionPorts`
- **THEN** a `PhotoStorage` instance (`OpenDalPhotoStorage` configured against Garage) is constructed and exposed alongside the existing command/repository ports
