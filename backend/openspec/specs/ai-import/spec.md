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
replayable. The merge SHALL read the Scene read-model projection (legitimate
API-edge read). The merge SHALL block/no-op until the target block has applied
scenes (domain invariant: scripts for a block are always finished before a
schedule is created).

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

### Requirement: Idempotent upsert apply via user-driven mapping
Applying a preview SHALL dispatch existing commands
(`CreateScene`/`UpdateSceneDetails`, `CreateCharacter`/`Assign…`,
`CreateShootingDay`, `ScheduleSceneOnShootingDay`, `PlanSceneShoot` with
`source: AiExtracted`). Each draft row SHALL require an explicit user decision
(new vs update-existing-`#id`) — there SHALL be no automatic fuzzy matching in
v1. A persisted `projection_ai_import_mapping(preview_id, draft_ref,
aggregate_kind, aggregate_id)` SHALL make re-applying the same preview
idempotent: mapped rows dispatch `Update…` (no-op if unchanged); unmapped rows
dispatch `Create…` + a mapping write. Re-import of an updated document SHALL
re-suggest mappings from the prior projection for the user to confirm. No
matching state SHALL live on Scene/Character/ShootingDay/SceneShoot aggregates.

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
reach apply SHALL be recorded as `NotApplied` (`edit_distance` NULL); jobs that
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
