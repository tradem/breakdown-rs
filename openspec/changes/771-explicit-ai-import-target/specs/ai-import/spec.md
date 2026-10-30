<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# ai-import Delta (771-explicit-ai-import-target)

## ADDED Requirements

### Requirement: An upload may declare its intended season
Both upload routes (`POST /v1/ai-import/scripts`,
`POST /v1/ai-import/schedules`) SHALL accept an optional
`X-Declared-Season` header carrying the season id the client resolved as the
import target. The `X-Active-Block` header SHALL remain the authoritative write
target: the declaration is advisory metadata whose only effect is to make a
contradiction refusable.

An absent, empty or unparsable declaration SHALL degrade to "no declaration" and
SHALL NOT fail the upload — a client that cannot spell a header must still be
able to import (same degradation rule as `X-Document-Filename`).

#### Scenario: A matching declaration is accepted
- **WHEN** an authorized caller uploads with `X-Active-Block` naming a block of
  season S and `X-Declared-Season: S`
- **THEN** the job is enqueued (`202`) exactly as without the header

#### Scenario: No declaration keeps the established behaviour
- **WHEN** an authorized caller uploads without `X-Declared-Season`
- **THEN** the job is enqueued and `block_id` comes from `X-Active-Block`

#### Scenario: An unparsable declaration is ignored, not fatal
- **WHEN** `X-Declared-Season` is not a UUID
- **THEN** the header is ignored and the upload proceeds

### Requirement: A contradictory declared season is refused
The upload SHALL refuse a well-formed declared season that does not own the
`X-Active-Block` block with the registered problem code
`ai-import.scope-mismatch` (`409`, empty extension list). The refusal SHALL
happen before any document is stored and before a job row exists, so a refused
request leaves no trace.

#### Scenario: Declared season owns another block
- **WHEN** an authorized caller declares season B while `X-Active-Block` names a
  block of season A
- **THEN** the response is `409` `ai-import.scope-mismatch`, no source document
  is stored, and no job row is created

#### Scenario: The refusal is registered and localized
- **WHEN** the problem document for `ai-import.scope-mismatch` is rendered
- **THEN** it carries the registry `title`/`status`/`type`, a Fluent-localized
  `detail` in both `de` and `en`, and a golden-file snapshot

### Requirement: An AI-import job snapshots its dispatched target
`AiImportJob` SHALL expose an additive, nullable `target`
(`{season_id, season_number, block_number}`) recording the season and both
production-global numbers the upload resolved at dispatch. The snapshot SHALL be
resolved at the API edge from the block's owning season (`projection_block` →
`projection_season`) and SHALL NOT become a second write target: the apply path
keeps pinning itself to `block_id`.

The three persisted columns SHALL be written together; a failed or partial
season read SHALL degrade the whole snapshot to `null` rather than blocking an
upload whose write target is already authorized. Pre-#771 rows SHALL render
`null` (no backfill).

#### Scenario: A dispatched import names its target afterwards
- **WHEN** a job is enqueued for a block of season S (number 7), block number 3
- **THEN** the job's `target` is `{season_id: S, season_number: 7,
  block_number: 3}` and the list/status reads render it without a further lookup

#### Scenario: An unresolved season degrades honestly
- **WHEN** the season projection read fails during enqueue
- **THEN** the upload still succeeds and the job's `target` is `null`

#### Scenario: A pre-#771 job stays absent
- **WHEN** a job row created before the migration is read
- **THEN** `target` is `null` and no season is invented
