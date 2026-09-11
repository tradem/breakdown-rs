<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->

# add-play-store-release

> **Status: proposal-stub.** This change is planned but not started; specs,
> design, and tasks are refined when implementation begins. It depends on
> `add-android-release-workflow` (signed AAB artifact) and optionally on
> `add-fdroid-inclusion` (channel ordering decision).

## Why

Beyond F-Droid, Google Play should distribute the app to reach testers and
users without sideloading. Play requires `.aab` uploads, Play App Signing
enrollment, and a Data Safety declaration; the signed AAB already produced by
the release workflow is the direct input, so this change is mostly account,
signing, and listing work.

## What Changes

- Play Console setup: developer account, app entry with the application ID
  from the existing scaffold.
- Play App Signing decision: enroll with the D9 developer key as upload key
  (and evaluate whether Play's re-keyed app signing key conflicts with the
  GitHub-Release/F-Droid one-key invariant — documented per D9's escape
  hatch).
- Release-track wiring: internal testing track fed from the release
  workflow's AAB artifact (new publish step or separate workflow job);
  alpha/beta semantics mapped to Play tracks.
- Data Safety + content rating declarations (app collects nothing; offline
  cache only; backend is self-hosted).
- Store listing: localized texts, screenshots, feature graphic (reuse
  F-Droid fastlane assets where formats coincide).
- Any store-specific manifest requirements (e.g., no changes expected given
  no FCM/Play Services usage — verified in this change).

## Capabilities

### New Capabilities
- `flutter-play-store-release`: AAB publish pipeline to Play tracks, Play
  App Signing enrollment rules, and Data Safety/listing compliance.

### Modified Capabilities
- (none expected)

## Impact

- `frontend-flutter/android/**` (signing enrollment consequences only),
  `.github/workflows/` (AAB publish step), Play Console (external, no repo
  artifacts beyond docs).
- Precondition: stable AAB artifact from `add-android-release-workflow` and
  a finished FOSS audit from `add-fdroid-inclusion` (or performed here if
  Play comes first).
