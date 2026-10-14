<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3-flash (neuralwatt) -->

# 653 — Spotify-style user account drawer (NavigationDrawer) from the profile icon

## Why

Issue #653 asks for a **user account drawer** triggered by the shell top
bar's user icon: a Material 3 side drawer that slides in as an overlay
(with scrim), Spotify-style — explicitly **not** a bottom sheet. Today the
profile affordance opens `showModalBottomSheet` (the exact surface the
issue forbids), and its *Über die App* entry opens the `AppInfoDialog` —
the issue requires About to open a **full screen route, explicitly not a
dialog**. Settings (full-screen push, issue #516) and Logout
(`SessionReset`, issues #610/#612) already conform.

## What Changes

- The shell's three Scaffolds (compact/medium/expanded) host an
  `AccountDrawer` (`NavigationDrawer`) as their side drawer; the profile
  icon opens it via `Scaffold.of(context).openDrawer()` — an overlay above
  the content with scrim, tap-outside and swipe dismiss, no bottom-sheet
  variant anywhere.
- The drawer content mirrors the old sheet entries: the signed-in
  identity header, *Über die App* (→ full-screen route), *Einstellungen*
  (→ full-screen push on the active destination's navigator, same seam as
  before), *Abmelden* (→ `sessionResetProvider.signOut()`).
- **About becomes a full-screen route:** the `AppInfoDialog` /
  `showAppInfoDialog` surface is replaced entirely by an `AppInfoScreen`
  (`Scaffold` + `AppBar` back navigation) carrying the same content
  contract (version, AGPL-3.0 license + source link, AI-notice doorway to
  `AiDisclosureScreen`). No other caller exists, so the dialog code is
  deleted, not deprecated.
- Decisions settled with the PO (issue #653 thread): replace the dialog
  entirely (spec delta, no dead code) and use the stock **M3
  `NavigationDrawer`** (full-height side drawer; the issue's
  "not full height" sizing note is consciously overridden in favor of
  Material's own a11y/gesture behavior).

## Impact

- **Specs:** `flutter-account-drawer` (new capability: account drawer
  behavior/entries), `flutter-app-dialogs` (modified: About surface is a
  full-screen route, the dialog requirement is removed).
- **Code:** `lib/features/shell/` (`account_drawer.dart` new,
  `app_shell.dart`, `profile_menu_button.dart`, `shell_top_bar.dart`),
  `lib/features/app_info/` (`app_info_screen.dart` new,
  `info_dialog.dart` deleted). No new l10n keys (existing
  `commonAbout`/`commonSettings`/`commonSignOut`/`profileTooltip` and
  identity copy are reused; de/en parity untouched). No API/contract
  change — `backend/openapi.yaml` untouched, no client regen.
- **Tests:** `profile_menu_test.dart` rewritten for the drawer (open-on-
  tap, About → screen route **not** dialog, sign-out, fail path, goldens);
  `info_dialog_test.dart` migrated to `app_info_screen_test.dart`;
  `app_shell_test.dart` modal-hosting assertions updated; integration
  tests keep working (`pumpAndSettle` covers the drawer animation).
