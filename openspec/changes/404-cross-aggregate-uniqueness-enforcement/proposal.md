<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# 404: Cross-aggregate uniqueness enforcement — API-edge 409 + projector poison-skip

## Why

Issue #404 confirmed a **bug class**: cross-aggregate uniqueness invariants
(scene-shoot pair, season/block/episode series numbering) were enforced
*only* by projection unique constraints. The write path answered a violating
command with **2xx** (the `*Created`/`SceneShootPlanned` event sat in the
event store, permanently violating the invariant) and the projector crashed
on the 23505 (worker panic → coordinator dead) — silent data loss from the
user's perspective.

**Drift check finding:** partial infrastructure already existed —
`SceneShootRepository::find_by_scene_and_day` and
`SeasonRepository::find_by_series_and_number` read ports were in place (the
latter documented "for the 409 pre-check") but **never wired into any
handler**; the `scene-shoot.pair-already-exists` problem code and Fluent
texts existed (backing the per-stream aggregate check). The audit also found
**two more instances of the same class** beyond the two named in the issue:
block and episode numbering (`idx_projection_block_series_number`,
`idx_projection_episode_series_number` — same client-supplied `number`, same
aggregate-comment pattern, and the `find_by_series_and_number` ports
already existed there too). **Scope decision (user): fix all four instances.**

## What Changes

1. **API-edge pre-checks + 409** (handlers are the only legitimate
   read-model consumer — AGENTS.md §1 CQRS boundary):
   - `plan_scene_shoot` → 409 `scene-shoot.pair-already-exists`
   - `create_season` → 409 `season.number-already-exists` (new code)
   - `create_block` → 409 `block.number-already-exists` (new code)
   - `create_episode` → 409 `episode.number-already-exists` (new code)
   Pre-checks are advisory; the projection unique constraints remain the
   authoritative backstop against races.
2. **Projector failure behavior** (`crates/infra/src/projectors/
   invariant_skip.rs`): the guarded inserts in the four projectors run
   inside a SAVEPOINT of the batch transaction; a permanent 23505 on
   exactly those constraints is classified, logged (`warn!`), rolled back
   to the savepoint, and acknowledged — no more panic-killed
   worker/coordinator. Full DLQ/poison-table mechanics stay in #37.
3. **Registry/docs**: 3 new `problem_codes!` entries (count guard 74 → 77),
   Fluent texts (de/en), golden snapshots, regenerated `openapi.yaml`
   (`x-code-registry`), instruction-file status table updated, and the
   gift-record cleanup note for the prod/upgrade path.

## Impact

- **core**: 3 new public registry consts (additive) — rides open 0.11.0 MINOR.
- **api**: new 409 behavior on four POST endpoints (openapi `x-code-registry`
  extended) — rides open 0.10.0 MINOR.
- **infra**: projector behavior fix, no public API change — rides open
  0.16.0 MINOR.

## Tasks

- [x] Registry entries + Fluent + golden snapshots + openapi regeneration
- [x] Handler pre-checks (4) + mock fakes made faithful (scan stores)
- [x] Projector savepoint-skip + classification unit tests
- [x] Handler tests: 409 + free-path (season/block/episode/scene_shoot)
- [x] CHANGELOGs + instruction-file status/cleanup notes
