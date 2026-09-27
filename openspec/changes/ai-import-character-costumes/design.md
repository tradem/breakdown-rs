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

## Risks / Trade-offs

[Costumes silently dropped by a model that ignores the prompt] → the
`summary` interim carrier keeps the text observable in the preview, and D5
drops anything not grounded, so a failure shows up as *missing* rather than as
wrong data. Verified: the hardened prompt already produces the description.

[Duplicate costumes on re-apply] → D4's mapping row per costume ordinal;
covered by a re-apply scenario in the spec and a task-level test.

[Apply partially applied: costume created, binding rejected] → the costume
stays unassigned (visible, correctable) and the apply reports the row as
partially applied; the retry reuses the mapping id rather than creating a
second costume.

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
