<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go)

## ADDED Requirements

### Requirement: Outfit is a character-bound aggregate

An `OutfitAggregate` (stream category `"outfit"`) SHALL represent a composed
look worn by exactly one character. It SHALL carry `id: Uuid` (UUIDv7),
`character_id: CharacterId` (mandatory), `name: String`,
`piece_ids: Vec<PieceId>` (`0..n`, insertion-ordered, deduplicated),
`variant_of: Option<Uuid>`, `photos: Vec<Uuid>`, `notes: String`, and
`version: AggregateVersion`.

`OutfitCreated` SHALL carry `id`, `character_id`, `name`, `piece_ids`,
`photos`, `notes`, and `version`. The outfit's season scope SHALL be derived
deterministically from `character_id → Character.season_id`; the aggregate
SHALL carry no `season_id` column of its own.

#### Scenario: Creating an outfit for a character

- **WHEN** `CreateOutfit { id, character_id, name, piece_ids }` is dispatched
- **THEN** the aggregate SHALL emit `OutfitCreated` with `variant_of = None`,
  `version = AggregateVersion::INITIAL`
- **AND** `OutfitView.season_id` SHALL resolve the character's season through
  the read-model join

#### Scenario: An outfit without a character is impossible

- **WHEN** the `OutfitAggregate` state or any `outfit` event is inspected
- **THEN** `character_id` SHALL be present and non-nullable

#### Scenario: Unknown character is rejected before dispatch

- **WHEN** `CreateOutfit` names a `character_id` that does not exist
- **THEN** the API edge SHALL answer 404 `character.not-found` and SHALL NOT
  dispatch the command

#### Scenario: Archived season blocks outfit mutation

- **WHEN** the character's season is archived and **any** outfit mutation is
  attempted — `CreateOutfit`, `CreateOutfitVariant`, `RenameOutfit`,
  `UpdateOutfitNotes`, `AddPieceToOutfit`, `RemovePieceFromOutfit`,
  photo link (`POST /v1/outfits/{id}/photos`) or photo unlink
  (`DELETE /v1/outfits/{id}/photos/{photo_id}`)
- **THEN** the API edge SHALL answer 409 `season.archived` before dispatch and
  SHALL NOT write an event
- **AND** the gate SHALL be shared by all eight mutation routes (one helper),
  never re-implemented per handler

#### Scenario: Archived seasons stay readable

- **WHEN** `GET /v1/outfits/{id}` or `GET /v1/characters/{id}/outfits` is
  requested for an outfit of an archived season
- **THEN** the read SHALL answer 200 (issue #533: the archive is terminal for
  **mutations**, not for the inventory)
- **AND** the archived check SHALL therefore live in the mutation gate only,
  never in the shared scope-resolution helper the reads use

#### Scenario: Archived season refuses the AI outfit step and keeps the piece

- **WHEN** the AI script-apply drives a wardrobe row (the apply's costume
  plan: piece + outfit) whose target season is archived
- **THEN** steps 1 and 2 (`CreatePiece`, `UpdatePieceNotes`) SHALL still run
  and the piece SHALL remain in the fundus, visible and correctable
- **AND** the outfit step SHALL be refused: the mapping row SHALL end as
  `refused` with reason `BindingRejected`, and **no** `OutfitCreated` event
  SHALL be appended
- **AND** a season-lookup **outage** SHALL NOT be treated as a refusal — it
  fails the whole apply so the retry re-drives the unfinished rows

### Requirement: An outfit may be created as an empty shell

`CreateOutfit` SHALL accept an empty `piece_ids` list. Named looks (`"Outfit
1: Büro"`, `"OP-Kleidung"`) are routinely established — and photographed —
before the individual garments are catalogued. The outfit name SHALL be
required and non-blank (422 `outfit.validation` on violation).

#### Scenario: Empty shell outfit

- **WHEN** `CreateOutfit { piece_ids: [] }` is dispatched
- **THEN** the aggregate SHALL emit `OutfitCreated` with an empty
  `piece_ids` and the read model SHALL list the outfit with zero pieces

#### Scenario: Blank outfit name is rejected

- **WHEN** `CreateOutfit { name: "" }` or `RenameOutfit { name: "  " }` is
  dispatched
- **THEN** the command SHALL fail with `OutfitError::EmptyName`
- **AND** the HTTP surface SHALL answer 422 `outfit.validation` with no event
  written

