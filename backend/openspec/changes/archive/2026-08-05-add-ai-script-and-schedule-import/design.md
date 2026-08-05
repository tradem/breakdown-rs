## Context

Costume disposition is bootstrapped today by hand-keying Scenes, Characters,
ShootingDays and the Dispo list through the API. Productions deliver two
documents — a **script (Drehbuch)** and a **shooting schedule (Drehplan)** — and
both must be transcribed before any wardrobe work begins. ADR-013 ("Hybrid LLM
Script-Parsing") mandates a provider-pluggable, cost-bounded, data-sovereign
LLM import. This design realises ADR-013 against the existing hexagonal /
CQRS / event-sourced architecture.

### Current state (reuse, not rebuild)

```
SettingsAggregate (core/settings)         CredentialVault port (reused)
  - per-user credential binding             - store/fetch/rotate SecretValue
  - provider: String,                       - VaultClient impl in infra
    vault_key_id (opaque)                   - shared across contexts
  - gate: has_active_credential_role        (GDrive archival already uses it)

ShootingDaySource { Manual, AiExtracted }  ← provenance seam persisted day one
SceneDetails { scene_number, location, mood, summary, script_day }
DispoRow / SceneShootReportRepository::dispo_report  ← read-side dispo exists
ReportArchivalQueue (reporting/archival.rs) ← operational-job BLUEPRINT:
  dedup_key, Pending|Claimed|Staged|Succeeded|Failed|DeadLetter,
  separate PG schema, idempotent. NOT a saga.
retry_transient() + compute_backoff() (photo/sagas) ← resilient HTTP primitive
RenderBounds (reporting/mod.rs) ← bounded-knobs pattern (compile+env guarded)
config/default_costume_categories.toml ← seed-config pattern (parsed in infra)
utoipa present; schemars NOT a dep yet; reqwest + tower present.
```

### Stakeholders & constraints
- Costume designers / disponents: receive documents; review and apply imports.
- Operators: curate the provider enum and model allowlist; set bounds.
- NDAs / EU AI Act: script data sensitive; providers must be EU-hosted or
  self-hosted with zero-retention; ADR-013 prefers EURouter → Ollama.
- Cost neutrality: dev involves hundreds of prompt-tuning runs; per-job request
  caps + provider-side dollar budgets (defense in depth).
- CQRS hard rule (AGENTS.md §1): write-side code must never query read
  projections for audit/derived context; only the API edge may.

## Goals / Non-Goals

**Goals:**
- Import a script PDF into a reviewable `ScriptContext` preview via a
  provider-pluggable, schema-constrained LLM call.
- Import a shooting schedule (CSV native, or LLM for unstructured) into a
  reviewable `ShootingSchedule` preview.
- Deterministically merge schedule rows onto applied scenes, surfacing
  unmatched rows for human adjudication.
- Apply reviewed previews through the existing command surface, idempotently,
  with provenance `AiExtracted`.
- Per-user curated provider/key/model/prompt configuration, stored securely.
- Resilient, cost-bounded, observable LLM HTTP transport.
- Telemetry capturing `accept_as_is` + `edit_distance`, enabling a future
  telemetry-gated auto-apply (v2, out of scope here).

**Non-Goals:**
- Auto-apply without human review (v2; telemetry-gated).
- Self-hosted Ollama production deployment (ADR-013 Phase 2) — the Ollama
  adapter exists as a dev/test fallback only; no prod-Ollama hardening.
- Dynamic/runtime-defined output schemas — target structs are static Rust
  types; users edit prompt text only.
- A `Series` aggregate (still additive-only; `SeriesId` remains opaque).
- Real-time / collaborative review of previews.
- Re-importing documents in any order (domain invariant: scripts are finished
  — applied — before schedules are created; see Decisions §G).
- Persisting `MergedDispo` as event-sourced business truth (it is derived).

## Decisions

### A — Import is an operational job queue, not an event-sourced aggregate / saga
ADR-013's prose sketches `UploadScript` command → `ScriptUploaded` event →
async actor → `SceneExtracted` events. We reject event-sourcing the import
itself. Import is operational work, not business state. The existing
`ReportArchivalQueue` is the precedent: a separate PG schema, `dedup_key`,
`Pending|Running|Succeeded|Failed|DeadLetter`, idempotent enqueue.

**Why over event-sourced saga:** replaying an event-sourced import would
re-run the LLM (costly, non-deterministic, NDA re-exposure); a job row is
cheaply visible/killable/cappable per user; a saga that auto-applies would
violate the CQRS boundary (resolving `series_id` from projections on the
write side is the mechanically-forbidden path).

**Why over direct synchronous parsing:** LLM latency (seconds to minutes)
is unacceptable on the request path; async + bounded retry is required.

**Alternative considered:** a `ScriptAggregate` event-sourced aggregate with
LLM calls in command handlers. Rejected: LLM calls in a command handler block
the event-store append path, are non-deterministic, and re-run on replay.

### B — Human-in-the-loop preview; auto-apply deferred + telemetry-gated
Apply is always preceded by a reviewable preview. Auto-apply is a v2 concern
gated on telemetry thresholds. The preview is a staged JSON blob + a preview
projection row; it is transient operational state, not a write-side aggregate.

**Why:** a runaway import mutates production state under the old design; under
preview-first it only burns tokens. The apply path is the existing handlers,
so all validation and audit are reused unchanged.

### C — Curated provider enum + per-user key
`LlmProvider` is a `#[non_exhaustive]` core enum (OpenAI, OpenRouter,
EURouter, Ollama) with hardcoded `base_url`s in infra. OpenRouter and EURouter
are separate providers and credential bindings. Users select a provider, supply
an API key (vaulted), pick a model (from a curated catalog subset) and edit
prompt text. Users never type a URL → no SSRF surface on chat/model-list calls.

**Why over per-user arbitrary base_url CRUD:** "reduction of choice, curated
LLM selection" (stakeholder); removes the credential-exfil / SSRF surface of
calling user-supplied URLs with user-supplied keys.

**Alternative considered:** full pi-coding-style arbitrary-provider CRUD.
Rejected: maximal flexibility at the cost of an SSRF/credential-exfil surface
and a UX burden on non-expert users.

### D — Static Rust target types + schema-constrained decoding
The LLM target (`ScriptContext` and friends) is a **static** Rust type derived
via `#[derive(Serialize, Deserialize)]`. `schemars::schema_for!(::ScriptContext)`
generates a JSON Schema fed to the provider's `response_format` constrained-
decoding parameter. Users edit prompt **text** (XML-tagged framing:
`<role>`, `<context>`, `<edge-case>`); output stays constrained JSON. The
schema is compile-time-generated, not runtime-defined.

**Why over dynamic/runtime schemas:** Rust has no reflection; dynamic schemas
land in `serde_json::Value` (no type safety) and need a schemars runtime
registry for validation — heavy machinery for zero benefit, since the import
feeds a fixed domain model. Static types give typed `ScriptContext`,
schema-constrained decoding gives reliable output, user prompt ownership gives
flexibility. Three concerns, three separate mechanisms.

**Ollama caveat:** its structured-output support is weaker than OpenAI/OpenRouter.
The Ollama adapter falls back to `{format:"json"}` + bounded parse-or-retry.
This is contained in infra behind the same `LlmClient` trait.

### E — Resilience, bounds, cost guardrails
```
per-import-job request cap   (N max chunks; exceeded → Failed, no retry)
per-user in-flight concurrency cap (advisory lock / PG counter)
retry_transient (existing)   429/5xx/timeout → ServiceUnavailable → in-loop retry
                             4xx (bad key/model) → permanent Failed
request timeout               reqwest/tower timeout
hard ceilings                AiImportBounds (mirrors RenderBounds):
                             max_chunks_per_script, max_tokens_per_req,
                             max_concurrent_jobs_global, …
```
Dollar/token spend is the provider's concern (enforced by provider-side
budgets); local request cap + per-user concurrency bounds the local "amok"
exposure to `max_chunks × tokens_per_chunk × per_user_concurrency`. Defense in
depth, exactly matching the stakeholder's "limits belong at the provider".

