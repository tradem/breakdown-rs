<!--
  Authors: Tobias Rademacher (@tradem) — domain stakeholder & spec author
           deepseek-v4-flash (opencode-go) — coding agent / co-author

  Synced from change: add-report-archival-backup
-->

# Report Archival

## Purpose

Provides durable, retry-safe automated backup of shoot-day report PDFs to
configurable external object storage (Google Drive, S3, GCS, WebDAV). Archival
is an infrastructure operation — it is triggered as a trusted service job scoped
to a season and a configured destination, dispatches no SierraDB command,
mutates no aggregate, and emits no domain event.

## Requirements

### Requirement: ReportArchiveStorage is a CRUD port in core

The system SHALL define a `ReportArchiveStorage` trait in `crates/core/src/reporting/`
following the non-CQRS CRUD-port precedent of `PhotoStorage`, but as a **separate port**
(report artifacts have deterministic keys, content digests, retention, and remote object
identifiers rather than `PhotoId` variants). Operations SHALL be idempotent:
`put(key, bytes, content_type, digest)`, `fetch(key)`, `delete(key)`, and `exists(key)`,
over a deterministic key type. The port SHALL NOT expose Google Drive, OpenDAL, or
storage-key-layout internals; the same trait SHALL be implemented by distinct injected
instances for internal staging and the external provider. The system SHALL define typed
`ReportStorageError` values that carry no PDF bytes and no provider credentials. `core`
SHALL gain no dependency on OpenDAL, `google-drive3`, `sqlx`, or Axum.

#### Scenario: Port is provider-neutral
- **WHEN** a worker calls `ReportArchiveStorage::put`
- **THEN** it passes only a deterministic key, bytes, content type, and digest
- **AND** the provider (OpenDAL `services-gdrive`, `google-drive3`, S3/GCS/WebDAV) is an
  adapter detail behind the same trait

#### Scenario: Two injected instances share the trait
- **WHEN** the worker writes to staging and to the external provider
- **THEN** both calls go through `ReportArchiveStorage`
- **AND** each is a distinct injected adapter instance

#### Scenario: Errors carry no secrets
- **WHEN** a storage operation fails
- **THEN** the returned `ReportStorageError` carries no PDF bytes and no credentials
- **AND** the failure is observable without logging sensitive material

### Requirement: Durable report-job lifecycle as infrastructure state

The system SHALL model the report backup job as infrastructure state in a PostgreSQL
schema **separate** from business projections. Every claim, insert, and update SHALL use
static SQL literals with bound values (no string-interpolated SQL). Redelivered triggers
SHALL be deduplicated by a key composed of report kind, shooting-day ID, trigger/snapshot
identity, locale, and template version. The job state SHALL record the dedup key, kind,
day ID, locale, template version, staged-object handle + content digest, provider
outcome (object ID/ETag + timestamp), retry count, and status. The job table SHALL NOT
write to business projections.

#### Scenario: Dedup across redelivered triggers
- **WHEN** the same trigger (kind + day + snapshot + locale + template version) is
  enqueued multiple times
- **THEN** exactly one job is created and exactly one provider upload occurs

#### Scenario: Static SQL only
- **WHEN** the job table's queries are audited
- **THEN** every statement sent to `sqlx::query*` is a static literal with dynamic values
  bound via `.bind()`
- **AND** the `no-string-interpolation-sql` CI job passes

#### Scenario: Separate from business projections
- **WHEN** a job is running
- **THEN** no write occurs to any business projection table
- **AND** integrity relies only on a read-side FK to the shooting-day id

#### Scenario: Job table is not a source of business truth (SSOT)
- **WHEN** the job table is consulted
- **THEN** it records only operational state (that a backup was requested, where bytes
  were staged, whether the provider accepted them)
- **AND** it SHALL NOT shadow, duplicate, or supersede any event, aggregate, or projection
- **AND** no domain query path reads from the job table (it is not a business fact store)

