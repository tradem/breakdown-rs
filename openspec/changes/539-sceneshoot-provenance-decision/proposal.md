<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3-flash (opencode-go) -->

# 539 — SceneShoot AI provenance: derive via pair join (no-op)

## Why

Issue #539 is the decision follow-up from the #517 review: AI provenance was
extended to `Scene` (`SceneSource`) but deliberately not to `SceneShoot`. The
question was whether to (A) derive SceneShoot provenance from its immutable
`(scene_id, shooting_day_id)` pair or (B) add an additive `source`
discriminator (same shape as `SceneSource`) with the full #517 backend
pattern.

## Decision (agreed with the maintainer, 2026-10-07)

**Option A+ — derive via pair join, no code change.** A SceneShoot's
provenance is the provenance of its scene (`SceneCreated.source`); the
derivation is stable by construction because both the pair (stream identity)
and scene provenance (set once, no update event) are immutable. Two
additional rationale layers agreed in the decision handshake:

1. **Audit reconstruction suffices** for forensic questions: the AI import
   applies with the human reviewer actor (`Provenance::Human`), so
   `projection_audit` does not attribute the planning act — but the
   authoritative content provenance lives first-class on the scene, and
   `ai_import.projection_ai_import_mapping` + job records allow correlating
   the import batch.
2. **EU AI Act does not require per-row planner attribution** (Art. 4/50
   duties are satisfied by the interaction-point disclosures, the
   scene/day provenance badges, and the preview-before-apply review step;
   Art. 50(2) marking rests with the provider).

Option B stays documented in the ADR as the only-opening case (if a future
requirement ever needs "who planned this shoot row — import or human"), with
its drift risk spelled out (manual scene planned onto an AI-imported day).

## Scope

| Area | Change |
|---|---|
| `core` | No domain change |
| `infra` | No change |
| `api` | No change |
| Docs | New `docs/architecture/adrs/ADR-037-sceneshoot-provenance-pair-join-derivation.md`, ADR index row, backend CHANGELOG `[Unreleased]` entry |

## Acceptance Criteria (mapped from issue #539)

- [x] Explicit ADR-lite decision: **derive via the pair join (no-op)** —
      recorded in ADR-037 with the pair/scene-immutability argument, the
      audit-reconstruction layer, and the EU AI Act reading.
- [ ] Additive path (projector migration + OpenAPI + Dart regen): **not
      taken** — documented as the only-opening case instead (AC satisfied by
      the explicit decision itself; the AC's "if additive" branch is void).

## Out of scope

- No code change, no migration, no OpenAPI/Dart regeneration.
- Future read surfaces (e.g. Dispo-row provenance badges) add one column to
  the already-existing `projection_scene` join — no new mechanism.
