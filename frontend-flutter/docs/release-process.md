<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: omen-alpha (opencode-go) -->
<!-- Co-authored-by: deepseek-v4-flash (neuralwatt) -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

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
# 2. Cut the CHANGELOG: turn `## [Unreleased]` into
#    `## [<build-name>] – Released <YYYY-MM-DD>` and leave a fresh, empty
#    `## [Unreleased]` at the top (content untouched: the cut, not an edit).
# 3. A STABLE release checks in its curated body: RELEASE-NOTES/v<build-name>.md.
# 4. Tag the release commit and push:
git tag v0.4.0
git push origin v0.4.0
```

### The release body comes from a reviewed source

`scripts/release/publish-release.sh` resolves the GitHub Release body from
exactly one place per release — it never publishes generated notes (the
defect `#953` fixed for the backend; the reviewed prose sat unread while
`--generate-notes` shipped a commit list):

1. **`RELEASE-NOTES/v<build-name>.md`**, used **verbatim** minus its
   SPDX/co-author comment header. The owner writes the body — title, intro,
   `### Highlights`, the per-ABI artifact list, the version line (the
   `v0.3.0` structure, `frontend-flutter/RELEASE-NOTES/v0.4.0.md` as the
   reference). Nothing is prepended or appended, so the reviewed file is
   what readers see.
2. otherwise the **mechanical body** the script emits itself — the four
   ABI-named artifacts and the sideloading hint. That is what every
   alpha/beta build needs and nobody curates.

A stable release is expected to check in (1). The resolution is guarded by
`scripts/release/tests/publish-release-notes-test.sh` (run from the
`flutter-ci.yml` `version-drift` job): curated body wins verbatim, fallback
unchanged, pre-release flag still derived from the tag name.

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

## The Flutter toolchain pin and the AOT smoke gate

The release and CI workflows pin `flutter-version: 3.50.1` (Dart 3.14.0)
**instead of floating on `channel: stable`**, and both must carry the same pin
(`flutter-ci.yml`, `flutter-release.yml` — bump them in one PR so the gates and
the build always see one SDK).

Why not float: a floating stable channel once carried a release-only AOT
miscompile into the pipeline. The AOT compiler aborted on one source shape — a
deferred `final` assigned in a pattern `switch` case and captured by a closure
([dart-lang/sdk#64917](https://github.com/dart-lang/sdk/issues/64917), P0):

```
runtime/vm/compiler/backend/linearscan.cc: 3013: error: unreachable code
Dart snapshot generator failed with exit code -6
```

That killed the v0.4.0 release build on all three ABIs **after** every
JIT/debug gate was green, because the crash only happens in a release AOT
build. It is not a build-config, signing or NDK problem, and it is not our
Dart — which is why the toolchain is pinned and why the shape is guarded (see
below) rather than trusted to a calendar.

**The guard is a PR gate, not a weekly job.** `dart compile aot-snapshot` uses
the same `gen_snapshot` as a release build, so the `format-and-analyze` job of
`flutter-ci.yml` AOT-compiles the danger shape in
`tool/aot-regressions/deferred_final_switch_closure.dart` against the **pinned**
SDK on every run (seconds: no Gradle, no Android SDK, no keystore). Run it by
hand before bumping:

```bash
bash scripts/release/check-flutter-aot-regression.sh
# exit 0 = this SDK AOT-compiles the shape (safe to pin)
# exit 3 = still aborts in linearscan.cc (do not pin or ship this SDK)
# exit 1 = cannot judge (SDK older than 3.14.0, or a different compile failure
#          — read the log, do not read it as a pass)
```

So a future bump onto a broken snapshotter fails the bumping PR instead of a
release pipeline: bump `flutter-version` in both workflows, let the AOT smoke
gate and the rest of the gates run, and only then tag.

Do not "reduce" the probe file and do not remove the closure capture: every
element of that shape is load-bearing for the repro.

**Measured 2026-11-27: the probe is necessary but NOT sufficient.** On the
pinned Dart 3.14.0 the probe *compiles* — so the gate reported `state=fixed`
for an SDK whose snapshotter still aborts. The gap is the call site: the probe
hands the capturing closure to a statically resolved, `vm:never-inline`
helper, and the register allocator is happy; the reductions that actually
crash hand it to a sink the compiler cannot see through (upstream's
`print(() => runId)`, and in this app the `Either.match(...)` closures of
`AiConfigController.create`). A shape probe can therefore never prove that
*this* app compiles.

**The authority is a release build for the target ABIs** — the very
`android_aot_release_android-*` task that killed the pipeline, i.e. the
Android build of the artifact you ship (the acceptance criterion of the fix
for issue #1011 was exactly this, ~2 min with a warm Gradle):

```bash
flutter build apk --flavor dev --release --target-platform android-arm64
# repeat per shipped ABI (android-arm, or the AAB/split you publish)
```

**A host AOT compile of the app's own kernel is the fast DIAGNOSTIC, never the
proof.** `dart compile aot-snapshot` runs the *host's* `gen_snapshot`, so it
exercises the same register-allocator pipeline in ~80 s without Gradle, an
Android SDK or a keystore, and it names the offending function on the first
failure — but it produces a host-architecture snapshot, so a pass does not
show that the Android binaries for the target ABIs compile. Use it to find a
culprit, then confirm with the release build above.

`flutter assemble` writes its intermediates to a configuration-hashed
directory under `.dart_tool/flutter_build/` — one `app.dill` per distinct
defines/`--output` combination — so a glob also matches kernels of *other*
configurations (an old `--output` directory alone changes the hash), and
`dart compile` accepts exactly one input. Clear that cache first so only this
build's kernel can remain, and chain the two steps so a failed kernel build
can never fall through to an older `app.dill`:

```bash
rm -rf .dart_tool/flutter_build   # so exactly one app.dill can exist below
# 1. release kernel only (no Gradle, no Android SDK, no keystore, ~40 s);
#    `&&` keeps step 2 out of a failed build
flutter assemble --no-version-check --output=/tmp/fbuild \
  -dTargetFile=lib/main.dart -dTargetPlatform=android -dBuildMode=release \
  -dTrackWidgetCreation=false -dTreeShakeIcons=true -dFlavor=dev \
  -dAndroidArchs="android-x64" -dMinSdkVersion=24 kernel_snapshot_program \
&& dart compile aot-snapshot \
     "$(find .dart_tool/flutter_build -name app.dill)" -o /tmp/app.aot
# crash report line: "Crash occurred when compiling ... in AOT mode in
# AllocateRegisters pass" — that is the function whose shape to rewrite
```

Prefer the release build over trusting the probe whenever the pin moves or a
controller grows a `switch` over a sealed type with a deferred `final`; reach
for the kernel diagnostic when you want the culprit named without a full
Gradle build.

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
#   DEFAULT_PROJECT_ID=<project-id>
./scripts/dev/build-test-apk.sh          # --help documents every define
```

Preconditions (hard fail before any build work, so misconfiguration never
surfaces as a later runtime error):

- `DEFAULT_PROJECT_ID` non-empty — an empty define dispatches a
  season-create with an empty project_id that only shows up as a generic
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
`http://10.0.2.2:3000`, emulator only), `DEV_AUTH_SUB`, `DEFAULT_PROJECT_ID`,
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
