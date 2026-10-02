<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3-flash (opencode-go) -->

# 546 — Scene costume assignment: ordered costume beats per (scene, character)

## Why

The relation “costume worn in scene S” does not exist in the domain model. There
is no field, no command, no event, no projection, no query, and no endpoint for
it. The answer to “which costume does character X wear in scene S” is today
*derived* — `X ∈ Scene.assigned_characters` → `Costume.character_id = X` — which
expresses at most one global costume per character, not per-scene casting. An
`on change` (two costume states inside one scene, a routine episodic device)
cannot be represented at all; it can only be smuggled into scene prose.

The relation must therefore be modelled as an ordered sequence of costume beats
per (scene, character), not as one costume per scene. A 1:1 model would encode a
rule the domain does not have and force a wire break in the first production
season.

## Decision

**Option A — Scene-owned ordered beats.** `SceneAggregate` gains
`costume_beats: Vec<SceneCostumeBeat>` with
`SceneCostumeBeat { character_id, costume_id, order, note }`. Three commands
(`AddCostumeBeat`, `UpdateCostumeBeat`, `RemoveCostumeBeat`), four events on the
Scene stream (`CostumeBeatAdded`/`Updated`/`Removed`/`BeatsCleared`). This is
symmetric with the established `assigned_characters` pattern: the invariants
(“a character in this scene wears these costumes, in this order”) are
intra-aggregate, enforced in `handle()` — no cross-aggregate doctrine, no new
stream, no cascade handling, trivially replay-safe, and it expresses
`on change` natively.

**Doctrine decision (§6 row 4 of the issue, written down explicitly):** a
costume may be cast for a character it is **not** primarily bound to. The
aggregate cannot know costume state, so a mismatch is *not* rejected: no API-edge
409 pre-check, no projection constraint, no dead-letter path. A beat is a
statement about the scene (“this figure wears this garment here”), the costume’s
`character_id` stays the primary/default binding only. This is the “garment on
loan” reading and avoids inventing an advisory check that would block
legitimate reuse. The aggregate *does* enforce its own invariant: a beat may
only exist for a character in `assigned_characters` (422
`scene.character-not-in-scene`).

## Changed capabilities

- **NEW capability `scene-costume-assignment`** — the aggregate invariants, the
  projection, the read model, and the API surface.
- MODIFIED `costume-character-binding` — “binding lives on
  character_id/category_id” restated: `character_id` is the **primary/default**
  character; per-scene casting lives on the Scene.
- MODIFIED `scene-scoping` — the Scene read model gains
  `costume_beats` (additive on the wire); the `CreateScene` scenario
  text is corrected (it wrongly lists `assigned_characters` as a command field).
- MODIFIED `production-hierarchy` — the hierarchy description gains the
  per-scene ordered costume beats as the costume↔scene relation.

## Implementation decision (scope)

**Backend + OpenSpec + vendored client in this change; Flutter follows in the
second PR** — the precedent of #543 (backend PR + separate Flutter PR, wire
window accepted). Flutter tasks stay in the task list as the deferred
remainder.

## Impact

- `crates/core/src/scene/`: new `costume.rs` (`SceneCostumeBeat`),
  commands, events, aggregate state + apply branches, `SceneError` variants
  (`CharacterNotInScene`, `BeatNotFound`).
- `crates/core/src/error_registry.rs`: two new `problem_codes!` entries
  `scene.beat-not-found` (422), `scene.character-not-in-scene` (422) + Fluent
  texts.
- `crates/infra/`: migration `projection_scene_costume_assignment`
  (`PRIMARY KEY (scene_id, character_id, order)` + reverse index),
  four projector branches (version-guarded), `command_adapters.rs` entries,
  `SceneRepository` query enrichment (`SceneView.costume_beats`).
- `crates/api/`: four routes under the scene group (block-membership middleware
  applies → no handler-internal AUTHZ-GATE), request struct schemas,
  `openapi.yaml` regen, `scripts/regen-client.sh` byte-identity.
- AI import (`mapping_kind::SCENE_COSTUME_BEAT`, per-figure re-grouping,
  `AssignCharacter`+`AddCostumeBeat` dispatch): **deferred to a follow-up** —
  the archived change’s spec deltas survive this change unharmed (the “SHALL NOT
  introduce a scene scope” sentence targets scope *columns* on the Costume
  aggregate, not the scene-side casting this change introduces; the restated
  binding requirement is MODIFIED once here, no open competing delta exists)
  and an import that does not persist the relation regresses nothing — it
  already persisted nothing.
