<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.2 (neuralwatt) -->

## 1. Move
- [ ] 1.1 `git mv backend/openspec openspec` (preserves history)
- [ ] 1.2 Verify `/openspec/changes`, `/openspec/specs`, `/openspec/config.yaml`,
       `/openspec/changes/archive` all present

## 2. Tooling & CI
- [ ] 2.1 `openspec validate` runs against the new root from anywhere in the
       repo
- [ ] 2.2 Update any CI workflows referencing `backend/openspec` paths
- [ ] 2.3 Update `backend/docs` / README cross-references if any point at
       `backend/openspec`

## 3. Verification
- [ ] 3.1 `openspec doctor --json` reports healthy at the new root
- [ ] 3.2 All archived + active changes still validate
