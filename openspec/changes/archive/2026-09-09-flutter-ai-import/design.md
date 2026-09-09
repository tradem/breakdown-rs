<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# Design: AI Import

## 1. Contract facts (grounding)

From the checked-in `backend/openapi.yaml` and
`backend/crates/api/src/handlers/mod.rs`:

- **Discovery:** `GET /v1/ai-import/providers` → `AiProviderInfo
  {provider: LlmProvider, key}` (enum: openai, openrouter, eurouter,
  neuralwatt, opencode-go, opencode, ollama; curated model sets refreshed
  per backend PR #360 — pickers read the routes, never hardcoded ids);
  `GET /v1/ai-import/providers/{provider}/models` → `ModelInfo {id,
  provider, display_name?}` (422 on unknown provider).
- **Credentials:** `POST /v1/settings/credentials`
  (`CreateCredentialRequest {provider, secret}`) → `IdVersionResponse`
  — the id is the `vault_key_id` used by the config. Server-held
  Vault; write-only, no read-back route.
- **Config:** `POST /v1/ai-import/config`
  (`CreateAiConfigRequest {provider, assistant_model, prompts:
  {script|schedule → text}, vault_key_id, image_model?}`) → 201
  `IdVersionResponse`; `GET /v1/ai-import/config` → caller's configs
  (newest-first; backend issue #337, PR #357); `GET
  /v1/ai-import/config/{id}` → `AiConfigView`
  (public view: opaque `vault_key_id`, NO secret material; owner
  check server-side); `PATCH …` (`UpdateAiConfigRequest`, version
  echo) → `AggregateVersion`; `POST …/revoke`
  (`RevokeAiConfigRequest {version}`). All 403 on credential-role
  denial (handler-internal gate).
- **Submission:** `POST /v1/ai-import/schedules` and
  `POST /v1/ai-import/scripts` — RAW body with `Content-Type`
  `application/pdf | text/csv | text/plain` (schedules) /
  `application/pdf` (scripts); 202 job enqueued / 200 duplicate →
  `AiImportJobId`; 413 size, 415 media type, 403 (season costume-dept
  membership — `// AUTHZ-GATE:` in the handler), 404 AI import
  disabled.
- **Job status:** `GET /v1/ai-import/jobs/{id}` →
  `AiImportJobResponse {job: AiImportJob}` with `status`, `retries`,
  `max_retries`, `last_error?`, `preview_handle?`, `document_kind`,
  `source_format`, timings. `JobStatus`: `pending | running |
  succeeded | failed` (retryable) `| dead_letter | payload_unavailable`
  (both terminal).
- **Preview:** `GET /v1/ai-import/jobs/{id}/preview` → 200
  `AiImportPreviewResponse { job_id, document_kind, status, preview:
  AiPreviewPayload }` with the `kind`/`data` enum (`script` →
  `ScriptContext`, `schedule` → `ShootingSchedule` (pre-merge) or
  `merged` → `MergedPreview`; backend issue #337, PR #357 — the
  former plain-object shape is superseded); 404 when no preview exists.
  Every operation additionally declares its RFC 9457
  `application/problem+json` error responses (backend issue #343,
  PR #356) — error copy branches on the stable problem `code`.
- **Apply:** `POST /v1/ai-import/jobs/{id}/apply` with
  `ApplyAiImportRequest {episode_id (required), series_id?, mappings:
  [ApplyMapping {draft_ref, decision: Create | Update{aggregate_id,
  version}}], accept_as_is, edit_distance}` → 200
  `ApplyAiImportResponse {applied_count, created_days,
  planned_scene_shoots}`; 403. Server-side apply is idempotent
  (reserve-before-create, backend issue #338 / PR #351): an apply with
  an unknown outcome reconciles by re-reading before any bounded retry
  — never blind re-dispatch.
- **Job list:** `GET /v1/ai-import/jobs` → caller's jobs,
  newest-first with `limit`/`offset` pagination (backend issue #337,
  PR #357); per-job season-membership filtering mirrors
  `authorize_ai_job(Read)` server-side.

There is **no** cancel route (a deliberate design gap, not an issue);
D3 in the proposal documents this honestly. Config/job discovery via
the list routes (D2) and the typed preview (D1) supersede the former
issue-#337 gaps.

## 2. Feature structure

```
features/ai_import/
├── ai_config/            # provider/model/prompt configuration
│   ├── ai_config_screen.dart       # entry; manages one config
│   ├── ai_config_controller.dart
│   └── widgets/…
└── import_jobs/          # submission → status → preview → apply
    ├── import_submit_screen.dart  # doc kind + picker/paste + upload
    ├── job_status_screen.dart     # watch + terminal error states
    ├── preview_screen.dart       # rows + per-row decisions
    ├── apply_controller.dart    # builds + submits mappings
    └── widgets/…
```

Both follow the reference pattern (ConsumerWidget containers, pure
widgets, Result repositories, codegen). Entry point: a toolbar action
on the seasons screen ("AI import"); the job status/preview screens
are pushed after a 202/200 upload response carrying the returned
`AiImportJobId`.

### 2.1 Configuration flow

1. Read remembered config id (secure storage). None / 404 →
   "not configured yet" state with provider picker.
2. Provider picker → providers list → model pickers
   (`/providers/{key}/models`, 422 → "provider unavailable" copy).
3. Credential field: masked input for the LLM API key →
   `POST /v1/settings/credentials` (`provider` = the selected
   provider key, `secret` = key). The secret lives only in the
   request payload (D6) and is never persisted client-side.
4. **Credential hand-off (exact, contract-checked):**
   `POST /v1/settings/credentials` returns an `IdVersionResponse`
   (the **Settings aggregate id + version**) — *not* the
   `vault_key_id`. The opaque `vault_key_id` required by
   `CreateAiConfigRequest` is therefore obtained in a second step via
   `GET /v1/settings/{id}` → `SettingsView {vault_key_id,
   binding_state, vault_version, version}`.
5. `POST /v1/ai-import/config` (create, carrying that `vault_key_id`)
   or `PATCH` (edit, version echo); remember the id on create. 403 →
   localized "administrator role required" narrative (D4 —
   session-only pre-gate, no capability surface exists for credential
   roles).
6. **Rollback on config failure.** If step 5 fails, the Settings
   aggregate created in step 3 must be destroyed:
   `DELETE /v1/settings/{id}` with `VersionRequest {version}` (the
   version from step 3/4). Vault destruction in the handler is
   best-effort, so a failed DELETE is retried (bounded) and, if it
   remains failed, surfaced as a localized "orphaned credential"
   notice with a retry affordance — never silently dropped.
7. **Ambiguous timeout reconciliation.** When step 5 times out (no
   response, outcome unknown) the client MUST NOT blindly delete the
   credential: it first reconciles by reading
   `GET /v1/ai-import/config/{remembered id}` (or
   `GET /v1/settings/{id}`). A committed config → keep the credential
   and continue to the config screen; a definitive 404 → run the
   step-6 cleanup. Only an unresolved ambiguity after the bounded
   reconciliation attempts surfaces a "configuration state unknown —
   verify" state with both actions offered; the credential is never
   destroyed while it may be referenced by a committed config.

### 2.2 Submission flow

- Document kind schedule: CSV file (via `file_picker`), PDF file, or
  pasted plain text; script: PDF only (per the content-type contract).
- Raw-body upload with the picked `Content-Type` (NOT multipart;
  mirrors the backend route — raw bytes/text body). 413/415/403/404
  rendered keyed on `code`.
- **200 (duplicate)** is a first-class happy path: the UI navigates to
  the existing job with an explicit "already imported (duplicate)"
  callout; accidental double-apply is structurally impossible because
  apply is always an explicit user action.

### 2.3 Job watch + preview + apply

- `jobRepository.watch(jobId)` — bounded-backoff refetch while
  subscribed (D5). Statuses: pending (queued copy, indeterminate
  progress — the backend exposes no percentage and fabricating a
  determinate value is a dark pattern), running (same), failed
  (retryable — "retry scheduled" with `retries/max_retries`),
  dead_letter / payload_unavailable (terminal error cards, primary
  copy keyed on status, `last_error` as secondary detail text only).
- Preview: raw object → runtime-validated row adapter (D1). Known row
  shapes render as cards; unrecognized shapes render a degraded
  "unrecognized preview row" card and are excluded from one-tap
  accept-all; no silent coercion into fabricated typed rows.
- Apply screen — **episode context is data, not navigation state.**
  `ApplyAiImportRequest.episode_id` is required, and the documented
  entry point (seasons toolbar, §2.1) plus the remembered-job path
  both allow reaching a preview with no `EpisodeView` on the stack.
  Therefore the episode context (`episode_id` + `series_id`) is
  **persisted with the job record** when the job is enqueued and with
  every remembered job id, and the apply request is built from that
  persisted context. If a job is opened whose context is missing (e.g.
  a job id from an older build), the UI requires an explicit episode
  selection (picker over the season's episodes, ids from the read
  DTOs) before apply is enabled — apply is never dispatched with a
  guessed or empty `episode_id`.
  Per-row decision: Create / Update (picker over the episode's
  existing aggregates, ids + versions from the picked read DTOs) /
  skip. `accept_as_is` ("create all drafts as-is") and
  `edit_distance` (reported by the selection state; never invented).
- Apply 200 → summary card (`applied_count`, `created_days`,
  `planned_scene_shoots`) + deep navigation into the Phase 1/2
  hierarchy screens to review the imported days/scenes.

## 3. Caching (and explicit non-goals)

- Job rows cache in Drift (`ai_import_jobs` table) for last-seen state
  and offline reads; the "job list" surface is the remembered job ids
  (secure-storage id list, bounded to the N most recent) since no
  list route exists (same honest gap as D2).
- **AI-import state is scoped to the authenticated user.** All of it —
  `ai_import_jobs` rows, the remembered configuration id, and the
  remembered job-id list — is keyed by the authenticated subject
  (`sub`), and is cleared on sign-out and on account switch (the
  Phase 1a sign-out path already empties the Drift cache and
  invalidates session providers; this change adds the secure-storage
  id lists to that same reset). Offline reads after switching from
  user A to user B MUST expose no state belonging to A; a unit test
  covers exactly that A → B switch. (The pre-existing keying of the
  *other* Drift tables is out of scope here — they are cleared
  wholesale on sign-out by Phase 1a, so no cross-user read is
  reachable.)
- Preview is NEVER cached (regenerable, potentially large); config is
  fetched by remembered id; no secrets cached anywhere.

## 4. Testing

- Unit: repository Ok/Err per route; the mapping-request builder
  (Create / Update / skip; verbatim `draft_ref`s); the status watch
  state machine (bounded attempts, terminal stop, unsubscribe stop)
  with a fake scheduler; row adapter (known/unknown shapes, no silent
  coercion); credential handoff (secret present in the request only
  — assert no persistent store write).
- Widget + golden: config first-run/edit/denied; submission (paste +
  file, 413/415/403/404, duplicate-200); job status screens (all six
  statuses + terminal error cards); preview + degraded rows; apply
  summary; light/dark × android/macos goldens.
- Integration: emulator smoke with the upload → job → preview → apply
  chain stubbed at the repository seam (controllable fake pipeline;
  LLM paths faked — deterministic, no network LLM in CI).
