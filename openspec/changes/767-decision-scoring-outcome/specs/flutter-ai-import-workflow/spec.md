<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# flutter-ai-import-workflow Delta (767-decision-scoring-outcome)

## ADDED Requirements

### Requirement: A row whose scoring failed states it
A preview row whose own scoring request failed (`DecisionRubric.scoringFailed`
is `true`) SHALL render an explicit, localized, non-blocking failure state
("Bewertung fehlgeschlagen – keine Sternchen" / "Scoring failed — no stars.")
in the same visual language as the other degradation surfaces. The row SHALL
NOT render a rating for it, and a row without any rubric — where the pass
genuinely never ran — SHALL render nothing extra: the failure state names a
failure, not an absence.

#### Scenario: The scoring request for a row failed
- **WHEN** a script preview row carries a rubric with `scoringFailed: true` and no score
- **THEN** the row renders the localized failure line and no star rating

#### Scenario: The pass never ran for a row
- **WHEN** a preview row carries no rubric at all
- **THEN** the row renders neither the failure line nor a rating

#### Scenario: A scored row is unaffected
- **WHEN** a preview row carries a score and a rubric with `scoringFailed: false`
- **THEN** the row renders its stars and no failure line

### Requirement: The preview and job view name the effective Decision Model
The preview header and the job cost card SHALL state the **effective Decision
Model** of the import from the job's recorded `decision_telemetry`: the
resolved `provider / model` when the pass ran, and otherwise the reason class —
distinguishing "no model configured" (`skipped_no_config`), "model unavailable"
(`client_unavailable`) and "scoring failed" (`scoring_failed`, with the affected
row count). The copy SHALL be keyed on the stable outcome class only, never on
backend prose, and SHALL be localized in German and English. A job that
recorded no outcome (a pre-#767 row, or a failed read) SHALL render no line at
all — never a guessed class.

#### Scenario: The pass ran with a configured model
- **WHEN** the job's `decision_telemetry.outcome` is `ran`
- **THEN** the preview header states the resolved `provider / model`

#### Scenario: The import ran without a Decision Model
- **WHEN** the job's outcome is `skipped_no_config`
- **THEN** the header states that no model was configured — distinguishable from the `client_unavailable` copy, which names the configured pair

#### Scenario: The scoring pass failed
- **WHEN** the job's outcome is `scoring_failed` with `failed_rows = N`
- **THEN** the header names the failure and the number of affected rows, in both locales (correct singular/plural)

#### Scenario: The job recorded no outcome
- **WHEN** the job carries `decision_telemetry: null`
- **THEN** neither the preview header nor the job cost card renders an outcome line

### Requirement: The Decision Model outcome is read without a second stream
The client SHALL read the job-level outcome through ONE snapshot read of
`GET /v1/ai-import/jobs/{id}` (or the job the screen already holds) and SHALL
NOT add a second SSE consumer: the job-status controller stays the app's only
event-stream subscriber (battery contract D5).

#### Scenario: The preview screen states the outcome
- **WHEN** the preview screen renders for a job with a recorded outcome
- **THEN** the outcome line appears without opening an event stream

#### Scenario: The cost card states the outcome
- **WHEN** the job status screen already holds the job
- **THEN** the cost card renders the outcome line from that job without an additional read