### Requirement: Idempotent staging-then-external backup pipeline

The worker SHALL perform an authorized-by-service-scope read and the same `ReportRenderer`
as the HTTP path, then: (1) write the complete PDF and content digest to durable internal
Garage/S3 staging; (2) upload that exact staged object to the configured external provider
with an idempotent destination key; (3) record the provider object ID/ETag and success
**before** applying the staging retention policy. An external upload failure SHALL never
discard the only rendered copy; retries SHALL reuse the staged object with exponential
backoff and SHALL NOT re-query the projection or re-render (the digest SHALL match).
Garage staging SHALL be durable object storage, not an ephemeral process file or container
volume. Retries SHALL be bounded; on exhaustion the job SHALL move to an observable
failed/dead-letter state requiring operator action. Sensitive PDF bytes and provider
credentials SHALL never be logged.

#### Scenario: Staged object is reused on retry
- **WHEN** an external upload fails and is retried
- **THEN** the retry re-uploads the exact staged object
- **AND** the projection is not re-queried and the PDF is not re-rendered
- **AND** the content digest matches the staged object

#### Scenario: External failure never loses the only copy
- **WHEN** an external upload fails after staging succeeded
- **THEN** the staged Garage object remains
- **AND** the job is retried (and eventually dead-lettered), not discarded

#### Scenario: Bounded retries with dead-letter
- **WHEN** retries are exhausted
- **THEN** the job moves to an observable failed/dead-letter state
- **AND** operator action is required (no silent infinite retry)

#### Scenario: Reconciliation of stranded jobs
- **WHEN** a crash leaves a job or staged object in an inconsistent state
- **THEN** a periodic reconciliation pass detects and finalizes or dead-letters it

#### Scenario: No sensitive material logged
- **WHEN** the worker runs or fails
- **THEN** PDF bytes and provider credentials are not logged
- **AND** typed errors carry no bytes or credentials

### Requirement: Shared bounded-rendering budget

The backup worker SHALL render via the same `ReportRenderer` and the same process-wide
render semaphore introduced for the HTTP path, so a backup burst cannot starve HTTP
renders (and vice versa). Rendering SHALL use the configured wall-clock deadline and
input/page bounds. A render failure (e.g. `PageLimitExceeded`) SHALL mark the job failed
without staging partial bytes.

#### Scenario: Backup does not starve HTTP
- **WHEN** a burst of backup jobs runs concurrently with HTTP render requests
- **THEN** both contend for the same shared semaphore budget
- **AND** neither path can exhaust the other's budget

#### Scenario: Render failure is not staged
- **WHEN** a report render fails (bounds, page limit, compiler failure, timeout)
- **THEN** the job is marked failed
- **AND** no partial bytes are staged or uploaded

### Requirement: Triggered archival via schedule, ShootingDayWrapped reaction, and manual "archive now"

The system SHALL enqueue archival jobs via three triggers, all idempotent via the same
dedup key and all using the same pipeline (a new trigger is only a new enqueue source,
never a parallel pipeline): a configured schedule, a reaction to the `ShootingDayWrapped`
event (the day is "closed for planning"), **and a manual "archive now" HTTP endpoint**.
The schedule and `ShootingDayWrapped` triggers are trusted service jobs scoped to an
explicit season and configured destination and are **not** a public authorization bypass.
The manual trigger is the **setting-gerechte remediation path** for cases where
automation fails or is delayed (the Filmbetrieb has no operator-CLI culture; a web-UI
button is the only accepted remediation tool). The manual trigger SHALL be gated by a
stricter `AUTHZ-GATE` than the PDF HTTP routes: only `CostumeDesigner` and
`WardrobeSupervisor` season members may enqueue manually (`CostumeAssistant` is
excluded) — manual archival is a deliberate remediation action, not for every season
assistant. The manual trigger SHALL fail closed on lookup or policy errors and SHALL
NOT render, query, or upload before the gate passes. All three triggers dispatch no
SierraDB command, mutate no aggregate, and emit no domain event. HTTP PDF routes
SHALL retain their `AUTHZ-GATE` handler-internal authorization unchanged.