### F — MergedDispo is a derived projection + a transient preview blob; NOT event-sourced
The applied dispo IS event-sourced — in the Scene/Character/ShootingDay/
SceneShoot streams. `MergedDispo` is a **read projection**, rebuilt on demand
from those streams at zero LLM cost. The pre-apply merge preview is a transient
staged blob served by the job store. Event-sourcing a derived view would (a)
let the merge drift from the real aggregates, (b) require re-running the LLM on
rebuild. Neither is acceptable.

**Stakeholder confirmation:** the only data a user can lose from a crashed/
abandoned import is the *unreviewed preview draft*; everything approved is safe
in the real aggregate streams.

### G — Split workflow; hard ordering ScriptApply → Merge
The script import and its apply are independent and usable alone. The merge
step exists only as part of the schedule import. **Domain invariant: scripts
for a block are always finished (applied) before a schedule is created** (the
production runs a "Fuzzelcheck"). Therefore:

```
ScriptImport (LLM) ─▶ ScriptContext preview ─▶ APPLY (no merge) ─▶ scenes exist
                                                                    (real aggregates)

ScheduleImport (LLM/CSV) ─▶ ShootingSchedule preview ─┐
applied scenes (above) ────────────────────────────────┤
                                                       ▼
                                              MERGE (deterministic join
                                              of schedule rows → applied
                                              scenes by scene_number;
                                              NO LLM; cost-free; replayable)
                                                       │
                                                       ▼
                                       merged preview + unmatched_*_rows
                                                       │
                                                       ▼
                                              APPLY (schedule side)
                                       → CreateShootingDay / ScheduleSceneOn
                                       ShootingDay / PlanSceneShoot (AiExtracted)
```

