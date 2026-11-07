<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# flutter-scene-detail

## ADDED Requirements

### Requirement: The scene detail screen reads as page identity, not tiles

The scene detail screen SHALL render `Szene {number}` as the app-bar title
(the summary leaves the app bar), followed by a content header block — the
scene number as a large numeral, the location as the title line, and a
metadata chip row (mood with its #721 icons, script day,
geplant/ungeplant flag, and the „AI-generiert" provenance badge derived from
`SceneView.source`). The header SHALL NOT be wrapped in a card border and
SHALL NOT use a collapsing `SliverAppBar`.

#### Scenario: The app bar names the scene

- **WHEN** the screen resolves a scene with `sceneNumber = 12`
- **THEN** the app bar reads „Szene 12" regardless of the summary text

#### Scenario: The AI badge follows the provenance

- **WHEN** `SceneView.source` is `AiExtracted`
- **THEN** the header and the synopsis section render the „AI-generiert"
  badge; a manually created scene renders none

### Requirement: Sections are divider-free and collapsed by default

Every section of the screen (Figuren, Kleidung, Drehtage, Synopsis) SHALL
render through the `SectionCard` component without shape borders — the screen
SHALL NOT contain a `Divider` (or Material-3 `ExpansionTile` border chrome)
in any expansion state. Every section SHALL be collapsed by default and SHALL
keep its count in the header (e.g. „Figuren (3)"). Separation comes from
cards and token spacing only.

#### Scenario: A collapsed section still tells its story

- **WHEN** the screen first renders with three characters, five beats and two
  days
- **THEN** every section is collapsed and its header shows the count

#### Scenario: No divider in any state

- **WHEN** any section is expanded or collapsed
- **THEN** the widget tree contains no `Divider` widget on this screen

### Requirement: The synopsis has its own section

The synopsis SHALL be rendered in full in a dedicated section — not as the
app-bar title — with the AI-provenance badge when applicable, the persisted
Decision-Model ratings via `AiScoreStars` (`scene_score` / `synopsis_score`),
and an honest „Keine Synopsis" empty state. An absent score SHALL render
nothing (no fabricated stars).

#### Scenario: A scored synopsis shows its ratings

- **WHEN** the scene carries `synopsisScore = 0.82` and `sceneScore = 0.55`
- **THEN** the synopsis section shows both star ratings next to the text

#### Scenario: An unscored scene shows no stars

- **WHEN** either score is `null`
- **THEN** no star widget renders for that score

### Requirement: All scene fields are editable through one sheet

A „Szene bearbeiten" affordance SHALL open one sheet covering scene number,
location, mood, script day and summary, dispatched through
`SceneRepository.updateSceneDetails` with the `version` echoed from the acted
-on `SceneView` (optimistic locking, #473). Mood editing SHALL offer the
canonical set as chips plus a free-text fallback, and SHALL NOT destroy a
stored value outside the canonical set. The command error surface SHALL be
localized keyed on `code`, with `concurrency.version-mismatch` rendered as a
retry narrative.

#### Scenario: The editor echoes the version

- **WHEN** the user saves the sheet
- **THEN** the dispatched `UpdateSceneDetailsRequest` carries the `version`
  of the `SceneView` the sheet was opened from

#### Scenario: A non-canonical mood survives the editor

- **WHEN** the stored mood is not in the canonical set and the user edits
  only the location
- **THEN** the dispatched details keep the stored mood verbatim

#### Scenario: A version conflict is a localized retry

- **WHEN** the update answers `409 concurrency.version-mismatch`
- **THEN** the screen surfaces the localized conflict narrative and refreshes
  the projection, and never re-dispatches automatically
