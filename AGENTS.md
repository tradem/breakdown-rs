<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# Breakdown-RS — Monorepo Agent Guidelines

You are the coding agent for the `breakdown-rs` monorepo — a collaborative costume
scheduling app: an event-sourced Rust backend (`backend/`), a Flutter client
(`frontend-flutter/`, Android first), and OpenSpec governance at the monorepo-root
`/openspec/`. Keep this file minimal — it is loaded in every session of this repo.

## 1. Area rules — read the matching AGENTS.md first
Area-specific core rules are **not duplicated here.** _pi_ loads context files only
from the session cwd and its parents — a `backend/` session does **not** auto-load
`frontend-flutter/AGENTS.md` and vice versa. If your task touches an area (or reads
its files), read its AGENTS.md **before** generating code:

| Area | Rules | Status |
|---|---|---|
| `backend/` | `backend/AGENTS.md` | slimmed core rules; long forms load on demand from `backend/.github/instructions/` (see its §6 register) |
| `frontend-flutter/` | `frontend-flutter/AGENTS.md` | **not yet reworked** — comprehensive long-form file, authoritative as-is; candidate for the same core/instructions split as the backend |

The Flutter file also documents its own ported pi skills (`.pi/skills/`) and the
area's on-demand rule file (`.github/instructions/flutter-code-discovery.instructions.md`).
Its former `design.md` ↔ `AGENTS.md` byte-identity contract is retired: the
`add-flutter-app-foundation` change is archived, so the on-disk `AGENTS.md` is
the authoritative copy and is edited in place.

## 2. Cross-cutting rules
- **License:** AGPL-3.0. SPDX headers and `Co-authored-by:` attribution lines apply
  monorepo-wide — conventions and tooling (`scripts/add-spdx-headers.sh` at the repo root)
  are described in `backend/AGENTS.md` §7 (the Flutter file mirrors them).
- **API contract:** `backend/openapi.yaml` is the single wire-contract review
  artifact (authored code-first via `utoipa` in `backend/`); CI fails on drift.
- **Secrets:** never commit secrets anywhere in the monorepo — `gitleaks` enforces.
- **CI:** all workflows live under `.github/workflows/`; the CI-hardening hard
  rules (SHA-pinning of actions, no `${{ github.event.* }}` interpolation into
  `run:`) apply to every workflow in this monorepo.
- **Code discovery — code-aware first, text only for text:** the deciding
  question is **not** "which tool is convenient" but "what am I asking?".
  **Text search answers whether a string OCCURS. A code-aware search answers
  what the code DOES** (who defines it, who calls it, what breaks). `rg`
  cannot see the difference between a definition, a call site, an import and a
  doc-comment mention, cannot report edge kinds, and cannot report
  completeness — so for every *meaning* question (where is X defined, who uses
  X, what does a change touch, how does X work) use the **`codebase-memory`
  knowledge graph** for project `breakdown-rs` (seeded at the monorepo root,
  covering backend Rust **and** frontend Dart) or ast-bro. `rg`/`grep` stays the
  CORRECT tool — not the lazy fallback — for pure text: ARB keys, problem
  `code`s, config/YAML values, Markdown/prose, version strings, and every path
  under `docs/`, `openspec/`, `lib/l10n/` and the test trees.
  The decision is supported, not just stated: `.pi/extensions/graph-first-nudge.ts` appends the
  code-aware result to a symbol-shaped text search AND attaches the symbol
  outline to a cold whole-file `read` of a sizeable code file (soft advisory,
  never a block; `PI_GRAPH_NUDGE=0` opts out of both halves, and a `# literal:`
  marker opts out of the search half for one call), and
  `scripts/who-watches.sh <provider>` answers the one question the graph is
  structurally blind to (Riverpod `ref.watch` wiring) by combining both tools
  in one call. The extension lives in the monorepo's project-local
  `.pi/extensions/`, which pi only loads for sessions started at THAT directory
  — run `scripts/install-pi-extensions.sh` once per clone to link it into
  `~/.pi/agent/extensions/`, so area sessions (`frontend-flutter/`, `backend/`)
  get it too; the extension resolves the indexed project from the session cwd
  and stays silent where no project matches.
  The index is machine-local (`.codebase-memory/` is gitignored), so freshness is
  a local duty, never a CI gate: `scripts/check-graph-freshness.sh` to report,
  `scripts/reindex-graph.sh [--if-stale]` to refresh; the `post-merge`,
  `post-checkout` and `post-rewrite` hooks (installed by
  `scripts/install-git-hooks.sh`, or active via `core.hooksPath=backend/git-hooks`)
  refresh it in the background. An empty
  graph result for code present on disk means *stale index* — reindex before
  falling back to text search — except under `frontend-flutter/vendor/`, which
  the indexer prunes by default. Per-area how-to (incl. the question→tool
  table and the graph's honest limits):
  `.github/instructions/flutter-code-discovery.instructions.md` (frontend) and
  `backend/AGENTS.md` §6 (backend).

## 3. On-demand instructions (pi-rules)
Detailed backend documentation is injected when matching files are read, from two levels of
glob-scoped rule files: `backend/.github/instructions/` (backend-relative globs, fires for any
read under `backend/**`) and the monorepo-root `.github/instructions/` (workflows, root
scripts, and the Flutter tree — `frontend-flutter/**` has no area-level instructions directory,
so its reads resolve to the root level). pi-rules resolves the project root **per read file** —
the first `Cargo.toml` / `.git` marker walking up decides which level's instructions fire — so
rules load regardless of the session's launch directory. `/rules` lists only always-on rules;
glob rules appear attached to the file reads they match. The register lives in
`backend/AGENTS.md` §6. Recommend launching pi in `backend/` for backend-heavy sessions (loads
`backend/AGENTS.md` natively and avoids per-read re-injection of it); Flutter-specific
on-demand rules sit at the root level (see the register).

*When in doubt, read the area AGENTS.md and the referenced ADRs before generating code.*
