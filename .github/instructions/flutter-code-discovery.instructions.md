---
description: Code discovery for the Flutter app - graph-first lookup with the codebase-memory knowledge graph, tool precedence (graph vs ast-bro vs grep), index freshness, and the pitfalls candidates must know before trusting a result.
applyTo:
  - "frontend-flutter/lib/**/*.dart"
  - "frontend-flutter/test/**/*.dart"
  - "frontend-flutter/integration_test/**/*.dart"
  - "frontend-flutter/tool/**/*.dart"
  - "frontend-flutter/features-spec/**/*.feature"
---

<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# Code discovery in `frontend-flutter/` (graph-first)

Normative rule lives in `frontend-flutter/AGENTS.md` (callout before §1) and in
the monorepo `AGENTS.md` §2 ("Code discovery"). This file is the how-to.

## 1. The graph covers Dart — "it doesn't work for Dart" is false

The indexed project is **`breakdown-rs`** (root: the monorepo root, *not*
`frontend-flutter/`). Measured coverage of the Dart tree:

- ~500 Dart files indexed (≈3.7k methods, ≈1.5k classes, ≈6.5k call edges).
- `frontend-flutter/vendor/breakdown_api/**` is **not** indexed. It is *tracked*
  (395 committed files, the OpenAPI drift gate depends on them), but the indexer
  prunes `vendor` by default — `index_status` lists `frontend-flutter/vendor`
  under `excluded.dirs`. Read those files directly; no reindex will ever return
  their symbols.
  the generated OpenAPI client never pollutes a lookup. Good.
- `**.g.dart` (Drift/Riverpod/freezed/json_serializable output) **is** indexed
  because it is committed — roughly a fifth of the Flutter nodes live there.
  When a hit points into a `.g.dart`, read the hand-written source it came from
  instead; never cite or edit generated code.

## 2. Tool precedence (no ambiguity, this is the rule)

**Decide by the shape of the question, not by speed:** *text search answers
whether a string OCCURS; code-aware search answers what the code DOES.* A
definition, a call site, an import and a doc-comment mention are the same
characters to `rg` — it cannot tell them apart, cannot report edge kinds and
cannot report completeness. Text search is therefore the CORRECT tool for pure
text (ARB keys, problem `code`s, config values, prose) and the WRONG one for
meaning (who defines/uses X, what breaks). When a text search does hit a
symbol-shaped token, `.pi/extensions/graph-first-nudge.ts` appends the
code-aware answer to the same result — a soft advisory, never a block.

| Question | Tool |
|---|---|
| "How does X work?", "what does this file contain?" | `get_code_snippet` / `get_file_outline`, else `analyze_ast_context` |
| "Who calls X?", "what breaks if I change/rename X?" | `trace_path` (inbound/outbound), else `analyze_ast_impact` |
| "Where is X / find the symbol named …" | `search_graph` (`name_pattern`), ast-bro `analyze_ast_search` as second opinion |
| "How does module A relate to B?", "architecture" | `get_architecture`, else `analyze_ast_graph` |
| Non-trivial multi-hop aggregation | `query_graph` (Cypher) |
| Projection-DTO ↔ screen wiring, "what did my branch touch" | `detect_changes` |
| **"Who observes this Riverpod provider?"** (`ref.watch` is not a graph edge) | `scripts/who-watches.sh <provider>` — the graph definition plus the subscribing call sites (`ref.watch` / `ref.listen`); `ref.read` sites are listed separately because they do not subscribe |
| **String literal, error/problem `code`, ARB key, config value, CWG text, YAML** | `grep` / `rg` — the graph indexes symbols, not literals |
| Generated output, `.g.dart`, `vendor/**` contents | `read`, never a graph claim |

`search_graph` argument syntax (verified — it is easy to get wrong):
`name_pattern` is a **regex** (`.*AiImportJobs.*`), `file_pattern` is a
**glob** (`frontend-flutter/**`, `*ai_import*controller.dart`). A regex in
`file_pattern` (`frontend-flutter/.*`) silently matches nothing and looks
exactly like a stale index.

