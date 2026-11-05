<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# 827 — Tasks

Two PRs, stacked: the backend + generated client first (the Flutter PR consumes
the field and can ship alone if it lands first — an absent field renders
nothing).

## 1. Core: the deterministic block scan and the additive wire field (PR 1)

- [x] 1.1 `core/ai/preview.rs`: `block_marker` (shape-driven, case-insensitive
      token, 1-3 digits, digit boundary, field boundary behind the number).
- [x] 1.2 `core/ai/preview.rs`: `pub fn extract_block_number(document)` — first
      occurrence wins, `None` when the document states none.
- [x] 1.3 `core/ai/preview.rs`: `ScriptContext.block_number: Option<i32>`,
      additive with `serde(default)`.
- [x] 1.4 `core/ai/views.rs`: `AiImportProgress.block_number: Option<i32>`,
      additive with `serde(default)`.
- [x] 1.5 `core/ai/mod.rs`: re-export `extract_block_number`.
- [x] 1.6 `core/ai/preview_tests.rs`: header shapes, glued header, repeated
      headers, differing headers, prose/scene-heading rejection, absence.
- [x] 1.7 `core/ai/views_tests.rs`: additive-in-both-directions wire test.

## 2. Infra: publish, fall back, and reach the model (PR 1)

- [x] 2.1 `infra/ai/workers.rs`: seed `progress.block_number` from
      `extract_block_number(text)` on the FIRST frame (zero extra tokens).
- [x] 2.2 `infra/ai/workers.rs`: model fallback per chunk — only when the scan
      found nothing; also recorded on the accumulated `ScriptContext`.
- [x] 2.3 `infra/ai/client.rs`: `ScriptContextSchema.block_number` (the
      provider-facing strict mirror; without it the prompt rule is unreachable).
- [x] 2.4 `config/default_ai_prompts.toml`: `<block>` element (leading digits
      only, repeated headers are no conflict, no uncertainty for a missing
      marker, a location name is not a block number).
- [x] 2.5 Tests: worker publishes the document's block; model fallback fills a
      gap; prompt element regression; provider schema mirror.
- [x] 2.6 `openapi.yaml` regenerated (`UPDATE_OPENAPI=1 … openapi_drift`).
- [x] 2.7 Generated Dart client regenerated + version bumped
      (`CLIENT_VERSION` 1.1.0 in `scripts/regen-client.sh`).
- [x] 2.8 Version bumps + CHANGELOGs: `core` 0.58.0, `infra` 0.68.0,
      `api` 0.56.0, dependent pins, `backend/CHANGELOG.md`.

## 3. Flutter: show the script's block next to the episode (PR 2)

- [ ] 3.1 `import_jobs/job_status_screen.dart`: a block chip beside the episode
      chips, same visual weight; hidden when the field is absent.
- [ ] 3.2 `import_jobs/jobs_screen.dart`: the one-line "Episoden erkannt" value
      gains the block (only when known).
- [ ] 3.3 `import_jobs/preview_screen.dart`: a scope line "Skript: Block {n} ·
      Importziel: Block {m}" from `progress.blockNumber` + `job.target`.
- [ ] 3.4 Association, not omission: with no script block, render the target as
      the associated block with explicit wording.
- [ ] 3.5 Mismatch surfacing: a non-blocking warning banner when the two differ.
- [ ] 3.6 de/en ARB keys + regenerated localizations.
- [ ] 3.7 Widget tests for all three surfaces (present, absent, mismatch).
- [ ] 3.8 `pubspec.yaml` version bump + `CHANGELOG.md` entry.
