<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4-flash (neuralwatt) -->

# Design — Costume write version freshness (issue #473)

## Context

The Flutter costume screen follows the seasons reference pattern: a projector
read (`costumesViewProvider`, backed by Drift + `GET /v1/costumes`) and a
write side (`CostumesController`) that dispatches commands carrying an
`AggregateVersion` for the server's optimistic-concurrency guard. The backend
guard is **strict equality** (`cmd.version != self.version → 422
`domain.validation``), so a write must echo exactly the aggregate version the
server currently holds.

The existing overlay/version-fence machinery already advances `CostumeRowOverlay`
to the ack version, and `CostumeDetailScreen._resolveCostume` prefers the
fence-held overlay — which covers the single-screen happy path. The defect:
`updateNotes`/`addDetail`/`assign`/`unassign` build the wire request with
`version = costume.version` taken from the `CostumeView` **snapshot the screen
passes in**. Any path where that snapshot lags the acknowledged state — the
editor re-opened cached state, or a reconcile refetch result never fed back
into the view object the editor holds — echoes a stale version and produces a
silent `422` loop.

## Goals / Non-Goals

**Goals:**
- Every costume write resolves the echoed version from the freshest known
  state at command time.
- Consecutive writes to one costume succeed (save → save again → 200).
- A genuine optimistic-concurrency defeat surfaces a distinct pull-to-refresh
  narrative.

**Non-Goals:**
- No backend change (the equality guard is correct; `backend/openapi.yaml`
  untouched).
- No new fetch-before-write round-trip: the resolution is purely from already-
  known controller state, so there is no added latency or network risk.
- No Gherkin scenario: the costume flow already has on-device Gherkin coverage;
  a Tier-2 widget + controller regression satisfies requirement #2 without a
  heavyweight on-device addition (mirrors the #472 precedent).

## Decisions

**D1 — Resolve at command time from freshest known state.** A private
`CostumesController._resolveVersion(costumeId, fallback)` returns the maximum
version known for the costume across:
1. a held overlay's `overlay.version` (this client's latest ack — authoritative
   and above any lagging projection),
2. the reconciled projection row from `costumesViewProvider`,
3. the screen-passed `fallback`.
The maximum is the correct estimate: overlays and projections are both derived
from the same monotone aggregate (an ack never overtakes it, a projection can
only lag), so the max equals the server's current aggregate version — required
because the guard is strict equality (echoing a *lower* version 422s as today;
echoing a *higher* one would also 422).

**D2 — Apply uniformly to every write.** Wired into `updateNotes`, `addDetail`,
`assign` (first-assignment), `unassign`, and both legs of `_reassign` (the
intermediate unassigned overlay already carries the unassign ack version, so
the assign leg resolves to the same value — preserving the #454 sequence
contract).

**D3 — Distinct version-mismatch copy.** `concurrency.version-mismatch` (409)
and `costume.version_conflict` → "Changed elsewhere — pull to refresh and try
again." The generic `domain.validation` 422 is deliberately NOT blanket-mapped:
it also covers non-concurrency validation (e.g. the #472 wire-id defect), where
a pull-to-refresh narrative would mislead.

## Risks / Trade-offs

- The max-resolution trusts the monotonicity of aggregate versions (sound in
  this event-sourced backend). If a projection ever carried a version above
  the aggregate, an echo could over-shoot — but projections are derived from
  the aggregate's event stream and cannot exceed its current version.
- No new network fetch: the residual stale-cache-at-boot case (projector lag
  on cold start with no overlay) is still possible, but the max-resolution now
  prefers any fresher projection row the controller holds, and a genuine
  multi-user conflict on the live aggregate surfaces the new 409 narrative
  rather than a silent loop.
