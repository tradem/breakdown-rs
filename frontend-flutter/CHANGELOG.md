<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: muse-spark-1.3-contributor (opencode-go) -->
<!-- Co-authored-by: omen-alpha (opencode-go) -->

# Changelog

All notable changes to the Breakdown Flutter client will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
per ADR-033: single source of truth is `version: X.Y.Z+N` in `pubspec.yaml`,
releases are cut as `flutter-vX.Y.Z` tags.

## [Unreleased]

### Added

- AI document import (`flutter-ai-import`): the user-facing
  configure → submit → watch → preview → apply pipeline over
  `/v1/ai-import/*`. Provider/model discovery-driven configuration with
  the two-step credential hand-off (`POST /v1/settings/credentials` →
  vault key id — the LLM key never persists on the device), version-echo
  edits without automatic re-dispatch on 409, credential rollback with
  orphan cleanup; raw schedule/script submission (paste, CSV, PDF via
  `file_picker` — PDF bytes uploaded verbatim, no re-encoding), duplicate
  uploads surfaced honestly (200 → callout, never a fresh import);
  bounded job watch state machine with an honest no-cancel copy
  (cancellation is backend-owned); typed preview rendering with strict
  rejection of unknown future payload kinds; apply into an episode with
  verbatim `draft_ref`s, edit distances from real selections, and a
  missing-context picker requirement. Every dispatch is AUTHZ-gated
  client-side (denial issues zero requests); sign-out and backend-switch
  wipe the hand-off store and job cache.
- **Version bump:** `0.2.0+8 → 0.3.0+9` (MINOR per ADR-033 D2 — additive
  feature surface; `+N` monotonic for the Play `versionCode`; no
  `flutter-v*` tag cut).
- Reports screen (`flutter-reports`): day-context Soll-Ist on-screen report
  (planned/actual counts, moved/missing/skipped/reshot flag chips, finality
  banner — all verbatim from the JSON report read DTOs, no client-side
  recomputation) plus the three per-day PDF report cards (dispo, shoot-day,
  planned-vs-actual): user-initiated streamed fetch through the pinned-CA
  generated client (path-keyed interceptor, 25 MB byte cap with CancelToken
  abort and temp cleanup), in-app FOSS preview (pdfrx) and platform-sheet
  share under `<day>-<report>.pdf`; PDF bytes never persist into Drift.
  Local non-fetching AUTHZ-GATE (`canViewReports` via
  `currentMembershipProvider`) refuses with zero report requests.
- **Version bump:** `0.1.0+7 → 0.2.0+8` (MINOR per ADR-033 D2 — additive
  feature surface; `+N` monotonic for the Play `versionCode`; no
  `flutter-v*` tag cut).
- Pre-release version line: the client versions as `0.x+N` until the
  first store submission, which will cut `1.0.0` (the `1.0.0+1` in
  `pubspec.yaml` was the untouched `flutter create` scaffold default, not
  a maturity claim; backend components version 0.x likewise). Build
  number `+N` keeps increasing monotonically for the Play `versionCode`.
  MINOR bumps carry additive features per ADR-033 D2 even before the
  first tag (D3/D7: tags snapshot the pubspec surface at release time; no
  flutter tag exists yet).
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

### Fixed

- Seasons list fetch wired to the backend (issue #377): `seasonsListFetch`
  calls `GET /v1/seasons` via `SeasonRepository.fetchSeasonsList` (regenerated
  `vendor/breakdown_api`) instead of short-circuiting with
  `transport.seasons_list_unavailable`. The projection now confirms a created
  id, so the "Created — catching up" overlay clears and blocks → … → day
  board become reachable. The fetch is unscoped (no `series_id`), confirming
  ids from any series and keeping the full-snapshot cache write coherent.
- **Version bump:** `0.1.0+3 → 0.1.0+4` (monotonic Play `versionCode`; no
  release tag cut — the client stays on the `0.1.x+N` pre-release line).
