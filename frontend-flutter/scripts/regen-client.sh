#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: hy3 (opencode-go)
# Co-authored-by: qwen3.8-flash (opencode-go)

# Regenerate the typed, Dio-based Dart API client (`breakdown_api`) from
# `backend/openapi.yaml` into `vendor/breakdown_api/`.
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
# The generated package is a standalone Dart package with its own `lib/` and is
# consumed as a path dependency. It MUST NOT live inside `lib/` (e.g. the former
# `lib/api/generated/`, under the Flutter root's own `packageUri: lib/`): the
# kernel compiler (CFE) then attributes the package's `.g.dart` *part* files to
# the root package's language version (3.x) while resolving the library file via
# `package:breakdown_api` (2.18), so every library fails to compile with
# "The language version override has to be the same in the library and its
# part(s)". Keeping the package in a sibling `vendor/` tree removes the
# packageUri overlap so the whole package resolves at its own language version.
# The package name (`breakdown_api`) and its import path
# (`package:breakdown_api/breakdown_api.dart`) are unchanged.
OUT="vendor/breakdown_api"
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
  --additional-properties=pubName=breakdown_api,hideGenerationTimestamp=true \
  --reserved-words-mappings update=decisionUpdate

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

# Work around an openapi-generator 7.25.0 `dart-dio` template bug: for a
# `oneOf` whose branch is an *inline* `type: string` `enum` (utoipa emits this
# for the unit variant of an externally-tagged Rust enum, e.g.
# `ApplyMappingDecision::Create`, `ShootingDaySource::Manual`), the template
# references the branch type as `FullType(OneOf0Enum)` but never emits that
# enum's declaration, so the client does not compile ("Not a constant
# expression"). The generator's own doc comment for the field already names the
# branch `[String]`, so substituting `String` matches the generator's intent and
# the wire format (a bare JSON string). Applied to the library sources before
# `build_runner`; deterministic and idempotent (a no-op once upstream fixes it).
while IFS= read -r -d '' file; do
  if grep -q 'OneOf[0-9]*Enum' "${file}"; then
    sed -i -E 's/\bFullType\(OneOf[0-9]+Enum\)/FullType(String)/g' "${file}"
  fi
done < <(find "${OUT}" -name '*.dart' -print0)

# Pin build_runner to a deterministic version. The generated pubspec declares
# `build_runner: any`; pinning keeps the built_value codegen output
# reproducible for the CI OpenAPI drift check (which runs this same script into
# a throwaway and diffs against the committed tree).
sed -i.bak -E "s/^  build_runner: any$/  build_runner: '^2.7.0'/" "${OUT}/pubspec.yaml"
rm -f "${OUT}/pubspec.yaml.bak"

# Work around openapi-generator 7.25.0 / Dart SDK mismatches that make the
# generated client non-reproducible or non-compiling against current pub.dev:
#  * `source_gen` is pinned to 3.0.0: newer versions resolve to 3.1.0, whose
#    analyzer API is incompatible with this SDK (`getInvocation` undefined),
#    so `build_runner` codegen fails.
#  * `built_value` / `built_value_generator` are pinned to 8.11.x: the
#    `dart pub get` + `build_runner` codegen step below runs *standalone* inside
#    the generated package, so these are the versions that actually emit the
#    `.g.dart` files. The 7.25.0 template output pairs with the 8.11.x emitter
#    and `dart format` result; 8.12.x emits `@dart=` language-version headers
#    into the `.g.dart` parts that then mismatch the library file. NOTE: the
#    `update`-field/`Builder.update` collision that these pins are sometimes
#    said to fix is NOT version-dependent -- both 8.11.2 and 8.12.7 declare
#    `Builder.update`; it is handled above via `--reserved-words-mappings`.
# The whole `dependency_overrides` block is normalized to the pinned set so
# the pins are always present and deterministic (idempotent across re-runs and
# regardless of whether the generator emits the block itself).
OUT="${OUT}" python3 - <<'PY'
import os, pathlib
p = pathlib.Path(os.environ["OUT"]) / "pubspec.yaml"
text = p.read_text()
lines = text.splitlines(keepends=True)
new_lines = []
i = 0
while i < len(lines):
    if lines[i].strip() == "dependency_overrides:":
        i += 1
        # Drop the indented continuation lines of the old block.
        while i < len(lines) and (lines[i].startswith("  ") or lines[i].strip() == ""):
            i += 1
        continue
    new_lines.append(lines[i])
    i += 1
text = "".join(new_lines)
if not text.endswith("\n"):
    text += "\n"
text += "\ndependency_overrides:\n"
text += "  source_gen: 3.0.0\n"
text += "  built_value: 8.11.2\n"
text += "  built_value_generator: 8.11.1\n"
p.write_text(text)
PY

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
