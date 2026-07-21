## 1. ADR-019 and shared types (core)

- [ ] 1.1 Write **ADR-019** (at `docs/architecture/adrs/ADR-019-costume-photo-storage.md`) recording: (a) Garage-as-S3 decision superseding ADR-009's Phase 1 `fs` plan; (b) Photo-as-aggregate decision (SSOT alignment, disaster-recovery story); (c) proxy-only serving decision (security over bandwidth); (d) derived-authorisation v1 decision with the v2 `SeasonCrew` evolution pointer. Cross-link from ADR-009 and ADR-002.
- [ ] 1.2 Add `PhotoId(Uuid)` opaque UUIDv7 id to `crates/core/src/shared.rs` (mirror `EpisodeId`/`CostumeCategoryId`); re-export from `crates/core/src/lib.rs`.
- [ ] 1.3 Add `PhotoVariant { Original, Thumb, Medium }` enum (with `as_str()`) to `crates/core/src/shared.rs`.
- [ ] 1.4 Add `VariantStatus { Pending, Ready, Failed }` enum to `crates/core/src/shared.rs`.

## 2. Photo aggregate (core)

- [ ] 2.1 Create `crates/core/src/photo/` module (`mod.rs` + `aggregate`/`commands`/`events`/`views`/`error`/`ports`) mirroring the `scene/`/`costume/` layout; wire `pub mod photo;` into `crates/core/src/lib.rs`.
- [ ] 2.2 Implement `events.rs`: `PhotoEvent` variants `PhotoUploaded`, `OriginalNormalized`, `VariantGenerated`, `VariantFailed`, `PhotoDeleted` (each carrying `id: PhotoId`, relevant metadata, `version: AggregateVersion`); implement `kameo_es::EventType`.
- [ ] 2.3 Implement `commands.rs`: `UploadPhoto { id, content_type, size_bytes }`, `NormalizeOriginal { id, new_size, rotated, version }`, `GenerateVariant { id, variant, size_bytes, version }`, `MarkVariantFailed { id, variant, error, version }`, `DeletePhoto { id, version }`; derive `serde::Deserialize` + `utoipa::ToSchema`; implement `kameo_es::CommandName` for each.
- [ ] 2.4 Implement `aggregate.rs`: `PhotoAggregate { id, content_type, size_bytes, variants: Vec<PhotoVariantRecord>, exif_stripped_at, deleted_at, version }`; `Entity` impl with `category = "photo"`; `Apply` impl for all five events; `Command` impls with version-mismatch guards; `DeletePhoto` is terminal (rejects mutations after `PhotoDeleted`).
- [ ] 2.5 Implement `error.rs`: `PhotoError` (`ValidationError`, `NotFound`, `AlreadyDeleted`, `VersionMismatch`); wire `From<PhotoError> for DomainError` into `crates/core/src/error.rs`.
- [ ] 2.6 Implement `views.rs`: `PhotoView { id, content_type, size_bytes, variants: Vec<PhotoVariantView>, exif_stripped_at, version }`, `PhotoVariantView { kind: PhotoVariant, status: VariantStatus, size_bytes }` (+ `ToSchema`).
- [ ] 2.7 Implement `ports.rs`: `PhotoStorage` trait (`store`, `fetch`, `delete_all`, `list` — type-safe over `PhotoId` + `PhotoVariant`); `PhotoCommands` write port (`upload`, `normalize_original`, `generate_variant`, `mark_variant_failed`, `delete`); `PhotoRepository` read port (`find_by_id`, `list_known_ids`, `count_links` for the refcount check).
- [ ] 2.8 Define `PhotoMetadata { content_type, size_bytes }`, `PhotoBytes { bytes, content_type, size_bytes, etag }`, `PhotoGcConfig { enabled, interval_secs, max_age_secs, batch_size, dry_run }` in `views.rs` or a dedicated `types.rs`.
- [ ] 2.9 Write `aggregate_test.rs`: upload emits `PhotoUploaded` with initial variant statuses `Pending`; `NormalizeOriginal`/`GenerateVariant`/`MarkVariantFailed` transitions; `DeletePhoto` is terminal and rejects subsequent mutations; version-mismatch rejection on every command; refcount-deletion invariant is *not* on the aggregate (lives in the saga; tested in integration).

