<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-4.6-fp8 (neuralwatt) -->

# Proposal: EU AI Act Art. 4/50 transparency — backend provenance substratum (issue #517)

## Summary

Implement the **backend share** of the EU AI Act (Regulation (EU) 2024/1689)
transparency obligations for the AI import. This change makes AI-derived data
permanently identifiable at the domain/wire level so both frontends can render
point-of-interaction disclosures and provenance badges in a follow-up:

1. **Scene provenance:** new `SceneSource` discriminator (`Manual` |
   `AiExtracted { document_id, external_ref, confidence }`) on `SceneCreated`,
   the `SceneAggregate`, the projection (`source JSONB` + migration), the read
   adapter, and the wire (`SceneView.source`). The AI script apply stamps
   AI-imported scenes; the REST handler records `Manual`.
2. **Honest confidence:** `ShootingDaySource::AiExtracted.confidence` becomes
   `Option<f32>`; the schedule apply records `None` instead of the misleading
   hard-coded `1.0`. Persisted `f32` values deserialize losslessly as `Some(..)`.
3. **Explicit non-goal (documented):** Art. 50(2) machine-readable marking of
   raw model outputs (C2PA/watermarks) is a *provider* duty — Breakdown RS is a
   deployer of a server-side configured third-party LLM and publishes no
   AI-derived content; internal-use labeling duties do not bite. The
   preview-before-apply flow is the human editorial review step the AI Act
   narrative rewards.

## Problem

The current-state audit in issue #517 shows: the only AI disclosure is a static
About-dialog notice (not at the point of interaction), `Scene`/`SceneShoot`
cannot represent provenance at all, and the schedule apply hard-codes
`confidence: 1.0` — a value the pipeline never measured. Without the domain
substratum, no persistent provenance badge anywhere in the app is possible.

## Decision

- `SceneSource` mirrors `ShootingDaySource` but carries `confidence: Option<f32>`
  from day one. `SceneCreated.source` is serde-defaulted to `Manual` so historic
  events replay without a migration (event-fixture contract test pins this).
- REST clients **cannot** fabricate provenance: `CreateSceneRequest` has no
  source field; only the AI workers stamp `AiExtracted` server-side.
- `SceneShoot` provenance is **deferred** (user decision): its provenance is
  transitively implied by the pair-unique (scene, day) pair; tracted as a
  follow-up if a read surface ever needs it.
- Wire: `SceneView.source` is an additive field (ADR-021 D3 — MINOR, `/v1` path
  version stays); wire fixture allowlisted, `openapi.yaml` regenerated.

## Validation

- `cargo test -p breakdown_core`: 337 passed (incl. new
  `tests/scene_provenance.rs` — legacy-event replay defaults, numeric-confidence
  lossless decode, AI provenance round-trip through aggregate + replay).
- `cargo test -p infra`: 371 passed (projector writes source JSONB).
- `cargo test -p api`: all green, `openapi_drift` 4/4 after regeneration.
- Integration tests (Postgres/SierraDB testcontainers): projector_scene_test,
  projector_tests, command_adapter_tests, query_repository_tests,
  repository_scene_test, scene/shooting_day round-trips, event fixture chain
  (legacy replay → projection), wire-contract gate with the additive allowlist.
- `cargo clippy --workspace --all-targets`: clean; `cargo fmt` applied.

## Non-goals (this change)

- All Flutter read-surface work: in-flow disclosure on the submit screen, AI
  banner on the preview, review-acknowledgement before apply, provenance badge
  rendering, About-dialog expansion, Drift cache column + migration, regenerated
  Dart client — **follow-up in a separate frontend session/branch** (same issue).
- Art. 50(2) machine-readable output marking (provider duty) — documented
  non-goal above; publication labeling of internal data stays out of scope.
- Art. 4 operational team duty (AI literacy training) — outside the codebase.

## Version bumps

| Crate | Previous | New | Bump type | Reason |
|---|---|---|---|---|
| `core` | 0.12.0 | 0.13.0 | MINOR | New public `SceneSource` enum + `CreateScene.source` field; `ShootingDaySource.confidence` type change (`f32` → `Option<f32>`, serde-compatible) |
| `infra` | 0.17.0 | 0.18.0 | MINOR | Additive `projection_scene.source` column (migration) + projector writes provenance; re-pins `core` 0.13.0 |
| `api` | 0.11.0 | 0.12.0 | MINOR | Additive `SceneView.source` wire field (ADR-021 D3/MINOR) + regenerated `openapi.yaml`; re-pins `core` 0.13.0 / `infra` 0.18.0 |
