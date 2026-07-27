# ADR-022: In-Process Typst for PDF Reporting and Report Archival

**Status**: Proposed
**Date**: 2026-07-27
**Author**: Tobias Rademacher (@trademacher); gpt-5.6-sol (opencode)
**Supersedes**: —
**Related**: ADR-015 (SierraDB event store and PostgreSQL read model), ADR-019
  (photo storage CRUD-port precedent), ADR-021 (HTTP API versioning)
**Source change**: tracked in GitHub issue #TBD

---

## Context

The three shooting-day reports — `dispo`, `shoot-day`, and `planned-vs-actual` — are
currently read-side JSON responses backed by PostgreSQL projections. They now
need deterministic PDF output in two modes: an on-demand HTTP response and an
automated asynchronous backup uploaded to configurable external storage. PDF
rendering remains a read-side concern: it does not dispatch a SierraDB command,
change an aggregate, or emit a domain event.

The first supported locale is `de-DE`. Number and date formatting, translated
labels, empty data, optional values, pagination, and ordering must be stable
across hosts. Branded fonts, logos, and page headers are deferred, but the
chosen engine and template boundary must admit them without redesign. Reports
are limited to 50 pages in the first release.

The security boundary is important. Report values, notes, and future image
metadata are untrusted data even though templates are trusted application
assets. A renderer must not turn row values into executable template source,
fetch arbitrary URLs, read the host filesystem, resolve packages over the
network, or permit unbounded concurrent CPU work. Existing PDF handlers must
retain the handler-internal season-membership check marked by
`// AUTHZ-GATE:` before querying or rendering report data.

### Candidate inventory and licences

All crate licences below were checked against crates.io on the decision date.
Apache-2.0, MIT, BSD-3-Clause, and Unicode-3.0 are compatible with an
AGPL-3.0 application. Compatibility does not remove attribution, notice, or
source-offer obligations.

| Candidate | Integration mode | Licence and AGPL-3.0 assessment |
|---|---|---|
| Direct Typst library (`typst` + `typst-pdf`) | In-process Rust | Apache-2.0 for both crates; compatible. `typst-pdf` is the PDF exporter used after Typst compilation. |
| Typst through `typst-as-lib` | In-process Rust wrapper | `typst-as-lib` MIT; underlying Typst crates Apache-2.0; compatible. |
| Typst CLI | Subprocess | Typst CLI/compiler Apache-2.0; compatible. Binary version and notices must be shipped with the image. |
| Typst source generated with Tera, Askama, or MiniJinja | In-process templating plus Typst | Tera MIT; Askama MIT OR Apache-2.0; MiniJinja Apache-2.0; Typst Apache-2.0; all compatible. |
| `printpdf` | In-process Rust | MIT; compatible. |
| `pdf-writer` | In-process Rust | MIT OR Apache-2.0; compatible. |
| `genpdf` | In-process Rust | Apache-2.0 OR MIT; compatible. |
| `typst-pdf` alone | In-process Rust | Apache-2.0; compatible, but it exports an already compiled Typst document and is not a standalone layout/report engine. |
| WeasyPrint | Python subprocess | BSD-3-Clause; compatible. Its native Cairo/Pango/font stack has separate compatible licences and requires an image-level licence/SBOM verification. |
| Headless Chromium controlled by `headless_chrome` or `chromiumoxide` | Browser subprocess | Controllers are MIT or MIT OR Apache-2.0. Chromium core is BSD-3-Clause-style and bundles many separately licensed components; expected compatible, but the exact distributed binary's notices/SBOM must be verified. |
| Gotenberg | Dockerized HTTP service | Gotenberg is MIT; compatible. Its Chromium and LibreOffice image contents retain their own licences and require an image-level licence/SBOM verification. |

