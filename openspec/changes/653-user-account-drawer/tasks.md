<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3-flash (neuralwatt) -->

# 653 — Tasks

## 1. About full-screen route

- [ ] 1.1 Create `lib/features/app_info/app_info_screen.dart`:
      `AppInfoScreen` (Scaffold key `app-info-screen`, AppBar back,
      ListView with `info-version`, `info-license`, `info-source-link`
      (LaunchUri seam), `info-ai-notice` doorway → `AiDisclosureScreen`);
      keep `kSourceRepositoryUrl`.
- [ ] 1.2 Delete `lib/features/app_info/info_dialog.dart`; migrate
      `info_dialog_test.dart` → `app_info_screen_test.dart`
      (content, link-launch, fail notice, AI doorway, textScaler hold,
      goldens regenerated for the screen).
- [ ] 1.3 Update `docs/design/screens/about-ai.md` references if they
      mention the dialog (screen-level docs follow-up allowed).

## 2. Account drawer

- [ ] 2.1 Create `lib/features/shell/account_drawer.dart`:
      `AccountDrawer` (`NavigationDrawer`, key `profile-account-drawer`,
      identity header `profile-identity`, entries `profile-about` /
      `profile-settings` / `profile-signout`; About + Settings push on
      the active destination navigator; Abmelden runs
      `sessionResetProvider`).
- [ ] 2.2 Host the drawer on all three shell Scaffolds
      (`lib/features/shell/app_shell.dart`); profile icon opens it via
      `Scaffold.of(context).openDrawer()`
      (`lib/features/shell/profile_menu_button.dart`,
      `shell_top_bar.dart` cleanup).
- [ ] 2.3 Verify l10n: no new keys; de/en parity untouched.

## 3. Tests + validation

- [ ] 3.1 Rewrite `test/features/shell/profile_menu_test.dart`: drawer
      opens on tap, entries present, About → screen route (NOT dialog),
      Settings push, sign-out → gate, failed sign-out fail-closed,
      drawer goldens (de locale, light + dark).
- [ ] 3.2 Update `app_shell_test.dart` modal-hosting assertions (drawer
      is shell-level; About pushes destination-level).
- [ ] 3.3 `dart format`, `flutter analyze`, `flutter test` (goldens with
      `--update-goldens` once), integration smoke unaffected
      (`pumpAndSettle`).
- [ ] 3.4 Bump `pubspec.yaml` version.
