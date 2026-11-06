#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: deepseek-v4.1-flash (opencode-go)
# test-patch-cbmem-extension.sh - Guard test for patch-cbmem-extension.sh.
#
# Runs the patcher against a FIXTURE agent dir (PI_CODING_AGENT_DIR), so the
# real generated extension is never touched. Asserts the four properties the
# patcher promises: the patch applies, it is idempotent, `delete_project` keeps
# its required argument (schema AND allowlist), and an unknown generated format
# is refused with exit 2 instead of being silently half-patched.
#
# Needs bash + python3 only. The one assertion that parses the patched file
# (`node --check`, TypeScript-aware from Node 22) is SKIPPED with a notice on an
# older runtime, so this test stays runnable in CI without a toolchain download.
#
# Usage: ./test-patch-cbmem-extension.sh
# Exit status: 0 when all assertions hold, 1 otherwise.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCHER="$SCRIPT_DIR/patch-cbmem-extension.sh"
FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT

failures=0
fail() {
    echo "❌ FAIL: $1" >&2
    failures=$((failures + 1))
}
pass() {
    echo "✅ PASS: $1"
}

# A minimal stand-in for the generated extension: the real anchors, two
# project-scoped tools, one destructive tool, and one tool whose project-like
# argument must NOT be rewritten (`base_project`).
make_fixture() {
    mkdir -p "$FIXTURE/agent/extensions"
    cat >"$FIXTURE/agent/extensions/cbmem.ts" <<'TS'
import { spawn } from 'node:child_process';
import { Type } from 'typebox';

async function call(tool, args, signal) {
  return new Promise((resolve) => {
    resolve({ ok: true });
  });
}

export default function (pi) {
  pi.registerTool({
    name: 'search_graph',
    label: 'search_graph',
    parameters: Type.Object({
      project: Type.String(),
      query: Type.Optional(Type.String())
    }),
    execute: async (toolCallId, params, signal, _onUpdate, ctx) => {
      return await call('search_graph', params, signal);
    },
  });
  pi.registerTool({
    name: 'delete_project',
    label: 'delete_project',
    parameters: Type.Object({
      project: Type.String()
    }),
    execute: async (toolCallId, params, signal, _onUpdate, ctx) => {
      return await call('delete_project', params, signal);
    },
  });
  pi.registerTool({
    name: 'compare_graphs',
    label: 'compare_graphs',
    parameters: Type.Object({
      base_project: Type.String(),
      target_project: Type.String()
    }),
    execute: async (toolCallId, params, signal, _onUpdate, ctx) => {
      return await call('compare_graphs', params, signal);
    },
  });
}
TS
}

# --- 1. --check reports "not patched" on a fresh generated file --------------
make_fixture
out=$(PI_CODING_AGENT_DIR="$FIXTURE/agent" "$PATCHER" --check 2>&1)
rc=$?
if [ "$rc" = "1" ]; then
    pass "--check exits 1 on an unpatched file"
else
    fail "--check exit was $rc, want 1 ($out)"
fi

# --- 2. --dry-run changes nothing -------------------------------------------
before=$(cksum <"$FIXTURE/agent/extensions/cbmem.ts")
out=$(PI_CODING_AGENT_DIR="$FIXTURE/agent" "$PATCHER" --dry-run 2>&1)
rc=$?
after=$(cksum <"$FIXTURE/agent/extensions/cbmem.ts")
if [ "$rc" = "0" ] && [ "$before" = "$after" ]; then
    pass "--dry-run exits 0 and leaves the file untouched"
else
    fail "--dry-run rc=$rc, file changed=$([ "$before" = "$after" ] && echo no || echo yes)"
fi

# --- 3. the patch applies, and the result parses ----------------------------
out=$(PI_CODING_AGENT_DIR="$FIXTURE/agent" "$PATCHER" 2>&1)
rc=$?
if [ "$rc" = "0" ]; then
    pass "patch applies (exit 0)"
else
    fail "patch exit was $rc: $out"
fi
patched="$FIXTURE/agent/extensions/cbmem.ts"
if grep -q 'project: projectArg()' "$patched" &&
    ! sed -n "/name: 'search_graph'/,/execute/p" "$patched" | grep -qE '^[[:space:]]*project: Type\.String\(\)';
 then
    pass "a non-destructive 'project' schema became optional"
else
    fail "a non-destructive 'project' schema is still required"
fi
node_major=$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || true)
if [ "${node_major:-0}" -ge 22 ] 2>/dev/null; then
    if node --check "$patched" >/dev/null 2>&1; then
        pass "patched file is syntactically valid TS"
    else
        fail "patched file does not parse (node --check)"
    fi
else
    echo "⏭  SKIP: patched-file parse check needs node ≥ 22 (found ${node_major:-none})"
fi

# --- 4. destructive and project-LIKE arguments are left alone ---------------
if grep -q 'base_project: Type.String()' "$patched" &&
    grep -q 'target_project: Type.String()' "$patched"; then
    pass "base_project/target_project keep their required schemas"
else
    fail "the patcher rewrote a project-like argument it does not own"
fi
if sed -n "/name: 'delete_project'/,/execute/p" "$patched" | grep -qE '^[[:space:]]*project: Type\.String\(\)'; then
    pass "delete_project keeps its REQUIRED schema"
else
    fail "delete_project's schema was loosened but it is never defaulted (the schema would lie)"
fi
if ! sed -n "/const PROJECT_TOOLS/,/^]);/p" "$patched" | grep -q "'delete_project'"; then
    pass "delete_project is not in the project-default allowlist"
else
    fail "delete_project is in the project-default allowlist"
fi

# --- 5. idempotent: a second run is a no-op ---------------------------------
before=$(cksum <"$patched")
out=$(PI_CODING_AGENT_DIR="$FIXTURE/agent" "$PATCHER" 2>&1)
rc=$?
after=$(cksum <"$patched")
if [ "$rc" = "0" ] && [ "$before" = "$after" ] && [ "$out" = "already patched: $patched" ]; then
    pass "second run is a no-op (idempotent)"
else
    fail "second run rc=$rc changed=$([ "$before" = "$after" ] && echo no || echo yes) out=$out"
fi

# --- 6. an unknown generated format is REFUSED, not half-patched ------------
mkdir -p "$FIXTURE/weird/extensions"
printf 'export default function (pi) { pi.registerTool({ name: "x" }); }\n' \
    >"$FIXTURE/weird/extensions/cbmem.ts"
before=$(cksum <"$FIXTURE/weird/extensions/cbmem.ts")
out=$(PI_CODING_AGENT_DIR="$FIXTURE/weird" "$PATCHER" 2>&1)
rc=$?
after=$(cksum <"$FIXTURE/weird/extensions/cbmem.ts")
if [ "$rc" = "2" ] && [ "$before" = "$after" ]; then
    pass "unknown format exits 2 and leaves the file alone"
else
    fail "unknown format rc=$rc (want 2) changed=$([ "$before" = "$after" ] && echo no || echo yes)"
fi

# --- 7. a missing generated file is reported as such ------------------------
mkdir -p "$FIXTURE/empty"
out=$(PI_CODING_AGENT_DIR="$FIXTURE/empty" "$PATCHER" 2>&1)
rc=$?
if [ "$rc" = "2" ] && printf '%s' "$out" | grep -q 'no generated extension'; then
    pass "missing cbmem.ts is reported, not silently skipped"
else
    fail "missing cbmem.ts rc=$rc out=$out"
fi

echo
if [ "$failures" = "0" ]; then
    echo "all assertions passed"
    exit 0
fi
echo "$failures assertion(s) failed"
exit 1
