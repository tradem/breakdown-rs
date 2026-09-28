## Context

The script import extracts a scene's characters but has no field for costumes:
`DraftScene` is `{ draft_ref, scene_number, location, mood, summary,
script_day, characters }`. The provider is handed a JSON schema that mirrors
exactly that shape, so a model that recognises a costume has nowhere to put it
and `serde_json` drops it silently.

Evidence from the live device test (93-page German production script, 85 chunks,
~7 min, 268 characters extracted over 131 preview scenes):

- **0 costumes** — the field does not exist.
- 55 of 131 `draft_ref` values were invented placeholders (`scene_1`, `scene_2`).
  Because the apply step resolves a row with
  `mappings.find(|m| m.draft_ref == draft_ref)`, a repeated reference sends
  several preview rows to the *same* decision — a correctness bug that the
  costume work must not inherit.
- Hardening the default prompt alone (done in this session, shipped with the
  `ai_costume_extraction` spec) makes the model emit the costume **into
  `summary`** ("trägt einen leicht ölverschmierten Mechaniker-Overall").
  Verified live. That is a lossy interim carrier, not a data model.

The domain already has the right shape: a `Costume` aggregate bound to a
`Character` through `character_id` only (`costume-character-binding` spec), with
`CreateCostume` + `AssignCostumeToCharacter` as the creation path. The user
chose the "Figuren-Kostüme-Konstellation" (character-costume constellation)
explicitly: a costume belongs to the figure, which is what costume continuity
means in this application.

## Goals / Non-Goals

**Goals:**
- A dedicated, reviewable costume structure per draft scene, traceable to the
  quoted script fragment it came from.
- Apply that creates the row's **characters** and then the **costumes** bound to
  them, through the existing costume commands. Character creation is **new apply
  behaviour** — it does not exist today — and is therefore part of this change.
- Idempotent re-apply at character- and costume-row granularity.
- Server-owned `draft_ref` (already implemented this session) so the costume
  rows inherit a collision-free key.

**Non-Goals:**
- Requisition/prop extraction as a first-class field (recorded in `summary` for
  now; a `props` field is a separate change).
- Costume *categories* or season wardrobe reuse — the costume enters the domain
  as a plain, unassigned `Costume` the user can categorise later.
- Costuming for the schedule-side import.
- Any inference the script does not state. Missing costuming stays missing.

## Decisions

**D1 — Costume rides on the draft scene, not on a separate LLM call.**
`DraftScene` gains `costumes: Vec<DraftCostume>`; the same chunk prompt that
already extracts characters also extracts costumes. Alternative: a second
per-scene call dedicated to costuming. Rejected — it doubles paid calls for
information that is in the same text window, and the observed 7-minute/85-chunk
runtime makes that a poor trade. The bound in
`ai-costume-extraction` (no second paid pass) follows from this.

**D2 — `DraftCostume { character_name, description, source_quote }`.**
Flat, three strings, no nested object. `character_name` is resolved against the
scene's own `characters` list at extraction time (a costume for an unlisted
character is rejected as an uncertainty, per spec). `source_quote` makes the
review verifiable and gives the no-invention check something concrete to verify
against — the model is not trusted to have grounded the entry, the server
checks. Alternative: `character_id: Option<Uuid>` — rejected, the LLM has no
ids and the write side must not resolve ids from a projection (CQRS boundary).