No candidate above adds a GPL or AGPL copyleft dependency to the application.
The network-effect caveat still applies to `breakdown-rs` itself: operating a
modified AGPL-3.0 server for users triggers AGPL section 13's Corresponding
Source offer. A separately deployed service would not weaken that obligation,
and modifications to any separately AGPL-licensed service would carry that
service's own network obligations; no such service is selected here.

### Weighted comparison

Scores are 0 (unacceptable) to 5 (best). The weighted maximum is 85. “Costs”
includes licence fees and recurring deployment/operations cost; engineering
limitations are reflected primarily in future-proofing and template
ergonomics. Scores assess the complete integration, not PDF byte writing in
isolation.

| Candidate | License ×3 | Security ×3 | Future-proof ×3 | Costs ×3 | Rust-native ×2 | Template ergonomics ×2 | Ops simplicity ×1 | Weighted total / 85 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| **Direct in-process Typst (chosen)** | 5 | 4 | 4 | 5 | 5 | 5 | 5 | **79** |
| Typst through `typst-as-lib` | 5 | 4 | 3 | 5 | 5 | 5 | 5 | **76** |
| Typst CLI subprocess | 5 | 3 | 4 | 4 | 2 | 5 | 3 | **65** |
| Typst + generated source (Tera/Askama/MiniJinja) | 5 | 2 | 4 | 4 | 5 | 4 | 4 | **67** |
| `printpdf` | 5 | 4 | 3 | 4 | 5 | 2 | 5 | **67** |
| `pdf-writer` | 5 | 4 | 3 | 4 | 5 | 1 | 5 | **65** |
| `genpdf` | 5 | 4 | 2 | 4 | 5 | 3 | 5 | **66** |
| `typst-pdf` alone | 5 | 4 | 1 | 4 | 5 | 0 | 5 | **57** |
| WeasyPrint subprocess | 5 | 3 | 4 | 3 | 1 | 4 | 2 | **57** |
| Headless Chromium subprocess | 4 | 2 | 5 | 2 | 1 | 5 | 1 | **52** |
| Gotenberg service | 4 | 3 | 4 | 2 | 0 | 4 | 1 | **48** |

Typst wins because it supplies a high-level, paged typesetting language,
repeatable tables, page headers/footers, font shaping, and future branding
without adding a browser, Python runtime, external service, or shell boundary.
Its security score is not 5: it is a large compiler dependency, compilation is
CPU-intensive, the Rust embedding API changes between releases, and an
in-process compilation cannot be force-killed as cleanly as a subprocess.
Those costs are controlled by trusted static templates, version pinning,
bounded inputs, and concurrency limits.

## Decision

### D1: Use direct, in-process Typst compilation

The reporting adapter shall compile trusted Typst templates in process with the
same pinned release of the Apache-2.0 `typst` and `typst-pdf` crates. No Typst
CLI, Python process, browser, containerized reporting service, or network call
is on the render path. `typst-as-lib` is not part of the baseline; the adapter
owns the small `World`/virtual-file-system integration needed by the compiler,
which keeps the project in control of filesystem, package, and font access.
The Typst crates must be upgraded in lockstep and only after report regression
tests pass.

Templates are static application assets. They shall not be built by
concatenating report values into `.typ` source and shall not be passed through
Tera, Askama, or MiniJinja. The adapter serializes a renderer-owned data model
to JSON and exposes it as a virtual, in-memory `report.json`; the fixed template
reads that data. Translation data and approved image/font assets use the same
allowlisted virtual filesystem. Package lookup, arbitrary host filesystem
access, and network retrieval are disabled. Future logos and continuity images
must be fetched and validated by Rust code and injected as bounded virtual
assets; a template never resolves their IDs or URLs itself.

A minimal, pinned, licence-reviewed font set is packaged from the first release
for deterministic Latin text, independently of later branded fonts. Host font
fallback is disabled. The exact font files and their notices require a licence
review before merge; an OFL-1.1 family such as Noto Sans is a candidate, not an
unreviewed implicit dependency.

