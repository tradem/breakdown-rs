<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# 898 — Design

## Context

The AI-import submit screen's target card resolves the write target before the
upload and renders it as one line (`Season 1 · Block 1`). Three of the four
target states are already reachable:

| State | Today |
|---|---|
| exactly one block / remembered block | adopted silently, line shows it |
| several blocks, no matching scope | inline candidate picker |
| no block at all | deferred target: dispatch **block-less**, block taken from the script after extraction (#829) |
| a block exists, but the script names a *different* one | **nothing** — the existing block wins and the script's block is only a mismatch hint (#827) |

The block-less dispatch is the missing capability's entire backend: `POST
/v1/ai-import/scripts|schedules` accepts an absent `X-Active-Block` with a
mandatory `X-Declared-Season` (#829), a job stores `block_id = NULL` and a
season-only target snapshot, `PUT /v1/ai-import-jobs/{id}/target` attaches the
block once, and the apply refuses an unattached target (`409
ai-import.target-missing`).

On the client the adoption is equally present: `ScriptBlockScope.targetBlockUnset`
is true for such a job, and the preview's target card adopts the script's block
on its own — the existing block carrying that number is attached, otherwise a
block with that number is created and then attached (`_scheduleAutoAdopt`,
`_attach`, `_create`).

The one thing that is *derived* rather than offered is the choice itself:

```dart
// import_submit_screen.dart, _SubmitButtonState
bool get _isBlockLess => widget.seasonHasNoBlock && widget.target == null;
```

A season that has a block can therefore never dispatch block-less, which is
exactly the reported case.

## Goals / Non-Goals

**Goals:**

- Make "the script's block is my target" a **choice** on the submit card, per
  dispatch, without changing any wire contract or backend behaviour.
- Keep one visible truth: the target line, the submit guard, and the
  `X-Active-Block` / `X-Declared-Season` headers must not contradict each other.
- Reuse the existing adoption path instead of describing a second one.

**Non-Goals:**

- Reading the script's block on the **submit** screen. The number exists only
  after extraction (`AiImportProgress.block_number`), so the card cannot name
  `Block 98` before the upload — promising it there would be a fabricated fact.
- Switching the *ambient* scope (the shell's block pill) as a side effect.
- Changing the preview's adoption mechanics, the backend, or the OpenAPI
  contract.
- An offline queue or a retry-after-failure redesign of the upload.

## Decisions

### D1 — A per-dispatch intent notifier, not a mode and not a scope mutation

A `Notifier<bool>` (`aiImportExtractBlockProvider`) lives next to
`pendingDocumentProvider` in `import_submit_controller.dart`; `true` means "this
dispatch takes its block from the script".

*Alternative: clear `activeBlockProvider`.* Rejected. That provider is the
shell's block pill and the target of every other screen; unsetting it to express
one import's intent would silently re-target unrelated surfaces, and a failed
upload would leave the app without a block the user still sees selected.

*Alternative: an enum mode with a "scoped / extracted" state machine.* Rejected
as over-modelling: there is exactly one bit, and the card already derives
everything else from the resolution.

The intent is **cleared** wherever the pending document is cleared (kind switch,
successful dispatch), so a stale flag can never turn a later dispatch block-less
behind the user's back — the review finding of #829, kept true.

### D2 — Offered whenever a season is known and the "no block" arm is not active

In the empty arm (`BlockScopeResolution.isEmpty`) the block-less dispatch is the
*only* target that exists and already applies with zero taps (#829 follow-up); a
toggle there would be a no-op that suggests an alternative that does not exist.
Everywhere else — a resolved block, candidates, or a failed block list — the
option is offered, because it depends on no block list at all (that is its
whole point).

### D3 — The card states the deferred target while the intent is active

With the intent set, the line renders `{season} · Block unbekannt`
(`aiImportTargetUnknownBlock`) plus the existing `aiImportTargetBlockLess` hint,
and the extract action turns into the **undo** that restores the resolved line.
The alternative — leaving `Block 1` on screen while dispatching block-less — is
the drift #771 exists to forbid: the user would read a target the request does
not carry. The ambient scope is untouched, so the undo needs no restore logic.

### D4 — The dispatch reads the same flag the card renders

`_SubmitButton` computes `blockLess = extractIntent || (seasonHasNoBlock &&
target == null)` and passes it to `submit(...)`. The existing controller path is
unchanged: `blockLess` suppresses `X-Active-Block` through the established
per-request interceptor opt-out, still requires a season
(`ai_import.scope_missing`), and skips the scope-mismatch guard because there is
no block to contradict the declared season.

### D5 — Adoption after extraction is *reused*, not re-implemented

A block-less job makes `ScriptBlockScope.targetBlockUnset` true, and the
preview's `_PreviewTargetCard` already does the whole job: it matches the
script's number against the season's block list, attaches the match, or creates
the block with that number (no dates — the script states none) and attaches the
acknowledged id. Re-specifying that flow here would create a second, divergent
copy of the same rules.

A script that states **no** block keeps the manual affordances in the preview
(pick an existing block, or create one); no number is invented on either side.

### D6 — Copy: "Block extrahieren" names what happens, honestly

The label is the reporter's own wording, and it is exact enough: the block is
taken from the extracted script, not from the current scope. The card hint
carries the *when* (`nach dem Hochladen`) and the two possible outcomes
(übernehmen oder anlegen), because at submit time neither the number nor the
season's block list can decide between them.

## Risks / Trade-offs

- **The user expects the block number before uploading** → the hint states that
  the block is decided *after* the upload, and the preview names it as soon as
  the job reports it. The card never prints a number it has not received.
- **Extraction yields no block** (a document whose header states none) → the job
  stays block-less and the apply refuses without a target (`409
  ai-import.target-missing`); the preview's manual affordances are the way out,
  unchanged from #829.
- **Repeated uploads of the same document**: the dedup key is
  `user|kind|format|document-digest` (no block), so the block-less dispatch does
  not break duplicate detection — the second upload answers the duplicate
  callout as before.
- **Episode-number collisions** in a newly created block (numbers are
  project-unique) stay a visible `409 episode.number-already-exists` at apply
  time — a pre-existing outcome of #829's adoption, not introduced here.
- **A stale intent** would silently drop the resolved block. Mitigated by the
  single reset points (D1) and a widget test that asserts the default path still
  sends `X-Active-Block`.
