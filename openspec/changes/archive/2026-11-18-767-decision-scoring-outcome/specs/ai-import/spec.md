<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# ai-import Delta (767-decision-scoring-outcome)

## ADDED Requirements

### Requirement: The job records the Decision Model scoring outcome
Every import job SHALL record what its optional Decision Model scoring pass did,
as an additive `decision_telemetry` on the `AiImportJob` view:
`provider` and `model` (the pair the job **resolved**), an `outcome` class and
`failed_rows`. The outcome SHALL be one of exactly
`ran` (the pass answered), `skipped_no_config` (no configuration resolved),
`client_unavailable` (configured, but the decision client could not be built),
`scoring_failed` (the pass ran and at least one unit failed after the bounded
retry) or `skipped_not_applicable` (the job had nothing to score: a native CSV
schedule, or a pure merge). The record SHALL be written by the same
owner-fenced completion write as the extraction telemetry, so it can never
describe a run that did not happen. `provider`/`model` SHALL be present for
`ran`, `client_unavailable` and `scoring_failed` — a configured pair is named
even when it produced nothing, which is what distinguishes "never configured"
from "configured but unavailable". `failed_rows` SHALL count the preview rows
whose own scoring request failed (one missed unit counts its rows, never the
job).

#### Scenario: A configured pass ran
- **WHEN** a script job resolves a decision triple, builds its client and every scoring request answers
- **THEN** its `decision_telemetry.outcome` is `ran`, `provider`/`model` name the resolved pair and `failed_rows` is `0`
- **AND** the preview rows carry non-null `scene_score`/`synopsis_score` with a rubric naming that same pair

#### Scenario: The decision client could not be built
- **WHEN** the resolved decision configuration's credential fetch or transport build fails
- **THEN** the job still succeeds, no scoring request is issued and every score stays `null`
- **AND** `decision_telemetry.outcome` is `client_unavailable` with the resolved `provider`/`model`

#### Scenario: No decision configuration resolved
- **WHEN** a job is claimed for a user whose AI config carries no decision triple
- **THEN** the job runs without a scoring pass
- **AND** `decision_telemetry.outcome` is `skipped_no_config` with no provider/model

#### Scenario: The scoring request failed
- **WHEN** a scoring request fails after the bounded quick retry
- **THEN** the job still succeeds, the affected rows keep a rubric with `scoring_failed: true` and no score
- **AND** `decision_telemetry.outcome` is `scoring_failed` and `failed_rows` equals the number of rows left unscored

#### Scenario: A job recorded before the field existed
- **WHEN** a client reads a job stored before `decision_telemetry` existed
- **THEN** the field deserializes as `null` (never a fabricated outcome)
- **AND** the job remains readable through every existing route

### Requirement: The four Decision Model degradation paths are greppable
The worker SHALL log the previously traceless path — a claim that resolves no
decision configuration — at `info` with the `job_id` and the resolved
`config_id`, and SHALL keep the `warn` records for the credential/build failure
and the scoring failure. No decision-scoring degradation may be silent.

#### Scenario: A missing decision configuration is logged
- **WHEN** a claimed job resolves an AI config with no decision triple
- **THEN** an `info` record carries the `job_id` and the `config_id`
- **AND** the same `job_id` appears in the `warn` records of the other three failure paths when they occur

### Requirement: The configured scoring path is covered end to end
The configured Decision Model path SHALL be asserted through the production
worker with a fake decision client (non-null scores, rubric provider/model
matching the configuration, `ran` outcome), and each degradation path SHALL be
asserted for its outcome class, its row count and its "the job still succeeds"
guarantee.

#### Scenario: A configured Decision Model yields scores
- **WHEN** the test suite processes a script job with a configured decision triple and a fake decision client
- **THEN** the preview rows carry non-null `scene_score`/`synopsis_score`
- **AND** their rubric's `decision_provider`/`decision_model` equal the configured pair
