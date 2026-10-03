# AI Import

## Purpose

Provides AI-assisted script and schedule import for costume scheduling.
AI provider/model/prompt configuration lives in a dedicated `ai` bounded
context with its own `AiConfig` aggregate; imports are operational jobs
(`AiImportJob`) in a dedicated Postgres schema, mirroring the
`ReportArchivalQueue` pattern. Script imports parse PDF text into a static
`ScriptContext` type via schema-constrained LLM decoding, schedule imports
merge deterministically onto applied scenes, and applies dispatch existing
commands idempotently via a user-driven mapping projection. Telemetry is
captured from day one, and all endpoints are authorization-gated.
## Requirements
### Requirement: AI bounded context is separate from Settings
The system SHALL model AI provider/model/prompt configuration in a dedicated
`ai` bounded context (`crates/core/src/ai`) with its own `AiConfig` aggregate.
The existing `Settings` aggregate SHALL NOT be extended to carry model,
image-model or prompt-template fields. The AI context SHALL reuse the existing
`CredentialVault` port (and the infra `VaultClient`) to store API keys under
an opaque `vault_key_id` it owns; no new secret store SHALL be introduced.

#### Scenario: AI config stores an opaque vault reference not a secret
- **WHEN** a user submits an AI provider API key
- **THEN** the system stores the key only via the `CredentialVault` port
- **AND** the persisted `AiConfig` aggregate carries a `vault_key_id` and NO
  plaintext or ciphertext secret material
- **AND** the `Settings` aggregate is unchanged

#### Scenario: Revoking an AI key does not affect GDrive bindings
- **WHEN** an AI credential binding is revoked
- **THEN** only the AI context's `vault_key_id` is destroyed
- **AND** GDrive report-archival credential bindings remain usable

### Requirement: Curated LLM provider enum
The system SHALL expose a `LlmProvider` enum (`#[non_exhaustive]`) curating the
set of supported providers (OpenAI, OpenRouter, EURouter, Neuralwatt, OpenCodeGo, OpenCode, Ollama). OpenRouter
and EURouter SHALL be modeled as separate providers with separate curated URLs
and credential bindings.
Each provider's `base_url` SHALL be hardcoded in infra; the API SHALL NOT
accept a user-supplied base URL for model-list or chat calls. Adding a
provider SHALL be an additive, non-breaking change.

#### Scenario: User selects a provider from a curated list
- **WHEN** the user configures an AI provider
- **THEN** the system presents only the curated `LlmProvider` variants
- **AND** rejects any user-supplied base URL

#### Scenario: Model catalog is curated per provider
- **WHEN** the system lists models for a selected provider
- **THEN** it fetches the OpenAI-compatible `GET /v1/models` using the user's
  vaulted key
- **AND** applies a curated allowlist (reduction of choice) before returning the
  list to the user

### Requirement: Per-user AI configuration
Each user MAY persist an `AiConfig` selecting a curated provider, an assistant
model, an image model and one editable prompt template per document kind
(Script, Schedule). Creating or mutating an AI config SHALL be gated by the
existing `has_active_credential_role` membership check. Prompt template text is
the ONLY user-editable schema-affecting input; the output structure is static.

#### Scenario: Only credential-role members may configure AI
- **WHEN** a user without an active credential role attempts to create an
  `AiConfig`
- **THEN** the system returns 403

#### Scenario: Prompt text is editable; output schema is not
- **WHEN** a user edits their script-import prompt template
- **THEN** the system persists the new prompt text
- **AND** the target `ScriptContext` struct shape is unchanged and
  compile-time-derived from Rust types

### Requirement: Import is an operational job queue
AI imports SHALL be modelled as operational jobs (`AiImportJob`), NOT as
event-sourced aggregates or sagas. The queue SHALL live in a dedicated
Postgres schema, mirror the `ReportArchivalQueue` pattern (dedup key,
`Pending|Running|Succeeded|Failed|DeadLetter` status, idempotent enqueue),
and emit NO business events. The job family consists of three kinds:
`ScriptImport` (LLM), `ScheduleImport` (CSV native OR LLM) and `Merge`
(deterministic, no LLM).