### D2: Define renderer and artifact-storage ports in `core`

A new pure module under `crates/core/src/reporting/` owns renderer-neutral
request/response DTOs, `ReportKind` (`Dispo`, `ShootDay`, `PlannedVsActual`), the
supported locale identifier, `ReportRenderer`, `ReportArchiveStorage`, and
typed `ReportRenderError`/`ReportStorageError` values. The render request holds
pure report data and presentation context, not a database pool, Typst value,
Axum type, OpenDAL operator, filesystem path, or provider credential.
`ReportRenderer` returns PDF bytes plus safe response metadata and never
panics for invalid data or a compiler failure.

`ReportArchiveStorage` follows the non-CQRS CRUD-port precedent of
`PhotoStorage`, but it is a separate port: report artifacts have deterministic
keys, content digests, retention, and remote object identifiers rather than
`PhotoId` variants. It supports idempotent put/fetch/delete/existence semantics
needed for staging and retry. The port API must not expose Google Drive or
OpenDAL types.

Implementations and resources are placed as follows:

- `crates/infra/src/reporting/typst.rs`: `TypstReportRenderer` adapter;
- `crates/infra/src/reporting/storage.rs`: OpenDAL-backed report artifact
  storage;
- `crates/infra/src/reporting/backup.rs`: durable job orchestration and retry;
- `crates/infra/templates/reports/{dispo,shoot-day,planned-vs-actual}.typ`: trusted,
  compile-time-embedded templates;
- `crates/infra/templates/reports/i18n/de-DE.ftl`: report messages;
- `crates/infra/assets/reporting/`: reviewed fonts and future logos.

The existing `SceneShootReportRepository` remains the read port for PostgreSQL
projection data. It is not folded into the renderer. `api` orchestrates the
repository and renderer through ports, while `main.rs` constructs and injects
the concrete infra adapters. `core` gains no dependency on Typst, ICU4X,
Fluent, OpenDAL, `sqlx`, or Axum.

### D3: Render `de-DE` through an explicit locale layer

The initial supported BCP-47 locale is exactly `de-DE`, selected from an
allowlist rather than used as a template path. Human-readable labels come from
Fluent resources (`fluent-bundle`, Apache-2.0 OR MIT). Decimal and calendar
formatting use ICU4X components (`icu`, `icu_decimal`, and `icu_datetime`,
Unicode-3.0) in the infra adapter; exact component features are fixed by the
implementation spike. Timestamps are converted with an explicit configured or
request-supplied IANA time zone before formatting. Locale and time zone are not
conflated, and the process host's locale/time zone is never consulted.

The template receives already localized display values and stable raw values
only where layout needs them. For `de-DE`, missing optional values render as an
em dash, an empty row set renders a valid report with localized “Keine Daten
vorhanden”, and empty notes/photo lists render their localized empty state. The
`PlannedVsActualReport.final` value derived from `wrapped_at` is preserved and rendered
as a localized final/preliminary state. This is defined behavior, not a
template exception. Future locales add a catalog and locale-formatting tests
without copying report query logic.

Typst can shape broad Unicode when a suitable font is supplied, but the first
font bundle only guarantees the characters needed by `de-DE`. CJK and RTL are
therefore not first-release supported locales. Enabling them requires reviewed
fonts plus mixed-direction, line-breaking, table, and visual regression tests;
no engine replacement is expected.

### D4: Add explicit PDF routes without removing JSON in the first release

The first rollout augments rather than silently changes the existing JSON
contract. The API-first change adds explicit PDF resources for each report
under the active ADR-021 API prefix, for example
`/v1/shooting-days/{id}/report/dispo.pdf`; equivalent `shoot-day.pdf` and
`planned-vs-actual.pdf` routes follow the same rule. Existing JSON routes remain during
the migration and may be deprecated separately under ADR-021.

Every PDF handler retains the existing handler-internal authorization pattern:

