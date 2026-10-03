<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->

## ADDED Requirements

### Requirement: Scene carries ordered costume beats

A `SceneAggregate` SHALL hold `costume_beats: Vec<SceneCostumeBeat>` with
`SceneCostumeBeat { character_id, costume_id, order: u32, note: Option<String> }`.
A beat SHALL only exist for a character in the scene's `assigned_characters`
(422 `scene.character-not-in-scene` otherwise, no event). `order` SHALL be
dense, zero-based and unique per character within the scene, computed by the
aggregate as `max(order) + 1` on add — never client-supplied on the add path.
Reordering SHALL be expressed as remove + add; `UpdateCostumeBeat` SHALL
never change `order`.

#### Scenario: Adding a beat to an assigned character

- **WHEN** an `AddCostumeBeat` command targets a scene where `character_id` is
  in `assigned_characters`
- **THEN** the aggregate SHALL emit `CostumeBeatAdded` carrying the
  aggregate-computed `order` (the first beat of that character gets `order = 0`)
- **AND** the aggregate version SHALL advance by exactly one

#### Scenario: Adding a beat for a character not in the scene

- **WHEN** an `AddCostumeBeat` (or `Update`/`Remove` beat command) targets a
  scene where `character_id` is NOT in `assigned_characters`
- **THEN** the command SHALL fail with 422 `scene.character-not-in-scene`
- **AND** no event SHALL be emitted

#### Scenario: On change — two costumes in one scene, in order

- **WHEN** two consecutive `AddCostumeBeat` commands add costumes A and B for
  the same character in the same scene
- **THEN** the character's beats SHALL carry orders 0 and 1 in that add order
- **AND** the read model SHALL present them in ascending `order`

#### Scenario: Dense order is preserved without renumbering

- **WHEN** a character's beats hold orders 0, 1, 2 and the beat at order 1 is
  removed via `RemoveCostumeBeat` with `Some(1)`
- **THEN** the surviving beats keep orders 0 and 2
- **AND** the next add for that character SHALL get `order = 3` (max + 1), not
  a renumbered slot

#### Scenario: Consecutive-identical-beat guard

- **WHEN** an `AddCostumeBeat` appends a beat whose `costume_id` equals the
  character's current last beat's `costume_id`
- **THEN** the command SHALL fail with 422 `scene.validation`
- **AND** no event SHALL be emitted

#### Scenario: Updating a beat in place

- **WHEN** an `UpdateCostumeBeat { character_id, order, costume_id, note }`
  command targets an existing (character, order) beat
- **THEN** the aggregate SHALL emit `CostumeBeatUpdated` carrying the same
  `order` and the new costume/note values
- **AND** when no beat exists at that position the command SHALL fail with
  422 `scene.beat-not-found`

#### Scenario: Removing all beats of a character

- **WHEN** a `RemoveCostumeBeat` command with `order: None` targets a
  character that has at least one beat
- **THEN** the aggregate SHALL emit `CostumeBeatsCleared` and the character
  SHALL have no costume in the scene afterwards
- **AND** when the character has no beats at all the command SHALL fail
  with 422 `scene.beat-not-found` (dedicated `NoCostumeBeats` variant — a
  client can tell "nothing to clear" apart from a generic validation
  failure)

#### Scenario: Removing a character clears its beats

- **WHEN** a `RemoveCharacter` command targets a character that holds one
  or more costume beats
- **THEN** the aggregate SHALL emit `CostumeBeatsCleared` for the
  character **before** `CharacterRemoved`, both advancing the aggregate
  version in order
- **AND** no orphan beat row SHALL survive in aggregate state or the
  projection

#### Scenario: Legacy streams replay without beats

- **WHEN** a Scene stream recorded before this change replays (only legacy
  `SceneCreated` and earlier events)
- **THEN** the aggregate state SHALL have an empty `costume_beats` list
- **AND** replay SHALL require no data migration

### Requirement: Scene costume beats projection

