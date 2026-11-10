<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# Tasks — 871 (three PRs, one design)

Track prefixes: **[A]** breaker / fail-fast (PR 1), **[B]** chunk-level resume
(PR 2), **[C]** retry policy (PR 3). A task may only start once the decision it
implements exists in `design.md` (`D-A*`, `D-B*`, `D-C*`). No task gates on wall
clock (AGENTS.md §4).

## 1. [A] Core — breaker semantics on the wire and in the bounds

- [ ] 1.1 `AiImportBounds`: new `max_attempt_retries` (default 2, env
      `AI_IMPORT_MAX_ATTEMPT_RETRIES`, bounded `0..=10`),
      `breaker_failure_threshold` (default 3, env
      `AI_IMPORT_BREAKER_FAILURE_THRESHOLD`, bounded `1..=10`),
      `max_provider_hold_secs` (default 21600, env
      `AI_IMPORT_MAX_PROVIDER_HOLD_SECS`) and a `const _: () = assert!(…)` tie
      between attempt retries and the breaker threshold (**D-C1**). The assert
      guards the **defaults** only; `from_env` bounds each value and `warn!`s when
      `threshold > 1 + max_attempt_retries` (the counter is per pair, so the
      breaker still opens — just more slowly).
- [ ] 1.2 `core::ai::views`: `ProviderBreakerState { Closed, Open, HalfOpen,
      Expired }` (`as_str`, `serde(rename_all = "snake_case")`) and `ProviderHold
      { provider, model, reason_code, state, until, hold_deadline, chunks_done }`
      with `ToSchema`; new additive `AiImportJob.provider_hold:
      Option<ProviderHold>` (`serde(default)`) whose doc states it is cleared by
      every other lifecycle write **except** the hold-expiry write, which keeps it
      with `state = Expired` (**D-C4**). Document that `Expired` is a *job-hold*
      state only: the breaker's own `provider_health.state` CHECK accepts three
      values and never `expired`.
- [ ] 1.3 `AiImportJob.provider`/`.model` (`Option`, `serde(default)`) — the
      enqueue-time snapshot (**D-A2b**).
- [ ] 1.4 `core::ai::ports`: `AiImportQueue::mark_held(id, worker_id,
      hold: ProviderHold)` with the doc table from **D-A4** (what it deliberately
      does NOT do) and `AiImportQueue::expire_provider_holds(...)` (the claim-free
      sweeper write, **D-C4**); a `ProviderHealth` port (`open`, `record_failure`,
      `record_success`, `try_begin_probe`, `state`, plus the two derived writes
      `hold_runnable_jobs` / `refresh_held_jobs`) so the worker loop stays
      queue-agnostic and the breaker is unit-testable against a fake.
- [ ] 1.5 `AiImportEnqueueRequest`: `provider`/`model` fields; doc names the API
      edge as their source (CQRS boundary) and the #771/#763 precedent.
- [ ] 1.6 Unit tests: the bounds defaults + the compile-time invariant, the view
      serde round-trip and `provider_hold: null` on an old payload.

## 2. [A] Infra — the durable breaker and the held path

