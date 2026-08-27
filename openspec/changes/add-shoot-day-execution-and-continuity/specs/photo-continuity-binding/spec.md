<!--
  Authors: Tobias Rademacher (@tradem) — domain stakeholder & spec author
           glm-5.2 (neuralwatt) — coding agent / co-author
  Note: OpenSpec does not natively track authorship; this header is a manual addition.
-->

## ADDED Requirements

### Requirement: Photo aggregate carries a PhotoBinding discriminator

The `Photo` aggregate SHALL carry a `binding: PhotoBinding` field with variants:
- `Costume { costume_id: CostumeId }` — Anprobe / planning photo (taken before the shoot).
- `Continuity { scene_shoot_id: SceneShootId, costume_id: Option<CostumeId> }` — continuity photo taken during the shoot; `costume_id` is `Option` so prop-only continuity shots are permitted (the edge case), while the costume-bound case is the normal one.

The `binding` SHALL be carried on the `PhotoUploaded` event and on `PhotoView`. Event deserialisation of pre-binding historical `PhotoUploaded` events SHALL default `binding` to `Costume` (since all pre-existing photos are costume photos).

#### Scenario: Costume binding on upload
- **WHEN** a photo is uploaded for a costume
- **THEN** the emitted `PhotoUploaded` event SHALL carry `binding = Costume { costume_id }`

#### Scenario: Continuity binding with costume
- **WHEN** a continuity photo is uploaded for a `SceneShoot` and a costume is supplied
- **THEN** the emitted `PhotoUploaded` event SHALL carry `binding = Continuity { scene_shoot_id, costume_id: Some(_) }`

#### Scenario: Continuity binding without costume (prop photo)
- **WHEN** a continuity photo is uploaded for a `SceneShoot` with no costume
- **THEN** the emitted `PhotoUploaded` event SHALL carry `binding = Continuity { scene_shoot_id, costume_id: None }`

#### Scenario: Legacy events default to Costume binding
- **WHEN** a historical `PhotoUploaded` event without a `binding` field is deserialised
- **THEN** the `binding` SHALL be treated as `Costume { costume_id }` derived from the linked costume

### Requirement: Continuity photo upload endpoint

The system SHALL accept continuity photo uploads via `POST /shooting-days/{day_id}/scenes/{scene_id}/continuity-photos` (resolving the `SceneShoot` pair). The API SHALL receive the bytes (multipart), validate content-type and size (reusing the photo-storage allowlist and cap), store them in Garage via `PhotoStorage::store`, dispatch `UploadPhoto` (with `PhotoBinding::Continuity`) on the `Photo` aggregate, and dispatch `LinkContinuityPhoto` on the `SceneShoot` aggregate.

Compensating `PhotoStorage::delete_all` SHALL be invoked if the `LinkContinuityPhoto` step fails (matching the costume upload compensating-delete pattern).

#### Scenario: Successful continuity upload
- **WHEN** an authorised user uploads a valid JPEG to the continuity endpoint
- **THEN** the API stores bytes in Garage, dispatches `UploadPhoto` with `binding = Continuity`, dispatches `LinkContinuityPhoto` on the `SceneShoot`, and returns `201` with the `photo_id` and variant statuses

#### Scenario: Compensating delete on link failure
- **WHEN** `PhotoStorage::store` succeeds but `LinkContinuityPhoto` fails
- **THEN** the API calls `PhotoStorage::delete_all(photo_id)` and no `PhotoUploaded` event is emitted

### Requirement: Continuity photo download and delete endpoints

The system SHALL serve continuity photo bytes via `GET /shooting-days/{day_id}/scenes/{scene_id}/continuity-photos/{photo_id}/bytes?variant=...` and SHALL delete via `DELETE /shooting-days/{day_id}/scenes/{scene_id}/continuity-photos/{photo_id}`. The download SHALL enforce authorisation on every request.

#### Scenario: Authorised continuity download
- **WHEN** an authorised user GETs the bytes endpoint
- **THEN** the API validates the JWT, checks season/block membership, streams bytes with appropriate headers

#### Scenario: Delete unlinks then dispatches DeletePhoto when refcount zero
- **WHEN** a continuity photo is deleted
- **THEN** the API dispatches `UnlinkContinuityPhoto` on the `SceneShoot`; the continuity deletion saga SHALL then refcount the photo and dispatch `DeletePhoto` when zero references remain

### Requirement: Continuity photo handlers enforce handler-internal authorization

Because continuity photo routes are gated only by `Requirement::Authenticated` (they live under a route not covered by block-membership middleware), each continuity photo handler (`upload`, `get_bytes`, `delete`) SHALL call the relevant `AuthorizationPolicy` method (e.g. `has_active_costume_role_in_season` or block-membership equivalent) inside the handler body and return `403` on denial. Each such handler SHALL be annotated with a `// AUTHZ-GATE:` comment marking the check, matching the existing photo handler pattern.

#### Scenario: Non-member continuity upload denied
- **WHEN** an authenticated but non-authorised user POSTs a continuity photo
- **THEN** the handler's internal AUTHZ check SHALL return `403` before any bytes are stored

### Requirement: photo deletion saga branches on binding kind

The `PhotoDeletionSaga` (and the existing `PhotoBytesCleanupSaga`) SHALL handle both binding kinds:
- On `PhotoUnlinked` from the `costume` stream → refcount via `projection_costume_photo` (existing behaviour).
- On `ContinuityPhotoUnlinked` from a `SceneShoot` stream → refcount via a new `projection_continuity_photo` (or a unified binding-aware refcount). When the refcount reaches zero for that `photo_id` across all bindings, dispatch `DeletePhoto` on the `Photo` aggregate.

#### Scenario: Continuity unlink with zero refs deletes photo
- **WHEN** a `ContinuityPhotoUnlinked` event fires and the photo has no remaining references in `projection_costume_photo` NOR `projection_continuity_photo`
- **THEN** the saga dispatches `DeletePhoto`

#### Scenario: Continuity unlink with remaining refs does not delete
- **WHEN** a `ContinuityPhotoUnlinked` event fires but the photo is still referenced by another `SceneShoot` or costume
- **THEN** the saga SHALL NOT dispatch `DeletePhoto`

### Requirement: projection_continuity_photo

A `projection_continuity_photo` table SHALL be replay-derived and SHALL contain `photo_id`, `scene_shoot_id`, `costume_id NULL`, with FKs to `projection_photo` and `projection_scene_shoot`. It SHALL be populated by the photo projector when it encounters a `PhotoUploaded` with `Continuity` binding (and by the `SceneShoot` projector on `ContinuityPhotoLinked`/`Unlinked`).

#### Scenario: Table is replay-derivable
- **WHEN** Postgres is lost and SierraDB is intact
- **THEN** replaying both the `Photo` and `SceneShoot` event streams repopulates `projection_continuity_photo`