The scene projection SHALL persist costume beats in
`projection_scene_costume_assignment` with
`PRIMARY KEY (scene_id, character_id, "order")` — one costume per beat, beats
uniquely ordered per character as a structural property of the table — a
foreign-key cascade to `projection_scene` on scene deletion, and a reverse
index on `costume_id` for “in which scenes is this costume worn?” lookups. No
cascade to `projection_costume` SHALL be added (a costume is never deleted).
The projector SHALL handle `CostumeBeatAdded`/`Updated`/`Removed`/
`BeatsCleared` idempotently and version-guarded; `CostumeBeatRemoved` SHALL
delete exactly the removed row and SHALL NOT renumber surviving orders
(denseness is an aggregate fact, not a projection repair job).

#### Scenario: Beat rows persist per scene, character and order

- **WHEN** a scene's aggregate has two beats for one character (orders 0, 1)
- **THEN** `projection_scene_costume_assignment` SHALL hold exactly two rows
  for that `(scene_id, character_id)`
- **AND** no row combination violating the primary key can be projected

#### Scenario: Reverse lookup by costume

- **WHEN** a query asks for the rows with `costume_id = K`
- **THEN** the reverse index SHALL answer without a table scan

#### Scenario: Cascade on scene deletion

- **WHEN** a `projection_scene` row is deleted
- **THEN** all of its `projection_scene_costume_assignment` rows SHALL be
  deleted by the FK cascade

### Requirement: Scene read model exposes costume beats

`SceneView` SHALL carry `costume_beats: Vec<SceneCostumeBeatView>` — additive
on the wire — with each beat resolved by the query layer: character name
(joined from `projection_character`) and costume identity (id and the
current model's display fields from `projection_costume`), ordered by
(character_id, order). The scene query SHALL read the beats fan-out-free (the
issue-#550 correlated-subquery pattern), never via a row-multiplying join.

#### Scenario: Reading a scene with beats

- **WHEN** a client GETs a scene whose aggregate holds beats
- **THEN** the returned `SceneView.costume_beats` SHALL list them in
  `(character_id, order)` order with resolved character and costume identity
- **AND** clients written against the pre-beat `SceneView` decode the new
  field without breakage (additive, serde-defaulted on the client)

#### Scenario: Reading a scene without beats

- **WHEN** a scene has no beats
- **THEN** `costume_beats` SHALL be an empty list, not null, never an error

### Requirement: Scene costume assignment HTTP surface

The API SHALL expose, under the existing scene route group (block-membership
middleware applies; no additional handler-internal gate):

| Route | Command | Responses |
|---|---|---|
| `POST /v1/scenes/{id}/costumes` | `AddCostumeBeat` | 200 `AggregateVersion`, 404, 409, 422 |
| `PATCH /v1/scenes/{id}/costumes/{character_id}/{order}` | `UpdateCostumeBeat` | 200 `AggregateVersion`, 404, 409, 422 |
| `DELETE /v1/scenes/{id}/costumes/{character_id}/{order}` | `RemoveCostumeBeat(Some(order))` | 200 `AggregateVersion`, 404, 409, 422 |
| `DELETE /v1/scenes/{id}/costumes/{character_id}` | `RemoveCostumeBeat(None)` | 200 `AggregateVersion`, 404, 409, 422 |

The add request body SHALL carry `character_id`, `costume_id`, `note`,
`version` — no client `order`. Failures SHALL surface as RFC 9457 problems
with the registry codes `scene.character-not-in-scene` (422) and
`scene.beat-not-found` (422); a stale `version` SHALL surface as 409
`concurrency.version-mismatch`.

#### Scenario: Adding a costume beat over HTTP

- **WHEN** a block member POSTs `{ character_id, costume_id, note, version }`
  to `/v1/scenes/{id}/costumes`
- **THEN** the response SHALL be 200 with the new aggregate version
- **AND** the projector SHALL reflect the beat after catch-up

#### Scenario: Beat command failures as problems

- **WHEN** a beat command fails aggregate validation
- **THEN** the client SHALL receive an `application/problem+json` body whose
  `code` distinguishes `scene.character-not-in-scene` from
  `scene.beat-not-found` from `concurrency.version-mismatch`
- **AND** clients branch on the stable `code`, not on `detail`

#### Scenario: Route is scoped to an active block

- **WHEN** a request without block membership (no `X-Active-Block` or a block
  the user is not a member of) targets any beat route
- **THEN** the block-membership middleware SHALL reject it before the handler
  runs