- [ ] 2.1 Migration `…_ai_import_provider_health.up/down.sql`: the
      `ai_import.provider_health` table from **D-A2** plus three additive, nullable
      job columns with no backfill: `ai_import_job.provider varchar`,
      `.model varchar` (the breaker key snapshot, **D-A2b**), `.provider_hold
      jsonb` (the wire view's column, **D-A4**) and `.provider_hold_series_started_at
      timestamptz` (the **series clock** that a breaker close must NOT clear,
      **D-C4**). (**D-X3**)
- [ ] 2.2 `infra::ai::provider_health` repository: single-statement transitions
      from the **D-A6** table (`closed→open` with the `closed_at` stable-window
      flap rule, `open→half_open` with the `probe_owner` CAS + probe lease,
      `half_open→closed`, `half_open→open` with **no** flap increment but a
      refresh of the pair's held jobs); `min_open(n) = min(60 s · 2^n, 30 min)`;
      the `closed_at` column in the migration; pure `next_state(...)` function for
      the table-driven test.
- [ ] 2.2b **Probe task** (D-A3): a periodic task in the sweeper family (same
      registration/join as 2.10b) that, for every breaker with
      `state <> 'closed' AND retry_at <= now()`, runs the probe in **three short
      steps** — (1) commit the `open → half_open` CAS with a fresh `probe_lease_id`,
      (2) perform the provider request **outside any transaction** so a hung request
      cannot hold the row lock and block the lease takeover, (3) commit the fenced
      result — never one transaction across the network call. Candidate selection
      returns the **job identity** (`id, user_id, document_kind`), restricted to an
      **active** hold (`status = 'failed'` and `provider_hold.state` in
      `open`/`half_open`), so an expired terminal marker is never a donor and the id
      is never re-derived. **Provider dispatch**: hosted → `catalog.list(provider,
      vaulted_key)`; **Ollama → unauthenticated `GET {curated ollama base}/api/tags`**
      (no vault read, no bearer — `catalog.rs:140` rejects an empty key and would
      leak a token to a plain-HTTP origin). **Outcome classification is
      reachability-only**: 2xx → close; transport/timeout/429/5xx → stay open +
      advance `retry_at`; **401/403 → close** and log the rejection. The probe
      **never** retires or terminalizes a job — that is the job's own attempt's job
      (#637 permanent path). It must not claim a job and must not issue a paid call.
      A *credentials* outcome (401/403) is **not** a provider verdict either — and it
      is **not** grounds to retire a job: the endpoint answered, so the breaker
      closes, and the job's own attempt later produces the honest
      `dependency.auth-failed` through the existing permanent path (#637). Rotation
      is bounded to `PROBE_CANDIDATE_LIMIT` per tick (3). Every result write is
      CAS-fenced on the
      **probe lease token** (`state = 'half_open' AND probe_lease_id = $3`), never on
      `probe_owner`, which the same task can reacquire.
- [ ] 2.3 Every transition logs `tracing::warn!` with the literal marker
      `#871 provider breaker` and the fields from **D-X2** (never a new health
      check on `/v1/health`).
- [ ] 2.4 `queue.rs`: add the `NOT EXISTS (… provider_health … ph.state <>
      'closed')` predicate to **all four** claim paths (`claim_next`,
      `claim_next_kind`, `claim_next_reconciling`,
      `claim_next_kind_reconciling`) — one semantics, four copies. Only `closed`
      admits a claim: `retry_at` must NOT appear in the predicate, or the due
      probe would open a queue drain instead of a single probe (**D-A2**).
- [ ] 2.5 `queue.rs`: `mark_held` (owner-fenced like `mark_failed`: `WHERE id = $1
      AND status = 'running' AND worker_id = $2`), writing `failed` +
      `next_attempt_at = hold.until` + `provider_hold`, **without** touching
      `retries` and **without** inserting an `ai_import_job_attempt` row; plus
      clearing `provider_hold` in `claim_next*`, `mark_succeeded`, `mark_failed`,
      `mark_payload_unavailable`, the ordinary dead-letter path **and on a
      successful breaker close** (**D-A4**, **D-A6**) — with **one** documented
      exception: the **hold-expiry** write keeps it with `state = expired`, because
      that marker is what separates an expiry from a spent retry budget.
- [ ] 2.5b `queue.rs`: `hold_runnable_jobs(provider, model, retry_at)`, the
      claim-free materialization run by the `closed→open` transition
      (`status='pending'` or due `failed`, one statement, notify each returned id),
      carrying `provider_hold_series_started_at =
      COALESCE(provider_hold_series_started_at, now())` — the series clock lives in
      its own column because `provider_hold` is cleared on every close, and a
      deadline inside it would restart at 6 h on each short recovery (**D-C4**) —
      and `refresh_held_jobs(provider, model, retry_at)` for `half_open→open`
      (**D-A4**, **D-A6**). The series column is cleared on **claim** and after a
      `STABLE_WINDOW` of un-held state.
- [ ] 2.5c `queue.rs`: `hold_owed_jobs(...)` — the **sweeper** materialization. The
      open-time write cannot reach a job enqueued while the breaker is already open,
      nor a `failed` job whose `next_attempt_at` became due afterwards; both are
      excluded by the claim predicate and would stay `pending`/`failed` with no
      `provider_hold`, i.e. invisible **and unexpirable** (the expiry precondition
      is the hold). One idempotent statement per non-`closed` pair, guarded by
      `provider_hold IS NULL`, setting the hold + series clock; test the
      enqueue/open race explicitly (**D-A4**).
- [ ] 2.6 `enqueue`: persist `provider`/`model`; the API edge resolves them from
      the user's active AI config (same edge as the #771 target snapshot). The
      config-**change** edge stamps the new pair onto that user's runnable jobs in
      one statement, so a stale snapshot cannot filter a job against a breaker it
      no longer uses (**D-A2b**).
