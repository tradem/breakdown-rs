# flutter-seasons-home Specification

## Purpose
TBD - created by syncing change redesign-seasons-home. Update Purpose after archive.
## Requirements
### Requirement: Season Cards as Home Content
The Season tab SHALL render each projected season as a Material 3
card containing the season title (name if present, otherwise
"Season {number}"), contextual metadata (block count, and scene/
costume counts where available from the Drift read-model cache),
and a trailing chevron navigation affordance. The card tap SHALL
enter the season's detail/planning view as before. Optimistic
overlay rows SHALL render as cards in the same visual language,
preserving their existing keys (`overlay-<id>`, spinner /
`overlay-warning`) and stale-warning behavior.

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

### Requirement: Cache Metrics With Stale Indication
Season-card metadata SHALL be sourced from the Drift read-model
cache without additional network calls. When the underlying cache
entries are older than their TTL (or marked stale by existing
mechanisms), the card SHALL show a subtle stale indicator (time
reference or glossary icon) next to the metadata rather than hiding
the values (team decision 4). If no cached datastore entry exists
for a season, the metadata line is omitted — no fabricated counts.

#### Scenario: Stale cache
- **WHEN** a season's cached hierarchy entries exceed the TTL.
- **THEN** the card renders its counts plus the stale indicator
  (e.g. cloud-off icon or "Stand: vor 2 h" reference).

#### Scenario: No cached metadata
- **WHEN** a projected season has no hierarchy cache rows.
- **THEN** the card renders title and chevron without a metadata
  line and without network activity.

### Requirement: Extended FAB Primary Action
The Season tab SHALL render the create action as a
`FloatingActionButton.extended` labeled "Season erstellen"
(visible label; icon from the glossary). Its visibility SHALL keep
the AUTHZ-GATE comment and authenticated-session condition of the
current FAB ("create_season is auth-only; visibility tracks the
resolved session").

#### Scenario: FAB renders with label
- **WHEN** an authenticated user views the Season tab with or
  without seasons.
- **THEN** an extended FAB with the visible label "Season erstellen"
  renders and opens the create flow on tap.

#### Scenario: Signed-out
- **WHEN** no resolved authenticated session exists.
- **THEN** no FAB renders (unchanged gate semantics).

### Requirement: Guided Empty State
When the seasons list is empty and no fetch is failing, the Season
tab SHALL render an informative empty state: a headline, one
sentence of guidance, and two call-to-action entries — one
starting season setup (create flow; later the setup wizard), one
linking to the AI import (Mehr tab path, with its AUTHZ-GATE
denial narrative when membership is missing). The empty state's
create entry SHALL respect the same session-visibilty rule as the
FAB.

#### Scenario: First launch with no seasons
- **WHEN** a fresh authenticated user opens the Season tab and the
  projected list is empty without errors.
- **THEN** the empty state renders headline, guidance copy, and both
  CTAs (setup/import) instead of the bare 'No seasons yet' text.

#### Scenario: Import denied
- **WHEN** the user without costume-dept membership taps the import
  CTA.
- **THEN** the localized denial narrative renders (existing
  AUTHZ-GATE client check runs before any network call).

### Requirement: Loading Skeleton
While the seasons projection loads after a cold start (no cached
rows), the Season tab SHALL render a lightweight skeleton
placeholder for the list area (M3-styled, no network imagery) and
SHALL NOT show the empty state for the transient loading window.

#### Scenario: Cold start without cache
- **WHEN** the app starts with an empty Drift cache and the
  seasons fetch is in flight.
- **THEN** a skeleton list placeholder renders until data or error
  resolves (empty state does not flash).