#### Scenario: Schedule enqueues idempotently
- **WHEN** the scheduled ticker fires
- **THEN** it enqueues jobs per the operator policy
- **AND** redeliveries are deduplicated by the dedup key

#### Scenario: ShootingDayWrapped enqueues archival
- **WHEN** a `ShootingDayWrapped` event is projected
- **THEN** an archival job is enqueued for that day's reports
- **AND** no aggregate is changed and no command is dispatched

#### Scenario: Service jobs are not an authz bypass
- **WHEN** the worker or the schedule/wrap trigger runs
- **THEN** it enforces season-scoped authorization internally against a configured destination
- **AND** HTTP PDF routes retain their `AUTHZ-GATE` handler-internal check unchanged

#### Scenario: Manual "archive now" is gated to CostumeDesigner and WardrobeSupervisor
- **WHEN** an authenticated active season member with role `CostumeDesigner` or
  `WardrobeSupervisor` requests a manual archive for a shooting day
- **THEN** the handler resolves the season chain, passes the `// AUTHZ-GATE:` check,
  enqueues a job via the same dedup key and pipeline, and returns the job id

#### Scenario: CostumeAssistant is denied at the gate
- **WHEN** an authenticated active season member with role `CostumeAssistant` requests a
  manual archive
- **THEN** the handler returns `403` under a literal `// AUTHZ-GATE:` comment
- **AND** no job is enqueued, no render occurs, no command is dispatched

#### Scenario: Lookup error is fail-closed
- **WHEN** the shooting-day → season chain cannot be resolved
- **THEN** the manual endpoint returns an error and enqueues nothing

#### Scenario: Manual press is idempotent against a recent archive
- **WHEN** a manual "archive now" is pressed for a day that was already archived
  recently (same dedup key)
- **THEN** the press is a no-op (returns the existing job id or "already enqueued")
- **AND** no second render or second provider upload occurs

#### Scenario: Manual press is not a double-trigger at the wrap moment
- **WHEN** a `ShootingDayWrapped` reaction has already enqueued for the same day
- **THEN** a manual press for that day is a no-op via the dedup key
- **AND** the manual trigger is only meaningfully invoked when automation has failed
  or is delayed

### Requirement: Provider-pluggable external storage with spike-gated Google Drive

The external `ReportArchiveStorage` adapter SHALL be provider-pluggable. OpenDAL's
`services-gdrive` backend SHALL be the first Google Drive implementation. A spike MUST
prove shared-drive, folder, refresh-token/service-account, conditional-write, and
idempotent-overwrite behavior before the adapter is locked. If those semantics are not
exposed reliably, **only** the Google Drive adapter SHALL swap to the `google-drive3`
client with `yup-oauth2`; the `core` port, renderer, worker, and Garage staging SHALL
remain unchanged. S3, GCS, or WebDAV SHALL be selectable by configuration through other
OpenDAL backends without changing `core`.

#### Scenario: Spike gates the provider
- **WHEN** the OpenDAL `services-gdrive` backend is evaluated
- **THEN** retry/idempotency, conditional-write, and auth semantics are demonstrated
- **AND** a transitive licence + RustSec inventory is recorded before merge

#### Scenario: Fallback changes only the adapter
- **WHEN** the spike fails for Google Drive
- **THEN** only the external adapter swaps to `google-drive3` + `yup-oauth2`
- **AND** the `core` port, worker, and Garage staging are unchanged

#### Scenario: Other backends selectable by config
- **WHEN** an operator selects S3/GCS/WebDAV
- **THEN** the external adapter uses the corresponding OpenDAL backend
- **AND** no `core` change is required
