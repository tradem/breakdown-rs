<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

## Why

Issue #695 (follow-up from the CodeRabbit review of PR #692 / issue #677):
the AI script extraction classifies character categories per scene block. A
**document-global** conflict — the same figure named under two cast sections
with differing non-default categories (`guest` vs `extra`) — is only visible
by comparing rows, and the apply plan's reconciliation rule (first
non-default wins) hides it behind a deterministic decision instead of asking
the reviewer.

## What Changes

- `core`: new pure scan `ai::category_conflict_uncertainties(&ScriptContext)`
  collecting the per-identity non-default category signals across the whole
  preview; one blocking `Uncertainty` (kind `field_ambiguity`, field
  `category`, `scene_index` = first appearance) per conflicting identity,
  `suggested_value` = the first non-default signal (what the plan picks;
  display-only). Plus `CharacterCategory::as_str` (stable snake_case slug
  for reviewer-facing notes).
- `infra`: the script worker runs the scan after all chunk rows are merged,
  before the preview is stored — the extracted uncertainty travels inside
  the stored preview like every other uncertainty.
- No wire-shape change (`Uncertainty` already carries `kind`), no migration,
  no OpenAPI drift; old stored previews are unchanged.

## Impact

- **Reviewer flow:** an unacknowledged conflict blocks the apply via the
  existing `ensure_script_applyable` gate; the #663 acknowledgement flow
  (`uncertainty_acknowledgements`) gives the one-tap resolution path.
  Agreement and default-correction signals never surface — only genuinely
  differing non-default categories.
- **Affected specs:** `specs/ai-import/spec.md` (extraction uncertainties).

## Version Bumps (lockstep core → infra → api)

| Crate | Previous | New | Bump type | Reason |
|---|---|---|---|---|
| `core` | 0.38.0 | 0.39.0 | MINOR | New public `category_conflict_uncertainties` + `CharacterCategory::as_str` |
| `infra` | 0.43.0 | 0.44.0 | MINOR | Script worker emits conflict uncertainties; re-pin core |
| `api` | 0.36.1 | 0.36.2 | PATCH | Consumption re-pin; no handler/wire change |
