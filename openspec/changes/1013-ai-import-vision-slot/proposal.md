<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# 1013 — A real vision slot, and the zoning pass that finally has a producer

## Why

Two defects share one root cause: **the AI configuration has no vision slot.**

1. **Nobody can configure a VLM.** The page-streaming schedule extractor renders
   a page PNG and sends it to `provider` + `assistant_model` — the *text* model
   of the configuration (`crates/infra/src/ai/workers.rs:2359-2368`,
   `queries/ai_config.rs:155`). A text-only assistant model makes every
   Drehplan import fail on its first paid page call; a vision-capable assistant
   model forces the operator to also use it for the 100+ text chunks of a
   Drehbuch. `image_model` looks like the missing slot but is the *diffusion
   generation* seam (#673), read by no worker at all.
2. **The VLM structural-zoning pass was designed, named, and never built.**
   `DocumentZones::fell_back_to_script_body()` (`core/src/ai/document.rs:686`)
   is documented as "the signal the VLM structural pass is meant to answer" and
   has zero production callers; `core/src/ai/preview.rs:4315-4318` silently
   widens an unfamiliar template to "all prose" — the exact pre-#959
   contamination mode (`SYNOPSIS` / `SCRIPT REPORT` glued into scenes), with no
   log line and no preview diagnostic.

Both are additive, both have a proven precedent in the codebase (the #722
`decision` triple), and neither needs a `/v2` contract cut.

## What changes

The change is cut into four independently reviewable PR packages, stacked in
this order (each branch builds on the previous one):

| Package | Scope | Behaviour change |
|---|---|---|
| `[V1]` | Core aggregate + commands/events/views + validation + migration + projector/queries + API handlers + OpenAPI + Dart client regen | **none** — `vision_* = None` is byte-identical to today |
| `[V2]` | Infra: `AiWorkerVisionConfig`, vision client + egress gate in the page-streaming path, breaker/cost isolation, provider-health binding | schedule pages go to the vision pair when configured |
| `[V3]` | Vision catalogue: `curated_vision_model_ids`, pricing rows, `ModelInfo.supports_vision`, catalog route | the vision picker can no longer offer a blind model |
| `[V5]` | Zoning pass: `extract_scenes_with_zones`, VLM zone-labels-only call, fail-open + diagnostics, corpus tests | an unfamiliar template is re-zoned instead of silently widened |

`[V4]` (the Flutter configuration surface) is the companion issue **#1014** and
is not implemented here; this change owes it the wire shape, the catalog route
decision and the stable problem code for a non-compliant vision provider.

## W1 — the vision triple on the aggregate (mirrors the `decision` slot)

```rust
pub vision_provider: Option<LlmProvider>,
pub vision_model: Option<String>,
pub vision_vault_key_id: Option<String>,
pub vision_zdr_attested: bool,   // attestation for HIS provider (#968 semantics)
```

- **Same-key reuse rule** (copy of #722): `vision_vault_key_id` MAY equal
  `vault_key_id` when `vision_provider == provider`; otherwise it must reference
  a distinct active credential of the vision provider owned by the caller.
- **Fallback contract:** `vision_* = None` means "use the assistant pair", so no
  existing configuration changes meaning and a rollback needs no data fix.
- **Fail before money:** the aggregate refuses a vision provider that cannot
  carry page images (`vision_egress_compliant(vision_egress_policy_for_config(
  vision_provider, vision_zdr_attested)) == false`) at *config save* time, with
  a stable problem code — not on the first paid PDF.
- `zdr_attested` stays as-is for the primary pair; `vision_zdr_attested` is
  separate because the attestation is an account fact of a *different account*.

## W2 — the worker uses the vision pair for pages

`AiWorkerConfig` gains `vision: Option<AiWorkerVisionConfig { provider, model,
vault_key_id, zdr_attested }>`, resolved all-or-nothing in
`find_worker_config` (a partially-set row degrades to `None`, exactly like
`decision`). The page-streaming path holds `Arc<dyn LlmClient>` for the vision
transport and keeps the primary client for flat text; breaker, admission and
ledger attribution stay keyed `(provider, model)` per pair, which the existing
`compute_cost_snapshot` group fold already prices correctly.

## W3 — the zoning pass (bounded, fail-open)

- **Trigger:** only when `classify_document_zones` returns
  `fell_back_to_script_body()` — never "always on".
- **Input:** one rendered page PNG plus its spatial text hint, rendered, sent and
  dropped one page at a time (same byte ceilings as the schedule path).
- **Output:** zone labels and block anchors only, never prose (`D3` intact); an
  unknown zone, a missing/duplicate page number or an anchor outside the
  document's `BlockAnchor` space is a bounded validation failure, not a retry
  storm.
- **Fail-open:** denial, timeout, malformed JSON, render refusal
  (`legacy-pdftotext`) or exhausted budget → one stable `warn` event, one
  preview diagnostic (`zone_detection: fell_back`) and today's widening. A
  screenplay never fails to import because the structural helper was
  unavailable.

## Contract deltas (additive, no `/v2`)

| Layer | Change |
|---|---|
| `core::ai` aggregate | 4 vision fields + triple validation + `#[serde(default)]` event fields for replay |
| Migration | `ai_config_vision_slot.{up,down}.sql` — 4 nullable columns on `ai_import.projection_ai_config` |
| Projector / queries | upsert + `find_by_id`/`list_for_user`/`find_worker_config`, all-or-nothing triple resolution |
| `api` handlers | create/update requests gain the triple (update side `deserialize_optional_nullable`), `AiConfigView` gains the triple + `vision_zdr_attested` |
| `api` catalog | `GET /v1/ai-import/models` gains `supports_vision`; `curated_vision_model_ids` feed |
| `openapi.yaml` + Dart | regenerate, `CLIENT_VERSION` MINOR, commit the `regen-client.sh` diff |

Backward compatibility: every new wire field is optional/defaulted, so a
pre-change client can still save a configuration (and implicitly keeps the
assistant pair for vision). A pre-change **server** reading a post-change event
is not a supported matrix — this project does not run mixed aggregate code.

## Out of scope

- Any use of the vision slot for image generation (`image_model`, #673/#676).
- Vision-driven schedule *apply* semantics (ADR-041 `D6`).
- A general "ask a VLM about anything" surface.
- Non-EU / non-ZDR vision providers: the gate stays fail-closed; this change
  adds choices *inside* the compliant set, not outside it.
