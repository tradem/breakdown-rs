<!--
  Authors: Tobias Rademacher (@tradem) — domain stakeholder & spec author
           glm-5.2 (neuralwatt) — coding agent / co-author
-->

## Context

`add-report-rendering-and-pdf-routes` delivers deterministic PDF reports on demand via
HTTP. ADR-022 D6 additionally requires **automated archival** — durable, retry-safe
backup of each shoot-day report PDF to configurable external object storage (Google
Drive first) — so productions hold an authoritative off-system copy. Archival is an
infrastructure operation: triggered as a trusted service job scoped to a season and a
configured destination, never a public authorization bypass, dispatching no SierraDB
command, mutating no aggregate, emitting no domain event.

The key design constraint (ADR-022 D6) is the **staging-then-external** pipeline:
the complete PDF and a content digest are first written to durable internal
Garage/S3 staging; only that exact staged object is uploaded to the external provider
with an idempotent destination key; the provider outcome is persisted before staging
retention is applied. An external upload failure never discards the only rendered
copy; retries reuse the staged object so they cannot diverge from the bytes the
snapshot produced. The worker uses the same `ReportRenderer` and the same
bounded-rendering budget as the HTTP path (a backup burst cannot starve requests).

The third ADR-022 spike unknown belongs to this change: whether OpenDAL's
`services-gdrive` backend reliably exposes the authentication, shared-drive, folder,
refresh-token/service-account, conditional-write, and idempotent-overwrite semantics
the worker relies on. If not, **only** the Google Drive adapter swaps to the MIT
`google-drive3` + `yup-oauth2` client — the `core` port, renderer, worker, and
Garage staging are unchanged. S3/GCS/WebDAV remain selectable via other OpenDAL
backends without touching `core`.

## Goals / Non-Goals

**Goals:**
- Define `ReportArchiveStorage` as a CRUD port in `core` (precedent: `PhotoStorage`),
  idempotent, with deterministic keys and typed errors; never leaking
  Google/OpenDAL types.
- Implement durable internal Garage/S3 staging + an external provider adapter
  behind the same port.
- A durable report-job table (separate schema, static-SQL-only) with deterministic
  dedup over {kind, shooting-day, trigger/snapshot identity, locale, template version}.
- An idempotent backup worker: render (shared budget) → staging (+ digest) → external
  (idempotent key) → persist outcome → staging retention.
- Bounded retries with exponential backoff; exhausted retries → observable
  failed/dead-letter state; periodic reconciliation of jobs and staged objects
  stranded by crashes.
- Triggers: a configured schedule, a `ShootingDayWrapped` reaction, **and a manual
  "archive now" HTTP endpoint** (the setting-gerechte remediation path for automation
  failure; gated to `CostumeDesigner` + `WardrobeSupervisor`).
- Spike-gated provider choice (OpenDAL `services-gdrive` vs `google-drive3` fallback).

**Non-Goals:**
- ~~Public HTTP endpoints that enqueue backups~~ — **moved into v1 scope** (the manual
  "archive now" trigger is now a first-class trigger; setting-gerechte remediation
  for automation failure, gated to `CostumeDesigner` + `WardrobeSupervisor`).
- Real-time/push notifications of backup status (status observable via job state).
- Multi-tenant provider account management UI.
- Archival of assets other than the three report PDFs.
- Changing the `ShootingDay` aggregate or its events (the reaction is a projector-side
  job enqueue; the aggregate is unchanged).
- Re-implementing the renderer or bounded-rendering budget (consumed from change 1).

## Decisions

### D1. `ReportArchiveStorage` is a CRUD port in `core` (precedent: `PhotoStorage`)

`ReportArchiveStorage` follows the non-CQRS CRUD-port precedent of `PhotoStorage`,
but is a **separate port**: report artifacts have deterministic keys, content
digests, retention, and remote object identifiers rather than `PhotoId` variants.
Operations: idempotent `put(key, bytes, content_type, digest)`, `fetch(key)`,
`delete(key)`, `exists(key)`. The port API SHALL NOT expose Google Drive, OpenDAL, or
storage-key-layout internals; key layout for staging vs external is an adapter detail
implemented against the same trait by distinct injected instances.

### D2. Durable job lifecycle in `infra`, not a domain aggregate (SSOT guardrail)

The report backup job is **infrastructure state, not a domain aggregate**. It carries
NO business truth: business state lives exclusively in aggregates + events (EventStorming
contract) and in the replay-derived Postgres projections (single source of truth for
reads). The job table is operational plumbing — it records *that* a backup was requested,
*where* bytes were staged, and *whether* the provider accepted them. It SHALL NOT be a
source of business facts; it SHALL NOT shadow, duplicate, or supersede any event,
aggregate, or projection, and no domain query path reads from it. This is the explicit
EventStorming / single-source-of-truth guardrail the stakeholder required.

