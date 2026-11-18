<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# 827 — The script's own block, next to the episode

## Why

The import knows and shows the **episode** it extracted ("Ep. 292", episode
chips in the progress card) but never the **block**, although every production
script states it in its page headers (`Block: 2`, `Block: 098/Ep.: 294`). Two
consequences, both from the reporter:

- the reviewer cannot tell whether the script belongs to the block the import
  will write into;
- an import into the wrong block is discovered at apply time (the cross-block
  guard answers `403`) or never.

Today "import target" means exactly one thing: the block that was **active at
upload** (`X-Active-Block`, surfaced as `job.target` since issue #771). The
block the **document states** is a different fact and was never read.

## What changes

The script's block becomes a first-class, read-only fact next to the target —
it never *changes* the target (adopting the script's block as the target is a
separate, design-gated issue).

**Backend (this change's first PR, zero extra LLM tokens):**

- A deterministic `Block:` marker scan next to `episode_marker` in
  `core/ai/preview.rs` (`block_marker` + `extract_block_number`). Observed
  shapes: `Block: 2`, `Block 2`, and the glued page header
  `Block: 098/Ep.: 294` (leading digits only — `98`). The scan is SHAPE-driven
  rather than casing-driven (page headers also arrive as `BLOCK: 2`): 1-3
  digits, a non-alphanumeric digit boundary and a field boundary behind them, so
  prose ("Block 2 wurde am Montag gedreht.", "Der Block 2 war besser.") and a
  scene heading ("1. I/T - Block 2 - WOHNUNG") never parse. The FIRST occurrence
  wins, so a page header repeated on every page is one fact, not a per-line
  flip-flop.
- `AiImportProgress.block_number: Option<i32>` — additive with
  `serde(default)`, published from the very first progress frame. `None` is
  honest absence ("the script states none"), never a fabricated number.
- `ScriptContext.block_number: Option<i32>` — the same fact on the stored
  preview.
- Model fallback: `ScriptContextSchema` (the provider-facing strict mirror)
  gains `block_number` and the default script prompt gains a `<block>` element,
  so a marker the scan cannot read has a field to land in instead of becoming an
  invented uncertainty. The scan stays authoritative; the model only fills a gap.

**Frontend (second PR, display only):**

- Job status card: a block chip next to the episode chips.
- Jobs row: the one-line "Episoden erkannt" value gains the block when known.
- Preview screen: a scope line — "Skript: Block 2 · Importziel: Block 1" — where
  the target is `job.target.blockNumber` and the script value is the new field.
- Association instead of omission: with `block_number == null` the line renders
  the target as the associated block with explicit wording.
- Mismatch surfacing: a non-blocking warning banner when the two differ.

## Design decisions

- **Separate field, never overloaded `target`.** A single field cannot answer
  "what does the script say" and "where will this land"; only two fields let a
  client compare them.
- **Deterministic scan first, model second.** The header is machine-readable, so
  the primary source costs no tokens and cannot hallucinate. The prompt rule is
  the fallback for a foreign header shape — and because it is a *new* schema
  field rather than a prompt-only rule, it is actually reachable under `strict`
  Structured Outputs (the older per-scene `episode` rule is not: the mirror never
  declares it).
- **First occurrence wins.** A document that names two different blocks (a block
  change mid-script) publishes the one it opens with; a single published number
  must not flip per page.
- **No target change here.** Making the script's block the target needs a
  block-less upload and a late attach; this change produces the data that design
  will need.

## Risks / limits

- A script whose header carries no recognizable block marker and whose chunks the
  model reads without a block answer publishes `null`; the client then shows the
  target as the associated block — the honest state, not a guess.
- Prompt edits reach only deployments whose stored script prompt is empty (the
  documented `AI_IMPORT_DEFAULT_PROMPTS_PATH` / stored-prompt behaviour); the
  deterministic scan is unaffected by that, which is why it stays primary.

## Out of scope

- Choosing / creating the target block from the submit screen.
- Adopting the script's block as the import target (late attach).
- Any blocking gate on a mismatch — this change surfaces, it does not refuse.

## Related

- #826 — sibling marker rules (`(OT)`, `Ep.: <n>/<suffix>`) in the same prompt
  and the same deterministic scan family.
- #771 — `job.target` (season + block numbers of the import target).
