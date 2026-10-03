<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3-flash (opencode-go) -->

# Tasks — 546 scene costume assignment (backend + OpenSpec + vendored client)

Scope note: this task list covers the backend change (core/infra/api +
migration + specs + openapi + vendored client regen), the precedent of #543.
The **Flutter** section is the explicitly deferred remainder — it lands in the
second PR (scene detail costumes section, picker, controller, ARB keys,
goldens, `docs/design/screens/scenes.md`).

## 1. Core — aggregate, commands, events (`crates/core/src/scene/`)

- [x] **1.1 `costume.rs`**: `SceneCostumeBeat { character_id, costume_id,
      order: u32, note: Option<String> }` with `Serialize`/`Deserialize` and
      `#[serde(default)]`-friendly shape for replay of legacy streams.
      *Satisfies:* scene-costume-assignment “Scene carries ordered costume
      beats”.
- [x] **1.2 Commands** (`commands.rs`): `AddCostumeBeat { id, character_id,
      costume_id, note, series_id, version }`,
      `UpdateCostumeBeat { id, character_id, order, costume_id, note,
      series_id, version }`,
      `RemoveCostumeBeat { id, character_id, order: Option<u32>, series_id,
      version }`.
- [x] **1.3 Events** (`events.rs`): `CostumeBeatAdded { id, character_id,
      costume_id, order, note, version }`, `CostumeBeatUpdated { … }`,
      `CostumeBeatRemoved { id, character_id, order, version }`,
      `CostumeBeatsCleared { id, character_id, version }` + `EventType` arms.
- [x] **1.4 Aggregate state + apply branches** (`aggregate.rs`):
      `costume_beats: Vec<SceneCostumeBeat>`; apply for all four events;
      `SceneCreated` apply branch leaves beats empty (legacy streams replay
      clean).
- [x] **1.5 Command handlers**:
      - `AddCostumeBeat` — character must be in `assigned_characters`
        (422 `CharacterNotInScene`); `order` computed as `max+1` (0 when
        none); consecutive-identical-beat guard → `ValidationError`;
        re-adding the identical last `(costume_id, note)` → `ValidationError`.
      - `UpdateCostumeBeat` — edits the beat at `(character_id, order)` in
        place; `BeatNotFound` if absent; never changes `order`.
      - `RemoveCostumeBeat` — `Some(order)` removes exactly that beat
        (surviving orders untouched, dense invariant kept because removal of
        the last beat preserves denseness; reordering = remove + add);
        `None` removes all beats of the character.
- [x] **1.6 `SceneError`**: `CharacterNotInScene { character_id }`,
      `BeatNotFound { character_id, order }`; `From<SceneError> for
      DomainError` arms.
- [x] **1.7 Problem codes** (`error_registry.rs`): `SCENE_BEAT_NOT_FOUND`
      (`scene.beat-not-found`, 422, extensions `["character_id","order"]`),
      `SCENE_CHARACTER_NOT_IN_SCENE` (`scene.character-not-in-scene`, 422,
      extensions `["character_id"]`); Fluent texts in
      `crates/api/locales/{de,en}/errors.ftl`; golden snapshots.
      *Satisfies:* scene-costume-assignment error scenarios.
- [x] **1.8 Port methods** (`scene/ports.rs`): `add_costume_beat`,
      `update_costume_beat`, `remove_costume_beat` on `SceneCommands`.
- [x] **1.9 Core unit tests**: add/remove success; `CharacterNotInScene`;
      `BeatNotFound`; dense-order (add 3 → 0,1,2; remove middle → 0,2, no
      renumber); consecutive-identical guard; clear-all; version chain;
      replay of legacy `SceneCreated` without beats.

## 2. Infra

- [x] **2.1 Migration** `projection_scene_costume_assignment`
      (`PRIMARY KEY (scene_id, character_id, order)`, FK CASCADE to
      `projection_scene`, reverse index on `costume_id`) + down migration.
      *Satisfies:* scene-costume-assignment projection requirement.
- [x] **2.2 Projector branches** (`projectors/scene.rs`): Added/Updated/
      Removed/Cleared, version-guarded style consistent with the existing
      handlers; `CostumeBeatsCleared` = `DELETE … WHERE scene_id=$1 AND
      character_id=$2`; `CostumeBeatRemoved` deletes exactly the one row.
- [x] **2.3 Command adapters** (`event_store/command_adapters.rs`):
      `add_costume_beat` / `update_costume_beat` / `remove_costume_beat` with
      `check_nonzero_version`, `ExpectedVersion::Exact`,
      `series_id` from the command field only.
