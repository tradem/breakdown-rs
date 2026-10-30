<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# Dev data reset that preserves the configuration (issue #770)

## Why

Replaying the AI script imports for integration verification is blocked in two
independent ways, both verified against the running dev stack:

1. **Upload dedup.** `ai_import.ai_import_job` is unique on `(user_id,
   dedup_key)` (digest of the document) and the insert is
   `ON CONFLICT … DO UPDATE SET dedup_key = EXCLUDED.dedup_key` with no status
   filter, so re-uploading the same PDF answers `200` with the existing
   `succeeded` job — no new extraction.
2. **Ambient import target.** The write target is the block in the required
   `X-Active-Block` header; a freshly created season changes nothing unless the
   ambient scope is switched (#771 made that target visible and refusable, but
   it does not scope a re-import).

"Just create a new season" cannot solve either, and there is no way to undo an
import: only `ArchiveSeason`, `ArchiveCostumeCategory`, `ArchiveShootingDay`
and `DeletePhoto` existed — scene/episode/block/character/piece/outfit had no
delete or archive command at all.

## What changes

A maintenance binary (`reset-dev-data`, engine in `infra::dev_reset`, wrapper
`scripts/reset-dev-data.sh`) with two levels:

- **`imports`** — delete the job rows, purge the payload objects, and remove the
  import-created aggregates through **real domain commands** (children first).
- **`business`** — export the keep-list streams verbatim, wipe every business
  projection, the operational bookkeeping and the business buckets, replay the
  keep-list.

Seven new domain delete commands (`DeleteScene`, `DeleteEpisode`,
`DeleteShootingDay`, `DeleteSceneShoot`, `DeleteCharacter`, `DeletePiece`,
`DeleteOutfit`) with `*Deleted` events and idempotent projection deletes,
deliberately without an HTTP route or write-port method.

## Safety (non-negotiable)

No HTTP route; prod refusal (`--env dev`, `APP_ENV`, `REQUIRE_IN_TRANSIT_TLS`,
loopback-only URLs, local docker context, stopped API); `--dry-run` plan for
both levels; backup by default; interactive target confirmation unless
`--yes`; closed keep/reset classification (exhaustive `match` + workspace source
scan); audit line per run.

## Non-goals

- No reset endpoint, no scheduled/automatic reset.
- No production use: the tooling refuses non-development stacks by design.
- No import → episode provenance (#763) — the episode resolution stays a
  documented heuristic until that lands.
- No client-side "clear local cache" action: the procedure documents clearing
  the Drift DB and secure storage instead.
