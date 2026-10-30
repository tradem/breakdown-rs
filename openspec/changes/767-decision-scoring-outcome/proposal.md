<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# 767 — A configured Decision Model states its scoring outcome instead of going silent

## Why

Issue #767: a Decision Model was configured in the app (provider + model + key,
saved through the AI-config screen; the round trip was verified by #769). A
subsequent script import produced **no star ratings in the preview** — and
**no way to find out why**.

Verified in the tree: every part of the transport/persistence chain is
complete (app create/PATCH send the triple, the aggregate validates and
persists it, the projector columns are written, the worker resolves the triple
per claimed job and builds the pass best-effort, the scoring pass writes
`scene_score`/`synopsis_score`/`DraftShootingDay.score`, the wire carries them
and the preview renders stars whenever a score is non-null). The defect is the
**silence** around four different failure causes, all of which collapse into
the same user-visible "no stars, no explanation":

| Cause | Backend signal before | User-visible signal |
|---|---|---|
| No decision config resolved (`config.decision == None`) | **none** — no log at all | stars absent |
| Decision client build failed (credential/transport) | one `warn` | stars absent |
| Scoring call failed after the quick retry | `warn` + `scoring_failed: true` on the row's rubric | stars absent — **the app never read the rubric** |
| Partial/incomplete provider answers | scores are honestly `None` | stars absent |

`frontend-flutter/lib/**` contained **no** reference to `scoring` /
`scoringFailed` / `DecisionRubric`: the entire rubric the backend records was
unused by the client, and nothing on the job said whether the worker had a
Decision Model at all. Answering the reporter's question ("did my config even
reach the backend?") required server log access.

There was also **no test coverage for the configured path**: every AI-config
fixture set `decision_provider: None`, so "configure a Decision Model and get
scores" could silently do nothing forever.

## What changes

1. **The job records its decision outcome (additive).**
   `AiImportJob.decision_telemetry: Option<DecisionTelemetry>` carries the
   resolved `provider`/`model`, an `outcome` class
   (`ran | skipped_no_config | client_unavailable | scoring_failed |
   skipped_not_applicable`) and `failed_rows`. It is written by the **same
   owner-fenced completion write** as the extraction telemetry
   (`record_worker_telemetry`, new JSONB column `decision_telemetry`,
   migration `20261102000001`), so it can never describe a run that did not
   happen. `serde(default)` + `NULL` for pre-#767 rows: an older client reading
   a newer view and a newer client reading an older row both stay honest — an
   unrecorded outcome renders as *nothing*, never as a guessed class.

2. **The two traceless paths become greppable.** An `info` log with `job_id`
   and `config_id` is emitted when no decision configuration resolves at claim
   time (previously: no log at all), and the existing `warn`s for the
   credential/build failure and the scoring failure are kept. All four paths
   are now answerable for a given `job_id`.

3. **The worker carries the *reason*.** `ScriptImportWorker.decision` /
   `ScheduleImportWorker.decision` change from a bare
   `Option<Arc<DecisionPass>>` — which cannot distinguish "nothing was
   configured" from "configured but unbuildable" — to
   `Option<DecisionResolution>`; the scoring passes report how many rows they
   left unscored.

4. **The client surfaces it.**
   - **Per row:** a row whose `DecisionRubric.scoringFailed` is `true` renders
     an explicit, localized, non-blocking failure line ("Bewertung
     fehlgeschlagen – keine Sternchen" / "Scoring failed — no stars.") instead
     of unexplained empty space — and never a fabricated rating.
   - **Per job:** the preview header and the job cost card name the **effective
     Decision Model** when the pass ran, and otherwise state the reason class,
     distinguishing "no model configured" from "model unavailable" from
     "scoring failed".

5. **Tests (the actual regression guard).** The configured path is asserted end
   to end through the production worker (non-null `scene_score` /
   `synopsis_score`, rubric `decision_provider`/`decision_model` matching the
   configuration, outcome `ran`), the three degradation paths are asserted
   (`client_unavailable` with the job still succeeding and no decision request
   issued, `skipped_no_config`, `scoring_failed` with its row count), the
   credential failure is asserted at the worker-loop boundary, the additive
   wire contract is asserted in both directions, and a Postgres integration
   test round-trips the new column. Flutter: unit tests for every outcome class
   (de + en, including pluralization) and widget tests for the row failure
   state, the header line, the cost card, and the "no recorded outcome renders
   nothing" arms.

## Impact

- **Specs:** `ai-import` (ADDED: recorded scoring outcome on the job, greppable
  degradation logs, row-count reporting), `flutter-ai-import-workflow` (ADDED:
  per-row failure state, effective-decision-model line on preview and cost
  card).
- **Backend:** `core` (`DecisionOutcome`, `DecisionTelemetry`,
  `AiImportJob.decision_telemetry`, `Telemetry.decision`), `infra`
  (`DecisionResolution` + resolution-aware worker slots, scoring-pass row
  counts, `resolve_decision` with the `info` log, migration + JSONB
  write/decode). Versions `core 0.50.0 → 0.51.0`, `infra 0.59.0 → 0.60.0`,
  `api 0.49.0 → 0.50.0`; `openapi.yaml` regenerated.
- **Frontend:** `vendor/breakdown_api/` regenerated (`DecisionTelemetry`,
  `DecisionOutcome`, `AiImportJob.decisionTelemetry`),
  `lib/features/ai_import/import_jobs/decision_outcome.dart` (new: outcome
  provider, copy mapping, header line, per-row note), `preview_screen.dart`,
  `job_status_screen.dart`, ARB catalogs de+en + regenerated l10n.
- **Not changed:** the extraction path's own behaviour, the per-row scores
  themselves, the Decision Model configuration UI (issue #722/#723, #769), and
  the cost/pricing model — the sibling defect of Decision-Model token usage
  being priced at the extraction model's rates is a separate issue (#768).
