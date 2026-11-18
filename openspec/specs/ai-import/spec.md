<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->

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
set of supported providers (OpenAI, Gemini, OpenRouter, EURouter, Neuralwatt, OpenCodeGo, OpenCode, Ollama). OpenRouter
and EURouter SHALL be modeled as separate providers with separate curated URLs
and credential bindings. Google Gemini (`LlmProvider::Gemini`, canonical key
`"gemini"`, alias `"google"`) SHALL use Google's official OpenAI-compatible
endpoint (`https://generativelanguage.googleapis.com/v1beta/openai`).
Each provider's `base_url` SHALL be hardcoded in infra; the API SHALL NOT
accept a user-supplied base URL for model-list or chat calls. Adding a
provider SHALL be an additive, non-breaking change. The provider registry SHALL
maintain curated assistant model lists (`curated_model_ids`) and curated image
generation model lists (`curated_image_model_ids`, preparing for #673), while
preserving previously curated legacy model IDs in the validation allowlist so
existing persisted `AiConfig` records remain valid across catalog refreshes.

#### Scenario: User selects a provider from a curated list
- **WHEN** the user configures an AI provider
- **THEN** the system presents only the curated `LlmProvider` variants (including `gemini`)
- **AND** rejects any user-supplied base URL

#### Scenario: Google alias resolves to Gemini provider
- **WHEN** a client requests `/v1/ai-import/providers/google/models` or `/v1/ai-import/providers/gemini/models`
- **THEN** both resolve to `LlmProvider::Gemini` and return the curated Gemini models

#### Scenario: Model catalog is curated per provider
- **WHEN** the system lists models for a selected provider
- **THEN** it returns the curated models for that provider (with `recommended: true` on the provider's default model)
- **AND** applies the curated allowlist (including legacy allowlisted model IDs) when validating configurations

### Requirement: Per-user AI configuration
Each user MAY persist an `AiConfig` selecting a curated provider, an assistant
model, an image model, one editable prompt template per document kind
(Script, Schedule), and a `cost_display_preference` (`CostDisplayPreference`:
`token` default or `energy`). Creating or mutating an AI config SHALL be gated by the
existing `has_active_credential_role` membership check. Prompt template text is
the ONLY user-editable schema-affecting input; the output structure is static.
Pre-existing `AiConfigCreated` and `AiConfigUpdated` events persisted before
`cost_display_preference` was introduced SHALL deserialize with
`CostDisplayPreference::Token` (`#[serde(default)]`).

#### Scenario: Only credential-role members may configure AI
- **WHEN** a user without an active credential role attempts to create an
  `AiConfig`
- **THEN** the system returns 403

#### Scenario: Prompt text is editable; output schema is not
- **WHEN** a user edits their script-import prompt template
- **THEN** the system persists the new prompt text
- **AND** the target `ScriptContext` struct shape is unchanged and
  compile-time-derived from Rust types

#### Scenario: Cost display preference round-trips and replays safely
- **WHEN** a user creates or updates an `AiConfig` with `cost_display_preference = "energy"`
- **THEN** `GET /v1/ai-import/config` and `GET /v1/ai-import/config/{id}` return `cost_display_preference = "energy"`
- **AND** historic `AiConfig` events without `cost_display_preference` replay as `"token"`

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

#### Scenario: A rejected dependency credential is not retried
- **WHEN** a worker's Vault read answers `401`/`403` (invalid or expired token)
- **THEN** the failure is classified as `DomainError::DependencyAuthFailed`
  (registered code `dependency.auth-failed`) and `DomainError::is_retryable()`
  is false
- **AND** the job is dead-lettered without consuming the remaining retry budget
  against the permanent misconfiguration

#### Scenario: The wire exposes retry timing and attempt history
- **WHEN** `GET /v1/ai-import/jobs/{id}` is read for a retryable `failed` job
- **THEN** `next_attempt_at` carries the due time and `attempts` lists each
  recorded attempt (newest first) with its own status, error summary and
  retryable flag
- **AND** the per-attempt rows survive later attempts, unlike `last_error`
  which each attempt overwrites

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
`tokens_in`, `tokens_out`, `cached_tokens_in`, `energy_millijoules` (when
reported by the provider, e.g. Neuralwatt), `latency_total` and an apply state.
The LLM chat adapters (`OpenAiCompatibleChatClient` and `OllamaChatClient`)
SHALL extract token counts (`prompt_tokens`, `completion_tokens`,
`cached_tokens` / `prompt_eval_count`, `eval_count`) and hardware energy
telemetry (`energy.energy_joules` / `energy.energy_kwh`) from every provider
response and accumulate them across all chunks and bounded truncation or parse
retries of a job. Jobs that never
reach apply SHALL be recorded as `NotApplied` (`accept_as_is` NULL,
`edit_distance` NULL); jobs that
are applied SHALL record `accept_as_is: bool` (applied with zero edits) and
`edit_distance: u32` (content-free count of user resolutions/edits; never
script text — NDA). `accept_as_is` and `edit_distance` SHALL be captured at
apply time (the only moment they are observable) and SHALL NOT be backfillable.
Acceptance-rate and edit-rate calculations SHALL exclude `NotApplied` jobs.
Auto-apply is out of scope for v1.

#### Scenario: LLM worker accumulates real token and energy usage across chunks and retries
- **WHEN** a script import job runs two chunks where chunk 1 succeeds on the first call (`1000` in, `400` out, `5.0 J`) and chunk 2 truncates once (`800` in, `500` out, `4.0 J`) before succeeding on retry (`800` in, `900` out, `6.0 J`)
- **THEN** the worker records `tokens_in = 2600`, `tokens_out = 1800`, and `energy_millijoules = 15000` via `record_worker_telemetry`
- **AND** `GET /v1/ai-import/jobs/{id}` and `GET /v1/ai-import/jobs` expose the recorded telemetry on the `AiImportJob` view

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

### Requirement: Owner-fenced job progress with stage and episode visibility
The operational `AiImportJob` record SHALL carry an optional `progress`
payload (`AiImportProgress`: `stage`, `chunk`, `chunks_total`,
`episodes_seen`) persisted in `ai_import.ai_import_job.progress` (`JSONB`)
and exposed on `GET /v1/ai-import/jobs/{id}`, `GET /v1/ai-import/jobs`, and
`GET /v1/ai-import/jobs/{id}/events`. Progress writes SHALL be executed via
an owner-fenced `AiImportQueue::mark_progress` method
(`WHERE id = $1 AND status = 'running' AND claimed_by = $2`) and SHALL be
throttled to stage transitions (`extracting_text`, `extracting`, `merging`,
`storing_preview`) and completed chunks (`1..=chunks_total`), NEVER per
generated LLM token. The `episodes_seen` list SHALL be populated at zero
extra LLM token cost from the deterministic `Ep.:` marker scan and extracted
per-chunk `DraftEpisode` metadata in first-seen order, deduplicated. Re-claiming
a job after a retryable failure SHALL reset `progress` to `null` so stale
progress from an earlier attempt is never served.

#### Scenario: Script worker publishes throttled per-chunk progress and episodes seen
- **WHEN** a script import job with 12 scene chunks processes chunks 1 through 4
  spanning markers `Ep.: 3` and `Ep.: 4`
- **THEN** the worker calls `mark_progress` once after chunking and once after
  each completed chunk (never per LLM token)
- **AND** after chunk 4 the persisted `job.progress` carries
  `stage = "extracting"`, `chunk = 4`, `chunks_total = 12`, and
  `episodes_seen = ["Ep. 3", "Ep. 4"]`

#### Scenario: Displaced worker cannot overwrite progress
- **WHEN** a worker whose claim lease expired calls `mark_progress` after
  another worker has reclaimed the job
- **THEN** `mark_progress` affects zero rows and returns `DomainError::Conflict`
- **AND** the new owner's `progress` state remains intact

#### Scenario: Retry reclaim clears stale progress from a prior attempt
- **WHEN** a retryable `failed` job with non-null `progress` from attempt 1 is
  claimed for attempt 2
- **THEN** the claim transition resets `progress` to `null` before attempt 2
  begins processing

### Requirement: Push-based job progress stream via Server-Sent Events (SSE)
The system SHALL expose `GET /v1/ai-import/jobs/{id}/events` returning a
`text/event-stream` (`Cache-Control: no-store, no-transform`,
`X-Accel-Buffering: no`)
stream of `AiImportJobResponse` frames (`event: job`). The handler SHALL
enforce authentication and the handler-internal `// AUTHZ-GATE:`
`authorize_ai_job` check (`Action::Read`) before opening the stream,
returning `404 ai-import.disabled` when AI import is disabled,
`404 ai-import.not-found` when the job does not exist, and
`403 ai-import.forbidden` when the caller is not authorized.

The first message on every initial connect and every `Last-Event-ID`
reconnect SHALL be a full snapshot of the current `AiImportJobResponse`,
so clients need no separate catch-up polling. Subsequent messages SHALL be
pushed without database polling whenever an owner-fenced status or progress
write commits, distributed through a storage-agnostic port subscription
(`AiImportQueue::subscribe`) backed by an in-process broadcast hub
(`AiJobEventHub`). In the PostgreSQL operating mode, fenced writes SHALL
additionally emit `pg_notify('ai_import_job_events', ...)` in the same SQL
statement, bridged into the local hub by a single shared `PgListener` per
API instance; single-node test and future SQLite operating modes SHALL
publish directly to the in-process hub without requiring `LISTEN/NOTIFY`.
The stream SHALL emit keep-alive comment frames (~30 s) and SHALL close
automatically immediately after emitting a frame whose `job.status` is
terminal (`succeeded`, `dead_letter`, `payload_unavailable`).

#### Scenario: Initial connect receives an immediate full snapshot
- **WHEN** an authorized user opens `GET /v1/ai-import/jobs/{id}/events` for a
  running job
- **THEN** the server responds with `200 OK` and `Content-Type: text/event-stream`
- **AND** the first SSE event (`event: job`) carries the full current
  `AiImportJobResponse` snapshot (including `progress`) and an `id` field

#### Scenario: Reconnect with Last-Event-ID converges via fresh snapshot
- **WHEN** a client reconnects to `GET /v1/ai-import/jobs/{id}/events` with a
  `Last-Event-ID` header after missing intermediate chunk updates
- **THEN** the server immediately emits the latest authoritative
  `AiImportJobResponse` snapshot as the first SSE event without requiring
  catch-up polling

#### Scenario: Fenced progress and status updates push over the stream and terminal status closes it
- **WHEN** a worker commits `mark_progress` and then `mark_succeeded` for a
  watched job
- **THEN** the SSE stream pushes an `event: job` frame for the progress update
  and an `event: job` frame with `status = "succeeded"`
- **AND** the server closes the SSE stream immediately after the terminal
  `succeeded` frame

#### Scenario: Already-terminal job emits one snapshot and closes
- **WHEN** an authorized user connects to `GET /v1/ai-import/jobs/{id}/events`
  for a job that is already in `succeeded`, `dead_letter`, or
  `payload_unavailable`
- **THEN** the server emits the single snapshot `event: job` frame and closes
  the stream immediately

#### Scenario: Unauthorized caller is rejected before streaming
- **WHEN** a user who does not own the job or lacks active costume-department
  membership in the job's block requests `GET /v1/ai-import/jobs/{id}/events`
- **THEN** the handler rejects the request with `403 ai-import.forbidden`
  (`application/problem+json`) before opening an SSE stream

### Requirement: Seeded model pricing read model and periodic background refresh
The system SHALL maintain model pricing in a PostgreSQL read-model table
`ai_import.ai_model_pricing` keyed by `(provider, model)`. All monetary rates
SHALL be stored as non-negative 64-bit integers (`BIGINT` / `i64`) in
**nano-currency units** ($10^{-9}$ of the currency unit: `1_000_000_000 = 1.00`
`USD` or `EUR`), carrying:
- `currency` (`"USD"` or `"EUR"`),
- `input_nano_per_million` and `output_nano_per_million` (nano-units per 1,000,000 tokens),
- optional `cached_input_nano_per_million`,
- optional `energy_nano_per_kwh` and `energy_capped_by_token` (for providers offering energy billing such as Neuralwatt at `$10.00 / kWh`),
- optional `image_output_nano_per_million` and `image_nano_per_unit` (for image generation models such as Google Gemini *Nano Banana* and OpenAI `gpt-image-*`),
- `pricing_source` (`"curated_seed"`, `"provider_live"`, or `"models_dev"`), and
- `price_as_of` (`TIMESTAMPTZ`).

A database migration SHALL seed `ai_import.ai_model_pricing` with baseline
rates (`pricing_source = 'curated_seed'`) for all curated hosted models so
offline and freshly booted deployments have deterministic pricing immediately.
When `AI_IMPORT_ENABLED` and `AI_PRICING_REFRESH_ENABLED` (default `true`) are
active, a background task (`AiPricingRefreshWorker`) SHALL run an initial
non-blocking refresh after startup and periodically every
`AI_PRICING_REFRESH_INTERVAL_SECS` (default `21600` = 6 hours, clamped to
`300..=604800`), coordinated across instances via `pg_try_advisory_lock`.
The refresh worker SHALL fetch public catalogs over the ADR-024 hardened
hosted HTTP client (`api.neuralwatt.com/v1/models`, `openrouter.ai/api/v1/models`,
`api.eurouter.ai/api/v1/models`, and `models.dev/api.json`) and `UPSERT` rows
without deleting pre-existing rows that were rotated out of a live feed.

#### Scenario: Fresh deployment has seeded pricing before any network refresh
- **WHEN** the backend starts with all external catalog endpoints unreachable
- **THEN** `ai_import.ai_model_pricing` still contains the migration-seeded rates with `pricing_source = "curated_seed"`
- **AND** `GET /v1/ai-import/providers/{provider}/models` returns those rates with their `price_as_of` timestamp

#### Scenario: Background refresh upserts live pricing and preserves rotated models
- **WHEN** `AiPricingRefreshWorker` completes a refresh cycle against a provider feed that updated `glm-5.3` pricing and omitted legacy `glm-5.2`
- **THEN** the `glm-5.3` row is updated with the new nano-rates, `pricing_source = "provider_live"`, and a fresh `price_as_of`
- **AND** the existing `glm-5.2` row remains in `ai_import.ai_model_pricing` untouched

#### Scenario: Partial upstream failure does not abort other pricing sources
- **WHEN** one upstream catalog endpoint returns HTTP 503 or times out during a refresh cycle
- **THEN** `AiPricingRefreshWorker` logs a warning for that source and still commits updates from the remaining healthy sources

### Requirement: Model catalog exposes pricing metadata and unknown-price honesty
`GET /v1/ai-import/providers/{provider}/models` SHALL enrich each returned
`ModelInfo` with `pricing: Option<ModelPricing>` read from
`ai_import.ai_model_pricing`. For providers or models without known pricing
(such as local `LlmProvider::Ollama` models), `pricing` SHALL be `null` (`None`)
— NEVER a fabricated zero-price object. Genuine free-tier hosted models (e.g.
`nvidia/nemotron-3.5-lightning:free` where the provider explicitly reports `0`
input and `0` output cost) SHALL carry `Some(ModelPricing)` with
`input_nano_per_million = 0` and `output_nano_per_million = 0`.

#### Scenario: Hosted model returns token and energy pricing metadata
- **WHEN** an authorized caller requests `GET /v1/ai-import/providers/neuralwatt/models`
- **THEN** each curated model carries `pricing` with `currency = "USD"`, `input_nano_per_million`, `output_nano_per_million`, `energy_nano_per_kwh = 10000000000`, `energy_capped_by_token = true`, and `price_as_of`

#### Scenario: Local Ollama model returns null pricing
- **WHEN** an authorized caller requests `GET /v1/ai-import/providers/ollama/models`
- **THEN** every returned `ModelInfo` has `pricing = null`

### Requirement: Per-import immutable cost breakdown snapshot in integer nano-units
At job completion (immediately before `mark_succeeded`), the import worker
SHALL compute an immutable `CostBreakdown` snapshot from the job's accumulated
telemetry and the current `ai_import.ai_model_pricing` rows and persist it in
`ai_import.ai_import_job.cost` (`JSONB`). All cost math SHALL use integer
arithmetic (`i64` / `i128`, no floats).

Usage SHALL be accumulated **per component**, and each component SHALL be
priced with the rate card of the model that actually consumed it:

- the **extraction** component is the job's extraction provider/model usage
  (`Telemetry.tokens_in` / `tokens_out` / `cached_tokens_in` /
  `energy_millijoules` SHALL describe this component only), priced from the
  `(provider, model)` row of the job's extraction model;
- the **decision** component is the usage of the optional Decision Model
  scoring pass (script chunk scoring, schedule scoring and the Pass-2 outfit
  continuity pass), priced from the `(provider, model)` row of the **resolved
  Decision Model** — never from the extraction model's row.

Usage SHALL be retained **per request** within each component (issue #794):
both components keep the individual `LlmCallUsage` of every billable provider
request next to the summed counters, because a provider may cap energy per
request. A component's energy figure SHALL therefore be
`Σ_calls min(raw_energy_nano_i, token_cost_nano_i)` when the pricing row sets
`energy_capped_by_token` — never `min(Σ raw_i, Σ token_i)`, which is only an
upper bound (`Σ min(a_i, b_i) <= min(Σ a_i, Σ b_i)`) and would overstate what
was billed. `token_cost` (and `DecisionCostBreakdown::token_cost_nano`) SHALL
stay the figure of the component's **summed** tokens.

`CostBreakdown` SHALL carry:
- `status: CostStatus` (`"known"`, `"unknown"`, or `"not_applicable"`),
- `currency: Option<Currency>` (`"USD"` or `"EUR"` when `status == "known"`),
- `price_as_of: Option<DateTime<Utc>>`,
- `pricing_source: Option<PricingSource>`,
- `token_cost: Option<TokenCostBreakdown>` (`tokens_in`, `tokens_out`, `cached_tokens_in`, `input_rate_nano_per_million`, `output_rate_nano_per_million`, `cached_input_rate_nano_per_million`, `total_nano`) — the **extraction** component,
- `energy_cost: Option<EnergyCostBreakdown>` (populated when both hardware energy telemetry and `energy_nano_per_kwh` exist: `energy_millijoules`, `rate_nano_per_kwh`, `raw_energy_nano`, `effective_capped_nano`, `capped_by_token_cost`; all three figures SHALL be summed over the requests, each capped on its own — issue #794) — the **extraction** component,
- `image_cost: Option<ImageCostBreakdown>` (kind-tagged extensibility slot for #673 per-image / image-token costs),
- `decision: Option<DecisionCostBreakdown>` — the **decision** component, present
  iff the job issued at least one Decision-Model call, carrying `provider`,
  `model`, `status` (`"known"` or `"unknown"`), that component's own
  `tokens_in` / `tokens_out` / `cached_tokens_in` / `energy_millijoules`, its own
  `currency` / `price_as_of` / `pricing_source` snapshot, its own
  `input_rate_nano_per_million` / `output_rate_nano_per_million` /
  `cached_input_rate_nano_per_million` / `energy_rate_nano_per_kwh`, and the
  priced `token_cost_nano` / `energy_cost_nano` (the latter per-request capped,
  like the extraction component); and
- `total: CostTotal` (`status: CostTotalStatus`, `currency`, `total_nano`) — the
  figure the user pays, which SHALL only be a number when it is honest:
  `"known"` (every recorded component priced in one currency, `total_nano` is
  their sum), `"incomplete"` (a recorded component has no pricing row, so
  `total_nano` is `null` and the priced parts stay visible), `"mixed_currency"`
  (the components are priced in different currencies; no conversion exists per
  design D2, so `total_nano` is `null`), or `"unknown"` (nothing priced, and the
  `serde(default)` value for snapshots recorded before this field existed).

A missing pricing row for a component SHALL degrade **only that component** to
an explicit unknown — never `0`, never a substituted rate. The snapshot SHALL
be exposed on `AiImportJob` in `GET /v1/ai-import/jobs`,
`GET /v1/ai-import/jobs/{id}`, and the SSE `event: job` frames of
`GET /v1/ai-import/jobs/{id}/events`. Subsequent changes to
`ai_import.ai_model_pricing` SHALL NOT mutate the persisted `cost` snapshot of
already-completed jobs.

#### Scenario: Neuralwatt import records both token and energy cost snapshots
- **WHEN** a Neuralwatt script import completes with `tokens_in = 10000`, `tokens_out = 2000`, `energy_millijoules = 18000` (5 µkWh), and model pricing of `$1.45 / 1M` in, `$4.50 / 1M` out, `$10.00 / kWh` energy
- **THEN** the persisted `job.cost` has `status = "known"`, `token_cost.total_nano = 23500000` (`$0.0235`), `energy_cost.raw_energy_nano = 50000` (`$0.00005`) with `effective_capped_nano = 50000` and `capped_by_token_cost = false`
- **AND** `total.status = "known"` with `total.total_nano = 23550000` and `total.currency = "USD"`
- **AND** the terminal `succeeded` SSE frame on `GET /v1/ai-import/jobs/{id}/events` includes `job.cost`

#### Scenario: A multi-request component sums the per-request caps
- **WHEN** a Neuralwatt script import runs two extraction requests at `$10.00 / kWh` and `$1.45 / 1M` input tokens, where request 1 reports `10000` input tokens and `18000` mJ (`raw = 50000` nano, `token = 14500000` nano) and request 2 reports `1` input token and `18000` mJ (`raw = 50000` nano, `token = 1450` nano)
- **THEN** `job.cost.token_cost` holds the summed usage (`tokens_in = 10001`, `total_nano = 14501450`)
- **AND** `job.cost.energy_cost.raw_energy_nano = 100000` and `effective_capped_nano = 51450` (request 1 uncapped, request 2 capped at its own token cost)
- **AND** `capped_by_token_cost` is `true`, even though capping the sums would have reported `100000` and claimed no cap at all
- **AND** the Decision-Model component follows the same rule for its own requests

#### Scenario: Ollama import records unknown cost status and never zero
- **WHEN** an Ollama script import completes with `tokens_in = 8000` and `tokens_out = 1500`
- **THEN** the persisted `job.cost` has `status = "unknown"`, `token_cost = null`, and `energy_cost = null`
- **AND** `total.status = "unknown"` and `total.total_nano = null`
- **AND** the job still records `tokens_in = 8000` and `tokens_out = 1500` in its telemetry

#### Scenario: Native CSV schedule import records not_applicable cost status
- **WHEN** a CSV schedule import completes via the native parser without invoking an LLM
- **THEN** the persisted `job.cost` has `status = "not_applicable"`
- **AND** `job.cost.decision = null`

#### Scenario: A Decision Model on its own rate card is priced with its own rates
- **WHEN** a script import extracts 10000 in / 2000 out tokens with model `a` at `$1.45 / 1M` in and `$4.50 / 1M` out, and its Decision Model `b` consumes 3000 in / 500 out tokens at `$0.2925 / 1M` in and `$1.17 / 1M` out
- **THEN** `job.cost.token_cost` carries **only** the extraction usage (`tokens_in = 10000`, `tokens_out = 2000`, `total_nano = 23500000`)
- **AND** `job.cost.decision` carries `provider`/`model` of `b` with `tokens_in = 3000`, `tokens_out = 500`, `status = "known"`, `input_rate_nano_per_million = 292500000`, and `token_cost_nano = 1462500`
- **AND** `job.cost.total.status = "known"` with `total_nano = 24962500` (the sum of both components, what the user pays)

#### Scenario: Unknown decision pricing degrades only the decision component
- **WHEN** a script import completes successfully with a priced extraction model and a Decision Model whose `(provider, model)` has no `ai_model_pricing` row
- **THEN** `job.cost.token_cost` and the snapshot `status` are unchanged (the extraction component is priced)
- **AND** `job.cost.decision.status = "unknown"` with `token_cost_nano = null`, `energy_cost_nano = null`, `currency = null`, and its recorded `tokens_in`/`tokens_out` still present
- **AND** `job.cost.total.status = "incomplete"` and `total.total_nano = null` — no partial sum is presented as the total and no extraction rate is substituted

#### Scenario: Components priced in different currencies are never summed
- **WHEN** a job's extraction model is priced in `USD` and its Decision Model in `EUR`
- **THEN** `job.cost.total.status = "mixed_currency"` and `total.total_nano = null`
- **AND** both components still carry their own `currency` and priced figures

#### Scenario: An old snapshot does not claim a total it does not carry
- **WHEN** a job whose `cost` JSONB was recorded before the `decision`/`total` fields existed is read
- **THEN** it deserializes with `decision = null` and `total.status = "unknown"`, `total.total_nano = null`
- **AND** the pre-existing `status`, `token_cost` and `energy_cost` fields keep their recorded values

### Requirement: Deterministic set-shorthand mood extraction and costume-focused Dispo TL;DR
`extract_scenes` SHALL deterministically parse interior/exterior and time-of-day tokens from German and English scene headings into canonical set shorthand (`I/T`, `A/T`, `I/N`, `A/N`, `I/D`, `A/D`, `I/M`, `A/M`, `I/AB`, `A/AB`, `I/A/T`) on `SceneChunk.mood`, where `I/A/T` is the single three-component value for a combined `INT/EXT` heading with a time token. When the LLM omits `DraftScene.mood` on the first scene of a chunk, `ScriptImportWorker` SHALL backfill it from `SceneChunk.mood`. The default script extraction prompt SHALL instruct the model to emit a concise 1–2 sentence Dispo TL;DR in `summary` covering core physical action, costume continuity triggers, and grounded cross-department interfaces (hair/make-up, sound, props) without retelling dialogue.

#### Scenario: German short-form heading backfills canonical mood
- **WHEN** a chunk heading is `"12 I/N - WERKSTATT"` and the LLM returns `mood: null`
- **THEN** `SceneChunk.mood` is `Some("I/N")`
- **AND** the resulting `DraftScene.mood` is backfilled to `Some("I/N")`

#### Scenario: English heading maps to canonical set shorthand
- **WHEN** a chunk heading is `"EXT. STREET - NIGHT"`
- **THEN** `SceneChunk.mood` is `Some("A/N")`

#### Scenario: Combined INT/EXT heading maps to the three-component canonical value
- **WHEN** a chunk heading is `"INT/EXT. WORKSHOP - DAY"`
- **THEN** `SceneChunk.mood` is `Some("I/A/T")`

#### Scenario: Episode mismatch leaves the schedule row unmatched
- **WHEN** Episode 295 provides no matching scene for a row with `episode_number = Some(295)` and `scene_number = Some(10)`
- **AND** Episode 294 contains a Scene 10
- **THEN** `merge_schedule_to_scenes` leaves the row unmatched (it SHALL NOT attach it to Episode 294's Scene 10)

### Requirement: Dot-separated Episode.Scene schedule notation and episode-aware merge
Both native CSV schedule parsing and LLM schedule extraction SHALL accept `<Episode>.<Scene>` references (e.g., `"294.10"`, `"03.05"`) and split them deterministically as integer components into `ShootingScheduleRow.episode_number` and `ShootingScheduleRow.scene_number` without decimal float truncation. When `ShootingScheduleRow.episode_number` is present and `MergeInput` provides episode numbers for applied scenes, `merge_schedule_to_scenes` SHALL match rows by `(episode_number, scene_number)`. If no pair matches, it SHALL leave the row unmatched. It SHALL use `scene_number`-only matching only when episode context is unavailable.

#### Scenario: Trailing zero in Episode.Scene is preserved as scene 10
- **WHEN** a schedule row carries scene reference `"294.10"`
- **THEN** it parses to `episode_number = Some(294)` and `scene_number = Some(10)` (never scene 1)

#### Scenario: Multi-episode block schedule merges by episode and scene number
- **WHEN** a block contains applied Scene 10 in Episode 294 and Scene 10 in Episode 295
- **AND** a schedule row carries `episode_number = Some(295)` and `scene_number = Some(10)`
- **THEN** `merge_schedule_to_scenes` attaches the row to Episode 295's Scene 10

### Requirement: Dedicated Decision Model configuration and credential binding
`AiConfig` SHALL support an optional Decision Model configuration (`decision_provider`, `decision_model`, `decision_vault_key_id`) independent of the generative assistant model. Curated decision models SHALL be exposed for `Neuralwatt` (`clef-flash`, `clef`), `EURouter` (`clef-flash`, `metis`), and `OpenRouter` (`cloudflare/clef-flash`, `cloudflare/clef`, `typesafe/jev-1.14`, `perplexity/pplx-decider-flash-v1.2`, `liquid/d1`). When `decision_provider` matches the extraction `provider`, `decision_vault_key_id` MAY reuse `vault_key_id` or bind a separate active `Settings` credential owned by the caller for split billing; when `decision_provider` differs, the API edge SHALL pre-check that `decision_vault_key_id` is an active credential of `decision_provider` owned by the caller.

#### Scenario: Same-provider decision model reuses extraction vault key
- **WHEN** a user configures `provider = neuralwatt`, `decision_provider = Some(neuralwatt)`, `decision_model = Some("clef-flash")`, and `decision_vault_key_id = Some(vault_key_id)`
- **THEN** `AiConfig` accepts and persists the configuration

#### Scenario: Separate billing key for decision model is validated at API edge
- **WHEN** a user supplies a distinct `decision_vault_key_id` for `decision_provider`
- **THEN** the API handler verifies the key is active, owned by the caller, and bound to `decision_provider` before dispatching the command

### Requirement: Non-fatal hybrid scoring for scenes, TL;DR synopses, and shooting days
When a Decision Model is configured, `ScriptImportWorker` and `ScheduleImportWorker` SHALL evaluate each extracted chunk/schedule in a single forward pass via `DecisionClient` combined with deterministic grounding signals to populate `scene_score`, `synopsis_score`, and `shooting_day_score` (`Option<f32>` in `0.0..=1.0`). If no Decision Model is configured or if the decision request fails after bounded retry, the import job SHALL still succeed with the score fields set to `None`. Applying a scored preview SHALL record `scene_score` on `SceneSource::AiExtracted.confidence` and `shooting_day_score` on `ShootingDaySource::AiExtracted.confidence`.

#### Scenario: Decision endpoint outage does not fail script import
- **WHEN** script extraction succeeds for all chunks but the Decision Model endpoint returns 503
- **THEN** `ScriptImportWorker` stores the preview with `scene_score = None`, `synopsis_score = None`, `shooting_day_score = None` and marks the job `Succeeded`

### Requirement: A chunk that extracts no scenes never loses its scene
The script worker SHALL treat a chunk whose extraction returns an empty `scenes`
array as a data-loss event, never as an empty result. Because `extract_scenes`
yields exactly one chunk per detected heading (after duplicate-heading merging),
zero rows for a chunk always means a scene the document has and the preview does
not.

For such a chunk the worker SHALL:
- log a `warn` line carrying the job id, the chunk index/total and the heading;
- push a preview row rebuilt from the deterministic heading — `scene_number`,
  `mood`, `episode` and `shooting_day` as parsed by `extract_scenes`, every
  content field (`location`, `summary`, `characters`, `outfits`, `script_day`)
  empty;
- attach a `DroppedRow` uncertainty with `field = "extraction"` and
  `scene_index` pointing at the rebuilt row.

The job SHALL still reach `succeeded`: the extraction is already paid for and the
reviewer must be able to apply the preserved scene set. The uncertainty kind is
non-blocking by contract, so it never gates the apply.

A chunk that returns one or more rows SHALL NOT be reconciled further: a merged
"index + body" heading pair legitimately yields a single row.

#### Scenario: An empty chunk is rebuilt, not dropped
- **WHEN** a two-chunk script's first chunk extraction returns `scenes: []`
- **THEN** the stored preview carries two rows, the first built from the heading
  (`scene_number`, `mood`, `episode`, `shooting_day`) with empty content
- **AND** the job succeeds

#### Scenario: The degradation is code-keyed and non-blocking
- **WHEN** a row is rebuilt from its heading
- **THEN** the preview carries exactly one `DroppedRow` uncertainty with
  `field = "extraction"` for that row
- **AND** `blocks_apply()` is false for it, so the apply is not gated

#### Scenario: A healthy run synthesizes nothing
- **WHEN** every chunk returns at least one row
- **THEN** `scenes_synthesized = 0` and no `extraction` uncertainty exists

### Requirement: A script preview states detected vs extracted vs rebuilt scenes
`ScriptContext` SHALL carry three additive, `serde(default)` counters, stamped by
the worker at the storing boundary (never taken from the model's answer):
`scenes_detected` (deterministic headings), `scenes_extracted` (rows the model
returned, excluding rebuilt rows) and `scenes_synthesized` (rows rebuilt from a
heading). `scenes.len()` SHALL equal `scenes_extracted + scenes_synthesized`.

A payload stored before the fields existed SHALL still deserialize, with `0` for
each counter meaning "not recorded".

#### Scenario: A shortfall stays visible even when no scene is lost
- **WHEN** a 57-heading document yields 4 model rows and 53 rebuilt rows
- **THEN** the preview exposes `scenes_detected = 57`, `scenes_extracted = 4`,
  `scenes_synthesized = 53`
- **AND** a client can render the shortfall from the payload alone

#### Scenario: Pre-existing previews keep loading
- **WHEN** a preview blob without the counters is read
- **THEN** it deserializes with all three counters `0`

### Requirement: AI-import job telemetry records the scene reconciliation
`Telemetry` and `JobTelemetrySummary` SHALL carry the same three counters, and the
queue SHALL persist them as additive `NOT NULL DEFAULT 0` columns on
`ai_import.ai_import_job`. The owner-fenced worker telemetry write SHALL record
them; the unfenced apply-path write SHALL NOT touch them (the completion-time
telemetry snapshot is immutable). Schedule and merge jobs SHALL record zeros.

#### Scenario: The counters survive the round trip
- **WHEN** a worker records `scenes_detected = 57`, `scenes_extracted = 4`,
  `scenes_synthesized = 53`
- **THEN** the columns hold those values and the job's
  `JobTelemetrySummary` exposes them

#### Scenario: A single divergent job is greppable
- **WHEN** the model's row count differs from the detected heading count
- **THEN** the worker logs one `warn` line naming `scenes_detected`,
  `scenes_extracted`, `scenes_synthesized` and the preview row count

### Requirement: Terminal AI-import jobs carry no live progress
An `AiImportJob` in a terminal status (`succeeded`, `dead_letter`,
`payload_unavailable`) SHALL expose `progress = null`. `progress` describes the
live stage of a **running** job, so the queue SHALL clear the column in the same
statement that lands a terminal status (`mark_succeeded`, the dead-lettering
branch of `mark_failed`, and `mark_payload_unavailable`). The retryable `failed`
branch SHALL keep its progress — that job still has a future — and the
claim-time reset SHALL stay, so a re-claimed job never flashes a previous
attempt's stage.

#### Scenario: A completed job drops its stage
- **WHEN** a worker completes a job whose last published frame was
  `stage = storing_preview`
- **THEN** the `succeeded` job carries `progress = null` and no consumer renders
  a stage for it

#### Scenario: A dead-lettered job drops its stage
- **WHEN** `mark_failed` exhausts the retry budget and lands `dead_letter`
- **THEN** `progress` is cleared in the same statement

#### Scenario: A retryable failure keeps its context
- **WHEN** `mark_failed` schedules another attempt (`status = failed`)
- **THEN** `progress` is preserved until the next claim replaces it

### Requirement: An AI-import job carries the uploaded document's file name
An upload SHALL accept an optional percent-encoded UTF-8 `X-Document-Filename`
header naming the uploaded document. The server SHALL decode and sanitize it
(basename only, no path separators or control characters, collapsed whitespace,
bounded length) and persist it as an additive, nullable
`AiImportJob.source_file_name`. A request without the header, and every job
created before the field existed, SHALL expose `null` — an honest absence, never
a fabricated or `source_handle`-derived name. The raw-body upload contract
(content types and their `415` rejections) SHALL be unchanged.

#### Scenario: A named upload is attributable
- **WHEN** a client uploads `Erlösung Skript.pdf` with the percent-encoded name
- **THEN** the resulting job exposes `source_file_name = "Erlösung Skript.pdf"`

#### Scenario: A hostile header is sanitized, never echoed
- **WHEN** a client sends a name containing a path (`../../etc/passwd`), newlines
  or 400 characters
- **THEN** the persisted value is the bounded basename with control characters
  removed — or `null` when nothing printable remains

#### Scenario: An unnamed upload stays honest
- **WHEN** a client uploads without the header
- **THEN** `source_file_name` is `null` and the client renders the kind/date
  title unchanged

### Requirement: A successful script apply records its target episodes
A successful script apply SHALL attempt to persist the resolved target episodes
on the job as an additive `applied_episodes` list, each entry carrying the
episode id, its optional number, its optional name and the number of scene rows
this job applied into it. The list SHALL be derived from the apply path's own
plan and target data (enriched at the API edge, which is the only legitimate
read-model consumer) — never from a second projection lookup inside the write
path. `POST /v1/ai-import/jobs/{id}/apply` SHALL return the same list, whether or
not the column write succeeded. A schedule apply, which has no single target
episode, SHALL record an empty list rather than an invented one.

The persistence is **best-effort by design**: the scene rows are already
committed when it runs, so a failed write SHALL NOT fail the apply. In that case
the job keeps an empty list and every client falls back to its existing
kind/date copy — the same degradation an unnamed job uses. Durable recovery is
out of scope: it would require a persisted source for the summary that survives
the failed write.

A row SHALL only be attributed to an episode when **this** apply dispatched it.
A row whose mapping an earlier attempt already confirmed stays where that
attempt put it, so it SHALL NOT be attributed to the retry's target — neither by
id nor by label — because the retry's target need not be the scene's home. The
persistence SHALL therefore **merge** instead of replace: a known episode's
`applied_count` is accumulated with the rows the later apply dispatched, a new
episode is appended, and an empty list is a no-op. A re-apply of an applied preview contributes nothing and the earlier,
correctly attributed summary survives; a partially applied job adds the episodes
it reached later.

A number/name SHALL only be recorded when it is authoritative for the row's
persisted location. Concretely: the plan's requested `Create` target SHALL label
an entry only when **this** apply created that episode (a reapply keeps the
mapped episode, whose number/title come from the first apply). An episode the API
edge resolved before dispatch labels its entry. Otherwise the entry SHALL keep
its `applied_count` with `number` and `name` unset — a count without a name,
never a name that contradicts the stored episode.

#### Scenario: A single-episode import names its target
- **WHEN** a script apply lands 57 rows in episode 299 "Erlösung"
- **THEN** the job exposes one `applied_episodes` entry (`number = 299`,
  `name = "Erlösung"`, `applied_count = 57`) and the apply response returns it

#### Scenario: A multi-episode import reports every target
- **WHEN** a script apply lands rows in three episodes through episode groups
- **THEN** the job exposes three entries, each with its own `applied_count`

#### Scenario: A schedule apply invents no episode
- **WHEN** a schedule apply merges onto the project's existing scenes and days
- **THEN** `applied_episodes` is empty and the client falls back to its existing
  row copy

#### Scenario: A failed summary write degrades instead of failing the apply
- **WHEN** the scene rows applied successfully but persisting the summary fails
- **THEN** the apply still answers `200` with what it dispatched in its body, the
  job keeps the list from its earlier successful applies (or an empty one), and a
  client without a name renders its kind/date copy

#### Scenario: A reapply with a changed create target adds nothing
- **WHEN** an episode group already has a mapping and the reapply carries a
  changed `Create` target
- **THEN** the reapply contributes no entry — the persisted episode keeps the
  first apply's number/title, and the earlier entry survives the merge

#### Scenario: A later apply accumulates the count
- **WHEN** an earlier apply recorded 57 rows for episode A and a later apply
  dispatches 3 more into it
- **THEN** the summary reports 60 for A, not 3

#### Scenario: An already-applied row is never re-attributed
- **WHEN** the first apply lands a scene in episode A and a retry targets
  existing episode B (B resolvable at the API edge)
- **THEN** the retry's response carries no entry for that row, the job keeps A's
  entry, and B is never recorded

#### Scenario: A re-apply cannot erase the summary
- **WHEN** a retry finds every row already applied and therefore reports none
- **THEN** the merge is a no-op and the persisted summary still names the
  original episodes

### Requirement: The job records the Decision Model scoring outcome
Every import job SHALL record what its optional Decision Model scoring pass did,
as an additive `decision_telemetry` on the `AiImportJob` view:
`provider` and `model` (the pair the job **resolved**), an `outcome` class and
`failed_rows`. The outcome SHALL be one of exactly
`ran` (the pass answered), `skipped_no_config` (no configuration resolved),
`client_unavailable` (configured, but the decision client could not be built),
`scoring_failed` (the pass ran and at least one unit failed after the bounded
retry) or `skipped_not_applicable` (the job had nothing to score: a native CSV
schedule, or a pure merge). The record SHALL be written by the same
owner-fenced completion write as the extraction telemetry, so it can never
describe a run that did not happen. `provider`/`model` SHALL be present for
`ran`, `client_unavailable` and `scoring_failed` — a configured pair is named
even when it produced nothing, which is what distinguishes "never configured"
from "configured but unavailable". `failed_rows` SHALL count the preview rows
whose own scoring request failed (one missed unit counts its rows, never the
job).

#### Scenario: A configured pass ran
- **WHEN** a script job resolves a decision triple, builds its client and every scoring request answers
- **THEN** its `decision_telemetry.outcome` is `ran`, `provider`/`model` name the resolved pair and `failed_rows` is `0`
- **AND** the preview rows carry non-null `scene_score`/`synopsis_score` with a rubric naming that same pair

#### Scenario: The decision client could not be built
- **WHEN** the resolved decision configuration's credential fetch or transport build fails
- **THEN** the job still succeeds, no scoring request is issued and every score stays `null`
- **AND** `decision_telemetry.outcome` is `client_unavailable` with the resolved `provider`/`model`

#### Scenario: No decision configuration resolved
- **WHEN** a job is claimed for a user whose AI config carries no decision triple
- **THEN** the job runs without a scoring pass
- **AND** `decision_telemetry.outcome` is `skipped_no_config` with no provider/model

#### Scenario: The scoring request failed
- **WHEN** a scoring request fails after the bounded quick retry
- **THEN** the job still succeeds, the affected rows keep a rubric with `scoring_failed: true` and no score
- **AND** `decision_telemetry.outcome` is `scoring_failed` and `failed_rows` equals the number of rows left unscored

#### Scenario: A job recorded before the field existed
- **WHEN** a client reads a job stored before `decision_telemetry` existed
- **THEN** the field deserializes as `null` (never a fabricated outcome)
- **AND** the job remains readable through every existing route

### Requirement: The four Decision Model degradation paths are greppable
The worker SHALL log the previously traceless path — a claim that resolves no
decision configuration — at `info` with the `job_id` and the resolved
`config_id`, and SHALL keep the `warn` records for the credential/build failure
and the scoring failure. No decision-scoring degradation may be silent.

#### Scenario: A missing decision configuration is logged
- **WHEN** a claimed job resolves an AI config with no decision triple
- **THEN** an `info` record carries the `job_id` and the `config_id`
- **AND** the same `job_id` appears in the `warn` records of the other three failure paths when they occur

### Requirement: The configured scoring path is covered end to end
The configured Decision Model path SHALL be asserted through the production
worker with a fake decision client (non-null scores, rubric provider/model
matching the configuration, `ran` outcome), and each degradation path SHALL be
asserted for its outcome class, its row count and its "the job still succeeds"
guarantee.

#### Scenario: A configured Decision Model yields scores
- **WHEN** the test suite processes a script job with a configured decision triple and a fake decision client
- **THEN** the preview rows carry non-null `scene_score`/`synopsis_score`
- **AND** their rubric's `decision_provider`/`decision_model` equal the configured pair

### Requirement: A blocked apply run names its own liveness

The registered `409 ai-import.apply-in-flight` refusal SHALL carry, as its
declared S1 extensions, the two facts that let a client tell a live apply run
from an abandoned one instead of waiting blindly:

- `stale_after_seconds` — the server's own staleness window
  (`ApplyProgress::STALE_AFTER`). It SHALL be emitted on every such refusal, so
  no client has to mirror the constant.
- `apply_run_age_seconds` — how long the owning run had been silent when the
  refusal was emitted, measured against the server's own clock from the owner's
  last published payload. It SHALL be omitted (never emitted as zero) when that
  run has published nothing yet, and a failure to read the run slot SHALL omit
  the age rather than change the refusal into a different error.

The age SHALL be a duration, not an absolute timestamp, so a client whose clock
is wrong cannot misclassify a live run as abandoned. A payload older than the
window SHALL mean the server itself considers it abandoned — the next atomic
claim would steal the slot — while a payload inside the window (including one
exactly AT it, because the claim's comparison is strict) means the run is live.

The refusal SHALL NOT change: it remains a `409` with no new problem code, and
the single-flight claim stays the authority. Emitting the extensions is additive
metadata over an unchanged status and code.

#### Scenario: A live run blocks the refusal and names its age

- **WHEN** a second apply of a `succeeded` job is refused while the owning run
  published its payload four minutes ago
- **THEN** the `409 ai-import.apply-in-flight` carries
  `stale_after_seconds = 600` and `apply_run_age_seconds` measured from that
  payload
- **AND** the client can conclude that the run is live, because the age is
  inside the server's window

#### Scenario: An owner that published nothing carries no age

- **WHEN** a second apply is refused while the owning run has claimed the slot
  but written no progress frame
- **THEN** the refusal carries `stale_after_seconds` and NO
  `apply_run_age_seconds`
- **AND** no age of zero is reported, because a run that said nothing has no
  liveness to report

#### Scenario: The window is the server's single definition

- **WHEN** `ApplyProgress::STALE_AFTER` changes
- **THEN** every refusal's `stale_after_seconds` follows it with no second
  constant to update, and no client-side mirror exists to drift

### Requirement: Acknowledgement set semantics

An uncertainty acknowledgement SHALL be identified by its
`(scene_index, field)` pair, and that pair SHALL be the entire payload. A
repeated pair in `ApplyAiImportRequest.uncertainty_acknowledgements` SHALL be
**idempotent**: the API edge SHALL NOT refuse the request, because the
acknowledgement list is set-shaped by nature (the apply gate matches
acknowledgements by pair, and no ordering or last-write semantics exist to
lose). Every acknowledgement — including a repeat — SHALL still be validated
against the stored preview: an acknowledgement that references no blocking
uncertainty the preview carries SHALL be refused as a client bug.

#### Scenario: A repeated acknowledgement applies successfully

- **WHEN** an apply request carries the same `(scene_index, field)` pair twice
  and that pair is a blocking `field_ambiguity` of the stored preview
- **THEN** the request is accepted and reaches the apply worker
- **AND** no `422 domain.validation` is returned for the repetition

#### Scenario: A repeat cannot smuggle in an unknown pair

- **WHEN** an apply request repeats a pair the preview does not carry as a
  blocking uncertainty
- **THEN** the request is refused before any command is dispatched

#### Scenario: Duplicate pairs do not over-acknowledge

- **WHEN** a preview carries several blocking entries for one pair and the
  request acknowledges that pair
- **THEN** every entry of that pair counts as acknowledged by the gate

### Requirement: A transient LLM-provider failure is attributed to the provider

A transient failure **of the LLM provider** SHALL be classified with the
registered problem code `ai-import.llm-provider-unavailable` (HTTP 503,
retryable) instead of the generic `domain.service-unavailable`, so the recorded
attempt names the failing dependency from a stable signal rather than from its
free-form summary. The code SHALL reuse the existing retryable service-unavailable
error shape, so retryability, backoff, the retry budget and the attempt-persistence
path are unchanged: only the attempt's `code` (and therefore the localized
client narrative) moves.

The provider attribution covers exactly the chat client's transient
classifications:

- an HTTP 429 or 5xx answer from the provider (with the bounded provider-detail
  suffix preserved), and
- a transport timeout or connect failure against the provider.

Every **other** import pipeline dependency SHALL keep
`domain.service-unavailable`: the mapping DB, the pricing read model, payload
storage and the model catalog are not the provider, and no attempt row can
honestly attribute a failure to it. A provider response that is a deterministic
policy rejection (permanent validation, redirect violation) and a rejected
credential (`dependency.auth-failed`, #637) keep their existing codes — this
change adds attribution, it does not reclassify retryability.

The code SHALL NOT be derived from `error_summary`/`last_error` anywhere: the
summary is log text and stays secondary detail.

#### Scenario: Consecutive provider 503s are recorded as provider failures

- **WHEN** a script import's LLM call answers HTTP 503 three times on
  consecutive attempts
- **THEN** each attempt row carries `code = ai-import.llm-provider-unavailable`
- **AND** each attempt is `retryable = true`, the job keeps backing off with
  `next_attempt_at`, and its retry budget is consumed exactly as before

#### Scenario: A storage-database failure is not attributed to the provider

- **WHEN** the mapping DB read fails while recording extracted rows
- **THEN** the attempt carries `code = domain.service-unavailable`
- **AND** it is not rendered as a provider outage (the generic transient
  narrative is used)

### Requirement: The jobs list read carries attempt history

`GET /v1/ai-import/jobs` SHALL populate every returned job's `attempts` with its
newest attempts, using **the same per-job bound the single-job read uses**, in
one batch read for the page — never one query per job. The shared bound is a
correctness requirement: a client aggregates the consecutive newest
provider-attributed attempts into a count, so a shorter window on one surface
would make the compact list row report fewer failures than the status card for
the same job. The list
surface exists before the user opens any job, so a client that derives a
degraded-provider state from attempt history SHALL be able to derive the **same**
state from a list row as from the single-job read; publishing only `last_error`
(or nothing) would force either free-form parsing or a second per-row read, both
rejected.

The field is unchanged on the wire (`attempts`, already `serde(default)` and
already documented as additive), so a client that ignores it is unaffected, and
a pre-#822 row still reads.

#### Scenario: A list row names the provider failures it has

- **WHEN** a job has three recorded attempts whose codes are all
  `ai-import.llm-provider-unavailable`
- **THEN** the job appears in `GET /v1/ai-import/jobs` with those attempts
  (newest first) populated, and the page is read in a bounded number of queries
  regardless of its row count

### Requirement: The import SHALL read the block the script states

A script extraction SHALL read the production block number out of the document's
page headers, independently of the block that was active at upload:

- The deterministic scan SHALL accept the observed header shapes — `Block: 2`,
  `Block 2`, and the glued `Block: 098/Ep.: 294` — reading the **leading digits
  only** (everything after a `/` belongs to the next field).
- The scan SHALL be shape-driven rather than casing-driven: page headers also
  arrive in capitals, while `Block` capitalizes in German prose too. A marker
  SHALL therefore require 1-3 digits, a non-alphanumeric digit boundary, and a
  field boundary behind the number (end of line, a `/`/`|`/`·` separator, or an
  uppercase letter starting the next header field). Prose and scene headings
  SHALL NOT parse.
- The scan SHALL cost no LLM tokens.
- Page headers repeat the marker on every page; the FIRST occurrence SHALL win,
  and a repeated header SHALL NOT flip the published value.
- When the deterministic scan finds no marker, the extraction SHALL accept the
  model's answer as a fallback, which requires the field to be declared in the
  provider-facing strict schema (a prompt rule without a schema field is
  unreachable under `strict` Structured Outputs).

#### Scenario: A page header states the block on every page

- **GIVEN** a script whose pages are headed `Block: 2   Ep.: 3 (Der Unfall)`
- **WHEN** the extraction runs
- **THEN** every progress frame names block `2`
- **AND** the stored preview carries `block_number: 2`

#### Scenario: The header glues the block and the episode

- **GIVEN** a page header `Block: 098/Ep.: 294`
- **WHEN** the scan reads it
- **THEN** the block is `98`
- **AND** the episode is `294` (the suffix is never part of either number)

#### Scenario: Prose mentions a block, the header states none

- **GIVEN** a script whose body says `Block 2 wurde am Montag gedreht.`
- **WHEN** the scan runs
- **THEN** no block is published (`block_number` stays absent)
- **AND** no block number is inferred from the episode or the scene numbering

### Requirement: The script's block SHALL be published separately from the import target

`AiImportProgress` SHALL carry the block the script states as its own additive,
nullable field, distinct from the job's import target:

- `block_number: Option<i32>`, additive with `serde(default)`, so frames and
  previews written before the field existed deserialize as `None`.
- `None` SHALL mean "the script does not state a block" — never a fabricated
  number and never the target echoed back.
- The import target (`AiImportTarget.block_number`) SHALL keep meaning "the block
  this import writes into"; this change SHALL NOT alter the target.
- A client SHALL render the two side by side and flag a mismatch non-blocking.

#### Scenario: The script disagrees with the target

- **GIVEN** a job whose target block is `1` and a script headed `Block: 2`
- **WHEN** the client renders the progress or preview surface
- **THEN** both numbers are visible ("Skript: Block 2 · Importziel: Block 1")
- **AND** the mismatch is flagged without blocking the apply

#### Scenario: The script states no block

- **GIVEN** a script without a block marker and a job whose target block is `1`
- **WHEN** the client renders the scope line
- **THEN** the target is shown as the associated block with explicit wording
- **AND** no number is invented for the script

### Requirement: The blocked-apply age also covers a claim that published no frame

The `409 ai-import.apply-in-flight` refusal SHALL report
`apply_run_age_seconds` for **every** run that owns the apply-run slot,
including a run that claimed the slot and has published no progress frame
yet. The age SHALL be derived from the same owner-scoped timestamp the
single-flight claim's steal predicate judges an unpublished owner by — the
instant that run's own claim took the slot (`apply_claim_at`) — so the reported
age and the steal decision can never disagree, and no other run's write can move
either:

- a run that published a frame SHALL be aged from that payload's
  `updated_at` (the stamp the claim compares once a payload exists);
- a run without a payload SHALL be aged from its claim instant;
- a run whose slot reports no claim instant at all SHALL yield no age (the
  extension stays absent), never an age of zero.

The claim instant SHALL be written by the claim and by nothing else. It SHALL
NOT be the job row's `updated_at`, which every run-scoped write bumps —
including a previous apply's post-apply summary, which can land after the next
claim and would then understate that owner's silence. A claim predating the
column SHALL keep the pre-existing steal fallback (the row stamp) while
reporting no age, so a rolling deploy never makes a live claim stealable.
`stale_after_seconds` SHALL keep its meaning (`ApplyProgress::STALE_AFTER`), and
the refusal SHALL keep its status, code and extensions — the change is additive
metadata over an unchanged vocabulary.

#### Scenario: A claim that never published still carries its own age

- **WHEN** an apply claims the slot of a `succeeded` job and publishes no
  progress frame, and a second apply is refused inside the server's window
- **THEN** the refusal carries `stale_after_seconds` AND
  `apply_run_age_seconds` measured from the claim instant
- **AND** the client can reach its takeover affordance once that age exceeds
  the window, instead of waiting the window out with no information

#### Scenario: One timestamp decides both the age and the steal

- **WHEN** an unpublished owner's claim instant is older than the server's window
- **THEN** the next claim steals the slot
- **AND** the refusal reported the same instant as `apply_run_age_seconds`, so a
  client verdict of "abandoned" matches the server's own

#### Scenario: Another run's late write cannot extend the window

- **WHEN** a previous apply's post-apply summary (or any other run-scoped write)
  lands after the next claim took the slot
- **THEN** the reported `apply_run_age_seconds` is unchanged — the claim instant
  is owner-scoped
- **AND** the steal fires at the owner's own window, not later

#### Scenario: No stamp degrades to no age

- **WHEN** the apply-run slot reports neither a payload nor a claim instant
- **THEN** `apply_run_age_seconds` is absent rather than zero
- **AND** the client renders its unaged card, claiming neither liveness nor
  abandonment

### Requirement: The applied-episode summary is derived from the durable apply mappings

`AiImportJob.applied_episodes` SHALL be derived at the **read edge** from the
durable apply mappings, and SHALL NOT be written by the apply path. This
supersedes the persistence clause of the #763 requirement "A successful script
apply records its target episodes": the wire field, its meaning and its
consumers stay, the best-effort write behind it does not.

Derivation SHALL be: every `projection_ai_import_mapping` row of the job whose
`aggregate_kind` is `scene`, joined to the scene it names and to that scene's
episode, counted per episode. Each entry SHALL carry the episode id, the
persisted episode's own `number`/`name` (honest absence when the projection does
not know the episode), and the number of the job's rows mapped into it. Entries
SHALL be ordered by episode number, with the episode id as the tiebreak, so two
reads of an unchanged job agree.

The derivation SHALL be performed where the read model is legitimately read —
the job read (`GET /v1/ai-import/jobs/{id}`, its event stream) and the jobs list,
the latter in ONE query per page, never one per job. The write path SHALL NOT
consult a projection to produce it (CQRS boundary, `AGENTS.md` §1).

Consequences the derivation SHALL guarantee:

- an apply that committed rows leaves its summary resolvable **even when the
  client disconnected before the response**, because no write has to survive the
  cancelled handler future;
- a mapping that is still **reserved** (an id claimed, no command appended) SHALL
  NOT count — it is not applied work;
- a **schedule** apply, which writes only `scene_shoot`/`shooting_day` mappings,
  SHALL derive an empty list rather than an invented target;
- a row reconciled onto an **existing** scene SHALL be attributed to that scene's
  episode;
- a failure to derive SHALL be display-metadata loss only: an empty list and a
  logged warning, never a failed job read and never an unreachable job.

The `POST /v1/ai-import/jobs/{id}/apply` response SHALL keep reporting what that
request dispatched, from the apply's own plan — it answers "what did this request
do", not "where are this job's rows", and SHALL NOT wait for projector catch-up.

#### Scenario: A committed apply is readable after the client disconnected

- **WHEN** an apply commits scene rows and the client drops the request before
  the response, so no post-apply write runs
- **THEN** `GET /v1/ai-import/jobs/{id}` still lists the episodes those rows
  landed in, with their row counts

#### Scenario: A re-apply of an applied preview keeps the summary

- **WHEN** an apply re-runs a preview whose rows are all settled by confirmed
  mappings and therefore dispatches nothing
- **THEN** the job's summary still names where the earlier run put the rows, and
  the response's empty list does not erase it

#### Scenario: A schedule apply names no episode

- **WHEN** a schedule apply merges onto the project's existing scenes and days
- **THEN** the derived summary is empty and the client falls back to its existing
  row copy

#### Scenario: A job that was never applied stays distinguishable

- **WHEN** no row of the job is mapped to a projected scene
- **THEN** the summary is empty — the same answer as a job whose apply was
  cancelled before its first commit, and never a fabricated entry

#### Scenario: A row reconciled onto an existing scene is attributed to its home

- **WHEN** an apply updates an existing scene that lives in a different episode
  than the one the request named
- **THEN** the entry carries that scene's episode, not the request's target

#### Scenario: The list and the single read agree

- **WHEN** the jobs list and `GET /v1/ai-import/jobs/{id}` are read for the same
  job
- **THEN** both return the same summary, and the list pays one derivation query
  for the whole page

### Requirement: A live apply run keeps its single-flight slot while it executes

The apply slot SHALL be single-flight per job, and an owner that is still executing SHALL
keep it no matter how long the run takes. Because the slot's staleness predicate is
silence-based, an executing run SHALL renew its own claim (owner-fenced on the run
identity) while it works: a schedule apply publishes no progress frames, so silence alone
cannot distinguish it from a crashed owner.

The renewal SHALL only prove aliveness — it SHALL NOT write progress, advance the run
counter, or wake the apply stream. It SHALL be bounded by the same window the steal
predicate reads (`ApplyProgress::STALE_AFTER`), renewed at a strict fraction of it.

Every silence predicate (both steals, the takeover and the worker poll) SHALL judge an
owner by the **newer** of its last published frame and that lease stamp, and the age
reported in a `409 ai-import.apply-in-flight` SHALL be derived from the same pair — a
renewing run SHALL NOT be stealable on the strength of an old frame, and the reported age
SHALL NOT claim that it is.

#### Scenario: A schedule run longer than the staleness window is not stolen

- **WHEN** a schedule apply has been executing for longer than `ApplyProgress::STALE_AFTER`
- **AND** it renews its claim during that time
- **THEN** a second dispatch SHALL be refused (`409 ai-import.apply-in-flight`)
- **AND** the worker poll SHALL NOT hand the slot to another replica

#### Scenario: An old frame plus a live renewal keeps the slot

- **WHEN** a run's last published frame is older than `ApplyProgress::STALE_AFTER`
- **AND** its lease renewal is newer than that window
- **THEN** neither a second dispatch, nor the worker poll, nor a takeover SHALL claim the slot
- **AND** the `409` SHALL report the renewal's age, not the frame's

#### Scenario: A dead owner still becomes stealable

- **WHEN** the process owning a `running` apply slot dies
- **THEN** the renewals SHALL stop with that run's task
- **AND** after `ApplyProgress::STALE_AFTER` the next poll SHALL take the slot over
- **AND** the displaced run's renewal SHALL report `false` instead of renewing

### Requirement: Both surfaces that report an apply outcome name the run that produced it

Every HTTP surface that reports an apply run's state SHALL carry the identity of
the run that produced the reported outcome — `apply_run_id` on
`GET /v1/ai-import/jobs/{id}` and `run_id` on every `apply-events` frame. The
identity SHALL be resolved by one rule: the run that currently **owns** the
job's apply slot while it is live, otherwise the run recorded next to the
persisted outcome (ownership is released at the terminal transition so the slot
frees immediately, while attribution must survive).

A client compares this id against the run id its dispatch returned before
believing an outcome is its own, so a surface that omits or invents it makes a
client report another run's counters as its own import.

#### Scenario: a live run is reported by both surfaces

- **WHEN** a run owns the job's apply slot and has published progress
- **THEN** `GET /v1/ai-import/jobs/{id}` SHALL report that run's id as `apply_run_id`
- **AND** the `apply-events` frames SHALL report the same id as `run_id`

#### Scenario: a finished run keeps its identity after ownership is released

- **WHEN** a run reaches a terminal apply state
- **THEN** the slot SHALL free immediately (a subsequent dispatch is accepted without a staleness wait)
- **AND** both surfaces SHALL still report the finished run's id, not `null` and not the id of a run that has not started

#### Scenario: a later run supersedes the earlier one on both surfaces

- **WHEN** a second run claims the freed slot and finishes
- **THEN** both surfaces SHALL report the second run's id
- **AND** a client still holding the first run's id SHALL be able to detect the supersession by comparing them

#### Scenario: the composition of both surfaces is covered

- **WHEN** the CI runs the container-gated composition case for this chain
- **THEN** a handler that stops surfacing `apply_run_id` on the job read SHALL fail it
- **AND** a handler that stops surfacing `run_id` on the terminal frame SHALL fail it

### Requirement: Provider retry classification and hints are computed in one place

Every provider-HTTP call site in `infra` SHALL classify a response and read its
server-side retry hint through one shared, pure retry core
(`crates/infra/src/retry.rs`), so the follow-ups that honour `Retry-After` and
separate quota-exhausted `429`s change a scheduling decision instead of five
call sites.

The core SHALL expose:

- a status classification — `429` and every `5xx` **retryable**, every other
  `4xx` **rejected**, everything else (1xx/3xx/non-standard) **unexpected** —
  which the `DomainError` mapping consumes at the call boundary, so the error
  taxonomy stays unchanged;
- a hint type that is owned and free of any lifetime tied to the response
  (`wait`, `limit_remaining`, `limit_reset` plus the classification), because
  `reqwest::Response` is moved by the body read;
- the wait strategies the sites actually use (a fixed pause, the projector's
  equal jitter, the archival worker's full jitter) as one implementation each.

#### Scenario: The hint is read before the body is consumed

- **WHEN** a call site receives a provider response
- **THEN** it SHALL capture the hint from the response headers before it calls
  `.text()`/`.json()` (which move the response)
- **AND** reading the hint SHALL NOT change the request, its timing, its budget
  or its error classification.

#### Scenario: A malformed hint never fails a request

- **WHEN** a header the parser reads is absent, unparsable (`Retry-After:
  soon`), unreadable (non-ASCII bytes) or absurd (a wait beyond one day)
- **THEN** the corresponding hint field SHALL be `None`, or be capped at one
  day
- **AND** the request SHALL keep its ordinary outcome: a `2xx` body still
  decodes, and a non-`2xx` status still maps to the same `DomainError` variant
  as before the hint existed
- **AND** no panic and no validation error SHALL be raised for a bad header.

#### Scenario: No site's timing changes

- **WHEN** the retry core is adopted by an existing call site
- **THEN** that site's pre-existing timing, budget and error taxonomy SHALL be
  preserved: the in-attempt retry keeps its exponential pause (500 ms base,
  30 s cap, ≤25 % jitter), the decision pass keeps its single fixed pause, the
  truncation and Ollama parse loops keep re-requesting without a pause, and the
  catalog refresh keeps its interval ticker
- **AND** where a policy was implicit in a loop, a test SHALL pin it.

#### Scenario: The retry hint is observability only

- **WHEN** a provider sends `Retry-After` or `X-RateLimit-*` headers
- **THEN** the site SHALL log the hint at `debug` level and act on it in no
  other way
- **AND** honouring the hint SHALL be a separate, later change.

### Requirement: A provider's retry hint bounds every scheduler that already exists

A `429`/`5xx` response that carries `Retry-After` (or `X-RateLimit-Reset`) SHALL
propagate that wait **as data** out of the provider call and into the schedulers
that already exist — the in-attempt retry, the job-level `next_attempt_at`, the
breaker probe schedule and the provider hold — as a **minimum** delay. The hint
SHALL NOT be slept through inside the provider call, because that call holds an
`ai_import.concurrency_permit` for the whole sleep.

Every scheduler SHALL clamp the hint to a documented bound, so the analytic
worst case of one attempt stays a computed number and no provider can order an
unbounded permit-hold or an unbounded queue freeze.

#### Scenario: The hint lifts the in-attempt backoff, bounded at 120 s

- **WHEN** a provider answers `429` with `Retry-After: 5` and the computed
  exponential backoff for that attempt is smaller
- **THEN** the in-attempt retry SHALL wait 5 s instead of the computed delay
- **AND** the jitter SHALL stay on the computed backoff, so the hint is a floor
  and not a target
- **AND** a hint above `MAX_IN_ATTEMPT_HINT_SECS` (120 s) SHALL be clamped to
  it, with the computed backoff unchanged when it is already larger.

#### Scenario: The hint beats the job-level ladder, clamped to 6 h

- **WHEN** a retryable attempt fails with a hint and the job keeps its retry
  budget
- **THEN** `next_attempt_at` SHALL be `now + max(ladder, min(hint, 6 h))`
- **AND** a hint larger than the ceiling SHALL be clamped and logged, so a
  `Retry-After: 86400` cannot freeze the queue for a day
- **AND** a failure without a hint SHALL leave the `1 min × 2^retries` ladder
  byte-identical to the pre-hint behaviour.

#### Scenario: A known hint defers the probe instead of being rediscovered

- **WHEN** a provider failure carrying a hint is recorded for a `(provider,
  model)` pair
- **THEN** the breaker's `retry_at` SHALL be the later of the open window and
  the clamped hint
- **AND** the probe task SHALL therefore not probe that pair before the hint
  expires
- **AND** a job held while the breaker is open SHALL carry the same instant as
  its `ProviderHold.until`, keeping #822's registered
  `ai-import.llm-provider-unavailable` code rather than adding a problem code
  for rate limiting.

#### Scenario: The attempt narrative names the rate limit

- **WHEN** an attempt fails because the provider rate-limited it
- **THEN** the persisted attempt row's narrative SHALL name the rate limit (and
  the wait the provider asked for)
- **AND** the text SHALL be produced at the `infra` classification boundary
  from the same value as the typed hint, never re-derived from it (ADR-031: no
  string building in `core`).

#### Scenario: A hint never changes the classification

- **WHEN** any response carries a hint
- **THEN** its `DomainError` variant, problem code, HTTP status and retryability
  SHALL be identical to the same response without a hint
- **AND** a malformed or absurd header SHALL degrade to "no hint", never to an
  error or a panic.

#### Scenario: The documented worst case matches the code

- **WHEN** `AiImportBounds::attempt_worst_case_secs` renders the window one
  attempt may occupy a permit
- **THEN** its backoff term SHALL use
  `max(MAX_ATTEMPT_BACKOFF_SECS, MAX_IN_ATTEMPT_HINT_SECS)`
- **AND** the defaults SHALL render 22 min for a hosted provider and 28 min for
  Ollama, asserted in `bounds_tests` and mirrored in
  `.github/instructions/ai-import.instructions.md`.

### Requirement: A quota-exhausted `429` is terminal, a rate-limited one is not

A provider `429` SHALL be classified on **response-body evidence**, not on the
status alone: an account-level quota exhaustion (OpenAI `insufficient_quota` /
`credit_balance_exhausted`, Gemini's per-day quota id, OpenRouter's
`free-models-per-day`) SHALL be a **non-retryable** failure, while a per-minute
rate limit SHALL stay retryable.

The classification SHALL use a curated, non-user-configurable per-provider marker
table in the transport layer and SHALL default to **retryable** whenever the
evidence is missing or unreadable — an unparsable body, an empty body, an HTML
gateway page or an unknown code.

#### Scenario: Quota exhaustion dead-letters on the first attempt

- **WHEN** a provider answers `429` with a body naming an exhausted quota
- **THEN** the failure SHALL be non-retryable and the job SHALL be recorded as
  `dead_letter` without consuming another paid call
- **AND** the attempt row SHALL carry the registered
  `ai-import.llm-provider-unavailable` code and a narrative naming the status and
  the **matched** quota code — independent of where that code sits in the
  provider's prose, so the evidence cannot be truncated out of the history
- **AND** the terminal verdict SHALL NOT move the provider breaker counter, so a
  dead-letter can never be converted into a hold.

#### Scenario: A rate limit keeps today's behaviour

- **WHEN** a provider answers `429` with a rate-limit code, or with a body that
  cannot be parsed
- **THEN** the failure SHALL remain the retryable
  `ai-import.llm-provider-unavailable`, with the #926 hint scheduling unchanged
- **AND** a `5xx` carrying a quota-looking body SHALL stay retryable, because the
  evidence table only applies to `429`.

#### Scenario: The error body read is bounded in bytes and in time

- **WHEN** a non-2xx response carries a large or slowly-streamed body
- **THEN** at most 1 KiB SHALL be read, streamed chunk by chunk, **and** the
  whole read SHALL end within `min(5 s, the configured request timeout)` — the
  request timeout is configurable down to 1 s, so a fixed 5 s deadline would
  outlive the request it belongs to
- **AND** the two bounds SHALL be described as **limiting** the job's
  concurrency-permit hold, never as always ending it before the request timeout:
  at the 1–5 s floor of that knob the budget equals the timeout, so the read may
  last as long as the request itself would have. What they guarantee is that the
  read never extends the hold past the request's own timeout, and that at the
  default 120 s it ends after at most 5 s
- **AND** an IO error or the deadline SHALL keep the bytes collected so far and
  SHALL NOT replace the provider's real failure with a parsing error of our own
- **AND** an **incomplete** read SHALL NOT be treated as evidence: it keeps the
  conservative retryable default even when the bytes that arrived contain a
  quota code, because a stream cut by a proxy may have lost the part that
  changes the meaning.

#### Scenario: `402`/`403` stay distinct from `429`

- **WHEN** EURouter answers `402` for a budget cap, or a gateway answers `403`
  for an entitlement
- **THEN** the classification SHALL remain the existing non-retryable rejection
  and SHALL NOT be reported as a quota-exhausted `429`.

### Requirement: The preview distinguishes outfit provenance
The script preview SHALL expose, per outfit row, where the look came from, as ONE
plain wire string of `explicit_quote`, `derived`, `continued_from_scene` or
`inferred_from_context`. The Pass-2 provenance payload SHALL travel in a separate
optional `provenance` object carrying the source draft row reference, the source
scene number when known, and the confidence — never as data on the origin value
itself, because a mixed enum lowers to a `oneOf` whose two single-value string
alternatives make the generated client unable to decode `"explicit_quote"` at
all. The distinction SHALL be additive on the wire, so a preview stored before
the provenance existed still loads and keeps reading as `explicit_quote` with no
provenance.

#### Scenario: Reviewing a continued outfit
- **WHEN** a draft row's outfit continues an earlier scene's look
- **THEN** the preview SHALL report its origin as `continued_from_scene`
- **AND** its `provenance` SHALL name the source draft row and scene number
- **AND** its confidence SHALL be the probability the Decision Model reported

#### Scenario: Preview stored before provenance existed
- **WHEN** a preview stored with the former two-value origin is served
- **THEN** it SHALL deserialize without error
- **AND** every outfit row SHALL keep a valid origin and an empty provenance

#### Scenario: The origin stays client-decodable
- **WHEN** a client decodes any of the four origin values
- **THEN** each SHALL be a plain JSON string
- **AND** no origin value SHALL be modelled as a union of alternatives

### Requirement: A gap uncertainty carries only script-derivable candidates
An uncertainty of kind `dropped_row` on the `outfits` field MAY carry a list of
outfit candidates. Each candidate SHALL declare its origin, its display name,
the draft row it was derived from, and its confidence. The list SHALL be empty
when the script supports no candidate, and the preview SHALL never present an
invented option as a choice.

#### Scenario: Candidate list on a competing gap
- **WHEN** a scene carries a gap uncertainty whose figure has a prior outfit and whose location changed
- **THEN** the uncertainty SHALL carry both candidates
- **AND** each candidate SHALL name its origin and source draft row

#### Scenario: Gap without candidates
- **WHEN** the script supports no candidate for a gap
- **THEN** the uncertainty's candidate list SHALL be empty
- **AND** the preview SHALL still expose the gap as an uncertainty

### Requirement: A continued outfit reuses the source scene's OutfitId
For an outfit row whose origin is `continued_from_scene`, the apply planner
SHALL resolve the source row and the source outfit's ordinal from the immutable
preview and SHALL plan NO new pieces and NO new outfit. The apply worker SHALL
resolve the source outfit's aggregate id from the persisted apply mapping and
dispatch only the scene's outfit beat against that exact id, so the two scenes
cast the same `Outfit` (reference by identity, no duplicate aggregate). When the
source row or its outfit cannot be resolved in the preview, the plan SHALL
report the row as unapplied with a reason distinct from the create/beat
failures instead of creating a look of its own; when the source outfit's mapping
row does not exist or never reached its create, the worker SHALL report the same
distinct reason rather than fabricating an id.

#### Scenario: Two scenes share one outfit
- **WHEN** an accepted preview contains a scene-4 outfit and a scene-5 continuation of it
- **THEN** the apply SHALL create exactly one `Outfit` for that figure
- **AND** both scenes SHALL carry an outfit beat referencing it
- **AND** re-applying the preview SHALL add no second `Outfit` and no second beat

#### Scenario: Continuation whose source was rejected
- **WHEN** the reviewer rejects the source outfit row while accepting the continuation
- **THEN** no `Outfit` SHALL be created for the continuation
- **AND** the apply result SHALL report it as unapplied with the continuation reason

### Requirement: The reviewer may resolve a gap by selecting a candidate
The apply request SHALL accept, per gap, an optional selection of one of the
candidates the preview offered for that scene and character. A selection SHALL
be validated against the preview's own candidate list — an unknown scene index,
an unknown character identity or a candidate the preview does not offer SHALL be
refused as a client error. An accepted selection SHALL be planned as an outfit
row of its scene: a continuation selection plans as a
`continued_from_scene` row (no created look), a context selection plans as an
`inferred_from_context` row carrying the candidate's label and no pieces. A gap
without a selection SHALL apply without an outfit — never with an invented one.

#### Scenario: Reviewer picks the continuation
- **WHEN** the apply request selects the continuation candidate for a gap
- **THEN** the scene's beat SHALL reference the prior scene's `Outfit`
- **AND** no new `Outfit` SHALL be created for that row

#### Scenario: Reviewer picks nothing
- **WHEN** the apply request carries no selection for a gap scene
- **THEN** the scene SHALL apply without an outfit
- **AND** the apply SHALL NOT fail because of the gap

#### Scenario: Selection the preview never offered
- **WHEN** the apply request selects a candidate for a scene/character pair the preview does not carry as a gap
- **THEN** the apply SHALL be refused as a validation error
- **AND** no aggregate SHALL be dispatched

