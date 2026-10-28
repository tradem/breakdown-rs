<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

## MODIFIED Requirements

### Requirement: Idempotent upsert apply via user-driven mapping
Applying a preview SHALL dispatch existing commands
(`CreateScene`/`UpdateSceneDetails`, `CreateCharacter`/`Assign…`,
`CreatePiece`/`SetPieceCategory`/`UpdatePieceNotes`,
`CreateOutfit`/`AddPieceToOutfit`/`UpdateOutfitNotes`,
`CreateShootingDay`, `ScheduleSceneOnShootingDay`, `PlanSceneShoot` with
`source: AiExtracted`). Each draft row SHALL require an explicit user decision
(new vs update-existing-`#id`) — there SHALL be no automatic fuzzy matching in
v1. A persisted `projection_ai_import_mapping(preview_id, draft_ref,
aggregate_kind, aggregate_id)` SHALL make re-applying the same preview
idempotent: mapped rows dispatch `Update…` (no-op if unchanged); unmapped rows
dispatch `Create…` + a mapping write. Re-import of an updated document SHALL
re-suggest mappings from the prior projection for the user to confirm. No
matching state SHALL live on Scene/Character/ShootingDay/SceneShoot/Piece/Outfit
aggregates.

A draft row that carries outfits SHALL additionally apply each accepted outfit as
the wardrobe the reviewer sees: first its constituent `Piece`s in the season's
fundus, then the `Outfit` bound to the `Character` identified by that outfit's
character name, then the scene relation. Each piece SHALL be dispatched as
`CreatePiece` (seeded into the season's repertoire), optionally followed by
`SetPieceCategory` when the piece's `category_hint` matches, case-insensitively,
an active category of the target season, and optionally by `UpdatePieceNotes`
carrying the piece's extracted description. The `Outfit` SHALL then be dispatched
as `CreateOutfit` with the character id and the id list of the pieces created for
that outfit, carrying the outfit's name and its extracted notes. The
season's category vocabulary SHALL be resolved at the API edge and passed into
the pure apply planner — the write side SHALL NOT query the category projection
(CQRS boundary).

A draft row's scene relation SHALL be persisted (issue #546 §5.8): after the
row's scene step, the apply SHALL dispatch `AssignCharacter` for every figure of
the row on the row's scene stream — before any beat of that row — and then
`AddOutfitBeat` for every accepted outfit, in the outfit's plan order, grouped
per figure. A beat SHALL only be attempted for an outfit whose piece and outfit
chain fully succeeded (all pieces created, outfit created); an outfit that was
dropped as ungrounded SHALL never surface as a beat attempt. Beat mapping rows
SHALL use `aggregate_kind = 'scene_outfit_beat'`, be addressed by the figure's
preview-wide mapping reference as `draft_ref` (the same reference the `character`
rows use) with `ordinal` = the outfit's per-figure position 0..n-1 from the
plan-order re-grouping, and carry the scene aggregate id — per-figure position,
not the row-flat outfit ordinal, because two figures of one row would otherwise
share one mapping row and the second figure's first beat would silently never be
applied.

The scene-stream version SHALL be maintained jointly by the row's `scene` mapping
row and its `scene_outfit_beat` rows: both kinds hold versions of the SAME
aggregate stream, so a reader recovering the stream version SHALL take the maximum
across all of the row's rows, and confirms SHALL stay only-moves-forward so a late
duplicate can never roll a confirmed phase back. Every step of the chain
(`CreateScene` → `AssignCharacter`×n → `AddOutfitBeat`×m) SHALL append exactly one
event. Re-applying the same preview SHALL NOT add a second beat: a confirmed
`scene_outfit_beat` row skips the dispatch. The reviewer report SHALL distinguish
an outfit dropped as ungrounded (never created) from an outfit whose scene
relation could not be established (the outfit exists, but `AddOutfitBeat` was
refused) — the two SHALL NOT be reported with the same reason.

A figure SHALL be deduplicated across the WHOLE preview by a normalised name
identity (trimmed, case-folded, internal whitespace collapsed), not per draft row,
and SHALL be keyed in the mapping as an `aggregate_kind = 'character'` row
addressed by that identity. Keying characters per row was rejected: a live
93-page import named 268 figure mentions over 131 scenes, so per-row creation
would have produced hundreds of duplicate `Character` aggregates and destroyed
costume continuity. Outfit rows SHALL stay keyed PER ROW by
`(preview_id, draft_ref, outfit_ordinal)` with `aggregate_kind = 'outfit'`, so that
two outfits of one figure in one scene remain distinct rows and re-apply remains
idempotent. Piece rows SHALL be keyed PER ROW by
`(preview_id, draft_ref, piece_ordinal)` with `aggregate_kind = 'piece'`, where
`piece_ordinal` is the row-flat position across the outfits' piece lists, so two
identically named pieces of one row (e.g. two figures in `OP-Schuhe`) never
collapse into one aggregate. An outfit row SHALL NOT be created when its character
was skipped or could not be resolved; that case SHALL be surfaced to the reviewer
instead of creating an unbindable outfit.

#### Scenario: Crash mid-apply is safely retried
- **WHEN** an apply crashes after creating scenes 1–5 and is retried
- **THEN** the retry checks the mapping per row
- **AND** rows 1–5 dispatch `Update…` (no duplicate `CreateScene`)
- **AND** remaining rows dispatch `Create…` + mapping writes

#### Scenario: Apply reuses existing command validation
- **WHEN** a draft row maps to an existing scene and is applied
- **THEN** the dispatched `UpdateSceneDetails` command runs through the existing
  Scene aggregate validation and optimistic-concurrency check
- **AND** `project_id` is resolved at the API edge (no write-side projection
  lookup; CQRS boundary respected)

#### Scenario: Applying a row that carries outfits
- **WHEN** a draft row is accepted and carries two outfits for figures the
  preview also created
- **THEN** each outfit's pieces SHALL be dispatched as `CreatePiece` (with
  `SetPieceCategory` for a matched hint) before the outfit itself