- [ ] 2.7 `workers.rs`: `ProviderHealthGuard` consulted at the chunk boundary
      (before each chunk's first call) and before the in-attempt backoff sleep;
      an open breaker stops the loop, skips merge/preview and takes the held path
      with `chunks_done` (0 in PR A, the stored count in PR B) (**D-A5**).
- [ ] 2.8 `worker_loop.rs`: post-`resolve_config` authoritative re-check for the
      **resolved** pair + stamp-refresh of the snapshot when it differs
      (**D-A2b**).
- [ ] 2.9 `retry_bounded`/`retry_chat`/`retry_schedule`: consult the breaker guard
      at the **top of every iteration** (the first attempt included) and again before
      each backoff sleep — a check that runs only before the sleep can be invalidated
      by another worker opening the breaker *during* that sleep, and the loop would
      then still call. Short-circuit: no call, no sleep (the call-count half of
      **D-C2**).
- [ ] 2.9b `client.rs` + `ollama.rs`: the guard also goes **inside** the clients,
      because one attempt is not one request — `request_decoded` issues up to
      `1 + MAX_TRUNCATION_RETRIES = 3` billed requests (Ollama: up to
      `1 + max_parse_retries ≤ 4`) while re-requesting a truncated/malformed answer.
      Check the guard before **every** billable request, parse retries included, and
      return an internal `ProviderBreakerOpen` sentinel that `retry_bounded` and the
      chunk loop treat as terminal-and-hold (never a retryable `ServiceUnavailable`,
      which would be retried, and never a serialized wire error — D-X1).
- [ ] 2.10 Payload GC + `dev_reset/business.rs` + `dev_reset/plan.rs`: register
      `ai_import.provider_health` (before the job delete) (**D-X3**).
- [ ] 2.10b Provider-hold sweeper: a periodic claim-free task
      (`AI_IMPORT_PROVIDER_SWEEP_INTERVAL_SECS`, default 60 s) that does two things
      under one advisory lock, notifying each affected id — (a) **materialize** the
      holds the open-time transition could not reach (2.5c), (b) dead-letter a held
      job whose own `hold_deadline` passed. It is the only path that can reach such
      a job, because the claim predicate excludes it and `mark_held` needs an owner
      (**D-C4**). It keeps `provider_hold` with `state = expired` instead of nulling
      it (the durable expiry marker the client branches on) and is the same task
      family that hosts the probe (2.2b). Registered and joined like the payload-GC
      sweeper.
- [ ] 2.11 Unit tests with a fake `LlmClient` that fails N times then succeeds:
      **zero** provider calls while the breaker is open, the threshold opens it,
      a permanent failure never does, `mark_held` leaves `retries` AND the attempt
      rows untouched, the flap escalation table (**D-X4**).
- [ ] 2.12 Postgres test: the claim predicate skips a held job for an open pair
      and claims it again once the breaker closed; a job is **not** claimable while
      the breaker is `half_open` (the drain regression); the `closed→open`
      transition holds a queued (never-claimed) job with the series clock set; a
      failed probe refreshes the held rows' `until`; a successful close clears
      `provider_hold` **but not** the series clock; a flap cycle does not reset
      `hold_deadline`; a stale probe result writes nothing; a 401/403 probe
      **closes** the breaker and terminalizes **no** job; the sweeper dead-letters an
      expired hold with `state = expired` and `retries` unchanged; a **hung probe**
      leaves the breaker row unlocked so the next tick takes over the lease.

## 3. [A] API, client and docs

- [ ] 3.1 Composition root wiring (`AI_IMPORT_*` → `AiImportBounds`, breaker
      repository, probe via the existing `catalog.rs` client).
- [ ] 3.2 Regenerate `backend/openapi.yaml` (`UPDATE_OPENAPI=1 cargo test -p api
      --test contract openapi_drift`) and the Dart client.
- [ ] 3.3 Flutter: held banner + compact list line extending #822's
      `aiProviderDegradation` derivation; ARB `de`/`en` keys; widget test covering
      **both terminal causes** — hold expiry (`provider_hold.state = expired`) and
      genuine retry exhaustion — so the two never share copy
      (**flutter spec: "A held job renders why it is waiting"**).
- [ ] 3.4 `docs/operations/runbooks.md`: "AI provider breaker health (issue
      #871)" with the three operator queries (**D-X2**).
- [ ] 3.5 `backend/.github/instructions/ai-import.instructions.md`: the new env
      vars, the held semantics and the explicit note that `/v1/health` gains no
      provider check.
- [ ] 3.6 Bump `core`/`infra`/`api` (minor) + `CHANGELOG.md` `[Unreleased]`, then
      PR 1 with the version-bump table.

## 4. [B] Core — resume on the wire

- [ ] 4.1 `AiImportProgress.resumed_from: Option<u32>` (`serde(default)`, doc
      states "n chunks already stored; this attempt continues at n+1") and its
      absence-is-honest rule (**D-B5**).
- [ ] 4.2 `core::ai::ports`: chunk-store port (`load(job_id) -> Vec<StoredChunk>`,
      `put(job_id, worker_id, extraction_key, chunk_index, payload, usage)`,
      `clear(job_id)`, `resume_cursor(job_id)`, `stored_usage(job_id)`) so
      `workers.rs` stays testable against a fake — no read-model query from the
      write path. The `put` signature carries the owner and the fingerprint because
      the write is claim-fenced (**D-B3**).
- [ ] 4.3 Unit tests: the cursor is the contiguous prefix length (`0,1,3` ⇒ `2`,
      not `4`) and `resumed_from` serde round-trip.

## 5. [B] Infra — the chunk store, the cursor and the fingerprint

- [ ] 5.1 Migration `…_ai_import_chunk_resume.up/down.sql`: the
      `ai_import.ai_import_job_chunk` table from **D-B1** + `ai_import_job
      .extraction_key text` (**D-X3**).
- [ ] 5.2 `infra::ai::chunk_store`: the write runs in a transaction that takes the
      **job row `FOR UPDATE`** first, verifies `status='running'`, `worker_id` and
      `extraction_key` against the locked row, and then `INSERT … ON CONFLICT
      (job_id, chunk_index) DO UPDATE` (refused ⇒ `DomainError::Conflict`); the
      **invalidation** path takes the same lock on the same row, in the same order,
      in one transaction (fingerprint rewrite + chunk-row delete). A bare
      `INSERT … SELECT … WHERE …` is not enough under READ COMMITTED — it can read
      the old owner and commit after another worker reclaimed and invalidated the
      job (**D-B3**). Also: the ordered load whose **contiguous prefix** is the
      cursor (**D-B2**, the tail beyond a hole is deleted with a
      `#871 chunk resume hole at <index>` warn), `clear`, and the summed-usage read
      (**D-B4**).
- [ ] 5.3 Fingerprint helper (`document_digest | provider | model | sha256
      (effective prompt) | chunker version`), compare-and-set write, and the
      drop-and-restart path with the `#871 chunk resume invalidated: <component>`
      warn (**D-B7**).
- [ ] 5.4 `workers.rs`: seed `extraction_usage` from the stored rows, load the
      stored prefix into `context` in `chunk_index` order, iterate only the
      remaining chunks, re-check `claim_lost` before each chunk write, publish
      `resumed_from` on the first extraction frame and `put` each chunk as it
      completes (**D-B3**/**D-B5**).
- [ ] 5.5 Terminal transitions (`mark_succeeded`, `dead_letter`,
      `mark_payload_unavailable`) delete the job's chunk rows; the payload-GC
      sweep deletes them with the blobs; `dev_reset` lists register the table
      before the job delete (**D-B1**).
- [ ] 5.6 Unit test with a fake `LlmClient`: a job with stored chunks `1..=25`
      issues exactly `chunks_total − 25` calls and never re-asks for `1..=25`
      (call count, not wall clock) (**D-B6**).
- [ ] 5.7 Postgres test: a simulated kill after `put(25)` resumes at 26; the
      cursor survives a process restart; a fingerprint mismatch clears the rows
      and restarts at 0; a re-run chunk is counted once in the usage sum; and a
      **deterministic two-session test** of the write fence in both submission
      orders (chunk write vs. reclaim + fingerprint rewrite) — serialized by the
      job-row lock, never a stale chunk in the new set.

## 6. [B] Client and docs

- [ ] 6.1 `job_eta.dart`: every quantity the estimator derives from the attempt is
      computed from `chunk − resumed_from` — the **rate**, the sample floor
      (`aiJobEtaMinUnits`) and the **stall watchdog** (`chunkCadence` →
      `aiJobEtaStallCadenceFactor`). Using the absolute `chunk` would make a resumed
      attempt read 25 chunks in one second and declare a healthy successor chunk
      stalled after two minutes. Unit tests for `resumed_from = 25` covering rate,
      sample floor and stall window (**D-B5**).
- [ ] 6.2 Stage line copy `Fortsetzung ab Abschnitt {n} von {total}` (ARB
      `de`/`en`) only when `resumed_from > 0` — `Abschnitt`, not `Szene`, because
      `resumed_from` counts chunks and one chunk can yield several scene rows;
      widget test (**D-B5b**).
- [ ] 6.3 Regenerate `openapi.yaml` + the Dart client; bump versions per crate.
- [ ] 6.4 `ai-import.instructions.md`: the chunk table, the resume semantics, the
      invalidation rule **and** the one uncounted-spend sentence (**D-B4**).
- [ ] 6.5 PR 2 with the version-bump table.

## 7. [C] Retry policy

- [ ] 7.1 In-attempt retries read `bounds.max_attempt_retries` (not
      `max_retries`) in `retry_chat`/`retry_schedule` (**D-C1**).
- [ ] 7.2 Held jobs release the permit with the attempt; document and assert the
      computed in-attempt worst-case window **across both nested layers** —
      `(1 + max_attempt_retries) × (1 + inner_retries) × request_timeout_secs +
      max_attempt_retries × 30 s` = **19 min** hosted (`inner = 2`) / **25 min**
      Ollama (`inner ≤ 3`) — because `retry_bounded` sleeps while holding the permit
      and the clients re-request inside one attempt (**D-C2**).
- [ ] 7.3 `next_attempt_at` for a held job = the breaker's `retry_at`; the job
      curve stays for the `≤ threshold − 1` pre-breaker failures (**D-C3**).
- [ ] 7.4 Hold expiry → `dead_letter` with the provider narrative, `retries`
      untouched, exactly one attempt row; visible via `hold_deadline`
      (**D-C4**).
- [ ] 7.5 `ai-import.instructions.md` + `CHANGELOG.md`: the precedence split and
      the intentional retry-count reduction 5 → 2 documented as a cost change.
- [ ] 7.6 PR 3 with the version-bump table.

## 8. Acceptance (all three PRs landed)

- [ ] 8.1 A provider outage consumes no retry budget while the breaker is open;
      the job is held with a visible reason, probe time and deadline, and the copy
      states that waiting is correct.
- [ ] 8.2 A run that died at chunk 25 of 42 resumes at 26, asserted by provider
      call count.
- [ ] 8.3 A resumed attempt's progress and ETA start at the first uncompleted
      chunk and the client says where it resumed.
- [ ] 8.4 Cost accounting is explicit: the snapshot includes every persisted
      paid call, no double counting, and the one uncounted case is documented.
- [ ] 8.5 Recovery proven: the breaker closes on a successful probe, a held job
      then runs and completes, and a flapping provider is damped (bounded probes
      per hour).
- [ ] 8.6 Invalidation proven: a provider/model/prompt change never resumes
      across the change, and a crash between chunks never yields a preview with a
      hole.
- [ ] 8.7 Operators answer "is the breaker open, since when, which jobs are
      held" from the runbook SQL and the `#871 provider breaker` marker.
- [ ] 8.8 Tests as specified in **D-X4** — no wall-clock gating.

## Implementation status (in progress, PR A)

Landed on `feature/871-a-provider-breaker`:

- **1.1** bounds + the D-C1 compile-time assert. *Deviation:* the
  `threshold > 1 + max_attempt_retries` report is a **pure predicate**
  (`breaker_threshold_exceeds_attempt_budget`) logged by the composition root,
  not a `tracing::warn!` inside `from_env` — `core` carries no logging
  dependency (AGENTS.md §1). Same operator outcome.
- **1.2 / 1.3** `ProviderBreakerState`, `ProviderHold`, additive
  `AiImportJob.provider_hold/.provider/.model`.
- **1.4** `ProviderHealth` port + the pure state machine in
  `core::ai::provider_health`. *Deviation:* `hold_runnable_jobs` /
  `refresh_held_jobs` live on `AiImportQueue`, not on `ProviderHealth` — they are
  job-table writes, and putting them on the breaker port would have made the port
  depend on the queue. `mark_held` carries an explicit `hold_window_secs`
  parameter: the deadline is derived from the job's series clock plus the
  configured window, and inferring it from `hold_deadline - until` would be short
  by the current open window (up to 30 min at the flap cap).
- **1.5** `AiImportEnqueueRequest.provider/.model`.
- **1.6** state-machine, bounds and wire tests (core: 395 passing).
- **2.1** migration `20261110000001`. *Deviation (drift found against the real
  schema):* the design's "new `ai_import_job.provider`/`.model` columns" **already
  exist** as the *telemetry* provenance of the attempt that produced the result
  (`record_worker_telemetry`, and `has_telemetry` is derived from
  `provider IS NOT NULL`). Writing an enqueue-time snapshot into them would make
  a job that recorded nothing report a telemetry summary of zeros. The snapshot
  therefore gets its own pair, **`breaker_provider` / `breaker_model`**.
- **2.2** `infra::ai::provider_health` repository (CAS transitions driven by the
  core state machine). *Deviation:* the transitions are read → pure decision →
  compare-and-set (bounded retry), not one hand-written `UPDATE` per transition,
  so the arithmetic has exactly one source of truth. A hung probe in `half_open`
  is taken over after the lease window — without that branch a single dead HTTP
  request would wedge the pair forever, because no claim is admitted in
  `half_open`.
- **2.3** every committed transition logs `#871 provider breaker` with the D-X2
  fields.
- **2.4** the `NOT EXISTS (… provider_health …)` predicate on **all four** claim
  paths, without `retry_at`.
- **2.5** `mark_held` (retries untouched, no attempt row, series clock + derived
  deadline) and `provider_hold` cleared on every other lifecycle write.
- **2.5b / 2.5c** `hold_runnable_jobs` serves both materialization writers
  (open-time fast path and the sweeper's guarantee) — one idempotent statement
  guarded by `provider_hold IS NULL`, so `hold_owed_jobs` is not a second
  statement.
- **2.10** `dev_reset` registers `provider_health` before the job delete.

Verified against a throwaway Postgres 16 (full migration chain + the statements
above, executed as SQL): the claim predicate filters an open pair and admits it
once closed, `mark_held` leaves `retries` and the attempt history untouched, a
job enqueued **while** the breaker is open is held, the second materialization is
a no-op, `refresh_held_jobs` moves `until` but not the deadline, the expiry
dead-letters once (`state = expired`, `retries` unchanged, exactly one attempt
row) and is idempotent, and the probe lease refuses a concurrent prober, lets the
next tick take over a hung one, discards a superseded lease's result and closes
on the current one.

Landed in slices 3–4:

- **2.7 / 2.9** `ProviderGate` + a defaulted `AiImportQueue::provider_breaker`
  consult (a fake queue reports `closed`, so every test fake and every worker
  construction stayed unchanged). The retry loop consults the gate at the **top
  of every iteration** and again before each sleep; both workers consult it at
  their boundary and take the held path. The verdict travels as an internal
  sentinel (`BREAKER_OPEN_REASON` / `is_breaker_open`) on the existing `Conflict`
  channel — never a retryable `ServiceUnavailable` (that is the shape
  `is_transient` retries) and never a new problem code (D-X1).
- **2.2b / 2.10b** `provider_probe` (lease → request outside any transaction →
  fenced result; hosted via the donor job's own vaulted key, Ollama
  unauthenticated on a local-only client) and `provider_watch` (materialization
  of the holds the open-time write cannot reach + expiry, under one advisory
  lock, `AI_IMPORT_PROVIDER_SWEEP_INTERVAL_SECS`). **This slice is not optional
  for merge:** while a pair is open no job is claimed, so no paid call can
  succeed and nothing else can close the breaker — the probe is the only way out
  of a non-`closed` state.
- **3.1** composition-root wiring (breaker, probe, watch).
- *Deviation:* `run_provider_watch_tick` takes the probe as an
  `Option<&dyn ProviderProbe>` seam so the tick is testable without a network,
  and a **local** credential failure closes the breaker (logged) instead of
  staying open — otherwise one user's deleted key would hold every job of that
  endpoint hostage, which is exactly the D-A1 failure mode; the affected job's
  own attempt still surfaces `dependency.auth-failed` (#637).

Remaining for PR A: the `worker_loop` post-`resolve_config` re-check (2.8), the
client-internal guard over truncation retries (2.9b), the config-change stamp
(2.6), the Postgres test suite (2.11, 2.12), §3's remaining surface (OpenAPI +
Dart, Flutter held banner/ARB/widget test, runbook, `ai-import.instructions.md`,
version bumps), and then PRs B and C.