### Requirement: Layering is explicitly permitted

An `Outfit` SHALL impose **no** uniqueness constraint on
`Piece.category_id`. Multiple pieces of the same category (e.g. T-shirt +
dress shirt + sweater = three `Oberteil`, or several `Accessoires`) SHALL be
accepted and preserved in insertion order.

#### Scenario: Two pieces of the same category

- **WHEN** two pieces whose category is `Oberteil` are added to one outfit
- **THEN** both SHALL be accepted and `OutfitView.piece_ids` SHALL contain
  both

#### Scenario: Adding the same piece twice is a no-op

- **WHEN** `AddPieceToOutfit` names a `piece_id` already in `piece_ids`
- **THEN** the aggregate SHALL emit no event and the command SHALL succeed
  with the unchanged version

#### Scenario: Removing an absent piece is a no-op

- **WHEN** `RemovePieceFromOutfit` names a `piece_id` not in `piece_ids`
- **THEN** the aggregate SHALL emit no event and the command SHALL succeed
  with the unchanged version

#### Scenario: Unknown piece is rejected before dispatch

- **WHEN** `AddPieceToOutfit` (or `CreateOutfit`) names a `piece_id` that
  does not exist
- **THEN** the API edge SHALL answer 404 `piece.not-found` with no event
  written

### Requirement: Outfit variants are copy-on-write clones

`CreateOutfitVariant { id, source_outfit_id, character_id, name, piece_ids,
notes }` SHALL create a **new, independent** `OutfitAggregate` stream and
emit exactly one `OutfitVariantCreated { id, source_outfit_id, character_id,
name, piece_ids, notes, version }` with `variant_of = Some(source_outfit_id)`.
The source's identity, character and piece list SHALL be resolved at the
**API edge** from `OutfitRepository` (the only legitimate read-model
consumer per the CQRS boundary) and carried in the command — neither the
aggregate nor its command adapter SHALL query the source outfit. Subsequent
mutations of the variant SHALL NOT affect the source outfit, and scenes
referencing the source SHALL keep referencing it.

#### Scenario: Forking an outfit

- **WHEN** a client POSTs a variant request for source outfit S with a new
  name and an adjusted piece list
- **THEN** the new stream SHALL emit `OutfitVariantCreated` carrying
  `variant_of = Some(S)`
- **AND** the new outfit SHALL be listed independently with its own version

#### Scenario: Editing the variant leaves the source untouched

- **WHEN** `AddPieceToOutfit` targets the variant
- **THEN** the source outfit's `piece_ids` and version SHALL be unchanged
- **AND** every `SceneOutfitBeat` referencing the source SHALL continue to
  resolve to the source

#### Scenario: Variant creation never queries the read model on the write side

- **WHEN** the `OutfitCommands` adapter dispatches `CreateOutfitVariant`
- **THEN** it SHALL NOT call `OutfitRepository`
- **AND** the `cqrs-boundary` ast-grep job SHALL pass

### Requirement: Outfit notes, name and photos are editable

`RenameOutfit`, `UpdateOutfitNotes`, `LinkOutfitPhoto` and
`UnlinkOutfitPhoto` SHALL emit `OutfitRenamed`, `OutfitNotesUpdated`,
`OutfitPhotoLinked`, `OutfitPhotoUnlinked` respectively, each advancing the
version by exactly one. Photo link/unlink SHALL be idempotent no-ops on
repeat/absence. Linking a photo to an outfit MAY additionally link the same
`PhotoId` to the outfit's current pieces (shared fitting photos, capability
`piece-fundus`).

#### Scenario: Renaming an outfit

- **WHEN** `RenameOutfit` carries a non-blank name
- **THEN** the aggregate SHALL emit `OutfitRenamed` and the projection SHALL
  reflect the new name after catch-up

#### Scenario: Linking a fitting photo to outfit and pieces

- **WHEN** a photo is uploaded with `PhotoBinding::Outfit { outfit_id }`
- **THEN** `LinkOutfitPhoto` SHALL be dispatched for the outfit
- **AND** the handler MAY additionally dispatch `LinkPiecePhoto` for each
  piece currently in the outfit

### Requirement: Photo deletion reference counting spans outfits and pieces

`PhotoDeletionSaga` SHALL resolve the reference count of a photo across the
`Outfit` and `Piece` streams (in addition to `SceneShoot` continuity
references) before dispatching `DeletePhoto`. While any reference remains,
deletion SHALL be skipped; only a combined reference count of `0` SHALL
delete the photo.

