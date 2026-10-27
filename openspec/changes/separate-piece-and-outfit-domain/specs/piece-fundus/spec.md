<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go)

## ADDED Requirements

### Requirement: Piece is a scope-free fundus aggregate

A `PieceAggregate` (stream category `"piece"`, replacing the former
`CostumeAggregate`/`"costume"` stream) SHALL represent exactly one garment in
the wardrobe fundus. It SHALL carry `id: Uuid` (UUIDv7), `name: String`,
`category_id: Option<CostumeCategoryId>`, `seasons: Vec<SeasonId>`,
`details: Vec<PieceDetail>`, `photos: Vec<Uuid>`, `notes: String`, and
`version: AggregateVersion`. It SHALL NOT carry `character_id` — a piece
belongs to the fundus, never to a character; the character binding now lives
exclusively on `Outfit` (capability `outfit-management`).

`PieceCreated` SHALL carry `id`, `name`, `category_id`, `season_id:
Option<Uuid>` (the optional initial repertoire season), `notes`, `details`,
`photos`, and `version`. No legacy `Costume*` event SHALL be replayed or
aliased — the cut is clean because no production streams exist yet.

#### Scenario: Creating a named piece

- **WHEN** a `CreatePiece { id, name, category_id, season_id }` command is
  dispatched to an empty `"piece"` stream
- **THEN** the aggregate SHALL emit `PieceCreated` carrying the given `name`
  and `version = AggregateVersion::INITIAL`
- **AND** the aggregate state SHALL carry `seasons` either empty (no
  `season_id`) or containing exactly that one `SeasonId`

#### Scenario: A piece carries no character binding

- **WHEN** a `PieceCreated` event or the `PieceAggregate` state is inspected
- **THEN** it SHALL contain no `character_id` field

#### Scenario: Legacy costume streams are not replayed

- **WHEN** the store still contains streams of the retired `"costume"`
  category
- **THEN** the piece projector SHALL NOT subscribe to them and no piece
  projection row SHALL be written for them
- **AND** no deserialization error SHALL surface (the streams are inert, not
  poisoned events)

### Requirement: A piece name is required and non-blank

`CreatePiece` and `RenamePiece` SHALL reject a `name` that is empty or
consists only of whitespace with 422 `piece.validation`; no event SHALL be
emitted. Names are stored verbatim (surrounding whitespace trimmed, interior
whitespace preserved) and are **not** unique within a season — two identical
garments are a legitimate fundus state.

#### Scenario: Blank name is rejected

- **WHEN** `CreatePiece { name: "   " }` is dispatched
- **THEN** the command SHALL fail with `PieceError::EmptyName` and the HTTP
  surface SHALL answer 422 `piece.validation`
- **AND** no event SHALL be emitted

#### Scenario: Duplicate names are allowed

- **WHEN** two pieces with the identical name are created in the same season
- **THEN** both commands SHALL succeed and both pieces SHALL be listed

#### Scenario: Renaming a piece

- **WHEN** a `RenamePiece { id, name, version }` command targets an existing
  piece with a non-blank name
- **THEN** the aggregate SHALL emit `PieceRenamed { id, name, version }` and
  the version SHALL advance by exactly one

### Requirement: A piece belongs to at most one category

A `Piece` SHALL belong to at most one `CostumeCategory` (n:1). The binding is
set or cleared via `SetPieceCategory { id, category_id, season_id,
project_id, version }`, emitting exactly one `PieceCategorySet { id,
category_id, version }`; `category_id: None` clears it. Re-dispatching the
value the piece already carries SHALL be a state-based no-op (no event,
`Ok`). Because `Piece` is season-repertoire-scoped while `CostumeCategory` is
season-scoped, the invariant `category.season_id ∈ piece.seasons` SHALL be
pre-checked at the **API edge before dispatch**: unknown category → 404
`costume-category.not-found`, archived category → 409
`costume-category.archived`, foreign season → 409
`costume-category.season-mismatch` (extension `category_id`). There is no
projection unique constraint for this invariant; the projector resolves
`category_name` best-effort (`None` on a projection miss) and never fails the
event.

#### Scenario: Setting a category from a repertoire season

- **WHEN** `SetPieceCategory` targets a piece whose `seasons` contains the
  category's season
- **THEN** the aggregate SHALL emit `PieceCategorySet { id, category_id,
  version }` with the version incremented by exactly one

#### Scenario: Foreign-season category is rejected before dispatch

- **WHEN** the category's `season_id` is not in `piece.seasons`
- **THEN** the API edge SHALL answer 409 `costume-category.season-mismatch`
  with the `category_id` extension
- **AND** no command SHALL be dispatched and no event written

