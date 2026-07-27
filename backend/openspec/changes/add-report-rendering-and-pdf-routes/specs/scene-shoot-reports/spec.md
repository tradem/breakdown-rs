<!--
  Authors: Tobias Rademacher (@tradem) — domain stakeholder & spec author
           glm-5.2 (neuralwatt) — coding agent / co-author
-->

## MODIFIED Requirements

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