1. resolve shooting day → episode → block → season;
2. execute the season-membership policy check under a literal
   `// AUTHZ-GATE:` comment and fail closed on lookup/policy errors;
3. only after authorization, query report rows and render PDF.

Successful responses use `application/pdf`, a server-generated and sanitized
`Content-Disposition` filename, and `Cache-Control: private, no-store`. User
input does not become a response header or storage path. A render/storage error
is mapped from its typed port error to an API error; it never panics and never
returns partial PDF bytes. A manual endpoint that enqueues an external backup,
if added, uses the same gate. Internal scheduled/event-driven jobs are not
public authorization bypasses: they are trusted service jobs scoped to an
explicit season and configured destination.

### D5: Bound and isolate rendering work within the process

Typst produces a complete paged document before `typst-pdf` emits bytes, so the
first implementation is deliberately one-shot, not falsely described as
streaming. It renders into memory, checks the final page count, and rejects a
document over 50 pages with a typed `PageLimitExceeded` error. Row count,
serialized JSON size, individual string length, injected asset count/size, and
output byte size also receive configured bounds before or during rendering.
Reports exceeding the synchronous policy must use an asynchronous export or a
future segmented format; they are not partially returned.

Compilation is CPU-bound and runs via `tokio::task::spawn_blocking` behind a
process-wide semaphore with a configured concurrency limit. The HTTP path and
backup worker share that budget so a backup burst cannot starve requests. A
wall-clock deadline bounds caller waiting, while the semaphore remains held
until the blocking compilation actually ends; Tokio cancellation alone is not
claimed to kill compiler code. Because templates are trusted and inputs are
bounded, this is accepted for the first release. If the spike demonstrates
unacceptable tail latency or non-terminating compilation, D1 is reversed in
favor of the pinned Typst CLI in a sandboxed worker process.

Rendering reads a projection snapshot and is outside aggregate actors and the
SierraDB command path. Concurrent requests do not mutate event-sourced state.
The adapter is stateless apart from immutable templates/fonts and bounded
compiler caches; report inputs and outputs are not shared mutably between
renders.

### D6: Use durable staging and an idempotent async backup worker

An internal trigger — initially a configured schedule and/or a
`ShootingDayWrapped` reaction — enqueues a durable operational report job. The
job is infrastructure state, not a domain aggregate. If PostgreSQL is used for
the queue, its schema is separate from business projections and every claim,
insert, and update uses static SQL literals with bound values. Redelivered
triggers are deduplicated by a deterministic key containing report kind,
shooting-day ID, trigger/snapshot identity, locale, and template version.

A worker performs the same authorized-by-service-scope read and the same render
adapter as the HTTP path, then:

1. writes the complete PDF and content digest to durable internal Garage/S3
   staging through an injected `ReportArchiveStorage` instance;
2. uploads that exact staged object to the configured external
   `ReportArchiveStorage` instance with an idempotent destination key;
3. records the provider object ID/ETag and success before applying the staging
   retention policy.

An external upload failure never discards the only rendered copy. The staged
Garage object is reused on exponential-backoff retries, so retry does not query
a newer projection or regenerate different bytes. Retries are bounded and
move to an observable failed/dead-letter state requiring operator action;
periodic reconciliation detects jobs and staged objects stranded by crashes.
Garage staging is durable object storage, not an ephemeral process file or
container volume. Sensitive PDF bytes and provider credentials are never
logged.

The same OpenDAL technology already used for photos is the preferred adapter:
Garage/S3 is used for staging, and OpenDAL's real `services-gdrive` backend is
the first Google Drive implementation to evaluate. Google Drive shared-drive,
folder, refresh-token/service-account, conditional-write, and idempotency
behavior must be proven by an integration spike. If those required semantics
are not exposed reliably, only the Google Drive adapter changes to the MIT
`google-drive3` client with `yup-oauth2` (MIT OR Apache-2.0); the core port,
renderer, worker, and Garage staging remain unchanged. S3, GCS, or WebDAV can
be selected by configuration through other OpenDAL backends without changing
`core`.

