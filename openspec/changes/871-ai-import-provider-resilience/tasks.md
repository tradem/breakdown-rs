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
      between attempt retries and the breaker threshold (**D-C1**).
- [ ] 1.2 `core::ai::views`: `ProviderBreakerState { Closed, Open, HalfOpen }`
      (`as_str`, `serde(rename_all = "snake_case")`) and `ProviderHold
      { provider, model, reason_code, state, until, hold_deadline, chunks_done }`
      with `ToSchema`; new additive `AiImportJob.provider_hold:
      Option<ProviderHold>` (`serde(default)`) whose doc states it is cleared by
      every other lifecycle write (**D-A4**).
- [ ] 1.3 `AiImportJob.provider`/`.model` (`Option`, `serde(default)`) — the
      enqueue-time snapshot (**D-A2b**).
- [ ] 1.4 `core::ai::ports`: `AiImportQueue::mark_held(id, worker_id,
      hold: ProviderHold)` with the doc table from **D-A4** (what it deliberately
      does NOT do); a `ProviderHealth` port (`open`, `record_failure`,
      `record_success`, `try_begin_probe`, `state`) so the worker loop stays
      queue-agnostic and the breaker is unit-testable against a fake.
- [ ] 1.5 `AiImportEnqueueRequest`: `provider`/`model` fields; doc names the API
      edge as their source (CQRS boundary) and the #771/#763 precedent.
- [ ] 1.6 Unit tests: the bounds defaults + the compile-time invariant, the view
      serde round-trip and `provider_hold: null` on an old payload.

## 2. [A] Infra — the durable breaker and the held path

- [ ] 2.1 Migration `…_ai_import_provider_health.up/down.sql`: the
      `ai_import.provider_health` table from **D-A2** plus
      `ai_import_job.provider varchar` / `.model varchar` (additive, nullable, no
      backfill) (**D-X3**).
- [ ] 2.2 `infra::ai::provider_health` repository: single-statement transitions
      from the **D-A6** table (`closed→open`, `open→half_open` with the
      `probe_owner` CAS + probe lease, `half_open→closed`, `half_open→open` with
      the `STABLE_WINDOW` flap rule); `min_open(n) = min(60 s · 2^n, 30 min)`; pure
      `next_state(...)` function for the table-driven test.
- [ ] 2.3 Every transition logs `tracing::warn!` with the literal marker
      `#871 provider breaker` and the fields from **D-X2** (never a new health
      check on `/v1/health`).
- [ ] 2.4 `queue.rs`: add the `NOT EXISTS (… provider_health …)` predicate to
      **all four** claim paths (`claim_next`, `claim_next_kind`,
      `claim_next_reconciling`, `claim_next_kind_reconciling`) — one semantics,
      four copies (**D-A2**).
- [ ] 2.5 `queue.rs`: `mark_held` (owner-fenced like `mark_failed`: `WHERE id = $1
      AND status = 'running' AND worker_id = $2`), writing `failed` +
      `next_attempt_at = hold.until` + `provider_hold`, **without** touching
      `retries` and **without** inserting an `ai_import_job_attempt` row; plus
      clearing `provider_hold` in `claim_next*`, `mark_succeeded`, `mark_failed`,
      `mark_payload_unavailable` and the dead-letter path (**D-A4**).
- [ ] 2.6 `enqueue`: persist `provider`/`model`; the API edge resolves them from
      the user's active AI config (same edge as the #771 target snapshot).
