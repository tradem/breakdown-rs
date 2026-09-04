<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: muse-spark-1.3-contributor (opencode-go) -->

# Changelog

All notable changes to the Breakdown Flutter client will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
per ADR-033: single source of truth is `version: X.Y.Z+N` in `pubspec.yaml`,
releases are cut as `flutter-vX.Y.Z` tags.

## [Unreleased]

### Added

- Versioning scheme per ADR-033 (`pubspec.yaml` as single source of truth,
  `flutter-vX.Y.Z` release tags, monotonically increasing `+N` build number
  for the Play Store `versionCode`).
- `AppConfig.appVersion`: CI-injected `--dart-define=APP_VERSION` for the
  About/Info dialog (spec `flutter-app-dialogs`), falling back to `'unknown'`
  for local builds without the define.
- `package_info_plus` dependency as the native `version`/`buildNumber` reader
  (validates the injected `APP_VERSION` in release builds).
- `version-drift` CI job: enforces the `X.Y.Z+N` pubspec format on every run
  and the tag == build-name agreement on `flutter-v*` tags.