#### Scenario: Re-uploading the same document is deduplicated
- **WHEN** a user uploads a document whose hash + user id matches an existing
  job
- **THEN** the system returns the existing job id without enqueuing a new job

#### Scenario: Import failures are classified
- **WHEN** an LLM call returns 429/5xx/timeout
- **THEN** the job is retried in-loop via `retry_transient` and mapped to
  `ServiceUnavailable`
- **WHEN** an LLM call returns 4xx (bad key / bad model)
- **THEN** the job transitions to `Failed` (permanent) without retry

### Requirement: Script import uses schema-constrained LLM decoding
The script import SHALL parse PDF text into a static `ScriptContext` Rust type
using `schemars`-generated JSON Schema constrained decoding
(`response_format`). Output fields SHALL be `Option<T>`-tolerant (LLM outputs
may be incomplete). Prompt text SHALL use XML-tagged framing
(`<role>`, `<context>`, `<edge-case>`); output SHALL be constrained JSON, not
XML.

#### Scenario: Ollama falls back to JSON mode
- **WHEN** the selected provider is Ollama and schema-constrained decoding is
  unsupported
- **THEN** the adapter falls back to `{format:"json"}` with bounded parse-or-retry
- **AND** schema-constrained providers (OpenAI/OpenRouter) use strict schemas

### Requirement: Uncertainty model — null-on-doubt, marked suggestions, apply gate
Every `ScriptContext` preview SHALL carry an `uncertainties: Vec<Uncertainty>`
list. The seeded prompt SHALL instruct the model NOT to assert values it
cannot read, to leave the field null, and to append an `Uncertainty`
(`scene_index`, `field`, `note`, optional `suggested_value`). The model MAY
supply a clearly-marked `suggested_value` for the user to confirm or replace.
A `ScriptContext` preview with open uncertainties SHALL NOT be applicable.

#### Scenario: Model flags an uncertainty instead of guessing
- **WHEN** the LLM cannot confidently read a scene's location
- **THEN** the `ScriptContext` preview has that `location` field null
- **AND** an `Uncertainty` entry describes the ambiguity

#### Scenario: Marked suggestion is rendered distinctly
- **WHEN** the model supplies a `suggested_value` for an uncertainty
- **THEN** the preview exposes it as a marked suggestion, distinct from an
  asserted value
- **AND** the user must confirm or replace it before apply

#### Scenario: Open uncertainties block apply
- **WHEN** the user attempts to apply a ScriptContext preview with unresolved
  uncertainties
- **THEN** the system rejects the apply

### Requirement: Merge is deterministic, only for schedule imports, ordered after script apply
The merge step SHALL exist only as part of the schedule import. It SHALL be a
deterministic join of `ShootingSchedule` rows onto already-**applied** scenes by
scene number, using NO LLM, costing zero tokens, and being idempotently
replayable. The merge SHALL NOT query the Scene read-model projection at
runtime; instead, the required scene context SHALL be prepared as an immutable
`MergeInput` at the authorized API/query boundary and stored alongside the
schedule preview before the merge job is claimed. The write-side merge worker
performs only the deterministic join against this pre-loaded input (CQRS
boundary, AGENTS.md §1). The merge SHALL block/no-op until the target block
has applied scenes (domain invariant: scripts for a block are always finished
before a schedule is created).

#### Scenario: Merge blocks until scripts are applied
- **WHEN** a schedule import completes for a block that has no applied scenes
- **THEN** the merge job does not produce a merged preview
- **AND** surfaces a blocked-pending-applied-scripts state

#### Scenario: Unmatched rows surface for adjudication
- **WHEN** the merge runs against fully-applied scenes and a schedule row
  references a scene number not present in the block
- **THEN** the merged preview lists the schedule row in `unmatched_schedule_rows`
- **AND** the user must adjudicate (create the missing scene or correct the
  schedule) before the schedule-side apply

