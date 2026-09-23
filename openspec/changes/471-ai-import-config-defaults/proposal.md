<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4-flash (neuralwatt) -->

# Proposal: AI import config dialog — prompt-default prefill + provider/model suggestion (issue #471)

## Problem

The AI-config screen (`lib/features/ai_import/ai_config/`) has the full create
flow — provider picker, assistant/image model pickers, masked key entry,
script + schedule prompt fields — but **everything starts empty and there is no
backend contract to prefill the prompts or suggest a provider/model**. First-run
users must type the production prompt text by hand.

The single source of truth for prompt defaults lives in
`backend/config/default_ai_prompts.toml` (`[script]` / `[schedule]`,
`AI_IMPORT_DEFAULT_PROMPTS_PATH` overridable) and is exposed by ZERO contract
routes (verified against `backend/openapi.yaml`). The prompt fields therefore
start empty; users cannot start from the same defaults the backend itself uses.
The catalog routes (`GET /v1/ai-import/providers`,
`GET /v1/ai-import/providers/{key}/models`) carry no "recommended/default"
flag, so the dialog has nothing to preselect.

## Design

### Backend — contract

1. **`GET /v1/ai-import/defaults`** — serves the prompt defaults from
   `infra::ai::default_prompts()` (which reads `AI_IMPORT_DEFAULT_PROMPTS_PATH`
   or the built-in `config/default_ai_prompts.toml`), so deployments keep their
   single-source override. Response (`AiImportDefaults`):
   `{ "script": String, "schedule": String }`.
   - Gating: **same decision as the existing catalog reads**
     (`list_ai_providers` / `list_ai_models`) — the credential-role policy
     (`authorize_credential_role`) + `AI_IMPORT_ENABLED`. The prefill layer is
     independent of the credential-role gating (issue #470 resolves the 403
     narrative), but the defaults are part of the same config-discovery
     surface, and a consistent gate avoids a second narrative path: when the
     role is denied the whole screen degrades honestly anyway.
   - Error surface: `ai-import.forbidden` (403), `ai-import.disabled` (404) —
     existing registered codes, no new registry entries.

2. **Recommended model per provider** — `ModelInfo` gains a boolean
   `recommended` field (additive, `utoipa ToSchema`; live-provider catalogs
   set `false`). A new `infra::ai::recommended_model(provider)` designates the
   curated recommendation; `curated_models(provider)` marks exactly that model
   `recommended: true`. The endpoint contract stays
   `GET /v1/ai-import/providers/{key}/models` — the flag rides on `ModelInfo`,
   so the frontend picks the recommendation without a new route.

### Frontend — prefill/preselect (first-run only)

3. `AiConfigRepository::fetchDefaults()` → `GET /v1/ai-import/defaults`
   (generated client DTO `AiImportDefaults`), exposed via a
   `aiImportDefaultsProvider`.
4. **Prompt prefill:** while the screen is in the **pristine first-run state**
   (no active config, user has not touched the prompts), the controller seeds
   `scriptPrompt`/`schedulePrompt` drafts from the defaults when they arrive.
   Editable — the user can overwrite before create; the config aggregate
   contract is unchanged.
5. **Provider + model preselect:** while pristine, the controller selects the
   **first displayed provider** from the curated catalog and, once its model
   set loads, the provider's **`recommended` model** (falling back to the first
   model if the endpoint predates the flag). Both remain user-overridable.
   Since every field is guarded by "the draft is still pristine", the user's own
   interaction always wins.
6. Degradation: if the defaults fetch fails, the prompt fields simply stay
   empty (the user types by hand) — no blocking error state, consistent with the
   existing honest-degradation culture.

## Non-goals

- No change to the config aggregate (`CreateAiConfigRequest` /
  `UpdateAiConfigRequest` still carry user-supplied prompts).
- No new problem codes (reuses `ai-import.forbidden` / `ai-import.disabled`).
- The configured/edit form keeps its current behavior — prefill is strictly
  first-run, never silently replacing an existing config's prompts.

## Testing

- **Backend (unit):** `default_prompts()` returns non-empty script/schedule;
  `recommended_model` is curated per provider and exactly one curated model is
  flagged; `catalog.rs` live list flags `recommended: false`.
- **Backend (handler authz):** `get_ai_import_defaults` allow/deny/repo-failure
  alongside the existing `list_ai_*` tests; wire-level defaults JSON shape.
- **OpenAPI drift:** `UPDATE_OPENAPI=1 cargo test -p api --test openapi_drift`
  regenerates `backend/openapi.yaml`.
- **Frontend (Dart client):** `scripts/regen-client.sh` regenerates
  `vendor/breakdown_api/` (byte-identical CI contract).
- **Frontend (widget):** first-run prefill — prompt fields seeded from the
  defaults DTO; provider + recommended model preselected; user override wins;
  configured state is untouched; goldens regenerated.
