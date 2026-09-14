<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->

# flutter-release-artifacts Specification

## ADDED Requirements

### Requirement: Tag-Triggered Release Build
A GitHub Actions workflow SHALL build Android release artifacts whenever a
tag matching `v<semver>` is pushed. The workflow MUST follow the CI-hardening
rules: actions pinned by commit SHA, no `${{ github.event.* }}` interpolation
into `run:` blocks, minimal `permissions:` (contents: write only).

#### Scenario: Pushing a release tag triggers the build
- **WHEN** a maintainer pushes the tag `v1.2.0`.
- **THEN** the release workflow starts, checks out the tag, and builds the
  `prod` flavor release binaries.

#### Scenario: A push without a tag does not release
- **WHEN** changes are merged to the default branch without a `v*` tag.
- **THEN** the release workflow does not run; only the normal CI gates run.

### Requirement: Version Consistency Gate
The workflow SHALL fail before publishing if the pushed tag does not match
the `version:` field in `frontend-flutter/pubspec.yaml`
(`version: <name>+<code>` where `<name>` equals the tag without the `v`
prefix). The `versionCode` integer SHALL be strictly monotonically
increasing across releases.

#### Scenario: Tag does not match pubspec version
- **WHEN** tag `v1.2.1` is pushed while `pubspec.yaml` still declares
  `version: 1.2.0+1200`.
- **THEN** the workflow fails with an explicit mismatch error and no
  artifacts are published.

#### Scenario: Matching tag and version build successfully
- **WHEN** tag `v1.2.0` is pushed and `pubspec.yaml` declares
  `version: 1.2.0+1200`.
- **THEN** the version gate passes and the build proceeds.

### Requirement: APK Split-Per-ABI and AAB Artifacts
Every stable release SHALL produce three split APKs (`--split-per-abi`:
`arm64-v8a`, `armeabi-v7a`, `x86_64`) and one `.aab` bundle, all built from
the `prod` flavor with the pinned-CA configuration. Artifact file names
SHALL contain the version (`breakdown-<version>-<abi>.apk` /
`breakdown-<version>.aab`) and be attached to the GitHub Release.

#### Scenario: A stable release publishes the full artifact set
- **WHEN** the workflow completes successfully for tag `v1.2.0`.
- **THEN** the GitHub Release for `v1.2.0` contains
  `breakdown-1.2.0-arm64-v8a.apk`, `breakdown-1.2.0-armeabi-v7a.apk`,
  `breakdown-1.2.0-x86_64.apk`, and `breakdown-1.2.0.aab`.

#### Scenario: The dev flavor is never published
- **WHEN** the release workflow runs for any tag.
- **THEN** it builds only the `prod` flavor; no `dev`-flavor artifact is
  produced or attached.

### Requirement: Alpha and Beta Pre-Releases for Direct Installation
Tags carrying a pre-release suffix (`-alpha.N`, `-beta.N`) SHALL be published
as GitHub pre-releases with the same artifact set. The published APKs MUST
be directly installable by testers (sideloading from the GitHub Releases
page) without any store account, with the GitHub Release notes listing the
APK files and installation hint.

#### Scenario: An alpha tag produces a pre-release
- **WHEN** tag `v0.3.0-alpha.1` is pushed.
- **THEN** a GitHub Release marked as pre-release is created containing the
  three split APKs (and optionally the AAB) built from the same tag.

#### Scenario: A tester installs the APK by sideloading
- **WHEN** a tester downloads `breakdown-0.3.0-alpha.1-arm64-v8a.apk` from
  the pre-release on an arm64 Android device and installs it.
- **THEN** Android accepts the package (signature verification passes) and
  the app installs; a later stable install with the same key updates
  in place without uninstall.

### Requirement: Release Workflow Quality Gates
The release workflow SHALL NOT publish artifacts unless the repository's CI
quality gates pass on the tagged commit: `dart format --set-exit-if-changed`,
`flutter analyze`, `flutter test`, the OpenAPI client drift check, and
`gitleaks` (extended to cover `.dart`, `.yaml`, `.arb`, workflow and gradle
files). The workflow SHALL reuse the existing CI workflow via a reusable
workflow call rather than duplicating gate definitions.

#### Scenario: Failing gates block the release
- **WHEN** a tag is pushed whose commit fails `flutter analyze` or the
  coverage gate.
- **THEN** the release workflow aborts before creating the GitHub Release
  and no artifacts are published.

#### Scenario: Passing gates publish once
- **WHEN** all gates pass on the tagged commit.
- **THEN** the workflow creates exactly one GitHub Release for the tag and
  re-running the workflow does not duplicate artifacts (idempotent
  publication, existing release is reused or the run fails visibly).
