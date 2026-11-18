<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# Proposal: Surface the cross-block episode-number conflict location and make the recovery navigable (issue #705)

## Why

Applying an AI script import whose draft episode number already exists in a
project (e.g. episode 293, created by the #665-documented import in another
block) is refused with `ai_import.episode_number_other_block`
("Wechsle den Block und lade das Dokument dort erneut hoch."). The refusal
names neither the season nor the block that hold the conflicting episode,
and every escape route from the preview is closed: the block picker is
season-scoped, the existing-episode picker is job-block-scoped (cross-block
adoption trips the IDOR guard by design), and "create" re-enters the same
check. The apply is a dead end.

## What Changes

**Backend — the 409 carries the conflict's location (S1):**

- `ApiError::EpisodeNumberAlreadyExists(EpisodeId, i32)` gains a third
  field: the conflicting episode's `BlockId`, rendered as the S1 extension
  `existing_block_id` (registered in `error_registry.rs` next to
  `existing_episode_id` / `number` from #665).
- Both raise sites (manual `POST /v1/episodes` pre-check and the AI-apply
  group loop) pass `EpisodeView.block_id` — both are API-edge pre-checks,
  the only legitimate read-model consumers.
- `openapi.yaml` regenerated via `UPDATE_OPENAPI=1 cargo test -p api --test
  contract openapi_drift`.
- Client compatibility: older clients ignore the new extension (serde-free
  JSON map); older backends simply omit it (client falls back).

**Flutter — attribution + one-tap scope-switch recovery:**

- `ensureGroupEpisodeResolved` (the client-side pre-check that today drops
  the conflicting row's `blockId`) resolves the location best-effort
  (`blockById` → seasonId + block number; season repository → season name)
  and sets the refusal with extensions
  `existing_episode_id` / `existing_block_id` / `existing_season_id` /
  `existing_season_name` / `existing_block_number`. On resolution failure
  it degrades to today's bare code (old copy still renders).
- New parameterized copy: the refusal names the episode's home
  ("Episode 293 liegt in Season X · Block Y …"); the bare fallback copy
  stays for the extension-less path.
- New one-tap recovery on the apply error card (`ai-apply-switch-scope`):
  switches the sticky active scope directly to the episode's home
  season+block (`activeBlockProvider.set` — bypasses the season-scoped
  picker, satisfying the cross-season AC) and pushes
  `AiImportSubmitScreen` so the reviewer re-uploads there; the new job is
  bound to the home block, where the number collision resolves through the
  existing adopt-in-job-block branch.
- The #665 `episode.number-already-exists` recovery now branches: when the
  409's `existing_block_id` matches the job's block → assign-existing
  (unchanged); when it differs → the new scope-switch recovery (assign-
  existing across blocks would 403 at the IDOR guard).

**Deliberately out of scope:** the longer-term product decision on
re-scoping jobs across blocks / cross-block group assignment (IDOR
doctrine) — noted in the issue as triage direction 3.

## Impact

- Affected specs: none (error-code contract extensions only; no new
  endpoint, no behaviour change of existing codes beyond added extensions).
- Version bumps (dependency-order lockstep, additive MINORs, #665
  precedent): `core 0.39.0 → 0.40.0` (registry whitelist), `infra
  0.44.0 → 0.45.0` (re-pin), `api 0.36.2 → 0.37.0` (variant carries the
  block id; re-pins).
