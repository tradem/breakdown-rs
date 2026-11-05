<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# 824 — A pushed screen's header is proportional to its title, and the status bar is counted once

## Why

Every pushed screen with a back arrow rendered ~80–96 dp of chrome around one
28 dp title line. Three independent causes, all in the same surface:

1. **The status bar was inset twice (device-only).** `ShellTopBar` wraps
   itself in `SafeArea(bottom: false)`; the tab content is its SIBLING
   (`Column[ShellTopBar, OfflinePill, Expanded(content)]`), so the subtree's
   `MediaQuery.padding.top` was untouched and every pushed `AppBar`
   (`primary: true`) applied that inset a second time as blank space above its
   toolbar. Invisible in goldens, which render zero view padding.
2. **No header theming at all.** `lib/design/theme.dart` set only
   `useMaterial3` + `colorScheme`; there was no `appBarTheme` and the string
   `toolbarHeight` did not appear anywhere under `lib/`. All 41 app bars took
   the untokenized M3 default of 56 dp.
3. **41 hand-rolled `AppBar(title: Text(...))`** with no shared component and
   no title rule — `scene_detail_screen` put a whole `scene.summary` in its
   title with no `maxLines`/`overflow`, so a long summary was clipped rather
   than ellipsized.

## Decision

- **D1 — fix the inset once, at the shell seam.** The shell bar owns the
  status-bar area; the tab `IndexedStack` is wrapped in
  `MediaQuery.removePadding(removeTop: true)`, so a pushed header starts
  exactly where the shell bar ends. One place, every morphology, every pushed
  route — instead of `primary: false` on 41 call sites (which cannot know
  whether it is inside the shell).
- **D2 — one `appBarTheme`, height DERIVED from the tokens.** `HeaderMetrics`
  composes the height from `typography.lineHeight.titleLarge` (28) plus two
  `spacing.8` steps (44) and clamps it up to
  `kMinInteractiveDimension` (48) — because the leading back button's touch
  target lives inside the bar. With today's tokens the header is **48 dp**
  around a 22 sp `titleLarge` instead of 56 dp, and no screen declares a
  `toolbarHeight`.
  A dedicated `component.appBar.height` token is deliberately NOT introduced:
  component tokens are a non-goal of the design-token foundation, so the
  derived value belongs in the theme layer until such a token exists (that is
  a separate token-source change, not a header fix).
- **D3 — a shared `BreakdownAppBar`.** Back arrow + title + optional actions.
  Its `preferredSize` is the same token value the theme renders, so a screen
  cannot smuggle in a different height. Text titles are rendered
  `maxLines: 1`, `overflow: TextOverflow.ellipsis`, `softWrap: false`; a
  composite title (the scene-shoots AI-provenance badge + label, the reports
  index title) opts out via `BreakdownAppBar.custom` and owns its overflow
  rule.
- **D4 — verify on device geometry, not by eye.** A widget test sets
  `tester.view.padding`/`viewPadding` (the pattern
  `app_shell_test.dart:798` already uses for the shell bar), pushes a screen
  inside a tab navigator, and asserts the header's rect: its top equals the
  shell bar's bottom and its height equals `HeaderMetrics.toolbarHeight`. A
  second test asserts the back button's ≥ 48 dp target still pops. A new
  golden renders the shell plus a pushed header **with** status-bar padding,
  because every other golden runs with zero padding and would keep hiding the
  regression.
- **D5 — description, not smaller text.** The title stays `titleLarge`
  (22 sp); the height comes from removing the duplicate inset and from token
  padding. At the repo's a11y ceiling (`textScaler` 1.3, 36.4 dp line) the
  title still fits the 48 dp bar — asserted in the widget test.

## Alternatives rejected

- **`primary: false` on the pushed app bars.** Correct height, but it has to
  be repeated at 41 sites and silently breaks the first screen pushed outside
  the shell.
- **Keep `toolbarHeight: 56` and only remove the inset.** Reaches 56 dp on
  device (already a large win, and zero golden churn) but leaves the bar
  untokenized and still 2× the title line.
- **A new `component.appBar.height` token.** Out of scope for a header fix:
  component tokens are an explicit non-goal of `flutter-design-tokens`, and
  introducing one belongs in its own token-source change.
- **Shrinking the leading `IconButton`.** Would buy 8 dp and break the 48 dp
  Material/a11y minimum.

## Impact

- `lib/design/header_metrics.dart` (new), `lib/design/theme.dart`
  (`appBarTheme` for both brightnesses),
  `lib/design/components/breakdown_app_bar.dart` (new).
- `lib/features/shell/app_shell.dart` — the inset seam.
- 37 files migrated from `AppBar(title: Text(...))` to `BreakdownAppBar`
  (41 sites; 1 site uses `.custom`, 1 passes `leading` +
  `automaticallyImplyLeading: false`, 4 keep their `key`).
- Tests: `test/design/header_metrics_test.dart`,
  `test/design/breakdown_app_bar_test.dart` (new), two geometry tests plus one
  status-bar golden in `test/features/shell/app_shell_test.dart`.
- Goldens: every screen golden that contains an app bar is re-baselined (the
  header is 8 dp shorter). The re-baseline was inspected: the title stays on
  one line, the back arrow keeps its target, and no body content is clipped.
- Docs: the screen-spec template gains the header rule; `scenes.md`,
  `settings.md`, `seasons.md`, `ai-import-jobs.md`, `script-view.md` and
  `navigation-shell.md` name the rule where they describe a header.

## Follow-ups (not this change)

- A `component.appBar.*` token group in `design/tokens/` (its own change), so
  the derived height moves from `HeaderMetrics` into the token source.
- The two stacked chrome bands (shell bar + pushed header) are still two
  surfaces; whether a pushed screen should carry its own bar at all when the
  shell already shows the location strip is a navigation design question, not
  a height bug (#638 is the related change).
- `git ls-files` still tracks stale `**/failures/` golden-diff artifacts that
  `.gitignore` already covers; they are unrelated to this change and were left
  untouched.