If PostgreSQL is used for the queue, its schema is **separate** from business
projections; every claim, insert, and update uses static SQL literals with bound
values (AGENTS.md hard rule — no string-interpolated SQL, enforced by the
`no-string-interpolation-sql` CI job). Redelivered triggers are deduplicated by a key
composed of report kind, shooting-day ID, trigger/snapshot identity, locale, and
template version. A job row carries: dedup key, kind, day ID, locale, template version,
staged-object handle + digest, provider outcome (ID/ETag + timestamp), retry count,
status, and materialized audit fields. A periodic reconciliation pass detects jobs and
staged objects stranded by crashes.

### D3. Idempotent staging-then-external pipeline

The worker performs the same authorized-by-service-scope read and the same `ReportRenderer`
as the HTTP path, then:

1. writes the complete PDF and content digest to durable internal Garage/S3 staging
   through an injected `ReportArchiveStorage` (the staging instance);
2. uploads that **exact** staged object to the configured external
   `ReportArchiveStorage` (the provider instance) with an idempotent destination key;
3. records the provider object ID/ETag and success **before** applying the staging
   retention policy.

The staged Garage object is reused on exponential-backoff retries: a retry does **not**
re-query a newer projection or regenerate different bytes. An external upload failure
never discards the only rendered copy. Garage staging is durable object storage, not an
ephemeral process file or container volume. Retries are bounded; on exhaustion the job
moves to an observable failed/dead-letter state requiring operator action (no silent
infinite retry). Sensitive PDF bytes and provider credentials are never logged.

### D4. Shared bounded-rendering budget; render is the gateway

The worker renders via the same `ReportRenderer` and the same process-wide render
semaphore introduced in `add-report-rendering-and-pdf-routes`, so a backup burst cannot
starve HTTP requests (and vice versa). Rendering uses a wall-clock deadline and the
configured input/page bounds; a render that fails (e.g. `PageLimitExceeded`) marks the
job failed without staging partial bytes. The worker never renders outside the shared
budget.

### D5. Triggers: schedule, `ShootingDayWrapped` reaction, and manual "archive now"

Three job-enqueue triggers, all idempotent via the same dedup key and all using the
same pipeline (a new trigger is only a new enqueue source, never a parallel pipeline):

- **Schedule** — a configurable periodic ticker enqueues archival jobs per the operator
  policy (e.g. nightly, or per-day-on-wrap). Idempotent via the dedup key.
- **`ShootingDayWrapped` reaction** — when the day is "closed for planning" (the same
  event that makes the Soll-Ist report `final`), a projector reaction enqueues an
  archival job for that day's reports. This is a trusted service job scoped to an
  explicit season and configured destination — it is **not** a public authorization
  bypass; HTTP PDF routes retain their `AUTHZ-GATE`, and the service job enforces its
  own season-scoped authorization internally.
- **Manual "archive now"** — a public HTTP endpoint that enqueues an archival job on
  demand. This is the **setting-gerechte remediation path** for cases where automation
  fails or is delayed (the Filmbetrieb has no operator-CLI culture; a button in the
  web app is the only accepted remediation tool). It is **not** a double-trigger at
  the `Wrapped` moment (where automation fires immediately) — it is a *fallback used
  specifically when automation has not*. The manual trigger SHALL reuse the same
  dedup key (so a manual press for an already-recently-archived day is a no-op) and
  the same pipeline. It is gated by a stricter `AUTHZ-GATE` than the PDF HTTP routes:
  only `CostumeDesigner` and `WardrobeSupervisor` season members may enqueue
  manually (`CostumeAssistant` is excluded) — manual archival is a deliberate
  remediation action, not for every season assistant.

#### Why the manual endpoint moved from "defer" into v1

The earlier "lean: defer" was reversed because a stakeholder pointed out that the
Filmbetrieb setting has no operator-CLI culture; when the schedule misses or the
`Wrapped` reaction fails to fire, the only accepted remediation path is a button in
the web UI, not a shell command. Deferring the endpoint to a follow-up would defer
the *remediation capability itself*, leaving v1 with no human-recoverable failure
path except waiting for the next schedule tick. The added cost — a public
`AUTHZ-GATE` surface — is accepted as necessary for the setting, and the role gate
(`CostumeDesigner` + `WardrobeSupervisor`) bounds it to a deliberate action.

### D6. Provider abstraction & spike-gated choice

