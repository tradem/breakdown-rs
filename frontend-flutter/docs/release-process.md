<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: omen-alpha (opencode-go) -->

# Android Release Process (tag → GitHub Release)

> OpenSpec change `add-android-release-workflow` (specs
> `flutter-release-artifacts`, `flutter-release-signing`). The release
> pipeline lives in `.github/workflows/flutter-release.yml`; the reusable
> quality gates it calls live in `.github/workflows/flutter-ci.yml`.

## Versioning — one rule, one source

- `frontend-flutter/pubspec.yaml` carries
  `version: X.Y.Z[-alpha.N|-beta.N]+N` and is the **single source** for
  `versionName`/`versionCode` (Flutter's default Gradle wiring).
- Release tags are `v<build-name>` — `v0.3.0`, `v0.3.0-alpha.1` — i.e. the
  tag equals the pubspec build-name with a `v` prefix. The release workflow
  fails loudly if they disagree, and fails if the pubspec versionCode is
  not strictly greater than every previous release tag's versionCode.
- Alpha/beta channels are tag suffixes (`-alpha.N`, `-beta.N`), **not**
  branches: suffixed tags publish as GitHub *pre-releases*, stable versions
  as full releases. One workflow, one boolean.

## Preconditions (one-time bootstrap)

1. Generate the release keystore offline and store the CI secrets
   (`KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD` on
   the protected `release` environment) — see
   [`release-signing-key-custody.md`](release-signing-key-custody.md).
2. Record the keystore's SHA-256 fingerprint as
   `EXPECTED_SHA256_FINGERPRINT` in `.github/workflows/flutter-release.yml`
   (done — `bfd0184e…fbc8b`; update it together with
   [`release-signing-key-custody.md`](release-signing-key-custody.md) §2
   if the key ever rotates, §6).
3. Provision the protected GitHub `release` environment (required
   reviewers, deployment restricted to `v*` tags) and add the prod OIDC
   secrets (`OIDC_ISS`, `OIDC_CLIENT_ID`, `OIDC_AUDIENCE`).
4. Update the pubspec version + commit, then tag.

## Cutting a release

```bash
# 1. Bump the version in frontend-flutter/pubspec.yaml (X.Y.Z+build),
#    commit to main, let PR CI run green.
# 2. Tag the release commit and push:
git tag v0.4.0-alpha.1
git push origin v0.4.0-alpha.1
```

The release workflow then runs, in order (logic encapsulated in locally
runnable scripts under `frontend-flutter/scripts/release/` — these are the
canonical implementation; the workflow only wires env/secrets around
them):

1. **Reusable CI quality gates** — format, analyze, gitleaks, OpenAPI
   client drift, version drift, coverage, gherkin harness
   (`.github/workflows/flutter-ci.yml` via `workflow_call`). Failing gates
   abort before any artifact is created.
2. **Version gate** — tag ↔ pubspec build-name equality + strictly
   monotonic versionCode across all previous `v*` tags.
3. **Build & publish** in the protected `release` environment (key
   custodians approve the deployment):
   - `flutter build apk --release --flavor prod -t lib/main_prod.dart
     --split-per-abi` → three APKs (`arm64-v8a`, `armeabi-v7a`, `x86_64`),
   - `flutter build appbundle --release --flavor prod -t lib/main_prod.dart`
     → one `.aab`,
   - all signed with the project keystore and verified against the recorded
     fingerprint (`apksigner` for APKs; `jarsigner` + a `bundletool
     build-apks` round-trip for the AAB),
   - artifacts named `breakdown-<version>-<abi>.apk` /
     `breakdown-<version>.aab`, attached to the GitHub Release (re-running
     the workflow re-uploads with `--clobber` — idempotent, no duplicates).

The `dev` flavor is dev-runtime-only and is never published.

## Installing (testers)

Download the APK for your device architecture (virtually all modern
devices: `arm64-v8a`) from the GitHub Release page, enable "Install unknown
apps" for the browser/file manager, and install directly — no store
account. A later release signed with the same project key updates in
place, no uninstall.

## Distribution roadmap

- **This change** — self-published GitHub Release APKs/AABs, project-key
  signed (Decision D9, one key across developer-published channels).
- **`add-fdroid-inclusion`** — F-Droid inclusion (fdroiddata metadata MR;
  will use this key's SHA-256 fingerprint for
  `AllowedAPKSigningKeys`/developer-signed `Binaries:`; F-Droid *source
  builds* are signed by F-Droid's own buildbot key and carry no
  cross-channel fingerprint claim).
- **`add-play-store-release`** — Google Play (AAB upload, Play App Signing
  enrollment, Data Safety form; consumes the signed `.aab` produced here).

## Local build notes (no CI)

- Local release builds without signing environment variables stay
  **unsigned** (prod) or **debug-signed** (dev, only for local
  `flutter run --release`); a locally built prod APK is NOT a release
  artifact — never distribute it.
- With Gradle flavors now declared (`dev`/`prod`, change
  `add-android-release-workflow`), builds must pass a flavor: build the
  dev variant with `flutter build apk --flavor dev` (or
  `flutter test integration_test/<test>.dart --flavor dev` on a device —
  the gherkin runner config sets `buildFlavor = 'dev'` itself). Plain
  unflavored builds no longer exist (`assembleDebug` → `assembleDevDebug`).
- **Coexistence (issue #419, option 2b):** the dev and prod flavors ship
  DISTINCT application IDs (`rs.breakdown.frontend_flutter` vs
  `rs.breakdown.frontend_flutter.dev`) AND distinct redirect schemes
  (`breakdown://auth/callback` vs `breakdown-dev://auth/callback`), so a
  locally debug-signed `devRelease` coexists with a published prod install
  — no certificate-mismatch uninstall dance, and the OAuth browser
  redirect always resolves to exactly one installed app. (Historical note:
  before this change both flavors shared one application ID, so installing
  a local dev build over a published prod APK failed with a
  certificate-mismatch error; existing dev installs from before the
  switch are a separate app now — uninstall the old one once.)
- The dev IdP client registration must allowlist the derived dev URI
  `breakdown-dev://auth/callback` — see `self-hosting.md` §4.
