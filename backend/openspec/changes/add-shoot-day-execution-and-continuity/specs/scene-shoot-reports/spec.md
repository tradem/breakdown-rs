<!--
  Authors: Tobias Rademacher (@tradem) — domain stakeholder & spec author
           glm-5.2 (neuralwatt) — coding agent / co-author
  Note: OpenSpec does not natively track authorship; this header is a manual addition.
-->

## ADDED Requirements

### Requirement: Three shoot-day reports compose from one projection

The system SHALL expose three read-side reports, all derived from `projection_scene_shoot` (joined with `projection_scene`, `projection_shooting_day`, `projection_photo` as needed). No separate write aggregate SHALL exist for reports.

1. **Dispo (planned / Soll)** — the planned preparation report for a `ShootingDay`: scenes ordered by `planned_order`, including scene number, script_day, location/mood, assigned characters and their costumes.
2. **Shoot Day (actual / Ist)** — the execution record: scenes ordered by `actual_order NULLS LAST`, including `start_dt`/`end_dt`, status, notes (current bodies), and continuity photo references.
3. **Soll-Ist-Vergleich (planned vs actual diff)** — a computed diff: for each planned scene, its planned vs actual position, plus flags for `moved`, `missing` (planned but no `SceneShoot` with execution data), `skipped`, and `reshot-candidate` (same scene appearing in another `SceneShoot` pair, on another day).

#### Scenario: Dispo lists planned scenes in planned order
- **WHEN** the Dispo report is requested for `ShootingDay D`
- **THEN** the system SHALL return the day's `SceneShoot`s ordered by `planned_order ASC`, each enriched with scene + costume read-model data

#### Scenario: Shoot Day lists executed scenes in actual order
- **WHEN** the Shoot Day report is requested for `ShootingDay D`
- **THEN** the system SHALL return the day's `SceneShoot`s ordered by `actual_order ASC NULLS LAST`, each with `start_dt`/`end_dt`, status, notes, and continuity photo references

#### Scenario: Soll-Ist diff flags a moved scene
- **WHEN** a scene's `planned_order` ranks it 1st but its `actual_order` ranks it 3rd
- **THEN** the Soll-Ist report SHALL flag that scene as `moved` with both positions

#### Scenario: Soll-Ist diff flags a missing scene
- **WHEN** a scene is planned (`planned_order` set) but has no execution data (`actual_order = None` and `start_dt = None` and status ≠ Shot)
- **THEN** the report SHALL flag that scene as `missing`

#### Scenario: Soll-Ist diff flags a reshoot candidate informatively
- **WHEN** the same `scene_id` has a `Shot` `SceneShoot` on another `ShootingDay`
- **THEN** the report SHALL include an informational `reshot-candidate` flag (not an error, since reshoots are legitimate)

### Requirement: Soll-Ist report finality is gated by ShootingDayWrapped

The Soll-Ist-Vergleich report SHALL read the `wrapped_at` state of the queried `ShootingDay` from `projection_shooting_day` and SHALL mark itself `final` when `wrapped_at IS NOT NULL` and `preliminary` otherwise. No write operation is needed to compute finality.

#### Scenario: Final report after wrap
- **WHEN** the Soll-Ist report is requested for a wrapped `ShootingDay`
- **THEN** the report payload SHALL include `"final": true`

#### Scenario: Preliminary report before wrap
- **WHEN** the Soll-Ist report is requested for an unwrapped `ShootingDay`
- **THEN** the report payload SHALL include `"final": false`

### Requirement: Report API endpoints

The system SHALL expose the three reports via HTTP:
- `GET /shooting-days/{id}/report/dispo`
- `GET /shooting-days/{id}/report/shoot-day`
- `GET /shooting-days/{id}/report/soll-ist`

All three SHALL be authorisation-checked against the season/block membership of the day's parent episode (handler-internal or middleware-enforced per the photo-authz pattern).

#### Scenario: Authorised report fetch succeeds
- **WHEN** an authorised member of the day's block requests a report
- **THEN** the API SHALL return `200` with the report payload

#### Scenario: Non-member is denied
- **WHEN** a non-member requests a report
- **THEN** the API SHALL return `403`
