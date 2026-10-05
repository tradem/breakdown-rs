<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3-flash (opencode-go) -->

# Design — 571-aggregate-soll-ist-report

## D1 — Rows are per `(scene, shooting day)`, not per scene

A scene can be planned on several days (pair-uniqueness guarantees at most one
`SceneShoot` per `(scene_id, shooting_day_id)`). Collapsing it to one row per
scene needs undefined merge rules (which day's planned order? which status?),
while the union of day rows is exactly what the day-scoped report semantics
promise: moved = `actual_order` ≠ `planned_order` on that day, missing =
planned but without execution data on that day, skipped = status, reshot =
the scene has a `Shot` record on *another day of the same scope*. Rows carry
`shooting_day_id` + `shooting_day_label` and are ordered by the shooting
day's `order_key`, then `planned_order`.

## D2 — Finality is computed by one server-side SQL summary

`is_final = (total >= 1 && wrapped == total)` over **non-archived** days of
the scope. A season/episode exists but has no days → `200` with
`total == 0`, `wrapped == 0`, `is_final == false` (decision 3) — never
vacuously final. The client renders state from the counts, never from
recomputing the rule.

## D3 — Authz reuses the existing season-membership policy, no new capability

Both handlers walk (season: none; episode → block) to the season and call
`has_active_costume_role_in_season` inside the handler (`// AUTHZ-GATE:`) —
the same gate as every day-scoped report handler. A member who can read each
day's report can read the union; no capability widening. Middleware
requirements: `/seasons/*` is already `Authenticated`; a new
`requirement_for` arm makes `/episodes/{id}/report/soll-ist` `Authenticated`
(mirroring the shooting-days JSON reports). The `.pdf` twins are covered by
the existing `.pdf && /report/` arm.

## D4 — Not found vs empty

An unknown season/episode id answers `404 season.not-found` /
`episode.not-found` through `DomainError::NotFound` — distinct from the
200-empty answer for an existing scope with zero shooting days (decision 3).

## D5 — PDFs render through the direct renderer path

The aggregate PDF handlers construct a `ReportRenderRequest` with the new
`ReportKind::SeasonSollIst` / `EpisodeSollIst` and call the renderer directly
(the archival `ReportDataLoader` pipeline stays day-scoped). New embedded
templates are adapted copies of `planned-vs-actual.typ` with a Drehtag column
and a day-completion summary block. The archival kinds list
(`triggers.rs`) and the JSON report contract stay untouched; the backup
loader gains explicit rejection arms so an aggregate kind can never leak into
an archivable job.

## D6 — Failure modes preserved from the day handlers

No panics (clippy deny), static SQL literals with `.bind()` only, no partial
PDF bytes on render failure, `Cache-Control: private, no-store` equivalent
headers as the day-scoped PDF handlers produce, and fail-closed ordering:
policy check before querying rows/rendering.
