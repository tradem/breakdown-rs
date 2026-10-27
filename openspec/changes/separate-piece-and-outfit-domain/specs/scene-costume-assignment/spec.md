<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go)

## REMOVED Requirements

### Requirement: Scene carries ordered costume beats
**Reason**: The clean cut replaces the costume-beat model with the outfit-beat
model. A `SceneCostumeBeat` referenced a `Costume` that carried both the
garment and the character binding, which forced multi-garment looks into
sequential `on change` beats; `SceneOutfitBeat` references a composed
`Outfit` instead (capability `outfit-management`), so a single beat expresses a
full look.

**Migration**: `AddCostumeBeat` → `AddOutfitBeat`, `UpdateCostumeBeat` →
`UpdateOutfitBeat`, `RemoveCostumeBeat` → `RemoveOutfitBeat`, and the events
`CostumeBeatAdded`/`Updated`/`Removed`/`BeatsCleared` →
`OutfitBeatAdded`/`Updated`/`Removed`/`BeatsCleared`. Administered scene
streams predating the cut carry no beat events and replay to an empty list; the
former `costume_beats` field is removed outright (no alias).

### Requirement: Scene costume beats projection
**Reason**: The projection table is renamed and re-keyed to the outfit
reference (`projection_scene_outfit_assignment`, reverse index on `outfit_id`).

**Migration**: `projection_scene_costume_assignment` →
`projection_scene_outfit_assignment` in the same migration that renames the
costume projections to piece projections. No data migration is required (no
production data); dev environments reset their volumes.

### Requirement: Scene read model exposes costume beats
**Reason**: `SceneView.costume_beats` is replaced by
`SceneView.outfit_beats`, resolving outfit identity (`id`, `name`,
`variant_of`) from `projection_outfit` instead of costume display fields from
`projection_costume`.

**Migration**: Clients switch the JSON field name from `costume_beats` to
`outfit_beats`; the vendored Flutter client is regenerated from
`backend/openapi.yaml` in this change. No released client exists against
`/v1` yet (ADR-021 needed no `/v2` window).

### Requirement: Scene costume assignment HTTP surface
**Reason**: The beat routes now address outfits
(`/v1/scenes/{id}/outfits*`) and take `outfit_id` in the body instead of
`costume_id`.

**Migration**: `POST /v1/scenes/{id}/costumes` →
`POST /v1/scenes/{id}/outfits`, `PATCH`/`DELETE /v1/scenes/{id}/costumes/{character_id}[/{order}]`
→ the same paths under `/outfits`. The retired routes return 404 — no alias,
no deprecation window.

## ADDED Requirements

### Requirement: Scene carries ordered outfit beats

A `SceneAggregate` SHALL hold `outfit_beats: Vec<SceneOutfitBeat>` with
`SceneOutfitBeat { character_id, outfit_id: Uuid, order: u32, note:
Option<String> }`. A beat SHALL only exist for a character in the scene's
`assigned_characters` (422 `scene.character-not-in-scene` otherwise, no
event). `order` SHALL be dense, zero-based and unique per character within the
scene, computed by the aggregate as `max(order) + 1` on add — never
client-supplied on the add path. Reordering SHALL be expressed as remove +
add; `UpdateOutfitBeat` SHALL never change `order`. A beat's `outfit_id` SHALL
NOT be validated against the beat's `character_id`: an outfit may legitimately
be cast for another character in a scene (the same freedom the former costume
beats had), and the aggregate cannot resolve cross-aggregate state anyway.

#### Scenario: Adding a beat to an assigned character

- **WHEN** an `AddOutfitBeat` command targets a scene where `character_id` is
  in `assigned_characters`
- **THEN** the aggregate SHALL emit `OutfitBeatAdded` carrying the
  aggregate-computed `order` (the first beat of that character gets `order = 0`)
- **AND** the aggregate version SHALL advance by exactly one

