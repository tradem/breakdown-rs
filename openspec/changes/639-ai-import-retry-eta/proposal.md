<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (neuralwatt) -->

# Proposal: AI import job status — retry ETA and why earlier attempts failed (issue #639)

## Why

The AI-import job-status screen does not tell the user **how long until the
next planned retry** nor **why the earlier attempts failed**. During a stalled
import (e.g. 2 of 6 screenplay imports failing with `service unavailable:
Vault unavailable: KV read returned 403 Forbidden`, issue #637) the screen
shows only a spinner/"retry scheduled" and the current retry count, so the
user cannot tell whether to wait or act.

Issue #637 (merged) closed the backend observability half: `AiImportJob` now
carries `next_attempt_at` and a per-attempt `attempts` history
(`AiImportAttempt`). Two gaps remain:

1. **The client never renders the ETA.** `next_attempt_at` reaches the wire
   but `job_status_screen.dart` still renders only the retry budget
   (`retries`/`max_retries`) on a retryable `failed` job.
2. **The failure reason has no stable code.** `AiImportAttempt` carries only
   `error_summary`, a free-form `DomainError::to_string()` such as
   `service unavailable: Vault unavailable: KV read returned 403 Forbidden`.
   `frontend-flutter/AGENTS.md` §5 forbids the client from branching on that
   text — copy must be keyed on the stable problem `code`. Without a code on
   the attempt the client cannot localize the reason honestly.

## What Changes

### A. Backend — the attempt history carries the problem `code`

- `DomainError::code()` returns the variant's registry entry (ADR-031 D2), so
  the operational queue and the HTTP layer read the same stable `code`.
- `ai_import_job_attempt` gains an `error_code` column (migration
  `20261011000001_ai_import_attempt_error_code`); `mark_failed` /
  `mark_payload_unavailable` persist the code alongside the summary.
- `AiImportAttempt` exposes `code: Option<String>` on the wire (the registry
  code; `None` when the writer had no typed error, e.g. test seams).
- `backend/openapi.yaml` regenerated.

### B. Frontend — live retry ETA + code-keyed failure reason

- On a retryable `failed` job the screen shows a **live, localized "next retry
  in …"** derived from `next_attempt_at` (a `Timer.periodic` ticker; no
  fabricated countdown).
- The **reason the prior attempt(s) failed** renders on the retryable state
  too (not only on terminal cards), keyed on the attempt's problem `code`
  and localized from the ARB catalogs. The raw `error_summary` stays
  secondary detail only, exactly as `last_error` already is.
- **Honest degradation:** an absent/unknown `next_attempt_at` says "retry
  scheduled" (never a guessed time); an unknown `code` renders the generic
  localized reason (never the raw backend text as identity).

## Non-goals

- No change to the retry budget or the backoff curve.
- No new problem codes; existing registry entries are reused.
- No offline command queueing or client-side retry scheduling.
- No change to the jobs **list** screen (issue #547 owns it); this change
  touches only the pushed job-status screen.
