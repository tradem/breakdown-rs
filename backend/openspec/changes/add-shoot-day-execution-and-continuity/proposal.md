<!--
  Authors: Tobias Rademacher (@tradem) — domain stakeholder & spec author
           glm-5.2 (neuralwatt) — coding agent / co-author
  Note: OpenSpec does not natively track authorship; this header is a manual addition.
-->

## Why

The application can plan a shoot day (the "Dispo" — the costume department's preparation plan derived from the assistant director's shooting order), but it cannot track a shoot day *while it is being executed*. Continuity — documenting the actual state of costumes, props, and scenes across non-chronological shooting — is currently impossible. Repeated takes, on-the-fly reordering, Anschluss (continuity) photos, and per-scene notes have no home in the domain, and the costume department cannot later compare *what was planned* against *what actually happened*.

## What Changes

- Introduce a new **`SceneShoot`** aggregate: one stream per `(Scene, ShootingDay)` pair, carrying both the **planned** order (Dispo/"Soll") and the **actual** order/execution data ("Ist"). Emitted by the existing Scene⇄ShootingDay join being upgraded.
- Add a **shoot-status lifecycle** on `SceneShoot` (`Planned → Scheduled → InProgress → Shot | Skipped`) with passive `planned_order` freezing: once a scene shoot gains execution data (`start_dt` or `actual_order`), its `planned_order` becomes immutable — no client "release" button required.
- Add **mutable, audited notes** on `SceneShoot` (`ShootDayNoteAdded` / `ShootDayNoteUpdated` / `ShootDayNoteRemoved` events); full history comes for free from the event store.
- Add an explicit **`ShootingDayWrapped`** event to the `ShootingDay` aggregate marking day completion; it freezes the "Ist" side and makes the Soll-Ist comparison authoritative.
- Extend the `Photo` aggregate with a **`PhotoBinding`** discriminator (`Costume { costume_id }` | `Continuity { scene_shoot_id, costume_id: Option<...> }`) so continuity photos taken during the shoot reuse the existing photo storage/variant/deletion machinery, while optional `costume_id` covers the prop-only edge case.
- Add a new **`scene-shoot-reports`** read surface producing three reports from one projection: ① Dispo (planned order), ② Shoot Day (actual order + times + notes + continuity photos), ③ Soll-Ist-Vergleich (planned-vs-actual diff: moved, skipped, missing, reshot).
- Add a **`script_day: Option<String>`** field to `SceneDetails` (free-form "1. Spieltag" / "Spieltag 2") as a script-chronology search index on the Scene — distinct from the calendar `ShootingDay.date`.

## Capabilities

### New Capabilities
- `scene-shoot`: The `SceneShoot` association aggregate — planned + actual ordering, shoot status lifecycle, mutable audited notes, per-pair continuity-photo links, and the passive `planned_order` immutability invariant.
- `scene-shoot-reports`: The three read-side reports (Dispo, Shoot Day, Soll-Ist-Vergleich) composed from the `SceneShoot` projection.
- `shooting-day-lifecycle`: The `ShootingDayWrapped` event and the day-completion → report-finalisation contract on the `ShootingDay` aggregate.
- `photo-continuity-binding`: Extension of the `Photo` lifecycle to continuity photos via `PhotoBinding`, including the continuity deletion-saga refcount path.

### Modified Capabilities
- `scene-scoping`: `SceneDetails` gains an optional `script_day: Option<String>` field (script-chronology search index, distinct from calendar `ShootingDay.date`); `SceneDetailsUpdated` already covers the update path.
- `photo-storage`: The `Photo` aggregate gains a `binding: PhotoBinding` discriminator; routing of deletion/refcount sagas branches on binding kind.

## Impact

- **Code — `crates/core`**:
  - New `scene_shoot` module (aggregate, events, commands, ports, views, error).
  - `shooting_day` module: new `ShootingDayWrapped` event + `WrapShootingDay` command + aggregate field.
  - `photo` module: `PhotoBinding` enum added to aggregate state and `PhotoUploaded`/created event; `PhotoView` exposes binding.
  - `scene::events::SceneDetails`: add `script_day: Option<String>` (additive; existing `SceneDetailsUpdated` carries it).
- **Code — `crates/infra`**:
  - New `projection_scene_shoot` migration + projector (replacing/augmenting today's thin `projection_scene_shooting_day` join; migration backfills existing rows as `Planned`).
  - New `projection_continuity_photo` (or refcount view) for the continuity deletion saga.
  - `shooting_day` projector gains `ShootingDayWrapped` handling.
  - `photo` deletion saga branches on binding kind (costume refcount vs continuity refcount).
  - Three report query paths (read port implementations) against `projection_scene_shoot`.
- **Code — `crates/api`**:
  - New routes under `/shooting-days/{id}/scenes/{scene_id}` (and `/scene-shoots/{id}`) for plan/execution/notes.
  - Continuity photo upload route `POST /shooting-days/{id}/scenes/{scene_id}/continuity-photos` (+ GET/DELETE), gated by handler-internal AUTHZ (matching the `AUTHZ-GATE:` pattern).
  - Report endpoints for Dispo / Shoot Day / Soll-Ist-Vergleich.
  - `SceneDetails` API type gains optional `script_day`.
- **Migrations**: `projection_scene_shoot` (with `planned_order`, `actual_order`, `start_dt`, `end_dt`, `status`, `notes JSONB`, `version`), `projection_continuity_photo`, `shooting_day` gains `wrapped_at`/status column, `SceneDetails` projection gains `script_day`.
- **Security**: continuity photo handlers must follow the handler-internal AUTHZ pattern (`AUTHZ-GATE:` comments + `AuthorizationPolicy` call) since photo routes are `Authenticated`-only.
- **No breaking API changes** — all additions are additive; existing `Scene ⇄ ShootingDay` join behaviour is migrated, not removed.