The merge job reads the Scene read-model projection (legitimate: it is the
operational/job API edge, not write-side code) and **blocks/no-ops until the
block has applied scenes**. If the merge against fully-applied scenes still
produces unmatched rows, that is a genuine data error (schedule references a
non-existent scene) for human adjudication, not a "wait for script" state.

**Why hard over soft ordering:** soft ordering (merge against script preview)
would create a "half-truth" preview linked to non-existent scenes, multiplying
Apply-Gate complexity. The domain already guarantees the hard order in practice.

### H — Idempotent upsert via user-driven mapping + AiImportMapping projection
Every draft row receives an explicit user decision in the review UI: **new** or
**update existing #id** (H1, user-driven; no fuzzy auto-matching in v1). A
persisted projection `projection_ai_import_mapping(preview_id, draft_ref,
aggregate_kind, aggregate_id)` makes re-applying the same preview idempotent:
mapped rows dispatch `Update…` (no-op if unchanged), unmapped rows dispatch
`Create…` + mapping write. A crash mid-apply is safe to retry because each row
either has a mapping (skip/create) or doesn't (create + record) — mirroring the
existing `WHERE version < $N` projector idempotency pattern. Re-import of an
updated document re-suggests mappings from the prior projection; the user
confirms. No matching state lives on Scene/Character/etc.

**Why not fuzzy/automatic matching in v1:** LLM summaries and scene numbers are
not stable across re-imports; auto-matching would require thresholding heuristics
that are brittle and add UX surface. User confirmation is cheap and reliable.
The mapping projection preserves suggestions across runs.

### I — Uncertainty model (null-on-doubt + allow-marked-suggestion + apply gate)
The `ScriptContext` preview carries an `uncertainties: Vec<Uncertainty>` list.
Each `Uncertainty { scene_index, field, note, suggested_value: Option<String> }`.
The seeded prompt rule (`<rule>` block) instructs the model: do NOT assert
values you cannot read; leave the field null and append an `uncertainty` with a
note; you MAY supply a clearly-marked `suggested_value` for the user to confirm
or replace.

**Apply gate:** a preview with open uncertainties cannot be applied. Resolving
an uncertainty (confirm suggestion / type replacement / drop) is itself an edit
→ feeds the `edit_distance` telemetry signal; `accept_as_is` == applied with
zero uncertainties originally raised.

**Why allow marked suggestions:** the apply gate forces human confirmation
either way; suppressing useful model hypotheses wastes model capability. Marked
suggestions are rendered distinctly from asserted values in the UI. The
stakeholder reading ("im Zweifel dem Nutzer hinterlassen") is satisfied because
the user always has the final word; the generous reading avoids throwing away
useful signal. Confirmed by stakeholder.

**Separate from Merge-Unmatched:** merge unmatched rows
(`unmatched_schedule_rows`, `unmatched_script_scenes`) are a deterministic join
miss, not an LLM uncertainty. They live on the merged preview, gated by the
Schedule-Apply-Gate. Two distinct channels, two distinct preview types.

### 6 — New `ai` bounded context; Vault port reused
`CredentialVault` / `VaultClient` is already in use for GDrive report archival
and generic provider secrets. The AI context stores its own `vault_key_id`
(opaque string) in its own `AiConfig` aggregate and calls into the same
`VaultClient` — port reuse, aggregate separation. The `Settings` aggregate is
**not** extended (its single-binding shape is too narrow for model +
image-model + prompt-template selection).

### Telemetry — captured now, decide later
Per-job columns: `provider, model, doc_kind, chunk_count, tokens_in, tokens_out,
latency_total, accept_as_is: bool, edit_distance: u32`. `accept_as_is` and
`edit_distance` are only cheaply capturable at apply time and cannot be
backfilled, so they are recorded from day one even though auto-apply is off.

