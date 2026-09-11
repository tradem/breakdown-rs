<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->

# add-android-release-workflow — Design

## Context

The Flutter app (`frontend-flutter/`) is Android-first, scaffolded with pinned
min-SDK/Kotlin/AGP versions (`flutter-scaffold` spec) and dev/prod flavors
wired via `--dart-define` (pinned-CA posture per `flutter-client-authz` /
`flutter-dev-ca`). CI today covers PR quality gates only; no signing, no
release builds, no published binaries exist. The backend AGENTS.md rules on
CI hardening (SHA-pinned actions, no `${{ github.event.* }}` in `run:`),
gitleaks, and secrets apply monorepo-wide.

Research on F-Droid inclusion (see conversation 2026-02) established:
F-Droid builds from source via an `fdroiddata` metadata MR and never accepts
APK uploads; Google Play requires `.aab` + Play App Signing; both benefit
from a pre-existing developer-owned signing key and stable artifacts. This
change establishes that foundation; F-Droid (`add-fdroid-inclusion`) and
Play (`add-play-store-release`) are separate changes.

## Goals / Non-Goals

**Goals:**
- One project-owned signing key used by every distribution channel (D9).
- Tag-triggered, gated release build producing installable APKs (alpha/beta
  testers sideload from GitHub Releases) plus one AAB for the later Play
  change.
- Reusable, idempotent workflow consistent with existing CI conventions.

**Non-Goals:**
- F-Droid metadata, reproducible-build hardening, `AllowedAPKSigningKeys`
  registration (→ `add-fdroid-inclusion`).
- Play Store account, Play App Signing enrollment, Data Safety form
  (→ `add-play-store-release`).
- In-app updater packages (e.g. `github_release_apk_updater`) — deferred;
  testers install manually for now.
- iOS/macOS distribution.
- Changes to the app's runtime behavior, auth, or the generated client.

## Decisions

### D9 — Developer-signed builds (locked)
All channels use one project keystore; F-Droid later verifies via
`AllowedAPKSigningKeys` instead of F-Droid's own key, Play later enrolls the
same key (Play App Signing "upload key = app signing key" is acceptable; if
Play generates its own app signing key, the one-key invariant is documented
as GitHub-Release/F-Droid-only for Play-sourced binaries).
- *Alternative considered:* F-Droid-signed builds — rejected: migration
  between channels would force uninstall/reinstall, and the community
  "developer signature" pattern is the established F-Droid-adjacent practice.
- *Alternative considered:* Play-first (upload key vs. app signing key split)
  — rejected for now: enrollment happens in `add-play-store-release`; this
  change does not want its keystore semantics coupled to Play.

### Signing material flows through CI secrets, not the repo
`KEYSTORE_BASE64` (+ passwords/alias) as GitHub Actions secrets; the workflow
decodes to a temp path at build time. Local builds without env vars fall back
to unsigned (`signingConfig` unset) — a *decisive* unsigned artifact, not a
debug-signed one, so an unsigned APK can never be mistaken for a release.
- *Alternative considered:* committed debug-keystore fallback (common
  template pattern) — rejected: a debug-signed release binary invites
  accidental distribution with the wrong key and violates the one-key
  invariant.

### Versioning: pubspec.yaml as single source, tag must match
`version: <semver>+<versionCode>` in `pubspec.yaml` drives both
`versionName` and `versionCode` (Flutter's default Gradle wiring). The
workflow gate fails on tag↔pubspec mismatch — this is exactly what F-Droid's
`UpdateCheckData: pubspec.yaml|version:...` expects later, so the convention
is established once and reused.
- *Alternative considered:* tag-driven version injection via
  `--dart-define`/`--build-name` — rejected: diverges from the pubspec
  source-of-truth and complicates the later `UpdateCheckData` regex.

### Pre-release channel: tag suffixes, not branches
`-alpha.N` / `-beta.N` suffixes map to GitHub pre-releases. No separate
branch, no separate channel workflow — one workflow, one boolean.
- *Alternative considered:* `main`/`beta`/`stable` branch model — rejected:
  overkill for the current team size; suffix tags carry the channel.

### Gates via reusable workflow call
The release workflow calls the existing CI workflow as a reusable workflow
before building, so gates are defined once. Publication happens only after
gates pass.

### Artifact naming: `breakdown-<version>-<abi>.apk` / `breakdown-<version>.aab`
Explicit, greppable, contains the version — F-Droid's later `Binaries:`
verification (if ever used) and human testers both benefit; plain
`app-arm64-v8a-release.apk` is ambiguous across versions.

## Risks / Trade-offs

- **Key loss = unrecoverable** (Android signature trust) → offline backup
  with at least two maintainers + recorded SHA-256 fingerprint; procedure in
  `docs/` (or `frontend-flutter/docs/`), not in code.
- **Secret leakage via workflow logs** → actions' `set-secret` masking plus
  gitleaks on the tree; the workflow never echoes signing variables.
- **Split-APK vs. universal APK confusion for testers** → Release notes name
  the correct APK per device ABI (arm64-v8a for virtually all modern
  devices); a universal APK can be added later without spec change if
  testers struggle.
- **Play App Signing may re-key the app later** → documented in D9; the
  one-key invariant applies to GitHub Releases + F-Droid; Play uses its
  enrollment decision from `add-play-store-release`.
- **Flutter engine/Gradle version drift breaks the release build** → the
  workflow pins Flutter SDK version the same way CI does (single source in
  the workflow or a committed version file).

## Migration Plan

1. Generate keystore offline, record fingerprint, store secrets + backup.
2. Land Gradle signing config (unsigned fallback) — no user-visible change.
3. Land the release workflow; test with a `v0.x.0-alpha.1` pre-release tag.
4. Cut the first real alpha release; testers sideload from GitHub Releases.
5. Rollback: disable the workflow; published releases are immutable and
   remain distributable.

## Open Questions

- Repository hosting for releases: assumed GitHub (mirrors current CI);
  confirm before the first tagged release since F-Droid metadata will point
  there.
- Keystore custody: which two maintainers hold the offline backup
  (decision needed before step 1 of the migration plan).
