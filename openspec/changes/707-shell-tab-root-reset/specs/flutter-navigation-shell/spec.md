<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3-flash-flex (neuralwatt) -->

# flutter-navigation-shell Delta

## MODIFIED Requirements

### Requirement: Tab Root Reset on Destination Selection

The shell SHALL reset the TARGET destination's nested navigator to its
root route when a destination is selected — both when SWITCHING to
another destination and when RE-TAPPING the already-active destination
(Material convention "re-tap = back to start"). The reset SHALL be
applied centrally in the shell's destination-selection handler so all
three morphologies (`NavigationBar`, `NavigationRail`,
`NavigationDrawer`) behave identically. Per-tab navigation position
memory across destination switches (former design D2) SHALL NOT exist.
When the target navigator is already at its root, the reset SHALL be a
no-op. The back contract (pop within the active destination's stack; at
a destination root no destination hopping; app-exit intent at the
initial Cast destination root) SHALL remain unchanged. The shell
controller SHALL distinguish a destination switch from a re-tap of the
already-active destination in its selection result and SHALL reject
out-of-range indices without changing state.

#### Scenario: Switching tabs shows the target's start screen

- **WHEN** the user has drilled into a destination's sub-pages (e.g.
  Settings opened from the account drawer, then a settings sub-page),
  switches to another destination, and returns.
- **THEN** the destination shows its start screen (root route), not the
  previously visited sub-page.

#### Scenario: Re-tap of the active destination pops to root

- **WHEN** the user taps the already-active destination while a
  sub-page is pushed on its nested navigator.
- **THEN** the navigator pops to the destination's root screen.

#### Scenario: Re-tap at the root is a no-op

- **WHEN** the user taps the already-active destination while its
  navigator is at the root route.
- **THEN** nothing changes (no error, no state transition).

#### Scenario: Reset applies in every morphology

- **WHEN** a destination is selected via the bottom `NavigationBar`
  (compact), the `NavigationRail` (medium) or the permanent
  `NavigationDrawer` (expanded).
- **THEN** the target destination's nested navigator is popped to its
  root in all three morphologies (one central handler).

#### Scenario: Back contract unchanged

- **WHEN** the user presses system back after the reset behavior is
  active.
- **THEN** back pops within the active destination's stack first, never
  hops destinations, and at the initial Cast destination root issues the
  app-exit intent (D3 unchanged).

#### Scenario: Out-of-range selection is still rejected

- **WHEN** the shell controller is asked to select a destination index
  below `0` or above `kScheduleTabIndex`.
- **THEN** the selected destination does not change and the selection
  result reports the rejection.
