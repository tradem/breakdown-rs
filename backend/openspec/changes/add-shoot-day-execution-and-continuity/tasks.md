<!--
  Authors: Tobias Rademacher (@tradem) — domain stakeholder & spec author
           glm-5.2 (neuralwatt) — coding agent / co-author
  Note: OpenSpec does not natively track authorship; this header is a manual addition.
-->

## 1. Shared types & scene script_day (core, additive)

- [x] 1.1 Add `SceneShootId` newtype to `crates/core/src/shared`
- [x] 1.2 Add `SceneShootStatus` enum (`Planned | Scheduled | InProgress | Shot | Skipped`) with serde/ToSchema
- [x] 1.3 Add `script_day: Option<String>` to `SceneDetails` (core); update `SceneDetailsUpdated` test fixtures; existing event carries it
- [x] 1.4 Add unit tests: `SceneDetails` round-trips `script_day`

## 2. SceneShoot aggregate (core)

- [x] 2.1 Create `crates/core/src/scene_shoot/` module (mod, aggregate, events, commands, error, ports, views)
- [x] 2.2 Define `SceneShootEvent` variants: `SceneShootPlanned`, `SceneShootReplanned`, `SceneShootStarted`, `SceneShootActualOrderSet`, `SceneShootFinished`, `SceneShootSkipped`, `ShootDayNoteAdded/Updated/Removed`, `ContinuityPhotoLinked/Unlinked`
- [x] 2.3 Define commands: `PlanSceneShoot`, `ReplanSceneShoot`, `StartSceneShoot`, `SetActualOrder`, `FinishSceneShoot`, `SkipSceneShoot`, `AddSceneShootNote`, `UpdateSceneShootNote`, `RemoveSceneShootNote`, `LinkContinuityPhoto`, `UnlinkContinuityPhoto`
- [x] 2.4 Define `SceneShootAggregate` state with the two orderings, status, times, notes, continuity_photos, version
- [x] 2.5 Implement `Apply` for all events
- [x] 2.6 Implement `Command` handlers with invariants: pair-uniqueness on plan, `PlannedOrderFrozen` when `actual_order`/`start_dt` set, note-not-found, already-linked
- [x] 2.7 Define `SceneShootCommands` + `SceneShootRepository` port traits
- [x] 2.8 Define `SceneShootView` read DTO
- [x] 2.9 Unit tests: lifecycle transitions, passive freezing, note mutations, duplicate-plan rejection

## 3. ShootingDay lifecycle (core)

- [x] 3.1 Add `wrapped_at: Option<DateTime<Utc>>` to `ShootingDayAggregate` state
- [x] 3.2 Add `ShootingDayWrapped` event variant + `WrapShootingDay` command
- [x] 3.3 Implement idempotent `WrapShootingDay` handler
- [x] 3.4 Unit tests: wrap, idempotent re-wrap, wrap-does-not-block-archive

## 4. Photo binding (core)

- [x] 4.1 Define `PhotoBinding` enum (`Costume { costume_id }` | `Continuity { scene_shoot_id, costume_id: Option }`)
- [x] 4.2 Add `binding` to `PhotoAggregate` state and to `PhotoUploaded` event
- [x] 4.3 Add backward-compat deserialisation default (`Costume`) for pre-binding historical `PhotoUploaded`
- [x] 4.4 Update `UploadPhoto` command to accept `binding`
- [x] 4.5 Expose `binding` on `PhotoView`
- [x] 4.6 Unit tests: both bindings persisted; legacy event deserialises as Costume

## 5. Infra — migrations