## 3. CostumePhotoView enrichment (core)

- [ ] 3.1 Extend `crates/core/src/costume/views.rs::CostumePhotoView` from `{ id }` to `{ id, content_type: String, size_bytes: u64, variants: Vec<PhotoVariantView> }`; add `PhotoVariantView` reference (re-export from `photo::views`).
- [ ] 3.2 Verify `PhotoLinked` / `PhotoUnlinked` events and `LinkPhoto` / `UnlinkPhoto` commands are structurally unchanged (additive consumer-side only).

## 4. Authorisation v1 (core)

- [ ] 4.1 Add `SeasonPhotoAccessPolicy` to `crates/core/src/membership/policy.rs` as an impl of `AuthorizationPolicy` that derives photo access via the SQL JOIN on `projection_membership` + `projection_block` (user_id, season_id, role IN costume-dept, state = active).
- [ ] 4.2 Document the between-blocks-gap limitation and the v2 `SeasonCrew` evolution path as a comment on `SeasonPhotoAccessPolicy`, mirroring the design.md section.

## 5. Projection migration (infra)

- [ ] 5.1 Author `crates/infra/migrations/<ts>_photo_tables.up.sql` (+ `.down.sql`): create `projection_photo` (photo_id UUID PK, content_type TEXT, size_bytes BIGINT, created_at TIMESTAMPTZ, updated_at TIMESTAMPTZ); `projection_photo_variant` (photo_id UUID, variant TEXT, status TEXT, size_bytes BIGINT, created_at TIMESTAMPTZ, PRIMARY KEY (photo_id, variant)); `projection_photo_gc_run` (run_id UUID PK, started_at TIMESTAMPTZ, finished_at TIMESTAMPTZ, scanned BIGINT, orphans_found BIGINT, orphans_deleted BIGINT, dry_run BOOLEAN). `projection_costume_photo` is reused unchanged.

## 6. PhotoStorage adapter (infra)

- [ ] 6.1 Add dependencies to `crates/infra/Cargo.toml`: `opendal` (features `services-s3`), `image` (features `jpeg`, `png`, `webp`), `kamadak-exif`.
- [ ] 6.2 Implement `crates/infra/src/photo/storage.rs::OpenDalPhotoStorage` configured via OpenDAL S3 service against Garage; key layout `{photo_id}/{variant}` (adapter-internal). Implement `store`, `fetch`, `delete_all`, `list` against the `PhotoStorage` port.
- [ ] 6.3 Add `crates/infra/src/photo/mod.rs` and wire `pub mod photo;` into `crates/infra/src/lib.rs`.

## 7. Photo projector + repository (infra)

- [ ] 7.1 Implement `crates/infra/src/photo/projector.rs::PhotoProjector` implementing `EntityEventHandler<PhotoAggregate, Transaction<Postgres>>`: on `PhotoUploaded` insert `projection_photo` + `projection_photo_variant` (original=pending, thumb=pending, medium=pending); on `OriginalNormalized` update original variant + set `exif_stripped_at`; on `VariantGenerated` update the variant row to `Ready` + new size; on `VariantFailed` update to `Failed` + error; on `PhotoDeleted` delete `projection_photo` + `projection_photo_variant` rows. Exhaustive `match`.
- [ ] 7.2 Implement `crates/infra/src/photo/commands.rs::PhotoCommandsImpl` (kameo_es `CommandService` dispatch — mirror `CostumeCommandsImpl`).
- [ ] 7.3 Implement `crates/infra/src/photo/repository.rs::PhotoRepositoryImpl` (sqlx): `find_by_id` (assembles `PhotoView` with variants), `list_known_ids` (for GC), `count_links(photo_id)` (COUNT on `projection_costume_photo`).
- [ ] 7.4 Extend the existing `CostumeProjector` (or `CostumeRepository::enrich`) to populate `CostumePhotoView.content_type`, `size_bytes`, and `variants` by joining `projection_photo` + `projection_photo_variant` when assembling `CostumeView`.

## 8. Sagas (infra)

