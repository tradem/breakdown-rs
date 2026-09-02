<!--
  Authors: Tobias Rademacher (@tradem) — domain stakeholder & spec author
           glm-5.2 (neuralwatt) — coding agent / co-author
  Note: OpenSpec does not natively track authorship; this header is a manual addition.
-->

## Context

`breakdown-rs` models a four-level production hierarchy `Series → Season → Block → Episode → {Scene, ShootingDay}`. Today the `ShootingDay` aggregate is a purely *planning* object (id, episode_id, label, order_key, optional calendar `date`, source, archived). Scenes reference ShootingDays via a thin many-to-many kept on the Scene side (`SceneAggregate.shooting_day_ids: Vec<ShootingDayId>`) and mirrored in `projection_scene_shooting_day` — that join carries no ordering, no execution data, no notes.

The costume department needs more than planning:

1. A **Dispo** (the costume department's preparation plan, derived from the assistant director's shooting order — the *planned* sequence in which scenes will be shot on a given day).
2. **Shoot-day execution tracking**: while a day is being shot, the crew reorders scenes, records start/end times, adds Anschluss (continuity) notes, and takes continuity photos so that non-chronological shooting doesn't produce visible continuity errors. The script is shot out of order for logistical/economic reasons; continuity records the *actual state* so later-within-script scenes match earlier-taken material.
3. **Three reports**: ① Dispo (planned), ② Shoot Day (actual), ③ Soll-Ist-Vergleich (planned-vs-actual diff).

Continuity photos are distinct from the existing costume (Anprobe) photos: Anprobe photos are taken *before* the shoot for planning ("this is how it should look"); continuity photos are taken *during* the shoot to record reality ("this is how it was done"). A scene may be reshot on a later day if conditions require it — each such pair `(Scene, ShootingDay)` is a separate continuity record.

The `photo` bounded context already implements upload → normalisation → variant generation (Thumb/Medium) → deletion, with Garage (S3 via OpenDAL) for bytes and a `PhotoDeletionSaga` that refcounts via `projection_costume_photo`.

## Goals / Non-Goals

**Goals:**
- Model the `(Scene, ShootingDay)` association as a first-class aggregate (`SceneShoot`) carrying both planned and actual state, with audited mutable notes.
- Reuse the existing `Photo` machinery for continuity photos by adding a `PhotoBinding` discriminator, without duplicating storage/variant/saga code.
- Provide a passive, crew-free `planned_order` immutability rule (frozen on first execution data) and an explicit `ShootingDayWrapped` event for report finalisation.
- Produce three read-side reports from a single projection (no separate write aggregates for reports).
- Add `script_day: Option<String>` to `SceneDetails` as a script-chronology search index, distinct from the calendar `ShootingDay.date`.

**Non-Goals:**
- AI call-sheet extraction for `SceneShoot` planning (the `ShootingDaySource::AiExtracted` seam already reserves a shape; `SceneShoot.source` may mirror it later).
- Real-time multi-user live editing / collaborative cursors.
- An explicit client-driven "release/approve plan" button or workflow.
- A separate daily-report *write* aggregate — reports are pure reads.
- Video or audio continuity assets (photos only).
- Costumer-side scheduling optimisation algorithms.

## Decisions

### D1. `SceneShoot` is a new aggregate, category `"scene_shoot"`, one stream per `(Scene, ShootingDay)` pair

**Choice:** A dedicated association aggregate rather than extending the `Scene` or `ShootingDay` aggregate.

