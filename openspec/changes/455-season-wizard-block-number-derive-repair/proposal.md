<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# Proposal: season-wizard happy path 409s on series-scoped block number — harness derive repair

## What Changes

The season-setup-wizard Gherkin happy path (`features-spec/setup/season-wizard.feature`,
promoted in #442, re-pended in #456/#368) fails its first authoritative
on-device run: the dispatch's first `POST /v1/blocks` answers **409
`block.number-already-exists`** even though the wizard's
`seedDerivedNumbers` derivation looked free.

This change makes the derivation **hold against accumulated,
concurrently-mutated dev-series state** (numbers are unique per SERIES,
`idx_projection_block_series_number` — not per season). Concretely:

1. `seedDerivedNumbers` derives the first free series-scoped **block**
  number from **live, forced-fresh per-season block fetches** (via the
  screens' injected `blocksListFetchProvider`), never from the boot-time
  `seasonsView`/Drift cache — a cache read can be poisoned by concurrent
  harness writes and by a failed-fetch fallback that "degrades to base 1".
2. The dispatch **re-derives the series-scoped EPISODE base after the
  first block create**: episodes are `BlockMember`-scoped server-side
  (`GET /v1/episodes` requires `X-Active-Block`), so at wizard open the
  caller has NO block membership and the read honestly degrades to base 1
  — a freshly created block grants its creator ownership (the dispatch's
  existing AUTHZ-GATE scope-set), after which the series' episodes become
  readable via the new `EpisodeRepository.listBySeries`.
3. The derivation is **repeatable/re-derivable** and re-run at dispatch
  start (fresh plan only; a retry keeps its locked numbers). The
  [numbersSeeded] gate keeps its meaning (the derivation SETTLED before
  the advance/confirm lifts).
4. The **happy path was promoted to on-device green** (5/5 scenarios in
  the default run); its structure assertion was corrected to the actual
  append-template result (5 blocks · 40 episodes — "4x8" appends to the
  wizard's default draft). The three sibling scenarios expose independent
  pre-existing on-device harness gaps and remain `@pending` under a
  follow-up (#463).

The backend contract is untouched (`block/season/episode` number
uniqueness stays per series, server-enforced); this is a client-side
repair of the derivation to match the contract under accumulated,
concurrently-written state.

## Why

The bug is a **read-model race + TTL-cache staleness** interaction:

- The wizard derives from `seasonsView` (boot-time cache rows, possibly the
  retained-snapshot fallback of a failed/partial fetch) and reads each
  season's blocks through `blockRepository.listBySeason`, which serves
  **cached** rows whose `cachedAt` TTL may be fresh while the underlying
  projection is stale relative to concurrent harness writes.
- Harness seeding runs **concurrently in the same on-device run** (issue
  #368), so between the derive snapshot and the dispatch's block create the
  backend sees a number the derive believed free.
- The honest-fallback path *"a failed fetch degrades to base 1"* makes the
  worst part of this worse: a degrading fetch starts the plan at block 1,
  which the accumulated dev series has long taken.

## Impact / Non-goals

- **No API contract change**, no `backend/openapi.yaml` drift.
- **No offline-command queue** (AGENTS.md §8 — out of scope; the wizard
  stays online-first with the in-session retry).
- The `features-spec/setup/season-wizard.feature` **happy path is
  promoted to on-device green** (the third acceptance criterion). The
  three sibling scenarios stay `@pending` on their own independent,
  pre-existing on-device harness gaps (template draft-card finder,
  abort empty-state assertion, partial-failure fault interaction) —
  tracked in follow-up #463.

## Success Criteria

- `seedDerivedNumbers` derives block numbers from live per-season fetches,
  not the TTL cache; a stale/poisoned cache cannot skew them.
- The episode base is re-derived after the first block create (the wizard
  owns a block by then) so existing series episode numbers cannot 409 the
  plan.
- The derivation is repeatable and re-derivable on demand, with
  `numbersSeeded` still gating the advance/confirm.
- `features-spec/setup/season-wizard.feature` happy path reaches on-device
  green against the accumulated dev series.

## OpenSpec Decisions

| Q | Decision |
|---|---|
| Q1: repair the harness (seed before boot) or the derivation? | **the derivation** — seeding before every boot is fragile (the wizard may open before the projection settles) and cannot repair already-accumulated state; the derivation must hold by construction. |
| Q2: how to source the derivation reads? | **live refetch on demand** with the same repositories the screens use (never a second projection lookup of audit context; network is per-scope, bounded, Result-typed). |

## Tasks

- [x] 1.1 Rework `seedDerivedNumbers` to derive block numbers from live
      per-season block fetches (`blocksListFetchProvider`, forced fresh),
      never the boot-time `seasonsView`/cache.
- [x] 1.2 Add `EpisodeRepository.listBySeries` (series-scoped episode read,
      the backend `GET /v1/episodes?series_id=…`) and re-derive the episode
      base after the first block create (BlockMember scope granted by the
      created block) — the honest fix for the episodes route's
      `X-Active-Block` requirement.
- [x] 2.1 Controller unit tests cover the live-fetch read path, the boot-
      empty `seasonsView` immunity, repeatability, and the submit-time
      block re-derive.
- [x] 2.2 Updated the `flutter-season-setup-wizard` spec delta (derivation
      requirement: live refetch + post-first-block episode base).
- [x] 3.1 Happy path promoted and green on-device (`tool/run_gherkin.sh`,
      5/5 scenarios); structure assertion corrected to the append-template
      reality. Sibling scenarios deferred to follow-up #463.
