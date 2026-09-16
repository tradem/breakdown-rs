<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

## ADDED Requirements

### Requirement: Screen specifications follow the unified format
Every feature screen (new or redesigned) SHALL have a screen
specification at `docs/design/screens/<screen-name>.md` following the
unified template with sections: Purpose & Context, Navigation,
Layout, Components & Semantics, States, Interactions, Input &
Validation, Accessibility & i18n, Tests. The screen spec SHALL be
authored (or updated) in the same OpenSpec change that implements the
screen.

#### Scenario: New screen is proposed
- **WHEN** a change adds or significantly redesigns a screen
- **THEN** the change's artifacts reference a screen spec at
  `docs/design/screens/<screen-name>.md` containing all nine template
  sections
- **AND** the spec is written before the implementation tasks are
  executed

#### Scenario: Existing screen without a spec
- **WHEN** a screen exists without a screen spec and is not modified
- **THEN** no backfill is required by this change (backfill is tracked
  by the roadmap's P5 item, not enforced here)

### Requirement: Salt wireframes document static layout only
Screen specs SHALL express layout as embedded PlantUML Salt wireframes
(in fenced ```plantuml blocks). Salt wireframes SHALL be limited to
static structure: component arrangement, grouping, and hierarchy.
Behavior, state transitions, timing, animation, and interaction
details SHALL be documented in the spec's structured Markdown sections
(and codified in tests), never inside Salt diagrams (team decision 7).

#### Scenario: Wireframe shows a navigation bar
- **WHEN** a screen spec contains a Salt wireframe of a screen with
  bottom or rail navigation
- **THEN** the wireframe renders destination labels as visible text
  alongside icons, per the labeling rule in the glossary requirement

#### Scenario: Interaction behavior needs documenting
- **WHEN** a screen has bottom-sheet behavior, snackbar timing, or
  animated transitions
- **THEN** the screen spec documents it in the Interactions (or
  States) Markdown section
- **AND** does not attempt to express it inside the Salt wireframe

### Requirement: Salt wireframes must compile
Every PlantUML block under `docs/design/` SHALL be syntactically valid
PlantUML. CI SHALL validate all `.md` files under `docs/design/` by
extracting fenced ```plantuml blocks and running PlantUML
`-checkonly` validation, failing the pipeline on any syntax error.

#### Scenario: A design doc with a broken diagram is pushed
- **WHEN** a commit modifies a file under `docs/design/` containing a
  fenced PlantUML block that does not compile
- **THEN** CI fails with the file name and the PlantUML error output

### Requirement: Icon and terminology glossary
The repository SHALL maintain a glossary at `docs/design/glossary.md`
mapping each Material Symbols icon in use to its user-facing German
term and its usage context. Every navigation destination and every
primary action in the app SHALL render a visible text label; icons
MAY reinforce but SHALL NOT be the sole carrier of meaning. Screen
specs SHALL source their UI copy keys and icon choices from the
glossary.

#### Scenario: Adding a new screen action
- **WHEN** a new screen action or navigation destination is added
- **THEN** its visible label, icon, and context are recorded in
  `docs/design/glossary.md`
- **AND** the UI renders the label visibly (not only as a tooltip or
  content description)

### Requirement: Design docs are cross-platform source files
Screen specs and the glossary SHALL be written platform-neutral:
component references to Material 3 components SHALL use generic
component vocabulary (e.g. "navigation bar", "extended FAB",
"assist chip") so the same spec can seed Svelte, Slint, and GPUI
implementations. Flutter-specific details SHALL be confined to task
lists and code, not to the spec's component/semantics tables.

#### Scenario: Spec reviewed for a second platform
- **WHEN** a Svelte or Slint frontend derives from an existing screen
  spec
- **THEN** the spec's Layout, Components & Semantics, States, and
  Interactions sections apply without Flutter-specific vocabulary
  blocking the derivation