Do **not** open with `grep` for a symbol question and do **not** open with the
graph for a literal question. Both directions are common failure modes: grep
cannot resolve same-named Dart methods across features, and the graph cannot
find `'season.archived'` in an ARB file.

## 3. Freshness — check before you trust, refresh when stale

The index is machine-local and gitignored (`.codebase-memory/`), so **CI can
never keep it fresh** and `index_status` may report `watch: watched=false`
(auto-sync only covers the MCP session's own project; a session launched in
`frontend-flutter/` or `backend/` does not qualify — the index root is the
monorepo root).

```bash
root=$(git rev-parse --show-toplevel)        # the scripts are monorepo-root assets
bash "$root/scripts/check-graph-freshness.sh"       # report: fresh / stale / no index
bash "$root/scripts/reindex-graph.sh" --if-stale    # refresh only when stale
bash "$root/scripts/reindex-graph.sh" --mode moderate  # faster, filtered + semantic
```

"Stale" covers two cases: the index lags HEAD, **and** the working tree holds
code files newer than the index (`indexed_at`). The second one matters because
the indexer reads the working tree, not a commit — a symbol you just added is
invisible until a reindex even though the commit matches.

Git hooks `post-merge` / `post-checkout` / `post-rewrite` (in
`backend/git-hooks/`) run `reindex-graph.sh --if-stale --background` only
**after activation**, once per clone: either run
`scripts/install-git-hooks.sh` (links them into the git hooks directory) or set
`core.hooksPath` to `backend/git-hooks`. Without one of those, nothing refreshes
the index automatically. Opt out with `CODEBASE_MEMORY_SKIP_AUTOINDEX=1`.

`post-rewrite` exists because `post-merge` covers merges only: `git pull
--rebase`, `git rebase` and `git commit --amend` move HEAD without running it.

Rules of thumb:

- An empty `search_graph` result for code you can see on disk means **stale
  index**, not "the tool is broken". Run the freshness check, then reindex.
  Exception: `frontend-flutter/vendor/**` is never indexed (see §1) — read those
  files instead of concluding the index is stale.
- An `index_status` `status: failed`/`parse_partial` note is a coverage gap, not
  proof of absence. For a negative claim ("nothing calls X", "X does not
  exist"), confirm with `check_index_coverage` (pass every evidence path) and
  fall back to `rg` for the listed ranges.
- After a branch switch the graph may describe the previous branch — reindex
  before writing an impact analysis into an OpenSpec artifact or PR body.

## 4. What the graph is used for in Flutter work

- **Drift check first** (`flutter-issue-implementation/SKILL.md` step 2): before
  planning an issue, confirm what already exists for the aggregate/screen —
  graph lookup, then `analyze_ast_context` / `read` for the exact body.
- **Blast radius before edits**: `trace_path` inbound on the controller,
  repository or provider you are about to change — Riverpod indirection makes
  textual callers look sparse even when 30 widgets watch the provider.
- **AUTHZ-GATE audits**: enumerate the handler-internal-authz paths that call a
  repository method (`trace_path` outbound) instead of trusting a `grep
  AUTHZ-GATE` count alone (the comment is prose, the graph sees the call).
- **Onboarding a feature folder**: `get_architecture` scoped to
  `frontend-flutter/lib/features/<area>` before reading files one by one.

## 5. Honest limits

- Dart resolution is tree-sitter-level, not the analyzer: dynamic dispatch via
  `Provider`/`ref.watch`, extension methods and code-generated mixins can hide
  an edge. Treat a `trace_path` result as *candidate* edges; the analyzer
  (`flutter analyze`) remains the authority for compilation.
- Test files are indexed but marked; exclude them in a trace unless the test is
  the thing you are changing.
- Markdown/prose (AGENTS.md, OpenSpec artifacts, screen specs) is only reachable
  via `doc_links`/MENTIONS and is notoriously under-resolved — `grep` prose.
