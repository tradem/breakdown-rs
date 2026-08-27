<!--
  Authors: Tobias Rademacher (@tradem) — domain stakeholder & spec author
           glm-5.2 (neuralwatt) — coding agent / co-author
-->

## ADDED Requirements

### Requirement: Renderer-neutral reporting module in core

The system SHALL define a pure module `crates/core/src/reporting/` owning renderer-neutral
types: `ReportKind` (`Dispo | ShootDay | PlannedVsActual`), a `ReportLocale` newtype over
a BCP-47 allowlist (v1 = `de-DE`), a `RenderPresentationContext` carrying locale + IANA
time zone + template version, a `ReportRenderRequest` holding pure report data and
presentation context, `ReportBytes` (PDF bytes + page count + content type + safe response
metadata), a `ReportRenderer` trait, and a typed `ReportRenderError`. The `ReportRenderRequest`
SHALL NOT carry a database pool, Typst value, Axum type, OpenDAL operator, filesystem path,
or provider credential. `core` SHALL gain no dependency on Typst, ICU4X, Fluent, OpenDAL,
`sqlx`, or Axum.

#### Scenario: Port is renderer-neutral
- **WHEN** a caller invokes `ReportRenderer::render` with a `ReportRenderRequest`
- **THEN** it passes only pure report data + presentation context
- **AND** the concrete engine (Typst, or a fallback CLI worker) is an infra adapter detail

#### Scenario: Renderer never panics for invalid data
- **WHEN** the renderer receives malformed or out-of-bounds report data
- **THEN** it returns a typed `ReportRenderError` variant
- **AND** it does not panic

#### Scenario: core boundary stays clean
- **WHEN** `cargo test -p architecture_tests` and `cargo deny check bans` run
- **THEN** `crates/core` has no dependency on Typst / ICU4X / Fluent / OpenDAL / sqlx / Axum

### Requirement: In-process Typst adapter with a restricted virtual filesystem

The system SHALL implement a `TypstReportRenderer` in `crates/infra` that compiles trusted
static Typst templates with the same pinned release of the Apache-2.0 `typst` and `typst-pdf`
crates, upgraded only in lockstep and only after report regression tests pass. The adapter
SHALL own a restricted `World`/virtual filesystem in which package lookup, arbitrary host
filesystem access, and network retrieval are **disabled**. Report values SHALL be serialized
to an in-memory `report.json` exposed as a virtual file; a template SHALL NOT be built by
concatenating report values into `.typ` source. Host font fallback SHALL be disabled; a
minimal, pinned, licence-reviewed Latin font bundle SHALL be packaged from the first release.

#### Scenario: Trusted static template boundary
- **WHEN** a report is rendered
- **THEN** the template source is a compile-time-embedded static asset
- **AND** report values flow only through an in-memory `report.json` virtual file
- **AND** no report value is concatenated into `.typ` source

#### Scenario: Denied host/package/network access
- **WHEN** a template or an injected value attempts to read the host filesystem, resolve a
  package, or open a network connection
- **THEN** the compilation fails with a `CompilerFailure` / `AssetRejected` error
- **AND** no host path, package, or URL is resolved

#### Scenario: Lockstep pinning
- **WHEN** `typst` or `typst-pdf` is upgraded
- **THEN** both crates move together to the same pinned release
- **AND** the upgrade is gated on the report regression / golden test suite passing

#### Scenario: Deterministic font output
- **WHEN** the same input is rendered in CI and in the production image
- **THEN** the page layout is identical (byte-identical or golden page count + content)
- **AND** host font fallback is disabled

### Requirement: de-DE locale layer via ICU4X + Fluent

The system SHALL support `de-DE` as the first locale, selected from an allowlist (never a
template path). Human-readable labels SHALL come from `fluent-bundle`; decimal and calendar
formatting SHALL use ICU4X components in the infra adapter. Timestamps SHALL be converted
with an explicit configured (deployment-time, default `Europe/Berlin`) or per-request
`X-Report-Timezone` IANA time zone before formatting. Locale and
time zone SHALL NOT be conflated; the process host's locale and time zone SHALL never be
consulted. Missing optional values SHALL render as an em dash; an empty row set SHALL render
a valid report with the localized "Keine Daten vorhanden" empty state; empty notes/photo
lists SHALL render their localized empty state; the `PlannedVsActual.final` flag (from
`wrapped_at`) SHALL be rendered as a localized final/preliminary state. CJK and RTL are not
first-release supported.

