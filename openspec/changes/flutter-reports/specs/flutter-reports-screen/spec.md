<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# flutter-reports-screen Specification (delta)

## ADDED Requirements

### Requirement: Contract-Gated Reporting Surface
The reports feature SHALL be implemented only against routes the
generated Dart client carries: the on-screen Soll-Ist report from the
JSON report routes, and the PDF reports from the three PDF routes
WITH the day id expressible through the client. Until the backend
defines the PDF `{id}` parameter (tracked defect) and exports the
JSON report routes, the client SHALL NOT ship hand-built URLs,
retyped report DTOs, or substitute data sources for this surface.

#### Scenario: PDF contract lands
- **WHEN** the spec defines `{id}` on the three PDF routes and the
  client is regenerated.
- **THEN** the PDF cards dispatch via the generated per-day methods
  only (no `Dio` string interpolation of the route).

### Requirement: Soll-Ist On-Screen Report From the Read Model
The report screen SHALL render the day's Soll-Ist report (planned vs
actual scene shoots with moved/missing/skipped/reshot flags and the
day's finality from `wrapped_at`) exclusively from the report read
DTO, following the reference pattern (`asyncValue.when`, error copy
keyed on `code`, theme-token styling, {light,dark} ×
{android,macos} goldens). No client-side recomputation of flags or
finality SHALL occur; unknown status/flag values from a future
backend SHALL strict-reject the DTO with a stable code.

#### Scenario: Wrapped day report
- **WHEN** the user opens the report of a wrapped day.
- **THEN** the finality banner renders and every row carries the
  server-derived flags verbatim.

#### Scenario: Unknown status strict-rejects
- **WHEN** the report DTO contains a flag/status string the client
  does not know.
- **THEN** the screen renders the standard error state keyed on the
  stable code instead of guessing a meaning (no guessed rendering).

### Requirement: PDF Fetch, Preview, Share
Fetching a PDF SHALL occur only on explicit user action, through the
pinned-CA generated client, streamed with bounded in-memory buffering
and a visible indeterminate/linear progress affordance while running;
the document SHALL preview in-app (FOSS viewer) and be shareable/
saveable via the platform sheet to a user-visible file name. PDF
bytes SHALL never persist into Drift. A role-gated user denial SHALL
be pre-empted client-side with `// AUTHZ-GATE:`-annotated capability
checks and the localized 403 narrative before any network call.

#### Scenario: Fetch and share
- **WHEN** the user taps a PDF card and confirms share.
- **THEN** the fetch shows progress, the preview opens, and the
  shared file lands under a `<day>-<report>.pdf` name; no part of
  the blob enters the Drift cache.

#### Scenario: Fetch failure
- **WHEN** the PDF fetch returns an error (transport or 4xx/5xx).
- **THEN** the card returns to idle with copy keyed on the problem
  `code`; nothing is cached and no partial file is left in the
  documents directory (temporaries cleaned).
