<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.2 (neuralwatt) -->

## 1. Move
- [x] 1.1 `git mv backend/openspec openspec` (preserves history)
- [x] 1.2 Verify `/openspec/changes`, `/openspec/specs`, `/openspec/config.yaml`,
       `/openspec/changes/archive` all present

## 2. Tooling & CI
- [x] 2.1 `openspec validate` runs against the new root from anywhere in the
       repo (CLI auto-detects root at repo root; `openspec doctor --json`
       reports `healthy: true`)
- [x] 2.2 Surveyed `.github/**` — no CI workflow references `backend/openspec`
       paths (only a comment in `flutter-ci.yml` points at `backend/openapi.yaml`,
       the OpenAPI spec, which stays put and is correct). Nothing to update.
- [x] 2.3 Updated live cross-references that pointed at `backend/openspec`:
       - `frontend-flutter/AGENTS.md` + `openspec/changes/add-flutter-app-
         foundation/design.md` (the §Cross-references sentence — kept
         byte-identical between the two)
       - `frontend-flutter/.pi/skills/flutter-issue-implementation/SKILL.md`
         (where Flutter change artifacts live + the `git add` path)
       - `openspec/changes/226-run-ai-integration-tests-in-ci/proposal.md`
         (self-reference)
       Historical narrative inside `flutter-openspec-home/spec.md` and this
       change's own files intentionally keeps `backend/openspec` as the
       *source* location being described.

## 3. Verification
- [x] 3.1 `openspec doctor --json` reports healthy at the new root
       (`root.healthy: true`, `root.source: nearest`, no broken references)
- [~] 3.2 Validation at the new root: all Flutter changes (`add-flutter-app-
       foundation`, `scaffold-flutter-project`, `wire-openapi-dart-client`,
       `wire-flutter-oidc-auth`, `add-flutter-ci-tests`,
       `add-gherkin-critical-scenarios`, `add-drift-read-cache`,
       `first-screen-seasons`) **and** this change validate `✓`. Pre-existing
       `✗` failures in unrelated backend changes (AI-payload-storage track:
       174/175/179/180/181/202/206/214/221/222/226; specs `report-rendering`,
       `scene-shoot-reports`) are content/structure issues (missing delta
       headers / `## Purpose`) introduced long before this move and fixed in
       their own tracks — the directory move regressed nothing.

## Notes (discovered during this change)
- **AGENTS.md / design.md byte-identical invariant is currently BROKEN
  (pre-existing, not caused by this move).** The follow-up PRs #288 / #289 /
  #292 / #294 updated `design.md` (e.g. `breakdown_lints` +
  `analysis_server_plugin` lint-plugin decision, scoped Gitleaks `.md` scan)
  but the on-disk `frontend-flutter/AGENTS.md` was never re-synced. Diff is
  ~200 lines. Recommend a dedicated follow-up change that re-copies
  `design.md` → `frontend-flutter/AGENTS.md` (the foundation rule mandates
  byte-identity). Out of scope for the pure root-move.
