<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# Tasks — issue #824

## 1. Design layer

- [x] 1.1 `lib/design/header_metrics.dart` — height derived from
      `typography.lineHeight.titleLarge` + 2 × `spacing.8`, clamped up to
      `kMinInteractiveDimension` (48 dp); title style from the type tokens.
- [x] 1.2 `lib/design/theme.dart` — one `appBarTheme` per brightness
      (`toolbarHeight`, `titleTextStyle`, `centerTitle: false`,
      `titleSpacing`, elevation `level0` / `scrolledUnderElevation`
      `level2`, surface roles).
- [x] 1.3 `lib/design/components/breakdown_app_bar.dart` — shared header with
      a text form (one line + ellipsis) and a `.custom` form; `preferredSize`
      equals the theme height.

## 2. Shell seam

- [x] 2.1 `MediaQuery.removePadding(removeTop: true)` around the tab
      `IndexedStack` in `app_shell.dart`, so the status bar is counted once.

## 3. Migration (41 sites / 37 files)

- [x] 3.1 Replace `AppBar(title: Text(x))` with `BreakdownAppBar(title: x)`.
- [x] 3.2 Composite titles use `BreakdownAppBar.custom` (scene-shoots day
      board, reports index).
- [x] 3.3 Preserve every existing `key`, `actions`, `leading` and
      `automaticallyImplyLeading` (the setup wizard's confirm-then-leave
      leading, 4 keyed bars).

## 4. Tests

- [x] 4.1 `test/design/header_metrics_test.dart` — token derivation, the
      48 dp floor, the weight↔token pin, and both themes' app-bar role.
- [x] 4.2 `test/design/breakdown_app_bar_test.dart` — height from the theme,
      one line + ellipsis, theme title style, actions/leading pass-through,
      composite title, 48 dp back target + pop, `textScaler` 1.3.
- [x] 4.3 `app_shell_test.dart` — "a pushed header counts the status bar
      exactly once" (with `tester.view.padding`), and the back-target test.
- [x] 4.4 `app_shell_test.dart` — the status-bar-padded header golden
      `goldens/app_shell_pushed_header_status_bar.png`.
- [x] 4.5 Re-baseline every screen golden that contains an app bar and inspect
      the result (no clipping, title still one line).

## 5. Docs

- [x] 5.1 `docs/design/screens/README.md` — the header rule in the template.
- [x] 5.2 `scenes.md`, `settings.md`, `seasons.md`, `ai-import-jobs.md`,
      `script-view.md`, `navigation-shell.md` — name the rule where they
      describe a header.
- [x] 5.3 `scripts/check-design-diagrams.sh` passes.

## 6. Verification

- [x] 6.1 `dart format --set-exit-if-changed .` clean.
- [x] 6.2 `flutter analyze` clean.
- [x] 6.3 `dart run bin/run_lints.dart` (breakdown_lints_runner) — no
      violations.
- [x] 6.4 `bash tool/check_inline_copy.sh` — no user-facing literals.
- [x] 6.5 `flutter test` — full suite green.
- [x] 6.6 The single-inset test fails when the seam fix is reverted (verified
      by flipping `removeTop: false`: 48 dp → 76 dp).

## Follow-ups (not this change)

- [ ] A `component.appBar.*` token group in `design/tokens/` (own change) so
      the derived height moves from `HeaderMetrics` into the token source.
- [ ] Review the two stacked chrome bands (shell bar + pushed header) as a
      navigation design question (#638).
- [x] Untrack the stale `**/failures/` golden-diff artifacts that `.gitignore`
      already covers (issue #839).