#### Scenario: Explicit locale and time zone
- **WHEN** a report is rendered for `de-DE`
- **THEN** labels come from the `de-DE.ftl` Fluent catalog
- **AND** decimals/dates use ICU4X formatted with the explicit IANA time zone
- **AND** the host locale and time zone are never read

#### Scenario: Missing optional values
- **WHEN** a report field is absent
- **THEN** it renders as a localized em dash
- **AND** the report remains valid

#### Scenario: Empty data is defined behavior
- **WHEN** a report has no rows (and/or empty notes/photo lists)
- **THEN** it renders a valid report with the localized "Keine Daten vorhanden" empty state

#### Scenario: Final state preserved
- **WHEN** `PlannedVsActual.final` is true (from `wrapped_at`)
- **THEN** the report renders the localized final/preliminary state indicator

### Requirement: Per-request time zone override is display-only and security-bounded

The system MAY accept a per-request `X-Report-Timezone` header that overrides the
configured default for a single render. The configured default is read once at boot
from the `REPORT_DEFAULT_TIMEZONE` environment variable (default `Europe/Berlin`) —
it is a deployment-time setting, not a code constant and not changeable per-request
at runtime. The header value SHALL influence **display
formatting only** (TZ conversion before rendering); it SHALL NOT affect authorization,
filesystem paths, SQL, storage keys, Typst values, response headers, or any security
boundary. The value SHALL be validated against the IANA time-zone database allowlist;
an unknown or malformed value SHALL be rejected with HTTP `400` (mapped to a typed
`ReportRenderError`). The system MUST be covered by tests and fuzzing asserting that a
malicious, oversized, or unknown `X-Report-Timezone` value cannot crash rendering or
escape the locale layer into Typst source, filesystem access, or network access.

#### Scenario: Per-request override formats only
- **WHEN** a request supplies a valid `X-Report-Timezone` (e.g. `Europe/Berlin`)
- **THEN** timestamps are formatted in that zone for that render only
- **AND** authorization, SQL, storage keys, and Typst source are unaffected
- **AND** the boot-read `REPORT_DEFAULT_TIMEZONE` (default `Europe/Berlin`) applies when the
  header is absent

#### Scenario: Unknown time zone is rejected
- **WHEN** a request supplies a value not in the IANA time-zone allowlist (e.g.
  `../etc/passwd`, an oversized string, or a syntactically bogus name)
- **THEN** the request is rejected with HTTP `400`
- **AND** no rendering or filesystem/network/Typst access occurs

#### Scenario: Fuzz / malicious input cannot escape
- **WHEN** a fuzz corpus of malformed/oversized/injection-style TZ header values is
  run against the locale layer
- **THEN** every case is rejected without crashing
- **AND** no value reaches Typst source, host FS, or network retrieval

### Requirement: Bounded whole-document rendering

The system SHALL render PDFs as whole documents in memory (not streaming) and SHALL check
the final page count, rejecting any document over 50 pages with a `PageLimitExceeded` error.
Row count, serialized JSON size, individual string length, injected asset count/size, and
output byte size SHALL receive configured bounds enforced before or during rendering; an
over-limit input SHALL raise `InputBoundsExceeded` and SHALL NOT be partially returned.
Compilation SHALL run via `tokio::task::spawn_blocking` behind a process-wide semaphore
with a configured concurrency limit shared by the HTTP path and the future backup worker.
A wall-clock deadline SHALL bound caller waiting; the semaphore SHALL remain held until the
blocking compilation actually ends. The renderer SHALL never return partial PDF bytes.

#### Scenario: Page limit enforced
- **WHEN** a rendered document would exceed 50 pages
- **THEN** the renderer returns `PageLimitExceeded { max: 50, actual }`
- **AND** no partial PDF bytes are returned

#### Scenario: Input bounds enforced
- **WHEN** row count / JSON size / string length / asset count or size exceed configured bounds
- **THEN** the renderer returns `InputBoundsExceeded`
- **AND** rendering does not proceed

#### Scenario: Shared concurrency budget
- **WHEN** concurrent renders (HTTP and, later, backup) exceed the semaphore limit
- **THEN** they queue against the same process-wide budget
- **AND** no path can starve the other path's budget

#### Scenario: Deadline enforces caller waiting
- **WHEN** a render exceeds the configured wall-clock deadline
- **THEN** the caller receives `RenderTimeout`
- **AND** the semaphore is held until the blocking compilation actually ends