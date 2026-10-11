<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3-flash (opencode-go) -->

# flutter-role-extract Delta (issue #611 — role-extract view, degraded landing)

## ADDED Requirements

### Requirement: Cast Character Row Opens the Role Extract
The Cast view's character row SHALL open the role extract screen
(`RoleExtractScreen`) — the entry point IS the extract, never the bare
character detail. The screen is pushed on the Cast destination's nested
navigator, receives the season scope as plain data (same seam as the
roster) and the character id as route parameter, and mounts with the
stable route key `role-extract-<characterId>`.

#### Scenario: Tapping a roster row opens the role extract
- **WHEN** an authenticated user taps a character row in the Cast view's
  roster.
- **THEN** the role extract screen is pushed (route key
  `role-extract-<characterId>`), not the bare detail screen.

### Requirement: Degraded Fallback Without Client-Side Aggregation
Until the backend per-character appearances read model
(`GET /v1/characters/{id}/appearances`, backend issue #621) exists, the
role extract screen SHALL render the character detail as today
(list-only fallback). The client SHALL NOT aggregate the extract
client-side: per-scene membership fan-out (N scenes → N calls) is
rejected — per the CQRS discipline the client never aggregates
projections itself. When the backend route ships, only the screen's body
swaps to the generated appearances type; call sites and route keys are
unchanged.

#### Scenario: Degraded parity under the extract route
- **WHEN** the role extract screen is opened before the backend
  appearances read model exists.
- **THEN** the character detail content (contacts, measurements, category
  row) renders as today under the extract route, and no per-scene
  membership query is issued.

### Requirement: On-Device Navigation Step (Pending)
A Gherkin scenario SHALL cover "open role extract from Cast view"
(`features-spec/role_extract.feature`) with a dedicated `whenOpenRoleExtract`
step that scopes the Cast view to the seeded season and taps the roster's
character tile. The scenario is tagged `@pending` until the backend read
model ships and the seeding Given establishes the character symbolic id;
the degraded route is covered by widget tests meanwhile.

#### Scenario: Pending on-device promotion
- **WHEN** the backend appearances read model lands and the extract rows
  render.
- **THEN** the scenario is promoted (the `@pending` tag removed) and runs
  in the on-device pass (the runner's `not @pending` tag expression).
