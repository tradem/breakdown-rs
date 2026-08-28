#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: hy3 (opencode-go)

# Regenerate the typed, Dio-based Dart API client (`breakdown_api`) from
# `backend/openapi.yaml` into `lib/api/generated/`.
#
# This script is the SINGLE source of truth for client generation. It is run
# both locally and in CI (the OpenAPI drift check invokes it), so the result
# is reproducible and diff-stable. The generator version is pinned in the
# committed `openapitools.json` — never pass a different version on the CLI.
#
# The generated client uses the `dart-dio` OpenAPI generator (Dio HTTP client,
# built_value serialization). Because built_value requires codegen, this script
# also runs `build_runner` inside the generated package to produce the
# `.g.dart` files, then formats the result.
#
# NOTE: openapi-generator 7.25.0 (the latest release) generates a
# `source_gen` constraint that resolves to 3.1.0, which is incompatible with
# the Dart 3.13.x analyzer API (`getInvocation` is undefined there). We pin
# `source_gen` to 3.0.0 via a `dependency_overrides` block injected below so
# `build_runner` succeeds. This is a generator/SDK mismatch, not a project bug;
# revisit if the generator is ever upgraded past 7.25.0.
#
# Invariant for the CI drift check (OpenSpec `wire-openapi-dart-client`
# task 4): the generated tree committed to the repo MUST be byte-identical to
# what this script produces on a clean checkout. To keep diffs stable across
# runs, generation timestamps are stripped, `build_runner` is pinned, and a
# `// GENERATED — do not edit` banner is injected by this script.
#
# The script resolves the frontend-flutter root from its own location, so it
# works regardless of the caller's working directory.

set -euo pipefail

# Resolve the frontend-flutter root from this script's location, then cd there.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRONTEND_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${FRONTEND_ROOT}"

SPEC="../backend/openapi.yaml"
OUT="lib/api/generated"
BANNER="// GENERATED — do not edit. Regenerate with \`scripts/regen-client.sh\`."

if [[ ! -f "${SPEC}" ]]; then
  echo "error: spec not found at ${SPEC} (resolved from ${FRONTEND_ROOT})" >&2
  exit 1
fi

GENERATOR_VERSION="$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' openapitools.json | sed -E 's/.*"([^"]*)"$/\1/')"
echo "Regenerating Dart client"
echo "  spec : ${SPEC}"
echo "  out  : ${OUT}"
echo "  gen  : openapi-generator-cli (JAR ${GENERATOR_VERSION} from openapitools.json)"

# Clean the previous output so removed operations/models disappear from the tree.
rm -rf "${OUT}"

# Use the unpinned npm launcher (latest). It reads the generator JAR version
# from openapitools.json (generator-cli.version) and downloads that JAR.
# NOTE: do NOT pin the npm package version here — npm and JAR versions
# follow different schemes, and pinning the wrong npm version breaks npx.
npx --yes @openapitools/openapi-generator-cli generate \
  -i "${SPEC}" \
  -g dart-dio \
  -o "${OUT}" \
  --skip-validate-spec \
  --additional-properties=pubName=breakdown_api,hideGenerationTimestamp=true

# Inject the `do not edit` banner into every generated Dart file (idempotent).
# Skips files that already carry the banner so the pipeline stays deterministic.
while IFS= read -r -d '' file; do
  if ! head -n 1 "${file}" | grep -q "GENERATED — do not edit"; then
    tmp="$(mktemp)"
    printf '%s\n\n' "${BANNER}" > "${tmp}"
    cat "${file}" >> "${tmp}"
    mv "${tmp}" "${file}"
  fi
done < <(find "${OUT}" -name '*.dart' -print0)

# Pin build_runner to a deterministic version. The generated pubspec declares
# `build_runner: any`; pinning keeps the built_value codegen output
# reproducible for the CI OpenAPI drift check (which runs this same script into
# a throwaway and diffs against the committed tree).
sed -i.bak -E "s/^  build_runner: any$/  build_runner: '^2.7.0'/" "${OUT}/pubspec.yaml"
rm -f "${OUT}/pubspec.yaml.bak"

# Work around an openapi-generator 7.25.0 / Dart 3.13.x mismatch: the generated
# `source_gen` constraint resolves to 3.1.0, whose analyzer usage is
# incompatible with this SDK (`getInvocation` undefined). Pin source_gen to a
# compatible 3.0.0 via dependency_overrides so `build_runner` codegen succeeds.
if ! grep -q "dependency_overrides" "${OUT}/pubspec.yaml"; then
  printf '\ndependency_overrides:\n  source_gen: 3.0.0\n' >> "${OUT}/pubspec.yaml"
fi

# The Dart-Dio client relies on built_value codegen (`.g.dart`). It is a
# standalone package, so run the codegen inside it.
( cd "${OUT}" && dart pub get && dart run build_runner build --delete-conflicting-outputs )
# Format the generated + codegen output with the package's own language-version
# context so the result is stable and CI's `dart format --set-exit-if-changed`
# passes.
( cd "${OUT}" && dart format lib )

# Drop standalone-package artifacts we do not ship, but KEEP the package itself
# (pubspec.yaml + lib/ + build.yaml) so it is consumed as a real path dependency
# named `breakdown_api` (per AGENTS.md §2). The CI drift check runs this same
# script, so the committed tree MUST be byte-identical to its output.
rm -rf "${OUT}/test" "${OUT}/doc" "${OUT}/.openapi-generator" \
       "${OUT}/.openapi-generator-ignore" "${OUT}/.gitignore" \
       "${OUT}/.travis.yml" "${OUT}/git_push.sh" "${OUT}/README.md" \
       "${OUT}/analysis_options.yaml"

echo "Done. Regenerated client is in ${OUT}"
