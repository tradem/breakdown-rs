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
  and evaluate whether Play's re-keyed app signing key conflicts with the
  GitHub-Release one-key invariant — per D9, the one-key guarantee does
  not extend to Play-distributed binaries, so the enrollment model chosen
  here defines Play's own update/reinstall behavior.
- Release-track wiring: internal testing track fed from the release
  workflow's AAB artifact (new publish step or separate workflow job);
  alpha/beta semantics mapped to Play tracks.
- Data Safety + content rating declarations, grounded in an evidence
  audit: the app is online-first — it sends commands and fetches read
  projections over the network, and authentication traffic leaves the
  device — so data IS transmitted off-device; self-hosting the backend
  does not make that collection local. Audit network requests,
  third-party SDKs (SDK data collection must be disclosed per Play
  policy), manifest permissions, and locally stored data, then complete
  the Data Safety form and privacy policy from the audit findings.
- Store listing: localized texts, screenshots, feature graphic (reuse
  F-Droid fastlane assets where formats coincide).
- Store-specific manifest/dependency audit (task, not a pre-verified
  claim): audit `frontend-flutter/android/app/src/main/AndroidManifest.xml`,
  the Android Gradle files, `frontend-flutter/pubspec.yaml`, and the
  resolved pub/Gradle dependencies and SDK versions; record the findings
  (including any store-specific manifest requirements) together with the
  Data Safety review.

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
