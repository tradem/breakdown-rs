<!--
SPDX-License-Identifier: AGPL-3.0
Copyright (C) 2024-2026 Breakdown RS Contributors
Co-authored-by: omen-alpha (opencode-go)
-->

# Hosting your own breakdown-rs instance

> Self-hosting guide (issue #416). Documentation only — every mechanism
> described here already exists in the app; this guide just walks you
> through using it.

## Why the official APK cannot reach your instance

The officially published Android binaries (GitHub Releases, see
[`release-process.md`](release-process.md)) are **deliberately bound to the
project-operated backend at build time**:

- the API base URL is compiled in (`--dart-define=API_BASE`; without it the
  prod flavor defaults to `https://api.breakdown.rs`),
- the client pins a specific CA (`assets/certs/prod/ca.pem`) and constructs
  its TLS context fail-closed, with **no system roots** (ADR-032),
- the OIDC issuer, client id and redirect URI are baked in, and the prod
  bootstrap refuses to start without them (`lib/app.dart`
  `validateStartupConfig`). The audience (`OIDC_AUDIENCE`) is baked in
  when configured and validated by the backend at runtime — it is **not**
  a client-side startup requirement,
- the in-app "Backend URI" override exists in the **dev flavor only**; a
  prod build ignores and clears any stored override on boot (spec
  `flutter-app-dialogs`).

This posture is intentional: **one binary = one instance**, so a shipped
app can never be silently redirected. It is a security stance, not a
limitation you can work around at runtime — and you do not need to. The
app is a compile-time-configurable client, so building your own APK bound
to *your* instance is fully supported by design.

**What you build is yours to control.** The release-pipeline "one key"
invariant (Decision D9 in `add-android-release-workflow`, spec
`flutter-release-signing`) scopes to binaries **the project publishes
itself**. An instance-owned build signs with the instance's own key by
design.

## 1. Deploy the backend

The Android client needs three server-side things, all under *your*
control:

1. **An HTTPS edge with your own domain.** The backend edge is Caddy with
   ACME certificates (ADR-025). Your API must be reachable at an
   `https://` URL whose certificate chains to a root CA **you control
   pinning for** (§3). For host hardening beyond the edge, see ADR-026 and
   `backend/docs/operations/host-hardening.md`.
2. **Your own OIDC identity provider.** The backend validates JWTs from
   the configured issuer (ADR-010, ADR-018). Register a **native-app
   client** in your IdP and note:
   - `OIDC_ISS` — the issuer URL (the `https://…` value the backend uses),
   - `OIDC_CLIENT_ID` — the native client registration id,
   - `OIDC_AUDIENCE` — the audience the backend expects (mirrored by the
     client's token request; validated by the backend at runtime).
3. **A redirect URI registered for that client.** The app authenticates
   via an Android deep link on a custom scheme. The default URI is
   `breakdown://auth/callback` (from `frontend-flutter/oidc-config.json`);
   register exactly this URI with your client unless you deliberately
   change it (§4).

For the backend deployment itself (Postgres, SierraDB, API service,
release runbook), follow `backend/docs/operations/runbooks.md` and
`backend/docs/operations/release-runbook.md`.

## 2. Prerequisites on your machine

- Flutter SDK (the stable channel pinned by the repo — see
  `.github/workflows/flutter-ci.yml` for the version CI uses),
- a clone of this repository,
- for signing (§5): `keytool`/`apksigner` from the Android build tools.

## 3. Pin YOUR instance CA

The client pins a CA — **the root, not a leaf** — and trusts nothing else
(`withTrustedRoots: false`, fail-closed). Pinning the root means your
leaf certificates can rotate freely (e.g. an ACME ~90-day rhythm) without
re-shipping the app; only a root rotation needs a new build (ADR-032,
which also describes the dual-root overlap pattern for that case).

Two ways to supply the CA for a prod build:

- **Replace the bundled asset (tree-local, what this guide uses):** put
  your instance root CA (PEM, `-----BEGIN CERTIFICATE-----` block) into
  `frontend-flutter/assets/certs/prod/ca.pem` in your build checkout.
  A missing or unparseable PEM aborts startup before any HTTP client is
  constructed — you will notice immediately, not in production traffic.
- **Inline define (no tree edit):** pass the PEM via
  `--dart-define=PINNED_CA_PEM="<contents>"`. This takes precedence over
  the bundled asset (`lib/src/network/api_client.dart`). Watch shell
  quoting with multi-line PEM values; if your toolchain mangles them,
  prefer the asset replacement.

> If your edge uses a Let's Encrypt certificate and you are fine pinning
> its root (ISRG X1 / X2), the CA file is that root's PEM. If you run a
> private CA, export its root certificate.

Do **not** disable verification or ship a `danger_accept_invalid_certs`
equivalent — there is no such switch in this codebase by design (spec
`flutter-client-authz`).

## 4. OIDC redirect URI: one source, checked fail-closed

`frontend-flutter/oidc-config.json` is the single source for the redirect
URI:

- Gradle reads it to derive the deep-link scheme and register the
  manifest placeholder natively,
- the same file is passed to the Dart build via
  `--dart-define-from-file=oidc-config.json`,
- the file is also bundled as an app asset.

At startup, `checkRedirectConsistency` (in `lib/app.dart`) verifies that
the compiled `OIDC_REDIRECT_URI` matches the bundled JSON and **aborts
startup on any mismatch** — because an explicit `--dart-define` bypasses
the file, and neither side can see the other. The failure message tells
you the rule:

> Set the URI in `oidc-config.json` and pass it via
> `--dart-define-from-file` instead of `--dart-define`.

So: keep `breakdown://auth/callback` (and register it in your IdP), or
edit `oidc-config.json` to your own scheme **and keep passing the file
via `--dart-define-from-file`** — never set `OIDC_REDIRECT_URI` with an
explicit `--dart-define=` alongside it.

## 5. Build the instance-owned APK

From the repository root:

```bash
cd frontend-flutter

# Signing material — YOUR instance's key, generated on your machine:
#   (see spec flutter-release-signing for the shape of the Gradle wiring;
#    the same KEYSTORE_* environment variables the CI uses work locally)
keytool -genkeypair -v -keystore ~/instance-release.keystore \
  -alias instance -keyalg RSA -keysize 4096 -validity 10000

export KEYSTORE_FILE="$HOME/instance-release.keystore"
export KEYSTORE_PASSWORD='…'   # keystore passphrase
export KEY_ALIAS=instance
export KEY_PASSWORD='…'        # key passphrase

flutter build apk --release --flavor prod -t lib/main_prod.dart \
  --split-per-abi \
  --dart-define=API_BASE=https://breakdown.example.org \
  --dart-define=OIDC_ISS=https://idp.example.org \
  --dart-define=OIDC_CLIENT_ID=your-native-client-id \
  --dart-define=OIDC_AUDIENCE=breakdown \
  --dart-define=APP_VERSION=0.1.0+selfhost \
  --dart-define-from-file=oidc-config.json
```

Notes:

- **`API_BASE` is mandatory for a self-hosted build.** Omitting it
  compiles in the project default `https://api.breakdown.rs`. The prod
  flavor requires an `https://` base (asserted at the composition root —
  cleartext would bypass the pinned-CA TLS context).
- **`OIDC_ISS` and `OIDC_CLIENT_ID` are required.** A prod build without
  them fails closed at startup (`validateStartupConfig`); the CI performs
  the same check at build time (`scripts/release/check-build-config.sh`).
- **`APP_VERSION`** feeds the About dialog; it falls back to `unknown`
  when omitted. Use your own versioning (`+selfhost` marks the build
  metadata).
- **Signing:** without the `KEYSTORE_*` variables the prod release build
  is **deliberately unsigned** (no debug-key fallback — D9). With them,
  Gradle signs the APK with your key (including v3 signature-scheme
  lineage, ready for a future planned rotation).
- The build emits split APKs per ABI (`arm64-v8a`, `armeabi-v7a`,
  `x86_64`); install the one matching your device (usually `arm64-v8a`).
  Add `flutter build appbundle` with the same flags if you want an `.aab`.
- Each build is bound to your instance; a different instance means a
  different APK. That is the stated trade-off of the single-instance
  posture.

## 6. Install and verify

1. Install the APK ("install unknown apps" on your device).
2. On first launch the app loads its pinned CA and OIDC configuration
   before any network traffic; a misconfiguration (missing CA, OIDC
   mismatch) shows a fatal-config screen naming the problem.
3. Sign in via your IdP; the deep link returns to the app.
4. Sanity-check the connection: the app talks to `API_BASE` exclusively.

## 7. Testing without public infrastructure

To try a self-hosted setup before standing up public infrastructure, use
the **dev flavor** against your backend dev compose:

```bash
# Backend (repo root):
cd backend && docker compose -f docker-compose.dev.yml up -d
DATABASE_URL=postgres://postgres:postgres@localhost:5432/breakdown \
SIERRADB_URL=redis://127.0.0.1:9090/?protocol=resp3 \
cargo run -p api

# Client (physical device on the same LAN):
cd frontend-flutter
flutter run --flavor dev \
  --dart-define=API_BASE=http://192.168.x.y:3000
```

- The dev flavor's API base defaults to `http://10.0.2.2:3000`
  (Android-emulator host alias); a physical device needs a LAN-reachable
  address. Cleartext `http://` works in the dev flavor — the HTTPS-only
  assertion is prod-only; note that the dev **runtime** override dialog
  (Settings) additionally restricts cleartext to the loopback/emulator
  hosts in `kDevCleartextHosts`.
- For remote devices, an SSH/reverse tunnel to a dev host works the same
  way.
- **Dev auth mode:** run the backend with `DEV_AUTH_SUB` set and no
  `OIDC_ISS`, and the client treats the dummy user as authenticated —
  no IdP needed for local trials.
- **Optional dev IdP:** the backend dev overlay can boot a Logto IdP on
  `http://localhost:3301` (`docker-compose.idp.yml` +
  `./scripts/seed-logto-dev.sh`). The dev flavor pins the dev CA set
  (spec `flutter-dev-ca`), and `DEV_IDP_INSECURE=1` (dev flavor,
  non-release builds only) allows the HTTP port-forward IdP exception —
  verification stays on; this flag is impossible in prod or release
  builds by startup guard.
- The in-app Settings dialog can change the backend URI at runtime in
  the **dev flavor only** (`api_base_override`); a prod build ignores and
  clears it on boot.

## Non-goals

- The **officially published** APK stays single-backend — this guide
  changes nothing about it.
- **Reproducible builds** (so anyone can verify a published binary from
  source) are tracked by the `add-fdroid-inclusion` change; that is the
  trust anchor for "build your own" at distribution scale, beyond this
  guide.

## References

- ADRs: [`ADR-032`](../../backend/docs/architecture/adrs/ADR-032-flutter-client-tls-pinning-rotation.md)
  (TLS pinning/rotation), [`ADR-010`](../../backend/docs/architecture/adrs/ADR-010-authentication-with-oidc.md)
  (OIDC), [`ADR-018`](../../backend/docs/architecture/adrs/ADR-018-oidc-jwt-validation-and-dev-auth-toggle.md)
  (JWT validation), [`ADR-025`](../../backend/docs/architecture/adrs/ADR-025-https-edge-and-cert-rotation.md)
  (HTTPS edge), [`ADR-026`](../../backend/docs/architecture/adrs/ADR-026-arch-linux-vps-hardening-baseline.md)
  (host hardening)
- OpenSpec specs: `flutter-client-authz`, `flutter-dev-ca`,
  `flutter-app-dialogs`, `flutter-release-signing`,
  `flutter-release-artifacts` (under `openspec/specs/`)
- Related changes: `add-android-release-workflow` (the release pipeline
  this builds on — archived), `add-fdroid-inclusion` (reproducible
  builds), `add-play-store-release`
- Build/reference scripts: [`scripts/release/build-release.sh`](../scripts/release/build-release.sh),
  [`scripts/release/check-build-config.sh`](../scripts/release/check-build-config.sh)
