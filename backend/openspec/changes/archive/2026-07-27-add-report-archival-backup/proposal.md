<!--
  Authors: Tobias Rademacher (@tradem) — domain stakeholder & spec author
           glm-5.2 (neuralwatt) — coding agent / co-author
  Derived from ADR-022 (D6: durable staging + idempotent async backup worker).
-->

## Why

The PDF reports (delivered on-demand by the `add-report-rendering-and-pdf-routes`
change) also need **automated archival**: a durable, retry-safe backup of each
shoot-day report PDF to configurable external object storage (e.g. Google Drive), so
productions retain an authoritative, off-system copy even when the app is offline or
the projection later changes. Archival is an **infrastructure operation**, not a
domain concern: it is triggered as a trusted service job scoped to a season and a
configured destination — it is never a public authorization bypass and it dispatches
no SierraDB command, mutates no aggregate, and emits no domain event of its own.

ADR-022 D6 specifies: render → write the complete PDF + content digest to durable
internal Garage/S3 staging → upload that exact staged object to an external provider
with an idempotent destination key → persist the provider object ID/ETag before
applying staging retention. An external upload failure never discards the only
rendered copy; retries reuse the staged object so re-renders can't diverge. The
worker follows the same bounded-rendering budget and the same `ReportRenderer` as the
HTTP path.

## What Changes

- **New `ReportArchiveStorage` port in `core`**: a CRUD port (precedent:
  `PhotoStorage`) for report artifact bytes with idempotent
  put/fetch/delete/exists semantics keyed by a deterministic key; it SHALL NOT expose
  Google Drive or OpenDAL types. One injected instance is the durable Garage/S3
  staging store; another is the configured external provider.
- **Durable report-job lifecycle in `infra`** (not a domain aggregate): a PostgreSQL
  job/claim table in a schema **separate** from business projections; every claim,
  insert, and update uses static SQL literals with bound values. Redelivered triggers
  are deduplicated by a key composed of report kind, shooting-day ID, trigger/snapshot
  identity, locale, and template version.
- **Idempotent backup worker pipeline**: claim → (authorized-by-service-scope) read
  → render via the shared `ReportRenderer` → write PDF + digest to Garage staging →
  upload the exact staged object to the external provider with an idempotent
  destination key → record provider object ID/ETag and success → apply staging
  retention.
- **Retry & failure handling**: external upload failures reuse the staged object with
  exponential backoff; retries are bounded and move to an observable failed/dead-letter
  state requiring operator action; periodic reconciliation detects jobs and staged
  objects stranded by crashes. Sensitive PDF bytes and provider credentials are never
  logged.
- **Triggers**: a configured schedule, a `ShootingDayWrapped` reaction (the day is
  "closed for planning" → enqueue an archival job for that day's reports), **and** a
  manual "archive now" HTTP endpoint (the setting-gerechte fallback for cases where
  automation fails or is delayed; the Filmbetrieb has no operator-CLI culture, so a
  button is the only accepted remediation path). The manual trigger is idempotent via
  the same dedup key and SHALL use the same pipeline; it is gated to
  `CostumeDesigner` + `WardrobeSupervisor` roles only (a deliberate remediation
  action, not for every season assistant).
- **Provider abstraction**: OpenDAL's real `services-gdrive` backend is the first
  Google Drive implementation to evaluate; if the integration spike cannot prove
  shared-drive/folder/refresh-token-or-service-account/conditional-write/idempotency
  behavior, **only** the Google Drive adapter swaps to the MIT `google-drive3` client
  with `yup-oauth2` — the `core` port, renderer, worker, and Garage staging remain
  unchanged. S3/GCS/WebDAV are selectable by configuration through other OpenDAL
  backends without changing `core`.

## Capabilities

### New Capabilities
- `report-archival`: the `ReportArchiveStorage` CRUD port (core), durable internal
  Garage/S3 staging + external-provider adapters (infra), the durable report-job table
  + idempotent dedup, the staging-then-external backup worker pipeline, bounded
  retries → dead-letter + reconciliation, and the trigger surface (schedule +
  `ShootingDayWrapped` reaction).

### Modified Capabilities
- `shooting-day-lifecycle`: the `ShootingDayWrapped` event now also enqueues a
  trusted, season-scoped report-archival job (a service job, not an authorization
  bypass); the aggregate/event themselves are unchanged.

## Impact

- **Code — `crates/core`**:
  - New `reporting` additions: `ReportArchiveStorage` trait (idempotent
    put/fetch/delete/exists over a deterministic key; `ReportArtifactId`/key type),
    typed `ReportStorageError`. CRUD, not CQRS-split (matches `PhotoStorage`).
  - `core` gains no dependency on OpenDAL/Google/`sqlx`/Axum.
- **Code — `crates/infra`**:
  - `crates/infra/src/reporting/storage.rs`: OpenDAL-backed staging adapter (Garage/S3)
    implementing `ReportArchiveStorage`.
  - `crates/infra/src/reporting/backup.rs`: durable job orchestration + retry; the
    claim/dedup table; the worker loop; reconciliation; dead-letter handling.
  - External provider adapter(s): OpenDAL `services-gdrive` (primary) and, if the spike
    requires, a `google-drive3` + `yup-oauth2` adapter behind the same `core` port.
  - `main.rs` constructs two `ReportArchiveStorage` instances (internal staging +
    external provider), the worker, and wires them via the port; spawns the worker
    against the shared render-semaphore budget.
- **Schema (Postgres)**: a **dedicated** report-job schema/table separate from
  business projections (claim state, dedup key, staged object handle, provider
  outcome, retries, status). All SQL static literals + bound values; FK to read-model
  shooting-day IDs for integrity but no writes to business projections.
- **Triggers**: a scheduled ticker + a `ShootingDayWrapped` projector reaction that
  enqueues archival jobs (season-scoped).
- **Env vars**: provider endpoint/credentials/destination (e.g. `REPORT_BACKUP_*` /
  Google `GDRIVE_*`), `REPORT_BACKUP_STAGING_*` (Garage), retry/dead-letter config,
  recon interval, dedup/materialized knobs. No secrets in code; `gitleaks` must pass.
- **CI**: idempotency-under-redelivery tests, staging-reuse-on-retry tests,
  dedup-key uniqueness, dead-letter on exhausted retries, reconciliation of stranded
  jobs/staged objects, provider integration spike (OpenDAL `services-gdrive` retry/
  idempotency; or the fallback client), no-credential-logging assertions.
- **Security**: trusted service jobs are scoped to an explicit season + configured
  destination and are **not** a public authz bypass; `AUTHZ-GATE` semantics stay on
  the HTTP path; provider credentials least-privilege (folder/bucket scope), TLS,
  never logged.

## Dependencies

- **Depends on `add-report-rendering-and-pdf-routes`**: reuses the `ReportRenderer`
  port, the `TypstReportRenderer` adapter, and the bounded-rendering semaphore budget.
- Depends on ADR-015 (Postgres + SierraDB), ADR-019 (CRUD-port precedent via
  `PhotoStorage`), and ADR-022 D6 decisions.
- The Google Drive integration is the third ADR-022 spike-gated unknown (`google-drive3`
  is the documented fallback only if OpenDAL's `services-gdrive` cannot prove the
  required semantics).
