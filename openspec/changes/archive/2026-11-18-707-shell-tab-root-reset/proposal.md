<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3-flash-flex (neuralwatt) -->

# 707 — Shell: tab switch and re-tap reset the destination to its root screen

## Why

Issue #707 reports that switching tabs (and re-tapping the active tab)
does NOT show the destination's start screen: the nested `Navigator`
inside the `IndexedStack` stays "stuck" on the last-visited sub-page
(reproduction: open Settings/About/AI-Import-Jobs from the account
drawer, drill into sub-pages, switch tabs and back — you are still deep
inside the sub-pages). Re-tapping the already-active tab — the
established Material convention "re-tap = back to start" — does nothing.

Root cause: `ShellController.selectTab()` mutates only the index; the
nested navigators are never reset. `AccountDrawer` pushes Settings/About
onto the ACTIVE destination's nested navigator (the deliberate #653
seam), exactly where the stack then stays.

## What Changes

- **Controller distinguishes re-tap from switch:** `selectTab()` returns
  a `ShellTabSelection` result (`switched` / `reTapped` / `rejected`)
  so the shell can distinguish the two tap kinds at the call site.
  Out-of-range indices are still rejected, never clamped.
- **Root reset in the shell:** `AppShellState` gains one central
  `_onDestinationSelected` handler used by all three morphologies
  (NavigationBar / NavigationRail / NavigationDrawer). After a valid
  selection (switch OR re-tap) it pops the TARGET destination's nested
  navigator to its root via `popUntil((route) => route.isFirst)`.
  On a tab root `popUntil` is a no-op, not an error.
- **Design D2 is consciously overridden:** per-tab position memory is
  dropped — switching destinations shows the target's start screen. The
  `AppShell` doc comment and the `flutter-navigation-shell` spec are
  updated accordingly. D3 (back pops within the tab; app-exit intent at
  the Cast root) is unchanged.

## Impact

- **Specs:** `flutter-navigation-shell` (ADDED requirement "Tab Root Reset on
  Destination Selection" — a canonical `openspec/specs/flutter-navigation-shell/
  spec.md` does not exist yet: the position-memory behavior (former design D2)
  was never in a live spec, only in the archived `redesign-app-shell-navigation`
  delta and in `AppShell` doc comments. `MODIFIED` would target a nonexistent
  canonical requirement, so the reset contract is encoded as an ADDED
  requirement; the still-open foundational `three-view-navigation-shell` change
  also carries ADDED requirements only, so there is no collision).
- **Code:** `lib/features/shell/shell_controller.dart` (`selectTab`
  return type + new enum), `lib/features/shell/app_shell.dart` (central
  handler + doc comments). No l10n, no API/contract change —
  `backend/openapi.yaml` untouched, no client regen.
- **Tests:** `shell_controller_test.dart` extended (switch/re-tap/
  rejected results); `app_shell_test.dart` migrates the two tests that
  assert D2 position memory ("Script drilldown survives a Cast switch",
  "tab switch shows the ACTIVE tab location") to root-reset semantics
  and adds re-tap and switch reset tests across all three morphologies.

## Non-goals

- No scroll-to-top of the destination root's list on re-tap (not in the
  issue's settled behavior).
- No change to the `PopScope`/back contract (D3) or to the
  `AccountDrawer` push seam (#653).