- [x] **2.4 Query enrichment** (`queries/scene.rs`):
      `SceneView.costume_beats: Vec<SceneCostumeBeatView>` — fan-out-free
      correlated subquery pattern (issue #550 shape), enriched with
      character name + costume identity (category + icon via the current
      model) joining `projection_character` / `projection_costume`.
- [x] **2.5 Infra tests**: projector for all four events incl. version-guard
      redelivery; migration up/down; FK cascade when the scene row
      disappears. (Delivered across PR #578 + the §5.8 PR:
      `crates/integration-tests/tests/scene_costume_beats.rs` covers all four
      projector branches, the PK backstop and the FK cascade;
      `beat_projector_redelivery_is_idempotent_under_guard_parent` pins the
      `guard_parent` redelivery behaviour; migration up/down is covered by
      the global `migrations_are_reversible` harness.)

## 3. API

- [x] **3.1 Routes** (`handlers/mod.rs`, scene route group):
      `POST /v1/scenes/{id}/costumes`,
      `PATCH /v1/scenes/{id}/costumes/{character_id}/{order}`,
      `DELETE /v1/scenes/{id}/costumes/{character_id}/{order}`,
      `DELETE /v1/scenes/{id}/costumes/{character_id}` — 200
      `AggregateVersion` / 404 / 409 / 422; block-membership middleware
      applies (no handler-internal AUTHZ-GATE needed).
      *Satisfies:* scene-costume-assignment API requirement.
- [x] **3.2 Request schemas**: `AddSceneCostumeBeatRequest`,
      `UpdateSceneCostumeBeatRequest` (no client `order` on add — the
      aggregate owns it); register in `components(schemas(...))`.
- [x] **3.3 API tests**: 200/404/409/422 paths; version-conflict 409 echo.
- [x] **3.4 Contract**: `UPDATE_OPENAPI=1 cargo test -p api --test
      openapi_drift`; `bash scripts/regen-client.sh`; vendored
      `vendor/breakdown_api/` byte-identical, committed.

## 4. Specs & docs

- [x] **4.1 `specs/scene-costume-assignment/spec.md`** (ADDED) — invariants,
      projection, read model, API (this change's deltas).
- [x] **4.2 `specs/costume-character-binding/spec.md`** (MODIFIED) —
      primary/default binding + per-scene beats restatement.
- [x] **4.3 `specs/scene-scoping/spec.md`** (MODIFIED — read model gains
      `costume_beats`; `CreateScene` scenario text corrected).
- [x] **4.4 `specs/production-hierarchy/spec.md`** (MODIFIED — hierarchy
      description gains the beats relation).
- [x] **4.5** `openspec validate 546-scene-costume-assignment --strict`
      passes.

## 5. Flutter (deferred to the second PR — PLANNED, NOT in this diff)

- [x] **5.1** `scene_repository.dart` + `scenes_controller.dart`:
      `addCostumeBeat` / `updateCostumeBeat` / `removeCostumeBeat`, `Result`
      returns, `// AUTHZ-GATE:` membership capability check before the
      network call, optimistic-after-2xx + version fence + bounded retry.
- [x] **5.2** Scene detail screen `_SceneCostumesSection` (`ExpansionTile`,
      one row per beat, `A → B` rendering, empty-state affordance,
      `+ Kostümwechsel`), bottom-sheet picker per the create-sheet
      convention.
- [x] **5.3** ARB keys (`app_de`/`app_en`, parity), error banners keyed on
      `code`.
- [x] **5.4** `docs/design/screens/scenes.md` (nine sections + Salt
      wireframe), `scripts/check-design-diagrams.sh` green; widget tests +
      first scene-screen goldens.

## 6. AI-import persistence (§5.8 — the apply persists the scene relation)

- [x] **6.1** OpenSpec delta `specs/ai-import/spec.md` (MODIFIED requirement
      "Idempotent upsert apply via user-driven mapping"): the apply persists
      `AssignCharacter`×n before the beats, `AddCostumeBeat` per accepted
      costume in per-figure plan order, `scene_costume_beat` mapping rows;
      re-apply adds no second beat; the report distinguishes "dropped as
      ungrounded" from a refused beat.
- [x] **6.2 Core** (`crates/core/src/ai/`): `mapping_kind::SCENE_COSTUME_BEAT`
      (additive constant); pure per-figure re-grouping of the row's flat
      costume list (`scene_beat_lanes`, plan order kept, per-figure 0..n-1,
      unit-tested); `UnappliedCostumeReason::BeatRejected` (additive wire
      variant) so a refused beat never looks like the plan-time drop.
- [x] **6.3 Infra apply worker** (`crates/infra/src/ai/workers.rs`):
      `AssignCharacter` per figure of the row on the scene stream (before any
      beat; `CharacterAlreadyAssigned` and a stale version are recovery, not
      failure), `AddCostumeBeat` per costume after its chain succeeded;
      `scene_costume_beat` mapping rows keyed by the figure's mapping
      reference + per-figure ordinal, `aggregate_id` = scene id; the
      scene-stream version is maintained jointly across the `scene` row and
      the beat rows (max-read on recovery, only-moves-forward confirms,
      collision documented at the worker).
- [x] **6.4 Worker tests**: pinned chain arithmetic (exactly one event per
      step, mapping versions record the phases), re-apply adds no second
      beat, crash recovery between the chain steps resumes at the right
      phase, drop-vs-beat report distinction.
- [x] **6.5 Wire + client (single-PR closure, user decision 2026-10-03):
      additive `beat_rejected` enum value regenerated into
      `backend/openapi.yaml` and `vendor/breakdown_api/`; Flutter reason copy
      (`aiApplyUnappliedReasonBeatRejected`, de/en) + switch arm. Overrides
      the handoff's "no wire change" assumption — without it the refused-beat
      case would be indistinguishable from the ungrounded drop on the wire.
- [x] **6.6** `openspec validate 546-scene-costume-assignment --strict`
      passes.
