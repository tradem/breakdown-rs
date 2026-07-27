<!--
  Authors: Tobias Rademacher (@tradem) — domain stakeholder & spec author
           glm-5.2 (neuralwatt) — coding agent / co-author
-->

## 1. Port in core (pure)

- [x] 1.1 Add `ReportArchiveStorage` CRUD trait to `crates/core/src/reporting/`:
      idempotent `put(key, bytes, content_type, digest)`, `fetch(key)`, `delete(key)`,
      `exists(key)`; `ReportArtifactKey`/handle types; `Send + Sync`
- [x] 1.2 Add typed `ReportStorageError` (NotFound, Conflict, ProviderFailure,
      CredentialMissing, KeyRejected, …); serde + Debug; no bytes/credentials in errors
- [x] 1.3 Assert the port exposes no Google/OpenDAL types; `core` stays free of
      OpenDAL/sqlx/Axum (arkitect + `cargo deny check bans`)

## 2. Durable job table (infra, separate schema)

- [x] 2.1 Add a **dedicated** report-job migration in a schema separate from business
      projections: dedup key UNIQUE, kind, shooting_day_id, locale, template_version,
      staged_handle, content_digest, provider_outcome (id/etag + ts), retries, status,
      audit fields
- [x] 2.2 Implement claim/insert/update with **static SQL literals + bound values**
      only (passes the `no-string-interpolation-sql` CI job)
- [x] 2.3 Dedup key composed of {kind, shooting_day_id, trigger/snapshot identity,
      locale, template_version}; unique constraint; redelivered triggers dedup
- [x] 2.4 FK to read-model shooting-day id for integrity; **no writes** to business
      projections
- [x] 2.5 SSOT/EventStorming guardrail assertion: the job table holds NO business
      truth — no domain query path reads from it; it shadows/duplicates/supersedes no
      event, aggregate, or projection (verified by a test asserting no read-port/
      domain module imports the job-table query path)

## 3. Staging + external storage adapters (infra)

- [x] 3.1 `crates/infra/src/reporting/storage.rs`: OpenDAL Garage/S3 staging adapter
      implementing `ReportArchiveStorage` (#1 — durable internal staging)
- [x] 3.2 External provider adapter implementing `ReportArchiveStorage` (#2) via
      OpenDAL `services-gdrive` (primary); idempotent destination key
- [x] 3.3 Adapter key layout is infra-internal; the port sees only deterministic keys
- [x] 3.4 Adapters never log PDF bytes or provider credentials; typed errors carry none

## 4. Idempotent backup worker (infra)

- [x] 4.1 `crates/infra/src/reporting/backup.rs`: claim a job → authorized-by-service-scope
      read → render via shared `ReportRenderer` (shared semaphore + deadline + bounds)
- [x] 4.2 Pipeline: render → write PDF + content digest to Garage staging → upload the
      **exact** staged object to external provider with idempotent key → persist provider
      ID/ETag + success → apply staging retention
- [x] 4.3 On external failure: reuse the staged object on exponential-backoff retry
      (no re-query, no re-render); verify digest matches
- [x] 4.4 Bounded retries → move to observable failed/dead-letter state requiring
      operator action (no silent infinite retry)
- [x] 4.5 Reconciliation pass detects jobs and staged objects stranded by crashes;
      finalizes or dead-letters them
- [x] 4.6 `main.rs`: construct staging + external `ReportArchiveStorage`, the worker
      against the shared render budget; env-driven provider config; spawn worker

## 5. Triggers

- [x] 5.1 Scheduled ticker enqueues archival jobs per operator policy; idempotent via
      dedup key
- [x] 5.2 `ShootingDayWrapped` projector reaction enqueues an archival job for that
      day's reports (season-scoped service job; NOT a public authz bypass); no aggregate
      change
- [x] 5.3 Service-job authorization is enforced internally (season-scoped, configured
      destination); HTTP PDF routes retain their `AUTHZ-GATE`
- [x] 5.4 Manual "archive now" HTTP endpoint: enqueues a job on demand via the same
      dedup key + same pipeline (NOT a parallel pipeline); setting-gerechte remediation
      path for automation failure (no operator-CLI culture in the Filmbetrieb)
- [x] 5.5 Manual endpoint `// AUTHZ-GATE:` stricter than PDF routes: resolve season chain,
      admit **only** `CostumeDesigner` + `WardrobeSupervisor` (exclude `CostumeAssistant`),
      fail closed; no render/query/upload before the gate passes
- [x] 5.6 Manual press idempotency: a press for a day already archived recently (same
      dedup key) is a no-op — returns existing job id / "already enqueued"; no second
      render or second provider upload

## 6. Provider spike (GATE before external adapter lock)

- [x] 6.1 OpenDAL `services-gdrive`: retry/idempotency under transient failures;
      conditional-write behavior (or documented absence); shared-drive + folder +
      service-account/refresh-token auth; least-privilege scoping
- [x] 6.2 Integration test: upload → idempotent-overwrite → fetch → delete against a
      real/test Google Drive target (or a contract test vs documented semantics)
- [x] 6.3 Transitive licence + RustSec inventory for the chosen client
- [x] 6.4 **Gate decision**: if required semantics are not exposed reliably, swap **only**
      the external adapter to `google-drive3` + `yup-oauth2`; `core`/worker/staging
      unchanged. Otherwise lock the OpenDAL backend

## 7. Tests & CI

- [x] 7.1 Idempotency under redelivery: the same trigger enqueued multiple times yields
      one job and one provider upload
- [x] 7.2 Staging-reuse-on-retry: an external failure does not re-render/re-query; the
      staged bytes + digest are reused and match
- [x] 7.3 Dedup-key uniqueness across {kind, day, snapshot, locale, template_version}
- [x] 7.4 Dead-letter after exhausted retries; reconciliation finalizes/flags stranded
      jobs + staged objects
- [x] 7.5 Shared-budget behavior: a backup burst cannot starve HTTP renders (and vice
      versa) against the shared semaphore
- [x] 7.6 No-credential-logging and no-bytes-in-errors assertions (`gitleaks` clean)
- [x] 7.7 `cargo deny check bans` + `cargo test -p architecture_tests` pass; `core`
      boundary stays clean with the port added
