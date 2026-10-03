<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3-flash (neuralwatt) -->

## MODIFIED Requirements

### Requirement: Idempotent upsert apply via user-driven mapping
Applying a preview SHALL dispatch existing commands
(`CreateScene`/`UpdateSceneDetails`, `CreateCharacter`/`Assign…`,
`CreateCostume`/`AssignCostumeToCharacter`,
`CreateShootingDay`, `ScheduleSceneOnShootingDay`, `PlanSceneShoot` with
`source: AiExtracted`). Each draft row SHALL require an explicit user decision
(new vs update-existing-`#id`) — there SHALL be no automatic fuzzy matching in
v1. A persisted `projection_ai_import_mapping(preview_id, draft_ref,
aggregate_kind, aggregate_id)` SHALL make re-applying the same preview
idempotent: mapped rows dispatch `Update…` (no-op if unchanged); unmapped rows
dispatch `Create…` + a mapping write. Re-import of an updated document SHALL
re-suggest mappings from the prior projection for the user to confirm. No
matching state SHALL live on Scene/Character/ShootingDay/SceneShoot/Costume
aggregates.

A draft row that carries costumes SHALL additionally apply each accepted
costume as a `Costume` bound to the `Character` identified by that costume's
character name, by dispatching the existing `CreateCostume`, then
`UpdateCostumeNotes` (which carries the extracted description —
`CreateCostume` has no description field), then `AssignCostumeToCharacter`.

A draft row's scene relation SHALL be persisted (issue #546 §5.8): after the
row's scene step, the apply SHALL dispatch `AssignCharacter` for every figure
of the row on the row's scene stream — before any beat of that row — and then
`AddCostumeBeat` for every accepted costume, in the costume's plan order,
grouped per figure. A beat SHALL only be attempted for a costume whose
`Costume` chain fully succeeded (created, noted, bound); a costume that was
dropped as ungrounded SHALL never surface as a beat attempt. Beat mapping rows
SHALL use `aggregate_kind = 'scene_costume_beat'`, be addressed by the
figure's preview-wide mapping reference as `draft_ref` (the same reference the
`character` rows use) with `ordinal` = the costume's per-figure position
0..n-1 from the plan-order re-grouping, and carry the scene aggregate id —
per-figure position, not the row-flat costume ordinal, because two figures of
one row would otherwise share one mapping row and the second figure's first
beat would silently never be applied.

The scene-stream version SHALL be maintained jointly by the row's `scene`
mapping row and its `scene_costume_beat` rows: both kinds hold versions of the
SAME aggregate stream, so a reader recovering the stream version SHALL take the
maximum across all of the row's rows, and confirms SHALL stay only-moves-
forward so a late duplicate can never roll a confirmed phase back. Every step
of the chain (`CreateScene` → `AssignCharacter`×n → `AddCostumeBeat`×m) SHALL
append exactly one event. Re-applying the same preview SHALL NOT add a second
beat: a confirmed `scene_costume_beat` row skips the dispatch. The reviewer
report SHALL distinguish a costume dropped as ungrounded (never created) from
a costume whose scene relation could not be established (the `Costume` exists
and is bound, but `AddCostumeBeat` was refused) — the two SHALL NOT be
reported with the same reason.

A figure SHALL be deduplicated across the WHOLE preview by a normalised name
identity (trimmed, case-folded, internal whitespace collapsed), not per draft
row, and SHALL be keyed in the mapping as an `aggregate_kind = 'character'` row
addressed by that identity. Keying characters per row was rejected: a live
93-page import named 268 figure mentions over 131 scenes, so per-row creation
would have produced hundreds of duplicate `Character` aggregates and destroyed
costume continuity. Costume rows SHALL stay keyed PER ROW by
`(preview_id, draft_ref, costume_ordinal)` with `aggregate_kind = 'costume'`, so
that two costumes of one figure in one scene remain distinct rows and re-apply
remains idempotent. A costume row SHALL NOT be created when its character was
skipped or could not be resolved; that case SHALL be surfaced to the reviewer
instead of creating an unbindable costume.

#### Scenario: Crash mid-apply is safely retried
- **WHEN** an apply crashes after creating scenes 1–5 and is retried
- **THEN** the retry checks the mapping per row
- **AND** rows 1–5 dispatch `Update…` (no duplicate `CreateScene`)
- **AND** remaining rows dispatch `Create…` + mapping writes

