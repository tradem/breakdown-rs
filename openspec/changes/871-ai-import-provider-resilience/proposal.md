<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# 871 — A provider outage stops costing money before the retry budget is gone

## Why

#822 (PR #870) made a degraded LLM provider **visible**: the attempt's stable
`code` names the provider, the client aggregates repeated provider failures into
one state, and a `dead_letter` after provider failures stops promising a retry.
It deliberately changed **no spending behaviour**. The observed incident is
therefore still fully reproducible:

```
job 01a1a554-…   status = failed   retries = 3 / 5
  last_error      = service unavailable: LLM provider returned HTTP 503
  next_attempt_at = 07:10:11Z
  progress        = {stage: extracting, chunk: 25, chunks_total: 42}
attempt 1/2/3     domain.service-unavailable   (06:54:59, 06:58:34, 07:06:11)
```

Three consecutive upstream 503s over ~17 minutes; the 42-chunk document never got
past chunk 25 — **three times**. Every attempt restarts at chunk 0, so the same
~25 chunks were paid for three times (≈5 min / ~120k input tokens per pass),
while the retry budget that exists to *recover* the import was spent learning the
same fact. Nothing in the pipeline stops a worker from calling a provider that is
already known to be down, and nothing persists a per-chunk result, so the work is
structurally re-bought.

This change is the **design decision** for the two halves the issue names —
stop paying (workstream A), stop re-paying (workstream B), and settle the retry
policy both depend on (workstream C) — before any of it is written. The issue
carries 17 explicitly open design questions; answering them in code, one PR at a
time, is how inconsistent retry semantics get shipped.

## What changes

Three workstreams, **one design, three PRs** (`tasks.md` tracks them as
`[A]`, `[B]`, `[C]`). No task in one track may be implemented before a decision
it depends on is in `design.md` — every decision is recorded there as `D-A*`,
`D-B*`, `D-C*` with the rejected alternatives.

### A — Circuit breaker / fail-fast (PR 1)

- A **durable** per-`(provider, model)` breaker (`ai_import.provider_health`),
  opened by N consecutive *retryable provider* failures and closed only by a
  successful cheap probe (the existing `catalog.rs` `GET {base}/models` call) or
  a successful paid call.
- The job row snapshots `(provider, model)` at enqueue, so **all four** claim
  paths can filter a job whose endpoint is known to be down **in SQL** — one
  query, no per-job discovery, no vendor call.
- A job that hits an open breaker is **held**, not failed: a new queue write
  `mark_held` keeps `status = 'failed'`, sets `next_attempt_at` to the breaker's
  retry time, does **not** increment `retries` and appends **no** attempt row.
- A running job stops at the **chunk boundary** before the next billable call
  (the `heartbeat::claim_lost` cooperative-abort precedent) and takes the same
  held path — one chunk of overspend, no refunded request.
- An additive `AiImportJob.provider_hold` field (no new `JobStatus`) states the
  wait, its deadline and the reason, so #822's banner is extended instead of
  contradicted.
- Half-open probing with a single CAS-guarded prober, escalating minimum-open
  duration and a bounded flap count; every transition logs a greppable
  `#871 provider breaker` marker and lands in the durable row (runbook SQL), not
  in the public health route.

### B — Chunk-level resume (PR 2)

- The parsed **per-chunk result** (and its usage) is persisted per completed
  chunk in `ai_import.ai_import_job_chunk`, keyed `(job_id, chunk_index)` —
  overwrite-on-replay, so re-running a chunk costs one call, never a row.
- The resume cursor is **derived** (the length of the contiguous stored prefix,
  i.e. the first missing chunk), never a column that can disagree with the rows; a
  crash between chunks therefore leaves a contiguous prefix and can never yield a
  preview with a hole — and a hole that does exist is resumed **at**, never past.
- A retried attempt resumes at the first uncompleted chunk: chunks 1..25 are not
  re-bought. Asserted by **provider call count**, never by wall clock.
- Progress stays honest: an additive `AiImportProgress.resumed_from` lets the
  attempt publish `chunk = 25` as its first frame instead of snapping to 0, and
  the client's ETA (#762 `job_eta.dart`) measures from the resume point.
- Chunk usage is stored per chunk so the job's cost snapshot counts **every paid
  call exactly once** across attempts — a retried import visibly costs more.
- An extraction fingerprint (`document_digest | provider | model |
  sha256(effective prompt) | chunker version`) invalidates the whole chunk set
  when anything that determined the output changed; the restart is logged with
  the component that changed.

### C — Retry policy (PR 3, mostly a decision this change lands early)

- The two nested retry layers stop sharing one knob: `AI_IMPORT_MAX_RETRIES`
  stays the job-level budget, `AI_IMPORT_MAX_ATTEMPT_RETRIES` (default 2) bounds
  in-attempt retries — today one chunk can be paid for up to 25 times.
