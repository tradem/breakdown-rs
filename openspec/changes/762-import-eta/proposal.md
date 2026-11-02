<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# 762 — Honest, cadence-based ETAs for extraction and apply progress

## Why

Issue #762 asks two questions from the 299 "Erlösung" import test: can the
extraction phase show an ETA, and can the apply phase show one too. Both are
feasible, but not with the data on the wire:

- `AiImportProgress` carries `stage`, `chunk`, `chunks_total` and
  `episodes_seen` — **no timestamps**. A client can only run a stopwatch while
  its own screen stays open; a reconnecting or restarted client (the SSE stream
  is snapshot-first, and closes as soon as the status is terminal) can never
  reconstruct a rate from counters alone.
- The apply is one synchronous `POST /ai-import/jobs/{id}/apply` with a button
  spinner: no applied-row counter, no stage, no ETA — and the existing job SSE
  stream is unusable for that phase, because the job is already `succeeded`
  (terminal) when the apply starts, so the stream closes on its first frame.

Two decisions shape this change:

1. **Never fabricate a countdown.** An estimate is advisory visibility data —
   never correctness state, never blocking. It is hidden while it is not
   defensible, rendered in coarse units, shown as a range when the cadence is
   unsteady, and dropped to "delayed" when frames stop.
2. **Byte-based denominators beat chunk counts.** One chunk is one scene, and
   scene lengths differ by an order of magnitude; the deterministic chunk scan
   already knows each chunk's size, so the byte pair is free to publish.

The work is delivered as two stacked PRs so each diff stays reviewable and CI
stays green on each:

- **PR 1 — extraction ETA** (this half): additive wire fields, the pure Dart
  estimator, the job-status screen line, l10n, tests, OpenAPI + Dart client.
- **PR 2 — apply progress**: an `apply_progress` field on the job view plus a
  dedicated `GET /ai-import/jobs/{id}/apply-events` SSE stream, the per-row
  throttled writes from `ApplyWorker::apply_script`, and the staged progress in
  the apply screen.

## What changes (PR 1)

### Wire (additive, `serde(default)`)

- `AiImportProgress.started_at: Option<DateTime<Utc>>` — the claim timestamp of
  the **current attempt**, published on every frame. `claim_next*` stamps
  `updated_at = now()` in the same statement that clears the stale counters, so
  the anchor and the counters always belong to one attempt and a retry restarts
  the estimate instead of inheriting the previous attempt's rate.
- `AiImportProgress.done_bytes` / `total_bytes: Option<u64>` — source-text bytes
  already extracted and the document's budget. `total_bytes` is the sum over the
  deterministic chunk sizes, `done_bytes` advances once per completed chunk;
  `None` means "no byte budget" (a schedule job is a single extraction unit) and
  is honest absence, never a fabricated zero.
- `AiImportProgress::set_byte_budget` / `record_done_bytes` keep the pair's
  invariant in core: the numerator saturates and is clamped to the denominator,
  so a client dividing them can never see a progress value above 1.

### Client (Flutter)

- `job_eta.dart` — a pure, deterministic estimator (`estimateAiJobEta`) with an
  explicit `now` and an optional `previous` frame:
  - `null` until **two** completed units exist (one unit is a single sample);
  - the remaining time is re-derived from an EMA of the per-unit cost on every
    frame, with the newest sample clamped to 1.5× the previous value, so a
    countdown never jumps backwards on one slow chunk;
  - bytes are preferred whenever `total_bytes > 0`, chunks are the fallback;
  - a remaining time beyond 24 h is refused as a broken anchor; a negative one
    clamps to zero;
  - `aiJobEtaStalled` drops the estimate when no frame arrived within 3× the
    observed cadence, clamped to 2–30 min (a chunk may legitimately take the
    provider timeout plus retries);
  - `aiJobEtaText` renders coarse units only ("ca. 3 min", "2–4 min", "2 h"),
    "almost done" under a minute (never `0 min`), "estimating …" while nothing
    is defensible and "delayed" on a stall.
- The job-status card renders that line only for a `running` job: a `pending`
  job is queued, and its wait is not extraction time. The 30 s ticker is local
  (no network), so the "no polling" decision of #547/#664 stands and the SSE
  stream stays the only source of job state.

### Compatibility

- A pre-#762 backend frame deserializes into the new fields as `None` → no
  estimate is shown. A pre-#762 client ignores the new fields.
- A job without counters renders byte-identically to the pre-change card, so
  the existing goldens pass unchanged.

## Out of scope (PR 2)

- The apply-progress channel, its SSE endpoint, the per-row throttling in
  `ApplyWorker::apply_script` and the apply screen's staged progress.
