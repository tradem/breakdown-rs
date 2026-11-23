<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: hy4-flash-free (opencode-go) -->

# Proposal — P3 CastDirectory, deterministic role precedence & continuity context (issue #961)

Part 3 of `ai-import-vlm-document-structure` / ADR-041. Depends on #958 and #959,
both closed at `53a9c56`; no P3 symbol exists yet, so there is no drift to reconcile.

## Discovery evidence

- Index: project `breakdown-rs`; `scripts/check-graph-freshness.sh` → fresh (commit `53a9c56`, 2026-11-23T15:15:49Z).
- Graph (meaning): `search_code("PageZone|CastList|ScriptBody", regex=true)` → `document.rs:PageZone (Enum)`, `classify_document_zones (Function)`, `preview.rs:SegmentedScript (Struct)`; `search_code("CastDirectory|resolve_character_category|NeighborSceneBrief|existing_season_cast", regex=true)` → 0 results. `trace_path(verify_draft_outfits, inbound)` → 10 callers (9 preview tests + `infra/src/ai/workers.rs`); `trace_path(continuity_state, inbound)` → 11 (1 continuity test, `run_outfit_continuity_pass`, 8 indirect tests, one worker file hit); `trace_path(extract_scenes_from_structured, inbound)` → 17 (15 preview tests, spatial-pdf test, `workers.rs`).
- Text (occurrence): `rg -n "CastDirectory|resolve_character_category|NeighborSceneBrief|existing_season_cast|CharacterCategory" crates/core/src/ai crates/infra/src/ai config/default_ai_prompts.toml` → only the existing `CharacterCategory` uses in `preview.rs` (no P3 implementation). `rg -n "3\\.1|P3" ../openspec/changes/ai-import-vlm-document-structure/tasks.md` → §3 checkboxes all unchecked.
- Coverage: `check_index_coverage(paths=[core/src/ai/document.rs, core/src/ai/preview.rs, core/src/ai/continuity.rs, infra/src/ai/worker_loop.rs, infra/src/ai/workers.rs])` → 4 clean, `infra/src/ai/workers.rs` `missing` (read via targeted `get_code_snippet` source pages 621–1382 before editing).
- Not the graph (and why): prompt wording is text/config → `rg` + full read of `config/default_ai_prompts.toml`; the exact struct fields of `CharacterView`, `AiImportJob`, `AiImportTarget` and `CharacterCategory` came from `get_code_snippet` (graph source reads), not from grep.

## Plan

1. **Core — `ai/document.rs`** (D5, zero `Arc`): add `const CAST_SECTION_MAPPING: &[(&str, CharacterCategory)]` with the exact header table from the issue; `CastDirectory` / `CastDirectoryEntry` and a pure `parse_cast_directory(&[ZonedLine<'_>])` that reads `PageZone::CastList` lines, splits comma lists, strips trailing `(44)` / `(8, OT)` / `(MT)` parentheticals and records `inline_ot`. Add dictionary-gated `normalize_kerning(text, &CastDirectory)` that only joins whitespace-split token runs whose concatenation equals a multi-character name token from the directory.
2. **Core — `ai/preview.rs`**: carry `cast_directory` on `SegmentedScript` (built in `extract_scenes_from_structured`, empty for the flat-text seam); add `ExistingSeasonCharacter`, `NeighborSceneBrief`, neighbour-bracket construction and a compact `<document-context>` renderer; implement pure `resolve_character_category` with the five-step ladder (directory → existing season cast → inline background marker → zero-dialogue generic role → `main_cast`) and one `characters` uncertainty for a conflicting-directory identity. Extend grounding so `verify_draft_outfits` accepts both raw and kerning-normalized text via an additive second entry point; keep the existing signature for all current callers.
3. **Core — `ai/continuity.rs`**: extend the Pass-2 `continuity_state` payload with `previous_scene` / `next_scene` (`scene_number`, `location`, `mood`, `script_day`, `same_script_day`), taking neighbour brackets as borrowed slices.
4. **Infra — read boundary + worker**: add `character_repo: CharacterRepositoryImpl` (by value) to `WorkerDeps`, load `list_by_season` once in `script_worker_tick` for `job.target.season_id` (best effort, bounded, never blocking), map `CharacterView` → `ExistingSeasonCharacter`, and pass a borrowed slice through a new `process_with_cast` seam so the ~20 existing worker test constructors stay untouched. Inject `<document-context>` before the Pass-1 scene text; verify outfits against raw + normalized text; apply the resolver to every LLM character row before it reaches the preview; pass neighbour brackets into Pass 2.
5. **Prompt + docs**: update `config/default_ai_prompts.toml` with `<document-context>` and the strict rule (directory wins over an inline `(OT)` when the figure is listed; an unlisted `(OT)` is always `extra`; never say "sometimes guest"). Update the AI-import instructions and OpenSpec §3 checkboxes; changelogs/versions per ADR-020.

## Guardrails

- No `Arc<T>` on domain data or new call-path parameters; `PgCharacterRepository` stays a by-value `Clone` in `WorkerDeps`.
- Read-model lookup only in `worker_loop.rs` (worker read boundary), never in an adapter/saga/aggregate; projection-miss or error degrades to an empty cast slice.
- No `unwrap`/`expect`/`panic`, static SQL only, `#[serde(default)]` on new persisted preview fields, no wall-clock test gates.

## Verification

- Deterministic unit tests for the four acceptance examples, kerning safety (ordinary German prose untouched, grounded outfits kept), Pass-1 context rendering and Pass-2 neighbour state.
- `cargo test -p breakdown-core`, `cargo test -p breakdown-infra`, `cargo clippy --workspace --all-targets -- -D warnings`, `cargo test -p architecture_tests`.
- `AI_EVAL_CORPUS_DIR=~/Downloads/drive-download cargo test -p infra --test ai_document_eval_corpus -- --nocapture` → **pass**: 5/5 scripts at their expected scene counts (40/42/43/42/42) and **20/20** cast-category assertions via the real resolver (the manifest now carries `cast=name:category` expectations for every script).

## Version bumps (planned)

| Crate | Previous | New | Bump type | Reason |
|---|---|---|---|---|
| `core` | 0.77.0 | 0.78.0 | MINOR | New public cast-directory/role-resolution/continuity API |
| `infra` | 0.88.0 | 0.89.0 | MINOR | New public worker dependency slice + context-aware pass |
| `api` | 0.71.2 | 0.71.3 | PATCH | Composition-root wiring + dependency re-pin; no wire change |