- [x] 5.1 `projection_scene_shoot` migration (unique on scene_id+shooting_day_id; planned_order, actual_order NULL, start_dt, end_dt, status enum, notes JSONB, continuity_photo_ids, version, updated_at)
- [x] 5.2 `projection_continuity_photo` migration (photo_id, scene_shoot_id, costume_id NULL, FKs)
- [x] 5.3 Add `wrapped_at` column to `projection_shooting_day`
- [x] 5.4 Add `script_day TEXT NULL` to `projection_scene`
- [x] 5.5 Backfill SQL documented in migration as comment
- [x] 5.6 Tag existing photos as Costume binding — handled by projector via serde(default)
- [x] 5.7 Down-migrations for all of the above

## 6. Infra — projectors

- [x] 6.1 `SceneShootProjector` handling all `SceneShootEvent` variants → `projection_scene_shoot`
- [x] 6.2 Extend `ShootingDayProjector` for `ShootingDayWrapped`
- [x] 6.3 Extend `SceneProjector` for `script_day` (already handled in existing code)
- [x] 6.4 Extend `PhotoProjector` to write `projection_continuity_photo` on Continuity upload
- [ ] 6.5 Projector idempotency tests (redelivery)

## 7. Infra — ports, sagas, reports

- [x] 7.1 `SqlxSceneShootCommands` adapter (write-side command dispatch)
- [x] 7.2 `SqlxSceneShootRepository` adapter: find_by_id, list_by_shooting_day, find_by_scene_and_day, list_by_scene
- [x] 7.3 Add `ContinuityDeletionSaga` for continuity photo refcount + deletion
- [x] 7.4 `ShootingDayRepository` gains `wrapped_at` in view
- [x] 7.5 Report queries: Dispo (`ORDER BY planned_order`), Shoot Day (`ORDER BY actual_order NULLS LAST`), Soll-Ist diff (moved/missing/skipped/reshot flags + `final` from wrapped_at)
- [x] 7.6 Repository tests (Tier-3) for each query

## 8. API

- [x] 8.1 OpenAPI spec updates for all new endpoints + types
- [x] 8.2 `POST /shooting-days/{id}/scenes/{scene_id}/scene-shoots` (plan) + PATCH reorder (replan)
- [x] 8.3 Execution endpoints: `POST .../start`, `.../actual-order`, `.../finish`, `.../skip`
- [x] 8.4 Notes endpoints: `POST/PUT/DELETE .../notes`
- [x] 8.5 Continuity photo endpoints: `POST/GET/DELETE ...` with `// AUTHZ-GATE:` comments + policy checks
- [x] 8.6 Report endpoints: `GET /shooting-days/{id}/report/{dispo|shoot-day|soll-ist}`
- [x] 8.7 `WrapShootingDay` endpoint: `POST /shooting-days/{id}/wrap`
- [x] 8.8 `SceneDetails` API type gains `script_day`; create/update accept it
- [x] 8.9 Wire composition root (`main.rs`) for new actor + projector spawns

## 9. Tests

- [ ] 9.1 Tier-4 integration: plan → start → finish round-trip reads from `projection_scene_shoot`
- [ ] 9.2 Tier-4: continuity photo upload → variant generation → bytes in Garage → projection rows
- [ ] 9.3 Tier-4: continuity delete → refcount → `DeletePhoto` only at zero → bytes cleaned
- [ ] 9.4 Tier-4: `ShootingDayWrapped` flips report `final` flag
- [ ] 9.5 Tier-4: passive `planned_order` freeze enforced after `StartSceneShoot`
- [ ] 9.6 Tier-4: reshoot = new pair (no amendment to prior Shot stream)
- [ ] 9.7 Mutation tests for new aggregate invariants (frozen-order, note mutation, pair-uniqueness)

## 10. Docs & guardrails

- [ ] 10.1 Update AGENTS.md SceneShoot/ShootingDay section + photo AUTHZ note for continuity handlers
- [ ] 10.2 Verify no-string-interpolation-sql CI passes (static literals only) for new queries
- [ ] 10.3 `cargo deny check bans` + architecture test (`core` unaffected by infra deps)
- [ ] 10.4 README/env doc: no new env vars (reuses S3_*, PHOTO_MAX_SIZE_MB)
