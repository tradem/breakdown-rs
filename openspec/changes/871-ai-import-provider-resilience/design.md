<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# Design — 871 provider resilience

## Context

The AI import pipeline has **two nested retry layers** that both key on
`DomainError::ServiceUnavailable`:

1. **In-attempt, per chunk.** `retry_chat`/`retry_schedule` →
   `retry_bounded` (`crates/infra/src/ai/workers.rs:3989`) retries a transient
   provider failure `AiImportBounds::max_retries` (=5) times with
   `compute_backoff(attempt, 30s)` (base 500 ms doubling, cap 30 s, ≤25 % jitter —
   `crates/infra/src/projectors/supervisor.rs:90`). "Transient" is the reused
   photo-saga helper `is_transient` (`crates/infra/src/photo/sagas/mod.rs:116`),
   which matches the `ServiceUnavailable` shape — and since #822 that shape
   carries the provider code `ai-import.llm-provider-unavailable` for LLM
   provider faults.
2. **Job-level.** `mark_failed(…, retryable)` (`crates/infra/src/ai/queue.rs:865`)
   increments `retries`, sets `failed` +
   `next_attempt_at = now() + LEAST(1 min · 2^retries, 6 h)`, and appends an
   `ai_import.ai_import_job_attempt` row; `dead_letter` once
   `retries + 1 >= max_retries`. All four claim paths (`claim_next`,
   `claim_next_kind`, `claim_next_reconciling`, `claim_next_kind_reconciling` —
   `queue.rs:379/433/500/556`) re-claim a `failed` job whose `next_attempt_at` is
   due, and each of them nulls `progress` (deliberate, #664).

Neither layer knows anything about provider health, and nothing per chunk is
persisted:

- **No breaker, no health signal.** Nothing pauses the worker loops
  (`worker_loop.rs`) or skips a claim. The only health surface is the public
  `GET /v1/health` (DB/SierraDB/projectors).
- **A re-claimed attempt starts from zero.** Source bytes are re-loaded and
  re-chunked (deterministic and cheap), then the worker iterates `chunks` from
  index 0 with `progress.chunk = Some(0)`; extracted scenes accumulate **in
  memory** (`context.scenes`) and the preview is only written at the end
  (`storing_preview` → `mark_succeeded`). A kill between two chunks loses every
  paid call of that attempt.
- **The cost snapshot is per attempt.** Telemetry and `CostBreakdown` are written
  on the successful completion only, so the wasted spend of failed attempts is
  invisible in the job's cost breakdown.
- **Effective cost ceiling per chunk today:** `1 + max_retries` in-attempt calls
  **times** `max_retries` job attempts = up to 25 paid calls for the same chunk
  before anything is surfaced, each holding a concurrency permit for up to
  `request_timeout_secs` (120 s).

Two facts shape every decision below:

- **The job row does not know its provider.** `resolve_config` resolves the
  user's active AI config per attempt (`worker_loop.rs:181`); the job carries
  `user_id`, not `(provider, model)`. Any claim-side filter needs that pair on
  the row.
- **`GET /v1/health` cannot host a provider check.** It is unauthenticated with a
  2 s per-check timeout (`crates/api/src/health.rs`, `HEALTH_CHECK_TIMEOUT`), and
  a provider probe needs a vaulted key. A public check either cannot run or leaks
  topology.

## Goals / Non-Goals

**Goals:**

- An open breaker costs **zero** paid calls and **zero** retry budget; the job
  waits in a state the surface can explain, with a resume time and a deadline.
- A retried attempt resumes at the first uncompleted chunk; the provider is never
  asked to re-extract a chunk that already produced a result.
- The job's cost snapshot counts every paid call once across attempts.
- Every state change is operable: an operator can answer "is the breaker open,
  since when, which jobs are held" from the durable row (runbook SQL) and a
  greppable log marker.
- Recovery is provable without wall-clock gating: call counts and computed bounds
  only.

**Non-Goals:** see `proposal.md` (failover, refunds, #822's surface, #809's
reachability seam, a public provider-health endpoint, apply-run resume).

## Decisions

### D-A1 — The verdict is scoped per `(provider, model)`

The breaker key is exactly the pair `resolve_config` yields
(`AiWorkerConfig.provider` + `.model`). Rationale:

- A degraded endpoint is a property of **the endpoint**, not of a document: per
  job (option a) makes every queued job pay to discover the same outage.
- Global (option c) couples unrelated users, and one user's *permanent* failure
  (revoked/over-quota key) would stop every other user on a healthy endpoint.
- `(provider, model)` is sufficient because `provider` already determines the
  curated base URL (`provider_registry.rs`); there is no per-user custom base URL
  that could make two pairs indistinguishable.

**Only retryable provider failures count toward opening.** The classifier is the
`ServiceUnavailable` shape **and** the provider code
`ai-import.llm-provider-unavailable`. A revoked key, a bad model or an
entitlement 4xx is `dependency.auth-failed`-class permanent (#637) and must
never open a breaker: it would convert one user's misconfiguration into an
outage for everyone on that endpoint. Mapping-DB, pricing-read-model,
payload-storage and catalog-*parse* failures keep `domain.service-unavailable`
and never count either.

The probe needs a usable credential, so **it is performed by the worker that
observed the failure** (it holds the key for its job) — never by a synthetic or
shared credential. No job for a pair ⇒ no probe ⇒ the breaker closes lazily on
the next real call.

### D-A2 — The state is durable, and the claim filter runs in SQL

New table (PR A):

```sql
CREATE TABLE ai_import.provider_health (
    provider              text        NOT NULL,
    model                 text        NOT NULL,
    state                 text        NOT NULL DEFAULT 'closed'
                          -- Three values only: `expired` (D-C4) is a *job-hold*
                          -- state, never a breaker state, so this CHECK rejects it.
                          CHECK (state IN ('closed', 'open', 'half_open')),
    consecutive_failures  integer     NOT NULL DEFAULT 0,
    opened_at             timestamptz,
    retry_at              timestamptz,
    probe_owner           text,
    probe_started_at      timestamptz,
    flap_count            integer     NOT NULL DEFAULT 0,
    last_failure_at       timestamptz,
    -- When the breaker last closed (D-A6): the stable-window test on the next
    -- `closed → open` reads it, so a flap is counted where a new outage starts.
    closed_at             timestamptz,
    -- Fence of the *current* probe lease (D-A6). A fresh UUIDv7 per probe
    -- attempt, because `probe_owner` alone is not unique: the same worker (or
    -- task instance) can reacquire the lease, and a stale result would then pass
    -- an owner check. Both result writes match on `probe_lease_id`.
    probe_lease_id        uuid,
    updated_at            timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (provider, model)
);
```

Durable, not an in-process `watch` channel:

- The filter has to happen **atomically with the claim** (`FOR UPDATE SKIP
  LOCKED` already picks the row; a second in-process check is a TOCTOU). That is
  a SQL predicate, so the state must be in Postgres.
- A multi-replica deployment keeps N independent verdicts if the state is
  in-process: replica B keeps paying for an outage replica A already proved.
- A restart forgets an in-process verdict, which is exactly when a fresh
  cold-start fleet re-pays the first failure. The permit and the lease are
  durable for the same reason; the SSE hub is in-process because losing a
  wake-up is harmless (the poll recovers it). A lost breaker verdict is not
  harmless.

No `pg_notify` is added for the breaker: the *user-facing* signal is the job row,
which `mark_held` notifies through the existing hub; the breaker row itself is
operator-facing.

Claim predicate, added to **all four** claim paths (they are four copies of one
statement and must stay one semantics):

```sql
AND NOT EXISTS (
    SELECT 1 FROM ai_import.provider_health ph
    WHERE ph.provider = job.provider
      AND ph.model    = job.model
      AND ph.state <> 'closed'
)
```

**Only `closed` admits a claim — `retry_at` is the probe schedule, not a claim
gate.** An earlier draft also required `ph.retry_at > now()`, which would have
lifted the filter the moment the probe became due: at that instant the breaker is
`half_open`, so every queued job of the pair would have been claimed and would
have issued its paid first chunk — a queue drain instead of one probe, re-paying
the outage the breaker just proved. Only the probe (D-A6) may end a non-`closed`
state.

### D-A2b — The job snapshots `(provider, model)` at enqueue

New columns `provider text`, `model text` on `ai_import.ai_import_job`, filled
from the user's active AI config **at the API edge** (the only legitimate
read-model consumer; precedent: the `target` snapshot #771 and
`source_file_name` #763). `NULL` for every pre-#871 row and for an upload whose
config could not be resolved — the claim predicate then simply does not filter
that job, which is the honest degradation.

The same pair is what PR B fingerprints the chunk set with (D-B7), so the column
is not A-specific.

**Staleness is handled by three layers, because a snapshot-only filter could
strand a job.** A user may change their AI config between upload and attempt,
and the claim filter runs **before** `resolve_config` — so a filter that trusts a
stale snapshot could refuse a job forever (the worker that would re-check never
gets it). The layers:

1. **Propagation at the config-change edge.** Writing the user's AI config also
   stamps the pair onto that user's runnable jobs in one statement
   (`UPDATE ai_import.ai_import_job SET provider = $1, model = $2 WHERE user_id =
   $3 AND status IN ('pending', 'failed')`). The config write is an API-edge
   operation, so no write-side path gains a read-model query.
2. **The re-check after `resolve_config`** (authoritative — that is the pair the
   attempt will actually call), with a stamp-refresh when it differs.
3. **A backstop that cannot be missed:** opening the breaker materializes the
   hold on every runnable job of that pair (D-A4) and holds expire through a
   claim-free sweeper (D-C4). A job can therefore never be *silently* stranded by
   a stale snapshot — worst case it waits one breaker window and is then
   either claimed (breaker closed) or dead-lettered with the provider narrative
   (hold expired).

A pre-#871 or config-unresolvable job has `provider`/`model` `NULL`; the claim
predicate does not filter it, which is the honest degradation.

### D-A3 — Detection: open reactively, close on a cheap probe (option c)

- **Open** when `consecutive_failures >= AI_IMPORT_BREAKER_FAILURE_THRESHOLD`
  (default **3**, matching the #822 incident's three 503s) for one pair, observed
  by any worker. Consecutive per **pair**, incremented by a provider failure and
  reset by a success — not per job, not per chunk, so failures from different
  jobs, chunks and replicas accumulate toward the same verdict.
- **Close** only on a successful **cheap probe** or a successful paid call.
  "Elapsed time ⇒ closed" would resume paying into a still-broken endpoint.
- The probe is the existing model-catalog read (`catalog.rs:135`,
  `GET {base}/models`): already implemented, already exercised by the AI-config
  screen (#809), and it costs no tokens. Reactive-only detection (option a) would
  need a canary job that pays to learn the endpoint recovered — exactly what the
  breaker exists to stop.
- **The probe is its own task, not a claimed job.** Because only `closed` admits a
  claim (D-A2), no worker is running for that pair when the probe becomes due, so
  the probe cannot ride on a claim: it is a CAS'd task in the sweeper family
  (D-C4/D-X2), and its credential comes from **one active held job of the pair** —
  the query returns the *job's identity*, not just its user
  (`SELECT id, user_id, document_kind FROM ai_import.ai_import_job
  WHERE provider = $1 AND model = $2 AND status = 'failed'
    AND provider_hold IS NOT NULL
    AND provider_hold ->> 'state' IN ('open', 'half_open')
  ORDER BY created_at LIMIT 1`). The id is kept for the log line (`#871 provider
  breaker` names the donor job) and never re-derived later: re-selecting "a job of
  that user" would be a different job as soon as the first one expires. No permit,
  no chunk, no paid call, no synthetic credential. A pair with no active held job
  has nobody to probe for, which is correct: nothing is waiting on it. The `state`
  predicate matters: the terminal expiry marker (D-C4) also leaves `provider_hold`
  non-null, and an expired job must never be picked as a credential donor.
- **The probe dispatches on provider, because Ollama has no credential at all.**
  `OpenAiCompatibleModelCatalog::list` rejects an empty key
  (`AI_CONFIG_EMPTY_VAULT_KEY`, `catalog.rs:140`) and always sends
  `bearer_auth` — so it cannot probe a local Ollama endpoint, and forcing it to
  would send a bearer token to a plain-HTTP curated origin (CWE-319; the same
  reason `OllamaChatClient` holds no key). An Ollama breaker therefore probes
  **unauthenticated** (`GET {curated ollama base}/api/tags` through the same
  local-only redirect policy), and no vault read happens on that path at all. The
  hosted path keeps `catalog.list(provider, vaulted_key)`. Without this split an
  Ollama breaker could never close.
- **The probe runs in three short steps, never one transaction across the network
  call.** A single transaction containing the lease CAS *and* the request would hold
  the row lock for the whole request (up to `request_timeout_secs`), so a hung probe
  would lock out the very takeover that the lease exists to allow:

  | step | transaction | content |
  |---|---|---|
  | 1 | short, committed | `open → half_open` CAS: `probe_lease_id` (fresh UUIDv7), `probe_owner`, `probe_started_at` |
  | 2 | **none** | the provider request, outside any transaction |
  | 3 | short, committed | the fenced result write (`state = 'half_open' AND probe_lease_id = $3`) |

  Between the steps the breaker row is unlocked, so another tick can take over an
  expired lease — which is exactly why the result write must be fenced by the
  lease token (D-A6) instead of by "I hold the lock".
- **The probe judges reachability only, and it never retires a job.** A probe result
  is a verdict about the endpoint, not about a document:

  | probe outcome | breaker | why |
  |---|---|---|
  | 2xx | **close** | the endpoint answers |
  | transport error / timeout / 429 / 5xx | **stay open**, `retry_at` advanced, flap rule applies | the outage this breaker exists for |
  | 401 / 403 | **close**, log `#871 probe: catalog credential rejected (401/403)` | the endpoint answered — that is what the probe measures. A catalog denial does **not** establish that the credential cannot run a completion: a restricted key may hold `chat.completions` without `models.read`, and a key may even be replaced while the request is in flight |

  So the earlier draft's **retirement** write is **dropped entirely**. It answered a
  problem that the existing machinery already solves correctly: a job whose own
  credential is dead is claimed, fails with `dependency.auth-failed` through the
  existing permanent path (#637, no retry) and terminalizes itself — one request
  per affected job, no new write, and the honest code the client already localizes.
  That also removes the need to fence a retirement against a mid-flight credential
  change: nothing kills a job from a probe, so a key replaced while the probe runs
  can never dead-letter a job that would have worked. The candidate set drains the
  same way (a terminal job leaves `provider_hold IS NOT NULL`).

  A rejected-credential probe does **not** increment `flap_count` — it says nothing
  about the provider's stability — and `PROBE_CANDIDATE_LIMIT` (3) bounds how many
  donor jobs one tick may try.

### D-A4 — A held job stays `failed`; the wait is an additive field, not a status

Adding `waiting_for_provider` to `JobStatus` was rejected: the enum carries
`is_terminal()` and `is_non_resumable()` (`core/src/ai/views.rs:101`), which the
payload-retention, `dev_reset` and claim predicates key on — a fifth case must be
classified correctly in every one of them, plus a new ARB key, glyph and golden in
the client. `#822`'s banner already renders "provider degraded · next attempt at
X"; the honest extension is a *field* on the existing state.

Reusing `pending` was also rejected: `pending` carries no `next_attempt_at`, no
attempt history, and reads as "not started yet" — it hides that the delay is
upstream, which is the defect #822 existed to remove.

The wire addition (additive, `serde(default)`, older clients ignore it):

```rust
pub struct ProviderHold {
    pub provider: LlmProvider,
    pub model: String,
    /// The registered code that opened the hold — today always
    /// `ai-import.llm-provider-unavailable` (no new code, D-X1).
    pub reason_code: String,
    /// `Open | HalfOpen` while waiting, `Expired` on the terminal expiry write
    /// (D-C4) — the state that lets a client tell "the provider did not come
    /// back" from "your retries are used up". `Expired` exists only here (a
    /// job-hold state); the breaker's own `state` column never takes it.
    pub state: ProviderBreakerState,
    /// Breaker's next probe time — also this job's `next_attempt_at`.
    pub until: DateTime<Utc>,
    /// Absolute deadline of the whole hold series (D-C4).
    pub hold_deadline: DateTime<Utc>,
    /// Chunks already paid for and stored; the resume point (D-B2).
    pub chunks_done: u32,
}
```

`AiImportJob.provider_hold: Option<ProviderHold>`.

**Three writers produce a hold, because a job can be excluded before it is ever
claimed.** An owner-fenced write needs a `running` row, and a job whose pair is
already open is never claimed — it would sit `pending` with no reason and no
deadline, which is exactly the invisibility #822 removed. So:

1. **`mark_held`** (owner-fenced, `WHERE status = 'running' AND worker_id = $2`) —
   the migration path of a job that *did* run: mid-run abort (D-A5) or a
   post-`resolve_config` open verdict.
2. **Hold materialization on open** — the `closed → open` transition (D-A6)
   stamps **every runnable job of that pair** (`status IN ('pending')` or `failed`
   with a due `next_attempt_at`) in one statement: `status = 'failed'`,
   `next_attempt_at = retry_at`, `provider_hold = …`, and the **series clock**
   `provider_hold_series_started_at = COALESCE(provider_hold_series_started_at,
   now())` — a *separate* column on the job, because `provider_hold` itself is
   cleared on every close and a deadline stored inside it would restart at 6 h on
   each short recovery (D-C4). No claim, no owner, no provider call — and it
   notifies each returned id through the existing hub.
3. **Hold materialization in the sweeper** (every `AI_IMPORT_PROVIDER_SWEEP_INTERVAL_SECS`) — the same statement, re-run for every pair whose breaker is not
   `closed` and every owed job of that pair whose `provider_hold IS NULL`. The
   open-time write cannot cover two cases, and both would otherwise be **invisible
   and unexpirable**: a job **enqueued while the breaker is already open** (the
   claim predicate excludes it but writes nothing), and a `failed` job whose
   `next_attempt_at` becomes due **after** the opening transition (it was not
   runnable when the transition ran). Idempotent by the `provider_hold IS NULL`
   guard; the sweeper is also what expires these holds (D-C4), so without this
   writer the expiry precondition `provider_hold IS NOT NULL` could never be met.

Only the sweep is a *guarantee*; the transition write is the fast path that makes
an outage visible in the same instant it is detected. The claim-time SQL filter
(D-A2) is neither — it is purely the money-saver that stops the paid call.

The held transition is a **new queue write**, `AiImportQueue::mark_held`,
deliberately *not* `mark_failed`:

| | `mark_failed` (today) | `mark_held` (new) |
|---|---|---|
| `retries` | +1 | **unchanged** |
| attempt row | appended | **none** |
| `status` | `failed` → maybe `dead_letter` | `failed` |
| `next_attempt_at` | job backoff (1 min · 2^retries) | breaker `retry_at` |
| `last_error` | error summary | provider summary (old clients keep the #822 narrative) |
| `progress` | kept (retryable branch) | kept |
| `provider_hold` | cleared | set |
| attempt history | +1 row per failure | **no identical rows** |

`provider_hold` is cleared by every other lifecycle write (claim, `mark_succeeded`,
`mark_failed`, `mark_payload_unavailable`, ordinary dead-letter). The **one
exception** is the hold-expiry write, which keeps the field with
`state = Expired` (D-C4): that marker is the only durable signal separating "the
provider never came back" from "the retry budget is spent", so it must survive
the very terminal transition it records. Every other terminal path clears the
field as before.

### D-A5 — Both pre-claim and mid-run abort, at the chunk boundary

- **Pre-claim:** the SQL filter (D-A2). No claim ⇒ no permit, no source load, no
  call.
- **Mid-run:** after the config is resolved, the worker builds a
  `ProviderHealthGuard` for the resolved pair and consults it at the **chunk
  boundary**, immediately before each chunk's first paid call — the same
  cooperative shape as `heartbeat::claim_lost` (`heartbeat.rs`), which already
  proves a worker can stop mid-run on a durable signal. On open: stop the loop,
  skip the merge/preview, and take the held path (`mark_held`, no retry, no
  attempt row).

The in-flight request is **not** aborted: an aborted HTTP request is not
refunded, so the only honest saving is not *starting* the next one. The overspend
bound is therefore exactly one chunk per worker, which is a property of the
design, not a hope.

### D-A6 — Recovery and flapping: half-open, one CAS prober, escalating minimum-open, bounded flaps

State machine, all transitions as single-statement `UPDATE`s. `flap_count`
escalates the **open** window, so it must be incremented on the transition that
starts a *new* outage — `closed → open` — and not on `half_open → open`, which is
the same outage still failing to clear. The breaker therefore also records
`closed_at`:

| From → To | Trigger | Effect |
|---|---|---|
| `closed → open` | Nth consecutive failure | `opened_at = now()`; `flap_count` = `CASE WHEN closed_at IS NOT NULL AND now() - closed_at < STABLE_WINDOW THEN flap_count + 1 ELSE 0 END`; `retry_at = now() + min_open(flap_count)`; **materialize the hold** on every runnable job of the pair (D-A4) |
| `open → half_open` | `retry_at <= now()` and the **probe task** CASes a fresh `probe_lease_id` (a new UUIDv7 per attempt, with `probe_owner` + `probe_started_at`) | exactly one prober per window; a stale `probe_started_at` (older than the probe lease) lets the next tick take over; no claim is admitted in this state (D-A2) |
| `half_open → closed` | probe (or any paid call) succeeded | `consecutive_failures = 0`, `retry_at = NULL`, `closed_at = now()`, `probe_owner = NULL`; **release** the pair's held jobs (`provider_hold = NULL`) — they are claimable again through their own `next_attempt_at`, which is now in the past; the **hold series clock survives** (D-C4) |
| `half_open → open` | probe failed | `flap_count` **unchanged** (same outage); `retry_at = now() + min_open(flap_count)`; **refresh** every held job of the pair to the new `retry_at` |

**Every probe result is fenced to the lease it belongs to.** A probe can outlive
its lease (a hung `GET /models`), and by then another task may own the state; an
unfenced write would let the stale result close or re-open a state it never
observed. `probe_owner` is therefore **not** the fence — the same owner can
reacquire the lease, and its earlier result would still match. The fence is the
**lease token**: a fresh `probe_lease_id` (UUIDv7) written by the
`open → half_open` CAS and matched by both result writes:

```sql
... WHERE provider = $1 AND model = $2 AND state = 'half_open'
      AND probe_lease_id = $3
```

Zero rows ⇒ the result is discarded (debug log, no state change) — the same
`ensure_claim_owned` discipline every other owner-fenced write in this codebase
uses. `probe_owner` stays for operator readability only. Same-owner reacquisition
is a test case for both outcomes, not an assumption.

`min_open(n) = min(BASE_OPEN · 2^n, MAX_OPEN)` with `BASE_OPEN` 60 s and
`MAX_OPEN` 30 min. The stable-window test lives on `closed → open` because that
is where a *new* flap begins: a provider that a probe just cleared and that fails
again within `STABLE_WINDOW` has flapped. A `closed → open` after a longer closed
period resets `flap_count` to 0 — the provider was genuinely stable, so its
punishment must not be inherited by the next, unrelated incident.

**Held rows follow the breaker.** `mark_held` copies `retry_at` into
`next_attempt_at`/`provider_hold.until`, and a failed probe moves `retry_at` — so
the `half_open → open` transition also rewrites every held job of that pair in the
same statement, returning the ids so each one gets its existing SSE wake-up
(`pg_notify` via the hub). Without it a held job would display a resume time that
has already passed while the claim predicate (which reads the **breaker**, not the
job) keeps it unclaimable.

That is the bound the issue asks for: a provider that answers once and fails
again **cannot** loop open/closed at a fixed rate — every flap lengthens the open
window geometrically up to the cap, so probe frequency decays rather than
oscillating. A flapping provider settles at one probe per 30 min at worst.

Observability (D-X2): every transition is `tracing::warn!` with the literal marker
`#871 provider breaker` and the fields `provider`, `model`, `state`,
`consecutive_failures`, `retry_at`, `flap_count`; the durable row is the operator
query. The public `GET /v1/health` route is deliberately **not** extended: it is
unauthenticated with a 2 s per-check timeout and a provider probe requires a
vaulted credential — see Context.
`#871 provider breaker` and the fields `provider`, `model`, `state`,
`consecutive_failures`, `retry_at`, `flap_count`; the durable row is the operator
query. The public `GET /v1/health` route is deliberately **not** extended: it is
unauthenticated with a 2 s per-check timeout and a provider probe requires a
vaulted credential — see Context.

### D-B1 — Durability granularity: a chunk table, not a JSONB column

```sql
CREATE TABLE ai_import.ai_import_job_chunk (
    job_id      uuid        NOT NULL
                REFERENCES ai_import.ai_import_job(id) ON DELETE CASCADE,
    chunk_index integer     NOT NULL CHECK (chunk_index >= 0),
    payload     jsonb       NOT NULL,
    usage       jsonb       NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (job_id, chunk_index)
);
```

A single JSONB column on the job row (option a) was rejected on three concrete
grounds:

- **Write amplification:** one write per chunk against a growing document is
  O(n²) bytes for a 128-chunk script; a chunk row is a bounded insert.
- **`updated_at` is load-bearing:** the job row's `updated_at` is the retention
  clock and the payload-GC `ORDER BY` key (the AI-import instructions forbid a
  sweep from touching it), and it is also the ETA anchor `started_at` (#762,
  `claim_next*` writes `updated_at = now()`). Writing it once per chunk re-arms
  both.
- **Observability:** "how many chunks are done" becomes `count(*)`, which is what
  makes resume auditable in SQL instead of by reading a blob.

Registration required (mechanical, easy to forget): `dev_reset/business.rs` table
list (before `ai_import.ai_import_job`), `dev_reset/plan.rs` category, and the
payload-GC sweep (`payload_cleanup.rs`) deletes a terminal job's chunk rows in the
same run as its blobs. The `ai_payload_cleanup` marks stay payload-kind keyed —
the chunk rows are keyed by job, so their delete is idempotent without a new mark.

Cleanup on a *new upload* is impossible by construction: a re-upload of the same
bytes is the `dedup_key` path and returns the **existing** job; different bytes
are a new job id. Rows die on terminal transition and in GC.

### D-B2 — The cursor is the length of the contiguous stored prefix

No `resume_from_chunk` column — a stored cursor can disagree with the rows after a
lost write, a derived one cannot. And no `MAX`: `MAX(chunk_index) + 1` over
indices `0, 1, 3` is `4`, which would resume **past** the missing chunk 2 and
quietly omit it from the preview. The cursor is the first index that is missing:

```sql
SELECT chunk_index FROM ai_import.ai_import_job_chunk
WHERE job_id = $1 ORDER BY chunk_index
```

One ordered read (the merge pass needs all rows anyway) and the **contiguous
prefix** length is computed in Rust: walk the sorted indices from 0 and stop at
the first gap. That value is the resume cursor and `progress.resumed_from`.

A row beyond the gap is unreachable by construction and cannot be applied (the
merge pass is a prefix walk), so it is treated as garbage: the tail is deleted and
the event logged `#871 chunk resume hole at <index>` before extraction resumes at
the hole. Contiguity usually holds (a row exists only after its paid call
returned, and the insert is the last step of the iteration) — the read does not
*rely* on it, which is the point.

`progress.chunk` keeps its documented meaning — "1-based index of the last
**completed** chunk *of this attempt*" (`core/src/ai/views.rs:258`) — so the wire
semantics do not move. A resumed attempt's first frame reports
`chunk = resumed_from`, i.e. the prefix length.

### D-B3 — The stored unit is the parsed chunk result

`payload` is the per-chunk `ScriptContext`-shaped parse result (what
`retry_chat` returns today) plus the chunk's `LlmCallUsage` in `usage`, **not**
the applied scene rows. Insert on completion with
`ON CONFLICT (job_id, chunk_index) DO UPDATE`, so:

- a chunk re-run after a lost write repairs itself by **overwriting** — resume
  stays idempotent without any per-row mapping/reservation machinery;
- the resume unit equals the **paid call**, which is the only unit that matters
  for cost.

**Every chunk write is claim-fenced, like every other worker-originated write — and
the fence is a row lock, not a predicate.** A worker that lost its claim during an
in-flight call must not be able to add a result produced under the *old*
configuration into a chunk set another worker has since invalidated (D-B7). A bare
`INSERT … SELECT … WHERE status = 'running' AND worker_id = $2 AND extraction_key =
$6` would not be enough: under READ COMMITTED that sub-select reads the job row
without a lock, so another session can reclaim the job and rewrite `extraction_key`
between the read and the commit, and the stale write lands anyway. The
`claim_lost` heartbeat check does not close that window either — it is a check, not
a lock.

The write therefore runs in one transaction that **takes the job row first**:

```sql
SELECT status, worker_id, extraction_key FROM ai_import.ai_import_job
 WHERE id = $1 FOR UPDATE;                       -- lock, held to commit
-- verify the row still says running / $2 / $6, else Conflict
INSERT INTO ai_import.ai_import_job_chunk …  ON CONFLICT (job_id, chunk_index) DO UPDATE …;
```

`FOR UPDATE` (not `FOR SHARE`) because the **invalidation path takes the same lock
on the same row**: `provider_hold`-style fingerprint rewrite plus the `DELETE` of
the job's chunk rows also run under `FOR UPDATE` on that job row, in one
transaction. Both writers therefore serialize on one row in one order — job row
first, chunk rows second — which removes the lock-ordering ambiguity instead of
relying on it. A lost claim costs at most one already-paid chunk and can never mix
configurations. Zero rows from the guarded insert means `DomainError::Conflict`,
the same `ensure_claim_owned` discipline as `mark_progress`/`mark_failed`.

The preview is still assembled and applied **once** at the end (today's
behaviour: `context.scenes` accumulate in memory; the preview is written at
`storing_preview`). A resumed attempt loads the stored rows in `chunk_index`
order into that in-memory `context` before extracting the remainder, so a preview
can only exist if every chunk had a result — a crash can never yield a preview
with a hole in it.

### D-B4 — Per-chunk usage; the cost snapshot counts every paid call once

The chunk row carries its own usage. At attempt start the worker seeds
`extraction_usage` from the stored rows, then adds each fresh call's usage as it
lands, so the completion snapshot (`workers.rs:1162` → `CostBreakdown`, #675/#768)
sums **all** chunks of the job regardless of which attempt paid for them:

- a retried import visibly costs more than a clean one — the issue's preferred
  option;
- no double counting, because `ON CONFLICT DO UPDATE` *replaces* a re-run chunk's
  usage instead of adding it;
- keeping usage per attempt only was rejected: with resume the successful attempt
  did not pay for the resumed chunks, so the snapshot would *understate* a
  thrice-retried import — the invisible-waste defect itself.

**The one uncounted case is stated, not hidden:** a call whose response arrived
but whose row never persisted (kill between response and insert) is not in the
snapshot. Its spend is bounded by one chunk per crash, it appears in no other
surface, and that sentence goes into the ai-import instructions next to the
table. A cost card that silently guessed it would be worse.

### D-B5 — Progress and ETA measure from the resume point

Additive `AiImportProgress.resumed_from: Option<u32>` (`serde(default)`, so
pre-#871 frames read as `None`): `Some(n)` means "this attempt continues at chunk
`n + 1`, i.e. `n` chunks are already stored".

- The first extraction frame of a resumed attempt publishes `chunk = Some(n)`
  instead of `Some(0)`; the bar does not snap back to zero.
- The client's rate must use the delta, not `done`: `job_eta.dart:46`
  (`aiJobProgressUnits`) currently derives units from `(chunk, chunks_total)`.
  With `resumed_from = 25` and `chunk = 25`, a naive rate would report "25 chunks
  in one second". The client therefore computes the rate from
  `chunk - resumed_from` against `started_at`, and the *remaining* count from
  `chunks_total - chunk` (unchanged).
- Nothing is fabricated when `resumed_from` is absent: the estimate behaves
  exactly as today.

### D-B5b — One added copy line, no new stage

`AiImportStage` (`core/src/ai/views.rs:226`) gets **no** new value: a resume point
is a property of the attempt, not a pipeline stage, and a new enum value would
need a glyph, a golden and an `as_str` wire spelling for no information gain.

Client copy (German is the shipped template locale):

- stage line, only when `resumed_from > 0`:
  `Fortsetzung ab Abschnitt {n} von {total}` — `Abschnitt`, not `Szene`:
  `resumed_from` counts chunks, and one chunk can yield several scene rows;
- the held state (PR A) extends #822's banner rather than replacing it:
  `{provider} ist nicht erreichbar · wartet bis {time} · spätestens {deadline}`
  plus the second line `Kein Versuch wird verbraucht — der Import läuft nach der
  Pause weiter, sobald der Anbieter bis {deadline} zurück ist.` (conditional on
  recovery: an expired hold dead-letters instead of continuing).

Both keys live in the ARB catalogs (`de` template + `en`).

### D-B6 — The chunk budget cannot multiply under resume

- `max_chunks_per_script` is validated **once**, after deterministic chunking
  (`validate_chunk_count`, `workers.rs:3976`), over the same `document_digest` —
  a resume re-derives the identical chunk list, so the cap cannot be multiplied
  by resuming.
- Bounded truncation/parse retries stay per chunk and per attempt. The analytic
  worst case **shrinks** under resume: `chunks_remaining × (1 + truncation
  retries)` instead of `chunks_total × (1 + truncation retries)`.
- In-attempt provider retries are bounded by `AI_IMPORT_MAX_ATTEMPT_RETRIES`
  (D-C1), not by the job budget.
- Tests assert the **call count** against that computed bound (AGENTS.md §4: no
  wall-clock gating).

### D-B7 — Invalidation: an extraction fingerprint, drop-and-restart

`extraction_key text` on the job row, written as a compare-and-set at the first
stored chunk of an attempt:

```
sha256( document_digest | provider | model | sha256(effective prompt) | chunker_version )
```

`effective prompt` is the text actually sent — the user's **stored** prompt when
one is configured, else the deployment default (`prompts::default_prompt`,
`crates/infra/src/ai/prompts.rs:71`; a stored configuration prompt takes
precedence, an existing spec requirement). It is hashed rather than versioned
because **there is no prompt version anywhere in the system** — the stored prompt
is free text the user can edit, so a version string would have to be invented,
stored and bumped by hand (a fourth thing to keep in sync). A hash also answers
the question honestly: a whitespace-only prompt edit *can* change model output,
so re-invalidating on it is correct, not an over-reaction.

On attempt start, when the stored key differs from the key this attempt would
produce:

1. delete the job's `ai_import_job_chunk` rows (all of them — never a partial
   resume across two models),
2. write the new key,
3. `tracing::warn!` `#871 chunk resume invalidated: <component(s) that changed>`
   (log-only; a wire `detail` would violate the ADR-031 detail rule and the
   client has nothing to do with it),
4. start at chunk 0. The progress numbers alone are honest again.

Why store the components rather than only a hash: the operator needs to know
*what* changed (model, prompt or chunker) to decide whether the restart was
necessary. The preview already stamps `provider`/`model` (#675), so a chunk set
mixing two models would also contradict the provenance that ships with it.

### D-C1 — Two retry knobs, not one

`AI_IMPORT_MAX_RETRIES` keeps its meaning (job retries,
`AiImportBounds::max_retries`, default 5) — renaming a documented env var to fix a
precedence bug is churn without a beneficiary. A new
`AI_IMPORT_MAX_ATTEMPT_RETRIES` (default **2**, bounded `0..=10`) bounds the
in-attempt loop, i.e. `1 + 2 = 3` attempts per chunk.

Rationale: one knob allows `5 × 5 = 25` paid calls for one chunk before anything
surfaces, each holding a permit for up to 120 s. Three attempts are enough to
distinguish a blip from an outage.

The compile-time invariant ties the **defaults** only:

```rust
const _: () = assert!(DEFAULT_MAX_ATTEMPT_RETRIES + 1 >= DEFAULT_BREAKER_THRESHOLD);
```

It is deliberately not a constraint on configured values, and the earlier draft's
stronger claim ("a deployment cannot configure a breaker that never opens") does
not hold and is withdrawn: `consecutive_failures` counts per **pair across all
jobs, chunks and replicas** (D-A3), so a threshold of 10 with 0 in-attempt
retries still opens — it only opens more slowly, because each chunk contributes
one failure instead of up to three. `from_env` therefore bounds the threshold to
`1..=10` and logs a `warn!` when `threshold > 1 + max_attempt_retries`, naming the
effect ("a single chunk cannot open the breaker alone") rather than silently
rejecting an operator's choice.

### D-C2 — The permit: a hold releases it, an in-attempt retry stays bounded

- A hold **ends the attempt** (`mark_held` + return), so the permit is dropped
  with the run: a waiting job occupies no capacity. This is the issue's
  recommendation and it is free — the existing structure already releases on
  every return from `run_job`.
- In-attempt retries keep the permit. Releasing and re-acquiring per retry would
  let another job interleave between two calls of the same chunk and double the
  acquire/reclaim traffic, for a benefit that the breaker already provides. What
  matters is that the hold is **bounded and computed**, not guessed — and the bound
  has to cover everything one attempt can spend: the **request timeouts** (both
  nested loops), the **backoff sleeps** (`retry_bounded` sleeps while still holding
  the permit, `workers.rs:3989`, `compute_backoff` capped at 30 s) and the
  client-internal parse retries (see the next bullet, which is what turns 7 min
  into 19 min):

  ```
  (1 + max_attempt_retries) × request_timeout_secs
    + max_attempt_retries × MAX_ATTEMPT_BACKOFF        // 30 s, jitter ≤ 25 % is clamped into it
  = 3 × 120 s + 2 × 30 s = 420 s = 7 min              // outer layer alone
  ```

  Before #871 the outer layer alone was `6 × 120 s + 5 × 30 s = 870 s = 14.5 min`.
- **The guard is read before every attempt, not only before a sleep.** Another
  worker can open the breaker *during* the backoff, and a check that has already
  passed would then send the next attempt into a provider everyone else has stopped
  calling — the exact waste the breaker exists to stop. The guard is therefore
  consulted immediately before **each** attempt (the first one included) and again
  before each sleep; an open breaker costs neither a call nor a delay.
- **The guard also has to live inside the client, because one attempt is not one
  request.** `OpenAiCompatibleChatClient::request_decoded` loops over
  `MAX_TRUNCATION_RETRIES = 2` (`client.rs:54,172`), i.e. up to **three** billed HTTP
  requests per outer attempt while a malformed/truncated response is re-requested at
  a doubled budget; `OllamaChatClient` has the same shape with `max_parse_retries ≤ 3`
  (up to four). A guard consulted only at the `retry_chat` boundary would let the
  second and third request of an attempt go out after another worker had already
  opened the breaker. Both clients therefore take the same
  `ProviderHealthGuard` and consult it **before every billable request**, parse
  retries included; on open the client returns an internal `ProviderBreakerOpen`
  sentinel (never serialized, no new problem code — D-X1) that the outer loop and
  the chunk loop treat as terminal-and-hold, not as a retryable error (a
  `ServiceUnavailable` would be retried, which is the bug).
- **The permit bound therefore multiplies the two layers:**

  ```
  (1 + max_attempt_retries) × (1 + inner_retries) × request_timeout_secs
    + max_attempt_retries × MAX_ATTEMPT_BACKOFF
  hosted (inner = 2): 3 × 3 × 120 s + 2 × 30 s = 1140 s = 19 min
  ollama (inner ≤ 3): 3 × 4 × 120 s + 2 × 30 s = 1500 s = 25 min
  ```

  The test asserts that arithmetic **and** the client's request count (a fake
  transport counting calls), so a future retry layer cannot quietly re-open the
  unbounded window. No wall-clock gating (AGENTS.md §4).

### D-C3 — A provider failure takes the hold, not the job backoff

Once the breaker is open, `next_attempt_at` for every held job of the pair is the
breaker's `retry_at`. The whole fleet therefore re-probes at **one** instant
instead of a per-job stagger, which is what makes the single CAS prober (D-A6)
cheap and recovery fast.

The existing per-job curve (`1 min · 2^retries`, cap 6 h) survives only for the
`≤ threshold − 1 = 2` provider failures before the breaker opens, and for the
non-provider retryable failures it was designed for (mapping DB, payload storage,
pricing read model). No new curve constant is introduced: one fewer number to
tune, and the existing one stays documented where it lives.

### D-C4 — The hold expires, dead-letters with the provider narrative, and charges no budget

`AI_IMPORT_MAX_PROVIDER_HOLD_SECS` (default **6 h** — the same magnitude as the
job-backoff cap) measured from the first hold of the current attempt series,
recorded on the job as `provider_hold.hold_deadline`.

The expiry is a **claim-free sweeper**, not a worker write. The held job is
`failed` and its pair is open, so the claim predicate keeps it unclaimable: a
worker can never reach it, and `mark_held`'s owner fence could not update it
either. Expiry is therefore its own periodic task, in the family of the existing
reservation reaper / payload-GC sweepers (`AI_IMPORT_PROVIDER_SWEEP_INTERVAL_SECS`,
default 60 s):

```sql
UPDATE ai_import.ai_import_job
SET status = 'dead_letter', last_error = LEFT($1, 1000),
    next_attempt_at = NULL, progress = NULL,
    -- Kept, NOT nulled: `state = 'expired'` is the durable marker that lets the
    -- client distinguish "the provider never came back" from "the retry budget
    -- is spent" (the #822 derivation would otherwise render the budget copy,
    -- although `retries` was deliberately never charged).
    provider_hold = jsonb_set(provider_hold, '{state}', '"expired"'),
    provider_hold_series_started_at = NULL,
    worker_id = NULL, lease_expires_at = NULL, permit_id = NULL, updated_at = now()
WHERE status = 'failed'
  AND provider_hold IS NOT NULL
  AND (provider_hold ->> 'hold_deadline')::timestamptz <= now()
RETURNING id, pg_notify('ai_import_job_events', id::text)
```

It is keyed on the **job's own deadline**, never on a claim, so it reaches
pre-claim held jobs too; `retries` stays untouched, and it notifies every affected
id through the existing hub. An advisory lock keeps concurrent replicas from
double-sweeping (the payload-GC precedent).

**The deadline is the series clock, not the wait's clock.** The series start lives
in its own column, `provider_hold_series_started_at` (`COALESCE(...)`d on every
hold write), **not** in `provider_hold` — because `provider_hold` is cleared on
every close (D-A6) and a deadline stored inside it would restart at 6 h on each
short recovery. A job that flaps closed → open every few minutes would then never
expire, which is exactly the unbounded hold this decision exists to prevent. A
re-hold refreshes `until` and keeps the series start, so `hold_deadline =
provider_hold_series_started_at + AI_IMPORT_MAX_PROVIDER_HOLD_SECS` only moves when
the series ends. The series ends when (a) the job is **claimed** (it actually ran,
so the next hold is a new episode), or (b) the job has been un-held for
`STABLE_WINDOW` — the same sustained-recovery horizon the flap rule uses (D-A6);
the sweeper clears the column for such rows as hygiene. The series clock is
**never** cleared by a breaker close (that is the whole point), and terminal
writes clear it: `mark_succeeded`, `mark_payload_unavailable` and the expiry
itself. A re-hold keeps it, so a flapping provider cannot reset the 6 h budget one
probe at a time.

On expiry:

- transition to `dead_letter` with `last_error` = the provider summary plus
  "the provider stayed unavailable for 6 h" (localizable narrative stays
  client-side, keyed on the same code);
- `retries` **unchanged** — the document did not fail, the provider did, and the
  operator's "documents that failed" count must not be inflated by
  infrastructure;
- exactly **one** attempt row (the dead-letter), not five identical ones;
- `provider_hold` cleared by the terminal write.

Two reasons the expiry is not optional: an unbounded hold is a silent abandonment
of the import, and `failed` rows are deliberately **never** swept by the payload
GC (a `failed` row is by construction one that still has a future) — so a held
row that never expires pins its source document in object storage forever.

It is visible **before** it bites: the client renders `until` ("wartet bis") and
`hold_deadline` ("spätestens bis") from the additive field.

### D-X1 — No new problem code

The hold reuses #822's registered `ai-import.llm-provider-unavailable` as
`provider_hold.reason_code`. A hold is not an error: it has no HTTP surface of its
own, so inventing a code would only add a registry entry nothing can be answered
with. `PROBLEM_CODE_COUNT` stays unchanged, and the client's existing per-code
narrative keeps working for the `last_error` it still writes.

### D-X2 — Operator surface: log marker + runbook SQL

- `tracing::warn!` with the greppable marker `#871 provider breaker` on every
  transition (`#37`-style convention).
- A runbook section (`docs/operations/runbooks.md` → "AI provider breaker health
  (issue #871)") with the three queries an operator actually asks:
  open breakers + since when + retry_at; jobs held right now (grouped by pair);
  chunk-store size / resume points for a job under investigation.
- **Not** `GET /v1/health` (unauthenticated, 2 s timeout, no credential) and
  **not** a new public endpoint (#816's `GET /v1/me/capabilities` is a different
  concern; a provider-health surface, if it ever becomes user-facing, belongs
  there — a separate change).

### D-X3 — Migration and lifecycle placement

| PR | Migration | Registers in |
|---|---|---|
| A | `ai_import.provider_health` + `ai_import_job.(provider, model)` | `dev_reset/business.rs` (before the job delete), `dev_reset/plan.rs` |
| B | `ai_import.ai_import_job_chunk` + `ai_import_job.extraction_key` | `dev_reset` lists **and** the payload-GC sweep |

Both migrations are additive with `down.sql`; no backfill (a pre-#871 job has
`provider`/`model` `NULL`, is never breaker-filtered, and has no chunk rows to
resume — it simply runs the pre-#871 way, once).

### D-X4 — Testing strategy (no wall-clock gating)

| Layer | Test | Assertion |
|---|---|---|
| infra unit | fake `LlmClient` failing N times then succeeding | **provider call count** (resume: chunks 1..25 never called again; breaker: zero calls while open) |
| infra unit | `retry_bounded` short-circuit | calls + no sleep (injected clock/`tokio::time::pause`, never a real sleep) |
| infra unit | state machine transitions | pure function over `(state, failures, now)`; flap escalation is a table-driven case |
| Postgres (`crates/infra/tests/**` or the existing ai harness) | chunk store + cursor + invalidation | contiguous prefix after a simulated kill (`0,1,3` ⇒ cursor `2`); a lost-claim `put` returns `Conflict`; fingerprint mismatch deletes rows; `mark_held` leaves `retries` and attempt rows untouched; the sweeper expires a hold while the breaker is still open |
| api contract | `openapi_drift` | `provider_hold` + `resumed_from` present; registry count unchanged |
| Flutter | held copy + resumed ETA basis | widget test on the banner/stage line; `job_eta` unit test with `resumed_from = 25` |

## Risks / Trade-offs

| Risk | Mitigation |
|---|---|
| A `(provider, model)` breaker is too coarse for a per-user key problem | Only **retryable** provider failures count; 401/403/entitlement stay permanent and never open it (D-A1) |
| The 6 h default hold is shorter than a long provider incident | Configurable; the expiry is visible in advance (`hold_deadline`) and the narrative names the provider, so a longer incident is an operator decision, not a silent failure |
| A chunk payload can be large | Bounded by `max_tokens_per_req` (the call cannot return more), one row per chunk, GC'd with the job (D-B1) |
| Two workers probe simultaneously | CAS on `probe_owner` + a probe lease (`probe_started_at`), so a crashed prober cannot wedge `half_open` (D-A6) |
| A stale `(provider, model)` snapshot filters on the wrong pair | Authoritative re-check after `resolve_config`, with a stamp-refresh when it differs (D-A2b) |
| Resume across a silently changed sampling temperature | Not in the fingerprint on purpose: only what the *system* controls (document digest, provider, model, effective prompt, chunker version) can invalidate; a provider-side default change is out of reach and is what the preview's provenance stamp covers |
| Guidance drift: the AI-import rule file documents the old retry semantics | Task per PR updates `backend/.github/instructions/ai-import.instructions.md` in the same diff |

## Migration / Rollout

1. **A** ships with the breaker **enabled** (`AI_IMPORT_BREAKER_ENABLED`, default
   `true`) but at a threshold of 3 consecutive failures — the behaviour change is
   invisible until a provider actually fails 3× .
2. **B** ships with resume **enabled** (no flag): the fallback path is the
   pre-#871 behaviour when no chunk rows exist, so an empty store is a no-op.
3. **C** ships the split knob with a default that reduces in-attempt retries from
   5 → 2; documented in the same PR as an intentional cost change.
4. Each PR is independently revertible: A's migration is additive and its
   predicate is the only read of the new table; B's chunk store is ignored by any
   build that does not query it; C's knob defaults are env-overridable.