#### Scenario: Photo still referenced by a piece

- **WHEN** a deletion is requested for a photo linked to an outfit and to one
  of that outfit's pieces
- **THEN** the saga SHALL observe two references and SHALL NOT dispatch
  `DeletePhoto`
- **AND** after both unlinks the saga SHALL delete the photo on the next
  request

#### Scenario: PhotoReferenceExpired covers both stream categories

- **WHEN** the saga checks expiry for photo P
- **THEN** it SHALL query the `outfit` and `piece` reference tables and SHALL
  treat a projection miss as "reference unknown" rather than as zero

### Requirement: Outfit projection schema

The read model SHALL use `projection_outfit` (`id`, `character_id`, `name`,
`variant_of`, `notes`, `version`, `updated_at`), `projection_outfit_piece`
(PK `(outfit_id, piece_id)`, plus a `position` column preserving insertion
order), and `projection_outfit_photo` (PK `(outfit_id, photo_id)`).
`projection_outfit_piece` SHALL NOT hold a foreign key to
`projection_piece` — stream replay order is not guaranteed and a missing
piece row must never poison the projector. The projector SHALL be
version-guarded and idempotent on redelivery.

#### Scenario: Projection schema

- **WHEN** the outfit projection schema is inspected
- **THEN** `projection_outfit` SHALL carry `character_id`, `name`,
  `variant_of`, `notes`, `version`, `updated_at`
- **AND** `projection_outfit_piece` SHALL carry `position` and no FK to
  `projection_piece`

#### Scenario: Idempotent piece rows

- **WHEN** `OutfitPieceAdded` is redelivered
- **THEN** `projection_outfit_piece` SHALL hold exactly one row for that
  `(outfit_id, piece_id)`

#### Scenario: Outfits are listed per character

- **WHEN** a query lists outfits for `character_id = C`
- **THEN** the read model SHALL answer from `projection_outfit` filtered by
  `character_id` without a table scan

### Requirement: Outfit HTTP surface

The API SHALL expose:

| Route | Command / Query |
|---|---|
| `POST /v1/outfits` | `CreateOutfit` |
| `POST /v1/outfits/{id}/variants` | `CreateOutfitVariant` (source resolved at the edge) |
| `GET /v1/outfits/{id}` | `OutfitRepository::find_by_id` |
| `GET /v1/characters/{character_id}/outfits` | `OutfitRepository::list_by_character` |
| `PATCH /v1/outfits/{id}/name` | `RenameOutfit` |
| `PATCH /v1/outfits/{id}/notes` | `UpdateOutfitNotes` |
| `POST/DELETE /v1/outfits/{id}/pieces[/{piece_id}]` | `AddPieceToOutfit` / `RemovePieceFromOutfit` |
| `POST/DELETE /v1/outfits/{id}/photos[/{photo_id}]` | photo link/unlink |

Handlers operating on an outfit SHALL resolve the owning character's season
and apply the costume-department authorization policy **inside** the handler
(`// AUTHZ-GATE:`), returning 403 on denial.

#### Scenario: Creating an outfit over HTTP

- **WHEN** an authorized user POSTs `{ character_id, name, piece_ids }` to
  `/v1/outfits`
- **THEN** the response SHALL be 201 with `{ id, version }`
- **AND** a subsequent `GET /v1/characters/{character_id}/outfits` SHALL list
  it

#### Scenario: Outfit handlers are authorized in-handler

- **WHEN** an authenticated user without a costume-department role in the
  character's season targets any outfit route
- **THEN** the handler SHALL answer 403 and SHALL dispatch no command
- **AND** a reviewer `grep` for `AUTHZ-GATE` SHALL find the annotation on
  every new outfit handler

### Requirement: Outfit problem codes

The registry SHALL expose `outfit.not-found` (404) and `outfit.validation`
(422), each with a Fluent message in every shipped locale. Piece-related
failures inside outfit commands SHALL reuse `piece.not-found`.

#### Scenario: Unknown outfit

- **WHEN** a request names an outfit id that does not exist
- **THEN** the response SHALL be 404 `outfit.not-found`

#### Scenario: Invalid outfit request

- **WHEN** a name or version is structurally invalid
- **THEN** the response SHALL be 422 `outfit.validation`
