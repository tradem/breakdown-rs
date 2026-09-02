<!-- markdownlint-disable MD041 -->
<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: hy3 (opencode-go) -->

# Summary

<!-- Describe the Flutter app change. -->

## Flutter Dependency PRs (Dependabot `pub` / `gradle`)

If this PR bumps `frontend-flutter/pubspec.yaml` (Dependabot `pub`) or the
Android Gradle deps (Dependabot `gradle`), review the update per the notes
below. The full checklist also lives in the Dependabot `pub` block comment in
`.github/dependabot.yml`.

### `pub` PRs

Dependabot's `pub` updater resolves dependencies with the native `pub` tool
and commits the updated `pubspec.lock` itself, so a `pub` PR normally includes
the lockfile diff. As a reviewer:

- Confirm the `pubspec.lock` diff is present in the PR.
- Verify the resolution is clean against the currently pinned Flutter SDK by
  running `flutter pub get`. Do **not** run `flutter pub upgrade` — it ignores
  the committed lockfile and would override Dependabot's curated resolution
  with the latest versions.
- Major-version bumps open as separate PRs (minor/patch stay grouped via the
  `flutter-pub-deps` group); review them for breaking changes.

### `gradle` PRs (Android)

Gradle/AGP and Kotlin plugin bumps are independent of the Dart `pub` graph and
need no Flutter `pub` command. Validate major AGP bumps against the currently
pinned Flutter SDK (Flutter pins an AGP-compatibility floor per Flutter
version) before merging.

## Notes

- macOS is a later target: no `cocoapods` Dependabot block yet (only when
  native pods are introduced).
- `vendor/breakdown_api` is intentionally out of scope — it is a path
  dependency regenerated via `scripts/regen-client.sh`.

## Verification

- [ ] `dart format --set-exit-if-changed .` clean (if Dart changed)
- [ ] `flutter analyze` clean (if Dart changed)
- [ ] `flutter test` passing (if Dart changed)
- [ ] `pubspec.lock` diff present; `flutter pub get` resolves clean (pub PRs)
