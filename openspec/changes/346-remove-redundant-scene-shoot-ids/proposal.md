<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: muse-spark-1.3-contributor (opencode-go) -->

# Proposal: remove redundant path identifiers from PlanSceneShootRequest (issue #346)

## Context

`POST /v1/shooting-days/{day_id}/scenes/{scene_id}/scene-shoots` takes its
identifiers twice: once in the path (`day_id`, `scene_id`) and again as
required body fields (`shooting_day_id`, `scene_id`) on
`PlanSceneShootRequest`. Every caller sends redundant data; a contradictory
`scene_id` was silently ignored until PR #344 added a matching `400`
validation (issue #333 follow-up), and `plan_scene_shoot` still has to police
two equality checks plus a `400` response that exists only to guard the
duplication.

The route family was only just exported to `backend/openapi.yaml` in PR #344
(issue #333). The Flutter app has zero references to the new endpoints
outside the generated vendor model (`vendor/breakdown_api/`), which is itself
regenerated from the spec — no shipped client sends these fields yet.

## Decision: in-`/v1` breaking removal (Option A)

Per ADR-021 D2/D3, removing required wire fields is strictly a MAJOR
(`/v2` + 8-week `/v1` coexistence). We deliberately stay in `/v1` because:

- No deployed client depends on the redundant fields (freshly exported
  contract, client blocked waiting for it per #333) — there is nobody to
  protect with a deprecation window.
- The `/v2` dual-serve machinery (Deprecation/Sunset headers, concurrent
  handlers, wire-contract fixtures per D4/D6) does not exist yet; building it
  for a route nobody ships against is disproportionate.
- The rejected alternatives: **optional-with-fallback** (Option B) keeps the
  redundancy permanently and leaves a second deserialisation path to police;
  **strict `/v2` coexistence** (Option C) doubles handler surface for zero
  migrated clients.

This is documented as a pre-release-cleanup exception to ADR-021, not a
reinterpretation of the rule: once a client ships against a contract, D2/D3
apply in full.

## Changes

1. `crates/api/src/handlers/mod.rs`
   - `PlanSceneShootRequest` slims to `{ planned_order: LexicalSortKey }`.
   - `plan_scene_shoot` drops both body/path equality checks; `scene_id` and
     `day_id` come from the path only (core `PlanSceneShoot` command is
     unchanged — it still carries both ids, populated at the API edge).
   - The `400` utoipa response on the operation is removed (obsoletes the
     carve-out the #343 proposal noted for this handler).
2. `backend/openapi.yaml`: regenerated (`UPDATE_OPENAPI=1 cargo test -p api
   --test openapi_drift`).
3. `frontend-flutter/vendor/breakdown_api/`: regenerated via
   `scripts/regen-client.sh` and committed.
4. `crates/api/CHANGELOG.md`: entry under `[Unreleased]`/`[0.10.0]`.
