## Why

The AI script import extracts a scene's **characters** but has nowhere to put
its **costumes**: `DraftScene` carries `characters: Vec<String>` and nothing
else, so the model cannot return a costume even when the script states one
plainly. Measured on a 93-page German production script ("Die jungen Ärzte",
ARD), the import produced 268 characters across 131 preview scenes and **zero**
costumes — while the source text names them explicitly, e.g. "Renee Sanders (39)
eine wunderschöne Frau, deren leicht **ölverschmierter Mechaniker-Overall**
ihre elegante Erscheinung nicht verbergen kann".

The information is in the document and the model already recognises it: with a
hardened NER-style prompt the same scene returns "trägt einen leicht
ölverschmierten Mechaniker-Overall". Today that text only survives because it
is crammed into the scene `summary` — a lossy workaround, not a data model.
Costuming is the core input of this application (ADR-019: costume continuity
across a season), so an imported screenplay that silently drops its costuming is
only half imported.

## What Changes

- **BREAKING** — `DraftScene` gains a `costumes: Vec<DraftCostume>` field
  (`character_name`, `description`, `source_quote`), mirrored in the JSON schema
  the provider is given, in the stored preview blob, and in the apply DTOs.
  Wire-compatibility is preserved (additive, `serde(default)`), but the
  `ScriptContext` JSON contract changes for stored previews.
- **Prompt contract:** the default script prompt (`config/default_ai_prompts.toml`)
  specifies costume extraction as NER over three named evidence sources — a
  character parenthetical (`ANNA (30, Lederjacke)`), a `Kostümbild` note, and
  clothing attached to a person in the action line — with accessories counted
  as costume and an explicit no-invention rule. The `summary`-overflow
  workaround introduced with this change is removed from the prompt.
- **Apply:** a preview row with a costume decision dispatches the **existing**
  `CreateCostume` + `AssignCostumeToCharacter` commands against the character
  resolved for the same draft row — the "Figuren-Kostüme-Konstellung" the
  domain already models (`Costume.character_id` is the only binding,
  `costume-character-binding` spec). No new aggregate, no new scope field.
- **Apply mapping:** `projection_ai_import_mapping` gains
  `aggregate_kind = 'costume'` rows, keyed by `(preview_id, draft_ref,
  ordinal)` so two costumes of the same character in one scene stay distinct
  and re-apply stays idempotent.
- **Prompt-default trap, documented + surfaced:** a stored configuration prompt
  silently overrides the deployment default (observed live: a config kept the
  previous three-line prompt and silently ignored a hardened one). The
  configuration surface SHALL indicate that stored prompts take precedence.

## Capabilities

### New Capabilities
<!-- Capabilities being introduced. Replace <name> with kebab-case identifier. Each creates specs/<name>/spec.md -->
- `ai-costume-extraction`: NER-style extraction of character costumes from
  screenplay text (evidence sources, grounding/no-invention, accessories) and
  the resulting draft-scene costume structure.

### Modified Capabilities
<!-- Existing capabilities whose REQUIREMENTS are changing. Each needs a delta spec file. -->
- `ai-import`: the preview carries costumes, and the apply dispatches
  `CreateCostume` + `AssignCostumeToCharacter` with its own mapping rows and
  idempotency guarantees.
- `costume-character-binding`: AI-created costumes are created unassigned and
  then bound via `AssignCostumeToCharacter`, so the `character_id`-only binding
  rule gets an explicit creation-order requirement.

## Impact

- **Backend `core`:** `ai::DraftScene` (+ new `DraftCostume`), `SceneApplyCommand`
  gains a costume variant, `plan_scene_apply` resolves costume rows, preview
  blob version, `Stable` ref generation now also numbers costume rows.
- **Backend `infra`:** `DraftSceneSchema` (JSON-schema mirror sent to the
  provider), apply worker, `projection_ai_import_mapping` persistence,
  `merge_from_input`/`MergedPreview` costuming, a migration for the mapping
  discriminator.
- **Backend `api`:** apply request/response DTOs, `openapi.yaml` (code-first
  drift test), the AI-import defaults endpoint serves the new prompt.
- **Client (generated):** `vendor/breakdown_api` must be regenerated via
  `scripts/regen-client.sh`; the review UI gains a costume decision per row.
- **Docs:** AI-import instructions rule, the photo/costume spec cross-references.
- **No new LLM cost per call** for scenes without costuming; the prompt grows by
  roughly 2.9 kB, which slightly raises input tokens per chunk.
