<!--
  Authors: Tobias Rademacher (@tradem) — domain stakeholder & spec author
           glm-5.2 (neuralwatt) — coding agent / co-author
-->

## 0. Spike (GATE — evidence required before D1-lock)

- [x] 0.1 Build a minimal `TypstReportRenderer`-equivalent compiling a worst-case
      fixture per kind (empty, all-optionals-absent, Unicode, 50- and 51-page) and
      capture CPU/memory/tail-latency at the configured concurrency limit
- [x] 0.2 Malicious-input tests: JSON-via-virtual-file boundary cannot execute Typst
      code, fetch packages, read host FS, or open network connections
- [x] 0.3 Deterministic font/layout output: identical input → page-identical (or
      byte-identical golden) PDF across CI and the production image
- [x] 0.4 Crate/API audit comparing direct adapter vs `typst-as-lib`; full transitive
      licence + RustSec inventory for `typst`, `typst-pdf`, ICU4X components,
      `fluent-bundle`, chosen fonts
- [x] 0.5 **Gate decision**: record evidence; if any D1-reversal condition holds,
      swap to a sandboxed pinned Typst CLI worker (infra-only); otherwise lock the
      in-process baseline

## 1. Core reporting module (pure)

- [x] 1.1 Add `crates/core/src/reporting/mod.rs` with `ReportKind`
      (`Dispo | ShootDay | PlannedVsActual`), `ReportLocale` newtype over a `de-DE`
      allowlist, `RenderPresentationContext { locale, tz, template_version }`
- [x] 1.2 Add `ReportRenderRequest { kind, locale, tz, data }` (pure data — no DB
      pool, Typst value, Axum/OpenDAL type, FS path, or credential) and a renderer-owned
      data model struct serialized to `report.json` by the adapter
- [x] 1.3 Add `ReportBytes { kind, locale, pdf_bytes, page_count, content_type, ... }`
      + safe response metadata
- [x] 1.4 Add `ReportRenderer` trait (`async fn render(...) -> Result<ReportBytes,
      ReportRenderError>`; must never panic for invalid data/compiler failure)
- [x] 1.5 Add `ReportRenderError` variants: `PageLimitExceeded`, `InputBoundsExceeded`,
      `CompilerFailure`, `RenderTimeout`, `LocaleUnsupported`, `TemplateNotFound`,
      `AssetRejected`; serde + Debug; `Send + Sync`
- [x] 1.6 Unit tests: error variants round-trip; `ReportKind`/locale allowlist
      enforce; `core` has **no** dependency on typst/ICU4X/Fluent/OpenDAL/sqlx/Axum
      (arkitech boundary + `cargo deny check bans`)

## 2. Infra: in-process Typst adapter

- [x] 2.1 Add pinned `typst` + `typst-pdf` (lockstep) with minimal features; run
      `cargo deny check bans` + vuln; record RustSec findings
- [x] 2.2 Implement `TypstReportRenderer` in `crates/infra/src/reporting/typst.rs`
      owning a restricted `World`: package lookup disabled, host FS denied, network
      retrieval denied, host font fallback disabled
- [x] 2.3 Embed trusted static templates
      `crates/infra/templates/reports/{dispo,shoot-day,planned-vs-actual}.typ` and
      i18n `crates/infra/templates/reports/i18n/de-DE.ftl` at compile time
      (`include_str!` / `rust-embed`)
- [x] 2.4 Serialize the renderer-owned data model to an in-memory `report.json`
      exposed as a virtual file; templates read it — report values are never
      concatenated into `.typ` source
- [x] 2.5 Package a reviewed OFL-1.1 font bundle under
      `crates/infra/assets/reporting/` (+ notices) for deterministic Latin text
- [x] 2.6 Adapter unit tests: render each kind to a non-empty PDF; assert
      `application/pdf`; assert no host FS/net/package access on a poisoned input set

## 3. de-DE locale layer

- [x] 3.1 Add `fluent-bundle` + ICU4X (`icu`, `icu_decimal`, `icu_datetime`) with
      versioned data; host locale/time zone never consulted
