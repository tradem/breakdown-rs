<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# scene-scoping

## ADDED Requirements

### Requirement: Scene carries the Decision-Model quality scores

`SceneDetails` SHALL carry optional `scene_score: Option<f32>` and
`synopsis_score: Option<f32>` (normalized `0.0..=1.0`, the issue #722
`DraftScene` fields), additive on the event/command wire with serde defaults
(ADR-021 MINOR). The apply path SHALL populate them from the draft; the scene
projection SHALL store them as nullable `double precision` columns; the
`SceneView` read model SHALL expose them (`scene_score`, `synopsis_score` on
the wire). The projector SHALL write the scores on `SceneCreated` and SHALL
PRESERVE the persisted columns on `SceneDetailsUpdated` — a later detail edit
SHALL NOT erase the recorded provenance. A value SHALL be absent (`NULL`) for
manually created scenes and for draft rows whose best-effort scoring pass
failed; no consumer SHALL fabricate a value for the absent case.

#### Scenario: A scored AI apply persists both scores

- **WHEN** an apply dispatches `CreateScene` whose `details` carry
  `scene_score = Some(0.82)` and `synopsis_score = Some(0.41)`
- **THEN** the projector writes both values into `projection_scene` and the
  scene read model returns them unchanged

#### Scenario: A detail update preserves the recorded provenance

- **WHEN** `SceneDetailsUpdated` rewrites location/number/mood/summary of a
  scored scene (its details payload echoing no scores)
- **THEN** the projection keeps the persisted `scene_score` /
  `synopsis_score` from the apply, and the edited fields apply

#### Scenario: Pre-#834 events replay unscored

- **WHEN** a `SceneCreated` event payload without the score keys is
  deserialized (historic stream or legacy client)
- **THEN** both fields deserialize to `None` without a data migration
