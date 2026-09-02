<!--
  Authors: Tobias Rademacher (@tradem) — domain stakeholder & spec author
           glm-5.2 (neuralwatt) — coding agent / co-author
-->

## Purpose

Defines the three read-side shoot-day reports — Dispo (planned / Soll), Shoot Day (actual / Ist), and Soll-Ist-Vergleich (planned-vs-actual diff) — derived from `projection_scene_shoot`, their finality gating by `ShootingDayWrapped`, and the HTTP endpoints that serve them.
## Requirements
### Requirement: PDF delivery variant for each report kind

The system SHALL add an explicit PDF delivery variant for each of the three existing
shoot-day report kinds (Dispo, Shoot Day, Planned-vs-Actual) under the active ADR-021
API prefix, for example `GET /v1/shooting-days/{id}/report/{dispo|shoot-day|planned-vs-actual}.pdf`.
The existing JSON report routes SHALL remain unchanged during the migration and MAY be
deprecated separately under ADR-021 versioning. A PDF handler SHALL resolve
shooting_day → episode → block → season, execute the season-membership policy check under
a literal `// AUTHZ-GATE:` comment, and fail closed on lookup or policy errors BEFORE
querying report rows or rendering the PDF. Successful PDF responses SHALL use
`application/pdf`, a server-generated and sanitized `Content-Disposition` filename, and
`Cache-Control: private, no-store`. A render error SHALL be mapped from its typed
`ReportRenderError` port error to a structured API error; a handler SHALL never panic and
SHALL never return partial PDF bytes. User input SHALL NOT become a response header or a
storage path. Rendering reads a projection snapshot only and dispatches no command and
mutates no aggregate.

#### Scenario: PDF route is additive to JSON
- **WHEN** the `.pdf` delivery variant is added for a report kind
- **THEN** the existing JSON route for that kind continues to work unchanged
- **AND** deprecation of JSON is handled separately under ADR-021

#### Scenario: Authorized member can fetch a PDF
- **WHEN** an authenticated active season member requests a report PDF
- **THEN** the handler resolves the season chain, succeeds at the `// AUTHZ-GATE:` check,
  queries the rows, renders the PDF, and returns `200 application/pdf`

#### Scenario: Non-member is denied at the AUTHZ-GATE
- **WHEN** an authenticated non-member requests a report PDF
- **THEN** the handler returns `403` and does NOT query report rows or render the PDF

#### Scenario: Lookup error is fail-closed
- **WHEN** the shooting-day → season chain cannot be resolved
- **THEN** the handler returns an error and does NOT render the PDF

#### Scenario: Safe response headers
- **WHEN** a PDF is returned
- **THEN** the `Content-Type` is `application/pdf`
- **AND** `Content-Disposition` carries a server-generated, sanitized filename
- **AND** `Cache-Control: private, no-store` is set
- **AND** user input is reflected in no header and no storage path

#### Scenario: Render error never returns partial bytes
- **WHEN** rendering fails (bounds, page limit, compiler failure, timeout)
- **THEN** the handler maps the typed `ReportRenderError` to a structured API error
- **AND** returns no partial PDF bytes and does not panic

#### Scenario: Rendering is read-side only
- **WHEN** a PDF is rendered and returned
- **THEN** no SierraDB command is dispatched, no aggregate is mutated, and no domain event is emitted

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

