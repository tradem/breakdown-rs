<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: space-bunny (opencode-go) -->

## MODIFIED Requirements

### Requirement: Season-Scoped Costume-Category List
A costume-categories screen SHALL be entered from the **Cast destination's
app-bar action** (scoped to the active season) and SHALL list
`CostumeCategoryView` rows for that season ordered ascending by
`order_key`, via the Result-typed repository with the Drift cache
discipline of the hierarchy screens (TTL staleness, snapshot replace on
success, cache untouched on failure). The screen SHALL NOT be reachable
from the profile/settings surface — costume categories are costume-domain
vocabulary, not user settings. Archived categories SHALL be hidden behind
an explicit toggle, never silently unlisted without that toggle.

#### Scenario: Listing categories
- **WHEN** the user opens the categories screen for a season with
  categories.
- **THEN** rows render ordered by `order_key`; the archived toggle is
  visible and off by default.

#### Scenario: Empty season vocabulary
- **WHEN** the season has no categories.
- **THEN** a plain-language empty state with the create affordance
  (session-gated) renders.

#### Scenario: Entry point sits with the costume content
- **WHEN** the user opens the Cast destination with an active season.
- **THEN** the categories screen is one app-bar action away, and the
  profile menu offers no categories entry.
