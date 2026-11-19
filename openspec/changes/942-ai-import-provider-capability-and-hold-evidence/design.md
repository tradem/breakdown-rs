<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# design — 942 (W1–W3)

Companion to `proposal.md`. Decisions are `D1…D7` there; this file records the
mechanisms, the seams and why each is where it is.

## 1. Two-stage breaker recovery (W1, D1–D5)

### Capability table (pure, in `core::ai::ports`)

```rust
pub enum ProbeCapability { KeyEndpoint, LocalTags, NoPreflight }

pub const fn probe_capability(provider: LlmProvider) -> ProbeCapability {
    match provider {                       // no catch-all arm on purpose:
        EURouter | OpenRouter => KeyEndpoint,   // a new variant fails the build
        Ollama => LocalTags,                     // until its capability is decided
        OpenAI | Gemini | Neuralwatt | OpenCode | OpenCodeGo => NoPreflight,
    }
}
```

`KeyEndpoint` = authenticated `GET {base}/key` (zero tokens, verifies the
credential *and* reads the balance). `LocalTags` = today's unauthenticated
`GET {base}/api/tags` for Ollama. `NoPreflight` = no synthetic metadata read; the
elapsed window is the gate. Curated base URLs only (ADR-024), never user input.

### State machine (pure, `core::ai::provider_health`)

| from | trigger | to | `flap_count` | notes |
|---|---|---|---|---|
| `closed` | `threshold` consecutive retryable failures | `open` | `flap_count_on_open` | unchanged (#871) |
| `open` | `try_begin_probe` (lease CAS) | `half_open` | — | lease held, **no** trial token |
| `half_open` | `finish_probe(Usable)` | `half_open` | unchanged | **`trial_due = true`** — supersedes D-A6's `half_open → closed` |
| `half_open` | `finish_probe(NotUsable)` | `open` | unchanged | window re-armed from the current count |
| `half_open` | retryable **trial** failure | `open` | **+1** | new incident; `opened = true` re-materializes the holds |
| `half_open` | paid call answered (`record_success`) | `closed` | unchanged | the **only** closer; releases the pair's held jobs |
| any | `closed`/`open` transition | — | — | `trial_job_id` is nulled unless the new state is `half_open` |

`ProbeOutcome` was renamed `Reachable/Unreachable → Usable/NotUsable`: the old
names described "something answered", which is precisely the verdict that could
not protect the fleet.

### The trial token and the claim fence (D3)

`ai_import.provider_health.trial_job_id UUID` (migration
`20261119000001_provider_trial_token`). `ProviderHealth::begin_provider_trial`
picks the pair's longest-waiting held job in **one** statement (token minted +
`next_attempt_at = now()` + window re-armed, guarded by
`state = 'half_open' AND trial_job_id IS NULL` so two sweepers cannot both win).

The four claim predicates gain:

```sql
AND NOT (ph.state = 'half_open'
         AND ph.trial_job_id IS NOT NULL
         AND ph.trial_job_id = ai_import.ai_import_job.id)
```

The `IS NOT NULL` guard is load-bearing: with a NULL token the comparison yields
NULL, `NOT NULL` is NULL, and the row would be **admitted**.

Why SQL and not the in-process gate: `admits_billable_request` /
`ProviderGate::admits` run inside an already-claimed job and never see a job id.
They therefore ask `admits_paid_call()` (`closed` **or** `half_open`), which
cannot admit a second caller — no other job of the pair is claimable while the
breaker is not `closed`. `admits_claim()` keeps its `closed`-only meaning for
anything that reasons about claims.

### One request per trial (D4)

`ProviderGate.trial` is computed once per attempt
(`trial_pending(queue, provider, model, job.id, breaker_enabled)`), and
`retry_bounded` applies `gate.attempt_retries(configured)` → `0` for a trial.
A failed read answers `false`: without a verdict the attempt keeps its configured
budget rather than being demoted to one call on a guess.

## 2. Hold evidence (W2, D6)

`retry_bounded` captures `hold_evidence(&error)` (bounded summary +
`error.code().code`) **before** any sentinel replaces the failure, and returns
`CallFailure { error, evidence }`. `retry_chat`/`retry_schedule` propagate it
(they used to downcast the anyhow chain and lose everything but the sentinel).
`hold_job(..., evidence)` → `mark_held(..., evidence)`.

`mark_held` runs one CTE:

```sql
WITH before AS (SELECT provider_hold_series_started_at FROM … FOR UPDATE),
     held   AS (UPDATE … RETURNING id),
     recorded AS (
       INSERT INTO ai_import.ai_import_job_attempt
         (id, job_id, attempt_no, status, error_summary, error_code, retryable)
       SELECT $7, held.id, job.retries + 1, 'failed', $8, $9, TRUE
       FROM held JOIN before ON TRUE JOIN … job ON job.id = held.id
       WHERE before.provider_hold_series_started_at IS NULL
     )
SELECT pg_notify('ai_import_job_events', id::text) FROM held
```

`WHERE before.provider_hold_series_started_at IS NULL` is the "one row per
series" rule: the row is appended exactly when this write starts the series.
`attempt_no = retries + 1` matches `mark_payload_unavailable`'s numbering for a
transition that leaves `retries` alone. A hold with no first-hand failure (the
breaker was already non-closed when the attempt looked) gets a synthesized reason
in `mark_held` instead of an empty row. `hold_runnable_jobs` (the sweeper's
materialization) intentionally writes no row: it has no first-hand failure.

## 3. Quota taxonomy (W3, D7)

`AI_IMPORT_PROVIDER_QUOTA_EXHAUSTED` (`ai-import.provider-quota-exhausted`, 402)
in `problem_codes!`, `de`/`en` Fluent texts, and
`DomainError::LlmProviderQuotaExhausted::code()` maps to it.
`classify_http_status_rich` returns that variant for `402 Payment Required`
before the generic `RetryClass` mapping, which covers the extraction client and
`decision_client` (both funnel through it). `is_retryable()` stays `false`, so
`retry_bounded`'s `is_transient` guard still refuses to count it toward the
breaker (#927's invariant, `provider_gate_tests`).

## 4. Compliance

| Rule | How |
|---|---|
| ADR-031 (registered code + Fluent, no raw `detail`) | one `problem_codes!` entry, `problem-ai-import-provider-quota-exhausted` in both bundles, `PROBLEM_CODE_COUNT` 113 → 114 |
| ADR-027 / ADR-035 B2 | no new handler in this PR, no new `*_in_season` predicate |
| ADR-024 | `/key` uses the curated base URL and the curated redirect policy client; no user-supplied URL |
| ADR-040 | `jiff::Timestamp` + `infra::db_time` (`sql_ts`, `sql_ts_opt`, `get_ts_opt`) only |
| No panics / no discarded results | `unwrap_or*`/`map_or` fallbacks everywhere; the trial grant's `None` is logged, not dropped |
| Static SQL literals | every new statement is a `&str` literal with `.bind()` values |
| Poor Man's DI / `Arc` discipline | `ProviderHealth` owns the breaker row; the queue delegates nothing into it and the probe takes both as ports |
| Wire hygiene | no credential, no raw upstream body and no `vault_key_id` crosses the wire; the evidence summary is the already-bounded classifier text |
