## 1. Core — draft model

- [x] 1.1 Add `DraftCostume { character_name, description, source_quote }` to
      `crates/core/src/ai/preview.rs` and export it from `ai::mod`
- [x] 1.2 Add `costumes: Vec<DraftCostume>` to `DraftScene` with
      `#[serde(default)]` so stored previews from before this change still
      deserialise (BREAKING per proposal: newer previews lose the field on an
      older binary)
- [x] 1.3 Grounding helper `verify_draft_costumes(scene, chunk_text)`: drops a
      costume whose `source_quote` is absent from the supplied chunk and
      returns it as a `RejectedCostume` instead of letting it reach the reviewer
- [x] 1.4 A costume whose `character_name` is not in the same draft scene's
      `characters` is dropped with `RejectedCostumeReason::UnlistedCharacter`
- [x] 1.5 Unit tests for both rejection paths (ungrounded quote, unlisted
      character), plus empty-quote, case-insensitive matching, the
      outline-without-costumes case, and `serde(default)` compatibility for a
      stored preview without the field

## 2. Core — apply plan

> **Amended before implementation (design D7).** Characters are NOT planned
> per draft row. A figure is deduplicated across the WHOLE preview by a
> normalised name identity (`character_identity` = trim + lowercase + collapse
> internal whitespace), because a live 93-page import named 268 figure mentions
> over 131 scenes: keying per row would have created hundreds of duplicate
> `Character` aggregates and destroyed costume continuity (ADR-019). Costume
> ordinals stay per row, so two costumes of one figure in one scene remain
> distinct mapping rows.

- [x] 2.1 Add `CharacterApplyPlan { ordinal, name, identity }` and
      `CostumeApplyPlan { ordinal, character_identity, character_name,
      description, source_quote }` next to the existing `SceneApplyCommand`
- [x] 2.2 Extend `plan_scene_apply` into a `ScriptApplyPlan` that plans each
      row's scene command, the row's figures against the preview-wide identity
      map, and — for every ACCEPTED costume — its binding to that identity
- [x] 2.3 Tests: figures planned once per identity across rows; no figures for
      an outline row; a costume planned only when its character is planned; a
      reviewer-rejected costume is not planned; identity normalisation
      (case/whitespace) collapses the CAPS-and-mixed forms a script uses
- [x] 2.4 `ApplyMapping` carries `costume_decisions: Vec<CostumeDecision>`
      (`#[serde(default)]`, additive) so a pre-costume client still deserialises;
      an absent ordinal means accepted

## 3. Infra — character and costume creation in the apply worker

- [x] 3.1 Extend the apply worker with `character_commands` and
      `costume_commands` ports (today it only has scene/shooting-day/scene-shoot)
- [x] 3.2 Dispatch `CreateCharacter` once per figure identity BEFORE the costumes
      that bind to it, and persist the character id in the mapping row so a
      retry and a re-apply reuse it instead of creating a duplicate
- [x] 3.3 Dispatch the costume chain per planned costume: `CreateCostume`
      (unassigned, season resolved from the request) → `UpdateCostumeNotes`
      (the extracted description; `CreateCostume` has no description field) →
      `AssignCostumeToCharacter`. The stored aggregate version is the PHASE
      RECORD of a crashed apply (1 created, 2 +notes, 3 bound), so a retry
      re-drives only the steps above it — no duplicate costume, no double bind
      (design D8)
- [x] 3.4 Order test: the character command is dispatched before the costume
      binding for the same row
- [x] 3.5 Re-apply test: a second apply creates no duplicate character and no
      duplicate costume for the same preview
- [x] 3.6 A costume whose character could not be created is reported as NOT
      applied with a typed reason and does not create an unbindable costume
- [x] 3.7 A domain refusal of one row is reported and the apply CONTINUES; only
      an infrastructure outage fails the apply so it can be retried
      (`is_infra_outage`)

## 4. Persistence — mapping rows

