<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->

# flutter-release-signing Specification

## ADDED Requirements

### Requirement: Project-Owned Release Keystore
The project SHALL maintain a single Android release keystore (one key, one
keystore) that signs every published release binary. The keystore file MUST
NOT be committed to the repository; it SHALL be generated once by a
documented bootstrap procedure and stored as a GitHub Actions secret
(base64-encoded) plus an offline backup owned by at least two maintainers.

#### Scenario: Keystore is not in the repository
- **WHEN** gitleaks scans the repository (including `frontend-flutter/**`
  and `.github/workflows/**`) and a maintainer inspects `.gitignore`.
- **THEN** no keystore file, keystore passphrase, or base64 keystore blob
  exists in the tree, and `*.jks` / `*.keystore` / keystore upload scripts'
  secret material are covered by gitleaks rules or `.gitignore`.

#### Scenario: Bootstrap procedure reproduces the signing config
- **WHEN** a new maintainer follows the documented key-custody procedure.
- **THEN** they can regenerate the CI secrets from the offline backup and
  produce a signed APK whose SHA-256 signing-certificate fingerprint equals
  the recorded project fingerprint.

### Requirement: Gradle Signing Config From CI Secrets
The release build type in `frontend-flutter/android/app/build.gradle.kts`
SHALL read the keystore path, store passphrase, key alias, and key password
from environment variables (`KEYSTORE_BASE64`/derived path,
`KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`) and SHALL NOT contain any
hardcoded credentials. When the signing environment variables are absent
(local development), the build SHALL produce an unsigned release APK
(`signingConfig` unset) rather than fail.

#### Scenario: CI signs and verifies the release APK
- **WHEN** the release workflow runs with all signing environment variables
  set and builds an APK.
- **THEN** the APK is signed with the project keystore and `apksigner verify
  --print-certs` reports the recorded SHA-256 certificate fingerprint.

#### Scenario: CI signs and verifies the AAB with separate tooling
- **WHEN** the release workflow runs with all signing environment variables
  set and builds an `.aab`.
- **THEN** the AAB is signed with `jarsigner` using the same project
  keystore (`apksigner` accepts APK files only) and verified with
  `jarsigner -verify`; a `bundletool build-apks` round-trip with the same
  keystore generates APKs from the AAB, and each generated APK passes
  `apksigner verify --print-certs` against the recorded fingerprint.

#### Scenario: Local release build without secrets stays unsigned
- **WHEN** a developer runs `flutter build apk --release --flavor prod`
  locally without signing environment variables.
- **THEN** the build succeeds and emits an unsigned APK; no dummy or
  fallback credentials are read from the repository.

### Requirement: One Key Across Developer-Published Channels
Every binary the project itself publishes — GitHub Release APKs/AABs now,
developer-signed F-Droid artifacts later — SHALL be signed with the same
project key (Decision D9). The SHA-256 lowercase, colon-free signing
certificate fingerprint SHALL be recorded in the repository documentation so
the follow-up `add-fdroid-inclusion` change can set `AllowedAPKSigningKeys`
to it for developer-provided APKs. F-Droid source builds (signed with
F-Droid's own key) and Play-distributed binaries (key controlled by Play
App Signing) are outside this guarantee: `add-fdroid-inclusion` MUST define
a developer-signed artifact path (e.g. fdroiddata `Binaries:`) or drop the
cross-channel claim for F-Droid, and `add-play-store-release` decides the
Play enrollment model.

#### Scenario: Fingerprint matches across developer-published channels
- **WHEN** the release APK attached to a GitHub Release and a later
  developer-signed F-Droid artifact (fdroiddata `Binaries:`) for the same
  version are compared.
- **THEN** both report the identical SHA-256 signing-certificate
  fingerprint, allowing Android update installs between these channels
  without uninstall.

#### Scenario: F-Droid source builds are outside the guarantee
- **WHEN** F-Droid builds the app from source via the fdroiddata buildbot.
- **THEN** the resulting APK is signed with F-Droid's key, and the
  documentation claims no cross-channel fingerprint and no
  update-without-reinstall guarantee for it.

#### Scenario: A PR introduces a second signing key
- **WHEN** a PR adds an alternative signing configuration for a release
  channel.
- **THEN** review rejects it against this requirement (one-key invariant);
  a second key requires a new change proposal.