#### Scenario: Write-side worker never queries a projection
- **WHEN** the merge worker claims a schedule job
- **THEN** it reads only the immutable `MergeInput` blob from the preview store
- **AND** it does not call `EpisodeRepository` or `SceneRepository`
- **AND** the architecture check rejects any write-side AI adapter that queries
  a read-model projection

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

### Requirement: Schedule-side apply reserves aggregate ids before dispatch
The schedule-side apply SHALL make the create-style commands
(`CreateShootingDay`, `PlanSceneShoot`) and their idempotency mapping one
recoverable operation, so that a failure between the event append and the
mapping write cannot produce a duplicate aggregate on retry.

It SHALL do so by persisting the aggregate id **before** dispatching the
command: a *reservation* row is written to
`projection_ai_import_mapping` with `aggregate_version = 0` (the established
"no version yet" sentinel), the command is dispatched with that reserved id,
and the row is then *confirmed* by advancing it to the real aggregate version.
The reservation write SHALL be insert-if-absent and SHALL return the winning
row, so concurrent or retried applies converge on one id. The confirm write
SHALL only ever advance `aggregate_version`.

A mapping that is still reserved SHALL NOT count as applied work: the apply
SHALL re-drive that row onto the reserved id. Because both commands dispatch
with an empty-stream expected version, re-driving an already-appended stream
SHALL surface the current aggregate version, which SHALL be used to confirm
the mapping. A conflict reporting a version of 0 (an empty stream) SHALL NOT
be treated as recovery and SHALL propagate as an error.

#### Scenario: Crash between PlanSceneShoot and the mapping write
- **WHEN** `PlanSceneShoot` appends its event and the mapping write then fails
- **THEN** the mapping row remains in the reserved state
- **AND** a retry re-dispatches `PlanSceneShoot` with the *same* reserved
  `SceneShootId`
- **AND** exactly one scene shoot exists for that (preview, scene, shooting day)
- **AND** the mapping is confirmed with the version recovered from the stream

#### Scenario: Crash between CreateShootingDay and the mapping write
- **WHEN** `CreateShootingDay` appends its event and the mapping write fails
- **THEN** a retry reuses the reserved `ShootingDayId` and creates no second day

#### Scenario: Retried scene scheduling does not strand the mapping
- **WHEN** a retry re-dispatches `ScheduleSceneOnShootingDay` for a scene that
  the crashed attempt already linked to the day
- **THEN** the command succeeds as a no-op (state-idempotent)
- **AND** the apply proceeds to confirm the scene-shoot mapping

### Requirement: Resilience and bounded cost
The system SHALL bound LLM cost exposure via: a per-job request cap (max chunks;
exceeded → `Failed`, no retry), a per-user in-flight concurrency cap, and an
`AiImportBounds` config (mirrors `RenderBounds`) carrying compile-time and
env-guarded ceilings (`max_chunks_per_script`, `max_tokens_per_req`,
`max_concurrent_jobs_global`). Dollar/token spend SHALL be enforced at the
provider side; local caps are defense in depth.

#### Scenario: Per-job request cap stops a runaway import
- **WHEN** a script import would exceed `max_chunks_per_script`
- **THEN** the job transitions to `Failed`
- **AND** no further LLM calls are made for that job

### Requirement: Telemetry is captured from day one
Every import job SHALL record `provider`, `model`, `doc_kind`, `chunk_count`,
`tokens_in`, `tokens_out`, `latency_total` and an apply state. Jobs that never
reach apply SHALL be recorded as `NotApplied` (`accept_as_is` NULL,
`edit_distance` NULL); jobs that
are applied SHALL record `accept_as_is: bool` (applied with zero edits) and
`edit_distance: u32` (content-free count of user resolutions/edits; never
script text — NDA). `accept_as_is` and `edit_distance` SHALL be captured at
apply time (the only moment they are observable) and SHALL NOT be backfillable.
Acceptance-rate and edit-rate calculations SHALL exclude `NotApplied` jobs.
Auto-apply is out of scope for v1.

