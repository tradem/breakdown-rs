<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# Tasks — `1013-ai-import-vision-slot`

Four independently reviewable PR packages, stacked (`[V1]` → `[V2]` → `[V3]` →
`[V5]`). Every task respects `AGENTS.md` §1–§4: no write-side projection reads,
no panics on production paths, static SQL literals only, `jiff` for time,
`Arc` only for genuinely shared clients/ports, no new top-level `crates/api`
test binaries (§8).

## 1. `[V1]` Contract — aggregate, migration, projector, API (no behaviour change)

- [x] 1.1 `core::ai::aggregate::AiConfig` gains `vision_provider`,
      `vision_model`, `vision_vault_key_id`, `vision_zdr_attested`; `Apply`
      handles both `Created` and `Updated` (the update event carries the
      RESOLVED slot, mirroring `reasoning_effort`).
- [x] 1.2 `CreateAiConfig` / `UpdateAiConfig` commands gain the triple
      (update side tri-state `Option<Option<..>>` for the three slot fields,
      `Option<bool>` for the attestation) and `AiConfigEvent::Created/Updated`
      carry them with `#[serde(default)]` so pre-change events replay.
- [x] 1.3 `validate_vision_config` in the aggregate: all-or-nothing triple,
      non-empty model/key, egress-compliant provider (via
      `vision_egress_policy_for_config` + `vision_egress_compliant`), and the
      same-key reuse rule (`vision_vault_key_id == vault_key_id` only when
      `vision_provider == provider`).
- [x] 1.4 New `AiConfigError` variants + `problem_codes!` registry entries:
      `ai-config.vision-incomplete`, `ai-config.vision-model-empty`,
      `ai-config.vision-vault-key-empty`, `ai-config.vision-provider-unsupported`
      (not egress-compliant), `ai-config.vision-vault-key-mismatch` (same-key
      rule violated). Fluent texts in `de` + `en`.
- [x] 1.5 `AiConfigView` gains the triple + `vision_zdr_attested`, all
      `#[serde(default)]`.
- [x] 1.6 Migration `2026xxxx_ai_config_vision_slot.{up,down}.sql`: four
      nullable columns on `ai_import.projection_ai_config` with column
      comments; down migration drops them.
- [x] 1.7 `projectors/ai_config.rs` upsert/update carry the four columns;
      `queries/ai_config.rs` `find_by_id`/`list_for_user`/`map_config_row`
      project them back.
- [x] 1.8 `api`: `CreateAiConfigRequest`/`UpdateAiConfigRequest` gain the
      triple (update side `deserialize_optional_nullable`), the handlers map
      them into the commands, and the API edge validates the vision credential
      binding (ownership + provider binding, same shape as the decision key).
- [x] 1.9 `openapi.yaml` regenerated (`UPDATE_OPENAPI=1 cargo test -p api
      --test contract openapi_drift`), `CLIENT_VERSION` MINOR bump and the
      committed Dart client regenerated via `frontend-flutter/scripts/regen-client.sh`
      (including its tri-state serializer workaround for the new vision fields).
- [x] 1.10 Tests: aggregate triple validation (half-set, empty, same-key reuse,
      clear path, non-compliant provider), event replay of pre-change payloads,
      API create/update/view round-trip + `422` codes, projector/query round-trip.

## 2. `[V2]` Worker wiring — the vision pair actually carries pages

- [x] 2.1 `AiWorkerConfig.vision: Option<AiWorkerVisionConfig>` resolved
      all-or-nothing in `find_worker_config` (partial row → `None` + warn).
- [x] 2.2 Page-streaming schedule path builds a vision `Arc<dyn LlmClient>`
      (own gate, own credential) and sends pages with the vision pair; the flat
      text path keeps the primary client. Client reuse only when provider,
      credential and transport inputs match.
- [x] 2.3 Provider health binding includes the vision model, so the operator
      sees which credential serves images.
- [x] 2.4 Tests: recording client asserts pages use the vision pair and chunks
      the text pair (both directions); breaker isolation per pair; per-pair cost
      attribution; vision-client build failure → terminal code; rendered-byte
      ceiling unchanged.

## 3. `[V3]` Vision catalogue

- [x] 3.1 `provider_registry::curated_vision_model_ids(provider)` — a third
      curated list (text / image-generation / vision), never an overload of
      `curated_image_model_ids`.
- [x] 3.2 Pricing seed rows for every curated vision model in
      `ai_import.ai_model_pricing`.
- [x] 3.3 `ModelInfo.supports_vision: bool` (`#[serde(default)]`), populated by
      the curated catalog endpoint.
- [x] 3.4 Catalog route/param decision implemented (`GET /v1/ai-import/models`
      vision filter or sibling route) + OpenAPI + Dart regen.
- [x] 3.5 Aggregate validation uses `is_curated_vision_model` for a CHANGED
      model only (catalogue-rotation safety, same rule as `decision`).

## 4. `[V5]` Zoning pass

- [x] 4.1 `core::ai::preview::extract_scenes_with_zones(document, &zones)` and
      `extract_scenes_from_structured` delegating to it (zoning decisions stay
      outside the pure slicer).
- [x] 4.2 Zone-answer DTO + deserializer that structurally discards any prose
      (a model returning transcribed text cannot leak it into a chunk), with
      validation for unknown zones, missing/duplicate page numbers and anchors
      outside the document's `BlockAnchor` space.
- [x] 4.3 VLM zoning call in the script worker: triggered only by
      `fell_back_to_script_body()`, one page at a time, bounded by page count
      (`AI_IMPORT_MAX_ZONING_PAGES`) and `AI_IMPORT_MAX_RENDERED_TOTAL_BYTES`.
- [x] 4.4 Fail-open path: stable `warn` event + one preview diagnostic
      (`zone_detection: fell_back`), widened fallback unchanged; `legacy-pdftotext`
      render refusal logged by name, no render attempt.
- [x] 4.5 `StructuralPlan` records its source (`deterministic` | `vlm`); the
      digest keeps driving `fingerprint_key`, so a changed vision model restarts
      at chunk `0`.
- [x] 4.6 Tests: parity of `extract_scenes_with_zones` with today's deterministic
      path, prose-discarding deserializer, a "bad template" fixture whose only
      path to correct scene counts is a supplied zone plan, corpus run
      (40/42/43/42/42) with a scripted zone answer, and the fail-open path.
- [x] 4.7 `backend/.github/instructions/ai-import.instructions.md` documents the
      vision slot, the zoning trigger, the page cap and the legacy-parser limit.

## 5. Open finding (recorded, not fixed)

The `fell_back_to_script_body()` trigger specified in the issue is **inert for
the chunk set**: `classify_document_zones` marks any page with a recognised
scene heading as `ScriptBody`, so `!has_script_body()` implies the document has
NO recognised heading — and a zone plan cannot invent one. The pass therefore
runs, validates and is recorded (`source = vlm`), but the widened fallback it
replaces already produced the same (empty) chunk set. The contamination case the
issue describes (`SYNOPSIS`/`SCRIPT REPORT` glued into scenes) happens when
`has_script_body()` is TRUE, which the specified trigger never fires on.

A useful trigger is the issue's own "optional second trigger": fire the pass when
the deterministic verdict is *suspect* — e.g. a `SceneIndex` page plus a
`ScriptBody` page count below the index's entry count, or a body page count
that disagrees with the index. That is a behavioural change to the trigger and
belongs to a follow-up decision, not to this contract PR.