## Alternatives Considered

- **Typst through `typst-as-lib`.** Rejected as the baseline — it is a useful
  MIT wrapper, but adds another release-compatibility layer over Typst's
  already fast-moving internals and a smaller maintenance surface. The direct
  adapter is narrow and security-sensitive enough to own locally. The spike
  may reverse this if implementing a restricted `World` proves materially
  larger or less safe than the wrapper.
- **Typst CLI subprocess.** Rejected — it preserves Typst's layout quality and
  creates a stronger kill boundary, but adds binary installation/version
  drift, process spawning, temporary/pipe I/O, sandboxing, and error-protocol
  handling. It is the designated fallback if in-process CPU cancellation or
  compiler API churn is unacceptable.
- **Generate `.typ` source with Tera.** Rejected — Tera is MIT and ergonomic,
  but double templating introduces quoting ambiguities and turns missed
  escaping into Typst code injection. Static Typst plus JSON has one language
  and one data boundary.
- **Generate `.typ` source with Askama.** Rejected — Askama is MIT OR
  Apache-2.0 and compile-time checked, but compile-time template checks do not
  make arbitrary text safe Typst syntax. It retains the same unnecessary code
  generation boundary.
- **Generate `.typ` source with MiniJinja.** Rejected — MiniJinja is
  Apache-2.0 and lightweight, but has the same source-injection and two-template
  debugging costs. Its HTML-style escaping is not a Typst security contract.
- **`printpdf`.** Rejected — the MIT crate is a capable in-process Rust PDF
  library, but `breakdown-rs` would own table layout, repeated headers,
  pagination, line breaking, font fallback, and future branding primitives.
  That is reporting-engine code rather than domain value.
- **`pdf-writer`.** Rejected — the MIT OR Apache-2.0 crate is intentionally a
  low-level PDF writer, not a document layout or report templating engine. It
  is suitable beneath an engine, not as this system's authoring layer.
- **`genpdf`.** Rejected — the Apache-2.0 OR MIT crate offers higher-level
  elements, but its current 0.2 release and smaller feature/maintenance surface
  make complex tables, advanced typography, branding, CJK/RTL growth, and
  long-term evolution a higher risk than Typst.
- **`typst-pdf` alone.** Rejected as a standalone option — it serializes a
  compiled Typst paged document to PDF; it does not parse templates, evaluate
  data, or perform layout. It is a required part of the chosen Typst stack,
  not an alternative report engine.
- **WeasyPrint.** Rejected — BSD-3-Clause and strong paged CSS make it credible,
  but Python plus Cairo/Pango native packages increase image size, patching,
  SBOM work, subprocess supervision, and host parity risk. It is not Rust
  native and offers no decisive template advantage for these tabular reports.
- **Headless Chromium via `headless_chrome` or `chromiumoxide`.** Rejected — HTML
  and CSS ergonomics are excellent, but the browser is a very large,
  high-frequency security/runtime dependency. Sandboxing, process cleanup,
  fonts, version pinning, and substantial memory use outweigh reuse of web
  skills for three server-generated reports.
- **Gotenberg.** Rejected — the MIT Docker API is the strongest self-hosted
  service candidate, but it adds another network service, authentication,
  availability target, image/SBOM, Chromium/LibreOffice patching, and per-render
  network hop. In-process Typst is materially simpler for the present scale.

## Consequences

Positive: report layout becomes a versioned, reviewable template concern rather
than handwritten PDF drawing code; all three reports share deterministic
pagination and `de-DE` formatting; the same renderer serves HTTP and backups;
future fonts, logos, headers, and locales fit the virtual-asset/template
boundary; and renderer/external-storage adapters remain replaceable without
polluting `core`. The JSON-to-static-template boundary and denied
filesystem/network access substantially reduce template injection and SSRF
risk.

