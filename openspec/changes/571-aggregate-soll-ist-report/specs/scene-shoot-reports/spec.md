<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

## ADDED Requirements

### Requirement: Season-scoped aggregated Soll-Ist report

The system SHALL expose `GET /v1/seasons/{id}/report/soll-ist` returning an
`AggregateSollIstReport` aggregating the Soll-Ist rows of every non-archived
shooting day of the season. Each row SHALL represent one planned execution
(scene × shooting day) within the season and SHALL carry the day's id and
label. Rows SHALL be ordered by the shooting day's order key, then by
planned order. The handler SHALL resolve the season's membership policy
(`has_active_costume_role_in_season`) inside the handler body under a
`// AUTHZ-GATE:` comment before querying report rows, fail closed on lookup
or policy errors, and answer an unknown season id with the registered
`season.not-found` problem code. A season with zero shooting days SHALL
answer `200` with an empty row list and day counts of zero — an empty report,
not an error.

#### Scenario: member sees the season aggregate

- **WHEN** an authenticated active season member requests the season report
- **THEN** the handler succeeds at the `// AUTHZ-GATE:` check and returns
  `200` with the union of day rows, the season's non-archived day counts,
  and the server-derived finality flag

#### Scenario: any unwrapped day keeps the report provisional

- **WHEN** the season has at least one non-archived shooting day without
  `wrapped_at`
- **THEN** `is_final` is `false`, regardless of every other day's state

#### Scenario: all wrapped days make the report final

- **WHEN** the season has at least one non-archived shooting day and every
  one of them has `wrapped_at` set
- **THEN** `is_final` is `true`

#### Scenario: season with zero shooting days

- **WHEN** the season exists but has no non-archived shooting day
- **THEN** the response is `200` with `rows: []`,
  `total_shooting_days == 0`, `wrapped_shooting_days == 0`, and
  `is_final == false`

#### Scenario: non-member denied

- **WHEN** an authenticated non-member requests the season report
- **THEN** the handler returns `403` and does not query report rows

#### Scenario: unknown season id

- **WHEN** the season id does not resolve to a season projection
- **THEN** the handler returns `404` with the `season.not-found` problem code

### Requirement: Episode-scoped aggregated Soll-Ist report

The system SHALL expose `GET /v1/episodes/{id}/report/soll-ist` with the
same row semantics, finality rule, zero-day answer, gate, and failure modes
as the season-scoped report, scoped to the shooting days of one episode. The
handler SHALL resolve episode → block → season and apply the same
`has_active_costume_role_in_season` policy under a `// AUTHZ-GATE:` comment;
an unknown episode id SHALL answer the registered `episode.not-found`
problem code.

#### Scenario: episode aggregate mirrors season semantics

- **WHEN** an authorized member requests the episode report for an episode
  with wrapped and unwrapped days
- **THEN** rows are limited to that episode's shooting days and the
  finality rule is identical to the season-scoped rule

#### Scenario: unknown episode id

- **WHEN** the episode id does not resolve to an episode projection
- **THEN** the handler returns `404` with the `episode.not-found` problem code

### Requirement: PDF delivery variant for the aggregated reports

The system SHALL expose `.pdf` delivery variants of both aggregated reports —
`GET /v1/seasons/{id}/report/soll-ist.pdf` and
`GET /v1/episodes/{id}/report/soll-ist.pdf` — for the new report kinds
`season-soll-ist` and `episode-soll-ist`. The same authorizations and
fail-closed behavior as the JSON routes SHALL apply; the day-scoped PDF
packaging rules (content type, server-generated sanitized filename, no
partial bytes on render failure) apply unchanged.

#### Scenario: aggregate PDFs are additive

- **WHEN** the `.pdf` twins are added for the two aggregate scopes
- **THEN** the JSON routes, the day-scoped routes, and the day-scoped PDFs
  continue to work unchanged
