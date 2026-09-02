<!--
  Authors: Tobias Rademacher (@tradem) — domain stakeholder & spec author
           deepseek-v4-flash (opencode-go) — coding agent / co-author

           grok-4.5 (opencode-go) — coding agent / co-author
  Synced from change: add-report-archival-backup
-->

# Shooting Day Lifecycle

## Purpose

Describes the lifecycle events and state transitions of a shooting day
aggregate, including wrap (closure for planning) and the projector reactions
that follow.
## Requirements
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

### Requirement: ShootingDay gains a Wrap command and Wrapped event

The `ShootingDay` aggregate SHALL accept a `WrapShootingDay` command that emits a terminal `ShootingDayWrapped { id, version, wrapped_at }` event. The aggregate SHALL carry `wrapped_at: Option<DateTime<Utc>>` state, `None` until wrapped. Wrapping SHALL be idempotent: re-dispatching `WrapShootingDay` on an already-wrapped aggregate SHALL be a no-op (return current version, emit nothing). A wrapped `ShootingDay` SHALL remain unwrappable for archive purposes; wrapping SHALL NOT prevent archive.

#### Scenario: Wrapping an open shooting day
- **WHEN** `WrapShootingDay` is dispatched on a `ShootingDay` with `wrapped_at = None`
- **THEN** the aggregate SHALL emit `ShootingDayWrapped { wrapped_at }` and set `wrapped_at`

#### Scenario: Wrap is idempotent
- **WHEN** `WrapShootingDay` is dispatched on a `ShootingDay` with `wrapped_at = Some(t)`
- **THEN** the aggregate SHALL NOT emit a new event and SHALL return the current version

### Requirement: ShootingDayWrapped finalises the Ist side for reports

Once a `ShootingDay` is wrapped, the Soll-Ist-Vergleich report for that day SHALL be considered authoritative and final: the actual-side values (`actual_order`, `start_dt`, `end_dt`, status, notes) of all `SceneShoot`s belonging to that day SHALL be read as-is at report time. Unwrapped days MAY still produce a preliminary Soll-Ist report, flagged as non-final.

#### Scenario: Wrapped day yields a final comparison
- **WHEN** the Soll-Ist report is requested for a wrapped `ShootingDay`
- **THEN** the report SHALL be marked `final` and SHALL reflect the Ist side verbatim

#### Scenario: Unwrapped day yields a preliminary comparison
- **WHEN** the Soll-Ist report is requested for a `ShootingDay` that is not wrapped
- **THEN** the report SHALL be marked `preliminary` (Ist-side may still change)

### Requirement: ShootingDay projection reflects wrapped state

`projection_shooting_day` SHALL carry `wrapped_at TIMESTAMPTZ NULL`. The `ShootingDay` projector SHALL handle `ShootingDayWrapped` by setting `wrapped_at`.

#### Scenario: Projection stores wrapped_at
- **WHEN** a `ShootingDayWrapped` event is projected
- **THEN** `projection_shooting_day.wrapped_at` SHALL be set to the event's timestamp