**D3 — Apply reuses `CreateCostume` + `AssignCostumeToCharacter`, unassigned
first.** `CreateCostume` takes no `character_id`; binding is the separate
`AssignCostumeToCharacter` command. Creating unassigned and then binding keeps a
single creation path, reuses existing aggregate validation, and leaves an
orphan detectable ("unassigned costume") instead of silently unbound. The same
shape is already used for photo commands on repertoire-scoped costumes
(issue #532), so the precedent is in the codebase.

**D4 — Mapping rows gain `aggregate_kind = 'costume'` plus an ordinal.**
Today `(preview_id, draft_ref)` identifies a row. Two costumes of the same
character in one scene would collide, so the mapping key becomes
`(preview_id, draft_ref, costume_ordinal)`. Alternative: a synthetic
`draft_ref` per costume — rejected, it would corrupt the scene/apply join that
`draft_ref` already drives. This is the one schema migration in the change.

**D5 — The grounding check is server-side, not prompt-side.**
The prompt forbids invention, but a prompt is an instruction, not a
guarantee. The server verifies that each returned `source_quote` occurs in the
supplied chunk text; a costume that fails is dropped and recorded as an
uncertainty. This is the difference between "the model usually does not
hallucinate" and "a hallucinated costume cannot reach the reviewer".

**D6 — A stored configuration prompt keeps precedence, and the surface says so.**
Observed live: a configuration stored the previous three-line prompt and
silently ignored a hardened default, which invalidated a whole test round.
The deployment default remains the fallback; the configuration UI must
indicate that a stored prompt is in effect and offer a reset to the default.

**D7 — A figure is deduplicated across the WHOLE preview by normalised name
identity, not per draft row.** The task text originally said "characters planned
per row". Measured against a live 93-page German import, that is wrong: 268
figure mentions over 131 scenes, most of them the same ~40 people repeated, and
the script writes a name partly in CAPS (slug lines) and partly mixed-case.
Per-row planning would have created hundreds of duplicate `Character`
aggregates and destroyed costume continuity (ADR-019) — a costume bound to
"renee sanders #7" is useless to the wardrobe department. The planner therefore
keys figures on `character_identity(name)` (trim + lowercase + collapse internal
whitespace) over the entire preview and addresses the mapping row as
`@character/<identity>`; the `@` prefix makes figure refs disjoint from scene
draft refs (which always start with a digit) by construction. Costume ordinals
stay PER ROW (`(preview_id, draft_ref, 'costume', ordinal)`), because two
garments of one figure in one scene are genuinely two review items. Alternative:
per-row characters with a server-side merge pass — rejected, the merge would
have to happen after the reviewer edited the preview, i.e. it cannot be
expressed in the mapping table at all.

**D8 — The costume apply chain is three commands and the stored aggregate
version is its phase record.** `CreateCostume` (unassigned) →
`UpdateCostumeNotes` (carries the extracted description — `CreateCostume` has no
description field) → `AssignCostumeToCharacter`. A crash between steps leaves
the mapping row's version at 1, 2 or 3, and a retry re-drives ONLY the steps
above the stored version: no duplicate costume, no second assignment, no
re-written notes. The optimistic-locking semantics were verified explicitly
(they were an open question before implementation): binding a freshly created
costume uses the version `CreateCostume` returned, and a replayed bind is
refused as a version mismatch rather than performing a second assignment. A
whitespace-only description skips the notes step (`CostumePhases.has_notes`) so
the chain does not issue a command the aggregate would reject.

**D9 — `UncertaintyKind` splits blocking ambiguities from non-blocking drop
reports.** A field ambiguity must block the apply (the reviewer has not resolved
it). A costume the grounding check DROPPED must not: previews are immutable and
there is no dismiss mechanism, so blocking on every dropped row would make one
bad costume reject an entire 85-chunk paid import that the reviewer has already
accepted. `UncertaintyKind::{FieldAmbiguity, DroppedRow}` encodes that; the
client renders `DroppedRow` as information and keeps the apply dispatchable.
`#[serde(default)]` maps an old blob (no `kind`) to `FieldAmbiguity`, so stored
previews block exactly as they did before this change.

**D10 — A row the apply could not finish is reported with a typed reason.** The
200 response carries `created_characters`, `created_costumes` and
`unapplied_costumes[]` with a `reason` enum
(`character_not_planned` / `character_unavailable` / `create_rejected` /
`notes_rejected` / `binding_rejected`). The client localizes on that enum and
never on prose, so a partially applied row cannot read as a fully applied one.

## Risks / Trade-offs

[Costumes silently dropped by a model that ignores the prompt] → D5 drops
anything not grounded and D9 records the drop as a visible `DroppedRow`
uncertainty, so a failure shows up as *missing* (with its reason) rather than as
wrong data. The interim `summary`-overflow carrier was REMOVED with the
hardened prompt (task 6.1): keeping it would have re-introduced unstructured
costume text the reviewer cannot decide on.

[Duplicate costumes on re-apply] → D4's mapping row per costume ordinal plus
D7's preview-wide figure identity; covered by re-apply tests in the spec and at
task level (3.5).

[Apply partially applied: costume created, binding rejected] → the costume
stays unassigned (visible, correctable), the stored version records the phase
(D8), the retry resumes above it, and the 200 names the row with a typed reason
(D10).

[Figure identity over-collapses two genuinely different characters] → the
normalisation is deliberately narrow (case + whitespace only; no fuzzy match, no
surname stripping), and the reviewer still sees every row. Two figures that
differ by more than case/spacing stay separate aggregates — the conservative
direction, since a wrong MERGE is invisible to the wardrobe department while a
duplicate is.

[Prompt growth raises input-token cost per chunk] → the script prompt grows by
~2.9 kB. Accepted: input tokens are far cheaper than a second pass, and the
prompt is per-configuration editable so an operator can trim it.

[Preview blob compatibility] → `DraftScene.costumes` is `serde(default)` so an
older stored preview still deserialises; a newer preview read by an older
binary would lose the field, which is why the change is marked BREAKING in the
proposal.

[Two `scene_N`-style placeholder classes of reference] → already eliminated
server-side by `stable_draft_ref`; the costume rows inherit that key.

## Migration Plan

1. Migration adding the mapping discriminator/ordinal (additive; existing rows
   keep `aggregate_kind` for their current value and ordinal 0).
2. Core types and the JSON-schema mirror, then infra apply, then API DTOs.
3. `UPDATE_OPENAPI=1 cargo test -p api --test openapi_drift`, then
   `scripts/regen-client.sh` for the generated Dart client.
4. Deploy: new previews carry costumes; old previews apply unchanged (field
   defaults to empty).
5. Rollback: the mapping columns are additive and ignored by the previous code
   path; reverting the binary leaves previews intact.

## Open Questions

- Should a costume whose character was skipped be offered as an *unassigned*
  costume for later binding, or dropped with a report line? The spec currently
  requires the report; a follow-up may add the unassigned variant.
- Props as a first-class field: same shape as D1/D2, deferred to its own change.
