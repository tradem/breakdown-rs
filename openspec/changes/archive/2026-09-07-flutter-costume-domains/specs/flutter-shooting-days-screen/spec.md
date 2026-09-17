<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# flutter-shooting-days-screen Specification (delta)

## ADDED Requirements

### Requirement: Episode-Scoped Shooting-Day Management
The shooting-days screen SHALL list an episode's `ShootingDayView`
rows ordered by `order_key` ascending and support create
(`POST /v1/episodes/{episode_id}/shooting-days` — `order_key` derived
with the shared append rule, `source: Manual`, optional label/date),
update via the one-of `UpdateShootingDayRequest` (reorder / reschedule
/ rename, each a single-intent PATCH with version echo; `date: null`
is the explicit unschedule), and archive. All commands follow the
reference pattern (session AUTHZ-GATE, Result repository, optimistic
after 2xx, bounded reconciliation, error copy keyed on `code`). The
Soll/Ist execution UI is out of scope: the routes are absent from the
checked-in OpenAPI contract (documented blocker).

#### Scenario: Creating a shooting day
- **WHEN** the user creates a day (label "1. Tag", date picked) in the
  episode context.
- **THEN** the POST carries the derived append `order_key` and
  `Manual` source; the overlay row reconciles like the seasons
  reference.

#### Scenario: Rescheduling and unscheduling
- **WHEN** the user sets a new date, then clears it.
- **THEN** each action is a separate single-intent PATCH (`date: null`
  for the clear) with the version echo; the row updates optimistically
  after each 2xx; conflicts (409) render keyed on `code`.

#### Scenario: ordered list fidelity
- **WHEN** days exist with lexicographic `order_key`s.
- **THEN** the rendering uses the server order exactly (no client
  re-sort); a reorder PATCH issues a single new key from the read
  model's neighbor keys.

### Requirement: Scene-Day Scheduling From the Scene Side
The scene detail SHALL render the scene's scheduled shooting days
(from `SceneView.shooting_day_ids`, resolved via the episode's day
projection — read-DTO join only) and offer schedule (picker over the
parent episode's not-yet-archived days; `POST /v1/scenes/{id}/
shooting-days` with `shooting_day_id` from the picked DTO and the
scene `version` from the acted-on `SceneView`) and unschedule
(DELETE with ids from the read DTOs), both with the optimistic-after-
2xx discipline on the scene row's id list.

#### Scenario: Scheduling a scene onto a day
- **WHEN** the user picks a shooting day in the scene's day picker.
- **THEN** the command carries the day id from the read DTO and the
  scene version; after 2xx the day list optimistically contains the
  id and reconciles via the scene projection refetch.

#### Scenario: Unscheduling with conflict
- **WHEN** the DELETE returns 409 (scene changed elsewhere).
- **THEN** the local edit rolls back, conflict copy renders keyed on
  `code`; no automatic version bump re-dispatch.

### Requirement: Adaptive Scheduling UX
The day list SHALL stay correct on both platforms and themes: compact
date/label calendar-row layout on Android; pointer/keyboard traversal
and Escape-closable editors on macOS; goldens in {light, dark} ×
{android, macos}; date pickers localize through the Material date
utilities (no hand-rolled date math for locale).

#### Scenario: Dark-mode day list golden
- **WHEN** golden tests run for the day list in all four variants.
- **THEN** all variants match the committed goldens.
