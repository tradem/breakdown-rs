<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

## Why

Issue #706: the script (screenplay) AI import extracts scenes, figures,
costumes and episode markers — but not shooting days. `DraftScene.script_day`
is stored only as a scene detail; no `ShootingDay` aggregate is created and
scenes stay unscheduled. The schedule import path already implements the full
apply machinery (`schedule_apply.rs`: deterministic `derive_id`, mapping-row
idempotency, `recover_version`), and `ShootingDaySource::AiExtracted` exists
unused by the script path.

**Settled decisions (user, 2026-06):**

1. **Scope:** backend-only branch + regenerated API client + frontend version
   bump with the frontend kept compiling and tests green. Frontend
   planned→actual work continues in a new branch/PR (documented on the issue).
2. **Open question 1 (assign-to-actual semantics):** option (b) — link/merge a
   script-derived *planned* AI day into an *actual* day, moving the scene
   links. Backend surface shipped here; frontend wiring follows in the
   continuation PR.
3. **Open question 3 (labels):** normalize to the day number; the display
   label is preserved from the first occurrence.
4. **Open question 4 (merge path):** the merged (schedule + script) apply
   keeps the schedule rows' day labels/dates authoritative — its day creation
   already runs via `ScheduleApplyWorker`; script-day groups never create
   additional days there (documented, no code change needed).

## What Changes

- `core`:
  - New `DraftShootingDay { number: Option<i32>, label: Option<String> }`
    with `group_key()` (`day:<n>` / `day-l:<label>`) and `display_label()`,
    mirroring `DraftEpisode`.
  - Deterministic day-marker scan (`day_marker`) over the same normalized
    line copy as the `Ep.:` scan: `Tag N`, `N. Spieltag`, `Spieltag N`,
    `Drehtag N`, `Day N`. `SceneChunk.shooting_day` carries the day in effect
    at the chunk's heading (serde default — old stored previews keep loading).
  - `DraftScene.shooting_day: Option<DraftShootingDay>` (serde default).
    The LLM's existing verbatim `script_day` becomes the grounded fallback:
    when the scan found no marker for a chunk, the model's `script_day` is
    normalized through the same parser (post-extraction guard, #607
    doctrine: a prompt is an instruction, not a guarantee).
  - `shooting_day_group_refs(preview)` (mirrors `episode_group_refs`).
  - Apply planner: `ShootingDayPlan { day_ref, accepted }` reviewer decision
    per day group; `SceneApplyPlan.shooting_day: PlannedShootingDay` (None |
    Group{day_ref}); new gate error `MissingShootingDayGroup`.
- `infra`:
  - Script extraction stamps `scene.shooting_day` from the chunk scan;
    `ScriptContextSchema`/`DraftSceneSchema` (client.rs) carry the field.
  - `apply_script` resolves each planned day group to a real
    `ShootingDay` aggregate (episode-scoped from the row's resolved episode,
    `AiExtracted` source, deterministic id, mapping kind `shooting_day`)
    and links accepted scenes via `ScheduleSceneOnShootingDay` +
    `PlanSceneShoot` (fallback planned order, same as the schedule apply).
    Rejected groups leave scenes unscheduled and are reported.
  - New `LinkShootingDay`s surface (decision b):
    `POST /v1/shooting-days/{id}/link-into/{target_id}` — handler-orchestrated
    re-pointing of the source day's scene links onto the target day
    (per-scene `ScheduleSceneOnShootingDay` / `UnscheduleSceneFromShootingDay`,
    `PlanSceneShoot` for missing target pairs preserving planned order,
    source day archived). Target wrapped → 409
    `shooting-day.target-wrapped` (wrap finality, #376/#706); source/target
    episode mismatch → 409 `shooting-day.episode-mismatch`.
- `api`: apply request gains `shooting_days: Vec<ApplyShootingDayRequest>`
  (serde default — old clients keep applying); apply gate validates day refs
  against the preview (`409 ai-import.apply-missing-shooting-day-group`,
  ADR-031 registry); response reports `created_shooting_days`,
  `scheduled_scenes`, `skipped_day_groups`. New problem codes:
  `ai-import.apply-missing-shooting-day-group`, `shooting-day.target-wrapped`,
  `shooting-day.episode-mismatch` (+ Fluent locales de/en).
- Frontend: regenerate the API client (no drift), version bump, adapt any
  generated-type consumers so the app compiles and all tests stay green.

## Impact

- **CQRS boundary:** the planner stays pure; the write side resolves day
  ids only from its own mapping rows; the link handler reads projections at
  the API edge only (legitimate consumer).
- **Wrap finality:** the script apply only creates fresh days; the link
  endpoint refuses a wrapped target day with a registered 409.
- **Idempotency:** day creation and scene links reuse the reservation →
  command → confirm protocol (derive_id / recover_version / mapping rows), so
  re-apply converges.
- **Affected specs:** `specs/ai-import/spec.md` (extraction + apply),
  `specs/shooting-day-scheduling/spec.md` (link endpoint).

## Version Bumps (lockstep core → infra → api)

| Crate | Previous | New | Bump type | Reason |
|---|---|---|---|---|
| `core` | 0.40.0 | 0.41.0 | MINOR | New public AI-preview surface: `DraftShootingDay`, `SceneChunk.shooting_day`, `DraftScene.shooting_day`, `parse_script_day`, `shooting_day_group_refs`, `ShootingDayPlan`/`PlannedShootingDay`, extended `plan_scene_apply`, 2 new problem codes |
| `infra` | 0.45.0 | 0.46.0 | MINOR | Script-apply day/link machinery (`ApplyWorker` gains day+scene-shoot ports), shared reservation-protocol helpers; re-pins core |
| `api` | 0.37.0 | 0.38.0 | MINOR | Apply request/response day fields, `link-into` endpoint, 3 new problem codes + Fluent texts; re-pins core/infra |

Frontend (`frontend-flutter`): `0.4.0-beta.4+96 → 0.4.0-beta.5+97` — regenerated
client (no drift), version bump, app compiles and the full test suite stays
green; the planned→actual UI work continues in a follow-up PR.
