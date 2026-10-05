<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

## Why

The report surface is strictly day-scoped in the contract. #549 made the one
day-board entry findable, and #577 shipped the *reachability half* of #571: an
episode-scoped report index (`ReportsIndexScreen`) linking to the existing
per-day reports. What remains is the **aggregation half**: a user who wants
"wie lief die Staffel?" must still open the day report one day at a time. A
season- or scene-scoped report route does not exist, and a scene with 0 days
has nothing to report against beyond the #549 copy hint.

This change closes the remaining half with the four decisions the issue
deliberately left open, resolved at proposal time:

1. **Scope — season AND episode.** Both aggregation routes are nearly the same
   read query with different filters, and the decisions below apply
   identically. The scene case is *not* built: a scene with no shooting days
   is better served by the #549 report-provenance empty state than by an empty
   report (the issue itself flags this), and the per-day index from #577
   already covers the drill-down.
2. **Finality — server-derived, "all wrapped + ≥1 day".** `is_final = true`
   iff the scope has at least one non-archived shooting day and every one of
   them has `wrapped_at` set. Never recomputed client-side.
3. **Zero days — `200` with an empty report.** `rows: []`, day counts 0,
   `is_final: false`. No new problem code; the client keeps its localized
   empty state.
4. **Delivery — JSON + PDF twins.** Same packaging as the day-scoped routes.

Authz is **not** a new capability: the day-scoped report handlers are already
gated by `has_active_costume_role_in_season` (handler-internal
`AUTHZ-GATE`), so a member can already read every day's report. A season- and
an episode-scoped aggregate expose nothing wider; both handlers reuse the same
policy verbatim.

## What Changes

- **Two new JSON routes** serving an `AggregateSollIstReport`:
  `GET /v1/seasons/{id}/report/soll-ist` and
  `GET /v1/episodes/{id}/report/soll-ist`. Rows are one planned execution per
  `(scene, shooting day)` within the scope — the union of the day-scoped
  rows, each carrying its day's id and label so a scene planned on multiple
  days shows as multiple rows ordered by the day. Day counts
  (`total_shooting_days` / `wrapped_shooting_days`, non-archived) and the
  server-derived `is_final` travel with the report.
- **Two `.pdf` twins**: `GET /v1/seasons/{id}/report/soll-ist.pdf` and
  `GET /v1/episodes/{id}/report/soll-ist.pdf`, rendered via two new
  `ReportKind` variants (`season-soll-ist`, `episode-soll-ist`) and two Typst
  templates (day column + day-completion summary added to the
  planned-vs-actual layout).
- **Read-only** — no commands, no events, no migrations. The port
  `SceneShootReportRepository` gains `season_soll_ist_report` /
  `episode_soll_ist_report`.
- **Not archivable**: the aggregate kinds are deliberately not added to the
  archival trigger set (`ARCHIVABLE_KINDS` stays the three day-scoped
  kinds); the archival data loader rejects them explicitly.
- **Spec deltas**: `scene-shoot-reports` gains the aggregated-report
  requirements; `report-rendering` gains the two aggregate render kinds.
- Flutter half (regenerated client consumption, aggregate screens, spine
  entry, tier-3 scenario) — follow-up work on the same issue, split per the
  #577 precedent if it grows past a reviewable diff.

### Explicitly NOT in this change

- No scene-scoped aggregated report (the #549 empty-state stays the answer
  for day-less scenes; per-scene history remains reachable via the index).
- No archived days in the aggregate — they are excluded from counts and rows,
  mirroring `ShootingDayRepository::list_by_episode`.
