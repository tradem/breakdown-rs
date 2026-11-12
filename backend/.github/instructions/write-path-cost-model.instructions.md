---
description: Write-path cost model - what one SierraDB append costs and how that shapes commands (ADR-016 §6).
applyTo:
  - "crates/core/src/**"
  - "crates/infra/src/**"
  - "crates/api/src/**"
---

<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# Write-path cost model (SierraDB appends)

**Decision record:** ADR-016 §6 (`docs/architecture/adrs/ADR-016-sierradb-runtime-and-round-trip.md`).
**Measurement:** `scripts/bench-sierradb-append.py` (raw RESP3, asserts the success reply shape).
Numbers below are that baseline on the pinned `tqwewe/sierradb:0.3.1`, 2026-11-12, dev host
(btrfs on NVMe) — re-measure if the pin, the compose runtime or the `sync.*` settings change.

## One append is not one cheap write

SierraDB acks **after** it fsyncs, and a single append costs `1 + N` `fdatasync` calls, where `N`
is the number of events in that append (one for the segment data, one per event for the
confirmation-count header rewrite — `phase 5` of the cluster write path). Measured:

| Append | fsyncs | p50 (tuned runtime) |
|---|---|---|
| 1 event | 2 | ~4 ms (was ~50 ms before ADR-016 §6) |
| 5 events | 6 | ~11 ms |
| 20 events | 21 | ~41 ms |

For comparison: one Postgres single-row upsert on the same host is ~0.3 ms. An append is
~15–150× more expensive, so the number of appends — not the number of events — is what a write
path must economise.

## What that means for a command path

- **One command = one aggregate append** stays the rule (ADR-015). A command's *whole* event batch
  belongs in that one append: two events emitted as two appends pay two full sync rounds for one
  user action (`Command::handle` already returns `Vec<Event>` — use it).
- **No chatty write paths.** A "command per beat", "per figure" or "per row" loop multiplies the
  `1 + N` cost by the row count (the 49-scene AI-apply issues ~740 appends, issue #900). Batch at
  the domain level — one command carrying the rows — instead of looping the client.
- **Concurrency hides the tail, it does not remove it.** Parallel appends share one sync, so a
  throughput check can look healthy while a sequential UI chain pays a full tick per step. Measure
  both shapes (`--case parallel` *and* `--case warm`), never just one.
- **Never "fix" a slow write path by relaxing durability** (no-fsync, moving writes off the event
  store, fire-and-forget dispatch). Crash-safety is a product property: it needs an ADR, not an
  optimisation. The `sync.*` knobs ADR-016 §6 uses do not touch durability — the store still
  fsyncs before it acks; they only change how long an append waits for the next sync poll.
