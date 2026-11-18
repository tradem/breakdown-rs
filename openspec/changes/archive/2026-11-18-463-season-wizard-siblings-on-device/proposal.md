<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4-flash (neuralwatt) -->
<!-- Co-authored-by: glm-5.3-flash (neuralwatt) -->

# Proposal: season-wizard sibling scenarios on-device harness (issue #463)

## Problem

The season-setup-wizard **happy path** is on-device green (issue #455's
derive repair landed in #464; the default pass reports 5/5 scenarios).
The three sibling scenarios in
`frontend-flutter/features-spec/setup/season-wizard.feature` remain
`@pending` — they were never on-device validated (the #368 run aborted at
the happy path's 409), and their first on-device passes exposed independent,
pre-existing harness gaps OUTSIDE the derive repair:

1. **Template application expands editable drafts**: after applying `3x6`,
   the `wizard-block-draft-$i` finder for `i=1..3` times out (30s) — the
   blocks-step ListView draft cards are not found by the FlutterDriver. The
   happy path never exercises these keys (it only asserts the structure
   string on completion), so this was never caught.
2. **Abort discards the drafts**: the final assertion waits for
   `seasons-empty-setup-cta` (the empty-state CTA), which only renders with
   ZERO backend seasons; under accumulated dev data the seasons home shows
   the card grid → false negative.
3. **Partial failure**: relies on the `/v1/__faults/block-conflict` latch
   + in-session retry; needs validation against the re-derived plan (retry
   must not re-derive).

## What Changes

- **`features-spec/setup/season-wizard.feature`:** remove `@pending` from
  the three sibling scenarios (they enter the default on-device `not
  @pending` pass); replace the harness-status re-pending block with the
  promotion record (mirroring the #459 costume-assignment promotion).
- **`integration_test/gherkin/steps/season_wizard_steps.dart`:** harness
  repairs for the three gaps:
  - **Template finder (gap 1):** the `three block drafts with 6 episodes
    each exist and stay editable` step scrolls the blocks-step ListView
    until each `wizard-block-draft-$i` is visible before asserting it and
    its `wizard-episode-count-$i` text (established
    `driver.scrollUntilVisible` pattern from the review-confirm repair —
    the blocks step is a non-lazy `ListView(children: [...])` with a
    viewport-limited build; `waitFor` alone times out off-viewport). The
    `I remove the first block draft` step scrolls draft 0 into view before
    tapping its remove button.
  - **Abort assertion (gap 2):** already repairable in #464-compatible
    form — the final `nothing was created and reopening starts fresh` step
    asserts the seasons home via `season-add-fab` (renders in BOTH the
    empty state and the accumulated card-grid state) plus
    `waitForAbsent(wizard-step-season)`, never the empty-state CTA.
  - **Partial failure (gap 3):** two on-device failures were found and
    fixed:
    - **The scenario never OPENED the wizard.** Its feature steps went
      straight from `Given ... the backend rejects the first block create
      with a conflict` to `When I complete the season setup with 2 blocks
      of 4 episodes` with NO `When I start the season setup wizard from
      the empty state` step (unlike its siblings). The "complete" step's
      `_advanceThroughSteps` then drove the seasons HOME, where no
      `wizard-next` exists — the advance hung deterministically (it was
      invisible while `@pending`). Added the wizard-start step. This is
      the root-cause of the deterministic hang; it is not a frame-sync or
      device issue (the other wizard scenarios pass the identical advance).
    - The **fault-arming Given runs host-side** (the test-runner process)
      but used the raw `API_BASE` (`http://10.0.2.2:3000` — the
      emulator-only loopback alias, unreachable from the host): the first
      on-device pass timed out at the 5s connection timeout before arming
      the latch. It now reaches the backend via the shared `hostApiBase()`
      (`10.0.2.2` → `localhost`, the same host-resolution the seed helpers
      use).
    - **The "complete" step now enters the host-resolved free SEASON
      number** (the happy path's resolution discipline). It previously
      relied on the smart default, which recomputes max+1 from the
      projection — but the happy path's dispatch takes that number mid-run,
      so the season create 409s with `season.number-already-exists` and the
      block fault never fires (the block-conflict narrative is then
      missing). Entering the free number keeps the season create
      conflict-free so the armed block fault is the FIRST failure, as the
      scenario contracts.
    - The retry-vs-no-rederive contract (a retry re-enters with its ACKED
      numbers locked — `_completedCommandsSoFar() != 0` skips the
      dispatch-start derive) is validated on-device by the scenario; no
      client logic change was needed.
- **`integration_test/gherkin/steps/seed_http.dart` (environment
  hardening):**
  - `GHERKIN_WIZARD_RESOLVE` stays behind the env flag; `tool/run_gherkin.sh`
    now defaults it **on** (issue #463): the promoted wizard scenarios
    dispatch against the accumulated dev series, so the free-series-scoped
    number resolution must be active for the default on-device pass, never
    a silent literal 1.
  - New `awaitBlockProjection` + `getJson(..., activeBlock:)`: the seed
    awaits the BLOCK projection before the character/costume POSTs use it
    as `X-Active-Block` (the parallel to the existing `awaitSeasonProjection`).
    An intermittent 404 `block.not-found` in the costume seed aborted the
    whole on-device suite before any scenario (projector lag on
    `projection_block`). Serves issue #463 criterion 4 — the default
    on-device pass must be fully green.
  - New `resolveFreeBlockNumber`: the seed previously created its block with
    `number == <free season number>`, but block numbers are unique per
    SERIES independent of season numbers — an accumulated series where a
    free season number coincides with an existing block made the seed's
    `POST /v1/blocks` 409 (`block.number-already-exists`), aborting the
    whole suite before any scenario. The helper now resolves a free
    series-scoped BLOCK number via the same per-season block iteration the
    wizard's own derive uses.
- **`features-spec/README.md`:** note the season-wizard scope is now fully
  promoted (no `@pending` left).
- **`tool/run_gherkin.sh`:** default `GHERKIN_WIZARD_RESOLVE=on` (see
  above).
- **`integration_test/gherkin/steps/common_steps.dart` (accumulation
  hardening):** the costume-assignment `I open the costume assignment for
  season` step's Planen-list scroll budget is raised from 15s to a bounded
  45s worst case. The seeded season now sorts at the END of the accumulated
  dev series (~72 seasons, deepest row ~6400px), and the old budget reached
  only ~5000px — the on-device run timed out fetching it. The new budget
  covers the analytic worst case deterministically.
- **OpenSpec change artifact** at
  `openspec/changes/463-season-wizard-siblings-on-device/`.

## Non-goals

- No backend change; no `backend/openapi.yaml` drift. The fault-injection
  control route from issue #443 (`POST /v1/__faults/block-conflict`) is
  already in the `test-support` build and stays out of the wire contract.
- No app-UI change: every widget key the scenarios assert already ships
  (the wizard, default draft, templates, review scroll, completion,
  retro-encoded abort FAB).
- No change to the `@critical` / `@pending` discipline gates
  (`tool/check_gherkin.sh` already accepts a fully promoted critical scope).

## Acceptance criteria (from issue #463)

- [x] Template scenario green on-device (draft-card finder fixed).
- [x] Abort scenario green on-device (assertion reconciled with accumulated
      data).
- [x] Partial-failure scenario green on-device (fault + retry against the
      re-derived plan).
- [x] All three removed from `@pending`; the default on-device pass is fully
      green.
