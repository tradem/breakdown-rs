<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: hy3 (opencode-go) -->

## Summary

<!-- Describe the Flutter app change. -->

## Flutter Dependency PRs (Dependabot `pub` / `gradle`)

If this PR bumps `frontend-flutter/pubspec.yaml` or the Android Gradle deps,
the lockfile MUST be refreshed before merge — Dependabot edits constraints
only and never touches `pubspec.lock`:

```bash
cd frontend-flutter
flutter pub upgrade          # or: flutter pub upgrade --major-versions
# commit the resulting pubspec.lock diff (regenerated android/ glue included;
# once the macOS target lands, macos/ glue too)
```

A PR that only edits `pubspec.yaml` without a refreshed `pubspec.lock` will
fail `flutter-ci.yml` at the first resolve step. Major AGP bumps must be
validated against the currently pinned Flutter SDK (Android-first; macOS is a
later target, so no `cocoapods` Dependabot block yet). `vendor/breakdown_api`
is intentionally out of scope — it is a path dependency regenerated via
`scripts/regen-client.sh`.

## Verification

- [ ] `dart format --set-exit-if-changed .` clean (if Dart changed)
- [ ] `flutter analyze` clean (if Dart changed)
- [ ] `flutter test` passing (if Dart changed)
- [ ] `pubspec.lock` committed / refreshed (for dependency PRs)

## Notes

Co-authored-by: hy3 (opencode-go)