#### Scenario: Adding a beat for a character not in the scene

- **WHEN** an `AddOutfitBeat` (or `Update`/`Remove` beat command) targets a
  scene where `character_id` is NOT in `assigned_characters`
- **THEN** the command SHALL fail with 422 `scene.character-not-in-scene`
- **AND** no event SHALL be emitted

#### Scenario: On change — two outfits in one scene, in order

- **WHEN** two consecutive `AddOutfitBeat` commands add outfits A and B for
  the same character in the same scene
- **THEN** the character's beats SHALL carry orders 0 and 1 in that add order
- **AND** the read model SHALL present them in ascending `order`

#### Scenario: A full layered look needs a single beat

- **WHEN** a character wears an outfit composed of three layers in a scene
- **THEN** one `AddOutfitBeat` SHALL express the whole look
- **AND** the beat count for that character SHALL remain 1 (no `on change`
  beats are consumed by layering)

#### Scenario: Dense order is preserved without renumbering

- **WHEN** a character's beats hold orders 0, 1, 2 and the beat at order 1 is
  removed via `RemoveOutfitBeat` with `Some(1)`
- **THEN** the surviving beats keep orders 0 and 2
- **AND** the next add for that character SHALL get `order = 3` (max + 1), not
  a renumbered slot

#### Scenario: Consecutive-identical-beat guard

- **WHEN** an `AddOutfitBeat` appends a beat whose `outfit_id` equals the
  character's current last beat's `outfit_id`
- **THEN** the command SHALL fail with 422 `scene.validation`
- **AND** no event SHALL be emitted

#### Scenario: Updating a beat in place

- **WHEN** an `UpdateOutfitBeat { character_id, order, outfit_id, note }`
  command targets an existing (character, order) beat
- **THEN** the aggregate SHALL emit `OutfitBeatUpdated` carrying the same
  `order` and the new outfit/note values
- **AND** when no beat exists at that position the command SHALL fail with
  422 `scene.beat-not-found`

#### Scenario: Removing all beats of a character

- **WHEN** a `RemoveOutfitBeat` command with `order: None` targets a character
  that has at least one beat
- **THEN** the aggregate SHALL emit `OutfitBeatsCleared` and the character
  SHALL have no outfit in the scene afterwards
- **AND** when the character has no beats at all the command SHALL fail with
  422 `scene.beat-not-found` (a client can tell "nothing to clear" apart from
  a generic validation failure)

#### Scenario: Removing a character clears its beats

- **WHEN** a `RemoveCharacter` command targets a character that holds one or
  more outfit beats
- **THEN** the aggregate SHALL emit `OutfitBeatsCleared` for the character
  **before** `CharacterRemoved`, both advancing the aggregate version in order
- **AND** no orphan beat row SHALL survive in aggregate state or the
  projection

#### Scenario: Streams without beat events replay to an empty list

- **WHEN** a Scene stream containing no `Outfit*`-beat events is replayed
- **THEN** the aggregate state SHALL have an empty `outfit_beats` list
- **AND** the former `costume_beats` field SHALL no longer exist on the
  aggregate, the events, or the view

### Requirement: Scene outfit beats projection

The scene projection SHALL persist outfit beats in
`projection_scene_outfit_assignment` with
`PRIMARY KEY (scene_id, character_id, "order")` — one outfit per beat, beats
uniquely ordered per character as a structural property of the table — a
foreign-key cascade to `projection_scene` on scene deletion, and a reverse
index on `outfit_id` for "in which scenes is this outfit worn?" lookups. No
cascade to `projection_outfit` SHALL be added. The projector SHALL handle
`OutfitBeatAdded`/`Updated`/`Removed`/`BeatsCleared` idempotently and
version-guarded; `OutfitBeatRemoved` SHALL delete exactly the removed row and
SHALL NOT renumber surviving orders (denseness is an aggregate fact, not a
projection repair job).

