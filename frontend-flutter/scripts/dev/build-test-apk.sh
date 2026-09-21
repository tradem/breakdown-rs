#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: deepseek-v4-flash (neuralwatt)

#
# build-test-apk.sh — one-command local test-APK build (dev flavor)
# (issue #475; specs `flutter-dev-ca`, `flutter-release-artifacts`).
#
# Produces an installable APK for a real device or emulator from the `dev`
# flavor (debug-signed by the Gradle dev-flavor fallback, NEVER a release
# artifact and never published):
#
#   build/app/outputs/flutter-apk/app-dev-release.apk    (raw build)
#   build/test-apk/breakdown-dev-<marker>.apk            (stamped copy + sha256)
#
# This encodes the local-testing tribal knowledge (sessions 2026-09-21) that
# previously had no scripted home: the `dev` flavor + entrypoint, the
# --dart-define set, the pinned-CA sanity check, and the per-build version
# marker. `scripts/release/*` is the PROD pipeline (CI signing + real OIDC
# secrets) and is deliberately NOT the target for local testing.
#
# Values are read, in precedence order (highest first):
#   1. the calling environment,
#   2. the gitignored `.env.build-test` file in frontend-flutter/,
#   3. built-in defaults where safe (emulator API_BASE, auto APP_VERSION).
#
# Run `--help` for the full documentation of every define and where each value
# lives. Idempotent and cwd-independent: the frontend-flutter root is resolved
# from this script's own location (same pattern as scripts/regen-client.sh);
# the raw build output is overwritten deterministically on re-run, and each
# run stamps a NEW `DEV-<n>` marker (unless APP_VERSION is set) so every
# installed variant is identifiable in the About dialog.
#
# Tools required: flutter, openssl, sha256sum (coreutils).
# Exit: 0 = APK built + stamped, 1 = precondition/build failure, 2 = usage.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# .../frontend-flutter/scripts/dev -> frontend-flutter
FLUTTER_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${FLUTTER_DIR}"

ENV_FILE=".env.build-test"
CA_PEM="assets/certs/dev/ca.pem"
PLACEHOLDER_CA_CN="breakdown-dev-ca"
LOOPBACK_HOSTS=" 10.0.2.2 127.0.0.1 localhost "
APK_DIR="build/app/outputs/flutter-apk"
APK_NAME="app-dev-release.apk"
TEST_APK_DIR="build/test-apk"
ENTRYPOINT="lib/main.dart"
DEFAULT_API_BASE="http://10.0.2.2:3000"

# die LINE [LINE ...] -- print each line with an `error: ` / indent prefix to
# stderr and exit 1.
die() {
  local first=1 line
  for line in "$@"; do
    if (( first )); then
      printf 'error: %s\n' "$line" >&2
      first=0
    else
      printf '       %s\n' "$line" >&2
    fi
  done
  exit 1
}

