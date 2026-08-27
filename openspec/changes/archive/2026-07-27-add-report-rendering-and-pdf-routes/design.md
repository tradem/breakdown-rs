<!--
  Authors: Tobias Rademacher (@tradem) — domain stakeholder & spec author
           glm-5.2 (neuralwatt) — coding agent / co-author
-->

## Context

The three shoot-day reports (Dispo, Shoot Day, Planned-vs-Actual) are produced today
as JSON read-side responses from `projection_scene_shoot` via
`SceneShootReportRepository` (introduced by `add-shoot-day-execution-and-continuity`).
They need deterministic PDF output that is shareable, archival, translation-stable
across hosts, and authorization-correct. ADR-022 selects **direct in-process Typst**
for the engine and defines the renderer/storage-ports boundary; this change implements
the *rendering* half (ADR-022 D1–D5) plus the *HTTP delivery* (D4). The async backup
worker (D6) is a separate change that depends on this renderer.

Two ADR-022 material unknowns must be resolved by a spike **before the engine
decision is locked** (the third unknown — OpenDAL Google Drive idempotency — belongs
to the backup change):

1. Whether direct Typst embedding compiles representative worst-case reports (empty,
   all-optionals-absent, Unicode, 50- and 51-page) within acceptable latency/memory
   under concurrent load.
2. Whether a restricted virtual filesystem, pinned fonts, and compiler caches can be
   implemented without accidental host/package/network access or excessive adapter
   complexity.

If the spike demonstrates unbounded/non-cancellable compilation, an adapter unable to
enforce the resource boundary, unacceptable build/runtime cost, or frequent breaking
compiler integration, **D1 reverses to a sandboxed pinned Typst CLI worker** (ADR-022
Critical Review) — a fallback that preserves template quality with a stronger kill
boundary. This design is written against the chosen in-process baseline; the
fallback's substitution points are called out explicitly so a reversal does not rewrite
`core`.

## Goals / Non-Goals

**Goals:**
- Define a renderer-neutral `ReportRenderer` port and typed errors in `core`
  (no Typst/ICU4X/Fluent/OpenDAL/Axum penetration).
- Implement a pinned in-process Typst adapter (`infra`) with a restricted `World` and
  trusted static templates; JSON data boundary only — no `.typ` source generation.
- Deliver `de-DE` formatting via ICU4X + Fluent with an explicit IANA time zone,
  never the host locale/time zone; defined empty/optional-value semantics.
- Bound rendering (semaphore + deadline + page/page-input caps) shared by the HTTP
  path and the future backup worker.
- Add explicit `.pdf` HTTP routes while keeping JSON routes; retain the `AUTHZ-GATE`
  handler-internal authorization pattern, fail-closed.
- Spike-gate the engine decision with worst-case fixtures and malicious-input tests.

**Non-Goals:**
- Asynchronous backup / external archive upload (ADR-022 D6 — separate change).
- Branded fonts, logos, page headers/footers beyond layout primitives (deferred but
  admitted by the template boundary).
- CJK / RTL locales (first font bundle only guarantees `de-DE`; enabling them needs
  reviewed fonts + mixed-direction/visual regression tests; no engine replacement).
- Streaming PDF output (Typst produces a complete paged document; v1 is whole-document).
- Tagged-PDF / PDF-UA accessibility conformance (not assumed; requires verification).
- Removing or deprecating the existing JSON report routes (handled separately under
  ADR-021 versioning).
- Changing the read-side `SceneShootReportRepository` or its projection.

## Decisions

### D1. Direct in-process Typst, pinned + lockstep

The `TypstReportRenderer` (`crates/infra/src/reporting/typst.rs`) compiles trusted
static templates with the same pinned release of the Apache-2.0 `typst` and
`typst-pdf` crates. No Typst CLI, no Python/browser/containerized service, no network
call is on the render path. `typst-as-lib` is **not** baseline; the adapter owns the
small restricted `World`/virtual-FS integration to keep filesystem/package/font
access in-project. The two crates are upgraded in lockstep and only after the gold/CI
report regression tests pass.

