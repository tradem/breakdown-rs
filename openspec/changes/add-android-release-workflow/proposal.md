<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->

# add-android-release-workflow

## Why

The Flutter app currently produces no distributable Android artifacts: there is
no signing configuration, no release build pipeline, and no published binaries.
Alpha and beta testers have no way to install the app outside of a dev build.
Later distribution channels (F-Droid via an `fdroiddata` MR, Google Play) both
require a stable, developer-owned signing key and consistent versioned
artifacts as a precondition — establishing those now unblocks both follow-up
changes without reworking the pipeline.

**Distribution split:** This change covers ONLY the self-published release
artifacts (APK/AAB on GitHub Releases). F-Droid inclusion (fdroiddata
metadata + reproducible-build hardening) is a separate change
(`add-fdroid-inclusion`); Google Play integration (AAB upload, Play App
Signing enrollment, Data Safety) is a separate change (`add-play-store-release`).
Each is implemented as project progress allows; this one comes first.

## What Changes

- **Locked decision D9 — developer-signed builds:** All release binaries are
  signed with a project-owned keystore (not F-Droid's key, not Play App
  Signing's final key). One keystore, one key, used by every distribution
  channel so users can move between GitHub Releases / F-Droid / Play without
  uninstall/reinstall.
- Keystore generation + custody procedure documented (offline backup,
  passphrase in CI secrets only, never in the repo).
- Gradle release signing config in `frontend-flutter/android/` reading the
  keystore from environment variables (CI secrets), with an unsigned fallback
  for local dev builds.
- New tag-triggered GitHub Actions release workflow: on `v*` tag it builds
  APKs (`--split-per-abi`: arm64-v8a, armeabi-v7a, x86_64) and one `.aab`,
  SHA-pinned actions per the CI-hardening rules, and attaches them to a
  GitHub Release.
- Versioning convention: `pubspec.yaml` `version: <semver>+<versionCode>` is
  the single source for `versionName`/`versionCode`; the workflow fails if
  the tag does not match the pubspec version.
- Alpha/beta distribution convention: pre-release versions (`-alpha.N`,
  `-beta.N` suffixes on the tag) are published as GitHub *pre-releases*;
  stable versions as full releases. Testers install APKs directly from
  GitHub Releases ("install unknown apps"), no store account needed.
- Flavors: the release workflow builds the `prod` flavor; the existing `dev`
  flavor remains dev-runtime-only and is never published.
- Gitleaks coverage extended to the new workflow + gradle files (no
  `KEYSTORE_BASE64`-style material in the tree).

## Capabilities

### New Capabilities
- `flutter-release-signing`: project-owned release keystore, Gradle signing
  configuration from CI secrets, key custody rules, and the single-key
  (D9) signing invariant across all distribution channels.
- `flutter-release-artifacts`: tag-triggered release build pipeline,
  APK split-per-abi + AAB artifacts, tag↔pubspec version consistency gate,
  and GitHub Release publication with pre-release (alpha/beta) semantics.

### Modified Capabilities
- (none — CI workflow changes are additive; `ci-pipeline` /
  `flutter-ci-coverage` requirements are not altered)

## Impact

- **Files:** `frontend-flutter/android/app/build.gradle.kts` (signing config),
  `.github/workflows/` (new release workflow), `frontend-flutter/pubspec.yaml`
  (version bump convention), `scripts/` (optional keystore bootstrap helper),
  `.gitignore` (keystore exclusions).
- **New infra:** one GitHub Actions workflow; repository secrets
  (`KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`).
- **Dependencies:** none added to the app; workflow uses pinned action SHAs
  only.
- **Security:** keystore material must never enter the tree (gitleaks
  enforces); the signing key becomes the trust anchor for all future
  distribution — losing it is unrecoverable, hence the documented backup
  procedure.
- **Follow-ups unblocked:** `add-fdroid-inclusion` (needs
  `AllowedAPKSigningKeys` = this key's SHA-256 fingerprint) and
  `add-play-store-release` (needs the signed AAB produced here).