- [ ] 2.7 `workers.rs`: `ProviderHealthGuard` consulted at the chunk boundary
      (before each chunk's first call) and before the in-attempt backoff sleep;
      an open breaker stops the loop, skips merge/preview and takes the held path
      with `chunks_done` (0 in PR A, the stored count in PR B) (**D-A5**).
- [ ] 2.8 `worker_loop.rs`: post-`resolve_config` authoritative re-check for the
      **resolved** pair + stamp-refresh of the snapshot when it differs
      (**D-A2b**).
- [ ] 2.9 `retry_bounded`/`retry_chat`/`retry_schedule`: short-circuit on an open
      breaker instead of sleeping (the call-count half of **D-C2**).
- [ ] 2.10 Payload GC + `dev_reset/business.rs` + `dev_reset/plan.rs`: register
      `ai_import.provider_health` (before the job delete) (**D-X3**).
- [ ] 2.11 Unit tests with a fake `LlmClient` that fails N times then succeeds:
      **zero** provider calls while the breaker is open, the threshold opens it,
      a permanent failure never does, `mark_held` leaves `retries` AND the attempt
      rows untouched, the flap escalation table (**D-X4**).
- [ ] 2.12 Postgres test: the claim predicate skips a held job for an open pair
      and claims it again once `retry_at` has passed and the breaker closed.

## 3. [A] API, client and docs

- [ ] 3.1 Composition root wiring (`AI_IMPORT_*` → `AiImportBounds`, breaker
      repository, probe via the existing `catalog.rs` client).
- [ ] 3.2 Regenerate `backend/openapi.yaml` (`UPDATE_OPENAPI=1 cargo test -p api
      --test contract openapi_drift`) and the Dart client.
- [ ] 3.3 Flutter: held banner + compact list line extending #822's
      `aiProviderDegradation` derivation; ARB `de`/`en` keys; widget test
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
      `put(job_id, chunk_index, payload, usage)`, `clear(job_id)`,
      `resume_cursor(job_id)`, `stored_usage(job_id)`) so `workers.rs` stays
      testable against a fake — no read-model query from the write path.
- [ ] 4.3 Unit tests: cursor derivation is `max+1` (not `count`) and
      `resumed_from` serde round-trip.

## 5. [B] Infra — the chunk store, the cursor and the fingerprint

- [ ] 5.1 Migration `…_ai_import_chunk_resume.up/down.sql`: the
      `ai_import.ai_import_job_chunk` table from **D-B1** + `ai_import_job
      .extraction_key text` (**D-X3**).
- [ ] 5.2 `infra::ai::chunk_store`: `ON CONFLICT (job_id, chunk_index) DO UPDATE`
      put, the derived cursor query (**D-B2**), the ordered load for the merge
      pass, `clear`, and the summed-usage read (**D-B4**).
- [ ] 5.3 Fingerprint helper (`document_digest | provider | model | sha256
      (effective prompt) | chunker version`), compare-and-set write, and the
      drop-and-restart path with the `#871 chunk resume invalidated: <component>`
      warn (**D-B7**).
- [ ] 5.4 `workers.rs`: seed `extraction_usage` from the stored rows, load the
      stored chunks into `context` in `chunk_index` order, iterate only the
      remaining chunks, publish `resumed_from` on the first extraction frame and
      `put` each chunk as it completes (**D-B3**/**D-B5**).
- [ ] 5.5 Terminal transitions (`mark_succeeded`, `dead_letter`,
      `mark_payload_unavailable`) delete the job's chunk rows; the payload-GC
      sweep deletes them with the blobs; `dev_reset` lists register the table
      before the job delete (**D-B1**).
- [ ] 5.6 Unit test with a fake `LlmClient`: a job with stored chunks `1..=25`
      issues exactly `chunks_total − 25` calls and never re-asks for `1..=25`
      (call count, not wall clock) (**D-B6**).
- [ ] 5.7 Postgres test: a simulated kill after `put(25)` resumes at 26; the
      cursor survives a process restart; a fingerprint mismatch clears the rows
      and restarts at 0; a re-run chunk is counted once in the usage sum.

## 6. [B] Client and docs

- [ ] 6.1 `job_eta.dart`: derive the attempt's rate from `chunk − resumed_from`
      while the remaining count stays `chunks_total − chunk`; unit test with
      `resumed_from = 25` (**D-B5**).
- [ ] 6.2 Stage line copy `Fortsetzung ab Szene {n} von {total}` (ARB `de`/`en`)
      only when `resumed_from > 0`; widget test (**D-B5b**).
- [ ] 6.3 Regenerate `openapi.yaml` + the Dart client; bump versions per crate.
- [ ] 6.4 `ai-import.instructions.md`: the chunk table, the resume semantics, the
      invalidation rule **and** the one uncounted-spend sentence (**D-B4**).
- [ ] 6.5 PR 2 with the version-bump table.

## 7. [C] Retry policy

- [ ] 7.1 In-attempt retries read `bounds.max_attempt_retries` (not
      `max_retries`) in `retry_chat`/`retry_schedule` (**D-C1**).
- [ ] 7.2 Held jobs release the permit with the attempt; document the computed
      in-attempt worst-case window `(1 + max_attempt_retries) ×
      request_timeout_secs` and assert it as a constant in a test (**D-C2**).
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
