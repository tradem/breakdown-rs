<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024 Breakdown RS Contributors -->
<!-- Co-authored-by: space-bunny-free (opencode-go) -->

## Context

`ReportsScreen` is day-scoped by design decision D8 and is fully shipped
(#549 → PR #572): a labelled entry (`reports-open`) in the day board's app
bar, a strict parser over the generated report DTOs, PDF cards, and a
client-side `AUTHZ-GATE` on `currentMembershipProvider(seasonId)` that
issues **zero** requests on denial.

The gap is one level up. `ShootingDaysScreen` is the episode's list of
Drehtage — the natural place a user stands to ask "which of my days have a
report?" — and it is a **dead end**:

- `ShootingDayTile` is constructed with `onRename` / `onReschedule` /
  `onUnschedule` / `onArchive` / `onMoveUp` / `onMoveDown`. There is no
  `onTap`, and the tile renders no navigation target. (grep for
  `onTap|InkWell|ListTile` over the screen's own `ShootingDayTile` call
  site: the only `ListTile` is inside the tile widget itself.)
- The only inbound path to a day board is
  `scenes/scene_detail_screen.dart:490` → `SceneShootsScreen`.

Issue #571 asks for a season- or scene-scoped **report**. That is the
aggregation half and it carries four deliberately unmade decisions (scope,
authz widening, whether a day-less report is meaningful at all, and the
aggregate finality rule for multi-day reports). This design delivers the
**reachability** half instead, at zero backend cost, and leaves those
decisions unmade rather than guessed.

The key enabling fact: `ShootingDayView` (already on the wire, already in
the client's Drift cache) carries `label`, `date` and **`wrapped_at`** — the
same `wrapped_at` the day-scoped report derives its `final` flag from. An
index of days with per-day finality therefore needs **no** new query, **no**
new DTO and **no** new route.

## Goals / Non-Goals

**Goals:**

- Make every per-day report reachable in one hop from the episode's
  shooting-days list.
- Show, per day, whether that day has a report that is already
  `abschließend` (wrapped) or still `offen` — from the day's own
  `wrapped_at`, server-derived, never recomputed.
- Reuse the existing membership gate and the existing `ReportsScreen`
  unchanged; add zero network traffic and zero new persistence.
- Keep the D8 anchor honest: the index renders **no report content**; the
  per-day report screen remains the only renderer of report data.
- Reinstate #549's deleted `open-soll-ist-report-$seasonId` Gherkin step
  against a key that now exists.

**Non-Goals:**

- Any backend change: no route, no `openapi.yaml` edit, no client
  regeneration, no `SceneShootReportRepository` method, no
  `problem_codes!` entry.
- Any aggregated season-/scene-level report, and any aggregate finality
  rule (any/all unwrapped). The index deliberately shows *per-day* state
  and never presents a season-level verdict.
- Any new authorization capability. The index reuses
  `has_active_costume_role_in_season` via `canViewReports` — defensible
  precisely because the index exposes no report content, only day labels,
  dates and per-day finality that the day list already shows.
- Any change to the per-day `ReportsScreen`'s contract, parser, PDF cards
  or gate.
- Making the day rows themselves tappable. See Decision 5.

## Decisions

### 1. Episode-scoped index, not season-scoped

**Decision:** the index is scoped to one **episode** and is pushed from
`ShootingDaysScreen` (the episode's day list).

**Rationale:** the rows are already in memory there
(`shootingDaysControllerProvider(episodeId)`), so the index costs no
fetch. A season-scoped index would need a new season-wide day list (or a
client-side roll-up over blocks and episodes), which is aggregation again
— the thing being deferred. Episode scope is also the granularity at which
a "Drehtage" list already exists as a user-facing concept.

**Alternative considered — season-scoped index driven by the client from
the hierarchy spine:** rejected. It would require the client to walk
blocks → episodes → days, i.e. either three projection reads or a cached
tree; that is a *client-side aggregate*, which is exactly the shape the
client CQRS boundary (D2) and the server's `final`/aggregation semantics
argue against. It also pre-empts the scope decision #571 deliberately left
open.

**Alternative considered — scene-scoped index:** rejected. A scene's days
are already visible on the scene detail screen, which is the path that
*does* work today; an index there would duplicate an existing list.

### 2. No new fetch: the index reads the existing day-list controller

**Decision:** `reportsIndexControllerProvider(episodeId)` **watches**
`shootingDaysControllerProvider(episodeId)` and projects its `rows` into
index rows. It issues no HTTP request and adds no Drift table.

**Rationale:** the index is a pure projection of state the user is already
looking at. Reusing the controller also inherits the established
projection-lag machinery for free (cached rows stay visible and
stale-indicated on failure, `AsyncError` carries the problem `code`,
optimistic overlays reconcile with a bounded retry) instead of
re-implementing it.

**Alternative considered — a dedicated `reportsIndexRepository` with its
own fetch + cache:** rejected as duplicated projector-lag machinery for
data already in the cache; it would also create a second source of truth
for the same day list.

### 3. Per-day finality from `wrapped_at`, and only per-day

**Decision:** each index row renders an `abschließend` / `offen` state read
directly from that day's `ShootingDayView.wrapped_at`. The index shows **no
season-, episode- or scene-level verdict**, and no "N of M days complete"
summary.

**Rationale:** the day-scoped report already exposes exactly this
finality, server-derived. Surfacing the same per-day signal one level up
is honest and free. The moment the index shows an aggregate, it must
invent the any/all-unwrapped rule that #571 left open — and an invented
aggregate finality, once rendered, becomes the number users trust. Not
shipping it is the correct call, and it is what keeps this change a
navigation surface rather than a half-built #571.

**Alternative considered — an aggregate "x von y Tagen abgeschlossen"
counter:** rejected for exactly the reason above; it is the aggregate
finality decision wearing a small hat.

### 4. Optimistic overlay rows are excluded from the index

**Decision:** only `ProjectedShootingDayRow`s are listed. A day still in
the optimistic overlay (acknowledged by the command, not yet projected) has
no `ShootingDayView`, therefore no `wrapped_at` and no server state to
report on; the index shows the same stale/pending banner the day list
shows instead of listing a row whose report state is unknown.

**Rationale:** an index row that cannot state its own finality would have
to guess (or render an indefinite "unknown" chip that looks like a third
state). The overlay is a transient command-acknowledgement artefact, not a
day; the day list remains the place to watch it reconcile.

### 5. The index is a new screen; the day tiles stay non-navigating

**Decision:** the tile's action set is unchanged. The single new
affordance is the labelled reports action in `ShootingDaysScreen`'s app
bar, which pushes the index.

**Rationale:** the day tile is already action-dense (six callbacks). A
seventh tap target competing with the row's existing swipe/menu actions
would make both harder to use, and would make the "one tap to a report"
promise depend on hitting the right part of a dense row. Keeping the entry
in the app bar also matches the entry form #549 established and the
glossary's visible-label norm (`docs/design/screens/README.md:179`).

**Alternative considered — make the day rows tappable straight to their
report:** rejected: it skips the overview (the user still cannot see which
*other* days have reports), it crowds the tile, and it would duplicate the
day-board hop's own navigation. The `shooting-days` dead end is resolved by
the index entry, not by a second per-row affordance.

### 6. `season_id` is threaded as nav context, never looked up

**Decision:** `ShootingDaysScreen` gains a required `seasonId` parameter,
passed by `EpisodesScreen` from `block.seasonId` — the same field
`ScenesScreen` already receives on the adjacent push.

**Rationale:** `EpisodeView` carries `block_id` and `series_id` but **no**
`season_id`, and the reports gate needs the season id. Resolving it with a
`GET /v1/blocks/{id}` (or an episode-side season lookup) would be a second
projection read to fill in context — the client-side CQRS boundary (D2)
that `AGENTS.md` §1 mirrors from the backend. Threading the already-known
parent field is free and keeps the hierarchy spec's "ids come from the
parent DTO" rule intact.

**Alternative considered — a shell-level `activeSeason` read:** rejected.
The spine supports browsing a season that is not the active one
(`PlanningLocation` exists precisely to carry foreign-season context), so
an active-season read would be wrong for a browsed-but-not-active season.

### 7. The index reuses the day-scoped gate, with no report fetch of its own

**Decision:** the index evaluates the same
`currentMembershipProvider(seasonId)` → `canViewReports` gate
(`report.forbidden` on denial, `membership.pending` / `membership.unavailable`
on unresolved membership) and, on denial, renders the localized 403
narrative **without issuing any request** — the client-side `AUTHZ-GATE`
mirroring D6.

**Rationale:** the index needs a gate because a denial must be visible
before the user taps through, and because the per-day report screen it
pushes is itself gated. But the index has nothing to fetch, so the gate
here is purely a **pre-check for the destination** — it must not be
mistaken for a new backend authorization surface. That distinction is the
reason reusing the existing capability is honest: the index reads day
labels, dates and per-day finality that the episode's day list already
exposes to the same user.

**Alternative considered — no gate on the index at all:** rejected. The
day list is membership-scoped differently from reports, and a user who
cannot view reports should not be walked into a 403 by tapping through a
screen that looked available.

## Risks / Trade-offs

- **The index is a list of links, not a report — a user may expect a
  summary and find none.** → Accepted deliberately. The screen's title and
  the per-row `abschließend` / `offen` state set the expectation honestly,
  and the `flutter-reports-index` spec forbids a season-level verdict so a
  later "just add a summary" cannot land without a spec decision. This is
  the one risk users may actually feel; the empty-state copy and the
  per-day finality chip are what keep it legible.
- **Two taps where the day board is one hop away from a scene.** → The
  scene path is unaffected and remains the shortest route for a
  scene-specific question; the index exists for the episode-wide question
  that path cannot answer.
- **Reusing `shootingDaysControllerProvider` couples the index's content to
  the day list's fetch state**, so a day-list failure surfaces on the index
  too. → Accepted: identical data, identical failure, identical stale
  semantics. Duplicating the fetch would produce two divergent views of
  one projection, which is worse.
- **Threading `seasonId` is a signature change on `ShootingDaysScreen`.** →
  It is a required named parameter with exactly one call site; the compiler
  enumerates any other. No silent `null` season, no fallback lookup.
- **The change lands without resolving any of #571's four open decisions.**
  → Intended, and stated in the proposal's explicit non-goals so #571
  inherits a documented, evidence-backed starting point rather than an
  unexamined assumption.

## Migration Plan

None. No backend, no contract, no persistence, no data migration. The
change is additive on the client and fully revertible by dropping the new
screen, the app-bar action and the `seasonId` parameter.

## Open Questions

- **Should the index ever be pinned to a season instead of an episode?**
  Deferred to #571. If a season-level index is ever wanted, it needs its
  own day-list source and a decision on how foreign-season context is
  resolved — not a parameter change on this screen.
- **Should a day that is `archived` appear?** Today
  `ShootingDayRepository::list_by_episode` excludes archived days, so the
  index inherits that exclusion for free. If archived days ever become
  reportable, the exclusion becomes a product decision rather than an
  inherited one.
