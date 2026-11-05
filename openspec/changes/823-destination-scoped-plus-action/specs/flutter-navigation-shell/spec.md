<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

## ADDED Requirements

### Requirement: Destination-scoped plus action

The shell's quick-create plus action SHALL render on the **Script destination
only** — that is, while `ShellState.selectedIndex == kScriptTabIndex` — in all
three navigation morphologies (compact bottom bar, medium rail, expanded
drawer) and on every route pushed inside that destination's nested navigator. A
destination, not a route, is the scoping unit: the affordance is the Script
view's create entry, so it stays available while the user drills into a scene.

On the Cast and Schedule/Dispo destinations the shell SHALL render no plus
action at all, and SHALL NOT reserve the compact bottom clearance
(`kShellFabBottomClearance`) that exists only to keep a docked FAB off the last
list row. The three morphologies therefore differ only in where the FAB is
placed, never in whether it exists.

The entry set SHALL be unchanged: the Shell SHALL keep handing
`shellQuickCreateActions` to the shared quick-create sheet, including the
episode-scope guard that offers „Szene"/„Drehtag" only when the active episode
scope belongs to the active season.

The plus action SHALL be rendered only for a resolved authenticated session
(client-side AUTHZ-GATE mirror, Decision D6 of the Flutter foundation): a
pending, erroring or signed-out session renders no plus action on any
destination, and the gate's comment travels with the affordance.

#### Scenario: The Script destination carries the plus action in every morphology
- **WHEN** the shell renders with the Script destination selected at 360 dp,
  700 dp and 1000 dp
- **THEN** the `shell-plus-fab` affordance is present once in each morphology

#### Scenario: Cast and Schedule carry no plus action
- **WHEN** the user selects the Cast or the Schedule/Dispo destination
- **THEN** no plus action is rendered, and (compact) no
  `kShellFabBottomClearance` band is reserved under the content

#### Scenario: The plus action keeps the shipped entry set
- **WHEN** the Script destination's plus action opens the quick-create sheet
- **THEN** the sheet lists the unchanged entries („Szene" and „Drehtag" only
  for an active episode scope of the active season, plus „Import" and
  „Season-Setup"), and each entry routes to the flow it shipped with

#### Scenario: An unresolved session renders no plus action
- **WHEN** the auth session is pending, erroring or signed out
- **THEN** neither the shell's plus action nor the AI-import jobs screen's
  Import action is rendered
