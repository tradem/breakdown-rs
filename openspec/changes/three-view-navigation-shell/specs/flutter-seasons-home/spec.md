<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: space-bunny (opencode-go) -->

## MODIFIED Requirements

### Requirement: Season Cards as Home Content
The seasons overview SHALL render each projected season as a Material 3
card containing the season title (name if present, otherwise
"Season {number}"), contextual metadata (block count, and scene/
costume counts where available from the Drift read-model cache),
and a trailing chevron navigation affordance. The overview SHALL no
longer be a shell destination: it is pushed from the season scope
picker's season-management entry on the active destination's nested
navigator. The card tap SHALL enter the season's detail/planning view
as before. Optimistic overlay rows SHALL render as cards in the same
visual language, preserving their existing keys (`overlay-<id>`,
spinner / `overlay-warning`) and stale-warning behavior.

#### Scenario: Projected season with cached metadata
- **WHEN** the seasons list renders a projected season whose
  hierarchy cache holds block counts.
- **THEN** the card shows title and "B Blöcke" (plus cached scene
  and costume counts when present) with the chevron affordance.

#### Scenario: Optimistic overlay card
- **WHEN** a season create is acknowledged and the overlay renders.
- **THEN** the overlay appears as a card with "Just created —
  syncing…" (or the stale warning after retry exhaustion) and the
  existing widget keys.

#### Scenario: The overview is reachable from the scope picker
- **WHEN** the user taps the season scope chip and then the
  season-management entry.
- **THEN** the seasons overview pushes on the active destination's
  nested navigator and behaves exactly as it did as a tab root.