- **AND** each outfit SHALL be dispatched as `CreateOutfit` carrying its
  figure's `character_id` and its own piece ids
- **AND** each outfit row SHALL be persisted in the mapping with
  `aggregate_kind = 'outfit'` and its own ordinal, and each piece row with
  `aggregate_kind = 'piece'` and its own ordinal
- **AND** re-applying the same preview SHALL skip all of them (no duplicates)

#### Scenario: A category hint is resolved against the season vocabulary
- **WHEN** an extracted piece carries `category_hint = "Oberteil"` and the
  target season has an active category named `Oberteil`
- **THEN** the apply SHALL dispatch `SetPieceCategory` with that category's id
- **AND** the plan SHALL have carried the id from the API edge, never from a
  write-side projection read

#### Scenario: An unknown category hint leaves the piece uncategorized
- **WHEN** an extracted piece carries a `category_hint` matching no active
  category of the target season
- **THEN** the piece SHALL be created with no category
- **AND** the apply SHALL NOT fail or report the outfit as unapplied

#### Scenario: The apply persists the scene relation as ordered beats
- **WHEN** an accepted draft row names two figures and carries one outfit for
  each
- **THEN** the apply SHALL dispatch `AssignCharacter` for both figures on the
  row's scene stream before any beat
- **AND** each outfit SHALL be dispatched as `AddOutfitBeat` on the scene stream
  after its outfit is created, in plan order
- **AND** each beat SHALL be persisted as a `scene_outfit_beat` mapping row
  addressed by the figure's mapping reference and its per-figure position,
  carrying the scene aggregate id

#### Scenario: Re-applying a preview adds no second beat
- **WHEN** an apply that already added an outfit beat to a scene is retried
- **THEN** the confirmed `scene_outfit_beat` mapping row SHALL skip the
  `AddOutfitBeat` dispatch
- **AND** the scene SHALL NOT carry a duplicate beat

