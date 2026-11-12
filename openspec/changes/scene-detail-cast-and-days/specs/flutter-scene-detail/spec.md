<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# flutter-scene-detail

## ADDED Requirements

### Requirement: The scene detail plans before it casts

The scene detail body SHALL order its sections **workflow-first**: identity
block, synopsis, then the shooting days, then the cast. The shooting days SHALL
render above the cast because a scene is planned before it is cast and the dispo
is built from the days, not from the looks.

Every day affordance SHALL be reachable from that section as an ICON on the row
it acts on (day board, move to another day, unschedule) plus the labelled
schedule action below the list. The "move to another day" action SHALL schedule
the newly picked day **first** and unschedule the current one **only after that
acknowledgement**, chained on the version the API returned — a refused schedule
SHALL leave the scene on the day it had, and a refused release SHALL leave it on
both days (two visible, individually removable rows), never on none.

#### Scenario: The days section precedes the cast

- **WHEN** the scene detail renders for a scene with one planned day and one figure
- **THEN** the shooting-days card appears above the cast card in the scroll order

#### Scenario: Moving a scene to another day releases the old one last

- **WHEN** the reviewer picks "move to another day" on a planned row and chooses a second day
- **THEN** the scene is scheduled on the second day first, and the first day is
  unscheduled only after that command was acknowledged

#### Scenario: A refused move keeps the planned day

- **WHEN** the schedule command is refused (e.g. `concurrency.version-mismatch`)
- **THEN** no unschedule is dispatched and the scene keeps the day it had

#### Scenario: A refused release leaves both days visible

- **WHEN** the schedule succeeded but the unschedule of the previous day is refused
- **THEN** the scene is shown on both days, each row removable, and the refusal is
  reported with its stable problem `code`

### Requirement: The script day binds to a real shooting day

The identity block's script-day chip SHALL carry the affordance that binds the
day the SCRIPT states (`SceneView.scriptDay`, e.g. „Tag 1") to a **real** shooting
day of the episode, opening the same day picker the section uses. The affordance
SHALL be disabled exactly when no candidate day exists (the episode has none, all
are archived, or the scene already sits on the only one), and it SHALL NOT
fabricate a day, a date or an association the server does not hold.

#### Scenario: Binding the script day

- **WHEN** the scene states "Tag 1" and the episode has a real day that is not on the scene
- **THEN** the chip's icon opens the day picker and scheduling the picked day binds it

#### Scenario: Nothing to bind

- **WHEN** every day of the episode is already planned on this scene
- **THEN** the chip's icon is disabled

### Requirement: Figure and look share one table row

The scene detail SHALL render ONE expandable cast section, titled with both
counts (`Figuren ({characters}) · Looks ({looks})`), instead of separate figures
and looks sections: the reader SHALL NOT have to join two lists by hand.

Each row SHALL show the figure and the look it wears in this scene in the **same**
row, with column labels, the look's category icon, the wardrobe cue and the
change arrow (`→`) for a figure's further looks. A figure with several looks
SHALL render one row per look so each look stays individually removable, and a
figure without a look SHALL state that in the look cell and offer the look
affordance there.

Per row the reviewer SHALL be able to remove the look, remove the figure, add a
look, or edit — where editing opens the Cast screen (the character detail, with
the season row resolved cache-first) and returning refreshes the scene so a
renamed or removed look no longer renders its old label.

The section SHALL offer one bottom action, „Figur und Look zuweisen", which picks
an unassigned figure and then opens that figure's look picker: two commands in
the aggregate's order, because a beat needs an assigned character. A cancelled
look picker SHALL leave the figure cast (a role without a costume is a real
state) and SHALL NOT roll the assignment back. When the figure has no look yet,
the flow SHALL say so instead of opening an empty picker.

#### Scenario: One row names the figure and its look

- **WHEN** a scene casts one figure wearing one look
- **THEN** a single row shows the figure's name, the look's label and the look's
  category icon, and the section header names both counts

#### Scenario: A figure with a change renders one row per look

- **WHEN** a figure wears look A and then look B in the same scene
- **THEN** the figure is named once, and each look has its own row (the second
  prefixed with `→`) with its own removal

#### Scenario: The combined assign action casts and dresses

- **WHEN** the reviewer taps „Figur und Look zuweisen" and picks an unassigned figure
- **THEN** the character is assigned to the scene and its look picker opens

#### Scenario: Editing opens the Cast screen

- **WHEN** the reviewer taps the edit icon of a cast row
- **THEN** the Cast screen for that figure is pushed, and returning refreshes the
  scene projection

### Requirement: Mood icons render for mixed location shorthands

The mood resolver SHALL resolve every location component of the set shorthand
(one location icon per component, in the shorthand's own order) plus the
time-of-day icon, so a MIXED shorthand such as `A/I/T` ("shot outside at the
street, then inside the clinic / day") renders the same icons the import preview
shows for the simple shorthands — never plain text.

A shorthand naming exactly the two distinct locations `I` and `A` in either order
(`I/A/*`, `A/I/*`) SHALL resolve to ONE threshold icon, because the scene crosses
the door — one fact, not two. The editor's canonical chip set SHALL additionally
offer the `A/I/*` forms (which the deterministic heading scan never produces but
a script states verbatim); a stored value outside the canonical set keeps
rendering as its own chip and is never destroyed.

#### Scenario: A mixed mood renders icons

- **WHEN** a scene carries the mood `A/I/T`
- **THEN** the header renders the threshold icon and the day icon next to the
  visible `A/I/T` label

#### Scenario: An unparsable mood stays text

- **WHEN** the mood is free text such as "tense"
- **THEN** no icons render and the label stays visible
