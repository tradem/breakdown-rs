<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: omen-alpha (opencode-go) -->
<!-- Co-authored-by: deepseek-v4-flash (neuralwatt) -->

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

#### Building a dev test APK (`scripts/dev/build-test-apk.sh`, issue #475)

`scripts/dev/build-test-apk.sh` is the one-command way to produce an
installable test APK for a real device or emulator — it encodes what the
local-testing sessions kept as tribal knowledge (flavor + entrypoint, the
`--dart-define` set, the pinned-CA sanity check, the per-build version
marker). `scripts/release/*` is the PROD pipeline (CI signing + real OIDC
secrets) and is deliberately the wrong target for local testing. The dev
flavor is dev-runtime-only and is never published (spec
`flutter-release-artifacts`).

```bash
cd frontend-flutter
# one-time: create a gitignored .env.build-test with your values
#   API_BASE=https://<lan-ip>:3000
#   DEV_AUTH_SUB=<dev-subject>
#   DEFAULT_SERIES_ID=<series-id>
./scripts/dev/build-test-apk.sh          # --help documents every define
```

Preconditions (hard fail before any build work, so misconfiguration never
surfaces as a later runtime error):

- `DEFAULT_SERIES_ID` non-empty — an empty define dispatches a
  season-create with an empty series_id that only shows up as a generic
  422 at runtime (issue #467).
- `DEV_AUTH_SUB` non-empty — backend dev-auth parity (ADR-018).
- `assets/certs/dev/ca.pem` is NOT the committed placeholder
  (`CN=breakdown-dev-ca`) and parses as an X.509 certificate — the dev
  flavor pins this CA as its exclusive trust anchor (spec
  `flutter-dev-ca`). For a LAN https edge, install the LAN CA from
  `backend/dev-certs/lan/` (`ca.crt` → `assets/certs/dev/ca.pem`) with a
  leaf whose SAN covers the edge host/IP.
- `API_BASE` scheme/host policy hint: https always OK; cleartext http only
  for the emulator/loopback hosts in `kDevCleartextHosts`
  (`10.0.2.2`, `127.0.0.1`, `localhost`) — an http base to any other host
  warns loudly (non-fatal; the app's runtime validation is the final gate).

Defines (each injected with `--dart-define`; precedence: environment >
`.env.build-test` > built-in defaults): `API_BASE` (default
`http://10.0.2.2:3000`, emulator only), `DEV_AUTH_SUB`, `DEFAULT_SERIES_ID`,
and `APP_VERSION` — the latter defaults to `<pubspec version> · DEV-<n>`, a
per-build marker that auto-increments over the stamps in `build/test-apk/`
so every installed variant is identifiable in the About dialog.

Outputs, each run:

```text
build/app/outputs/flutter-apk/app-dev-release.apk   (raw build)
build/test-apk/breakdown-dev-<marker>.apk           (stamped copy, sha256 printed)
```

The dev-flavor release build type is debug-signed by the Gradle fallback
(`build.gradle.kts`), so the APK installs on a device without a signing
environment — but treats it as what it is: a local test build, never a
release artifact.
