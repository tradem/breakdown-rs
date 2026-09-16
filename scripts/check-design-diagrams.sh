#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: omen-alpha (opencode-go)
#
# check-design-diagrams.sh — validate every fenced PlantUML block in the
# design documentation.
#
# Extracts fenced ```plantuml blocks from all Markdown files under
# docs/design/, writes each block to a temp file and runs
# `plantuml -checkonly` on it. Exits non-zero on the first failure,
# printing the source file, line number, and PlantUML error output.
#
# Usage:
#   scripts/check-design-diagrams.sh                 # check docs/design/**/*.md
#   scripts/check-design-diagrams.sh FILE [FILE...]  # check specific files
#
# Environment:
#   PLANTUML_JAR   path to an existing plantuml.jar to use directly
#                  (skips download/verification)
#   CI_CACHE_DIR   cache directory for the downloaded jar
#                  (default: "$PWD/.cache" locally; CI sets its own)
#
# PlantUML jar provisioning (CI hardening: pinned version + SHA-256
# checksum verification, no curl|bash):
#   version : 1.2026.6  (matches the digest-pinned docker image in
#                         .github/workflows/docs.yml)
#   url     : https://github.com/plantuml/plantuml/releases/download/v1.2026.6/plantuml-1.2026.6.jar
#   sha256  : 89948f14c93756c7a3fb7b69078ff37e8489fd79dd430c582b931e2f65358690

set -euo pipefail

PLANTUML_VERSION="1.2026.6"
PLANTUML_SHA256="89948f14c93756c7a3fb7b69078ff37e8489fd79dd430c582b931e2f65358690"
PLANTUML_URL="https://github.com/plantuml/plantuml/releases/download/v${PLANTUML_VERSION}/plantuml-${PLANTUML_VERSION}.jar"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SCAN_DIR="${REPO_ROOT}/docs/design"
CACHE_DIR="${CI_CACHE_DIR:-${REPO_ROOT}/.cache}"

# --- resolve plantuml runner -------------------------------------------------
if [[ -n "${PLANTUML_JAR:-}" ]]; then
  if [[ ! -f "${PLANTUML_JAR}" ]]; then
    echo "error: PLANTUML_JAR=${PLANTUML_JAR} does not exist" >&2
    exit 2
  fi
  JAR="${PLANTUML_JAR}"
else
  mkdir -p "${CACHE_DIR}"
  JAR="${CACHE_DIR}/plantuml-${PLANTUML_VERSION}.jar"
  if [[ ! -f "${JAR}" ]]; then
    echo "Downloading PlantUML ${PLANTUML_VERSION} jar (SHA-256 verified)..."
    tmp="$(mktemp)"
    trap 'rm -f "${tmp}"' EXIT
    curl -sSfL --retry 2 -o "${tmp}" "${PLANTUML_URL}"
    echo "${PLANTUML_SHA256}  ${tmp}" | sha256sum -c --strict - >/dev/null
    mv "${tmp}" "${JAR}"
    trap - EXIT
  fi
fi

run_checkonly() {
  java -jar "${JAR}" -checkonly "$@"
}

# --- collect markdown files ---------------------------------------------------
files=()
if [[ $# -gt 0 ]]; then
  files=("$@")
else
  while IFS= read -r -d '' f; do
    files+=("${f}")
  done < <(find "${SCAN_DIR}" -type f -name '*.md' -print0 | sort -z)
fi

if [[ ${#files[@]} -eq 0 ]]; then
  echo "No markdown files found under ${SCAN_DIR}; nothing to check."
  exit 0
fi

# --- extract fenced plantuml blocks --------------------------------------------
# Block grammar: a fence opening line matching ^```plantuml\s*$ (allowing
# leading indentation), closed by the next fence line matching ^```\s*$.
tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

extract_blocks() {
  # $1 = markdown file; writes each block to $tmpdir/<n>.puml, records
  # "startline" per block index in $tmpdir/<n>.line
  local file="$1" in_block=0 idx=0 startline=0 lineno=0
  while IFS= read -r line; do
    lineno=$((lineno + 1))
    if [[ ${in_block} -eq 0 && "${line}" =~ ^[[:space:]]*\`\`\`plantuml[[:space:]]*$ ]]; then
      in_block=1
      idx=$((idx + 1))
      startline=${lineno}
      : > "${tmpdir}/${idx}.puml"
    elif [[ ${in_block} -eq 1 && "${line}" =~ ^[[:space:]]*\`\`\`[[:space:]]*$ ]]; then
      in_block=0
      echo "${startline}" > "${tmpdir}/${idx}.line"
    elif [[ ${in_block} -eq 1 ]]; then
      printf '%s\n' "${line}" >> "${tmpdir}/${idx}.puml"
    fi
  done < "${file}"
  if [[ ${in_block} -eq 1 ]]; then
    echo "error: ${file}: unterminated \`\`\`plantuml fence (opened at line ${startline})" >&2
    exit 1
  fi
  echo ${idx}
}

failures=0
blocks_total=0
for file in "${files[@]}"; do
  [[ -f "${file}" ]] || { echo "error: file not found: ${file}" >&2; exit 2; }
  count="$(extract_blocks "${file}")"
  blocks_total=$((blocks_total + count))
  for ((i = 1; i <= count; i++)); do
    startline="$(cat "${tmpdir}/${i}.line")"
    if ! err="$(run_checkonly "${tmpdir}/${i}.puml" 2>&1)"; then
      failures=$((failures + 1))
      echo "FAIL: ${file}:${startline}: PlantUML block does not compile" >&2
      echo "${err}" >&2
    fi
  done
done

echo "Checked ${blocks_total} PlantUML block(s) in ${#files[@]} file(s)."
if [[ ${failures} -gt 0 ]]; then
  echo "${failures} block(s) failed -checkonly validation." >&2
  exit 1
fi
echo "OK: all PlantUML blocks compile."
