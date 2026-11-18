<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: space-bunny (opencode-go) -->

## Context

`lib/features/shell/` already hosts the adaptive navigation suite
(`NavigationBar` / `NavigationRail` / `NavigationDrawer`) built from ONE
destination list (`ShellDestinations._specs`) plus a `ShellController`
carrying `{selectedIndex, activeSeason}`. Issue #610 changes the
destination *set*, not the machinery: four destinations become three.

Current tab roots and what they carry:

| Tab | Root | Carries |
|---|---|---|
| Season (0) | `SeasonsScreen` | seasons overview, create FAB, empty state; rows do **not** navigate |
| Planen (1) | `PlanningTabScreen` | season list (sets the active season) → blocks → episodes → scenes spine, AI-import entry, active-jobs row |
| Kleidung (2) | `CostumingTabScreen` | two-entry launcher: `CostumesScreen`, `CharactersScreen` |
| Mehr (3) | `MoreTabScreen` | identity, costume categories, About, Settings, Sign out |

Constraints that shape the design:

- **Season scoping must survive.** `ShellState.activeSeason` is the sticky
  season reference (persisted per session, resolved against the live
  projection). Dissolving the Season tab removes the surface that *sets*
  it, so the setter has to move somewhere always visible.
- **The scene read model is episode-scoped.** `GET /v1/scenes` requires
  `episode_id`; there is no season-wide scene route. A "chronological
  1..40 script" therefore requires a client fanout blocks → episodes →
  scenes (client-side, bounded, read-only — see issue #550, whose fanout
  regression is why the fanout is explicit and instrumented here).
- **The costume-categories placement is a hard acceptance criterion**, not
  a preference (issue #610; confirmed by #613): categories must live with
  the costume/character content and never with user settings.
- Glossary-driven copy: every label/icon comes from
  `docs/design/glossary.md`; icon-only destinations are forbidden.
- Sibling issues in the same navigation family: #611 (role-extract depth,
  out of scope), #612 (plus quick-create action, out of scope), #613 (final
  top-bar design + OmniSearch — this change ships only the minimal profile
  affordance #610 needs).

## Goals / Non-Goals

**Goals:**

- Three task-oriented destinations — **Cast | Script | Schedule/Dispo** —
  in all three morphologies, with visible labels and "Tab N of 3"
  semantics.
- One sticky, shell-owned scope surface carrying **season + block**, with a
  picker that also reaches season management and the production spine.
- The costume surface (costumes + characters + category vocabulary)
  integrated into the Cast view.
- All tab-index / destination-key / gherkin bindings migrated in the same
  change (no silent key drift).

**Non-Goals:**