- [x] 4.1 Migration `20260927000001_ai_import_mapping_key` adds
      `ordinal INTEGER NOT NULL DEFAULT 0` and widens the primary key to
      `(preview_id, draft_ref, aggregate_kind, ordinal)` (additive; existing
      rows default to ordinal 0)
- [x] 4.2 Persist and read character + costume mapping rows keyed by that full
      tuple; `find()` takes the ordinal and `derive_id()` hashes the whole key
- [x] 4.3 Re-import suggestion reads every kind back, so an updated document can
      re-suggest the prior mapping (figure rows are addressed by the
      `@character/<identity>` ref — the `@` prefix keeps them disjoint from
      numeric scene draft refs by construction)

## 5. Infra — provider contract

- [x] 5.1 Extend `DraftSceneSchema` in `crates/infra/src/ai/client.rs` with the
      costume list (per-field descriptions) so the schema sent to the provider
      carries it
- [x] 5.2 Run the grounding check in `workers.rs` for every returned costume
      before it is pushed into the preview context, against the EXACT
      `source_text` bytes handed to the model
- [x] 5.3 Test: a model response with an ungrounded costume yields a scene
      without that costume plus an uncertainty
- [x] 5.4 Grounding folds whitespace runs and case before comparing (a quote
      taken across a line wrap has a space where the document has a newline);
      a quote that is genuinely absent still fails

## 6. Prompt + configuration

- [x] 6.1 Ship the hardened script prompt as the deployment default and REMOVE
      the interim `summary`-overflow instruction for costumes, replacing it with
      the `<costumes>` extraction-field instruction
- [ ] 6.2 Verify via a small live run that a costume lands in `costumes` (not in
      `summary`) using a script block that states one
- [x] 6.3 Configuration surface: `AiConfigView.stored_prompt_kinds` reports the
      kinds whose stored prompt OVERRIDES the deployment default (blank stored
      text counts as no override — `resolve_prompt` treats blank and absent
      identically), the Flutter config screen says so per kind, and offers a
      reset that writes the fetched `GET /v1/ai-import/defaults` text into the
      editor (saving persists it; a reset never dispatches behind the user's
      back, and is disabled when the defaults could not be fetched)

## 7. API + client

- [x] 7.1 Add the costume fields to the apply request/response DTOs
      (`CostumeDecision`, `UnappliedCostume` + reason enum, `created_characters`,
      `created_costumes`) and `stored_prompt_kinds` to `AiConfigView`; resolve
      `season_id` at the API edge (episode → block → season) and bound the
      decision list against the preview's costume count (DoS guard)
- [x] 7.2 `UPDATE_OPENAPI=1 cargo test -p api --test openapi_drift` and commit
      the regenerated `backend/openapi.yaml`
- [x] 7.3 `bash scripts/regen-client.sh` to regenerate `vendor/breakdown_api`
      and commit the diff
- [x] 7.4 Review UI: a costume checkbox per extracted costume, showing the
      quoted source fragment next to the extracted description, decided
      INDEPENDENTLY of its scene row; a server-dropped costume stays visible as
      an uncertainty note and does not gate the apply (design D9); the apply
      outcome names un-applied costumes with a reason localized from the typed
      wire enum

## 8. Verification

- [x] 8.1 `cargo test -p breakdown_core -p infra -p api` green (all targets ok,
      incl. the Postgres contract tests against the dev stack). A preceding
      `cargo test --workspace` showed 2 failures in
      `integration-tests/command_adapter_tests` with `redis error: timed out`
      under 90-binary parallel load; both pass in isolation (16/16) — an
      environment flake, not a code defect. `cargo fmt --check` and
      `cargo clippy --all-targets --all-features -- -D warnings` (the
      pre-commit gate, workspace-wide) are clean.
- [x] 8.2 `cargo clippy --all-targets --all-features -- -D warnings` clean
8.3–8.5 and 6.2 require a live run against a real provider, which spends real
money (a 93-page script is ~85 paid chunk calls). They are deliberately left for
a manual run. Prerequisites, in order:

