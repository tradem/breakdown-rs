<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->

# add-fdroid-inclusion

> **Status: proposal-stub.** This change is planned but not started; specs,
> design, and tasks are refined when implementation begins. It depends on
> `add-android-release-workflow` (developer key, release convention).

## Why

The Flutter app should be distributed via F-Droid as a freely installable,
FOSS-trustworthy channel. F-Droid does not accept APK uploads: it builds from
source via build metadata in the `fdroiddata` repository, so the repo must be
buildable on F-Droid's infrastructure and an MR with the app metadata must be
prepared. The developer-signed key from `add-android-release-workflow`
(Decision D9) becomes the `AllowedAPKSigningKeys` fingerprint so users can
move between GitHub Releases and F-Droid without uninstalling.

## What Changes

- Reproducible-build hardening in `frontend-flutter/android/`:
  `dependenciesInfo { includeInApk = false; includeInBundle = false }`,
  explicit `compileSdk`/`targetSdk`/`minSdk`, pinned Gradle wrapper and
  toolchain versions, no timestamps or prebuilt binaries in the tree.
- FOSS dependency audit of `pubspec.yaml` (all pub + Gradle dependencies
  FOSS; no Firebase/FCM — UnifiedPush documented as the free push option for
  a later change); audit results documented in the repo.
- Build-time vs. runtime config split verified: everything needed to compile
  (dev CA pins, OIDC client IDs) is public in the repo; no secret env vars
  are required by the build (F-Droid has no secrets).
- `fdroiddata` app metadata YAML (`<applicationId>.yml`): `srclibs:
  flutter@<pinned>`, prebuild/build blocks (pub cache, no-analytics,
  `flutter build apk --release --target-platform=…`),
  `AllowedAPKSigningKeys: <D9 fingerprint>`, `AutoUpdateMode: Version`,
  `UpdateCheckMode: Tags`, `UpdateCheckData: pubspec.yaml|version: …`.
- Fastlane metadata structure (`fastlane/metadata/android/`: icon,
  description, changelogs, screenshots) and an RFP issue + GitLab MR against
  `fdroid/fdroiddata`.
- Anti-features assessed and declared (expected: none, or `NonFreeNet`
  discussion only if a hosted-only backend concern is identified).

## Capabilities

### New Capabilities
- `flutter-fdroid-metadata`: fdroiddata build metadata, update-check wiring,
  signing-key allowlist, and the FOSS dependency audit contract.
- `flutter-reproducible-builds`: Android build determinism requirements
  (dependency metadata, pinned toolchains, no prebuilt blobs) as enforced
  repository invariants.

### Modified Capabilities
- (none expected; `add-android-release-workflow` requirements are reused,
  not modified)

## Impact

- `frontend-flutter/android/**` (Gradle determinism),
  `frontend-flutter/pubspec.yaml` (dependency audit outcomes),
  external: `gitlab.com/fdroid/fdroiddata` MR (metadata YAML + fastlane
  assets), GitLab.com account for the MR.
- Precondition: at least one stable tagged release from
  `add-android-release-workflow` that F-Droid can reference (`commit:`/
  `versionCode:` mapping in the metadata).
