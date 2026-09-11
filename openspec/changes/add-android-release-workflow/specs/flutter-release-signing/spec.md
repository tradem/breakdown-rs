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

#### Scenario: CI build signs the release APK
- **WHEN** the release workflow runs with all signing environment variables
  set.
- **THEN** the produced APK/AAB is signed with the project keystore and
  `apksigner verify` reports the recorded SHA-256 certificate fingerprint.

#### Scenario: Local release build without secrets stays unsigned
- **WHEN** a developer runs `flutter build apk --release --flavor prod`
  locally without signing environment variables.
- **THEN** the build succeeds and emits an unsigned APK; no dummy or
  fallback credentials are read from the repository.

### Requirement: One Key Across All Distribution Channels
All published release binaries — GitHub Release APKs/AABs now, F-Droid
verification later, Play Store uploads later — SHALL be signed with the same
project key (Decision D9). The SHA-256 lowercase, colon-free signing
certificate fingerprint SHALL be recorded in the repository documentation so
the follow-up `add-fdroid-inclusion` change can set `AllowedAPKSigningKeys`
to it and Play uploads reference the same key.

#### Scenario: Fingerprint matches across channels
- **WHEN** the release APK attached to a GitHub Release and any later
  F-Droid/Play binary for the same version are compared.
- **THEN** all binaries report the identical SHA-256 signing-certificate
  fingerprint, allowing Android update installs across channels without
  uninstall.

#### Scenario: A PR introduces a second signing key
- **WHEN** a PR adds an alternative signing configuration for a release
  channel.
- **THEN** review rejects it against this requirement (one-key invariant);
  a second key requires a new change proposal.
