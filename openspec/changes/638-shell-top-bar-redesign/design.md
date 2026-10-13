<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (neuralwatt) -->

# Design — 638 shell top bar redesign

## Context

`AppShell.build` returns a `Scaffold` with **no `appBar`**; its body is a
`Column` whose first child is `ShellContextBar` (`LocationStrip` + the
season/block/episode `ActionChip`s). Because the body starts at `y = 0`,
the bar renders under the Android status bar. The view title, search and
profile affordance live in each destination root's own `AppBar`
(`cast_tab_screen.dart`, `script_tab_screen.dart`,
`schedule_tab_screen.dart`).

The shell is the right owner for the top bar: it is the only widget that
survives destination switches, and the scope surface is already
shell-owned (issue #548/#610). Moving the title/search/profile out of the
destination roots removes the duplication (the title existed once per
destination root) and gives one bar the status-bar inset.

## Decisions

### D1 — The shell owns a sticky two-row top bar

Row 1 (profile + scope pills) and row 2 (view title + breadcrumb + search)
are both rendered by the shell, wrapped once in
`SafeArea(top: true, bottom: false)`. The destination roots keep their
`Scaffold` (Material ancestor, standalone-test parity) but render **no
`AppBar`**.

*Why:* one status-bar inset, one title source, one search entry. The
alternative — keeping the destination `AppBar` as row 2 — leaves two
independent top surfaces and duplicates the title once the shell renders
it.

### D2 — The view title comes from the destination spec

`ShellDestinations` already owns the three destination labels
(`navCast`/`navScript`/`navSchedule`) and their keys. The view bar reads
the active destination's label from the same spec, so the title can never
drift from the destination list. The shell's `IndexedStack` keeps all three
destinations mounted, so the label is derived from
`shellControllerProvider.selectedIndex`, never from a mounted widget.

### D3 — Prerequisite-aware pill visibility

The three scope levels are **hierarchical**, not flat (unlike Spotify's
filter pills): a block belongs to a season and the episode picker needs a
block id. The visibility rule is therefore:

| Pill | Visible when | Unset label | Selected fill |
|---|---|---|---|
| Season | always | `scopeChipSeasonUnset` | `primaryContainer` |
| Block | season active **or** block scope set | `scopeChipBlockUnset` | `secondaryContainer` |
| Episode | block scope set **or** episode scope set | `episodeChipUnset` | `tertiaryContainer` |

An unset pill is neutral (`surfaceContainerHighest` fill,
`onSurfaceVariant` foreground) and opens its picker; a set pill is filled
with its own container color. The season pill is always present because it
is the only affordance that can SET a season when none is active — the
"no scope renders no bar" arm of the old spec is deliberately replaced by
"the bar is never hidden".

*Why not always show all three:* a disabled/neutral block pill before any
season exists is a dead affordance; *why not self-hide entirely:* the
levels would be undiscoverable. The prerequisite rule gives Spotify's
stable row without nonsensical taps.

### D4 — Pill colors use M3 color-scheme roles, no new tokens

`primaryContainer` / `secondaryContainer` / `tertiaryContainer` (with their
`on*` foregrounds) are visually distinct in both light and dark schemes and
require no new DTCG token (`frontend-flutter/AGENTS.md` §9: theme tokens are
the single source for colors; `lib/design/theme.dart` is the only place
that may hold `Color(...)` literals). Color is never the sole carrier of
meaning — each pill's visible label names the level and its state.

### D5 — Pills stay `ActionChip`s

A hand-rolled `Material` + `InkWell` pill would lose the chip's
`MaterialTapTargetSize.padded` 48dp touch target (the spec's touch-target
contract). `ActionChip` with `shape: StadiumBorder()`, explicit
`backgroundColor` / `labelStyle` / `side` gives the rounded Spotify look
while keeping the tap target. A shared `ScopePill` widget centralises the
styling so the three levels cannot drift.

### D6 — The Cast view's actions move into the Cast view, not the shell

The Cast view's costume-category (season-gated) and fundus actions are
costume-domain content. Keeping them inside `CastTabScreen` (in the view's
own toolbar row above the roster/costume switch) preserves their
navigator target (the active destination's nested navigator, so the
breadcrumb deepens), keeps `CastTabScreen` self-contained for its
standalone widget tests, and avoids coupling the shell to the costume
feature. `ScriptTabScreen` / `ScheduleTabScreen` have no view actions and
render no toolbar.

### D7 — Search/profile keep the active destination's navigator

Both moved from the destination `AppBar` into the shell. To preserve the
documented behaviour ("opens inside the active view's stack; back returns
there"), `ShellSearchAction` / `ProfileMenuButton` accept an optional
`GlobalKey<NavigatorState>` and resolve it at tap time, falling back to
`Navigator.of(context)`. The shell passes the active destination's
navigator key.

## Risks

- **Golden churn:** the shell goldens change for all three morphologies ×
  light/dark; regenerated with `flutter test --update-goldens` and reviewed
  by eye.
- **Narrow layouts:** three pills plus the profile icon in one scrollable
  row; the pill cluster is a horizontal `SingleChildScrollView`, so a
  narrow bar scrolls rather than overflows.
- **Breadcrumb width:** row 2 shares its width between the title, the
  breadcrumb and the search affordance; `LocationStrip` WRAPS the chain onto
  as many lines as it needs (each segment carries its trailing separator, so
  a wrapped line never starts with a dangling `›`), and its merged semantics
  node keeps the full path. `maxSegments` still caps how many levels render
  (deepest wins), which bounds the bar's height.

## Out of scope

- No backend/API change; no Dart client regeneration.
- The shell's scope pickers keep their current (root-navigator) push
  target — only the search/profile seam is wired to the destination
  navigator.
- No retro-fit of the ~60 per-feature goldens that pump their screens
  directly (the destination roots keep their own Scaffold).