**Security preference (stakeholder, firmed):** the in-process baseline is the preferred
engine **on security grounds** — no process-spawn/sandbox/pipe boundary, no Typst CLI
binary to ship/pin, no subprocess supervision surface. This does not remove the spike
evidence gate: the ADR still requires proof of bounded CPU/memory and a VFS that cannot
accidentally reach host FS/package/network before the decision is locked. If the spike
reverses D1, it reverses on *evidence* (unbounded compilation / unenforceable boundary /
API churn), not on a preference trade-off.

**Substitution points for the CLI fallback** (if the spike reverses D1): the
`ReportRenderer` port in `core` is unchanged; only `infra`'s adapter implementation
swaps to a sandboxed pinned-CLI worker process. No `core`/`api` rewrite is required.

### D2. Renderer-neutral ports in `core`; templates are static assets

A new pure module `crates/core/src/reporting/` owns:

- `ReportKind` enum: `Dispo | ShootDay | PlannedVsActual`.
- `ReportLocale`: a newtype over the supported BCP-47 locale identifier (v1 = `de-DE`)
  drawn from an allowlist, **not** a template path.
- `RenderPresentationContext`: locale + IANA time zone (request-supplied or
  configured) + template version tag (used by the backup change's dedup key).
- `ReportRenderRequest { kind, locale, tz, data }`: pure report data + presentation
  context — no DB pool, no Typst value, no Axum type, no OpenDAL operator, no
  filesystem path, no credential.
- `ReportBytes { kind, locale, pdf_bytes, page_count, content_type, ... }` plus safe
  response metadata.
- `ReportRenderer` trait: `async fn render(&self, req: ReportRenderRequest) ->
  Result<ReportBytes, ReportRenderError>`. It never panics for invalid data or
  compiler failure.
- `ReportRenderError`: typed variants — `PageLimitExceeded { max, actual }`,
  `InputBoundsExceeded { limit, field }`, `CompilerFailure { detail }`,
  `RenderTimeout`, `LocaleUnsupported { locale }`, `TemplateNotFound`,
  `AssetRejected`.

Templates are static application assets, embedded at compile time
(`crates/infra/templates/reports/{dispo,shoot-day,planned-vs-actual}.typ`) plus an
i18n catalog (`crates/infra/templates/reports/i18n/de-DE.ftl`) and reviewed fonts
(`crates/infra/assets/reporting/`). Report values are serialized to an in-memory
`report.json` and exposed to the compiler as a virtual file; a template never reads
host paths, fetches packages over the network, or resolves URLs. Package lookup,
arbitrary host-FS access, and network retrieval are **disabled** in the `World`.
Future logos/continuity images must be fetched and validated by Rust and injected as
bounded virtual assets; a template never resolves their IDs/URLs itself.

The existing `SceneShootReportRepository` is **unchanged**: the API orchestrates the
repository (to obtain report rows) and the renderer (to render them) through ports;
`main.rs` wires concrete adapters. `core` gains no Typst/ICU4X/Fluent/OpenDAL dep.

### D3. `de-DE` through an explicit locale layer (ICU4X + Fluent)

The initial supported locale is exactly `de-DE`, selected from an allowlist (never a
template path). Human-readable labels come from `fluent-bundle`; decimal/calendar
formatting uses ICU4X (`icu`/`icu_decimal`/`icu_datetime`) in the **infra adapter**.
Timestamps are converted with an explicit configured-or-request-supplied IANA time
zone before formatting. Locale and time zone are **not conflated**; the process host's
locale/time zone is never consulted.

The template receives already-localized display values + stable raw values only where
layout needs them. Defined `de-DE` behavior: missing optionals → em dash; empty row
set → valid report with localized "Keine Daten vorhanden"; empty notes/photo lists →
localized empty state; `PlannedVsActual.final` (from `wrapped_at`) → localized
final/preliminary state. This is defined behavior, not a template exception. Future
locales add a catalog + locale-formatting tests without copying query logic.

Typst can shape broad Unicode when a suitable font is supplied, but the first font
bundle only guarantees the characters needed by `de-DE`; CJK/RTL are thus explicitly
not first-release supported.

### D4. Explicit PDF routes (JSON remains)

The first rollout **augments** rather than silently changes the JSON contract.
API-first additions under the active ADR-021 prefix:

```
GET /v1/shooting-days/{id}/report/dispo.pdf
GET /v1/shooting-days/{id}/report/shoot-day.pdf
GET /v1/shooting-days/{id}/report/planned-vs-actual.pdf
```

Existing JSON routes remain during migration and may be deprecated separately under
ADR-021. Every PDF handler retains the existing handler-internal authorization
pattern:

1. resolve shooting day → episode → block → season;
2. execute the season-membership policy check under a literal `// AUTHZ-GATE:`
   comment and fail closed on lookup/policy errors;
3. only after authorization, query report rows and render the PDF.

Successful responses use `application/pdf`, a server-generated + sanitized
`Content-Disposition` filename (user input never becomes a header or storage path),
and `Cache-Control: private, no-store`. A render error maps its typed port error to an
API error; it never panics and never returns partial PDF bytes.

### D5. Bounded & isolated rendering

Typst produces a complete paged document before `typst-pdf` emits bytes; v1 is
deliberately one-shot, **not** streaming. The renderer renders into memory, checks
the final page count, and rejects documents over 50 pages with typed
`PageLimitExceeded`. Row count, serialized JSON size, individual string length,
injected asset count/size, and output byte size also receive configured bounds
enforced before/during rendering; reports exceeding the synchronous policy use a
future async export or segmented format and are never partially returned.

Compilation is CPU-bound and runs via `tokio::task::spawn_blocking` behind a
process-wide semaphore with a configured concurrency limit. The HTTP path and the
future backup worker (ADR-022 D6) **share** that budget so a backup burst cannot
starve requests. A wall-clock deadline bounds caller waiting; the semaphore stays held
until the blocking compilation actually ends, and Tokio cancellation alone is not
claimed to hard-kill compiler code (accepted: templates are trusted, inputs bounded).
If the spike shows unacceptable tail latency or non-termination, D1 reverses to a
sandboxed pinned Typst CLI worker.

The adapter is stateless apart from immutable templates/fonts and bounded compiler
caches; report inputs and outputs are not shared mutably between renders. Rendering
reads a projection snapshot and is outside aggregate actors and the SierraDB command
path — concurrent requests do not mutate event-sourced state.

## Risks / Trade-offs

- **[Compiler API churn / unstable embedding]** → Typst's embedding API is less stable
  than its language. Mitigation: pin + lockstep upgrades gated on report regression
  tests; template/VFS boundary is small; CLI fallback is the documented reversal.
- **[Whole-document, weak hard cancellation in process]** → Accepted for v1 (trusted
  templates + bounded inputs). Mitigation: semaphore + deadline + input bounds; the
  spike must demonstrate bounded CPU/memory on worst-case fixture sets; fallback
  documented.
- **[Build time / binary size]** → `typst`+`typst-pdf` are large. Mitigation: pinned
  feature set; CI tracks binary size; the license/SBOM review includes transitive
  crates and RustSec findings.
- **[Locale determinism across hosts]** → ICU4X data is versioned; host font fallback
  disabled; pinned font bundle. Mitigation: golden-output tests for `de-DE`; locale is
  always explicit.
- **[AUTHZ-GATE must not be forgotten on new handlers]** → Every PDF handler carries a
  literal `// AUTHZ-GATE:` comment; CI asserts the pattern grep-locates all new routes.
  Maps to the photo-handler precedent in AGENTS.md.
- **[Font licence contamination]** → Fonts are an implicit dependency if unchecked.
  Mitigation: minimal reviewed OFL-1.1 bundle; notices retained; `cargo deny` + manual
  fonts review before merge.

## Spike (gate before D1-lock)

The spike MUST produce written evidence before implementation is accepted:

- Render worst-case `dispo`, `shoot-day`, `planned-vs-actual` fixtures: empty, all
  optionals absent, Unicode, 50- and 51-page boundary cases. Benchmark concurrent
  CPU/memory/tail latency at the configured concurrency limit.
- Malicious-input tests: report values that would-be Typst syntax/code paths; assert
  the JSON-via-virtual-file boundary cannot execute, fetch packages, read host FS, or
  open network connections.
- Deterministic font/layout output: the same input produces byte-identical (or
  page-identical golden) PDFs across CI and the production image.
- A crate/API audit comparing the direct adapter with `typst-as-lib`, and a full
  transitive licence + RustSec inventory for `typst`, `typst-pdf`, ICU4X components,
  `fluent-bundle`, and the chosen fonts.

**Gate outcome:** if any of {unbounded/non-cancellable compilation, an adapter that
cannot enforce the resource boundary, unacceptable build/runtime cost, frequent breaking
compiler integration} is observed, D1 reverses to a sandboxed pinned Typst CLI worker
(substituting only `infra`'s adapter; `core`/`api` unchanged). Otherwise the
in-process baseline is locked.

## Migration Plan

1. **Dependencies**: add pinned `typst`, `typst-pdf`, ICU4X components, `fluent-bundle`,
   a reviewed OFL-1.1 font bundle + notices. `Cargo.toml` features minimal; run
   `cargo deny check bans` + vuln.
2. **Core** (`crates/core/src/reporting/`): add types, port, errors. No infra deps;
   `arkitech` boundary tests must keep `core` clean.
3. **Infra**: implement `TypstReportRenderer` + restricted `World`; embed templates +
   i18n + fonts; locale module. Wire a render-bounds/semaphore runtime.
4. **API**: add `.pdf` handlers with `AUTHZ-GATE`; `main.rs` constructs + injects the
   renderer via the port. JSON routes untouched.
5. **CI**: golden `de-DE` fixtures, malicious-input, empty/all-optional, 50/51-page,
   concurrent-render, and PDF-authz grep tests.
6. **Rollout**: ship the `.pdf` routes alongside JSON; no write-path changes; read
   snapshot only. Rollback = disable the new routes (JSON unchanged).

## Resolved Decisions

- **Asset embedding — `rust-embed` for fonts; `include_str!` for templates/`.ftl`.**
  Fonts are binary assets best served via `rust-embed` (deterministic CI/prod parity,
  self-contained binary); the static `.typ` templates and `de-DE.ftl` catalog are
  text and use `include_str!`. No versioned crate asset / runtime file lookup.
- **Default time zone — `Europe/Berlin`, deployment-configurable (not runtime, not
  hardcoded).** The configured default TZ — read once at boot from an environment
  variable (e.g. `REPORT_DEFAULT_TIMEZONE`, default `Europe/Berlin`) — applies when a
  request omits `X-Report-Timezone`. It is a deployment-time setting baked into the
  process config, NOT a code constant and NOT changeable per-request at runtime; per-
  request override is *only* via the validated header above.
- **Render-bounds semaphore — infra config.** `core` exposes the port only; knobs
  (`REPORT_RENDER_CONCURRENCY`, `REPORT_RENDER_DEADLINE_SECS`, `REPORT_MAX_PAGES`,
  `REPORT_MAX_*` bounds) are infra/environment config, not `core`-visible.
- **PDF handler module — dedicated `report_pdf` handler module**, sharing read-port
  calls with the JSON report handlers, to keep the `// AUTHZ-GATE:` grep surface tight
  on every new route.

## Open Questions

- Whether the boot-time configured default TZ (`REPORT_DEFAULT_TIMEZONE`, default
  `Europe/Berlin`) covers every deployment, or whether multi-region deploys later need
  a per-season stored TZ (lean: defer until a concrete multi-region requirement; v1
  default `Europe/Berlin` is deployment-time and serves the `de-DE` first release).
