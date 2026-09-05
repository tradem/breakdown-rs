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

- Pre-release version line: the client versions as `0.1.x+N` until the
  first store submission, which will cut `1.0.0` (the `1.0.0+1` in
  `pubspec.yaml` was the untouched `flutter create` scaffold default, not
  a maturity claim; backend components version 0.x likewise). Build
  number `+N` keeps increasing monotonically for the Play `versionCode`.
- Login & app shell (`flutter-login-and-app-shell`): auth gate (splash →
  login → seasons), OIDC platform leg (Custom Tabs + deep-link capture),
  light/dark Material 3 design tokens, app-shell overflow menu (identity,
  About, Settings, sign-out with cache clear), About/Info dialog (version,
  AGPL-3.0 + source link, AI usage notice), and settings dialog with
  dev-only runtime backend-URI override (validated, pinned-CA rebuild,
  generation-fenced cache reset).
- `AuthTokenInterceptor`: attaches the session bearer token over HTTPS
  only, always withheld on cleartext (CWE-319).
- Android deep-link registration for `OIDC_REDIRECT_URI` (Gradle
  `manifestPlaceholder` derived from the same source; `compileSdk 37` for
  `flutter_secure_storage`).
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
