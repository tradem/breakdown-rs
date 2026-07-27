<!--
  Authors: Tobias Rademacher (@tradem) — domain stakeholder & spec author
           glm-5.2 (neuralwatt) — coding agent / co-author
  Note: OpenSpec does not natively track authorship; this header is a manual addition.
  Derived from ADR-022 (In-Process Typst for PDF Reporting and Report Archival), D1–D5 + D4.
-->

## Why

The three shooting-day reports — `dispo`, `shoot-day`, and `planned-vs-actual` — are
currently read-side JSON responses backed by PostgreSQL projections. The costume
department needs **deterministic PDF output**: a shareable archival artifact with
stable pagination, `de-DE` labels and number/date formatting, and a clean
authorization boundary. PDF rendering remains a **read-side concern**: it dispatches
no SierraDB command, mutates no aggregate, and emits no domain event — it reads a
projection snapshot and renders trusted templates.

ADR-022 selects **direct in-process Typst** (`typst` + `typst-pdf`, Apache-2.0) over
every CLI/subprocess/browser/service alternative, on a weighted cost/security/
future-proof score. This change delivers the foundation agreed in ADR-022 D1–D5 and the
HTTP delivery surface in D4. The asynchronous backup worker (ADR-022 D6) is a separate,
dependent change (`add-report-archival-backup`) that consumes the renderer introduced here.

ADR-022 is explicitly **spike-gated**: three material unknowns (in-process Typst
latency/memory under concurrency, restricted-virtual-filesystem safety, and — for the
backup change — OpenDAL Google Drive idempotency) must produce evidence before the
engine decision is locked. The first two unknowns belong to *this* change. A spike
phase is therefore the first gate in `tasks.md`; a failure reverses D1 to a sandboxed
pinned Typst CLI worker.

## What Changes

- **New `core` reporting module** (`crates/core/src/reporting/`): renderer-neutral
  request/response DTOs, `ReportKind` (`Dispo | ShootDay | PlannedVsActual`), the
  supported-locale identifier, a `ReportRenderer` port returning PDF bytes + safe
  metadata, and typed `ReportRenderError` values. `core` gains **no** dependency on
  Typst, ICU4X, Fluent, OpenDAL, `sqlx`, or Axum.
- **In-process Typst adapter** (`crates/infra/src/reporting/typst.rs`): pinned,
  lockstep-upgraded `typst` + `typst-pdf`; owns a restricted `World`/virtual
  filesystem; compiles trusted static templates embedded at compile time
  (`crates/infra/templates/reports/{dispo,shoot-day,planned-vs-actual}.typ`).
  Templates read a serializer-produced in-memory `report.json`; report values are
  **never** concatenated into `.typ` source.
- **`de-DE` locale layer**: `fluent-bundle` (labels) + ICU4X
  (`icu`/`icu_decimal`/`icu_datetime`) for decimal/calendar formatting in the infra
  adapter; explicit IANA time zone conversion; host locale/time zone never consulted.
  Missing optionals render as em dash; empty row sets render a valid report with
  localized "Keine Daten vorhanden"; `final` (from `wrapped_at`) is preserved.
- **Bounded rendering**: whole-document compile via `tokio::task::spawn_blocking`
  behind a process-wide semaphore with a configured concurrency limit shared by the HTTP
  path (and future backup worker); wall-clock deadline; page limit 50 → typed
  `PageLimitExceeded`; row/JSON/string/asset/byte bounds enforced before/during render.
- **Explicit PDF routes** under the active ADR-021 API prefix, e.g.
  `/v1/shooting-days/{id}/report/{dispo|.pdf` etc.; existing JSON routes remain during
  migration. Every PDF handler retains the existing handler-internal `// AUTHZ-GATE:`
  authorization pattern (resolve day→episode→block→season; season-membership check,
  fail-closed; render data only after authorization).
- **Responses**: `application/pdf`, server-generated sanitized `Content-Disposition`
  filename, `Cache-Control: private, no-store`. Render errors map typed port errors →
  API errors; never panic; never return partial PDF bytes.
