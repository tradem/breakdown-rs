<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3-flash (neuralwatt) -->

## ADDED Requirements

### Requirement: AI-created scenes carry a provenance discriminator

The AI script apply SHALL stamp every scene it creates with
`SceneSource::AiExtracted { document_id, external_ref, confidence }`, where
`document_id` is the AI import job id, `external_ref` is the draft ref, and
`confidence` is `None` (the pipeline measures no per-row model confidence). The
REST scene-creation path and every client request SHALL record `Manual`; clients
SHALL NOT be able to set provenance on `CreateSceneRequest`. The `SceneView`
read model SHALL expose the discriminator as an optional additive field
(`source: Option<SceneSource>`, ADR-021 D3/MINOR): `Some(AiExtracted)` marks
AI-imported scenes, `Some(Manual)` the user-created path and `None` only
legacy clients that predate the field.

#### Scenario: Script apply marks the scene as AI-extracted

- **WHEN** the AI script apply dispatches `CreateScene` for a mapped draft row
- **THEN** the emitted `SceneCreated` event carries
  `SceneSource::AiExtracted { document_id: <job id>, external_ref: <draft_ref>, confidence: None }`
- **AND** the `SceneView` read model exposes the same discriminator as `source`

#### Scenario: Manual creation stays indistinguishable from legacy data

- **WHEN** a scene is created via the REST handler
- **THEN** the emitted `SceneCreated` event carries `SceneSource::Manual`
- **AND** a historic `SceneCreated` event persisted before the `source` field
  existed replays as `SceneSource::Manual` (serde default, no migration)

### Requirement: Recorded extraction confidence is honest

The schedule-side apply SHALL record `ShootingDaySource::AiExtracted.confidence`
as `None` while the import pipeline measures no real per-row model confidence.
It SHALL NOT hard-code a placeholder confidence value.

#### Scenario: Pre-change events read losslessly

- **WHEN** a persisted `ShootingDaySource::AiExtracted` event carries a plain
  numeric `confidence` (pre-#517 hard-coded `1.0`)
- **THEN** it deserializes losslessly as `Some(...)`
- **WHEN** the current apply creates a shooting day
- **THEN** the persisted provenance carries `confidence: null`
