<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# Tasks — 863

## 1. Core — one definition of the age

- [x] 1.1 `ApplyRunState` gains `owner_claimed_at: Option<DateTime<Utc>>` — the
      instant the current run took the slot, documented as owner-scoped (and as
      the reason it is NOT the row's `updated_at`).
- [x] 1.2 `ApplyRunState::owner_silence_at(now)`: payload stamp → claim instant
      → `None`; pure, so the fallback order is testable without a clock.
- [x] 1.3 The `apply_run_state` trait default reports **no** claim instant: a
      job DTO carries none, and guessing one from `updated_at` is the
      substitution the review rejected.

## 2. Infra — the stamp must leave the adapter

- [x] 2.1 Migration `20261106000002_ai_apply_claim_stamp` adds
      `apply_claim_at`; the claim writes it and its unpublished branch compares
      `COALESCE(apply_claim_at, updated_at)` (the rolling-deploy fallback).
- [x] 2.2 `PgAiImportQueue::apply_run_state` selects `apply_claim_at` into
      `owner_claimed_at`.
- [x] 2.3 The infra/API `FakeQueue`s mirror production: the claim stamps the
      claim instant and run-scoped writes do NOT touch it.

## 3. API — the refusal ages both states

- [x] 3.1 `apply_ai_import` derives the age from
      `ApplyRunState::owner_silence_at`, not from `progress`.
- [x] 3.2 The apply-stream handler's no-slot fallback reports no claim instant
      rather than substituting the job row's `updated_at`.
- [x] 3.3 `AiImportApplyInFlight`'s doc and the registry doc for
      `ai-import.apply-in-flight` say when the age is absent now (no stamp at
      all — a pre-#863 adapter), not "the owner published nothing".

## 4. Tests

- [x] 4.1 Core: the fallback order (payload wins, claim instant used when no
      payload, `None` when neither) as a pure unit test.
- [x] 4.2 Core: the trait default reports the job row's `updated_at`.
- [x] 4.3 API handler: a claim that published no frame is refused with BOTH
      extensions and an age bounded analytically by the claim stamp and the
      request window.
- [x] 4.4 API handler: a slot with no stamp still omits the age (never zero).
- [x] 4.5 Infra: the fake's claim stamp is what `apply_run_state` reports.
- [x] 4.6 Real Postgres (`ai_import_job_progress.rs`): a late run-scoped write
      cannot extend a claim's window; a pre-stamp claim reports no age but stays
      protected; the unpublished-claim steal test now forces the claim stamp.

## 5. Docs & release mechanics

- [x] 5.1 `docs/design/screens/ai-import-jobs.md`: the age is absent only when
      the slot names no stamp (pre-#863 server), not when the owner published
      nothing.
- [x] 5.2 `backend/CHANGELOG.md` + `backend/crates/core/CHANGELOG.md`
      `[Unreleased]` entries.
- [x] 5.3 OpenSpec delta spec validated (`openspec validate 863-apply-claim-age`).