#### Scenario: Re-setting the current category is a no-op

- **WHEN** `SetPieceCategory` carries the `category_id` the piece already
  carries
- **THEN** the aggregate SHALL emit no event and the command SHALL succeed
  with the unchanged version

### Requirement: Piece repertoire is idempotent aggregate state

`PieceAggregate.seasons` SHALL be real aggregate state seeded from
`PieceCreated.season_id` (absent ⇒ empty list). `AddPieceToSeason` /
`RemovePieceFromSeason` SHALL emit `PieceAddedToSeason` /
`PieceRemovedFromSeason` only on an actual state change; a repeated add or an
absent remove SHALL be a no-event success returning the unchanged version. An
empty repertoire is legitimate. Season existence (404 `season.not-found`) and
archived state (409 `season.archived`) SHALL be pre-checked at the API edge.

#### Scenario: Adding a season twice emits one event

- **WHEN** `AddPieceToSeason` for season S is dispatched twice
- **THEN** exactly one `PieceAddedToSeason` SHALL be recorded
- **AND** the second dispatch SHALL succeed with the unchanged version

#### Scenario: Removing an absent season is a no-op

- **WHEN** `RemovePieceFromSeason` targets a season not in the repertoire
- **THEN** no event SHALL be emitted and the command SHALL succeed

### Requirement: Piece details are pure descriptions

`PieceDetail` SHALL carry `id: Uuid`, `subject: Option<String>`, and `text:
String`. Details are added, updated and removed via `AddPieceDetail`,
`UpdatePieceDetail` and `RemovePieceDetail`; `PieceDetailUpdated` SHALL carry
the **full** detail (not a patch). An unknown `detail_id` SHALL answer 404
`piece-detail.not-found` — a code distinct from `piece.validation` so a
client can tell a stale row apart from a malformed request.

#### Scenario: Adding a description detail

- **WHEN** `AddPieceDetail { detail: { subject: Some("Rote Jacke"), text:
  "Knöpfe vorne" } }` is dispatched
- **THEN** the aggregate SHALL emit `PieceDetailAdded` carrying that detail
- **AND** (`piece_id`, `detail_id`) SHALL be the projection's primary key

#### Scenario: Updating an unknown detail

- **WHEN** `UpdatePieceDetail` / `RemovePieceDetail` names a `detail_id` the
  aggregate does not hold
- **THEN** the command SHALL fail and the HTTP surface SHALL answer 404
  `piece-detail.not-found`

### Requirement: Piece photos include photos taken of its outfits

A `Piece` SHALL link photos via `PiecePhotoLinked` / `PiecePhotoUnlinked`.
Because garments are usually photographed as part of an outfit fitting,
`PieceView` SHALL additionally surface photos linked to any `Outfit` that
contains this piece (`projection_outfit_piece ⋈ projection_outfit_photo`),
deduplicated by photo id against the directly linked piece photos. A photo
that is linked both directly and via an outfit SHALL appear exactly once in
`PieceView.photos`.

#### Scenario: Outfit photo appears on the piece

- **WHEN** a photo is linked to an outfit that contains piece P and not
  linked to P directly
- **THEN** `GET /v1/pieces/{P}` SHALL include that photo exactly once

#### Scenario: Direct and outfit link do not duplicate

- **WHEN** the same photo is linked both to piece P and to an outfit
  containing P
- **THEN** `PieceView.photos` SHALL contain it exactly once
- **AND** unlinking one of the two references SHALL NOT remove it from
  `PieceView.photos`

### Requirement: Piece projection schema

The read model SHALL use `projection_piece` (`id`, `name`, `category_id`,
`category_name`, `notes`, `version`, `updated_at`), `projection_piece_season`
(PK `(piece_id, season_id)`), `projection_piece_detail` (PK `(piece_id,
detail_id)`), and `projection_piece_photo` (PK `(piece_id, photo_id)`). No
`projection_piece` row SHALL carry a `character_id` column. The projector
SHALL be version-guarded (`WHERE version < $N`) and idempotent on redelivery.

#### Scenario: Projection schema carries no character binding

- **WHEN** the piece projection schema is inspected
- **THEN** `projection_piece` SHALL expose `name`, `category_id`,
  `category_name`, `notes`, `version`, `updated_at`
- **AND** it SHALL NOT expose a `character_id` column

#### Scenario: Redelivered events do not duplicate rows

- **WHEN** the same `PieceDetailAdded` event is processed twice
- **THEN** `projection_piece_detail` SHALL hold exactly one row for that
  `(piece_id, detail_id)`

### Requirement: Piece HTTP surface

