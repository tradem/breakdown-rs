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
- One project-owned signing key for every self-published binary (D9;
  scoped to GitHub Releases + developer-signed F-Droid artifacts — F-Droid
  source builds and Play use their channel's own key, see D9).
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
One project keystore signs every binary this project publishes itself. The
one-key guarantee is scoped to **developer-published channels**: GitHub
Release APKs/AABs (this change) and developer-signed F-Droid artifacts (if
`add-fdroid-inclusion` adopts the fdroiddata `Binaries:` pattern pointing at
these GitHub Release APKs). It deliberately does NOT extend to:
- **F-Droid source builds** — the fdroiddata buildbot signs with F-Droid's
  own key; `AllowedAPKSigningKeys` only *rejects* mismatched
  developer-provided APKs, it never changes the key of source-built ones.
  Source-built F-Droid APKs therefore do not carry the project fingerprint:
  `add-fdroid-inclusion` MUST define a developer-signed artifact path
  (`Binaries:` or reproducible builds) before any cross-channel
  no-uninstall claim is made for F-Droid.
- **Google Play** — Play App Signing controls the key of Play-distributed
  binaries under every enrollment model. Whether the developer key is
  enrolled as "upload key = app signing key" or Play generates its own key
  is decided in `add-play-store-release`; until then no cross-channel
  update-without-reinstall guarantee is claimed for Play.
- *Alternative considered:* F-Droid-signed builds for self-published
  channels — rejected: migration between self-published channels would
  force uninstall/reinstall, and the community "developer signature"
  pattern (fdroiddata `Binaries:`) is the established F-Droid-adjacent
  practice.
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
One tag/pubspec format across the release workflow and the CI validator:
`pubspec.yaml` carries `version: X.Y.Z[-alpha.N|-beta.N]+N` (the optional
pre-release suffix matches the release channel), the release tag is
`v<build-name>` (e.g. `v0.3.0`, `v0.3.0-alpha.1`), and the build-name drives
both `versionName` and `versionCode` (Flutter's default Gradle wiring). The
workflow gate fails on tag↔pubspec mismatch — this is exactly what F-Droid's
`UpdateCheckData: pubspec.yaml|version:...` expects later, so the convention
is established once and reused. Concretely, this change extends the existing
`flutter-ci.yml` `version-drift` validator: its regex accepts the optional
pre-release suffix, and its tag comparison applies to `v*` release tags
(the release-workflow format), superseding the `flutter-v*` prefix before
any release tag has been cut. `flutter-ci.yml` also gains a `workflow_call`
trigger in this change — without it the reusable CI gate below could never
run.
- *Alternative considered:* tag-driven version injection via
  `--dart-define`/`--build-name` — rejected: diverges from the pubspec
  source-of-truth and complicates the later `UpdateCheckData` regex.
- *Alternative considered:* strict `X.Y.Z+N` pubspec versions with
  pre-release info only in the tag — rejected: the tag↔pubspec gate could
  then never hold for pre-releases, defeating the single-source rule.

### Pre-release channel: tag suffixes, not branches
`-alpha.N` / `-beta.N` suffixes map to GitHub pre-releases. No separate
branch, no separate channel workflow — one workflow, one boolean.


- *Alternative considered:* `main`/`beta`/`stable` branch model — rejected:
  overkill for the current team size; suffix tags carry the channel.

### Gates via reusable workflow call
The release workflow calls the existing CI workflow as a reusable workflow
before building, so gates are defined once. Publication happens only after
gates pass. This requires the CI workflow to declare a `workflow_call`
trigger (added by this change together with the version-format alignment
above), and the reusable call must pass the tag's ref for the
`version-drift` gate to compare against.

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
- **Play App Signing re-keys Play-distributed binaries** → documented in
  D9; the one-key invariant applies to GitHub Releases + developer-signed
  F-Droid artifacts only. F-Droid source builds (F-Droid's key) and Play
  (Play App Signing's key, enrollment decided in `add-play-store-release`)
  are outside the invariant and outside this change's guarantees.
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
