<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# flutter-scene-shoots-screen Specification (delta)

## ADDED Requirements

### Requirement: Contract-Gated Implementation
The scene-shoot execution screens SHALL be implemented only against
routes present in the generated Dart client (regenerated from
`backend/openapi.yaml`). While the scene-shoot / continuity-photo /
wrap route family is absent from the checked-in OpenAPI contract, the
client SHALL NOT ship improvised calls, retyped DTOs, or substitute
routes for this surface.

#### Scenario: Contract lands
- **WHEN** the backend re-export includes the scene-shoot route
  family and the client is regenerated.
- **THEN** this change's implementation tasks unblock and consume the
  generated DTOs exclusively.

### Requirement: Day Board Follows the Reference Pattern
When unblocked, the day board SHALL render the day's scene shoots in
planned order with the Ist state (started/finished/skipped, actual
order, day finality from `wrapped_at`) taken only from the read
model, and SHALL dispatch plan/replan/start/actual-order/finish/
skip/notes commands with the ids and `version` echoed from the acted-on
read DTOs, the optimistic-after-2xx discipline, and bounded-retry
reconciliation.

#### Scenario: Finish a scene shoot
- **WHEN** the user finishes a started shoot (command 2xx).
- **THEN** the row optimistically carries the finished state and
  reconciles via the day-board projection refetch; conflicts (409)
  render "changed elsewhere — refresh" copy keyed on `code` without
  auto-retry.

#### Scenario: Wrapped day is immutable for execution
- **WHEN** the day is wrapped (`wrapped_at` present).
- **THEN** mutation affordances are absent or disabled with finality
  copy; the render remains possible read-only.

#### Scenario: Wrap confirm dialog
- **WHEN** the user taps wrap.
- **THEN** a confirmation names the consequence and the absence of an
  undo before the command dispatches (no dark pattern).

### Requirement: Continuity Photos Bound to Scene Shoots
When unblocked, continuity capture SHALL reuse the Phase 2 capture
pipeline (point-of-use permission rationale, isolate prepare,
progress-indicated upload) against the continuity-photo route with
the scene-shoot context and an optional costume link picked from the
season's costume read DTOs; every upload/list/unlink call SHALL be
preceded by an `// AUTHZ-GATE:`-annotated capability check
(`upload_continuity_photos` or the season photo policy mirror) with a
localized 403 narrative issued before any network call.

#### Scenario: Continuity upload denied
- **WHEN** a user without the continuity capability attempts capture.
- **THEN** the client short-circuits with the 403 narrative; no
  network request is issued (provable with a call-count-zero fake).

#### Scenario: Thumbnail appears after projector lag
- **WHEN** a continuity upload is acknowledged and variants reach
  `Ready`.
- **THEN** the thumbnail renders in the shoot's continuity strip
  within the bounded watch; a `Failed` variant shows the non-destructive
  explanation and capture-again affordance.

#### Scenario: Watch expires while a variant is still Processing
- **WHEN** the bounded watch budget is exhausted and a variant is
  still `Processing`.
- **THEN** polling stops (no further requests for that pass), the row
  renders a neutral "still processing" state with the recovery
  affordances (refresh / capture again), and the state is
  distinguishable from `Ready` and `Failed` in both the widget and
  Gherkin coverage.
