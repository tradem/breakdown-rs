#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: deepseek-v4.1-flash (opencode-go)
#
# patch-cbmem-extension.sh — make `project` OPTIONAL in the generated
# codebase-memory pi extension, defaulting to the indexed project that contains
# the session cwd.
#
# Why this exists: `codebase-memory-mcp` generates
# `$AGENT_DIR/extensions/cbmem.ts` from its own MCP tool registry, and every
# tool that takes a project declares `project: Type.String()` — REQUIRED. pi
# validates arguments before `tool_call` fires, so no extension-side hook can
# fill the value in: the model must know the literal project name at call time,
# or the call never happens. Measured against this repo: `search_graph` was
# called 14 times in 538 sessions, while ast-bro's `analyze_ast_search` — same
# job, no required argument — was called 305 times. One mandatory argument is
# one reason to reach for `rg` instead (AGENTS.md §2).
#
# After this patch the argument is optional and the CLI receives the project
# the extension resolved from the session cwd: it walks up from the cwd to the
# nearest `.codebase-memory/artifact.json` and reads its `project` field. That
# file is written by the indexer next to the index itself (per worktree, see
# AGENTS.md §2), so the answer is free — no `list_projects` round trip, no
# parsing of human-formatted output. Passing `project` explicitly still wins.
# `delete_project` is deliberately untouched — no allowlist entry AND no schema
# change — because a destructive call must name its target.
#
# The file is GENERATED and rewritten on every codebase-memory-mcp install or
# update, so this patch is re-applied by `scripts/install-pi-extensions.sh`
# instead of being a one-off edit. Re-running the script is a no-op.
#
# Usage:
#   scripts/patch-cbmem-extension.sh              # apply (idempotent)
#   scripts/patch-cbmem-extension.sh --check      # exit 0 patched, 1 not, 2 unsupported
#   scripts/patch-cbmem-extension.sh --dry-run    # report what would change
#
# Exit codes: 0 patched/applied, 1 not patched (--check), 2 anchor missing (the
# generated format changed — the patch would be a lie, so it refuses).
#
# Env:
#   PI_CODING_AGENT_DIR   agent dir (default: ~/.pi/agent)

set -uo pipefail

AGENT_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
TARGET="$AGENT_DIR/extensions/cbmem.ts"

MODE="apply"
for arg in "$@"; do
    case "$arg" in
        --check) MODE="check" ;;
        --dry-run) MODE="dry-run" ;;
        -h | --help)
            sed -n '2,43p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "patch-cbmem-extension.sh: unknown argument: $arg" >&2
            echo "Try --help." >&2
            exit 64
            ;;
    esac
done

if [ ! -f "$TARGET" ]; then
    echo "patch-cbmem-extension.sh: no generated extension at $TARGET" >&2
    echo "Install codebase-memory-mcp for pi first (it writes that file)." >&2
    exit 2
fi

MODE="$MODE" TARGET="$TARGET" python3 - <<'PY'
import os
import re
import sys

mode = os.environ["MODE"]
target = os.environ["TARGET"]

MARKER = "// breakdown-rs: project default (scripts/patch-cbmem-extension.sh)"
CALL_ANCHOR = "async function call(tool, args, signal) {"
SCHEMA_RE = re.compile(r"(?<![\w.$])project: Type\.String\(\)")

# Destructive: a delete must name its target, never inherit a guess.
NO_DEFAULT = {"delete_project"}

# The injected TypeScript, kept as a plain string so its braces need no escaping.
HELPERS = r"""// breakdown-rs: project default (scripts/patch-cbmem-extension.sh)
// `codebase-memory-mcp` generates this file and declares `project` as required
// on every project-scoped tool. pi validates arguments BEFORE any `tool_call`
// hook runs, so the value cannot be supplied by an extension-side hook — it is
// made optional here and resolved from the session cwd instead.
const PROJECT_TOOLS = new Set([
__PROJECT_TOOLS__
]);

/** `project` for every scoped tool: optional, resolved from the session cwd. */
function projectArg() {
  return Type.Optional(Type.String({
    description: 'Indexed project name. Omit it: the project containing the session cwd is used.',
  }));
}

let __cbmProjectCache = { at: 0, value: null };

/**
 * The indexed project for the session cwd: the `project` field of the nearest
 * `.codebase-memory/artifact.json` walking UP from the cwd. The indexer writes
 * that file beside the index (per worktree), so a session below the monorepo
 * root resolves the same project a root session does. `null` means "do not
 * guess": the caller reports it instead of querying the wrong index.
 */
async function defaultProject() {
  if (Date.now() - __cbmProjectCache.at < 60000) return __cbmProjectCache.value;
  let value = null;
  try {
    const fs = await import('node:fs');
    const path = await import('node:path');
    let dir = process.cwd();
    for (let depth = 0; depth < 40; depth++) {
      const artifact = path.join(dir, '.codebase-memory', 'artifact.json');
      if (fs.existsSync(artifact)) {
        const parsed = JSON.parse(fs.readFileSync(artifact, 'utf8'));
        if (typeof parsed?.project === 'string' && parsed.project.length > 0) {
          value = parsed.project;
        }
        break;
      }
      const parent = path.dirname(dir);
      if (parent === dir) break;
      dir = parent;
    }
  } catch {
    value = null;
  }
  __cbmProjectCache = { at: Date.now(), value };
  return value;
}

"""

