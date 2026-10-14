<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# 642 — Typst report renderer: real font discovery, no silent empty-renderer fallback

## Why

Every PDF report download returns HTTP 500 `http.internal-error`. Root cause chain:

1. `infra::reporting::typst_renderer::load_system_fonts()` scans only the top
   level of a small hardcoded font-dir list and only exact-`ttf` files. On
   Arch (and many distros/containers) fonts live in subdirectories → discovery
   returns `Err("No system fonts found")`.
2. `api/src/main.rs` swallows that failure (`unwrap_or_else`) and wires an
   **empty** renderer (no templates, no fonts), logging only a `warn!`.
3. Every `render()` then answers `TemplateNotFound` → generic 500 to the user.
   Silent, total feature outage, invisible at boot.

User decision (ask_user, 2026-10-13): the real fix is **comprehensive font
discovery** — recurse + `otf`/`ttc` and cover distro-dependent font paths
(XDG/fontconfig conventions), not just more hardcoded top-level dirs.

## What Changes

### 1. Real font discovery (infra, `typst_renderer.rs`)

- Candidate directories, in order, deduplicated:
  - `$XDG_DATA_HOME/fonts` (default `$HOME/.local/share/fonts`) and every
    `$XDG_DATA_DIRS/<dir>/fonts` (defaults `/usr/local/share`, `/usr/share`) —
    freedesktop fontconfig convention.
  - Legacy `$HOME/.fonts`.
  - Always `/usr/share/fonts`, `/usr/local/share/fonts` (containers often run
    without `$HOME`).
  - macOS: `/System/Library/Fonts`, `/Library/Fonts`; Windows: `%windir%\Fonts`.
- **Recursive** walk (depth-capped at 8), accepting `ttf`, `otf`, `ttc`, `otc`
  (case-insensitive); follows file symlinks, does not descend into symlinked
  directories (cycle safety).
- Canonical-path dedupe so XDG overlap doesn't load the same file twice.
- Still fails (no silent empty result) when nothing is found.
- `collect_font_files()` split out as a pure, unit-testable walker.
- CodeRabbit review (PR #651): best-effort fontconfig `<dir>` discovery
  from `/etc/fonts/fonts.conf` + `/etc/fonts/local.conf` (prefix attribute,
  `~`/`${...}` substitution) and an explicit `REPORT_FONT_DIRS` override
  (OS path list, `~`-expanded) that takes precedence over all automatic
  sources — escape hatch for NixOS-style package font layouts.

### 2. No silent empty renderer (api, `main.rs`)

- `TypstReportRenderer::with_defaults()` failure is now **fatal at boot** with
  an actionable error message (a report feature that cannot render is a
  deployment misconfiguration). Removes the `unwrap_or_else` empty-renderer
  fallback.

### 3. Distinct problem code (core + api, ADR-031)

- New registry entry `REPORT_RENDERER_UNAVAILABLE` — 503
  `report.renderer-unavailable`, title "Report rendering unavailable".
- `ReportRenderError::TemplateNotFound` (the only client-visible symptom of a
  broken renderer) maps to it in `problems::report_render_problem` instead of
  the generic 500.
- Fluent `detail` in `de`/`en`; golden file regenerated; `openapi.yaml`
  regenerated via `UPDATE_OPENAPI=1` (x-code-registry is woven from the
  registry).

### 4. Tests

- infra: walker unit tests (nested subdirectories, `otf`/`ttc`/`otc`,
  unknown extensions ignored, file symlink followed, symlinked dir not
  followed, depth cap, dedupe) on temp dirs; `with_defaults()` non-empty
  template map invariant (all five `ReportKind`s).
- api: `test_map_render_error_template_not_found` now expects 503
  `report.renderer-unavailable`.
- E2E on this host (Arch — exactly the failing layout): `with_defaults()`
  succeeds and renders a PDF (verified via test run).

## Version Bumps (planned)

| Crate | Previous | New | Bump type | Reason |
|---|---|---|---|---|
| `core` | 0.27.0 | 0.28.0 | MINOR | New public `REPORT_RENDERER_UNAVAILABLE` problem-code constant (additive) |
| `infra` | 0.32.0 | 0.33.0 | MINOR | Renderer font-discovery behavior fix (public behavior; re-pins core) |
| `api` | 0.25.0 | 0.26.0 | MINOR | New wire problem code + boot fail-fast (additive contract change; re-pins core+infra) |

## Risks / Trade-offs

- Boot now fails when fonts are genuinely absent (e.g. a bare container).
  That is the point: it surfaces at deploy time with an actionable message.
  The comprehensive XDG/fontconfig discovery plus recursion makes this case
  rare; the distro container images all carry fonts in standard trees.
- Considered and rejected: embedding a font set (binary weight + license
  files) and a `REPORT_FONT_DIRS` env override (config surface without a
  demonstrated need — revisit if a container layout defeats discovery).
- The orphaned `src/handlers/report_tests.rs` (not wired via `#[path]`,
  stale signatures) is left untouched — out of scope.

## Impact

- **Code:** `crates/infra/src/reporting/typst_renderer.rs`,
  `crates/api/src/main.rs`, `crates/api/src/problems/mod.rs`,
  `crates/core/src/error_registry.rs`, `crates/api/locales/{de,en}/errors.ftl`
- **Contract:** `backend/openapi.yaml` (x-code-registry +1),
  golden `tests/golden/problems/report.renderer-unavailable.json`
- **Nothing else:** no migrations, no new dependencies.
