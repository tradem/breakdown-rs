## Why

Costume disposition today is hand-keyed: scenes, characters, shooting days and
the dispo list are created one-by-one through the API. Productions arrive as two
semi-structured documents — a **script (Drehbuch)** and a **shooting schedule
(Drehplan)** — and both must be transcribed into the domain model before any
disposition work can start. ADR-013 mandates an LLM-based import that is
provider-pluggable, cost-bounded and data-sovereign. This change introduces the
import pipeline, the per-user provider/model/prompt configuration, and the
human-in-the-loop apply path that turns the two documents into real aggregates
without ever bypassing existing command validation or the CQRS boundary.

## What Changes

- **New `ai` bounded context** (`crates/core/src/ai`): an AI configuration
  aggregate carrying the user's selected curated provider, assistant model,
  image model and per-document-kind prompt templates, plus an opaque
  `vault_key_id` referencing an API key stored via the existing
  `CredentialVault` port (no `Settings` aggregate extension; the vault is shared,
  the aggregate is separate).
- **Curated `LlmProvider` enum**: OpenAI / OpenRouter / EURouter (EU-routed) /
  Ollama (dev/test fallback only). OpenRouter and EURouter are separate providers. Hardcoded base URLs in infra so users never
  type a URL (no SSRF surface). Adding a provider is additive
  (`#[non_exhaustive]`).
- **Provider model catalog port** `LlmModelCatalog::list` hitting the
  OpenAI-compatible `GET /v1/models`; infra applies a curated allowlist
  (reduction of choice).
- **AI import job family** (`AiImportJob`) shaped on the existing
  `ReportArchivalQueue` operational pattern (separate PG schema, dedup key,
  `Pending|Running|Succeeded|Failed|DeadLetter` status). Three job kinds:
  `ScriptImport` (PDF→LLM), `ScheduleImport` (CSV native OR LLM) and `Merge`
  (deterministic join, no LLM, no cost). The import is operational state, never
  event-sourced business truth.
- **Script preview** as the LLM target type `ScriptContext`, parsed via
  JSON-schema-constrained decoding (`schemars` + `response_format`). Fields are
  static Rust types (`Option<T>` tolerance); users may only edit the
  prompt text, not the output schema. Prompt text uses XML-tagged framing
  (`<role>`, `<context>`, `<edge-case>`); output is constrained JSON.
- **Uncertainty model (Fork I)**: every ScriptContext preview carries an
  `uncertainties: Vec<Uncertainty>` list. The seeded prompt rule is
  null-on-doubt — the model MUST NOT assert values it cannot read, and MAY
  supply a clearly-marked `suggested_value: Option<String>` for the user to
  confirm or replace. **Apply gate**: a ScriptContext preview with open
  uncertainties cannot be applied.
- **Merge semantics**: the merge job is only relevant to the schedule import.
  It deterministically joins `ShootingSchedule` rows to already-**applied**
  scenes by scene number, surfacing `unmatched_schedule_rows` and
  `unmatched_script_scenes` for human adjudication. Domain invariant: scripts
  for a block are always finished (applied) before a schedule is created, so
  the merge job is a no-op/blocked until the block has applied scenes.
- **Idempotent upsert via user-driven mapping (H1) + `AiImportMapping`
  projection**: each draft row receives an explicit user decision (new vs
  update-existing-`#id`) in the review UI. A persisted
  `projection_ai_import_mapping(preview_id, draft_ref, aggregate_kind,
  aggregate_id)` makes re-applying the same preview idempotent (mapped rows
  dispatch `Update…`, unmapped rows dispatch `Create…` + mapping write), so a
  crash mid-apply is safe to retry. Re-import of an updated document re-suggests
  mappings from the prior projection; the user confirms. No matching state
  lives on Scene/Character/etc. (no core domain pollution).
- **Apply targets the merged preview** when a schedule is in play, or the
  script preview alone when only a script was imported. Apply is a sequence of
  existing commands (`CreateScene`/`UpdateSceneDetails`, `CreateCharacter`/
  `Assign…`, `CreateShootingDay`, `ScheduleSceneOnShootingDay`, `PlanSceneShoot`
  with `source: AiExtracted`). All existing validation, optimistic-concurrency
  and `series_id`-at-the-edge resolution apply unchanged.
- **Telemetry now, auto-apply later**: every job records `provider`, `model`,
  `doc_kind`, `chunk_count`, `tokens_in/out`, latency, `accept_as_is: bool`
  (applied with zero edits) and `edit_distance: u32` (content-free count of
  user resolutions/edits). Auto-apply is explicitly out of scope for v1 and
  gated on future minimum-sample + accept-rate thresholds recorded in this
  table.
- **Resilience & bounds**: per-job request cap, per-user in-flight concurrency
  cap, `retry_transient` (existing primitive) for 429/5xx/timeout mapped to
  `ServiceUnavailable` (in-loop retry), 4xx (bad key/model) mapped to permanent
  `Failed`. An `AiImportBounds` config (mirrors `RenderBounds`) carries
  compile-time + env-guarded ceilings.
- **Authorization**: all import endpoints gated by active costume-dept
  membership (`AuthorizationPolicy`). The AI config aggregate gates on the
  existing `has_active_credential_role` membership check. Handlers under
  import routes follow the `// AUTHZ-GATE:` pattern.

## Capabilities

### New Capabilities
- `ai-import`: the AI bounded context — provider/model catalog, per-user AI
  configuration, the import job family (Script/Schedule/Merge), preview store,
  uncertainty model, merge join, user-driven mapping projection, idempotent
  upsert apply, resilience bounds and per-job telemetry.

### Modified Capabilities
<!-- None. Apply reuses existing Scene/Character/ShootingDay/SceneShoot commands
     unchanged; no spec-level behavior change to those capabilities. -->

## Impact

- **New `crates/core/src/ai` module**: `LlmProvider` enum, `AiConfig` aggregate
  + commands/events/ports/views, `AiImportJob` operational types, preview DTOs
  (`ScriptContext`, `ShootingSchedule`, merged preview, `Uncertainty`), the
  `LlmModelCatalog` + `LlmClient` ports, `AiImportBounds`, telemetry types.
- **New `crates/infra/src/ai` module**: `VaultClient`-backed key resolution
  (reuses `CredentialVault`, new binding keys), the OpenAI-compatible chat
  client + model-catalog adapter, `AiImportJob` queue adapter (PG schema,
  mirroring the report-archival queue schema), the merge join worker, the
  apply worker, `AiImportMapping` projection, pdftotext/CSV ingestion adapters.
- **New `crates/api` handlers**: provider/model listing, AI config CRUD,
  script/schedule upload (enqueue), job status + preview read, apply (reviewed
  rows → existing commands). All under `/v1/ai-import/...`.
- **New dependency**: `schemars` (JSON Schema generation for constrained
  decoding; coexists with `utoipa`). `pdftotext` via CLI subprocess (per
  ADR-013 evaluation).
- **Reused, not modified**: `CredentialVault`/`VaultClient`, `retry_transient`,
  `ReportArchivalQueue` pattern, `RenderBounds` pattern, existing Scene/
  Character/ShootingDay/SceneShoot commands, `ShootingDaySource::AiExtracted`
  (provenance seam already persisted).
- **CQRS boundaries enforced**: write-side apply dispatches only existing
  commands (no read-projection lookup by write-side code); merge/preview
  reads hit the read model only at the operation/job API edge.