- [x] 3.2 Implement `crates/infra/src/reporting/locale.rs`: decimal + calendar
      formatting for `de-DE`; explicit IANA time zone conversion before formatting;
      boot-read `REPORT_DEFAULT_TIMEZONE` (default `Europe/Berlin`, deployment-time, not
      runtime, not hardcoded); per-request `X-Report-Timezone` header validated against
      the IANA tz allowlist (unknown → `400` / typed error)
- [x] 3.3 Defined `de-DE` semantics: missing optionals → em dash; empty row set →
      localized "Keine Daten vorhanden"; empty notes/photo lists → localized empty
      state; `PlannedVsActual.final` → localized final/preliminary state
- [x] 3.4 Unit/golden tests: `de-DE` labels, number/date formats, empty/optional
      fixtures produce defined output

## 4. Bounded rendering

- [x] 4.1 Render via `tokio::task::spawn_blocking` behind a process-wide semaphore
      (config: `REPORT_RENDER_CONCURRENCY`); budget shared with the future backup
      worker (change 2)
- [x] 4.2 Wall-clock deadline (`REPORT_RENDER_DEADLINE_SECS`); semaphore held until the
      blocking compile ends (no claim of hard compiler kill)
- [x] 4.3 Enforce bounds before/during render: row count, serialized JSON size,
      individual string length, injected asset count/size, output byte size
      (`REPORT_MAX_*` config); over-limit → `InputBoundsExceeded`
- [x] 4.4 Final page count check; reject > 50 pages with `PageLimitExceeded`
      (`REPORT_MAX_PAGES=50`)
- [x] 4.5 Tests: 50-page OK, 51-page rejects; boundary input fixtures; concurrent
      renders respect semaphore; deadline elapses → `RenderTimeout`

## 5. HTTP PDF routes + AUTHZ-GATE (api)

- [x] 5.1 Add handlers `GET /v1/shooting-days/{id}/report/{dispo|shoot-day|planned-vs-actual}.pdf`
      (ADR-021 prefix); existing JSON routes untouched
- [x] 5.2 Each handler: resolve shooting_day → episode → block → season; run the
      season-membership policy check under a literal `// AUTHZ-GATE:` comment; fail
      closed on lookup/policy error; only then query rows + render
- [x] 5.3 Responses: `application/pdf`; server-generated + sanitized
      `Content-Disposition` filename (user input never a header/storage path);
      `Cache-Control: private, no-store`
- [x] 5.4 Render-error → API-error mapping: typed `ReportRenderError` variants map to
      structured API errors (e.g. 422 for bounds/page, 408 for timeout, 500 for
      compiler failure); never panic; never return partial PDF bytes
- [x] 5.5 `main.rs` constructs `TypstReportRenderer` (+ fonts, locale resources,
      semaphore) and injects it via the `ReportRenderer` port alongside the report
      repository
- [x] 5.6 Route-coverage tests verify auth for every new `.pdf` endpoint (mirror the
      existing auth-route-coverage pattern); assert the literal `// AUTHZ-GATE:`
      grep-locates every new handler

## 6. Tests & CI

- [x] 6.1 Golden `de-DE` PDF fixtures per kind (comparable page count + content) under
      `crates/infra` tests; deterministic across CI/prod
- [x] 6.2 Malicious-input suite: Typst-syntax-bearing values, path/package/URL
      attempts — all rejection-only, never executed
- [x] 6.3 Empty / all-optionals-absent fixture per kind renders a defined report
- [x] 6.4 50/51-page boundary tests per kind
- [x] 6.5 Concurrent render tests under the shared semaphore budget
- [x] 6.6 PDF endpoint authorization tests asserting fail-closed `// AUTHZ-GATE:`
      on every new route (member allowed; non-member denied; lookup error denied)
- [x] 6.7 `cargo deny check bans` + `cargo test -p architecture_tests` pass with the
      new deps; `core` boundary stays clean
- [x] 6.8 License/SBOM + font notice review recorded before merge
- [x] 6.9 `X-Report-Timezone` security tests + fuzz: unknown/oversized/injection TZ
      values are rejected (`400`) without crashing, and cannot reach Typst source, host
      FS, or network retrieval (display-formatting only)
