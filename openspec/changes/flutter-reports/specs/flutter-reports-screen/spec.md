<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# flutter-reports-screen Specification (delta)

## ADDED Requirements

### Requirement: Contract-Gated Reporting Surface
The reports feature SHALL be implemented only against routes the
generated Dart client carries: the on-screen Soll-Ist report from the
JSON report routes, and the PDF reports from the three PDF routes
WITH the day id expressible through the client. Both landed in the
checked-in contract (backend issues #333/#334, PRs #344/#349) — the
client dispatches via the generated per-day methods only (no `Dio`
string interpolation of the route) and consumes the generated report
DTOs (no retyped DTOs, no substitute data sources).

#### Scenario: PDF contract landed
- **WHEN** the spec defines `{id}` on the three PDF routes and the
  client is regenerated.
- **THEN** the PDF cards dispatch via the generated per-day methods
  only (no `Dio` string interpolation of the route) — the landed
  state since backend issues #333/#334.

### Requirement: Soll-Ist On-Screen Report From the Read Model
The report screen SHALL render the day's Soll-Ist report (planned vs
actual scene shoots with moved/missing/skipped/reshot flags and the
day's finality from `wrapped_at`) exclusively from the report read
DTO, following the reference pattern (`asyncValue.when`, error copy
keyed on `code`, theme-token styling, {light,dark} ×
{android,macos} goldens). No client-side recomputation of flags or
finality SHALL occur; unknown status/flag values from a future
backend SHALL strict-reject the DTO with a stable code.

- **Error-code contract (stable, testable):** the strict parser emits
  `report.unknown_status` (an unrecognized flag/status string) and
  `report.unknown_shape` (a structurally unexpected DTO). Transport
  failures and HTTP errors carry no backend problem `code`, so they
  are normalized to `transport.*` (`transport.tls` for a pinning/TLS
  failure, `transport.network` for connectivity/DNS,
  `transport.timeout`) and, for a code-less HTTP error, to
  `http.<status>`. Localization and tests key on exactly these codes;
  no path renders raw exception text or a server `detail`.

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
pinned-CA generated client, streamed and a visible indeterminate/linear
progress affordance while running; the document SHALL preview in-app
(FOSS viewer) and be shareable/saveable via the platform sheet to a
user-visible file name. PDF bytes SHALL never persist into Drift.

- **One bounded streaming model (verified against the generated
  client):** the generated PDF methods are
  `Future<Response<void>> dispoReportPdf({cancelToken, headers, extra,
  validateStatus, onSendProgress, onReceiveProgress})` — they accept no
  `Options` parameter, so `ResponseType.stream` cannot be passed per
  call, and the current repository discards the body entirely
  (`Result<void>`). The contract is therefore: a **path-keyed
  interceptor** on the pinned-CA Dio sets `responseType =
  ResponseType.stream` for `/v1/shooting-days/*/report/*.pdf`; the
  repository consumes `response.data` as a dio `ResponseBody` stream and
  writes each chunk straight to the cache/temp file while counting
  bytes; the call carries an explicit `CancelToken` so the transfer is
  cancellable at any point. `PDF_MAX_BYTES` (default 25 MB) is enforced
  **during** streaming — the moment the counter exceeds the cap the
  token is cancelled, the partial temp file is deleted, and the card
  returns to idle with the localized `pdf.too_large` copy. No full
  document is ever resident in memory and no unbounded buffering occurs
  — asserted by a unit test that streams an oversized body and expects
  the abort plus zero file writes.
- A role-gated user denial SHALL be pre-empted client-side with
  `// AUTHZ-GATE:`-annotated capability checks and the localized 403
  narrative before any network call. The pre-check is **local and
  non-fetching**: `currentMembershipProvider` may be `AsyncLoading`,
  `AsyncError`, or carry an unknown capability string, and in all three
  cases the PDF action is disabled/refused locally — the action never
  triggers a membership fetch, and a denied action issues zero report
  requests.

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