- [ ] 8.1 Implement `crates/infra/src/photo/sagas/thumbnail.rs::PhotoThumbnailSaga` subscribing to the `photo` stream's `PhotoUploaded` events: fetch original bytes from Garage via `PhotoStorage::fetch`; decode with `image` + read EXIF orientation with `kamadak-exif`; apply rotation; re-encode original upright EXIF-stripped (quality ~95) and overwrite in Garage via `PhotoStorage::store(id, Original, ...)`; dispatch `NormalizeOriginal`; generate `Thumb` (~200×200, JPEG q80) and `Medium` (~800×800, JPEG q85); dispatch `GenerateVariant` for each; on error dispatch `MarkVariantFailed`.
- [ ] 8.2 Implement `crates/infra/src/photo/sagas/deletion.rs::PhotoDeletionSaga` subscribing to the `costume` stream's `PhotoUnlinked` events: `PhotoRepository::count_links(photo_id)`; if 0 dispatch `DeletePhoto` on the `Photo` aggregate; else no-op.
- [ ] 8.3 Implement `crates/infra/src/photo/sagas/bytes_cleanup.rs::PhotoBytesCleanupSaga` subscribing to the `photo` stream's `PhotoDeleted` events: `PhotoStorage::delete_all(photo_id)` (idempotent under redelivery).
- [ ] 8.4 Wire the three sagas as spawned subscribers in `main.rs` alongside the existing `SeasonSeedingSaga`.

## 9. GC sweep task (infra)

- [ ] 9.1 Implement `crates/infra/src/photo/gc.rs::PhotoGcSweepTask` (pure logic, parameterised by `PhotoGcConfig`): list Garage objects via `PhotoStorage::list`; list known photo_ids via `PhotoRepository::list_known_ids`; compute orphans; delete those older than `max_age_secs` via `PhotoStorage::delete_all` (unless `dry_run`); acquire Postgres advisory lock at start (`pg_try_advisory_lock`); write `projection_photo_gc_run` history row at completion.
- [ ] 9.2 Implement `crates/infra/src/photo/gc.rs::PhotoGcScheduler` as a background tokio task spawned from `main.rs`: reads config from env (`PHOTO_GC_ENABLED`, `PHOTO_GC_INTERVAL_SECS`, `PHOTO_GC_MAX_AGE_SECS`, `PHOTO_GC_BATCH_SIZE`, `PHOTO_GC_DRY_RUN`) at startup; loops on the interval; single-task (no `tokio::spawn` inside the sweep loop).
- [ ] 9.3 Document the env vars and the `PHOTO_GC_DRY_RUN=true` first-rollout recommendation in `backend/AGENTS.md`.

## 10. API surface (api)

- [ ] 10.1 Extend `crates/api/src/state.rs::Ports` + `ProductionPorts` with `PhotoStorage`, `PhotoCommands`, `PhotoRepo`, and `SeasonPhotoAccessPolicy` fields; add accessor methods; wire construction in `main.rs`.
- [ ] 10.2 Implement `POST /costumes/{cid}/photos` handler: validate JWT; check `SeasonPhotoAccessPolicy`; parse multipart (photo_id + bytes); validate content-type allowlist (jpeg/png/webp; reject heic/heif with 415); enforce `PHOTO_MAX_SIZE_MB` (413 on exceed); `PhotoStorage::store(id, Original, bytes, content_type)`; on store failure return 500; dispatch `UploadPhoto` then `LinkPhoto`; on `LinkPhoto` failure call `PhotoStorage::delete_all` (compensating delete); return 201 with photo_id + variant statuses.
- [ ] 10.3 Implement `GET /costumes/{cid}/photos/{pid}/bytes?variant={original|thumb|medium}` handler: validate JWT; check `SeasonPhotoAccessPolicy`; `PhotoStorage::fetch(pid, variant)`; stream bytes with `Content-Type`, `Content-Length`, `ETag`, `Cache-Control: private, max-age=300`; return 404 on `NotFound`.
- [ ] 10.4 Implement `DELETE /costumes/{cid}/photos/{pid}` handler: validate JWT; check `SeasonPhotoAccessPolicy`; dispatch `UnlinkPhoto` (the deletion saga handles refcount + bytes cleanup); return 204.
- [ ] 10.5 Extend OpenAPI `#[openapi]` declaration in `crates/api/src/lib.rs` with the three new paths and the `PhotoView`, `PhotoVariantView`, enriched `CostumePhotoView` schemas.

