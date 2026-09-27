## 1. Core — draft model

- [x] 1.1 Add `DraftCostume { character_name, description, source_quote }` to
      `crates/core/src/ai/preview.rs` and export it from `ai::mod`
- [x] 1.2 Add `costumes: Vec<DraftCostume>` to `DraftScene` with
      `#[serde(default)]` so stored previews from before this change still
      deserialise (BREAKING per proposal: newer previews lose the field on an
      older binary)
- [x] 1.3 Grounding helper `verify_draft_costumes(quote, chunk_text)`: drops a
      costume whose `source_quote` is absent from the supplied chunk and
      returns it as a `RejectedCostume` instead of letting it reach the reviewer
- [x] 1.4 A costume whose `character_name` is not in the same draft scene's
      `characters` is dropped with `RejectedCostumeReason::UnlistedCharacter`
- [x] 1.5 Unit tests for both rejection paths (ungrounded quote, unlisted
      character), plus empty-quote, case-insensitive matching, the
      outline-without-costumes case, and `serde(default)` compatibility for a
      stored preview without the field

## 2. Core — apply plan

- [ ] 2.1 Add a `CharacterApplyPlan` (name, per draft row) and a
      `CostumeApplyPlan` (character reference, description, source_quote,
      ordinal) next to the existing `SceneApplyCommand`
- [ ] 2.2 Extend `plan_scene_apply` to plan the row's characters and, for each
      accepted costume, its binding to the character planned in the SAME row
- [ ] 2.3 Tests: characters planned for a row with characters; no characters
      planned for an outline row; costume planned only when its character is
      planned in the same row

## 3. Infra — character creation in the apply worker

- [ ] 3.1 Extend the apply worker with `character_commands` and
      `costume_commands` ports (today it only has scene/shooting-day/scene-shoot)
- [ ] 3.2 Dispatch `CreateCharacter` per planned character BEFORE the costumes of
      the same row, and persist the character id in the mapping so a costume can
      bind to it
- [ ] 3.3 Dispatch `CreateCostume` (unassigned) + `AssignCostumeToCharacter` per
      planned costume, using the character id created in 3.2
- [ ] 3.4 Order test: the character command is dispatched before the costume
      binding for the same row
- [ ] 3.5 Re-apply test: a second apply creates no duplicate character and no
      duplicate costume for the same preview
- [ ] 3.6 A costume whose character could not be created SHALL be reported as not
      applied (with the reason) and SHALL NOT create an unbindable costume

## 4. Persistence — mapping rows

- [ ] 4.1 Migration adding the character/costume discriminator + ordinal to
      `projection_ai_import_mapping` (additive; existing rows default to their
      current kind and ordinal 0)
- [ ] 4.2 Persist and read character + costume mapping rows keyed
      `(preview_id, draft_ref, ordinal)` with `aggregate_kind` in
      `{character, costume}`
- [ ] 4.3 Re-import suggestion reads both new kinds back so an updated document
      can re-suggest the prior mapping

## 5. Infra — provider contract

- [ ] 5.1 Extend `DraftSceneSchema` in `crates/infra/src/ai/client.rs` with the
      costume list so the schema sent to the provider carries it
- [ ] 5.2 Run the grounding check in `workers.rs` for every returned costume
      before it is pushed into the preview context
- [ ] 5.3 Test: a model response with an ungrounded costume yields a scene
      without that costume plus an uncertainty

## 6. Prompt + configuration

- [ ] 6.1 Ship the hardened script prompt (done this session) as the deployment
      default and REMOVE the interim `summary`-overflow instruction for costumes,
      replacing it with the `costumes` field instruction
- [ ] 6.2 Verify via a small live run that a costume lands in `costumes` (not in
      `summary`) using a script block that states one
- [ ] 6.3 Configuration surface: indicate that a stored prompt overrides the
      deployment default, and offer a reset-to-default action

## 7. API + client

- [ ] 7.1 Add the costume fields to the apply request/response DTOs and to
      `AiConfigView`-adjacent prompt payloads
- [ ] 7.2 `UPDATE_OPENAPI=1 cargo test -p api --test openapi_drift` and commit
      the regenerated `backend/openapi.yaml`
- [ ] 7.3 `bash scripts/regen-client.sh` to regenerate `vendor/breakdown_api`
      and commit the diff
- [ ] 7.4 Review UI: costume decision per row, showing the quoted source
      fragment next to the extracted description

## 8. Verification

- [ ] 8.1 `cargo test -p breakdown_core -p infra -p api` green
- [ ] 8.2 `cargo clippy -p breakdown_core -p infra -p api --all-targets` clean
- [ ] 8.3 Live re-import of the German production script: costumes present in
      the preview, `draft_ref` unique, re-apply creates no duplicates
- [ ] 8.4 A script without any costuming still imports successfully with an
      empty costume list (the "Block 100 / Tag 1" outline case)
- [ ] 8.5 An English-convention script (INT./EXT.) still imports unchanged —
      the German heading support must not regress it
