<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# Tasks — dev data reset (issue #770)

## 1. Domain delete commands

- [x] 1.1 `DeleteEpisode` / `EpisodeDeleted` (+ apply, projection delete)
- [x] 1.2 `DeleteScene` / `SceneDeleted`
- [x] 1.3 `DeleteShootingDay` / `ShootingDayDeleted` (+ clear the
      `report_ops.report_job` rows that reference the day with
      `ON DELETE RESTRICT`)
- [x] 1.4 `DeleteSceneShoot` / `SceneShootDeleted`
- [x] 1.5 `DeleteCharacter` / `CharacterDeleted`
- [x] 1.6 `DeletePiece` / `PieceDeleted`
- [x] 1.7 `DeleteOutfit` / `OutfitDeleted`
- [x] 1.8 Audit projector arms for every new event
- [x] 1.9 No HTTP route, no write-port method (documented decision)

## 2. Reset engine (`infra::dev_reset`)

- [x] 2.1 Closed keep/reset classification (`AggregateCategory`, exhaustive
      `match`, workspace source-scan test)
- [x] 2.2 Prod refusal guard (`--env dev`, `APP_ENV`, `REQUIRE_IN_TRANSIT_TLS`,
      loopback-only URLs)
- [x] 2.3 Plan with per-category/per-table counts, bucket targets and notes
- [x] 2.4 Keep-list export/replay (`ESCAN`/`EMAPPEND`, verbatim bytes)
- [x] 2.5 Level `imports` (jobs, payloads, aggregates, reservation release)
- [x] 2.6 Level `business` phases (export / wipe / replay / verify)
- [x] 2.7 Backup directory + manifest
- [x] 2.8 Audit line with mode, target, counts, backup path

## 3. CLI and wrapper

- [x] 3.1 `crates/api/src/bin/reset-dev-data.rs` (args, confirmation, report,
      exit code)
- [x] 3.2 `scripts/reset-dev-data.sh` (plan / imports / business / verify,
      pg_dump + volume tarball, volume drop)

## 4. Docs

- [x] 4.1 Runbook "13. Dev data reset (issue #770)"
- [x] 4.2 `.github/instructions/local-dev-runtime.instructions.md` entry
- [x] 4.3 Root README dev section
- [x] 4.4 Client-side reset documented (Drift DB + secure storage)

## 5. Verification

- [x] 5.1 `cargo test -p infra --lib dev_reset` (44 tests)
- [x] 5.2 `cargo clippy --workspace --all-targets` clean
- [x] 5.3 `--dry-run` prints the complete plan for both levels against the dev
      stack and writes nothing
- [ ] 5.4 End-to-end `--level imports`: re-uploading an identical PDF answers
      202 with a new job id (needs the user's go-ahead: it deletes the current
      dev data set)
- [ ] 5.5 End-to-end `--level business`: script import scores with the Decision
      Model afterwards
