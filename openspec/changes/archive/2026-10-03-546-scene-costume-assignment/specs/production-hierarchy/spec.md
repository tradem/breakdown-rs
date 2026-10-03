<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->

## ADDED Requirements

### Requirement: Production hierarchy gains the scene-side costume relation

Within the `Series → Season → Block → Episode → Scene` hierarchy, Characters
SHALL be season-scoped aggregates and Costumes SHALL stay scope-free with
their `character_id` as the primary/default character binding. The
costume↔scene relation SHALL live on the Scene side: the Scene aggregate owns
ordered costume beats (`SceneCostumeBeat { character_id, costume_id, order,
note }`) — the scene is a unit interval of story time, and the costume of a
character within it is a function of that interval, expressed as a dense,
zero-based per-character order that supports the `on change` device (more
than one costume of one character in one scene). The relation SHALL NOT be
modelled as a costume-level field, a 1:1 scene-count constraint, a separate
relationship aggregate, or any production-level scope column on the Costume.

#### Scenario: Reading the casting of a scene

- **WHEN** a read model question asks “which costume(s) does character C wear
  in scene S?”
- **THEN** the answer SHALL come from the scene's costume beats for C
  (ordered by `order`), not from any field stored on the Costume or the
  Character aggregate

#### Scenario: Character aggregate stays appearance-free

- **WHEN** the question “which Episodes does Character C appear in?” is asked
- **THEN** it SHALL be answered by a projection join over the existing
  Scene↔Character assignment relation, and the Character aggregate SHALL NOT
  store an appearances vector

#### Scenario: Costume run across an episode is derivable

- **WHEN** a character holds beats in several scenes of one episode
- **THEN** the costume run across the episode SHALL be derivable by
  concatenating those beats in scene-number order (the dedicated
  costume-run view is out of scope of this change)