#### Scenario: Apply reuses existing command validation
- **WHEN** a draft row maps to an existing scene and is applied
- **THEN** the dispatched `UpdateSceneDetails` command runs through the existing
  Scene aggregate validation and optimistic-concurrency check
- **AND** `series_id` is resolved at the API edge (no write-side projection
  lookup; CQRS boundary respected)

#### Scenario: Applying a row that carries costumes
- **WHEN** a draft row is accepted and carries two costumes for figures the
  preview also created
- **THEN** each costume SHALL be dispatched as `CreateCostume`, then
  `UpdateCostumeNotes`, then `AssignCostumeToCharacter` to that figure's
  `Character`
- **AND** each costume row SHALL be persisted in the mapping with
  `aggregate_kind = 'costume'` and its own ordinal
- **AND** re-applying the same preview SHALL skip both costumes (no duplicates)

#### Scenario: The apply persists the scene relation as ordered beats
- **WHEN** an accepted draft row names two figures and carries one costume for
  each
- **THEN** the apply SHALL dispatch `AssignCharacter` for both figures on the
  row's scene stream before any beat
- **AND** each costume SHALL be dispatched as `AddCostumeBeat` on the scene
  stream after its `Costume` is bound, in plan order
- **AND** each beat SHALL be persisted as a `scene_costume_beat` mapping row
  addressed by the figure's mapping reference and its per-figure position,
  carrying the scene aggregate id

#### Scenario: Re-applying a preview adds no second beat
- **WHEN** an apply that already added a costume beat to a scene is retried
- **THEN** the confirmed `scene_costume_beat` mapping row SHALL skip the
  `AddCostumeBeat` dispatch
- **AND** the scene SHALL NOT carry a duplicate beat

#### Scenario: The scene chain appends exactly one event per step
- **WHEN** a draft row with two figures and two costumes is applied
- **THEN** the scene stream SHALL carry exactly one event per chain step:
  create, one assign per figure, one beat per costume
- **AND** the mapping rows SHALL record the scene-stream version after every
  confirmed step, so a retry re-drives only the steps above the stored version

#### Scenario: A costume beat that cannot be added is reported distinctly
- **WHEN** `AddCostumeBeat` is refused for a costume whose `Costume` chain
  succeeded (e.g. a concurrent manual edit removed the figure from the scene)
- **THEN** the reviewer report SHALL surface the costume with a reason
  distinct from the plan-time ungrounded drop
- **AND** a costume dropped as ungrounded SHALL never be reported as a beat
  failure, and vice versa

#### Scenario: One figure mentioned in many rows becomes one aggregate
- **WHEN** a preview names the same figure, in differing case or spacing, across
  several draft rows
- **THEN** exactly one `Character` SHALL be created for that identity
- **AND** the costumes of every row SHALL bind to that single `Character`
- **AND** a second apply of the same preview SHALL create no additional
  `Character`

#### Scenario: A crash between costume steps resumes above the stored version
- **WHEN** an apply crashes after `CreateCostume` but before
  `AssignCostumeToCharacter`
- **THEN** the mapping row SHALL carry the version the costume reached
- **AND** the retry SHALL re-drive only the steps above that version
- **AND** the costume SHALL NOT be created a second time, NOR assigned twice

#### Scenario: A reviewer rejects one costume but keeps its scene
- **WHEN** the reviewer marks a single extracted costume as not accepted while
  accepting the draft row's scene
- **THEN** the scene SHALL still be applied
- **AND** no `Costume` SHALL be created for the rejected row
- **AND** the request SHALL carry the rejection by costume ordinal only

#### Scenario: A dropped costume does not block the apply
- **WHEN** a preview carries a costume the server dropped during grounding
- **THEN** the uncertainty SHALL be visible to the reviewer
- **AND** it SHALL NOT block applying the preview, because a stored preview is
  immutable and offers no way to dismiss it; blocking on it would make one bad
  costume reject an entire paid import

#### Scenario: Costume whose character was skipped
- **WHEN** a draft row is accepted for its scene but the character the costume
  belongs to was skipped by the user
- **THEN** no `Costume` SHALL be created for that costume
- **AND** the apply result SHALL report the costume as not applied, with the
  reason, instead of failing the whole row
