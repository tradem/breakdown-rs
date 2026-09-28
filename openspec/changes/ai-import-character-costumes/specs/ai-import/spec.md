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

## ADDED Requirements

### Requirement: The preview exposes extracted costumes for review
The script preview SHALL expose, per draft scene, the extracted costumes with
their character name, description and quoted source text, and SHALL allow the
reviewer to accept, reject or map each costume row independently of the scene
row. The reviewer interface SHALL show the quoted source fragment next to the
extracted description, so that a reviewer can verify the extraction against the
script without opening the document.

#### Scenario: Reviewing an extraction against its source
- **WHEN** a draft row shows a costume "ölverschmierter Mechaniker-Overall"
- **THEN** the quoted fragment the extraction was based on SHALL be visible next
  to the description
- **AND** the reviewer can reject that costume without rejecting the scene

### Requirement: A stored configuration prompt takes precedence over the deployment default
A per-configuration prompt that is stored (non-empty) SHALL override the
deployment default prompt, and the configuration surface SHALL indicate that a
stored prompt is in effect and that it therefore does not follow deployment
default updates. A configuration whose stored prompt is empty SHALL use the
deployment default, as before.

#### Scenario: Deployment hardens the default prompt
- **WHEN** the deployment default script prompt is updated and an existing
  configuration still stores the previous prompt
- **THEN** the import SHALL keep using the configuration's stored prompt
- **AND** the configuration surface SHALL show that a stored prompt is in effect
- **AND** the reviewer can reset the stored prompt to follow the default again

#### Scenario: Extracting an empty stored prompt
- **WHEN** a configuration's stored script prompt is empty
- **THEN** the import SHALL use the deployment default prompt