The external `ReportArchiveStorage` adapter is provider-pluggable. OpenDAL's real
`services-gdrive` backend is the first Google Drive implementation to evaluate. A spike
MUST prove shared-drive, folder, refresh-token/service-account, conditional-write, and
idempotent-overwrite behavior. If those semantics are not exposed reliably, **only** the
Google Drive adapter swaps to the MIT `google-drive3` client with `yup-oauth2`
(MIT OR Apache-2.0); the `core` port, renderer, worker, and Garage staging are unchanged.
S3, GCS, or WebDAV can be selected by configuration through other OpenDAL backends
without changing `core`.

## Risks / Trade-offs

- **[Provider idempotency / shared-drive semantics]** → OpenDAL `services-gdrive` may
  not expose conditional writes or idempotent overwrite reliably. Mitigation: spike
  before merge; fallback to `google-drive3` + `yup-oauth2` swaps only the adapter.
- **[Stranded jobs / staged objects after crashes]** → a worker crash mid-pipeline can
  leave a staged object with no finalized job or a job with no provider outcome.
  Mitigation: periodic reconciliation + dead-letter on exhausted retries; staging
  retention policy keeps objects long enough to recon.
- **[Credential leakage]** → provider credentials and PDF bytes must never be logged.
  Mitigation: typed errors carry no bytes; env-only secrets; `gitleaks`; least-privilege
  folder/bucket scopes; TLS.
- **[Job table in Postgres] → business-projection coupling]** → Mitigation: separate
  schema; FK-to-read-model-day-id for integrity only; never writes to business
  projections; static-SQL-only.
- **[Re-render divergence on retry]** → if a retry re-queried the projection, bytes
  could differ. Mitigation: retries reuse the staged object; no re-query/re-render on
  retry; digest recorded for verification.
- **[Backup burst starves HTTP]** → Mitigation: shared semaphore budget (D4) + bounds.

## Spike (gate before provider lock)

The archival provider spike MUST produce written evidence before the external adapter
is locked:

- OpenDAL `services-gdrive` retry/idempotency under transient failures; conditional-write
  behavior (or a documented absence); shared-drive + folder + service-account/refresh-token
  authentication flow; least-privilege scoping.
- An integration test exercising upload → overwrite-idempotent → fetch → delete against a
  real/test Google Drive target (or a contract test against the documented semantics).
- Transitive licence + RustSec inventory for the chosen client (`google-drive3`,
  `yup-oauth2`, or OpenDAL's `services-gdrive` feature).

**Gate outcome:** if the required semantics are not exposed reliably, switch only the
external adapter to `google-drive3` + `yup-oauth2` (`core` port/worker/staging
unchanged). Otherwise lock the OpenDAL backend.

## Migration Plan

1. **Core**: add `ReportArchiveStorage` port + `ReportStorageError` to
   `crates/core/src/reporting/`. No infra deps; arkitech boundary stays clean.
2. **Schema**: add the dedicated report-job schema/table (dedup key UNIQUE,
   staged-handle, provider-outcome, retries, status). Static SQL literals; migration
   reviewed by the `no-string-interpolation-sql` job.
3. **Infra storage**: OpenDAL Garage/S3 staging adapter (`ReportArchiveStorage` impl #1).
4. **Infra backup**: durable worker (`crates/infra/src/reporting/backup.rs`) — claim,
   render (shared budget), staging+digest, external upload (idempotent key), persist,
   retention; backoff + dead-letter + recon.
5. **External provider**: implement against `ReportArchiveStorage` via OpenDAL
   `services-gdrive`; run the spike; swap to `google-drive3` fallback only if gated.
6. **Triggers**: scheduled ticker + `ShootingDayWrapped` projector reaction (separate
   job enqueue; no aggregate change) + manual "archive now" HTTP endpoint (gated to
   `CostumeDesigner` + `WardrobeSupervisor`, fail-closed `AUTHZ-GATE`).
7. **`main.rs`**: construct staging + external `ReportArchiveStorage` instances, the
   worker against the shared render budget; env-driven provider config.
8. **CI**: idempotency-under-redelivery, staging-reuse-on-retry, dedup uniqueness,
  dead-letter, recon, provider spike, no-credential-logging assertions.

## Resolved Decisions

- **`template_version` is a compile-time constant**, baked into the binary from the
  immutable embedded templates. Because templates are trusted static assets, a
  template change produces a new binary with a new `template_version`, which naturally
  re-archives (the dedup key changes). It is NOT a runtime knob.
- **Job table lives in the same Postgres as projections, in a separate schema, static
  SQL only** — and ONLY because it does not violate EventStorming / single-source-of-
  truth (D2 guardrail): the table is operational state, holds no business facts, and no
  domain query reads from it. FK-to-read-model-day-id is for integrity only; the table
  never writes to business projections.

## Open Questions

- Exact staging retention window vs reconciliation interval (lean: retention a small
  multiple of the recon interval so crashed jobs can be finalized from staging).
