<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3-flash (neuralwatt) -->

## ADDED Requirements

### Requirement: Scene provenance projection (AI transparency)

The `projection_scene` table SHALL store the scene's provenance discriminator
`source` as JSONB covering both the `Manual` and the
`AiExtracted { document_id, external_ref, confidence }` shapes (migration
`20260926000001` with a `{"Manual":null}` default). The scene projector SHALL
write the `SceneCreated` event's discriminator on insert and redelivery update;
the scene and shooting-day query adapters SHALL deserialize it into
`SceneView.source`.

#### Scenario: Projection defaults legacy rows to Manual

- **WHEN** the migration runs against rows created before #517
- **THEN** each `projection_scene.source` equals the `{"Manual":null}` default

#### Scenario: Replay of a legacy event projects Manual

- **WHEN** the scene projector processes a `SceneCreated` event whose payload
  predates the `source` field (serde default `Manual`)
- **THEN** the projection row's `source` is `Manual`

#### Scenario: AI-created scenes are distinguishable in the read model

- **WHEN** the scene projector processes a `SceneCreated` event stamped
  `SceneSource::AiExtracted { document_id, external_ref, confidence: None }`
  (AI script apply)
- **THEN** the projection row's `source` carries the `AiExtracted` object shape
- **AND** `SceneView.source` exposes it unchanged to the wire (additive field,
  ADR-021 D3 MINOR)
