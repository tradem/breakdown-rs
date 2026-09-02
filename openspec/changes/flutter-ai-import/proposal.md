<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# Proposal: AI Import — Phase 3

## Why
Phase 3 is the roadmap's highest-value feature: AI schedule/script import
over `/v1/ai-import/*`. Today the client has nothing in this area, while
the backend contract is fully present in the checked-in
`backend/openapi.yaml`: provider/model discovery
(`/ai-import/providers[/{provider}/models]`), credential-submission
handoff (`/v1/settings/credentials` → vault key id), LLM configuration
(create/get/update/revoke `/ai-import/config*`), raw-document job
submission (`/ai-import/schedules`, `/ai-import/scripts` — pdf/csv/plain
bodies), job status (`JobStatus: pending|running|succeeded|failed|
dead_letter|payload_unavailable`), preview, and apply (mapping
decisions per draft row). This change lands the user-facing workflow:
configure the AI provider → submit a raw schedule/script → watch the
job → review the preview → apply mapped drafts into an episode.

## What changes
- **`lib/features/ai_import/`** with two sub-features:
  - **Configuration** (`ai_config/`): provider list + model picker
    (`ModelInfo`), assistant/image model selection, per-document-kind
    prompts (script/schedule), and the credential handoff (the LLM API
    key is submitted via `POST /v1/settings/credentials` and only its
    opaque `vault_key_id` is then referenced by the config — the secret
    never persists on the device).
  - **Workflow** (`import_jobs/`): document submission (file pick for
    PDF, paste/board for CSV/plain text; raw-body upload with the
    declared `Content-Type`), job list/watch with bounded
    foreground-only polling, preview review with per-draft-row user
    decisions (Create / Update-existing / skip), and apply
    (`ApplyAiImportRequest` with the episode context, mappings from
    the acted-on preview rows, `accept_as_is`, `edit_distance`) plus
    the applied-outcome summary (`applied_count`, `created_days`,
    `planned_scene_shoots`).
- Job status terminal errors (`dead_letter`, `payload_unavailable`,
  retryable `failed` with `retries/max_retries`) rendered as honest
  narratives; `last_error` displayed as secondary detail only.
- Result-typed repositories (`data/ai_import_repository.dart`,
  `data/ai_config_repository.dart`) on the generated client; Drift
  caching for the *job list* only (config is secure-storage id
  handoff; preview is never cached — regenerable).
- Tests: unit (repos, mapping-request builders, status state machine),
  widget + goldens (light/dark × android/macos), Gherkin none (AI
  import is not a designated critical scope), integration smoke with a
  faked LLM path.

## Capabilities
- `flutter-ai-config` (new)
- `flutter-ai-import-workflow` (new)

## Dependencies
- **Depends on:** `flutter-login-and-app-shell` (gate/tokens/theme),
  `flutter-hierarchy-navigation` (episode context, season context,
  shared reconciliation), `flutter-costume-domains` (assistant
  experience continuity: applied shooting days and scene shoots
  surface there).
- **New packages:** `file_picker` (document selection, FOSS). No other
  new dependencies; the upload is a raw_body dio call.

## Non-goals
- No background import queue or OS-level background work (store
  compliance + online-first `flutter-offline-scope`).
- No client-side LLM calls — the client never contacts an AI provider
  (mirrors the AI notice already shipped in the info dialog).
- No config list refresh beyond the realized contract — there is no
  list route (D2).
- No cancellation of a running job — no such route exists (D3); the
  user/client can only stop observing.
- No editing of the preview server-side (no such command); apply is
  the only write path.

## Design Decisions
- **D1 — Preview is consumed as an untyped-but-validated object.** The
  checked-in spec types the preview 200 response as a plain object.
  The client renders it through a runtime-validated row adapter
  (tolerant of absent fields, rejecting unknown row shapes with an
  explicit error state) instead of retyping DTOs client-side
  (never-retype hard rule). The apply request's `draft_ref`s are taken
  verbatim from the rows the user acted on. Backend asked to type
  the preview schema (GitHub issue #337); switching later is a mapper-only change.
- **D2 — Config discovery is via a locally remembered id.** The API
  offers no config-list route (GitHub issue #337); `GET
  `/ai-import/config/{id}` requires the id. The client persists the id from the create response in
  `flutter_secure_storage` and treats "no remembered id or 404" as the
  first-run state ("not configured yet"). Documented as an API gap —
  no workaround projections are invented.
- **D3 — No cancellation route exists.** "Cancel" in the UI is local
  stop-observing (dispose the watch); job processing continues
  server-side. The UI copy is honest ("processing continues; you can
  close this screen") — no dark pattern implying a cancellation that
  does not exist.
- **D4 — The config screens' pre-gate is session-only (documented
  exception).** The backend gates AI config/credential endpoints on a
  credential-role policy that is NOT exposed as a season capability;
  therefore no client-side `currentMembershipProvider` pre-gate can
  mirror it (the authz D6 mechanism is not applicable). The 403
  problem response renders a localized narrative; the hard rule's
  review verification still requires `// AUTHZ-GATE:` annotation of
  the *upload* calls, which ARE season-membership-gated and ARE
  pre-gated via the capability gate.
- **D5 — Polling is bounded and foreground-only.** Job watching uses
  the shared bounded-backoff scheduler while subscribers exist;
  no wake-ups, no background polling (battery/store compliance).
  Terminal statuses (`succeeded`, `dead_letter`,
  `payload_unavailable`) end the watch.
- **D6 — Secrets transit, never persist.** The LLM API key is typed by
  the user, POSTed to the server vault over the pinned-CA transport,
  and only the opaque `vault_key_id` flows into the config. It is
  never stored on the device (no secure-storage row, no logging,
  masked input field).