- The per-character role-extract depth (#611) — Cast ships the characters
  list/detail it has today.
- The plus quick-create action (#612).
- The final top-bar design and OmniSearch (#613) — this change ships the
  minimal profile menu only.
- Any backend change or new read route. The Script fanout is composed from
  existing `Authenticated` routes.
- Re-designing `CharactersScreen`/`CostumesScreen`/`ShootingDaysScreen`
  themselves (their controllers, keys, repositories and AUTHZ-GATE comments
  stay as-is; only their entry points move).

## Decisions

### D1 — Destination set: Cast | Script | Schedule/Dispo

Order follows issue #610's table and the PO's operating rhythm: who is in
front of the camera (Cast), what the text says (Script), when we shoot it
(Schedule/Dispo).

| Index | Label (de) | Glossary icon | Root |
|---|---|---|---|
| 0 | `Cast` | `face` / `face_outlined` | `CastTabScreen` |
| 1 | `Script` | `menu_book` / `menu_book_outlined` | `ScriptTabScreen` |
| 2 | `Schedule/Dispo` | `calendar_month` / `calendar_month_outlined` | `ScheduleTabScreen` |

The Cast label stays the industry term for the actor roster (the glossary
keeps „Figuren" for a single character row); `Schedule/Dispo` keeps the
German production term and the day board's own vocabulary. Alternatives
considered: (a) keeping `Planen` and renaming `Garderobe` → rejected, it
reproduces the model-oriented grouping the issue dissolves; (b) four
destinations with a `Mehr` tab → rejected, `Mehr` must die for the profile
menu to have a home.

`kCastTabIndex`/`kScriptTabIndex`/`kScheduleTabIndex` replace the four old
constants **without aliases**: the issue asks for an explicit migration, and
a silent alias would let stale bindings keep compiling. `selectTab` rejects
indices outside `0..kScheduleTabIndex`.

### D2 — Season + block scope in the shell context bar

The context bar (`ShellContextBar`, issue #548) already owns "what filters
your requests" and renders in all three morphologies. A season chip joins
the block chip there; both are hidden when unset, so a fresh install keeps
the minimal bar.

- The **season chip** shows the active season's number/title and opens the
  season scope picker.
- The **block chip** (`ActiveScopeChip`) keeps its current behaviour,
  including the foreign-season and unknown-block narratives and the
  cache-only backfill.

The season picker is one screen with three entry kinds:

1. season rows → `setActiveSeason(row)` **and** pop (CQRS boundary: the id
   comes from the acted-on read row, never a second lookup);
2. `Saisonen verwalten` → `SeasonsScreen` (push);
3. `Produktion verwalten` → `ProductionOverviewScreen` (push).

Alternatives considered: a per-view AppBar chip — rejected, it duplicates
the scope surface three times and re-opens the "which scope am I in?"
question when switching views; a seasons list inside the Cast view —
rejected for the same reason.

### D3 — Cast view integrates costumes and the category vocabulary

`CastTabScreen` renders a two-way segmented switch (Figuren / Kostüme)
over the existing season-scoped `CharactersScreen` and `CostumesScreen`,
plus a `Kategorien` app-bar action pushing `CostumeCategoriesScreen` for
the active season.

Rejected: (a) a launcher hub with two entries (that is the current Kleidung
tab — an extra tap for the most-used content); (b) a categories sheet from
the costume list — rejected because the vocabulary then hides behind a
second surface while the user is mid-assignment; a Cast-view app-bar action
keeps it one tap from both the roster and the costumes.

Both list screens keep their controllers, repositories and AUTHZ-GATE
comments; only the entry point changes. They are embedded as tab content
(nested `Scaffold` under the Cast root's AppBar) — the per-feature goldens
pump them directly and stay untouched.

### D4 — Script view: season-wide chronological scene list

`GET /v1/scenes` is episode-scoped, so `ScriptTabScreen` composes:

```
blocks (GET /v1/blocks?season_id=)
  → episodes (GET /v1/episodes?block_id=)
    → scenes (GET /v1/scenes?episode_id=)   [concurrent, bounded]
      → merged, sorted by scene_number, contiguous numbering asserted by the UI
```

The fanout is a pure read composition in `lib/features/scenes/`
(`seasonScriptController`), returning `Result`-typed rows with an explicit
`Partial` degradation: a failing episode yields a visible
`scriptPartialLoad` banner rather than an empty script (silently dropping
episodes would misrepresent the schedule). Row tap pushes
`SceneDetailScreen` with the scene DTO as navigation context (CQRS
boundary). Alternative: episode-grouped sections — rejected, the issue asks
for one continuously numbered overview; the episode grouping is available as
a secondary label on each row.

### D5 — Production overview replaces the Planen tab

The block/episode spine, the AI-import entry and the active-jobs row move
into `ProductionOverviewScreen`, pushed from the scope picker. It keeps
`PlanningTabScreen`'s content minus the season list (season management is
`SeasonsScreen`'s job now, one picker tap away), so `planning_tab_screen.dart`
and its tab-root role disappear.

### D6 — Minimal profile affordance

`ProfileMenuButton` is a shared app-bar action mounted by all three view
roots: identity tile (non-interactive, same `menu-identity` key contract
as today), `Über die App` (dialog), `Einstellungen` (full-screen push,
unchanged), `Abmelden` (the `SessionReset` coordinator, unchanged). It is
deliberately minimal: #613 owns placement (including the rail/drawer
morphology question) and adds OmniSearch beside it.

### D7 — Key, semantics and binding migration

- Keys: `shell-destination-0..2` (count shrinks with the destinations).
- Semantics: `seasonTabSemantic(label, n)` with n of 3.
- Navigator debug labels: `shell-tab-0-cast`, `-1-script`, `-2-schedule`.
- Screen keys migrate with their screens where the name is no longer true:
  `planen-list` → `script-list` / `production-list`, `kleidung-*` →
  `cast-*`, `mehr-*` → `profile-*`. Stale keys are removed, not aliased:
  a binding that silently keeps working is a binding nobody re-checks.
- Gherkin steps, `tab_switch_smoke_test.dart`, `settings_base_test.dart`,
  `app_shell_test.dart` and `shell_controller_test.dart` move in the same
  change.

## Risks / Trade-offs

- **Fanout cost/latency on the Script view** → bounded by the season's
  block/episode count, requests issued concurrently, results cached in Drift
  by the existing per-episode fetch seams; a failing episode is surfaced as
  a partial-load banner, never as a silently shorter script.
- **Nesting `CharactersScreen`/`CostumesScreen` under the Cast root's
  AppBar** → inner Scaffolds render their own AppBar under the Cast one; the
  resulting double title is accepted for v1 (both titles are the same
  domain), and the alternative (extracting body-only widgets) would touch
  ~60 unaffected goldens.
- **Dropping the `Mehr` tab before #613** → settings/sign-out move to the
  minimal profile menu in the same change, so nothing is unreachable;
  #613 refines placement afterwards.
- **`_sessionKey`-scoped season persistence** → unchanged; resetting the
  tab index on a session change now resets to the Cast view.
- **Breaking test-key/gherkin bindings** → intentional and explicit: the
  migration is enumerated in the spec deltas and verified by the migrated
  tests, and no old key is kept as an alias.
