<!--
  Authors: Tobias Rademacher (@tradem) — domain stakeholder & spec author
           glm-5.2 (neuralwatt) — coding agent / co-author
  Note: OpenSpec does not natively track authorship; this header is a manual addition.
-->

## MODIFIED Requirements

### Requirement: Photo aggregate is the single source of truth for photo lifecycle
The system SHALL model photo lifecycle (existence, content-type, size, variant generation status, EXIF-stripped flag, deletion) as a `Photo` aggregate (category `"photo"`) tracked in SierraDB. The `Photo` aggregate SHALL additionally carry a `binding: PhotoBinding` describing what the photo is attached to (`Costume { costume_id }` or `Continuity { scene_shoot_id, costume_id: Option<CostumeId> }`); see photo-continuity-binding capability for binding semantics. The `PhotoStorage` port (CRUD on bytes via OpenDAL/S3 against Garage) SHALL be a side-effect store: events say bytes should exist; the projector and sagas enforce that. Every projection table for photos (`projection_photo`, `projection_photo_variant`, `projection_photo_gc_run`, `projection_costume_photo`, and the new `projection_continuity_photo`) SHALL be replay-derived from SierraDB events, so that a Postgres loss is recoverable by replaying events without a bespoke Garage scan.

#### Scenario: Postgres loss is recoverable by event replay
- **WHEN** the Postgres read-model database is lost and SierraDB + Garage are intact
- **THEN** running `sqlx::migrate!` and booting the `PhotoProjector` (and the existing `CostumeProjector` and `SceneShootProjector`) repopulates `projection_photo`, `projection_photo_variant`, `projection_costume_photo`, and `projection_continuity_photo` by replaying events from SierraDB
- **AND** no bespoke S3-aware reconciliation scan is required

#### Scenario: Garage loss is detectable
- **WHEN** Garage bytes are lost but Postgres + SierraDB are intact
- **THEN** `projection_photo` rows still exist (event-sourced)
- **AND** a `PhotoStorage::fetch` for a photo with no Garage object returns a `NotFound` error
- **AND** the read model honestly reports the photo as existing while fetches fail (404 on the download endpoint)

#### Scenario: Photo aggregate lifecycle events
- **WHEN** a photo is uploaded, normalised, has variants generated, or is deleted
- **THEN** the corresponding `Photo` aggregate events (`PhotoUploaded` with `binding`, `OriginalNormalized`, `VariantGenerated`, `VariantFailed`, `PhotoDeleted`) are emitted to SierraDB
- **AND** each event is projected by the `PhotoProjector` into `projection_photo` / `projection_photo_variant`