**Rationale:**
- The association data (two orderings, start/end times, notes, continuity photos, per-pair status) is large and lives at the intersection of two existing aggregates. Embedding it in either side would bloat that aggregate and force unrelated version bumps (reordering one day's scenes would bump the `Scene` version for *every* day referencing it).
- A reshoot of a scene on a later day is a *new* `(Scene, ShootingDay)` pair and therefore a new stream — clean continuity separation without amending a prior `Shot` record.
- The bonus is read composability: the three reports are projections off one table with two order columns.

**Alternatives considered:**
- **A. Extend `SceneAggregate.shooting_day_ids` into a `Vec<SceneShootingDayRef>`** — rejected: write side stays on `Scene` (reordering a day bumps the scene across *all* its days), and the Vec grows unbounded.
- **B. Reverse the link onto `ShootingDayAggregate`** — rejected: scene loses its own overview of which days it runs on, and it crosses the existing ownership direction.

**ID:** `SceneShootId = Uuid` (UUIDv7).

### D2. Two orderings: `planned_order` (Dispo/"Soll") and `actual_order` ("Ist"), disjoint and frozen passively

**Choice:** `planned_order: LexicalSortKey` and `actual_order: Option<LexicalSortKey>` are separate fields. `planned_order` becomes immutable per-`SceneShoot` once *either* `actual_order` or `start_dt` is first set.

**Rationale:**
- The Soll-Ist comparison needs both the original plan and the actual sequence to compute drift (moved/skipped/reshot). Overwriting `planned_order` live would erase the plan.
- A client-driven "release plan" button was explicitly rejected by the stakeholder as "the famous extra click". The passive rule — first execution datum freezes that scene's plan — is robust and crew-free: nobody has to remember to click, and the rule is locally checkable inside the aggregate without external clock state.
- Per-scene freezing (not per-day) matches reality: at a shoot, scenes ahead of the camera can still be reordered by the AD while already-shot scenes are fixed.

**Alternatives considered:**
- **Day-wide `SceneShootStarted` auto-event emitted by client on date-reach** — rejected: mixes "day live" with "camera rolls for this scene"; would set false `start_dt` for scenes shot later the same day, and would block legitimate live reordering of not-yet-shot scenes. Day-"liveness" is a read-side UI state derived from the date, not a write-side fact.

### D3. `SceneShoot` lifecycle and status

**Choice** (per-pair state):
```
Planned ──(actual data appears)──▶ InProgress ──(ShootingDayWrapped or Shot)──▶ Shot
   │                                   │
   └──skip──▶ Skipped                  └──skip──▶ Skipped
```
Reshoot ⇒ new `SceneShoot` (new day, new pair); the prior one stays `Shot`.
- `Scheduled` is the planned-only state before any execution data.
- `Shot`/`Skipped` are terminal-ish per-pair states; `ShootingDayWrapped` (on the `ShootingDay` aggregate) is the cross-cutting day-finalisation that freezes the Ist side for reports.

### D4. Notes are mutable and audited via the event stream

**Choice:** `ShootDayNoteAdded` / `ShootDayNoteUpdated` / `ShootDayNoteRemoved` events. Current note state is derived by replay; the event store *is* the audit log ("who changed what when"). Notes carry an id (UUIDv7), body, and optional author claim (from the `CurrentUser`).

**Rationale:** Continuity relies on a trustworthy record; event sourcing gives a complete chronological audit for free, so `NoteUpdated` is allowed (not append-only) — stakeholders confirmed this was intended.

### D5. `ShootingDayWrapped` event on the `ShootingDay` aggregate

**Choice:** Add a terminal `ShootingDayWrapped { id, version, wrapped_at }` event + `WrapShootingDay` command. Once wrapped, the `SceneShoot` Ist side is considered final and the Soll-Ist-Vergleich reports are authoritative.

**Rationale:** An explicit, human-fired event is more reliable than "no new events for N hours" (shoots cross midnight, days can wrap early). It is fired once per day, not per scene, so it is not the "extra click" the stakeholder objected to (that objection was to a per-scene plan-release button).

### D6. `PhotoBinding` discriminator on the `Photo` aggregate

**Choice:**
```rust
enum PhotoBinding {
    Costume { costume_id: CostumeId },                               // Anprobe / planning
    Continuity { scene_shoot_id: SceneShootId, costume_id: Option<CostumeId> },
}
```
The `Photo` aggregate gains `binding: PhotoBinding`; `PhotoUploaded`/`PhotoView` carry it. `costume_id` is `Option` so prop-only continuity shots are permitted (stakeholder confirmed this is the edge case, costume is the normal case).

**Routing:**
- Storage/variant machinery is unchanged — bytes live in Garage keyed by `PhotoId` regardless of binding.
- `PhotoDeletionSaga` branches on binding: Costume → refcount via `projection_costume_photo` (existing); Continuity → refcount via a new `projection_continuity_photo` (or a unified `projection_photo` refcount keyed on binding).
- `PhotoUnlinked` (from the `costume` stream) still triggers costume-binding deletion; a `SceneShootRemoved` / `SceneShoot` lifecycle event or explicit `UnlinkContinuityPhoto` triggers continuity-binding cleanup analogously.

**Alternatives considered:**
- **Separate `ContinuityPhoto` aggregate** — rejected: duplicates storage, variants, and saga logic; the only real difference is the binding target.
- **Keep costume-only and hang continuity off the SceneShoot as `Vec<PhotoId>` without binding** — rejected: loses the refcount/cleanup symmetry and makes the deletion saga fork-prone.

### D7. Three reports = three read paths over one projection, no write aggregates

**Choice:** `projection_scene_shoot` holds both `planned_order` and `actual_order` (+ times, notes JSONB, status, version). The reporter port exposes:
- ① Dispo: `list_planned(shooting_day_id)` → `ORDER BY planned_order`.
- ② Shoot Day: `list_actual(shooting_day_id)` → `ORDER BY actual_order NULLS LAST`, includes notes + continuity photo refs.
- ③ Soll-Ist: `compare_planned_vs_actual(shooting_day_id)` → computed diff (moved, missing, skipped, reshot candidates = `SceneShoot`s for the same scene on other days).

All three are read-only query paths; the Soll-Ist diff is computed at read time (or a materialised view later if performance demands).

**Rationale:** CQRS read side is the natural home; a separate "report aggregate" would duplicate state and fight event sourcing.

### D8. `script_day: Option<String>` on `SceneDetails` (free-form, not a typed enum)

**Choice:** Add `script_day: Option<String>` to `SceneDetails` (e.g. "1. Spieltag", "Spieltag 2"). Looked up via `ILIKE`/equality on the projection for search, not as a first-class entity.

**Rationale:** The Spieltag is the *fictional* chronology in the script, distinct from the real calendar `ShootingDay.date`. It has no further semantics beyond "you can find scenes by it later", so a free-form string avoids over-modelling a `ScriptDay` entity. `SceneDetailsUpdated` already exists, so no new event is needed for this field — purely additive.

### D9. Migration of the existing `projection_scene_shooting_day` join

**Choice:** Introduce `projection_scene_shoot` (new migration) and backfill: each existing `(scene_id, shooting_day_id)` row becomes a `SceneShoot` in `Planned` status with `planned_order` assigned by a one-time sort (scene-script order or existing join order as the seed). `actual_order`/times start `None`. The old `projection_scene_shooting_day` may be kept read-only for a transition window or dropped once all reads move to the new projection.

**Rationale:** Existing data is plan-only; backfilling as `Planned` is lossless and matches the dominant pre-change state.

## Risks / Trade-offs

- **[Backfill ordering is arbitrary]** → Existing joins have no order; the seed `planned_order` is a best-effort (scene-script or join-insertion order). Stakeholders may need a one-time manual re-sort post-migration. Mitigation: document clearly; provide a reorder command immediately.
- **[Passive freezing relies on someone entering actual data]** → If a day is shot but no actuals are ever recorded, `planned_order` stays editable and the Soll-Ist report shows no drift. Acceptable: continuity is the whole *point*; if the crew doesn't record it, there's nothing to compare, and the report honestly reflects that.
- **[Continuity refcount table adds DB surface]** → `projection_continuity_photo` is a new projection with FK to `projection_photo` and `projection_scene_shoot`. Projector idempotency and FK ordering must match the existing `projection_costume_photo` patterns (the Tier-4 integration-test gotchas about missing projectors and FK violations apply — see AGENTS.md).
- **[`PhotoBinding` is an additive but non-trivial change to `PhotoUploaded`]** → Existing photo event streams predate the binding field. Migration/backfill must default existing photos to `PhotoBinding::Costume { costume_id }`, since all current photos are costume photos. Event deserialisation should treat a missing `binding` as `Costume` for backward compat.
- **[Day wraps cross-`SceneShoot` boundaries]** → `ShootingDayWrapped` freezes *reporting* for all `SceneShoot`s of that day, but those are separate streams. The reporter must read day-wrap state from the `ShootingDay` projection and intersect with `SceneShoot` projection rows for that day.
- **[Client clock used only for UI "live" badge]** → Acceptable since it affects display only, not write integrity; no Bauchschmerzen per stakeholder sign-off.

## Migration Plan

1. **Schema (Postgres migrations):**
   - Add `projection_scene_shoot` (scene_id, shooting_day_id, planned_order, actual_order NULL, start_dt NULL, end_dt NULL, status enum, notes JSONB DEFAULT '[]', version, ...), unique on (scene_id, shooting_day_id).
   - Add `projection_continuity_photo` (photo_id, scene_shoot_id, costume_id NULL) with FKs.
   - Add `wrapped_at TIMESTAMPTZ NULL` + status to `projection_shooting_day`.
   - Add `script_day TEXT NULL` to `projection_scene`.
2. **Backfill:** one-shot script creating `SceneShoot` `Planned` rows from `projection_scene_shooting_day`, seeded order = scene number / join order.
3. **Default photo binding:** existing `projection_photo` rows tagged `Costume` (or the projector defaults it on read for pre-binding rows).
4. **Roll forward:** deploy aggregate + projectors + API. Old join projection read path retired once all consumers moved.
5. **Rollback:** additive schema changes can be dropped; the old `projection_scene_shooting_day` read path remains until the new one is validated, enabling a read-side rollback without write-side changes.

## Open Questions

- Should `ShootingDayWrapped` be reversible (un-wrap) to correct mistake fires, or terminal-like `Archive`? Lean: allow unwrap via a `ShootingDayUnwrapped`/re-wrap in a follow-up if needed; for v1 treat as reversible-by-reissuing-wrap is *not* allowed (would confuse reports). Resolve in `scene-shoot` spec.
- Exact refcount table shape for continuity (dedicated `projection_continuity_photo` vs a unified `projection_photo_binding` table with a `kind` column). Decide in `photo-continuity-binding` spec; lean to dedicated table to mirror `projection_costume_photo`.
- Whether the Soll-Ist report should flag "same scene shot on multiple days" as a *reshot* automatically or treat each pair independently — lean: flag as info, not error, since reshoots are legitimate.
