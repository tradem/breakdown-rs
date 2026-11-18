<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# 663 — AI import: resolvable field-ambiguity uncertainties + dedicated apply-gate problem codes

## Why

A preview with `field_ambiguity` uncertainties can never be applied: the apply
gate refuses with a generic `409 domain.conflict` that discards which items
block, and no API exists to resolve them. The Flutter apply screen renders
only the bare code. A legitimate import is stuck with re-extraction as the
only escape (issue #663).

## What Changes

- **Three registered problem codes** replace the generic 409 for apply-gate
  refusals, rendered by a pure **API-edge pre-check** (the preview is already
  loaded in the handler; the worker keeps its authoritative re-check):
  - `ai-import.apply-blocked` (409) — unresolved blocking uncertainties;
    extensions carry the remaining blocking items
    (`blocking_uncertainties: [{kind, scene_index, field, note, suggested_value}]`).
  - `ai-import.apply-missing-mapping` (409, extension `draft_ref`).
  - `ai-import.apply-missing-episode-group` (409, extension `episode_ref`).
- **Request-carried acknowledgements** (design decision recorded in the
  issue): `ApplyAiImportRequest.uncertainty_acknowledgements:
  [{scene_index, field}]` with acknowledge semantics — the reviewer confirms
  the ambiguity is acceptable and the row applies as extracted. Stored
  previews stay immutable; old previews load unchanged.
- Acknowledgements are validated at the API edge (must reference an existing
  blocking uncertainty; no duplicates) and flow through the
  `ApplyScriptRequest` port into `plan_scene_apply`, whose gate now counts
  only *unacknowledged* blocking uncertainties.
- **Flutter:** the preview screen renders blocking uncertainties with a
  one-tap acknowledge action; the apply controller sends acknowledgements and
  renders `ai-import.apply-blocked` refusals from the response extensions
  inline (human-readable reason, not the bare code).

## Capabilities

### New Capabilities

None — this refines the existing `flutter-ai-import-workflow` and the
backend error surface (`http-error-surface`).

### Modified Capabilities

- `http-error-surface`: new registered codes with typed extensions.
- `flutter-ai-import-workflow`: acknowledge flow + refusal rendering.

## Impact

- `backend/crates/core/src/ai/preview.rs` — `UncertaintyAcknowledgement`,
  gate + planner signatures.
- `backend/crates/infra/src/ai/workers.rs` — port DTO + planner call.
- `backend/crates/api/src/handlers/mod.rs` — request field, validation,
  pre-check, dedicated 409s.
- `backend/crates/api/src/problems/mod.rs`, `crates/core/src/error_registry.rs`,
  `crates/api/locales/{de,en}/errors.ftl` — registry + rendering.
- `backend/openapi.yaml` — regenerated in the same PR (CI drift check).
- `frontend-flutter/` — preview/apply UI, controller, l10n, generated client
  (rebuild-only, `scripts/regen-client.sh`).