#### Scenario: Apply records accept signal
- **WHEN** a user applies a preview without any edits or uncertainty resolutions
- **THEN** the job's `accept_as_is` is recorded as true and `edit_distance` as 0
- **AND** an applied zero-edit outcome is distinguishable from a never-applied
  job (which SHALL have `edit_distance` NULL)

#### Scenario: Never-applied job has no edit distance
- **WHEN** a job reaches preview but is never applied
- **THEN** its apply state is `NotApplied`
- **AND** its `edit_distance` is NULL

#### Scenario: Telemetry contains no script content
- **WHEN** the system records `edit_distance`
- **THEN** the recorded value is a count only
- **AND** no script text, costume description, or NDA-protected content is
  persisted in telemetry

### Requirement: Authorization gates on import endpoints
All AI import and configuration endpoints SHALL be gated by active costume-dept
membership. Privileged handlers under `Authenticated`-only routes SHALL call the
relevant `AuthorizationPolicy` method inside the handler body and return 403 on
denial, and SHALL carry a `// AUTHZ-GATE:` comment (mirrors the photo-handler
rule). AI config create/mutate SHALL additionally gate on
`has_active_credential_role`.

#### Scenario: Non-member cannot import
- **WHEN** a user without an active costume-dept role in the target block
  attempts to upload a script
- **THEN** the system returns 403

### Requirement: Applied dispo is event-sourced in real aggregates; MergedDispo is derived
The applied dispo (scenes, characters, shooting days, scene shoots) SHALL be
event-sourced in the existing Scene/Character/ShootingDay/SceneShoot streams.
`MergedDispo` SHALL be a derived read projection rebuilt from those streams at
zero LLM cost; the pre-apply merge preview SHALL be a transient staged blob. No
`MergedDispo` event stream SHALL exist.

#### Scenario: Projection rebuild costs no LLM tokens
- **WHEN** the `MergedDispo` projection is rebuilt after an incident
- **THEN** it is re-derived from the Scene/Character/ShootingDay/SceneShoot
  event streams and projections
- **AND** no LLM call is made during the rebuild

### Requirement: AI-created scenes carry a provenance discriminator
The AI script apply SHALL stamp every scene it creates with
`SceneSource::AiExtracted { document_id, external_ref, confidence }`, where
`document_id` is the AI import job id, `external_ref` is the draft ref, and
`confidence` is `None` (the pipeline measures no per-row model confidence). The
REST scene-creation path and every client request SHALL record `Manual`; clients
SHALL NOT be able to set provenance on `CreateSceneRequest`. The `SceneView`
read model SHALL expose the discriminator as an optional additive field
(`source: Option<SceneSource>`, ADR-021 D3/MINOR): `Some(AiExtracted)` marks
AI-imported scenes, `Some(Manual)` the user-created path and `None` only
legacy clients that predate the field.

#### Scenario: Script apply marks the scene as AI-extracted
- **WHEN** the AI script apply dispatches `CreateScene` for a mapped draft row
- **THEN** the emitted `SceneCreated` event carries
  `SceneSource::AiExtracted { document_id: <job id>, external_ref: <draft_ref>, confidence: None }`
- **AND** the `SceneView` read model exposes the same discriminator as `source`

#### Scenario: Manual creation stays indistinguishable from legacy data
- **WHEN** a scene is created via the REST handler
- **THEN** the emitted `SceneCreated` event carries `SceneSource::Manual`
- **AND** a historic `SceneCreated` event persisted before the `source` field
  existed replays as `SceneSource::Manual` (serde default, no migration)

### Requirement: Recorded extraction confidence is honest
The schedule-side apply SHALL record `ShootingDaySource::AiExtracted.confidence`
as `None` while the import pipeline measures no real per-row model confidence.
It SHALL NOT hard-code a placeholder confidence value.

#### Scenario: Pre-change events read losslessly
- **WHEN** a persisted `ShootingDaySource::AiExtracted` event carries a plain
  numeric `confidence` (pre-#517 hard-coded `1.0`)
- **THEN** it deserializes losslessly as `Some(...)`
- **WHEN** the current apply creates a shooting day
- **THEN** the persisted provenance carries `confidence: null`

