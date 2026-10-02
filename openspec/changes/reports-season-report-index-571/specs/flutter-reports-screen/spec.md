<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024 Breakdown RS Contributors -->
<!-- Co-authored-by: space-bunny-free (opencode-go) -->

## ADDED Requirements

### Requirement: Second Inbound Path And Single-Renderer Invariant

The day-scoped report screen SHALL remain the **only** surface in the app
that renders report content. It SHALL gain a second documented inbound path
— from the episode's report index, in addition to the day board's labelled
entry (`reports-open`) — and SHALL render identically on both paths: the
same read DTOs, the same strict parser and its `report.unknown_status` /
`report.unknown_shape` rejections, the same server-derived flags and
`final` banner from `wrapped_at`, the same PDF cards, and the same
client-side `AUTHZ-GATE`.

An index row SHALL NOT become an alternative renderer of the same data: no
report rows, flags, counts or PDF affordances may appear outside the
day-scoped report screen. A scene or an episode with no shooting day SHALL
STILL be offered no report entry at the day-scoped surface's expense — the
report-provenance empty state shipped with #549 continues to be the only
hint there, and it names a report rather than linking one.

The day-scoped report surface SHALL remain backed exclusively by the
day-scoped contract routes (`/v1/shooting-days/{id}/report/*`); this change
introduces no season-, episode- or scene-scoped report route, and the
client SHALL NOT interpolate a report route to reach one.

#### Scenario: The report renders the same from either path

- **WHEN** the user reaches a given day's report from the day board's
  entry and, for a different day, from the episode's report index
- **THEN** both render the same screen from the same read DTOs with the same
  flags, finality banner, error states and PDF cards

#### Scenario: The index never renders report content

- **WHEN** the report index screen is rendered
- **THEN** no report row, flag chip, planned/actual count or PDF card is
  rendered outside the day-scoped report screen

#### Scenario: A day-less scope still offers no report link

- **WHEN** a scene is scheduled on no shooting day
- **THEN** the report-provenance empty state is the only affordance shown
  and no season-, episode- or scene-scoped report link is offered