GUARD = r"""  if (PROJECT_TOOLS.has(tool) && !(args && typeof args.project === 'string' && args.project.length > 0)) {
    const resolved = await defaultProject();
    if (!resolved) {
      return {
        error: `codebase-memory: no .codebase-memory/artifact.json above ${process.cwd()}; pass "project" explicitly (list_projects shows the names).`,
      };
    }
    args = { ...(args ?? {}), project: resolved };
  }
"""

source = open(target, encoding="utf-8").read()

if MARKER in source:
    print("already patched: " + target)
    sys.exit(0)

# --- preconditions ---------------------------------------------------------
if CALL_ANCHOR not in source:
    print("unsupported: anchor '" + CALL_ANCHOR + "' not found in " + target, file=sys.stderr)
    print("The generated extension format changed; review scripts/patch-cbmem-extension.sh.", file=sys.stderr)
    sys.exit(2)

schema_matches = len(SCHEMA_RE.findall(source))
if schema_matches == 0:
    print("unsupported: no 'project: Type.String()' schema found in " + target, file=sys.stderr)
    sys.exit(2)

# Which tools actually take a single `project`? Derived from the file itself, so
# the allowlist cannot drift from the registry it patches.
project_tools = sorted(
    match.group(1)
    for block in re.split(r"pi\.registerTool\(\{", source)[1:]
    for match in [re.search(r"name:\s*'([^']+)'", block)]
    if match and SCHEMA_RE.search(block) and match.group(1) not in NO_DEFAULT
)
if not project_tools:
    print("unsupported: could not derive the tool allowlist from " + target, file=sys.stderr)
    sys.exit(2)

if mode == "check":
    print("not patched: " + target + " (" + str(schema_matches) + " required 'project' schemas)")
    sys.exit(1)

if mode == "dry-run":
    print("would patch " + target + ":")
    print("  " + str(schema_matches - len(NO_DEFAULT)) + " 'project' schemas -> optional")
    print("  project default injected into call(), allowlist (" + str(len(project_tools)) + "): " + ", ".join(project_tools))
    print("  untouched (still required): " + ", ".join(sorted(NO_DEFAULT)))
    sys.exit(0)

# --- the patch -------------------------------------------------------------
allowlist = "\n".join("  '" + name + "'," for name in project_tools)
helpers = HELPERS.replace("__PROJECT_TOOLS__", allowlist)
injection = helpers + CALL_ANCHOR + "\n" + GUARD

patched = source.replace(CALL_ANCHOR, injection, 1)

# The schema rewrite runs PER TOOL BLOCK, so a destructive tool keeps a required
# argument in its schema. Loosening it there while refusing to default it would
# advertise an omission that still fails — a schema that lies is worse than a
# blunt one.
chunks = re.split(r"(?=pi\.registerTool\(\{)", patched)
rewritten = 0
kept: list[str] = []
for index, chunk in enumerate(chunks):
    name_match = re.search(r"name:\s*'([^']+)'", chunk)
    name = name_match.group(1) if name_match else None
    if index == 0 or name in NO_DEFAULT:
        if index > 0:
            kept.append(str(name))
        chunks[index] = chunk
        continue
    chunks[index], count = SCHEMA_RE.subn("project: projectArg()", chunk)
    rewritten += count
patched = "".join(chunks)

# Verify the patch landed as intended before writing: a half-applied edit to a
# generated file is worse than no edit (every graph call would fail at runtime).
if MARKER not in patched or CALL_ANCHOR not in patched:
    print("failed: patch did not apply cleanly (no anchor in result)", file=sys.stderr)
    sys.exit(2)
if rewritten != len(project_tools):
    print(
        "failed: rewrote " + str(rewritten) + " schemas for " + str(len(project_tools)) + " allowlisted tools",
        file=sys.stderr,
    )
    sys.exit(2)
if "projectArg()" not in patched or "defaultProject()" not in patched:
    print("failed: patch result is missing its own parts", file=sys.stderr)
    sys.exit(2)

with open(target, "w", encoding="utf-8") as handle:
    handle.write(patched)

print("patched " + target)
print("  " + str(rewritten) + " 'project' schemas -> optional")
print("  cwd default injected; untouched (still required): " + ", ".join(sorted(NO_DEFAULT)))
PY