- **Pinned font set & licence review**: a minimal, pinned, licence-reviewed Latin font
  bundle is packaged from the first release; host font fallback disabled. (OFL-1.1
  families such as Noto Sans are candidates, not unreviewed implicit dependencies.)

## Capabilities

### New Capabilities
- `report-rendering`: the renderer-neutral `ReportRenderer` port + typed errors in
  `core`, the in-process Typst adapter + restricted virtual filesystem in `infra`,
  the `de-DE` locale layer (ICU4X + Fluent, explicit TZ), and bounded whole-document
  rendering (semaphore + deadline + input/page bounds).

### Modified Capabilities
- `scene-shoot-reports`: gains an explicit `.pdf` delivery variant for each of the
  three existing report kinds; existing JSON routes remain; reaffirms the
  handler-internal `AUTHZ-GATE` season-membership check and the typed render-error →
  API-error mapping (no partial PDF, no panic).

## Impact

- **Code — `crates/core`**:
  - New `reporting` module: `ReportKind`, `ReportLocale` (`de-DE`), `ReportRenderRequest`,
    `ReportBytes`/response metadata, `ReportRenderer` trait, `ReportRenderError` enum
    (`PageLimitExceeded`, `InputBoundsExceeded`, `CompilerFailure`, `RenderTimeout`,
    `LocaleUnsupported`, …). Pure; no infra deps.
- **Code — `crates/infra`**:
  - `crates/infra/src/reporting/typst.rs`: `TypstReportRenderer` (pinned `typst` +
    `typst-pdf`), restricted `World`, allowlisted virtual FS, font loading.
  - `crates/infra/src/reporting/locale.rs`: ICU4X decimal/datetime + Fluent labels,
    explicit TZ, em-dash/empty-state semantics for `de-DE`.
  - `crates/infra/src/reporting/mod.rs` + a render-bounds / semaphore runtime.
  - Trusted static templates: `crates/infra/templates/reports/{dispo,shoot-day,planned-vs-actual}.typ`
    and `crates/infra/templates/reports/i18n/de-DE.ftl`, compile-time-embedded
    (`include_str!`/`rust-embed`).
  - Reviewed font assets: `crates/infra/assets/reporting/` (font files + notices).
  - The existing `SceneShootReportRepository` is **unchanged**; the renderer consumes
    the read-port DTOs already produced for JSON.
- **Code — `crates/api`**:
  - New handlers for `/v1/shooting-days/{id}/report/{dispo|shoot-day|planned-vs-actual}.pdf`,
    each carrying the `// AUTHZ-GATE:` handler-internal season-membership check.
  - `main.rs` constructs `TypstReportRenderer` (+ fonts, locale resources, semaphore)
    and injects it through the `ReportRenderer` port alongside the existing report
    repository.
- **Dependencies**: `typst`, `typst-pdf` (pinned, lockstep upgrade only after report
  regression tests pass); `icu`, `icu_decimal`, `icu_datetime` (Unicode-3.0);
  `fluent-bundle` (Apache-2.0 OR MIT); OFL-1.1 font bundle. `cargo deny` licence/vuln
  gates must pass; RustSec findings inventoried.
- **CI**: template-compilation, malicious-input, empty/all-optional-absent fixtures,
  50/51-page boundary tests, concurrent-render tests, `de-DE` golden cases, and PDF
  endpoint authorization tests asserting the literal `// AUTHZ-GATE:` pattern remains
  fail-closed. `cargo deny check bans` covers the new Typst/ICU4X/Fluent additions.
- **Security**: static templates + JSON data boundary + denied FS/net/package access
  reduce template-injection and SSRF surface; AUTHZ-GATE retained on the new PDF
  handlers; user input never becomes a response header or filesystem path.

## Dependencies

- Depends on the read-side `scene-shoot-reports` capability (already implemented in the
  `add-shoot-day-execution-and-continuity` change) — the renderer consumes its
  projection-derived rows, not a new projection.
- Depends on ADR-015 (Postgres read model) and ADR-021 (API versioning prefix).
- Is a prerequisite for the follow-up change `add-report-archival-backup` (ADR-022 D6),
  which reuses `ReportRenderer` and the bounded-rendering runtime.