The API SHALL expose the fundus under `/v1/pieces`:

| Route | Command / Query | Gate |
|---|---|---|
| `POST /v1/pieces` | `CreatePiece` | AUTHZ-GATE `authorize_piece_scoped` |
| `GET /v1/pieces/{id}` | `PieceRepository` | AUTHZ-GATE `authorize_piece_scoped` |
| `GET /v1/seasons/{season_id}/pieces` | repertoire listing | block-membership middleware |
| `PATCH /v1/pieces/{id}/name` | `RenamePiece` | AUTHZ-GATE |
| `PATCH /v1/pieces/{id}/notes` | `UpdatePieceNotes` | AUTHZ-GATE |
| `POST /v1/pieces/{id}/category` | `SetPieceCategory` | AUTHZ-GATE |
| `POST/DELETE /v1/pieces/{id}/seasons[/{season_id}]` | repertoire | AUTHZ-GATE |
| `POST /v1/pieces/{id}/details`, `PATCH/DELETE /v1/pieces/{id}/details/{detail_id}` | detail commands | AUTHZ-GATE |
| `POST/DELETE /v1/pieces/{id}/photos[/{photo_id}]` | photo link/unlink | AUTHZ-GATE |

Every handler NOT covered by the block-membership middleware SHALL carry an
`// AUTHZ-GATE:` comment and call the costume-department policy in its body
(403 on denial). The former `/v1/costumes*` routes SHALL be removed — no
alias, no deprecation window.

#### Scenario: Creating a piece over HTTP

- **WHEN** an authorized user POSTs `{ name, category_id, season_id }` to
  `/v1/pieces`
- **THEN** the response SHALL be 201 with `{ id, version }`
- **AND** the projector SHALL reflect the piece after catch-up

#### Scenario: Former costume routes are gone

- **WHEN** a client requests any retired `/v1/costumes*` route
- **THEN** the API SHALL answer 404 — no handler SHALL remain

#### Scenario: Authorisation is enforced in the handler

- **WHEN** an authenticated user without a costume-department role in the
  piece's season calls any `/v1/pieces/{id}*` mutation
- **THEN** the handler SHALL answer 403 and SHALL dispatch no command

### Requirement: Piece carries no production-scope column

A `Piece` SHALL NOT reference any production-level scope column
(`ProjectId`, `SeasonId`, `BlockId`, `EpisodeId`) and SHALL NOT reference a
`character_id`. Its only scope relation SHALL be the season **repertoire**
(`seasons: Vec<SeasonId>`), which decides in which seasons' wardrobe lists
the piece appears. Filtering pieces by production level SHALL happen in the
read model by joining `projection_piece_season` — never by a scope column on
the piece itself. This holds for AI-imported pieces as well: the import path
SHALL NOT introduce a scope column on the piece, and an imported piece SHALL
be reachable through exactly the same queries as a manually created one. An
imported piece is deliberately left **uncategorised** (the import chain never
dispatches `SetPieceCategory`); users categorise it later.

Per-scene casting is a **scene-side** relation (`SceneOutfitBeat`, capability
`scene-costume-assignment`), and the character binding is an **outfit-side**
relation (capability `outfit-management`) — neither is a field on the piece.

#### Scenario: Filtering pieces by season

- **WHEN** a query requests all pieces of a given Season
- **THEN** the read model SHALL resolve them through `projection_piece_season`
- **AND** the `Piece` aggregate, its events, and `projection_piece` SHALL
  carry no season, project, block, episode or character column

#### Scenario: An AI-imported piece is listed like a manual one

- **WHEN** a piece created by an AI import has been written to its stream
- **THEN** it SHALL appear in the same season-scoped piece query as a
  manually created piece
- **AND** it SHALL carry no additional field identifying its import origin
  and no category (categorisation is a later, explicit user action)

### Requirement: Piece problem codes replace the costume codes

The problem-code registry SHALL expose `piece.not-found` (404),
`piece.validation` (422), `piece-detail.not-found` (404), and
`piece.container-unresolved` (409) in place of the retired `costume.*` /
`costume-detail.*` entries. `costume-category.*` codes SHALL remain
unchanged. Each code SHALL have a Fluent entry in every shipped locale.

#### Scenario: Unknown piece answers a registered problem

- **WHEN** a request names a piece id that does not exist
- **THEN** the response SHALL be `application/problem+json` with code
  `piece.not-found`
- **AND** the retired code `costume.not-found` SHALL NOT be produced anywhere

#### Scenario: Every new code is localised

- **WHEN** the locales are compiled
- **THEN** each locale SHALL provide a `problem-piece-*` message for every
  registered piece code (missing message ⇒ build/test failure)