#### Scenario: The scene chain appends exactly one event per step
- **WHEN** a draft row with two figures and two outfits is applied
- **THEN** the scene stream SHALL carry exactly one event per chain step:
  create, one assign per figure, one beat per outfit
- **AND** the mapping rows SHALL record the scene-stream version after every
  confirmed step, so a retry re-drives only the steps above the stored version

#### Scenario: An outfit beat that cannot be added is reported distinctly
- **WHEN** `AddOutfitBeat` is refused for an outfit whose chain succeeded
  (e.g. a concurrent manual edit removed the figure from the scene)
- **THEN** the reviewer report SHALL surface the outfit with a reason distinct
  from the plan-time ungrounded drop
- **AND** an outfit dropped as ungrounded SHALL never be reported as a beat
  failure, and vice versa

#### Scenario: One figure mentioned in many rows becomes one aggregate
- **WHEN** a preview names the same figure, in differing case or spacing, across
  several draft rows
- **THEN** exactly one `Character` SHALL be created for that identity
- **AND** the outfits of every row SHALL bind to that single `Character`
- **AND** a second apply of the same preview SHALL create no additional
  `Character`

#### Scenario: A crash between piece and outfit steps resumes above the stored version
- **WHEN** an apply crashes after creating a piece but before `CreateOutfit`
- **THEN** the piece mapping row SHALL carry the version the piece reached
- **AND** the retry SHALL re-drive only the steps above that version
- **AND** the piece SHALL NOT be created a second time

#### Scenario: A reviewer rejects one outfit but keeps its scene
- **WHEN** the reviewer marks a single extracted outfit as not accepted while
  accepting the draft row's scene
- **THEN** the scene SHALL still be applied
- **AND** no `Piece` and no `Outfit` SHALL be created for the rejected row
- **AND** the request SHALL carry the rejection by outfit ordinal only

#### Scenario: A pre-rename client's rejection is still honoured
- **WHEN** a client written before this change sends its per-row decisions under
  the former `costume_decisions` key
- **THEN** the server SHALL read them as `outfit_decisions` (same `{ordinal,
  accepted}` item shape)
- **AND** a rejected row SHALL NOT be applied, because silently defaulting an
  unread decision to "accepted" would apply exactly what the reviewer refused

#### Scenario: A dropped outfit does not block the apply
- **WHEN** a preview carries an outfit the server dropped during grounding
- **THEN** the uncertainty SHALL be visible to the reviewer
- **AND** it SHALL NOT block applying the preview, because a stored preview is
  immutable and offers no way to dismiss it; blocking on it would make one bad
  outfit reject an entire paid import

#### Scenario: Outfit whose character was skipped
- **WHEN** a draft row is accepted for its scene but the character the outfit
  belongs to was skipped by the user
- **THEN** no `Piece` and no `Outfit` SHALL be created for that outfit
- **AND** the apply result SHALL report the outfit as not applied, with the
  reason, instead of failing the whole row

### Requirement: The preview exposes extracted outfits for review
The script preview SHALL expose, per draft scene, the extracted outfits with their
character name, outfit name, constituent pieces (each with its name, optional
category hint and optional description) and quoted source text, and SHALL allow the
reviewer to accept, reject or map each outfit row independently of the scene row.
The reviewer interface SHALL show the quoted source fragment next to the extracted
outfit, so that a reviewer can verify the extraction against the script without
opening the document.

#### Scenario: Reviewing an extraction against its source
- **WHEN** a draft row shows an outfit "ölverschmierter Mechaniker-Overall"
- **THEN** the quoted fragment the extraction was based on SHALL be visible next
  to the outfit
- **AND** the reviewer can reject that outfit without rejecting the scene

#### Scenario: Reviewing a shorthand outfit's derived pieces
- **WHEN** a draft row shows an outfit extracted from `PATIENT (in KHK)`
- **THEN** the outfit's derived pieces SHALL be listed with their names and
  category hints
- **AND** the quoted fragment `in KHK` SHALL be visible next to the outfit, so
  the reviewer can tell the look was named and the pieces derived
