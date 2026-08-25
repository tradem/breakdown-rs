<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.2 (neuralwatt) -->

# Proposal: Scaffold the Flutter Project (Android-first)

## Why
The foundation change (`add-flutter-app-foundation`) landed the
`AGENTS.md` and conventions but intentionally produced **no Flutter code**.
This change creates the actual `flutter create` project under
`frontend-flutter/` so subsequent follow-ups (OpenAPI client, auth, cache,
screens) have a project to land into.

## What changes
- `flutter create` Android-first app (min SDK / Kotlin / AGP pinned; macOS
  stubbed for later).
- `pubspec.yaml` core deps: `flutter_riverpod`, `riverpod_generator`,
  `fpdart`, `flutter_secure_storage`, `drift`, `dio` (or `http`),
  `json_annotation`, `freezed`, `flutter_gherkin` (dev), `build_runner` /
  `json_serializable` / `drift_dev` / `custom_lint` (dev).
- `analysis_options.yaml` with the custom lint rules referenced by the
  foundation skills (`discard-result` analog, no-throw-in-`data/domain`).
- `lib/main.dart` composition root: `ProviderScope`, flavor wiring, pinned-CA
  `HttpClient` from `--dart-define`.
- Flavors `dev` and `prod` only (per foundation `design.md` §7).
- SPDX headers + co-authored-by on all seeded files; extend
  `scripts/add-spdx-headers.sh` to cover `frontend-flutter/`.

## Dependencies
- **Depends on:** `add-flutter-app-foundation` (merged).
- **Unblocks:** `wire-openapi-dart-client`, `add-flutter-ci-tests`,
  `wire-flutter-oidc-auth`, `add-drift-read-cache`,
  `add-gherkin-critical-scenarios`, `first-screen-seasons`.

## Non-goals
- No OpenAPI client wiring (`wire-openapi-dart-client`).
- No auth/OIDC wiring (`wire-flutter-oidc-auth`).
- No read-cache (`add-drift-read-cache`).
- No screens (`first-screen-seasons`).
- No macOS build configuration.