#### Scenario: Beat rows persist per scene, character and order

- **WHEN** a scene's aggregate has two beats for one character (orders 0, 1)
- **THEN** `projection_scene_outfit_assignment` SHALL hold exactly two rows
  for that `(scene_id, character_id)`
- **AND** no row combination violating the primary key can be projected

#### Scenario: Reverse lookup by outfit

- **WHEN** a query asks for the rows with `outfit_id = K`
- **THEN** the reverse index SHALL answer without a table scan

#### Scenario: Cascade on scene deletion

- **WHEN** a `projection_scene` row is deleted
- **THEN** all of its `projection_scene_outfit_assignment` rows SHALL be
  deleted by the FK cascade

#### Scenario: Redelivered beat events are idempotent

- **WHEN** the same `OutfitBeatAdded` event is processed twice
- **THEN** `projection_scene_outfit_assignment` SHALL hold exactly one row for
  that `(scene_id, character_id, order)`

### Requirement: Scene read model exposes outfit beats

`SceneView` SHALL carry `outfit_beats: Vec<SceneOutfitBeatView>` — additive
on the wire — with each beat resolved by the query layer: character name
(joined from `projection_character`) and outfit identity (id plus `name` and
`variant_of` from `projection_outfit`), ordered by (character_id, order). The
scene query SHALL read the beats fan-out-free (the issue-#550
correlated-subquery pattern), never via a row-multiplying join.

#### Scenario: Reading a scene with beats

- **WHEN** a client GETs a scene whose aggregate holds beats
- **THEN** the returned `SceneView.outfit_beats` SHALL list them in
  `(character_id, order)` order with resolved character and outfit identity
- **AND** clients decode the field without breakage (additive, serde-defaulted
  on the client)

#### Scenario: Reading a scene without beats

- **WHEN** a scene has no beats
- **THEN** `outfit_beats` SHALL be an empty list, not null, never an error

#### Scenario: A dangling outfit reference does not fail the read

- **WHEN** a beat references an `outfit_id` whose projection row is missing
  (projector lag or a dead-lettered event)
- **THEN** the beat SHALL still be returned with an unresolved outfit name
  rather than failing the whole scene read

### Requirement: Scene outfit assignment HTTP surface

The API SHALL expose, under the existing scene route group (block-membership
middleware applies; no additional handler-internal gate):

| Route | Command | Responses |
|---|---|---|
| `POST /v1/scenes/{id}/outfits` | `AddOutfitBeat` | 200 `AggregateVersion`, 404, 409, 422 |
| `PATCH /v1/scenes/{id}/outfits/{character_id}/{order}` | `UpdateOutfitBeat` | 200 `AggregateVersion`, 404, 409, 422 |
| `DELETE /v1/scenes/{id}/outfits/{character_id}/{order}` | `RemoveOutfitBeat(Some(order))` | 200 `AggregateVersion`, 404, 409, 422 |
| `DELETE /v1/scenes/{id}/outfits/{character_id}` | `RemoveOutfitBeat(None)` | 200 `AggregateVersion`, 404, 409, 422 |

The add request body SHALL carry `character_id`, `outfit_id`, `note`,
`version` — no client `order`. Failures SHALL surface as RFC 9457 problems
with the registry codes `scene.character-not-in-scene` (422) and
`scene.beat-not-found` (422); a stale `version` SHALL surface as 409
`concurrency.version-mismatch`. The former `/v1/scenes/{id}/costumes*` routes
SHALL be removed without an alias.

#### Scenario: Adding an outfit beat over HTTP

- **WHEN** a block member POSTs `{ character_id, outfit_id, note, version }`
  to `/v1/scenes/{id}/outfits`
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

#### Scenario: Former costume beat routes are gone

- **WHEN** a client requests any `/v1/scenes/{id}/costumes*` route
- **THEN** the API SHALL answer 404 — no handler SHALL remain
