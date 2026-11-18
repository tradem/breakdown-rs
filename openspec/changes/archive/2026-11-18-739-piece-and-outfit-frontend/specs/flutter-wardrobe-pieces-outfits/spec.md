<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# flutter-wardrobe-pieces-outfits Delta

## ADDED Requirements

### Requirement: Piece Wardrobe Screens

The wardrobe screens SHALL operate on the `Piece` read model
(`PieceView` from `GET /v1/pieces*`): a season-scoped list of the fundus
garments and a piece detail with name, single optional category, season
repertoire, details, notes and photos. A piece SHALL NOT display, request
or infer a character binding — the aggregate has none, and the retired
`assign`/`unassign` affordances SHALL NOT exist anywhere in the UI. The
presentation code SHALL name the concept `Piece`/`Kleidungsstück`; the
`Costume*` identifiers, files and copy keys SHALL be gone from the
wardrobe feature (the `costumeCategory*` vocabulary identifiers are
exempt: the category aggregate did not split).

#### Scenario: List renders only fundus garments

- **WHEN** the season projection contains three pieces with categories
  `Oberteil`, `Schuhe` and none
- **THEN** the grid renders three tiles, each announcing its
  `PieceView.name` (never a UUID) and its category, with "Ohne Kategorie"
  for the uncategorised row, and no character name appears on any tile.

#### Scenario: No assignment affordance survives

- **WHEN** the piece detail is opened for a piece of the current season
- **THEN** the panel offers category, repertoire, details, notes and
  photos only — there is no "Zuweisen", "Neu zuweisen" or
  "Zuordnung entfernen" control and no request to a `/v1/costumes*` path
  is issued.

#### Scenario: Repertoire stays the piece's season scope

- **WHEN** the user adds the piece to a second season from the repertoire
  section
- **THEN** `POST /v1/pieces/{id}/seasons` is dispatched with the piece
  version echo and the repertoire row appears optimistically until the
  projection confirms it.

### Requirement: Outfit List per Character

The character detail screen SHALL show the character's outfits
(`GET /v1/characters/{character_id}/outfits`, Drift-cached per
character) as a section listing each look by its own `name`, its variant
lineage marker when `variant_of` is set, and its piece count, plus a
create affordance that dispatches `POST /v1/outfits` with the character
id and a non-blank name. An empty list SHALL render an honest empty state
with the create call to action, never a spinner left running.

#### Scenario: Looks are listed for the character

- **WHEN** the character has the outfits "Alltagslook Tag 1" (3 pieces)
  and "Alltagslook Tag 2" (a variant of the first, 3 pieces)
- **THEN** the section lists both rows with their names and piece counts,
  the second row carries the variant marker, and the order is the server
  order of the list route.

#### Scenario: Empty state offers creation

- **WHEN** the character has no outfits
- **THEN** the section shows the localized empty copy and the
  "Look erstellen" action, and creating a look with a blank name is
  blocked client-side by the disabled save affordance.

### Requirement: Outfit Detail Screen

The outfit detail screen SHALL manage one look: rename
(`PATCH /v1/outfits/{id}/name`), notes (`PATCH /v1/outfits/{id}/notes`),
ordered piece rows from `OutfitView.pieces` (sorted by `position`) with
add (`POST /v1/outfits/{id}/pieces`) and remove
(`DELETE /v1/outfits/{id}/pieces/{piece_id}` with the version echo),
variant lineage (`variant_of`, linking to the source look), fitting
photos via the outfit photo bindings, and a `Variante erstellen` action
that dispatches `POST /v1/outfits/{id}/variants` and navigates to the
fork. Every command SHALL apply the optimistic-after-2xx overlay and
clear it only when the refetched projection reaches the acknowledged
version (version fence); a failed refetch SHALL surface as an error, never
as a silently retained guess.

#### Scenario: Rename is optimistic and fenced

- **WHEN** the user renames the look to "OP" and the command is
  acknowledged with version 7 while the cached projection still carries
  version 6
- **THEN** the header shows "OP" with the reconciling indicator, and the
  overlay is dropped only after a refetch yields version ≥ 7.

#### Scenario: Pieces stay ordered and layering is allowed

- **WHEN** the look holds the pieces `[Hemd (0), Weste (1), Hemd-2 (2)]`
- **THEN** the rows render in exactly that `position` order, both shirts
  appear (layering is legal), and removing the middle row dispatches the
  remove command with the current outfit version without renumbering the
  remaining rows locally.

#### Scenario: Variant fork is independent

- **WHEN** the user creates a variant of a look and renames the fork
- **THEN** a new look with `variant_of` pointing at the source is opened,
  and the source look keeps its old name after the fork's rename is
  acknowledged.

#### Scenario: Join command is idempotent on the client

