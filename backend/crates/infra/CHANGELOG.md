<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: space-bunny-free (opencode-go) -->
<!-- Co-authored-by: deepseek-v4-flash (neuralwatt) -->
<!-- Co-authored-by: deepseek-v4-flash (opencode-go) -->
<!-- Co-authored-by: longcat-2.0-free (opencode) -->
<!-- Co-authored-by: hy4-preview (opencode-go) -->
<!-- Co-authored-by: muse-spark-1.3-contributor (opencode-go) -->
<!-- Co-authored-by: omen-alpha (opencode-go) -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# Changelog

All notable changes to the `infra` crate are documented here. Versioning
follows per-crate Semantic Versioning (ADR-020 D2); this changelog is the
crate-level companion to the release notes generated from conventional
commits (ADR-020 D5).

## [0.77.0] - Unreleased

### Added — durable chunk store and resume-on-retry (issue #871, workstream B)

- Migration `20261110000002_ai_import_chunk_resume`:
  `ai_import.ai_import_job_chunk` (PK `(job_id, chunk_index)`, FK cascade) plus
  `extraction_key` and `extraction_key_components` on the job row. A table rather
  than a JSONB column: one bounded insert per chunk instead of O(n²) bytes, and
  `updated_at` stays untouched — it is the retention clock, the payload-GC
  `ORDER BY` key and the ETA anchor `started_at` (#762).
- `PgAiImportChunkStore`: every write takes the job row `FOR UPDATE` first,
  because under READ COMMITTED a bare `INSERT … SELECT … WHERE status = 'running'`
  can read the old owner and still commit after another worker reclaimed the job
  and invalidated the set. The invalidation path takes the same lock in the same
  order. `ON CONFLICT (job_id, chunk_index) DO UPDATE` makes a chunk re-run repair
  itself by overwriting, so resume is idempotent and the usage sum counts one paid
  call per chunk.
- `load` deletes a tail beyond a hole (`#871 chunk resume hole at <index>`) and
  returns the prefix; `begin_extraction` compare-and-sets the fingerprint and
  deletes the whole set when it changed (`#871 chunk resume invalidated`).
- Terminal lifecycle writes delete the job's chunk rows in the SAME statement; a
  job that merely backs off keeps them — that is the resume. The payload-GC sweep
  deletes them with the blobs; `dev_reset` registers the table.
- The script import worker opens the chunk set, publishes `resumed_from`, feeds a
  stored chunk through the SAME merge body instead of re-requesting it, and `put`s
  a fresh chunk before the merge consumes it.
- Review follow-up from PR A: a `ProviderBreakerOpen` sentinel that arrives as an
  error (the client-internal guard can refuse a request inside an attempt) takes
  the HELD path instead of `mark_failed`.

## [0.76.0] - Unreleased

### Added — durable provider breaker, probe and hold sweeper (issue #871, workstream A)

- Migration `20261110000001_ai_import_provider_health`: the
  `ai_import.provider_health` table (one row per `(provider, model)`, three-value
  state CHECK, flap/`closed_at`/probe-lease columns) plus the additive job
  columns `breaker_provider`, `breaker_model`, `provider_hold` and
  `provider_hold_series_started_at`. The breaker key gets its own pair rather
  than the existing `provider`/`model` columns: those are the **telemetry**
  provenance of the attempt that produced the result, and `has_telemetry` is
  derived from `provider IS NOT NULL` — an enqueue-time snapshot there would make
  a job that recorded nothing report a telemetry summary of zeros.
- All four claim paths carry one predicate: only a `closed` breaker admits a
  claim. `retry_at` is deliberately not part of it (it is the probe schedule, not
  a claim gate).
- `mark_held` (retries untouched, no attempt row, breaker `retry_at` as
  `next_attempt_at`, series clock + derived `hold_deadline` in SQL), hold
  materialization/refresh, and the claim-free expiry that dead-letters at the
  job's own deadline with `state = expired` and exactly one attempt row.
- `infra::ai::provider_health::PgProviderHealth`: the core state machine applied
  as read → pure decision → compare-and-set, so the arithmetic has one source of
  truth. Every committed transition logs the `#871 provider breaker` marker.
- `infra::ai::provider_probe`: the recovery probe (catalog read for hosted
  providers with a donor job's own vaulted key, unauthenticated `/api/tags` for
  Ollama), lease → request outside any transaction → fenced result.
- `infra::ai::provider_watch`: the claim-free sweeper (materialize the holds the
  open-time write cannot reach + expire the overdue ones) under one advisory
  lock, `AI_IMPORT_PROVIDER_SWEEP_INTERVAL_SECS` (default 60).
- `dev_reset` registers `provider_health` before the job delete.

## [0.75.0] - Unreleased

### Changed — provider failures are provider-attributed, and the jobs list carries attempt history (issue #822)

- `classify_http_status_with_detail` (HTTP 429/5xx) and
  `classify_transport_error` (timeout/connect) now answer
  `llm_provider_unavailable` → `ai-import.llm-provider-unavailable`. Both are
  provider calls, so the recorded attempt names the dependency instead of "a
  service". The bounded provider-detail suffix is preserved, and the variants
  keep `ServiceUnavailable`, so retryability and the backoff schedule are
  untouched.
- Every non-provider dependency of the import pipeline keeps
  `domain.service-unavailable` (mapping DB, pricing read model, payload storage,
  and the catalog's own parse/client/DNS classifications). The catalog's and
  Ollama's provider HTTP/transport faults inherit the new code, because they
  genuinely are provider failures — a test pins both sides.
- `PgAiImportQueue::list_for_user` populates each row's `attempts` (newest first)
  for the whole page from ONE windowed query — **the same**
  `ATTEMPT_HISTORY_LIMIT` the single-job read uses, no N+1 — so a client derives
  the same degraded-provider state from a list row as from the single-job read.
  The shared bound is a correctness requirement: a client counts the consecutive
  newest provider-attributed attempts, so a shorter list window would make the
  compact row report fewer failures than the status card for the same job. A failed read serves empty histories with
  a warning (explanatory metadata never fails the list), matching the #864
  applied-episode derivation.
- Tests: the retryable statuses, the transport fault and the detail-carrying
  classification all pin the new code; a real-Postgres case records two
  consecutive provider attempts and one generic failure through `mark_failed` and
  asserts the list read publishes exactly those codes.

## [0.72.0] - Unreleased

### Changed — the apply claim gets an owner-scoped stamp (issue #863)

- Migration `20261106000002_ai_apply_claim_stamp` adds
  `ai_import_job.apply_claim_at TIMESTAMPTZ`: the instant the current run took
  the slot, written by the claim (and by a stealing claim) and by NOTHING else.
  The row's `updated_at` was the tempting shortcut — the claim stamps it too —
  but every run-scoped write bumps it, including a previous apply's post-apply
  summary, which lands after that apply released the slot. Judging the next
  owner by it understates a dead run's silence by the gap to that write and
  delays the steal by the same amount (review follow-up).
- `claim_apply_run` stamps `apply_claim_at` and its unpublished-owner branch now
  compares it: `OR (apply_progress IS NULL AND COALESCE(apply_claim_at,
  updated_at) < $3)`. The `COALESCE` is the rolling-deploy fallback: a claim made
  before the column existed keeps NULL there and is judged by the stamp it always
  used, so it is never more stealable than before. The payload branch
  (`apply_progress->>'updated_at'`) is untouched.
- `PgAiImportQueue::apply_run_state` selects `apply_claim_at` into
  `ApplyRunState::owner_claimed_at`, so the refused age and the steal decision
  read the same owner-scoped instant.
- Covered against real Postgres by three cases in
  `ai_import_job_progress.rs`: a late run-scoped write cannot extend a claim's
  window (new), a pre-stamp claim reports no age but stays protected (new), and
  the existing unpublished-claim steal test now forces the claim stamp.

## [0.70.0] - Unreleased

### Changed — the set-once statement is total and idempotent (review of #829)

- `set_target_once` now also requires `target_season_id IS NOT NULL`: a block
  number stored without its season pair would leave a target that no longer
  decodes. The state is unreachable today (every upload resolves a season), but
  the statement is the last line and is now total.
- The same block repeated is an idempotent success **before** the applied state
  is considered: a retry after the rows landed asks for nothing that is not
  already true, so it must not answer `AlreadyApplied` (a 409 the client renders
  as "target frozen").
- The adapter is covered by a real-Postgres suite
  (`crates/integration-tests/tests/ai_import_job_target.rs`) — until now only the
  in-memory fake exercised the rule, so the predicate could have been dropped
  without a red test.


### Added — `set_target_once` as one atomic statement (issue #829)

- `PgAiImportQueue::set_target_once` attaches a block-less job's write target
  with ONE conditional `UPDATE`:
  `SET block_id = $2, target_block_number = $3, updated_at = now() WHERE id = $1
  AND block_id IS NULL AND accept_as_is IS NULL`. No read-then-write window
  exists, so two racing attaches cannot both win, and `accept_as_is IS NULL`
  (the persisted fact `AiImportJob::applied` derives from) freezes the target of
  a job whose rows already landed. The block id and the number the visible
  snapshot renders move together — the guard value and the displayed target
  cannot drift. A refusal (or an idempotent repeat) is diagnosed with one
  follow-up read; a successful attach emits the same hub wake-up as the other
  job writes, so a watching client sees the attached target without reconnecting.

## [0.69.0] - Unreleased

### Changed — a target snapshot may carry its season without a block (issue #829)

- `decode_import_target` keeps the SEASON pair's all-or-nothing rule and lets
  `target_block_number` stay `NULL` on its own: a block-less upload persists the
  season pair from the first frame and gains the block number when the target is
  attached. The new migration `20261106000001_ai_import_target_block_optional` is
  comment-only — the three `target_*` columns were nullable from the start, so no
  schema change (and therefore no backfill or data risk) is involved.
- The enqueue binding already wrote what it was given; only its comment claimed
  "all three columns stay NULL together", which is no longer true.

## [0.68.0] - Unreleased

### Added — the script's block number reaches the job progress (issue #827)

- The script worker publishes `AiImportProgress::block_number` from the
  deterministic `Block:` page-header scan on its FIRST frame (no extra LLM
  tokens) and falls back to the model's answer only when the scan found no
  marker — the two-source discipline the episode metadata follows. The scan's
  value also SEEDS `ScriptContext::block_number` before the chunk loop, so the
  stored preview carries the block the document states even when the model
  repeats none (CodeRabbit review of PR #850: the seed used to live only on the
  progress frames).
- `ScriptContextSchema` — the provider-facing strict mirror — declares
  `block_number`. Without it the prompt rule would be unreachable under
  `strict` Structured Outputs: the model cannot emit a property the schema does
  not define (the reason the older per-scene `episode` rule never arrives).
- The default script prompt gains a `<block>` element that states the marker
  rules: leading digits only, repeated page headers are not a conflict, a
  missing marker is no uncertainty, and a location name inside a scene heading
  is not a block number.
- **0.67.1 → 0.68.0** (MINOR).

## [0.67.1] - Unreleased

### Fixed — the default script prompt resolves `(OT)` and the `Ep.: <n>/<suffix>` marker (issue #826)

- `config/default_ai_prompts.toml`, `<characters>`: `OT` / `(OT)` / `(O.T.)` /
  `Off-Text` are named as inline background notes ⇒ `extra` with **no**
  uncertainty — a plain `(OT)` is a stated signal, not an ambiguity. The prompt
  also states which reading this pipeline uses (Off-TEXT = a figure without
  dialogue, i.e. a Komparse; never the off-screen voice "Off-Ton"), and keeps the
  grounded-only discipline: a figure the document ALSO lists under
  "Darsteller"/"Hauptrollen" stays a genuine conflict.
- `<episode>`: `Ep.: <n>/<suffix>` names episode `<n>`; everything after the `/`
  is a scene/page/block index INSIDE it and is discarded — exactly what the
  deterministic `episode_marker` scan in `crates/core/src/ai/preview.rs` already
  does. `Ep.: 292/15` and `Ep.: 292/16` are one episode, and the glued page-header
  shape `Block: 098/Ep.: 294` is covered. A dissenting suffix is no longer read as
  a second candidate episode and needs no uncertainty.
- New `<uncertainties>` element: the canonical `field` vocabulary (`characters`,
  `episode`, `location`, `mood`, `scene_number`, `script_day`, `summary`,
  `outfits`), an explicit ban on nested paths and synonyms (`characters.category`,
  `character_category`, `category`, `role_type`), and at most one uncertainty per
  `(scene_index, field)`.
- Regression tests `script_prompt_classifies_ot_markers_as_extras_without_an_uncertainty`,
  `script_prompt_ignores_the_suffix_after_the_episode_number` and
  `script_prompt_names_one_canonical_uncertainty_field_per_concept`
  (`ai::catalog_misc_tests`) pin the wording per prompt element. They read
  `EMBEDDED_PROMPT_FILE`, so a deployment override cannot fail them, and the
  existing outline-style test still passes.
- Deployment note: this file is the fallback, not a lock. A deployment with a
  stored configuration prompt keeps serving that stored text and must update or
  clear it once (`POST/PATCH /v1/ai-import/config`, or the app's per-prompt
  reset) to pick the revised wording up.
- No public API change: **0.67.0 → 0.67.1** (PATCH).

## [0.67.0] - Unreleased

### Fixed — a `business` reset can no longer silently destroy the preserved configuration (issue #810)

The level-`business` reset is documented as *preserving* `ai_config`, `settings`
and `membership`. On 2026-11-03 it destroyed the AI configuration (Decision Model
and credential binding included), and **both runs exited 0**: a run that failed
right after the SierraDB volume was dropped left an empty event store, and the
next run exported that store as `10 streams / 0 events` and "replayed" nothing.
Four guards close the failure path:

- `dev_reset::events::export_keep_list` now takes `allow_empty_keep_list` and
  **refuses** an export whose keep projections hold rows while every keep stream
  carries zero events (`ensure_events_exported`); that combination is only
  explainable by an already-lost store. `--allow-empty-keep-list` is the
  explicit override, and the wrapper demands the stricter confirmation phrase
  `business-empty` for it.
- `KeepListExport::category_counts` / `business::keep_event_summary` expose the
  **event** counts beside the row counts, so `plan --dry-run` (best effort with
  the store down), the export phase and the wrapper's pre-drop summary show
  `0 event(s)` before the volume goes.
- `replay_phase` asserts its own result: the appended count must equal
  `export.event_count()`, every keep stream is re-read and compared exactly, and
  `<backup>/replay-report.json` (`backup::ReplayReport`, per-stream
  expected/appended, bound to the export's `created_at`) records what happened.
  A mismatch is a failure entry, a non-zero exit and a printed recovery command.
- `verify_phase` compares that receipt against the export and the store, so a
  later post-loss export cannot pass as the original one; and
  `require_empty_event_store` no longer *skips* when the export is empty — it
  probes the streams the projections still name and fails on a mismatch.

Tests: unit coverage for the export refusal (with the 10-streams/0-events
fixture), the replay receipt and the zero-event summary; a Tier-4 round trip
(`crates/integration-tests/tests/dev_reset_replay.rs`) that exports from a real
store, replays into a **second** (fresh) SierraDB container and asserts
byte-verbatim restoration plus the strict-versioning refusal of a second replay;
and a daemon-free wrapper test
(`scripts/tests/reset-dev-data-wrapper-test.sh`) that injects a wipe failure and
asserts the automatic restore.

Review follow-ups (same issue, all four independently exploitable):

- `ensure_events_exported` is **per category**, not on the total: an eventless
  `ai_config` beside a non-empty `settings` used to pass, after which the wipe
  deleted its projection and the replay skipped its empty stream.
- The export **never overwrites** a `keep-list.json` that still holds events with
  an empty one (after a failed replay *and* a failed restore the projections are
  empty too, so a re-run exported `0 events` over the only remaining copy).
- `recovery_hint` prints a runnable command (`--env dev` plus the `.env.local`
  sourcing the guard requires) and no longer suggests re-running `business`,
  which would hit the new overwrite guard.
- The wrapper turns **SIGTERM/SIGHUP** into exit 143/129: bash runs the EXIT trap
  with `$? = 0` after a signal, so the restore used to be skipped — the store
  stayed empty when a CI timeout or a closed terminal killed the run. The
  per-stream re-read in the replay now also reports a recovery hint instead of
  leaving the phase with `?`, and the `verify` receipt message names the volume
  reset the replay needs.

## [0.66.0] - Unreleased

### Fixed — the Decision Model adapter speaks the System One contract in both directions (issue #808)

Issue #803 fixed the *route*; the **bodies** were wrong in both directions, so a
correctly configured `eurouter` / `clef-flash` pair still scored nothing
(`decision_telemetry = {outcome: scoring_failed, failed_rows: 54}` on a 54-scene
import).

- **Request.** `decide` now emits `instructions` on every question and `criteria`
  for `score` (the label ladder) and `choice` (`name -> description`); the
  pre-#808 names `description` / `options` / `levels` are gone. One question is
  the unit of rejection — the provider answers the whole body with
  `400 {"error":{"details":[{"path":"questions.q.instructions", …}]}}` — so
  `question_payload` also refuses an unbuildable question (blank instruction, a
  one-level ladder, duplicate labels, a duplicated or descriptionless option)
  *before* the request leaves the process. `core 0.56.0 → 0.57.0` carries the
  model that makes the ladder expressible.
- **Response.** `score` is the scalar **mean** and `choice` the winning
  **label**; the mass rides under `probabilities` (level index → probability / 
  option name → probability) and `legend` echoes the ladder that was sent. The
  adapter now maps `probabilities` → the internal distribution and keeps the
  mean out of the answers. A `legend` that is not the sent ladder, a
  distribution that does not sum to ~1.0, a mean outside the level axis, an
  empty map or a winning label outside its own map is a **hard** error: silent
  mis-scaling is worse than a failed pass. CodeRabbit review hardening adds the
  contradictions that survived that first cut: a `probabilities` map shorter
  than its own `legend` (two entries under a five-label legend inflated
  `expected_score`), a mean that does not match the mass (`Σ level ×
  probability` — live-verified to ≤ 0.0003 on 2026-11-03, so a mean of 4 over
  mass on level 0 is now rejected), a `choice` key the question never declared
  (the resolver would compare zeroes and quietly degrade to a gap), `choice`
  mass that does not sum to 1.0 (the resolver compares raw values against
  `CONTINUITY_MIN_CONFIDENCE`), a `choice` label that is not its own
  highest-probability option, and a `noul` outside `0.0..=1.0`. Each rejection
  has its own test, and the live smoke test still passes against EURouter with
  the stricter validation in place.
- **Tests that could have caught it.** `testdata/decision_wire/` holds the
  captured provider bodies (the `400 details[]`, the `noul` / `score` /
  `choice` 200 envelopes, plus a legend-mismatch and an empty-mass case) and
  request goldens rendered from the *production* rubric; the unit mock is now a
  **strict** System One (rejects a body without `instructions`/`criteria` with
  the real 400 shape and builds its answers from the criteria it was sent), and
  `score_script_chunk` is exercised against it end to end:
  `scoring_failed == false`, `failed_rows == 0`, every row scored. An
  `#[ignore]`-gated live smoke test (`DECISION_LIVE_KEY`, see
  `docs/operations/runbooks.md`) is the only artifact that detects a
  *provider-side* schema change; the module docs record the probed live shapes
  with their date (2026-11-03).

## [0.65.0] - Unreleased

### Added — apply runs have an identity, a heartbeat and a drop guard (issue #800)

- Migration `20261104000001_ai_apply_run_identity` adds
  `ai_import.ai_import_job.apply_run_id` (the owning run, released with the
  payload) and `apply_run_seq` (monotonic, never cleared — the start/completion
  signal that survives a re-read). No backfill: a pre-#800 run cannot be
  reconstructed.
- `PgAiImportQueue::claim_apply_run` is the single-flight gate: one conditional
  `UPDATE` either wins a free slot or steals one whose owner is demonstrably dead
  (its payload is older than `ApplyProgress::STALE_AFTER`, computed in Rust from
  that constant so the window has one definition). `mark_apply_progress` is
  conditional on `apply_run_id`, so a superseded run can neither publish nor
  clear, and `apply_run_state` exposes owner + counter + payload to the stream.

### Fixed — a live apply is no longer mistaken for a dead one (issues #800 #3/#4)

- `ApplyWorker::apply_script` claims the slot, generates the run id and installs a
  run-scoped **drop guard**: a client disconnect (hyper dropping the handler
  future) now clears that run's payload instead of leaving `applying 12/57` behind
  for the whole staleness window. The clear is conditional on the run identity, so
  a deferred clear can never remove a newer run's progress; the apply itself is
  never detached.
- A run-scoped **heartbeat** refreshes the payload's `updated_at` at a quarter of
  the staleness window while the row phase and the trailing work run. Staleness
  now means "the process is gone" rather than "this row is slow": a single scene
  with several character/outfit creates no longer makes the stream declare a live
  run finished mid-apply.
- The worker's progress writes carry the run id, so every frame of one apply is
  attributable to one run.

## [0.64.0] - Unreleased

### Added — the apply worker reports its own progress (issue #762)

- Migration `20261103000001`: `ai_import.ai_import_job.apply_progress` (JSONB,
  nullable). `NULL` means "no apply in flight": every pre-#762 row, a preview
  nobody applied yet, and a finished run. The progress writes are advisory, so
  `NULL` is also the state of a running apply whose write has not landed yet —
  a reader must never treat it as proof that nothing is running.
- `PgAiImportQueue::mark_apply_progress` writes the payload only while the job
  is `succeeded` — it never touches the claim, the lease or the status — and
  every write wakes the job's subscription, so the apply stream pushes frames
  without polling.
- `ApplyWorker::apply_script` publishes the run: an anchor and the plan's row
  count up front, one frame per completed row through a bounded stride (always
  the last row), a `finalizing` boundary for the trailing work, and an explicit
  clear on **every** exit path — a failed apply that left "applying 12/57"
  behind would keep the client's stream open until the staleness window.
- Progress writes are advisory here: a failed write is logged and swallowed
  (the rows already dispatched are committed), the opposite trade-off from the
  owner-fenced worker writes that must abort before the next billable call.
- Consumes `breakdown_core` 0.55.0.
- Public API change: **0.63.0 → 0.64.0** (MINOR).

## [0.63.0] - Unreleased

### Added — ETA anchor and byte budget on the published progress frames (issue #762)

- The script worker publishes `started_at` (the claim stamp of the current
  attempt) and a byte budget on every `mark_progress` frame, and advances
  `done_bytes` once per completed chunk. The anchor is read from the claimed
  job's `updated_at`, which `claim_next*` stamps in the same statement that
  clears the stale counters — so anchor and counters always belong to the same
  attempt and a retry restarts the estimate instead of inheriting the previous
  attempt's rate.
- The byte budget counts exactly the bytes the model is handed
  (`heading` + `\n` + `text` per chunk), so the published fraction tracks the
  work that is actually left.
- Every published frame is stamped with `written_at` in `publish_progress` —
  the single funnel all worker frames go through — so the stamp always describes
  the write it travels with and no call site can forget it.
- The schedule and merge workers publish the anchor only; a schedule job is a
  single extraction unit and a merge is a single deterministic join, so their
  byte pair stays `None` rather than inventing a numerator.
- Consumes `breakdown_core` 0.54.0.
- Public API change: **0.62.0 → 0.63.0** (MINOR).

## [0.55.0] - Unreleased

### Fixed — PDF reports returned HTTP 500 for every non-empty report (issue #764)

- All five embedded Typst templates (`dispo`, `shoot-day`,
  `planned-vs-actual`, `season-soll-ist`, `episode-soll-ist`) passed raw JSON
  values as table cells. Typst requires `content`, so any row with a scene
  number (or `notes.len()`) aborted compilation with `expected content, found
  integer`, surfacing as an opaque 500 once scenes were assigned to a day.
- New shared snippet `templates/reports/_helpers.typ` defines
  `cell(v)` (none → empty, str/content unchanged, everything else → `repr`).
  `embedded_templates()` prepends it to every template — the restricted world
  serves only `main.typ` + `report.json`, so no `#import` is possible. Every
  table cell is now wrapped in `cell(...)`, including the previously unsafe
  Soll-Ist flag columns.
- Compiler-failure diagnostics now carry the report kind
  (`<kind>: expected content, found integer`), so the single logged 500 is
  actionable without correlating the request; no wire-contract change.
- Regression guard: per-kind render tests with representative rows (numbered +
  unnumbered scenes, `null` `actual_order`, notes present/absent, all diff
  flags, German location with `/ ( ) ·`) plus a direct `cell()` scalar test,
  all rendered on deterministic bundled fonts (`typst-assets`, feature
  `fonts`, dev-dependency) so they never skip on fontless hosts. The previous
  coverage only asserted that each embedded template source was non-empty.
- Public API change: **0.54.0 → 0.55.0** (MINOR: `embedded_templates()` and
  `embedded_template_helpers()` are public so the render tests exercise the
  exact bytes the production renderer embeds).

## [0.47.0] - Unreleased

### Added — set-shorthand mood backfill, Episode.Scene schedule parsing, LLM schedule decode (issue #721)

- `ScriptImportWorker` backfills `DraftScene.mood` from `SceneChunk.mood` on
  the first scene of a chunk when the model leaves it empty (same
  server-truth doctrine as `scene_number`, `episode`, `shooting_day`).
- `parse_schedule_csv` accepts dot-separated `<Episode>.<Scene>` scene
  references (`"294.10"` → episode 294, scene 10 — never decimal `294.1`); an
  unparseable reference leaves the row without a scene number (unmatched for
  review) instead of failing the whole import. `order` keeps strict
  validation.
- `OpenAiCompatibleChatClient` now implements `LlmClient::extract_schedule`
  (schema-constrained, same truncation-retry and usage semantics as
  `chat_constrained`): the schedule row's scene reference is accepted as a
  string or number and decoded losslessly via `parse_schedule_scene_ref`,
  `block_id` is never taken from model output, and an unparseable date
  degrades to `None`.
- `merge_loaded_schedule` / `MergeWorker::merge` take the episode-numbers map
  (prepared at the API boundary) and pass it into the episode-aware merge.
- Public API change: **0.46.0 → 0.47.0** (MINOR).

## [0.32.0] - Unreleased

### Changed — persist the AI-import attempt failure code (issue #639)

- Migration `20261011000001_ai_import_attempt_error_code` adds
  `ai_import.ai_import_job_attempt.error_code`; `mark_failed` and
  `mark_payload_unavailable` persist `DomainError::code()` in the same statement
  as the lifecycle write, and `list_attempts` decodes it into
  `AiImportAttempt.code`.
- The AI-import workers pass the error code at every failure site.

## [0.31.0] - Unreleased

### Added — Vault token renewal + auth classification, attempt history (issue #637)

- `VaultClient::send` now classifies 401/403 from Vault as
  `DomainError::DependencyAuthFailed` (non-retryable) instead of the generic
  `ServiceUnavailable`; new `token_valid`, `renew_token` and
  `spawn_token_renewal` keep a long-running API's periodic app token alive
  across the 24 h TTL.
- Migration `20261010000001_ai_import_job_attempt`; `mark_failed` and
  `mark_payload_unavailable` append a per-attempt row in the same statement as
  the lifecycle write, and `get` populates the job's attempt history.
- `OpenDalAiPayloadStorage::health_check` backs the Garage readiness probe.
- `breakdown_core` 0.25.0 → 0.26.0; **0.30.0 → 0.31.0** (MINOR).

## [0.30.0] - Unreleased

### Added — per-character appearances query (issue #621)

- `CharacterRepositoryImpl::character_appearances` reads
  `projection_scene_character` → `projection_scene` in script order
  (**episode number first**, then the episode-local `scene_number` NULLS LAST,
  id tie-break) and attaches the character's own
  `projection_scene_costume_assignment` beats (category resolved by join)
  through a correlated scalar subquery, so the one-to-many costume list cannot
  fan out the scene rows.
- Migration `20261009000001` adds the covering index
  `idx_projection_scene_character_character_scene (character_id, scene_id)`
  backing the filter + join. A literal `(character_id, scene_number)` index is
  impossible across the two tables (`scene_number` lives on
  `projection_scene`).
- `breakdown_core` 0.24.0 → 0.25.0; new trait-method implementation
  (additive): **0.29.2 → 0.30.0** (MINOR).

## [0.29.2] - Unreleased

### Changed — descriptive, configurable `User-Agent` on the AI provider HTTP clients (issue #521)

- New private `ai::user_agent` module resolves the `User-Agent` every AI
  provider client sends: default `breakdown-rs-backend/<version> (ai-import)`,
  overridable globally (`AI_IMPORT_USER_AGENT`) or per curated provider
  (`AI_IMPORT_USER_AGENT_<PROVIDER>`, e.g. `AI_IMPORT_USER_AGENT_OPENCODE_GO`).
  reqwest's generic `reqwest/<version>` fallback is the agent opencode /
  OpenCode-Go anti-abuse filters flag as a bot (403).
- Applied to the model-catalog client, the shared Ollama client, and every
  hosted-regime client built by `transport::build_hosted_client` (plus the new
  `pub(crate) build_hosted_client_with_user_agent` for per-provider agents).
  The issue #170 redirect / DNS-pin / no-proxy policy is unchanged; the agent
  is additive transport metadata. A `User-Agent` is not a credential, so no
  secret handling applies (gitleaks-safe).
- No public API change (`build_hosted_client` keeps its signature): **0.29.1 → 0.29.2** (PATCH).

## [0.29.1] - Unreleased

### Fixed — default script prompt no longer asks the model to comment on an empty block (issue #607)

- `config/default_ai_prompts.toml`, `<grounding>`: an outline-style block
  (heading + day marker only) is answered with empty `characters`/`costumes`
  **and a null `summary`** — the previous "return empty lists for it and say
  so in `summary`" instruction made every such block carry a boilerplate
  sentence ("Outline-style block with heading and day marker only; no
  characters, costumes, or props described.") into the preview, which renders
  `summary` verbatim.
- `<summary>` additionally forbids meta-information in the field: content
  only, never the shape of the block, its emptiness, or what the model did or
  did not extract; a block whose body states nothing gets `summary` null.
- No frontend blacklist/regex was added (the issue explicitly rejects it as
  brittle symptom-hiding); suppression happens at the prompt source.
- Regression test `script_prompt_leaves_summary_empty_for_an_outline_style_block`
  (`ai::catalog_misc_tests`) pins both the removal of the old instruction and
  the null-`summary` rule.
- Deployment note: the file is the fallback, not a lock. A deployment with a
  stored configuration prompt (editable in the app, `AI_IMPORT_DEFAULT_PROMPTS_PATH`)
  keeps serving the stored text and must update/clear it once to pick this up.
- No public API change: **0.29.0 → 0.29.1** (PATCH).

## [0.22.0] - Unreleased

### Added — aggregated Soll-Ist read adapter + render kinds (issue #571)

- `SceneShootReportRepositoryImpl::season_soll_ist_report` /
  `episode_soll_ist_report`: static-literal SQL over
  `projection_scene_shoot` × day/episode/block/season joins (non-archived
  days only), one day-count summary query per scope (never vacuously final),
  rows ordered by day `order_key` then planned order, `reshot_candidate`
  computed from the fetched set (scope-true semantics).
- Two embedded Typst templates (`season-soll-ist.typ`,
  `episode-soll-ist.typ`) registered on the aggregate `ReportKind`s;
  both render-only kinds are explicitly rejected by the archival data
  loader (never archivable).
- Tier-4 round-trip test `aggregate_soll_ist_report_episode_and_season_scopes`
  (scopes, finality rule, archived exclusion, reshot semantics).

## [0.26.0] - Unreleased

### Added — ES-native reservation streams: atomic cross-aggregate uniqueness at the write boundary (ADR-036, issue #586)

- `infra::reservations` (new module): atomic uniqueness claims for the four
  #404 invariants — episode/season/block numbering `(series_id, number)` and
  scene_shoot pair-uniqueness `(scene_id, shooting_day_id)` — on synthetic
  SierraDB streams (`reservation-*`, category `reservation`). `ReservationStore::reserve`
  appends `ReservationReserved` with `ExpectedVersion::Empty`; a competing
  claim fails the version condition in the event store and surfaces the
  invariant's registered 409 BEFORE any aggregate append. After a
  `ReservationReleased` the key is re-claimable via CAS; a claim held by the
  same `aggregate_id` is recovered instead of conflicted (idempotent AI-apply
  crash recovery, issue #182 mirror).
- Command adapters (season/block/episode `create`, scene_shoot `plan`) now
  claim → append → compensate: a handle-rejected command releases inline;
  unknown append state (version conflict / database error) leaves the claim
  to the reaper — the reaper probes the event store (never a projection), so
  projector lag can never cause a false release (ADR-036 §3.2).
- `ReservationProjector` + `projection_number_reservation` (migration
  `20261007000001`): claim-lifecycle mirror for observability and reaper
  candidate selection. `spawn_reservation_projector` in the composition root.
- `infra::reservations::reaper`: periodic claim-compensation worker
  (`RESERVATION_REAPER_ENABLED`, `RESERVATION_REAPER_INTERVAL_SECS`,
  `RESERVATION_CLAIM_TTL_SECS`, `RESERVATION_REAPER_BATCH_SIZE`), advisory-
  lock-single-flight. It consumes realized claims whose aggregate's first
  persisted create event matches the claim key (`ReservationConsumed`), and
  releases both crash orphans and mismatched phantom claims
  (`ReservationReleased` — a re-driven attempt can claim a different key
  under the same derived aggregate id; the reaper verifies the realized key
  against the claimed aggregate's create event before consuming).
- The four #404 projector savepoint-skips stay as documented backstop; the
  projection unique constraints remain the last authority.

## [0.21.0] - Unreleased

### Added — AI apply creates episodes for draft episode groups (issue #581)

- `ApplyWorker` gains an `EpisodeCommands` port and `ApplyScriptRequest`
  gains `block_id` + `episode_groups` (both resolved at the API edge — the
  write side never queries a projection, CQRS boundary). A group mapped to
  a NEW episode is created through `create_episode_reserved`, mirroring the
  scene reservation protocol: the mapping row
  `(preview_id, episode_ref, 'episode', 0)` is reserved before dispatch, a
  crashed attempt re-drives onto the same derived aggregate id via
  `created_now`, and the confirm finishes the interrupted attempt. Every
  row of a group converges on ONE episode; a retry re-creates nothing.
- The script import worker stamps each draft row with the deterministic
  `Ep.:` episode scan of the document; the LLM's `episode` field (new
  prompt rule in `config/default_ai_prompts.toml`) only fills in when the
  scan found no marker for the chunk — the scan wins.
- `ScriptApplyResult.created_episodes`: episodes THIS apply created (a
  group an earlier attempt created is not counted again).

## [0.20.0] - Unreleased

### Added — AI apply persists the scene relation (issue #546 §5.8)

- `ApplyWorker::apply_script` drives, per accepted draft row, the chain
  `CreateScene` → `AssignCharacter`×n → `AddCostumeBeat`×m: one
  `AssignCharacter` per figure of the row BEFORE any beat (a beat may only
  exist for a figure in `assigned_characters`), then one `AddCostumeBeat`
  per costume whose `Costume` chain fully succeeded, in per-figure plan
  order (`scene_beat_lanes` re-grouping).
- `scene_costume_beat` mapping rows with the mapping-row phase protocol of
  `CostumePhases` applied to the SCENE stream: the row's `scene` mapping row
  and its beat rows hold versions of the SAME aggregate stream — recovery
  reads the MAX across all of the row's rows, confirms stay
  only-moves-forward, and every chain step appends exactly one event
  (pinned by `scene_apply_chain_appends_exactly_one_event_per_step`). A
  confirmed beat row skips the dispatch, so a re-apply adds no second beat;
  a version conflict on the first dispatch re-dispatches once at the
  reached version so a concurrent stream move can never settle an absent
  beat silently; the identical-last guard settles the crash window between
  an append and its confirm.
- `ScriptApplyResult.created_costume_beats` (infra-internal reporting) and
  `UnappliedCostumeReason::BeatRejected` for the refused-beat report —
  distinct from the plan-time ungrounded drop.
- **No additional bump:** rides with the open, still-unreleased 0.20.0
  window.

### Added — scene costume-beat projection + adapters (issue #546)

- Migration `20261003000001_projection_scene_costume_assignment`:
  `projection_scene_costume_assignment` with
  `PRIMARY KEY (scene_id, character_id, "order")` (structural backstop for
  one costume per beat, beats uniquely ordered per character), FK cascade
  to `projection_scene`, reverse index on `costume_id` for "in which
  scenes is this costume worn?" lookups. No cascade to
  `projection_costume` (a costume is never deleted).
- `SceneProjector`: four new branches (`CostumeBeatAdded`/`Updated`/
  `Removed`/`BeatsCleared`), idempotent upsert/delete style matching the
  file, each guarded by the shared parent-version guard (`guard_parent`:
  claim `WHERE version < $N` first, skip the mutation on same-or-newer
  redelivery — a replayed older add cannot recreate a removed beat);
  removal deletes exactly one row and never renumbers survivors; the
  audit projector covers the new variants.
- `SceneCommandsImpl`: `add_costume_beat` / `update_costume_beat` /
  `remove_costume_beat` adapters (`check_nonzero_version`,
  `ExpectedVersion::Exact`, `series_id` only from the command field).
- `SceneRepositoryImpl` + `ShootingDayRepositoryImpl` scene reads:
  `SceneView.costume_beats` read fan-out-free (correlated jsonb subquery,
  issue-#550 pattern) and enriched by LEFT JOIN to
  `projection_character`/`projection_costume` (best-effort names).
- **No version bump:** the pending, still-unreleased 0.20.0 window already
  carries the MINOR bump for issue #543's additive API.

### Added — costume detail edit/delete adapters and projection (issue #544)

- `update_detail` command adapter (same version-fence + `EventMetadata`
  shape as `add_detail`); `series_id` is audit metadata resolved at the API
  edge and is never re-queried here (CQRS boundary).
- The costume projector gains a `DetailUpdated` arm onto the **existing**
  `projection_costume_detail` upsert plus `touch_parent` — no migration, no
  new query. It deliberately skips the `DetailAdded` category-derivation
  block: an edit can only be produced by the PATCH route, whose wire request
  carries no category (issue #543 made details pure description), and an
  edit must never change the costume's own category.
- `CostumeAuditProjector` learns the new event variant (entity-id match).
- **No version bump:** the pending, still-unreleased 0.20.0 window already
  carries the MINOR bump for issue #543's additive API.

### Added — costume-level category projection (issue #543)

- Migration `20261002000001_projection_costume_category`: `projection_costume`
  gains nullable `category_id UUID` / `category_name TEXT` (down drops both).
  `projection_costume_detail.category_id/category_name` deliberately stay for
  legacy replay; a later migration cleans them up.
- The costume projector: a `CostumeCategorySet` branch (best-effort
  `category_name` resolution — a dangling reference stays `NULL`, audit
  metadata never blocks) and the **first-wins derivation rule** in the
  `CostumeCreated`/`DetailAdded` branches, identical to the aggregate's
  `apply` so a replayed legacy stream yields the same category in aggregate
  and projection (parity test mandatory).
- The costume_category projector retargets rename propagation **from**
  `projection_costume_detail.category_name` **to**
  `projection_costume.category_name`.
- The costume query adapter reads `CostumeView.category_id/category_name`
  from `projection_costume`; the detail enrichment no longer resolves the
  detail category.
- `CostumeCommands` adapter gains `set_category` (version fence, audit
  metadata from the command field).
- **MINOR bump (ADR-020 D2):** migration + projector behavior + additive
  port method, re-pin `breakdown_core` 0.16.0 — **0.19.0 → 0.20.0**.

## [0.19.0] - Unreleased

### Added — credential-binding owner projection (issue #552)

- Migration `20261001000001_projection_settings_owner`: `projection_settings`
  gains a nullable `owner TEXT` column + `idx_projection_settings_owner`
  (down drops both). The settings projector populates it from the persisted
  `EventMetadata.actor` on `CredentialBound`; `SettingsRepositoryImpl` reads
  it into `SettingsView.owner`. Rotation deliberately does not touch the
  owner (the settings rotate/revoke handlers do not verify the rotating
  actor against the binding owner — a rotation backfill would let any
  credential-role member claim a legacy NULL-owner binding).
- **MINOR bump (ADR-020 D2):** additive projection column + projector
  behavior and re-pin `breakdown_core` 0.14.0 (`SettingsView.owner`):
  **0.18.0 → 0.19.0**.

## [0.18.0] - Unreleased

### Added — Scene AI provenance projection + honest day confidence (issue #517, EU AI Act Art. 50)

- Migration `20260926000001_projection_scene_source`: `projection_scene` gains
  `source JSONB NOT NULL DEFAULT '{"Manual":null}'` (down drops it). The scene
  projector writes the event's `SceneSource` on `SceneCreated` (insert +
  redelivery update), the scene/shooting-day query mappers deserialize it into
  `SceneView.source`.
- AI script apply (`ApplyWorker::create_scene_reserved`) now dispatches
  `CreateScene` with `SceneSource::AiExtracted { document_id: job_id,
  external_ref: draft_ref, confidence: None }` — AI-imported scenes are
  distinguishable from manual ones and the recorded confidence is honest
  (no invented value), same for the schedule apply's `ShootingDaySource`.
- **MINOR bump (ADR-020 D2):** additive projection column + projector behavior
  and re-pin `breakdown_core` 0.13.0 (`SceneSource`, `Option<f32>` confidence):
  **0.17.0 → 0.18.0**.

### Fixed — scene/shooting-day read queries fan out over joined one-to-many pivots (issue #550)

- `SceneRepositoryImpl::{find_by_id, list_by_episode, scenes_by_character}` and
  `ShootingDayRepositoryImpl::scenes_by_shooting_day` joined
  `projection_scene_character` × `projection_scene_shooting_day` side-by-side
  and aggregated each list with a bare `array_agg`, so the independent joins
  multiplied (`c·d` rows; `c·c·d` in `scenes_by_character`, which joined the
  character pivot twice) and `assigned_characters` / `shooting_day_ids` came
  back with one duplicated element per multiplied row. The pivots themselves
  were correct (composite PKs rule out duplicate rows) — only the SELECT was
  wrong.
- Both lists now read through correlated scalar subqueries scoped to a single
  pivot per scene (fan-out-free by construction, no `array_agg(DISTINCT …)`
  mask, no `GROUP BY`), with deterministic element order (sorted by id; the
  previous order was join-order-dependent and unspecified). The filter-only
  joins (`scenes_by_character`'s duplicate-join smell,
  `scenes_by_shooting_day`'s `link` join) became `WHERE EXISTS`.
- Read-only fix: no migration, no projector change, no wire-format change.
  Regression coverage (fan-out-triggering 2×2 fixture + aggregate-vs-query
  cross-check): `crates/integration-tests/tests/scene_query_fanout_regression.rs`.

## [0.17.0] - Unreleased

### Fixed — photo thumbnail saga crash-loop on aggregate version conflict (issue #515)

- `PhotoThumbnailSaga::process_upload` maps each `PhotoAggregate::execute`
  result with a saga-tolerant mapper (`map_saga_execute`) that treats the
  idempotent no-op outcome (`Executed(vec![])`) as success instead of failing
  with `command produced no events`. Combined with the idempotent aggregate
  commands (core), a redelivery of `PhotoUploaded` after the aggregate has
  advanced stabilizes and produces the thumb/medium variants instead of
  crash-looping with a version conflict.
- `GenerateVariant` now carries the real generated thumb/medium byte sizes
  (previously hardcoded `0`), so the read model reports actual variant sizes.

### Added — `AiConfigView` exposes the stored prompt texts (issue #490)

- `map_config_row` now passes the parsed `prompts` JSONB map through into
  `AiConfigView.prompts` (previously only its keys surfaced as
  `prompt_kinds`), so every read view carries the stored prompt texts.
- **MINOR bump (ADR-020 D2):** re-pins `breakdown_core` 0.12.0 (its
  `AiConfigView` gained a required `prompts` field): **0.16.0 → 0.17.0**.

## [0.16.0] - Unreleased

### Added — AI prompt defaults + curated recommendation (issue #471)

- `prompts::default_prompts()` returns both document-kind prompt defaults
  (`AiPromptDefaults { script, schedule }`) from one read of the configured
  `AI_IMPORT_DEFAULT_PROMPTS_PATH` (or the built-in fallback), so the wire
  endpoint and the per-kind worker seeding can never drift; `default_prompt`
  now delegates to it.
- `provider_registry::recommended_model(provider)` designates the curated
  recommendation (must be one of `curated_model_ids`); `curated_models` flags
  exactly that model `recommended: true` on `ModelInfo`.
- **No additional bump:** additive functions + curated metadata — rides with
  the open 0.16.0 MINOR.

### Added — costume season repertoire projection + query (issue #453)

- New migration `20260216000001_costume_season_repertoire`:
  `projection_costume_season (costume_id, season_id)` join table + season
  index. A costume can sit in **several** seasons' repertoires (main
  characters reuse costumes across seasons) — the join is many-to-many, not
  an ownership.
- Costume projector: `CostumeCreated` with `season_id: Some(_)` inserts the
  repertoire row (idempotent via PK); old events (`None`) skip it.
- `CostumeRepositoryImpl::list_by_season` now returns the **union** of
  costumes assigned to a character of the season (LEFT JOIN, previously
  INNER) and costumes in repertoire for the season (EXISTS) — unassigned
  seasonal costumes are visible, fixing the invisible-first-assignment bug.
- **No additional bump:** additive migration + widened query result — rides
  with the open 0.16.0 MINOR.

### Added — projector-health port implementation + ops predicate (issue #409)

- `MembershipRepositoryImpl::has_active_ops_role`: static-SQL predicate over
  `projection_membership` (`role = 'ops_admin' AND state = 'active'`, any
  block).
- `projectors::ProjectorHealthRepository` now implements the
  `breakdown_core::ops::ProjectorHealthRepository` port (row mirrors keep the
  `sqlx::FromRow` derives infra-side; DTOs moved to `core::ops` and are
  re-exported unchanged).
- Rides with the open 0.16.0 MINOR; no additional bump.

### Added — projector dead-letter + health signal (issue #37)

- New migration `20260815000001_projection_dead_letter`: durable poison-event
  table (`projection_id, partition_id, sequence` PK, stream id, event name,
  SQLSTATE, constraint name, error message, `attempts`, timestamps).
- kameo_es `PostgresProcessor` (vendored path patch): permanent errors
  (SQLSTATE class 23/22, event deserialization) that survive the 5× retry
  budget are dead-lettered and the projector checkpoint advances past the
  event in one transaction — no more infinite supervisor restart loop per
  stalled category; transient errors keep the restart behavior. New
  `EventErrorClassify` trait (`is_permanent_event_error`,
  `permanent_error_details`) implemented for `sqlx::Error`; classification
  unit tests included.
- New `infra::projectors::ProjectorHealthRepository` (module
  `projectors::health`): `list_dead_letters`, `dead_letter_count`,
  `checkpoint_progress` — the operator-facing health signal; psql variants
  documented in `docs/operations/runbooks.md` → "Projector dead-letter
  health (issue #37)".
- Stream-layer coverage (issue #411): Sierra messages whose payload/metadata
  cannot be decoded are dead-lettered by the `EventHandlerStream` via the new
  `EventProcessor::dead_letter_undecodable` (raw coordinates preserved in
  `TryFromSierraEventError`); processors without a durable DLQ surface (photo
  sagas, report triggers) keep the restart behavior via the default impl.
- Tier-4 regression tests `projector_dead_letter_tests.rs` (FK-violation
  repro of the original #37 report; corrupt-payload stream-layer repro).
- Rides with the open 0.16.0 MINOR; no additional bump (0.16.0 unreleased).
  The vendored `kameo_es` path patch is bumped `0.1.0` → `0.2.0` (new public
  `EventErrorClassify` trait + dead-letter path; not published to crates.io,
  the bump is for traceability of the vendored patch).

### Fixed — projectors skip permanent invariant violations instead of crashing (issue #404)

- `SeasonProjector` / `BlockProjector` / `EpisodeProjector` / `SceneShootProjector`:
  a permanent 23505 on the authoritative uniqueness constraints
  (`idx_projection_*_series_number`, `uq_projection_scene_shoot_pair`) is a
  poison event that previously panic-killed the projector worker/coordinator
  (batch transaction aborted). The guarded inserts now run inside a
  SAVEPOINT (`crates/infra/src/projectors/invariant_skip.rs`): the violating
  event is classified, logged (`tracing::warn!`), rolled back to the
  savepoint, and acknowledged — the projection keeps the authoritative row.
  Full DLQ/poison-table mechanics remain in #37.
- Rides with the open 0.16.0 MINOR; no additional bump.

### Added — season list-all projection query (issue #377)

- `SeasonRepositoryImpl::list_all`: every row of `projection_season`
  (`ORDER BY number, id`, `LIMIT`/`OFFSET` bound, static SQL) reusing
  `map_season_row`.
- Rides with the open 0.16.0 MINOR; no additional bump.

### Added — AI import discovery list queries (issue #337)

- `AiConfigRepositoryImpl::list_for_user`: caller's configs from
  `ai_import.projection_ai_config` (`WHERE user_id`, newest-first,
  `LIMIT`/`OFFSET` clamped in Rust over static SQL).
- `PgAiImportQueue::list_for_user`: caller's jobs from
  `ai_import.ai_import_job` (`WHERE user_id`, newest-first) reusing
  `map_job_row`.
- **MINOR bump (ADR-020 D2):** additive read-model surface: **0.15.0 → 0.16.0**.

### Fixed — Script apply reserves the scene id before creating (issue #338)

- `ApplyWorker::apply_script` read the draft→aggregate mapping before
  `SceneCommands::create` but never reserved it, so two concurrent applies
  for the same job both observed "no mapping yet" and created two scenes
  per draft (a client retry after an ambiguous timeout duplicated scenes).
- The script path now mirrors the schedule apply path: a deterministic id
  derived from `(preview_id, draft_ref)` is reserved via
  `AiImportMappingRepository::reserve` before dispatch and the command runs
  against the winning reservation; a `VersionConflict` on the reserved
  stream is recovered via `recover_version`, so concurrent duplicates
  converge on one scene per draft with a stable `applied_count`.
- A confirmed mapping makes a repeated apply a no-op returning the stored
  id/version (re-dispatching an `Update` would fail in production:
  identical details are rejected as unchanged). A reservation wins over a
  changed client decision so a crashed create is never orphaned.
- No public API change (`derive_id` / `recover_version` are shared
  `pub(crate)`); no version bump beyond the unreleased 0.15.0.

### Fixed — Membership projection stores plain `role` / `state` tokens (issue #342)

- `projectors::membership` wrote `serde_json::to_string(&role)` and
  `serde_json::to_string(&state)`, so the columns contained
  `"costume_assistant"` and `"active"` — while every membership authorization
  predicate compares `m.state = 'active'` and
  `m.role IN ('costume_designer', 'wardrobe_supervisor', 'costume_assistant')`.
  **No row could ever match**, so `has_active_costume_role_in_season`,
  `has_active_report_archive_role_in_season` and
  `has_active_credential_role` always returned `false` and every photo,
  continuity-photo, PDF/JSON report, manual-archive, AI-import and credential
  handler denied every caller with `403`.
- The projector now writes the bare token (`Role::as_str` /
  `MembershipStateKind::as_str`) and `map_membership_row` parses it with
  `from_token`, rejecting unknown values loudly instead of defaulting. The
  SQL predicates are unchanged and now match.
- **No data migration:** the backend is not in production, so development
  databases are re-seeded. Rows written by the previous projector are
  rejected by `from_token` rather than mis-read.

### Added — `has_active_membership_in_series` (issue #342)

- `MembershipRepositoryImpl` implements the new series-scoped predicate: a
  single join `projection_membership → projection_block` on the indexed
  `projection_block.series_id`, filtered to `state = 'active'`. Static SQL,
  all values bound.

### Changed — Version cascade (ADR-020 D3)

- **MAJOR (cascade):** re-pinned to `breakdown_core` 0.10.0 (the series-scoped
  audit gate adds a required method to the `MembershipRepository` trait, which
  `infra` implements); `infra` therefore bumps **0.14.0 → 0.15.0**. The two
  functional changes above would each be PATCH-class on their own (no public
  API change), but D3 makes the crate carry the cascade.

## [0.14.0] - 2026-08-23

### Changed — Bump MSRV to 1.98 (issue #257)

- **Breaking (MAJOR, ADR-020 D2/D3):** `rust-version` raised from `1.94` to `1.98` (workspace floor + Dockerfile builder `rust:1.98-bookworm`). Re-pinned to `breakdown_core` 0.9.0 (cascade).

## [0.13.0] - 2026-08-13

### Changed — Consume the structured `DomainError` surface (issue #230)

Adapters, projectors and sagas construct `DomainError` with the typed
registry-carrying variants instead of interpolated strings; read-model 404s
are upgraded to per-context codes (e.g. `character.not-found`). No
behavioural change beyond the error identity.

- **Breaking (cascade):** re-pinned to `breakdown_core` 0.8.0 (ADR-020 D3);
  infra bumps 0.12.0 → 0.13.0.

### Changed — Retry LLM responses truncated at the output-token budget

`OpenAiCompatibleChatClient` now inspects the provider `finish_reason`: a
response cut off at the caller's `max_tokens` ceiling (`finish_reason:
"length"`, unparseable JSON) is retried in-loop with a doubled output-token
budget, bounded by `MAX_TRUNCATION_RETRIES` (2). Previously such a response
failed permanently although a larger budget would have succeeded — this is
what broke the AI Import Nightly smoke on 2026-08-13 (`EOF while parsing an
object at line 1 column 1158`). Genuinely malformed JSON (`finish_reason:
"stop"` or absent) is still a permanent validation error: re-paying a paid
call on arbitrary malformed output is a cost risk, not a recovery. Budget
growth saturates at the `u32` ceiling, so the worst-case spend of one call
stays bounded (budgets `B, 2B, 4B` at most).

## [0.12.0] - Unreleased

### Added — Route non-CSV schedule imports through the LLM (issue #221)

- `ScheduleImportWorker` derives the extraction path from the job's persisted
  `source_format` instead of a caller-supplied `native_csv` flag: CSV stays on
  the native parser, `plain_text` goes straight to the LLM, and `pdf` is
  extracted to text with the same bounded `PdfTextExtractor` as the script
  worker before the LLM call. The flag is gone from `process`, `run_once` and
  `run_once_with_permit` — the worker loop and the processor cannot disagree
  anymore.
- New column `ai_import.ai_import_job.source_format` (NOT NULL, CHECK
  `('csv','pdf','plain_text')`). Legacy schedule rows backfill to `csv` (their
  previous routing) and script rows to `pdf`, so the claim path keeps working
  across the migration.
- **Breaking:** `ScheduleImportWorker` gains a required `extractor:
  PdfTextExtractor` field.

### Added — AI import worker loops wired through the concurrency limiter (issue #214)

The `PgAiConcurrencyLimiter` / `AiWorkerRuntime` were public API that nothing
constructed; jobs never consumed a permit and the `AI_IMPORT_MAX_CONCURRENT_JOBS_*`
ceilings were documentation only. This change adds the worker-loop side:

- New module `ai::worker_loop` with `spawn_script_import_worker` /
  `spawn_schedule_import_worker`. Each loop claims a job (reconciling orphaned
  permits via `claim_next_kind_reconciling`), resolves the job's per-user AI
  config + vaulted API key, builds the provider-matching LLM client, and routes
  the job through `AiWorkerRuntime::run_job_as` so the permit lifecycle
  (acquire → renew → release) and the `AiJobGuard` tracked for `drain()` are
  managed in one place. A saturated ceiling returns the claim unrun instead of
  acquiring first.
- `AiConfigRepositoryImpl::find_worker_config` resolves the active AI config
  (provider, model, prompt, vault reference) for a user + document kind — the
  job carries `user_id` but not a config id.
- `ScriptImportWorker` / `ScheduleImportWorker` no longer generic over the
  preview store (`S`); `previews` is now `Arc<dyn AiPreviewStore>`, which is
  what the production composition root already holds.

### Added — Per-payload cleanup state for the AI payload GC sweep (issue #206)

The sweep now records a completion mark per payload, so it makes progress
instead of re-selecting the same head of the queue on every run.

- New table `ai_import.ai_payload_cleanup`, keyed `(job_id, payload_kind)`.
  Each row records a *cleanup outcome* for one payload: a successful deletion
  **and** a not-found result (the goal state — the object is gone — holds for
  both, and a terminal job can never be re-claimed to recreate it). The row
  stores the `handle` that was targeted, the `run_id` of the sweep that
  recorded the mark, and `cleaned_at`. A job's two payloads are tracked
  independently, so a sweep that deleted the source but hit a 503 on the
  preview comes back for the preview only.
- `TERMINAL_JOBS_SQL` anti-joins the marks and selects a job only while it
  still owes a payload. Previously it returned the oldest `batch_size`
  terminal jobs unconditionally: deletions are idempotent so nothing was
  corrupted, but every run re-paid the S3 round-trips, re-counted the same
  deletions into `projection_ai_payload_gc_run`, and never advanced past the
  `LIMIT` — a job behind that parked head could outlive its retention window
  indefinitely.
- Marks are written only for deletions that actually happened. A **dry run**
  marks nothing (a mark hides the payload from every future real sweep, so
  marking in observation mode would leak exactly the objects being previewed),
  and a **failed** deletion marks nothing (so it is retried). A **not-found**
  result *is* marked: the goal state holds, and a terminal job can never be
  re-claimed to recreate the payload.
- Marks are flushed before the run-history row and before the early return on
  the first deletion error, so one failure in a batch cannot discard the marks
  its siblings earned.
- `run_gc_sweep` / `spawn_gc_scheduler` / `delete_payload` are now generic over
  `AiPreviewStore + AiDocumentStore` instead of taking the concrete
  `OpenDalAiPayloadStorage`. This is the port dependency the sweep always
  should have had, and it is what lets the partial-batch test inject a
  per-handle deletion failure — Garage accepts every malformed key and reports
  a delete of a nonexistent object as success, so the failure cannot be
  produced through the real adapter without failing the whole batch.
- New migration pair `20260813000001` (table) and `20260813000002` (partial
  index `idx_ai_import_job_retention` on `(updated_at)` covering only
  `status IN ('succeeded', 'dead_letter', 'payload_unavailable')`, built
  `CONCURRENTLY` in its own `-- no-transaction` file). The sweep previously had
  no usable index for its `updated_at` ordering; that was tolerable only while
  it re-read a parked head.

### Changed — Deterministic schedule-apply ids close the retry crash window (issue #182)

`ScheduleApplyWorker` now derives `ShootingDayId` and `SceneShootId`
deterministically from `(preview_id, draft_ref)` via SHA-256 (truncated to
128 bits, tagged with the version-7 / variant-10 bits) instead of generating
random UUIDs. A retry after a command succeeds but its mapping write fails now
re-derives the *same* id, so the aggregate's `ExpectedVersion::Empty` guard
rejects the duplicate (`VersionConflict { current }`, recovered as success by
`recover_version`). Previously the mapping projection was the only duplicate
guard, so a lost reservation row let a retry create a duplicate aggregate. The
mapping projection is preserved as the retry lookup and audit record. This is
the one documented exception to the repository UUIDv7 rule (AGENTS.md §3): a
time-based UUIDv7 cannot be derived from static inputs. Three deterministic
tests cover both crash-window paths (day + scene-shoot) and verify id stability
independent of the mapping projection.

### Added — AI import restart-recovery semantics (issue #181)

Durable payload storage (#174) made a restart survivable; this release defines
what happens when a payload is nonetheless missing, and stops cleanup from
causing that case.

- `PgAiImportQueue::mark_payload_unavailable`: owner-fenced terminal transition
  to `payload_unavailable`. `retries` is left untouched and no
  `next_attempt_at` is set — this is not an attempt that failed, it is the
  discovery that there is nothing left to attempt. Claim, lease and permit link
  are cleared like on every other terminal path, so no reclaim can resurrect
  the job. The claim predicates enumerate `pending` / `failed` /
  expired-`running`, so the new status is unclaimable by construction.
- `ScriptImportWorker` / `ScheduleImportWorker`: a payload load that fails with
  `NotFound` now terminates the job as `payload_unavailable` instead of
  consuming a retry. `ServiceUnavailable` (storage unreachable, bytes probably
  still there) stays retryable — the distinction is the whole point.
- `QueueMergeWorker`: **behaviour change.** A missing schedule preview blob was
  marked `retryable = true`, so a permanently lost payload burned the entire
  retry budget before dead-lettering. It is now terminated as
  `payload_unavailable` on the first attempt.
- **Payload GC retention fix.** The sweep matched `status IN ('succeeded',
  'failed', 'dead_letter')`, but `failed` is the *retryable* state: a job sits
  there with a backoff and is claimed again once it is due. The sweep therefore
  deleted the source document of jobs that were still scheduled to run,
  manufacturing the missing-payload case above. The sweep now matches exactly
  `succeeded`, `dead_letter` and `payload_unavailable`.
  `failed` is excluded **unconditionally**, not merely while it has retry
  budget left: the claim predicates match `status = 'failed' AND
  (next_attempt_at IS NULL OR next_attempt_at <= now())` and never consult
  `retries`, so even a budget-exhausted `failed` row is still claimable.
  Nothing leaks, because `mark_failed` dead-letters a job in the same statement
  that exhausts its budget.
- `UnconfiguredAiPayloadStore`: null-object `AiPreviewStore` / `AiDocumentStore`
  / `AiDocumentSource` that refuses every operation with `ServiceUnavailable`
  (never `NotFound`, which is the signal that permanently dead-ends a job). It
  replaces `MemoryAiPreviewStore` in the composition root when AI import is
  disabled, so a production process can no longer hold a store that accepts
  payloads and silently drops them on restart. `MemoryAiPreviewStore` remains,
  for unit tests only.
- Two new migrations extend the `status` CHECK constraint **without blocking
  writes**, split deliberately across files because sqlx wraps each migration
  in one transaction:
  `20260812000001_ai_import_payload_unavailable` adds the widened constraint
  `NOT VALID` (a fast catalog-only change) and commits, releasing the
  ACCESS EXCLUSIVE lock that `ADD CONSTRAINT` takes;
  `20260812000002_ai_import_payload_unavailable_validate` then runs
  `VALIDATE CONSTRAINT` in its own transaction — verified to take only
  `ShareUpdateExclusiveLock`, so enqueue, claim and lifecycle writes continue
  during deployment — and swaps the constraint names. Validating in the same
  file would have held the exclusive lock across the scan, defeating the point.
  The `002` down migration folds `payload_unavailable` rows into `dead_letter`
  — the closest pre-#181 state that is both terminal and unclaimable — before
  restoring the narrow constraint.

### Added — AI import permit reconciliation (issue #180)

A worker that dies mid-job leaves two leases behind: the job lease (recovered
by the reclaim predicate, #177) and the concurrency permit lease (recovered
only when it lapses, up to `AI_IMPORT_LEASE_SECS` later). The second one is
capacity consumed by a job that is already running elsewhere. This release
closes that gap.

- `AiImportQueue::claim_next_reconciling` / `claim_next_kind_reconciling`:
  claim the next runnable job **and** delete the permit orphaned by the worker
  that previously held it, as data-modifying CTEs of one statement. Returns
  `(job, released_orphan_id)`. Reconciliation is exactly-once — only the
  winner of the `FOR UPDATE SKIP LOCKED` race sees a non-null orphan id and
  the DELETE is by primary key. Both have default implementations that claim
  normally and report no orphan, so backends with no permit link (in-memory,
  test queues) need no change.
- `AiImportQueue::attach_permit`: link the acquired permit to the claim.
  Owner-fenced, so a displaced worker cannot overwrite the new owner's link
  and cause a later reclaim to delete a *live* permit.
- `AiImportQueue::release_claim`: hand a claimed job back unrun without
  charging a retry, used when the concurrency ceiling is saturated. Prevents a
  full ceiling from walking a valid job to `dead_letter`, and makes the job
  runnable immediately rather than after its lease lapses. Owner-fenced.
- `ScriptImportWorker::run_once_with_permit` /
  `ScheduleImportWorker::run_once_with_permit`: **claim, then acquire**, with
  both leases renewed for the whole run — the permit lease via
  `run_with_renewal`, the job claim via a `LeaseHeartbeat` started *before*
  the source load, so a slow document fetch cannot expire the claim underneath
  a working worker. The
  permit is charged to the job's own `user_id`, so
  `AI_IMPORT_MAX_CONCURRENT_JOBS_PER_USER` actually binds; acquiring first
  would mean acquiring before the owning user is known. The orphan is freed by
  the claim, *before* the acquisition, so a reclaiming worker is not refused
  the very slot the dead worker is still holding.
- Every claim path now clears `permit_id`, and every terminal write
  (`mark_succeeded`, `mark_failed`, `release_claim`) clears it again, so the
  link never outlives the claim it describes. This matters most on
  `mark_failed`'s retryable branch: the job stays claimable, so a stale id
  would be read by the next reclaim and deleted — freeing a permit the worker
  already released, and whose id may since belong to someone else. Otherwise a legacy reclaim would carry the dead worker's permit id
  forward and a later reconciling reclaim would delete a permit the current
  owner never attached.
- `ai_import_job` gained a nullable `permit_id UUID` column. No FK: the
  referenced permit may already have been freed by the lease sweep, and an FK
  would turn that ordinary race into a constraint violation.
- New migration `20260811000000_ai_import_claim_with_permit.{up,down}.sql`.

### Fixed — Retry-safe schedule-side scene-shoot apply (issue #179)

- `ScheduleApplyWorker` wrote its idempotency mapping only *after*
  `CreateShootingDay` / `PlanSceneShoot` succeeded. A crash (or a failing
  mapping write) in between left no mapping, so the retry minted a fresh
  `SceneShootId` and dispatched a **second** `PlanSceneShoot`. Because scene
  shoots are keyed by stream identity, the aggregate's `PairAlreadyExists`
  invariant did not catch it — the duplicate only surfaced later at the
  `uq_projection_scene_shoot_pair` constraint, i.e. after the duplicate event
  was already business truth. `resolve_day` had the identical window.
- The worker now follows a **reserve → command → confirm** protocol. The
  aggregate id is persisted as a reservation row (`aggregate_version = 0`)
  *before* the command, so every retry re-drives the *same* aggregate. Both
  commands dispatch with `ExpectedVersion::Empty`, so re-driving an
  already-appended stream returns `VersionConflict { current }` — the worker
  recovers `current` as the version the mapping needs and confirms. A conflict
  reporting version 0 (a genuinely empty stream) is **not** treated as
  recovery and propagates as an error. A still-reserved mapping no longer
  counts as applied work, so the row is re-driven rather than skipped.
- `PgAiImportMappingRepository::reserve` implements the insert-if-absent
  semantics with `ON CONFLICT ... DO UPDATE ... RETURNING` (a plain
  `DO NOTHING` returns no row on conflict, which would force a second round
  trip racing a concurrent confirm). The checked `u64 -> i64` version
  conversion is factored into `version_to_db` and shared with `insert`.

### Fixed — Cancellation-safe AI concurrency permits (issue #178)

- `AiWorkerRuntime::run_job` holds a permit across `operation().await`, which
  is a cancellation point. `Drop` cannot `.await`, so a worker cancelled during
  shutdown never ran `PgAiConcurrencyPermit::release()` and the anonymous
  `ai_import.concurrency_counter` stayed incremented forever. Because the
  increment had no owner, a leaked unit of capacity was indistinguishable from
  a busy one — later AI import jobs were refused admission until an operator
  repaired the row by hand.
- Capacity is now one owned row per permit in the new table
  `ai_import.concurrency_permit` (migration
  `20260810000001_ai_concurrency_permit`), which replaces and drops
  `concurrency_counter`. Owned rows make two reclaim paths possible:
  - **Reclaimer (fast path).** `PgAiConcurrencyLimiter::spawn_reclaimer`
    starts a background task; every permit's `Drop` pushes its id onto an
    unbounded channel (synchronous, non-blocking — the only thing `Drop` can
    do) and the task performs the `DELETE`. Task cancellation therefore returns
    capacity within milliseconds. `PermitReclaimer::shutdown` **drains** the
    queue before returning: shutdown is when workers are cancelled en masse, so
    the queue is fullest exactly when the reclaimer ends, and aborting there
    would push those reclaims back onto the 900s lease. Shutdown order:
    every sender clone must be gone before the channel closes, and permits
    hold one too — so the composition root (1) cancels **and joins** every
    task that may hold a permit, (2) drops every limiter clone, (3) awaits
    `shutdown()`. Skipping a step leaves a live sender and the call would wait
    forever; `abort()` and `Drop` remain for callers that cannot guarantee the
    ordering or cannot await.
  - **Lease (crash safety).** Each row carries `expires_at`. If the process
    dies the reclaimer dies with it, so acquisition first deletes every expired
    row and then counts. The leak is bounded by one lease window with no
    operator action; `PgAiConcurrencyPermit::renew` (interval from
    `permit_renewal_interval`, 1/3 of the window, mirroring `LeaseHeartbeat`)
    keeps legitimately long holders alive. Expiry is **irreversible**: `renew`
    is guarded by `AND expires_at > now()`, so a delayed holder cannot claw
    back a lease the limiter is already entitled to sweep and then hold
    capacity past its own deadline — it gets `Conflict` instead.
  All three paths are `DELETE ... WHERE id = $1`, so double-release is
  impossible by construction. `release()` disarms the drop hook only after a
  *confirmed* delete — its `await` is itself a cancellation point, and an early
  disarm would strand the row until the lease expired.
- `AiWorkerRuntime::run_job` renews the permit while the operation runs
  (`permit_renewal_interval`, 1/3 of the lease). A script job makes one LLM
  call per scene chunk — at defaults up to 128 calls of up to 120s — so without
  renewal the sweep would reclaim a *healthy* holder's row and admit a second
  job on top of it, over-admitting past the very ceiling the limiter enforces.
  The renewal is a `select!` loop in the operation's own task rather than a
  spawned heartbeat: it needs only a `&` borrow (no `Arc`/clone) and is
  inherently cancellation-correct, with nothing to join or abort. A `Conflict`
  aborts the operation — continuing would run on capacity the limiter has
  already handed to someone else. A transient renewal error is retried, but
  **only inside the lease the last confirmed renewal bought**: the loop tracks
  the confirmed deadline, never sleeps past it, bounds the renewal call itself
  with `timeout_at`, and aborts *before* it rather than after — otherwise a run
  of slow failures would carry the job past the point where its row becomes
  reclaimable. The state machine is unit-tested on tokio's paused clock (renews
  across five intervals, aborts on `Conflict`, survives a blip, extends the
  deadline on every confirmation, aborts before expiry under sustained slow
  failures, and never renews for a job shorter than one interval).
- New `PgAiConcurrencyPermit::deadline` exposes the lease deadline, so a holder
  can check its remaining headroom and operational tooling can surface
  "capacity at risk" without reading the table.
- All lease decisions use `clock_timestamp()`, not `now()`. `now()` is fixed at
  transaction start, and the acquisition transaction begins *before* the
  advisory-lock wait — under contention it would judge leases against a stale
  instant, missing rows that have since expired and issuing permits whose
  window silently started before the caller held the lock.
- The permit (and therefore its reclaim hook) is constructed **before**
  `tx.commit()`. `commit()` is an await point and a cancellation there is not
  benign: the COMMIT may already have reached PostgreSQL, so constructing the
  permit afterward would leave a durable row with no local owner — the exact
  leak this module removes, reintroduced at the last possible instant.
- Admission is serialised with `pg_advisory_xact_lock`: counting rows and
  inserting the new one must be atomic, and a row-level lock cannot cover a row
  that does not exist yet, so two concurrent acquisitions could otherwise both
  observe `count < limit` and over-admit.
- Both lease bounds derive from one named `LEASE_UNIT_SECS` (mirroring the
  claim-lease constants in `ai::queue`), with two compile-time assertions: the
  floor/default ordering, and that a renewal still fits strictly inside even
  the *shortest* permitted lease — so raising `RENEWALS_PER_LEASE` or lowering
  the floor cannot silently invert the relationship.
- New additive API: `PgAiConcurrencyLimiter::{spawn_reclaimer, with_lease,
  lease, try_acquire_as, in_flight}`, `PgAiConcurrencyPermit::{id, lease, renew}`,
  `AiWorkerRuntime::run_job_as`, `PermitReclaimer::{shutdown, abort}`,
  `permit_renewal_interval`, `DEFAULT_PERMIT_LEASE`,
  `PgAiConcurrencyPermit::deadline`. `try_acquire`, `release` and `run_job`
  keep their signatures; `run_job` additionally renews the lease it holds.
- Covered by `integration-tests/tests/ai_concurrency_permit_cancellation.rs`:
  a task aborted after acquisition leaves no permit row and the next job
  acquires the capacity; the lifecycle guard does not survive cancellation;
  normal completion and operation errors both release exactly once with the
  result/error preserved; an expired lease is reclaimed by the next
  acquisition; `renew` moves a live deadline forward but reports `Conflict`
  once the permit is expired or swept; `PermitReclaimer::shutdown` drains
  queued reclaims rather than discarding them; and cancelling `try_acquire`
  itself strands no permit. The last test sweeps 40 increasingly late
  cancellation points as best-effort *coverage* of the commit window, not as a
  timing assertion: the invariant it checks (capacity returns without a lease
  wait) must hold for every cancellation point, so no iteration has to land in
  a particular microsecond. Lease expiry is written into the past rather
  than slept out, keeping the suite timing-safe.

### Changed

- Re-pins `breakdown_core` to 0.7.0 (owner-fenced `AiImportQueue` lifecycle
  methods, issue #177).
- **Breaking (source):** `ScriptImportWorker::process` / `::process_text` and
  `ScheduleImportWorker::process` take the claiming `worker_id`, which they
  forward to the now owner-fenced lifecycle writes. `run_once` is unchanged
  (it already received `worker_id`).

### Added — Lease heartbeat for long AI import jobs (issue #177)

- New `ai::heartbeat` module (`LeaseHeartbeat`). A script job makes one LLM
  call per scene chunk — at defaults up to 128 calls of up to 120s, i.e. ~4.3h
  — while the lease is 900s, so the claim would lapse after roughly seven
  chunks and another worker would redo all the paid LLM work. The heartbeat
  renews the claim via the owner-fenced `mark_running` at 1/3 of the lease
  window (two spare renewals absorb a transient database blip).
- The renewal task is stopped before the terminal write and aborted on `Drop`,
  so an early `?` return cannot leak it. Because renewal is owner-fenced it can
  never resurrect a lost claim — it stops and flags `claim_lost`, and the
  script loop then aborts with `Conflict` instead of spending on an LLM call
  for a job it no longer owns.
- The heartbeat is skipped where it cannot help: native-CSV schedule parsing
  and the pure in-process merge are not long-running.
- The `claim_lost` state machine is unit-tested against a scripted queue on
  tokio's paused clock (`start_paused` + `time::advance`), so renewal ticks are
  driven instantly instead of slept out: a `Conflict` renewal flags the claim
  and stops further renewals, a transient error does neither, and `stop()`
  ends renewals before a terminal write. The tests synchronise on a renewal
  notification rather than on a `yield_now()` budget, so they cannot pass or
  fail on scheduler timing.

### Added — Owner fencing for AI import lifecycle writes (issue #177)

- `mark_running`, `mark_succeeded` and `mark_failed` fence their UPDATE on
  `status = 'running' AND worker_id = $N` and return `DomainError::Conflict`
  when no row matches. Reclaiming an expired lease means two workers can
  briefly run the same job; without the fence the displaced worker would
  overwrite the new owner's result (stale `preview_handle`, or failing a job
  another worker just completed). The rejection is logged with the job and
  worker id rather than silently swallowed.
- Because the claim is released on completion, the fence also makes a
  duplicate completion of an already-terminal job a `Conflict` instead of a
  silent overwrite.
- Worker telemetry is fenced too, via the new `record_worker_telemetry`. The
  unfenced `record_telemetry` is retained for the API apply path (terminal job,
  no claim). Both share one `TelemetryValues` conversion so their range checks
  cannot drift.
- `PgAiImportQueue` implements `lease_window()`, which is how workers obtain
  the interval for their heartbeat.

### Added — Worker leases for AI import jobs (issue #177)

- `PgAiImportQueue` now persists the claiming `worker_id` and a
  `lease_expires_at` deadline on every claim. A job whose worker crashed no
  longer stays in `running` forever: once the lease expires, `claim_next` and
  `claim_next_kind` reclaim it atomically (same `FOR UPDATE SKIP LOCKED`
  statement that flips the status), while an unexpired lease keeps a second
  worker out.
- `mark_running` doubles as a lease heartbeat; `mark_succeeded` and
  `mark_failed` release the claim (`worker_id`/`lease_expires_at` set to NULL)
  so `running` stays the only leased state.
- New builder `PgAiImportQueue::with_lease` plus accessor
  `PgAiImportQueue::lease` (MINOR, additive API).
- New environment variable `AI_IMPORT_LEASE_SECS`. An out-of-range *number* is
  clamped to the nearest bound (`30..=86400`); only an absent or unparsable
  value falls back to the `900` default.
- The three bounds derive from one named `LEASE_UNIT_SECS` constant (the
  report-archival recovery horizon) with a compile-time ordering assertion, so
  retuning the horizon cannot silently invert the range.
- Migration `20260809000001_ai_import_worker_lease` adds the two columns and
  expires pre-existing `running` rows so legacy strays become recoverable on
  the first claim. The follow-up migration
  `20260809000002_ai_import_lease_index` builds the
  `(status, lease_expires_at)` index with `CREATE INDEX CONCURRENTLY` so the
  build never blocks writes to `ai_import_job`. It is a separate,
  `-- no-transaction` migration on purpose: sqlx sends a migration file as one
  multi-statement simple query, which Postgres wraps in an implicit
  transaction, and `CONCURRENTLY` cannot run inside a transaction block.

## [0.10.0] - Unreleased

### Changed

- Re-pins `breakdown_core` to 0.6.0 (fallible `AuthorizationPolicy` checks,
  issue #175). No `infra` code change.

### Added — AI payload cleanup worker (issue #198)

- New `ai::payload_cleanup` module with periodic garbage collection for
  AI import payloads in Garage. Deletes source documents and preview
  payloads for terminal-state jobs (succeeded/failed/dead_letter) after
  a configurable grace period (default: 7 days).
- Advisory-locked sweep prevents concurrent cleanup runs.
- Dry-run mode for safe initial rollout (`AI_PAYLOAD_GC_DRY_RUN=true`).
- History table `projection_ai_payload_gc_run` tracks cleanup runs.
- New `AiPayloadGcConfig` type for cleanup configuration.
- Environment variables: `AI_PAYLOAD_GC_ENABLED`, `AI_PAYLOAD_GC_INTERVAL_SECS`,
  `AI_PAYLOAD_GC_MAX_AGE_SECS`, `AI_PAYLOAD_GC_BATCH_SIZE`, `AI_PAYLOAD_GC_DRY_RUN`.
- Re-pins `infra` to 0.10.0 (new ai::payload_cleanup module; MINOR bump).

## [0.9.0] - Unreleased

### Added — Durable AI payload storage (issue #174)

- New `ai::payload_storage` module with `OpenDalAiPayloadStorage` adapter
  that stores source documents and preview payloads in S3-compatible
  object storage (Garage). Replaces `MemoryAiPreviewStore` in production.
- New `AiDocumentStore` trait with `put_source`, `get_source`,
  `delete_source` methods for storing source documents separately from
  preview payloads.
- Source documents and preview payloads now survive API restarts: pending
  jobs can resume, retries can reload source documents, and succeeded
  jobs continue serving previews.
- Environment variables: `AI_PAYLOAD_S3_ENDPOINT`, `AI_PAYLOAD_S3_ACCESS_KEY`,
  `AI_PAYLOAD_S3_SECRET_KEY`, `AI_PAYLOAD_S3_BUCKET`, `AI_PAYLOAD_S3_TLS_ROOT_CERT`.
- Integration test `ai_payload_storage_round_trip` verifies restart-recovery
  behavior and payload lifecycle.

## [0.8.0] - Unreleased

### Added — Centralized LLM provider metadata (issue #173)

- New `ai::provider_registry` module with an exhaustive `PROVIDER_REGISTRY`
  table that maps each `LlmProvider` variant to its canonical key and
  supported aliases. Adding a provider now requires exactly one entry here
  plus a matching arm in core's `as_str` match — no other files change.
- `ai::list_providers()` returns curated provider info for the
  `/ai-import/providers` endpoint.
- `ai::resolve_provider(value)` resolves a user-supplied key or alias to
  its canonical `LlmProvider` variant.
- `ai::curated_models()` and `ai::curated_model_ids()` moved from the
  module-level `curated_models` function into the registry (re-exported
  from `ai`).
- Unit tests covering registry completeness, canonical-key resolution,
  alias resolution, unknown-value rejection, list ordering, model
  coverage, and alias-vs-key non-collision.

### Changed — AI merge worker no longer queries read-model projections (issue #172)

- `QueueMergeWorker` simplified from `QueueMergeWorker<Q, E, S, P>` to
  `QueueMergeWorker<Q, P>`: removed `EpisodeRepository` and `SceneRepository`
  generic parameters. The worker now reads an immutable `MergeInput` blob
  (schedule + pre-loaded scenes) from the preview store and calls
  `merge_from_input()` — never querying a read-model projection at runtime.
- Re-pins `breakdown_core` to 0.5.0 (consumes the new `MergeInput` type;
  under major-zero semver this is a MINOR bump, ADR-020 D2/D3).

## [0.6.0] - 2026-08-07

### Fixed — AI import telemetry: never-applied jobs have NULL edit_distance (issue #171)

- The `ai_import.ai_import_job.edit_distance` column is now **nullable**
  (migration `20260807000001_ai_import_not_applied`). Jobs that never reach
  apply are recorded with `accept_as_is = NULL` and `edit_distance = NULL`;
  an applied job accepted with zero edits keeps `edit_distance = 0` — the two
  outcomes are no longer conflated, so acceptance/edit-rate calculations can
  exclude `NotApplied` jobs.
- The script/schedule/merge workers record `TelemetryApplyState::NotApplied`
  at preview time; the apply path records `Applied { accept_as_is,
  edit_distance }` via the API edge.
- `record_telemetry` binds the apply state as `Option<bool>` / `Option<i32>`
  (NULL for `NotApplied`).

### Changed

- Re-pins `breakdown_core` to 0.4.0 (consumes the new `Telemetry`
  apply-state contract; under major-zero semver this is a MINOR bump,
  ADR-020 D2/D3).

## [0.5.0] - 2026-08-06

### Security fix — AI import provider transport (issue #170)

- Hosted AI providers (OpenAI-compatible) are now reachable over **HTTPS
  only**, and the Ollama endpoint is restricted to **local addresses**.
  Outgoing requests carry a curated redirect policy
  (`curated_provider_redirect_policy`) that blocks redirects to
  non-`https:` hosts for hosted providers and to non-local hosts for Ollama,
  preventing SSRF / credential-exfiltration via redirects.
- **DNS-rebinding guard (hosted regime):** every hosted destination is
  resolved before connecting and rejected unless **all** resolved addresses
  are globally routable — private, loopback, link-local, unique-local,
  CGNAT, multicast, documentation, the 0.0.0.0/8 "this network" range,
  the RFC 2544 benchmarking range (198.18.0.0/15), the Class E reserved
  range (240.0.0.0/4) and the deprecated site-local prefix fec0::/10 are
  blocked even when the hostname and scheme are otherwise allowed;
  IPv4-compatible IPv6 forms (`::a.b.c.d`) are classified by the IPv4 policy
  (`transport::validate_public_resolution`). The validated addresses are
  pinned for the whole request chain (initial request + same-origin
  redirects) via `ClientBuilder::resolve_to_addrs` and system proxies are
  disabled on the hosted client (they would resolve the CONNECT target
  outside the pin) (`transport::build_hosted_client`) — a rebinding attacker
  cannot point the connection at an internal service after validation.
- `OpenAiCompatibleModelCatalog::new` now builds its own HTTP client with the
  redirect policy and a fixed 30-second request deadline. **Breaking change:**
  the `new(http: reqwest::Client) -> Self` signature was replaced by
  `new() -> Result<Self, DomainError>` (under major-zero semver this is
  released as a minor bump; no in-tree caller used the old signature). A
  test seam `with_http(client)` remains for injected clients.
- `OpenAiCompatibleChatClient::new` is now **`async`** (it performs the
  resolution guard and pins the validated provider address). **Breaking
  change:** `new(provider, api_key, timeout)` must now be awaited.

### Added (additive public API)

- New `ai::transport` module with the redirect-policy constructors
  `curated_provider_redirect_policy`, `hosted_provider_redirect_policy` and
  `ollama_redirect_policy` (re-exported from `ai`).
- New `ai::transport::validate_public_resolution` (async DNS resolution
  guard for the hosted regime) and `ai::transport::build_hosted_client`
  (validated + pinned hosted client builder).

### Internal

- Follow-up refinements to the ADR-020/ADR-021 versioning rollout: projector
  `projector_version` guards, event/wire fixture contract tests and
  integration-test fixtures aligned with the released projection schema.

### Dependency updates (ADR-020 D7 bookkeeping)

- opendal 0.52 → 0.58 (S3 / GDrive storage)
- aes-gcm 0.10 → 0.11, base64 0.22 → 0.23, getrandom 0.3 → 0.4,
  rand_core 0.6 → 0.10, redis 1.4 → 1.5, schemars 1.2.1 → 1.2.2,
  serde 1.0.228 → 1.0.229, sha2 0.10 → 0.11