## 11. Docker runtime (infra)

- [ ] 11.1 Add `garage` service to `docker-compose.dev.yml`: image `dxflrs/garage:v1.0.1`; no host `ports:` mapping (internal-only); persistent named volume `garage_dev_data`; healthcheck against the admin ping endpoint.
- [ ] 11.2 Add `garage` service to `docker-compose.prod.yml` (same image, internal-only, persistent volume, healthcheck).
- [ ] 11.3 Add a `garage` init step (one-shot container or documented script) that creates the layout, the `costume-photos` bucket, and an access key, on first boot.
- [ ] 11.4 Document in `backend/AGENTS.md` and the repo README the new env vars (`S3_ENDPOINT`, `S3_ACCESS_KEY`, `S3_SECRET_KEY`, `S3_BUCKET`, `PHOTO_MAX_SIZE_MB`, the `PHOTO_GC_*` set) and the boot sequence (Garage must be up + provisioned before the API).

## 12. Integration tests (integration-tests)

- [ ] 12.1 Add a Garage testcontainer helper to `crates/integration-tests` (per ADR-014 one-harness rule): start `dxflrs/garage:v1.0.1`; wait for admin healthcheck; create layout + access key + `costume-photos` bucket; return the S3 endpoint URL + credentials.
- [ ] 12.2 Add Tier-3 test: spin up Postgres + Garage; exercise `OpenDalPhotoStorage::store` / `fetch` / `delete_all` / `store_variant` / `list`; verify HEAD, overwrite-by-default, listing behaviour against real Garage S3 semantics.
- [ ] 12.3 Add Tier-4 test (PG + SierraDB + Garage): spawn `PhotoProjector` + the three sagas; `POST /costumes/{cid}/photos` (proxy upload); poll `projection_photo_variant` until all three variants `Ready`; assert thumb dimensions (decode + check ≤200×200); assert original has no EXIF (decode with `kamadak-exif`, expect `None`); proxy download bytes match what was stored; `DELETE /costumes/{cid}/photos/{pid}`; poll until Garage objects gone; assert `projection_photo` rows removed.
- [ ] 12.4 Add Tier-4 N:M variant: link photo P to costumes A and B; unlink from A — assert bytes survive; unlink from B — assert bytes gone from Garage.
- [ ] 12.5 Add Tier-4 GC variant: write orphan bytes directly into Garage without dispatching `UploadPhoto` (use `PhotoStorage::store`); run the GC sweep; assert orphans older than the age gate are deleted, in-flight (younger) orphans are preserved; assert `projection_photo_gc_run` row recorded.
- [ ] 12.6 Confirm the new Tier-3/Tier-4 tests are excluded from `cargo-mutants` (`.cargo/mutants.toml`).

## 13. Architecture tests + lint

- [ ] 13.1 Run `cargo test -p architecture_tests` to confirm `crates/core` does not depend on `opendal`/`image`/`kamadak-exif` (those live in `crates/infra`).
- [ ] 13.2 Run `cargo deny check bans` to confirm the new dependency additions obey the boundary rules (ADR-017).
- [ ] 13.3 Run `gitleaks` on the new code to confirm no hardcoded Garage credentials (env-only).
- [ ] 13.4 Run `cargo mutants --in-diff` on the changed `crates/core` surface (aggregate tests) to confirm no mutants survive in the photo lifecycle logic.

## 14. Documentation

- [ ] 14.1 Update `backend/AGENTS.md` "Architecture & Core Patterns": document the `photo` bounded context, the `PhotoStorage` port as a non-CRQS-split CRUD port, and the three sagas (`PhotoThumbnailSaga`, `PhotoDeletionSaga`, `PhotoBytesCleanupSaga`).
- [ ] 14.2 Update `docs/architecture/adrs/README.md` active-ADRs table to include ADR-019.
- [ ] 14.3 Cross-link ADR-019 from ADR-009 (note Phase 1 `fs` is superseded/skipped) and from ADR-002 (photo lifecycle is event-sourced; bytes are a side-effect).