- **WHEN** a piece that the look already holds is added again
- **THEN** the optimistic overlay does not duplicate the row (the id-keyed
  list stays consistent) and the server no-op acknowledgement does not
  clear a pending row's fence.

### Requirement: Piece Outfit Navigation

Navigation between the two aggregates SHALL be explicit and
id-keyed: tapping a piece row in the outfit detail opens the piece detail
for that piece in the outfit's season, and the piece detail exposes the
entry to the characters' looks that reference it (via the character
detail's outfit section) without issuing a second projection call to fill
a command payload. Both pushes SHALL degrade gracefully when the target
row is missing from the local projection (honest fallback label, no UUID,
no crash).

#### Scenario: Piece row opens the garment

- **WHEN** the user taps the "Weste" row inside an outfit
- **THEN** the piece detail of that piece opens scoped to the outfit's
  season and back returns to the outfit detail.

#### Scenario: Missing piece row does not break the list

- **WHEN** an outfit references a piece id that is absent from the cached
  season projection
- **THEN** the row renders the joined `category_name` (or the generic
  fallback) and stays tappable to a not-found surface instead of throwing.

### Requirement: Wardrobe Copy and Terminology

All user-visible wardrobe copy SHALL come from the ARB catalogs (German
template plus complete English catalog) and use the glossary terms
`Kleidungsstück` / *piece* and `Look` / *outfit*; the term "Kostüm" SHALL
survive only where the domain keeps the word: the `costume-category`
vocabulary ("Kostüm-Kategorien"), the role/capability labels
("Kostüm-Rolle", `assign_costumes`) and the AI-import draft vocabulary.
`docs/design/glossary.md` and the screen specs SHALL list every new copy
key, and `de`/`en` key parity SHALL hold.

#### Scenario: Wardrobe copy names the right aggregate

- **WHEN** the wardrobe list, the piece detail and the outfit screens are
  read in the German locale
- **THEN** the list and detail speak of "Kleidungsstücke" and the
  character's composed looks of "Looks", while the category screen still
  says "Kostüm-Kategorien" and the role chip still says "Kostüm-Rolle".

#### Scenario: Copy parity is machine-checked

- **WHEN** `flutter gen-l10n` runs in CI with the parity check
- **THEN** every German key has an English counterpart and the
  untranslated report is empty, so no wardrobe string ships untranslated.

### Requirement: Piece and Outfit Photo Bindings

Photo upload, byte fetch and deletion SHALL use the split routes —
`/v1/pieces/{piece_id}/photos*` for garment photos and
`/v1/outfits/{outfit_id}/photos*` for fitting photos — through the
generated client surface, and SHALL NOT reference the retired
`/v1/costumes*` paths. Variant watching SHALL be one bounded-backoff
implementation generic over the enriched view, used by both the piece and
the outfit detail, terminating on the whole-pass terminal condition and
degrading to the manual-refresh affordance after the bounded budget.

#### Scenario: Piece upload hits the piece route

- **WHEN** a photo is captured on the piece detail
- **THEN** the upload posts to `/v1/pieces/{id}/photos` with the prepared
  bytes and the matching content type, and the returned variant set is
  watched until every variant is terminal.

#### Scenario: Outfit upload hits the outfit route

- **WHEN** a fitting photo is captured on the outfit detail
- **THEN** the upload posts to `/v1/outfits/{id}/photos`, the delete
  targets `/v1/outfits/{id}/photos/{photo_id}`, and the watch stops at
  the terminal condition instead of polling forever.

#### Scenario: Budget expiry keeps the row and offers refresh

- **WHEN** the bounded watch budget is exhausted while a variant is still
  `Pending`
- **THEN** the gallery renders the still-processing affordance with the
  manual refresh action and makes no further network call until the user
  re-subscribes.

### Requirement: Piece and Outfit Drift Cache

The offline cache SHALL hold the two projections in separate tables —
pieces (`name`, `category_id`/`category_name`, repertoire season ids,
details, photos) and outfits (`character_id`, `name`, `variant_of`, piece
refs with `position`, photos) — with the schema migration recorded in the
same change, snapshot-replace semantics per scope (season for pieces,
character for outfits), TTL staleness flags and no stale-row survival.
The retired costume snapshot tables SHALL NOT be reintroduced.

#### Scenario: Outfit slice is character-scoped

- **WHEN** the character's outfit list is refetched and the projection
  now holds two rows where the cache held three
- **THEN** the snapshot replace leaves exactly the two projected rows for
  that character, and another character's cached looks are untouched.

#### Scenario: Fetch failure keeps the stale slice

- **WHEN** the outfit list fetch fails with a Problem Details error
- **THEN** the cache is not mutated, the previously cached rows stay
  readable with the stale banner, and the screen surfaces the error with
  a retry affordance.
