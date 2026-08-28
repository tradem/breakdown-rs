<!--
  Authors: Tobias Rademacher (@tradem) — domain stakeholder & spec author
           glm-5.2 (neuralwatt) — coding agent / co-author
-->

## ADDED Requirements

### Requirement: ShootingDayWrapped triggers report archival

When a `ShootingDayWrapped` event is projected (the day is "closed for planning"), a
projector reaction SHALL enqueue a trusted, season-scoped report-archival job for that
day's reports. The trigger SHALL be idempotent via the report-archival dedup key. The
trigger is a service job scoped to an explicit season and configured destination and
SHALL NOT be a public authorization bypass; HTTP PDF routes SHALL retain their
`AUTHZ-GATE` handler-internal authorization. The trigger SHALL dispatch no SierraDB
command, mutate no `ShootingDay` aggregate or event, and emit no domain event of its
own.

#### Scenario: Wrap enqueues an archival job
- **WHEN** a `ShootingDayWrapped` event is projected
- **THEN** a report-archival job is enqueued for that day's reports
- **AND** the enqueue is idempotent across redeliveries

#### Scenario: Trigger is not an authz bypass
- **WHEN** the wrap-triggered archival job runs
- **THEN** it enforces season-scoped authorization internally against a configured
  destination
- **AND** HTTP PDF routes retain their `AUTHZ-GATE` check unchanged

#### Scenario: Aggregate is unchanged
- **WHEN** the wrap reaction fires
- **THEN** no `ShootingDay` command is dispatched and no `ShootingDay` event is emitted
- **AND** the `ShootingDayWrapped` event semantics (day-completion → report-finalisation)
  are preserved unchanged