1. Start the API against the dev stack so the mapping migration applies:
   `DATABASE_URL=postgres://postgres:postgres@localhost:5432/breakdown \
   SIERRADB_URL=redis://127.0.0.1:9090/?protocol=resp3 cargo run --bin api`.
   Then verify `\d ai_import.projection_ai_import_mapping` shows `ordinal` and
   `PRIMARY KEY (preview_id, draft_ref, aggregate_kind, ordinal)`. The dev DB is
   at `20260926000001`, so this migration has NOT run anywhere yet.
2. Configure a provider through `scripts/enable-dev-ai-import.sh` (the key goes
   to the vault; never into the repo).
3. Import the German script → review the preview → apply → re-apply. Check the
   six things the change exists for: costumes present with their quotes; one
   `Character` per figure identity across the whole preview; each costume bound
   to the right one; the description present as costume notes; re-apply creating
   nothing; a rejected costume row never becoming a `Costume`.

- [ ] 8.3 Live re-import of the German production script: costumes present in
      the preview, `draft_ref` unique, re-apply creates no duplicates
- [ ] 8.4 A script without any costuming still imports successfully with an
      empty costume list (the "Block 100 / Tag 1" outline case)
- [ ] 8.5 An English-convention script (INT./EXT.) still imports unchanged —
      the German heading support must not regress it

## 9. Follow-ups found while implementing

- [x] 9.1 REGRESSION FROM THIS BRANCH, now fixed: `511baaa9` (photo pipeline)
      made the costume detail screen fetch the enriched single-costume row on
      open, but its widget-test fakes do not override `CostumeRepository
      .getAndCache` — so the fetch fell through to the REAL Dio client.
      `selecting a tile opens the editor on the first screen` died with
      "A Timer is still pending even after the widget tree was disposed";
      reproduced after `511baaa9`, green at its parent commit. (My first
      reading — "pre-existing on main, unrelated" — was wrong: I had compared
      against `a53ee332`, which already CONTAINS that commit.)
      Fixed by scripting the detail read in both costume test fakes. Default for
      an UNSCRIPTED read is a failed read (list row keeps rendering), not a
      photo-less enriched row: the latter would silently replace a list row that
      carries photos and empty the gallery — which is how the first version of
      this fix broke two other tests.
- [x] 9.2 The behaviour `511baaa9` shipped was itself untested. Now covered:
      one fetch per open; the gallery renders the photos of the FETCHED row and
      drops the empty affordance; a failed fetch keeps the list row (no crash, no
      invented gallery, no blind retry).
- [x] 9.3 `costumes_controller.dart` was unformatted at `511baaa9` (the repo's
      `dart format --set-exit-if-changed` gate fails on it); fixed.
- [ ] 9.6 OBSERVED while fixing 9.1 (photo bounded context, not this change):
      when variant generation FAILS, the thumbnail saga's failure path marks
      `Thumb`/`Medium` as `Failed` but leaves the `Original` variant `Pending`
      forever — measured in `photo_round_trip` (`Medium:Failed, Original:Pending,
      Thumb:Failed`). A photo whose original cannot be normalized therefore
      reports a variant that is neither ready nor failed. Whether `Pending` is the
      right terminal state there (vs. `Failed`, or leaving the row absent) is a
      photo-context decision; the round-trip test now waits only on the two
      variants the saga actually owns, so it does not depend on the answer.
- [ ] 9.4 The AI-import screens predate the per-screen design-spec convention
      (`docs/design/screens/`): there is no wireframe spec for the import /
      preview / apply screens, so the costume review surface is documented in the
      glossary only. Authoring the missing specs is a separate change.
- [ ] 9.5 The script-preview branch of `AiPreviewScreen` has no golden (only the
      merged-preview shape does). The costume rows are covered by semantic widget
      tests, matching how the rest of that branch is covered; a golden needs a
      fixture with costumes and a CI-verified regeneration.
