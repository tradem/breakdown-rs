# flutter-reports-screen Specification

## Purpose
Defines the day-context reporting surface of the Flutter client: the
on-screen Soll-Ist report (planned vs actual scene shoots with
moved/missing/skipped/reshot flags and the day's finality from
`wrapped_at`) rendered exclusively from the JSON report read DTOs, and
the three per-day PDF reports (dispo, shoot-day, planned-vs-actual)
fetched through the pinned-CA generated client, streamed to a temp
file, previewed in-app (FOSS renderer) and shared via the platform
sheet — all locally pre-gated by the client-side AUTHZ-GATE.
## Requirements
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

- **One bounded streaming model (landed):** the generated PDF methods
  (`dispoReportPdf({id, cancelToken, headers, extra, validateStatus,
  onSendProgress, onReceiveProgress})` — `Future<Response<void>>`) accept no
  `Options` parameter, so `ResponseType.stream` cannot be passed per call.
  The contract is: a **path-keyed interceptor** on the pinned-CA Dio (`lib/src
  /network/pdf_streaming_interceptor.dart`) sets `responseType =
  ResponseType.stream` for `/v1/shooting-days/*/report/*.pdf`; the repository
  consumes `response.data` as a dio `ResponseBody` stream and writes each
  chunk straight to the cache/temp file while counting bytes; the call
  carries an explicit `CancelToken` so the transfer is cancellable at any
  point. `PDF_MAX_BYTES` (default 25 MB) is enforced **during** streaming —
  the moment the counter exceeds the cap the token is cancelled and the
  partial temp file is deleted, so **no partial file remains after the
  failure** (earlier chunks may have been written before the abort; the
  deleted file is the requirement, not zero writes). No full document is
  ever resident in memory and no unbounded buffering occurs — asserted by a
  unit test that streams an oversized body and expects the abort plus an
  empty temp directory.
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
