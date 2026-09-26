<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-4.6-fp8 (neuralwatt) -->

# Tasks: EU AI Act transparency — backend provenance substratum (issue #517)

## 1. Core domain

- [x] 1.1 Add `SceneSource` (`Manual` | `AiExtracted { document_id, external_ref, confidence: Option<f32> }`) in `crates/core/src/scene/events.rs`
- [x] 1.2 Add serde-defaulted `source` field to `SceneCreated` (historic events replay as `Manual`)
- [x] 1.3 Add `CreateScene.source` (serde default) and keep it through `SceneAggregate` apply/replay
- [x] 1.4 Expose `SceneView.source`; re-export `SceneSource` from `scene` + OpenAPI components
- [x] 1.5 Change `ShootingDaySource::AiExtracted.confidence` to `Option<f32>` with replay-compat docs
- [x] 1.6 Stamp `SceneSource::AiExtracted` in `plan_scene_apply` (planner truth) with the import job id

## 2. Infra

- [x] 2.1 Migration `20260926000001_projection_scene_source` (up + down): `projection_scene.source JSONB NOT NULL DEFAULT '{"Manual":null}'`
- [x] 2.2 Scene projector: write `source` on `SceneCreated` insert and redelivery update
- [x] 2.3 Query mappers (`queries/scene.rs`, `queries/shooting_day.rs`): select + deserialize `source` into `SceneView`
- [x] 2.4 AI script apply (`workers.rs::create_scene_reserved`): dispatch `CreateScene` with `AiExtracted { job_id, draft_ref, confidence: None }`
- [x] 2.5 Schedule apply (`schedule_apply.rs`): replace hard-coded `confidence: 1.0` with honest `None`

## 3. API / contract

- [x] 3.1 `create_scene` handler records `Manual` (no client-side provenance fabrication)
- [x] 3.2 Regenerate `openapi.yaml` (`UPDATE_OPENAPI=1 cargo test -p api --test openapi_drift`)
- [x] 3.3 Additive-allowlist `scene_view.source` in the wire-contract fixture gate (ADR-021 D3, MINOR)
- [x] 3.4 Update event-fixture projection expectation for the legacy replay (`source: "Manual"`)

## 4. Tests

- [x] 4.1 New `crates/core/tests/scene_provenance.rs`: legacy `SceneCreated` without `source` replays; legacy numeric `confidence` decodes as `Some`; AI round-trip through aggregate + state replay
- [x] 4.2 Update all `CreateScene`/`SceneCreated`/`SceneView` struct-literal constructors (tests + fuzz stubs)

## 5. Release (ADR-020 D2/D5)

- [x] 5.1 `core` 0.12.0 → 0.13.0 (MINOR), CHANGELOG entry
- [x] 5.2 `infra` 0.17.0 → 0.18.0 (MINOR, re-pin core), CHANGELOG entry
- [x] 5.3 `api` 0.11.0 → 0.12.0 (MINOR, re-pin core/infra), CHANGELOG entry
- [x] 5.4 `Cargo.lock` regenerated and committed

## 6. Follow-ups (out of this change)

- [ ] 6.1 Flutter transparency surfaces (disclosure banner, review acknowledgement, provenance badges, About-dialog expansion, Drift cache migration, Dart client regen) — separate frontend session/branch
- [ ] 6.2 Decide on `SceneShoot` provenance only if a read surface ever needs it