- A held job releases its concurrency permit (the hold ends the attempt); an
  in-attempt retry keeps it, bounded analytically at
  `(1 + attempt_retries) × request_timeout_secs` and short-circuited by the
  breaker instead of slept through.
- A provider-attributed failure takes the **hold**, not the job backoff, so the
  fleet re-probes at one instant; the existing per-job exponential curve survives
  only for the ≤ threshold−1 failures before the breaker opens.
- The hold **expires**: after `AI_IMPORT_MAX_PROVIDER_HOLD_SECS` (default 6 h)
  the job dead-letters with the provider narrative and an untouched `retries`
  count — the document did not fail, the provider did, and it is visible before
  it happens.

## Decisions recorded (the issue's 17 open questions)

Full reasoning, rejected alternatives and the data model are in `design.md`:

| Issue question | Decision |
|---|---|
| A1 scope of the verdict | per `(provider, model)`; retryable provider failures only |
| A2 where the state lives | durable `ai_import.provider_health` + `(provider, model)` snapshot on the job |
| A3 how detected | both: reactive open, cheap catalog probe to close |
| A4 what happens to the job | stays `failed`, **held** `next_attempt_at`, additive `provider_hold` field — no new status |
| A5 mid-run vs pre-claim | both; abort before the next billable call, at the chunk boundary |
| A6 recovery / flapping | half-open, single CAS prober, escalating minimum-open, bounded flaps, `#871` log marker |
| B1 durability granularity | table `ai_import.ai_import_job_chunk`, not a JSONB column |
| B2 cursor semantics | derived `max(completed) + 1` |
| B3 idempotency | stored **parsed chunk result** (resume unit = the paid call) |
| B4 usage / cost | per-chunk usage; the job's snapshot sums every durable chunk once |
| B5 ETA / progress honesty | additive `progress.resumed_from` + client measures from it + one copy line |
| B6 chunk budget | cannot multiply: validated once, chunking deterministic |
| B7 invalidation | extraction fingerprint on the job; mismatch drops the set and restarts from 0 |
| C1 precedence | split: `max_attempt_retries` (2) vs `max_retries` (5, job) |
| C2 the permit | held job releases it; in-attempt retries stay analytically bounded |
| C3 backoff shape | hold instead of the job curve; `next_attempt_at` = breaker `retry_at` |
| C4 budget vs evidence | hold expires (6 h) → `dead_letter` with the provider narrative, budget untouched |

## Affected packages / artifacts

| Package / Artifact | Action | Reason |
|---|---|---|
| `core` | minor bump | `ProviderHold` view + `provider_hold` field, `resumed_from` on progress, `AiImportBounds::max_attempt_retries`, breaker/probe port traits, `mark_held` on `AiImportQueue` |
| `infra` | minor bump | `provider_health` repository, claim-path filter, `mark_held`, chunk store + resume, fingerprint invalidation, breaker guard in the chunk loop |
| `api` | minor bump | `provider_hold`/`resumed_from` in the OpenAPI document; regenerated `backend/openapi.yaml`; `AI_IMPORT_*` wiring at the composition root |
| migrations | 2 new | `ai_import.provider_health` + job `(provider, model)` snapshot (PR A); `ai_import.ai_import_job_chunk` + `extraction_key` (PR B) |
| `dev_reset` (`business.rs`, `plan.rs`) | registered | both new tables must be in the imports/business reset lists |
| `payload_cleanup` | extended | a terminal job's chunk rows are swept with its blobs |
| `frontend-flutter` | patch per PR | held-state copy (A), resume copy + ETA anchor (B); ARB `de`/`en` |
| `breakdown_api` (Dart client) | regenerated per PR | follows `openapi.yaml` |
| `docs/operations/runbooks.md` | new section | "AI provider breaker health (issue #871)" |
| `backend/.github/instructions/ai-import.instructions.md` | extended | new env vars, hold semantics, resume/invalidation rules |
| OpenSpec | this change | design + delta specs + tasks |

## Non-goals

- The #822 surface itself (degraded state, attribution, list parity) — shipped in
  PR #870. This change extends its copy; it does not re-derive it.
- Multi-provider failover / automatic endpoint switching (a provenance decision of
  its own; the preview stamps `provider`/`model`).
- Billing/refund semantics against the provider.
- Re-designing the AI-config screen's reachability seam (#809) or putting a
  provider probe on the public `GET /v1/health` (it is unauthenticated and needs
  a vaulted key — see D-A6).
- A new public provider-health endpoint (#816's `GET /v1/me/capabilities` is a
  different concern); the operator surface is the durable row + runbook SQL.
- Chunking the *document* differently, or resuming an **apply** run (the apply
  path has its own identity/claim machinery, #800/#805).