**Future (v2, out of scope):** auto-apply eligibility = provider+model with ≥ N
jobs (min sample, say 50) and ≥ 95% `accept_as_is` on `doc_kind=Script`, with a
per-(provider,model) rollback toggle, and applied jobs retaining a preview for
audit. An additional `originating_job_id` in `EventMetadata` would reconstruct
"this scene came from script X run by model Y".

## Risks / Trade-offs

- **[Risk] Ollama structured-output unreliability** → Mitigation: Ollama is
  dev/test-only; the adapter falls back to JSON-mode + bounded parse-or-retry;
  prod path uses schema-constrained providers (OpenAI/OpenRouter). No
  prod-Ollama hardening effort is spent on a deployment that may never ship.
- **[Risk] LLM non-determinism across re-imports (mapping drift)** →
  Mitigation: H1 user-driven confirmation + persisted mapping projection
  re-suggests prior mappings; user is the source of truth, not the model.
- **[Risk] Cost runaway ("amok")** → Mitigation: per-job request cap, per-user
  concurrency cap, `AiImportBounds` ceilings; provider-side dollar budgets
  (defense in depth).
- **[Risk] NDA / data-sovereignty breach via provider** → Mitigation: curated
  enum (no arbitrary URLs); EURouter provides a dedicated EU-routed option; the
  Ollama self-host path remains available via the same trait if a deployment demands it.
- **[Risk] Apply crash mid-way → duplicate aggregates** → Mitigation:
  `AiImportMapping` checked before each dispatch; re-apply is idempotent by
  construction (mapped → Update, unmapped → Create+map).
- **[Risk] UI merges LLM-uncertainty channel and merge-unmatched channel into
  one confusing worklist** → Mitigation: two distinct preview types, two
  distinct apply gates (decided in design, must be reflected in the UI spec).
- **[Risk] MergedDispo drifts from real aggregates if mis-modelled as
  persisted** → Mitigation: F decided — derived projection only, rebuilt from
  Scene/ShootingDay/SceneShoot streams.
- **[Trade-off] Static schema means users cannot redefine the target struct** →
  Accepted: the target feeds a fixed domain model; user flexibility lives in
  prompt text, not schema shape.
- **[Trade-off] Hard ordering rejects "schedule before script" imports** →
  Accepted: domain invariant guarantees scripts-first; soft ordering would
  create half-truth previews. If a deployment violates the invariant, the user
  must apply the script first (the legitimate path).

## Migration Plan

This is additive — no existing aggregate, command or projection changes. Rollout:

1. Add `schemars` workspace dependency; add `pdftotext` CLI dependency to the
   Docker image (ADR-013 prefers CLI wrapper over the `pdf-extract` crate).
2. Land `crates/core/src/ai` first (traits + DTOs, no infra). Architecture tests
   extend to forbid `core` depending on `schemars`-runtime or `reqwest`.
3. Land `crates/infra/src/ai` (catalog/chat/queue/merge/apply/mapping) behind
   the existing `ProductionPorts` injection.
4. Land `crates/api` handlers under `/v1/ai-import/...` gated by active
   costume-dept membership; add `// AUTHZ-GATE:` comments to every new
   privileged handler (mirrors the photo-handler rule).
5. New PG migration for the AI job queue + mapping projection schemas (separate
   schema, like report-archival; runs via the migrator pool at boot).
6. Seed default prompt templates as config files (mirrors
   `default_costume_categories.toml`), parsed in infra.

**Rollback:** the feature is feature-flagged via `AI_IMPORT_ENABLED` (env).
Disabling the flag stops new enqueues; in-flight jobs drain to a terminal
state. Previews and applied state live in their own schemas; dropping them
does not affect any business aggregate. The `CredentialVault` bindings created
for AI keys are independent `vault_key_id`s and can be revoked without
touching GDrive bindings.

## Open Questions

- **Exact default bounds** for `AiImportBounds` (max_chunks, tokens_per_req,
  concurrency). To be set in infra config during implementation, validated by
  the Θ(cost) worst-case analysis required by the AGENTS.md timing-safe test
  convention.
- **Telemetry schema location**: dedicated PG schema vs. columns on the job
  row. Lean: columns on the job row (single source for job lifecycle); revisit
  if query patterns demand separation.
- **Prompt-template seeding granularity**: one default per `DocumentKind`, or
  per `DocumentKind × provider` (provider-specific instruction tweaks). Lean:
  one per `DocumentKind`, with provider-specific framing added by the chat
  adapter if required.