usage() {
  cat <<EOF
Usage: scripts/dev/build-test-apk.sh [--help]

One-command build of an installable dev-flavor test APK (issue #475). The dev
flavor is debug-signed by the Gradle fallback and is NEVER a release artifact
(spec flutter-release-artifacts).

Outputs
  ${APK_DIR}/${APK_NAME}
      raw 'flutter build apk --release --flavor dev' output (overwritten on re-run).
  ${TEST_APK_DIR}/breakdown-dev-<marker>.apk
      stamped copy; <marker> is the sanitized APP_VERSION (default 'DEV-<n>').
      A sha256 of the stamped copy is printed.

Precondition checks (hard fail before any build)
  - DEFAULT_SERIES_ID non-empty. An empty define dispatches a season-create
    with an empty series_id that surfaces only as a generic 422 at runtime
    (issue #467) — the script aborts instead.
  - DEV_AUTH_SUB non-empty. Dev-auth parity with the backend (ADR-018);
    without it the app has no authenticated developer identity.
  - ${CA_PEM} must NOT be the committed placeholder (CN=${PLACEHOLDER_CA_CN})
    and must parse as an X.509 certificate. The dev flavor pins this CA as its
    EXCLUSIVE trust anchor (spec flutter-dev-ca); a real device on a LAN or
    remote https edge needs a real CA whose leaf cert covers the edge host/IP
    (e.g. the LAN CA from backend/dev-certs/lan/: ca.crt -> ${CA_PEM}, per the
    local-testing session notes).
  - API_BASE scheme/host policy hint (mirror of kDevCleartextHosts in
    lib/data/settings/api_base_validation.dart): https always OK; cleartext
    http only for the emulator/loopback hosts 10.0.2.2, 127.0.0.1, localhost.
    An http base to any other host prints a loud warning but is NOT fatal — the
    app's runtime validation is the final gate
    (settings.backend_uri_cleartext_rejected; the transport withholds the
    bearer token).

Dart defines injected (--dart-define)
  API_BASE
      Backend base URL for this build. Default: ${DEFAULT_API_BASE} (emulator
      loopback — 10.0.2.2 is the Android-emulator alias for the host). A real
      device needs the https edge of the dev machine on your LAN, e.g.
      https://<lan-ip>:3000 — mirror the SAN of the LAN leaf you installed into
      ${CA_PEM}. Where it lives: .env.build-test or the calling environment.
  DEV_AUTH_SUB
      Authenticated subject for dev-auth mode (backend ADR-018 / DEV_AUTH_SUB).
      REQUIRED (hard fail when empty). Where it lives: your .env.build-test /
      environment; the backend must run with DEV_AUTH_SUB set to match.
  DEFAULT_SERIES_ID
      Season-creation pre-fill (lib/app_config.dart). REQUIRED (hard fail when
      empty, issue #467). Where it lives: a series id from the dev backend you
      test against (GET /v1/series), in .env.build-test / environment.
  APP_VERSION
      About-dialog marker (lib/features/app_info/info_dialog.dart). Default:
      '<pubspec version> · DEV-<n>' — <n> auto-increments from the stamps
      already present in ${TEST_APK_DIR}, so every build is unambiguous. Set it
      explicitly for a custom label; the stamped filename uses a sanitized form.

Value source precedence (highest first)
  1. Calling environment
  2. ${ENV_FILE} in frontend-flutter/ (gitignored; simple KEY=VALUE per line,
     '#' comments and blank lines ignored, optional surrounding double quotes
     stripped). Create it once so this script becomes truly one command:
       API_BASE=https://<lan-ip>:3000
       DEV_AUTH_SUB=<dev-subject>
       DEFAULT_SERIES_ID=<series-id>
  3. Built-in defaults (API_BASE emulator default, APP_VERSION auto marker)

Exit codes: 0 ok; 1 precondition/build failure; 2 usage error.
Tools required: flutter, openssl, sha256sum (coreutils).
EOF
}

if [[ $# -gt 0 ]]; then
  case "$1" in
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
fi

# --- Required tools ----------------------------------------------------------
for tool in flutter openssl sha256sum; do
  command -v "$tool" >/dev/null 2>&1 || die "$tool not found on PATH — required to build the dev test APK."
done

# --- Load optional gitignored .env.build-test --------------------------------
# KEY=VALUE lines only; the file is never evaluated (no arbitrary code). An
# environment variable that is already set (even to empty) wins over the file.
if [[ -f "${ENV_FILE}" ]]; then
  line=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"                     # strip CR (Windows line endings)
    [[ -z "${line}" || "${line}" == \#* ]] && continue
    if [[ "${line}" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
      key="${BASH_REMATCH[1]}"
      val="${BASH_REMATCH[2]}"
      if [[ "${val}" == \"*\" && ${#val} -ge 2 ]]; then
        val="${val:1:${#val}-2}"             # strip one layer of surrounding quotes
      fi
      # Skip keys already present in the environment (explicit env wins).
      [[ -n "${!key+x}" ]] && continue
      export "$key=$val"
    else
      echo "warn: ${ENV_FILE}: ignoring line '${line}' (expected KEY=VALUE)" >&2
    fi
  done < "${ENV_FILE}"
fi

# --- Built-in defaults -------------------------------------------------------
API_BASE="${API_BASE:-${DEFAULT_API_BASE}}"

# --- Preconditions (fail fast) -----------------------------------------------
require_nonempty() {
  local name hint
  name="$1"
  hint="$2"
  if [[ -z "${!name:-}" ]]; then
    die "${name} is empty — ${hint}" "Set it in ${ENV_FILE} or the calling environment (see --help)."
  fi
}
require_nonempty DEFAULT_SERIES_ID "an empty define dispatches a season-create with an empty series_id that surfaces only as a generic 422 at runtime (issue #467)"
require_nonempty DEV_AUTH_SUB "without it the app has no authenticated developer identity (backend dev-auth parity, ADR-018)"

# 3. Pinned-CA sanity (spec flutter-dev-ca). The dev flavor pins
#    assets/certs/dev/ca.pem as its EXCLUSIVE trust anchor: the committed
#    placeholder (CN=breakdown-dev-ca) must never reach a LAN/remote edge, the
#    file must exist, and it must parse as an X.509 certificate (the app fails
#    closed with TlsConfigError at bootstrap otherwise).
if [[ ! -f "${CA_PEM}" ]]; then
  die "${CA_PEM} not found — the dev flavor pins this CA exclusively (spec flutter-dev-ca); restore it," \
      "otherwise the app fails closed at bootstrap (TlsConfigError). See --help."
fi
# RFC2253 nameopt: deterministic, version-independent subject formatting. The
# default `oneline` format of `openssl x509 -subject` is locale/version
# dependent (some OpenSSL versions emit `CN = breakdown-dev-ca` with spaces
# around `=`), which would let the placeholder detection below fail to match.
# RFC2253 never inserts spaces around `=` and is stable across OpenSSL
# versions; the substring match is RDN-order independent.
CA_SUBJECT="$(openssl x509 -in "${CA_PEM}" -noout -subject -nameopt RFC2253 2>/dev/null || true)"
if [[ -z "${CA_SUBJECT}" ]]; then
  die "${CA_PEM} does not parse as an X.509 certificate (openssl x509 failed) — point it at a real CA PEM," \
      "not a placeholder or text file. See --help."
fi
if [[ "${CA_SUBJECT}" == *"CN=${PLACEHOLDER_CA_CN}"* ]]; then
  die "${CA_PEM} is still the committed placeholder (CN=${PLACEHOLDER_CA_CN})." \
      "The dev flavor pins this CA exclusively; a real device on a LAN/remote https edge needs a real CA" \
      "whose leaf cert covers the edge host/IP. Install a local LAN CA per the local-testing session notes," \
      "e.g. backend/dev-certs/lan/ca.crt -> ${CA_PEM} (leaf with the LAN IP in its SAN, see backend/dev-certs/lan/)." \
      "Docs: docs/release-process.md 'Local build notes'."
fi

# 4. API_BASE scheme/host policy hint (mirror of kDevCleartextHosts —
#    lib/data/settings/api_base_validation.dart). Non-fatal: the app's runtime
#    validation is the final gate.
AB_SCHEME="$(printf '%s' "${API_BASE}" | sed -E 's#^([A-Za-z][A-Za-z0-9+.-]*)://.*#\1#')"
AB_HOST="$(printf '%s' "${API_BASE}" | sed -E 's#^[A-Za-z][A-Za-z0-9+.-]*://([^/:?#]+).*#\1#' | tr 'A-Z' 'a-z')"
case "${AB_SCHEME}" in
  https)
    printf 'info : API_BASE %s (https) — OK\n' "${API_BASE}"
    ;;
  http)
    if [[ "${LOOPBACK_HOSTS}" == *" ${AB_HOST} "* ]]; then
      printf 'note : API_BASE %s is cleartext http to loopback/emulator host %s\n' "${API_BASE}" "${AB_HOST}"
      echo '       allowed per kDevCleartextHosts; fine for emulator runs, NOT for a real'
      echo '       device on a LAN/remote edge (use https + the LAN CA).'
    else
      printf 'warn : API_BASE %s is cleartext http to %s — the app runtime validation rejects it\n' "${API_BASE}" "${AB_HOST}"
      echo '       (settings.backend_uri_cleartext_rejected; CWE-319) and the transport'
      echo '       withholds the bearer token. Point a real device at the https edge.'
    fi
    ;;
  *)
    printf 'warn : API_BASE %s has no http(s) scheme — the app rejects such a base at bootstrap.\n' "${API_BASE}"
    ;;
esac

# 5. APP_VERSION marker — unambiguous per build (default '<version> · DEV-<n>').
#    <n> auto-increments above the highest DEV-<n> already stamped, so
#    re-running never reuses a marker.
n=1
mkdir -p "${TEST_APK_DIR}"
stamp=""
for stamp in "${TEST_APK_DIR}"/breakdown-dev-*; do
  [[ -e "${stamp}" ]] || continue
  if [[ "${stamp}" =~ DEV-([0-9]+)\.apk$ ]]; then
    cand=$((10#${BASH_REMATCH[1]}))
    if (( cand >= n )); then
      n=$((cand + 1))
    fi
  fi
done
if [[ -z "${APP_VERSION:-}" ]]; then
  PUBSPEC_VERSION="$(sed -n -E 's/^version:[[:space:]]*([^[:space:]]+).*/\1/p' pubspec.yaml | head -n 1)"
  if [[ -n "${PUBSPEC_VERSION}" ]]; then
    APP_VERSION="${PUBSPEC_VERSION} · DEV-${n}"
  else
    APP_VERSION="DEV-${n}"
  fi
fi
# Marker for the stamped filename: collapse every non [A-Za-z0-9._-] run to a
# single '-', strip leading/trailing '-'. '0.4.0+21 · DEV-3' -> '0.4.0+21-DEV-3'.
MARKER="$(printf '%s' "${APP_VERSION}" | sed -E 's/[^A-Za-z0-9._-]+/-/g; s/^-+//; s/-+$//')"
if [[ -z "${MARKER}" ]]; then
  die "APP_VERSION '${APP_VERSION}' sanitizes to an empty marker — set a non-empty APP_VERSION or unset it."
fi

# --- Build summary (safe fields only; these are not secrets) -----------------
echo "=== dev test-APK build (issue #475) ==="
echo "  flavor       : dev (debug-signed Gradle fallback — never publish)"
echo "  entrypoint   : ${ENTRYPOINT}"
echo "  API_BASE     : ${API_BASE}"
echo "  DEV_AUTH_SUB : ${DEV_AUTH_SUB}"
echo "  SERIES_ID    : ${DEFAULT_SERIES_ID}"
echo "  APP_VERSION  : ${APP_VERSION}"

# --- Build --------------------------------------------------------------------
flutter build apk --release --flavor dev -t "${ENTRYPOINT}" \
  --dart-define=API_BASE="${API_BASE}" \
  --dart-define=DEV_AUTH_SUB="${DEV_AUTH_SUB}" \
  --dart-define=DEFAULT_SERIES_ID="${DEFAULT_SERIES_ID}" \
  --dart-define=APP_VERSION="${APP_VERSION}"

# --- Verify, stamp, print sha256 ---------------------------------------------
APK="${APK_DIR}/${APK_NAME}"
if [[ ! -f "${APK}" ]]; then
  die "build produced no ${APK_NAME} under ${APK_DIR} — did 'flutter build apk --release --flavor dev' succeed?" \
      "Check the Gradle output directory and the raw commands above."
fi

STAMPED="${TEST_APK_DIR}/breakdown-dev-${MARKER}.apk"
cp "${APK}" "${STAMPED}"
SHA256="$(sha256sum "${STAMPED}" | cut -d' ' -f1)"

echo "=== done ==="
echo "  raw     : ${APK}"
echo "  stamped : ${STAMPED}"
echo "  sha256  : ${SHA256}"
echo
echo "Install on a device: adb install -r ${STAMPED}"
echo "Identify the build on-device: About dialog shows '${APP_VERSION}'."
