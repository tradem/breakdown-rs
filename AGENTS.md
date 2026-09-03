<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

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
`design.md` ↔ `AGENTS.md` byte-identity contract with the OpenSpec change artifacts.

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

## 3. On-demand instructions (pi-rules)
Detailed backend documentation is injected when matching files are read, from two levels of
glob-scoped rule files: `backend/.github/instructions/` (backend-relative globs, fires for any
read under `backend/**`) and the monorepo-root `.github/instructions/` (workflows, root
scripts). pi-rules resolves the project root **per read file** — the first `Cargo.toml` / `.git`
marker walking up decides which level's instructions fire — so rules load regardless of the
session's launch directory. `/rules` lists only always-on rules; glob rules appear attached to
the file reads they match. The register lives in `backend/AGENTS.md` §6. Recommend launching
pi in `backend/` for backend-heavy sessions (loads `backend/AGENTS.md` natively and avoids
per-read re-injection of it); frontend instructions may follow later in the same layout.

*When in doubt, read the area AGENTS.md and the referenced ADRs before generating code.*