Negative: `typst` and `typst-pdf` are large, fast-moving compiler dependencies
that increase clean build time, binary size, upgrade effort, and CPU/memory per
request. Their current 0.15.1 releases require Rust 1.92; the repository's
current Rust 1.97 toolchain satisfies that requirement, but CI/toolchain policy
must continue to do so. Typst's embedding API is less stable than its language,
PDF generation is whole-document rather than streaming, hard cancellation is
weaker in process, and first-release CJK/RTL support is intentionally absent.
Tagged-PDF/PDF-UA accessibility, exact PDF archival conformance, and Google
Drive conditional-write behavior are not assumed and require verification if
they become requirements.

Operational impact: `infra` gains pinned lockstep Typst dependencies, ICU4X
Unicode-3.0 components, `fluent-bundle`, embedded templates, reviewed font
assets/notices, render metrics, semaphore/deadline/page-size configuration,
and golden/text/page-count regression tests. OpenDAL remains Apache-2.0 and
gains only the configured backend feature; a direct Google adapter is added
only if the spike requires it. The runtime adds no PDF daemon or CLI, but async
backup adds a durable job table/worker, Garage staging lifecycle, retries,
dead-letter alerting, external-provider credentials, TLS, least-privilege
folder/bucket access, and orphan reconciliation. CI must run `cargo deny`,
dependency vulnerability/licence checks, template compilation, malicious-input
tests, empty/all-optional fixtures, 50/51-page boundary tests, concurrent render
tests, `de-DE` golden cases, and PDF endpoint authorization tests that assert
the literal `// AUTHZ-GATE:` pattern remains fail-closed.

AGPL impact: the permissive dependencies do not change the project's
AGPL-3.0 licence. Distribution must retain their notices and reviewed font
licences. Operators offering a modified `breakdown-rs` over a network must
continue to provide Corresponding Source under AGPL-3.0 section 13, including
the report adapter and project templates as part of that modified application.
Generated PDFs contain application data and rendered template output; this ADR
does not claim that every generated PDF is automatically licensed AGPL-3.0.

## Critical Review

The strongest counter-argument is that direct Typst embedding couples the
server to an unstable, heavyweight compiler API without a hard process-kill
boundary. A pinned Typst CLI worker would preserve the same template quality,
isolate CPU/memory failures, and reduce application code needed to implement a
`World`; its extra deployment work may be cheaper than repeatedly adapting to
compiler internals.

The decision rests on three material unknowns: (1) whether direct embedding can
compile representative 50-page reports within acceptable latency and memory
under concurrent load; (2) whether a restricted virtual filesystem, pinned
fonts, and compiler caches can be implemented without accidental host/package
access or excessive adapter complexity; and (3) whether OpenDAL's Google Drive
backend provides the authentication, shared-folder, idempotent overwrite, and
remote-ID semantics required by retries. Typst's current tagged-PDF/PDF-UA and
complex RTL behavior are also unproven, but are not first-release requirements.

Before implementation is accepted, a spike must render worst-case
`dispo`, `shoot-day`, and `planned-vs-actual` fixtures (empty, all optional values absent,
Unicode, 50 and 51 pages), benchmark concurrent CPU/memory/tail latency, test
malicious strings and denied file/network/package access, exercise deterministic
font/layout output in CI and the production image, and run an OpenDAL Google
Drive retry/idempotency integration test. A crate/API audit must compare the
direct adapter with `typst-as-lib` and inventory all transitive licences and
RustSec findings. Evidence of unbounded/non-cancellable compilation, an adapter
that cannot enforce the resource boundary, unacceptable build/runtime cost, or
frequent breaking compiler integration would reverse D1 to a sandboxed pinned
Typst CLI worker. Failure of only the Google Drive spike changes the storage
adapter, not the rendering decision. Subject to those gates, the recommendation
remains direct in-process Typst.
