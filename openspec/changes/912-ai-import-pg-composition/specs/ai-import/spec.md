<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# ai-import

## ADDED Requirements

### Requirement: Both surfaces that report an apply outcome name the run that produced it

Every HTTP surface that reports an apply run's state SHALL carry the identity of
the run that produced the reported outcome — `apply_run_id` on
`GET /v1/ai-import/jobs/{id}` and `run_id` on every `apply-events` frame. The
identity SHALL be resolved by one rule: the run that currently **owns** the
job's apply slot while it is live, otherwise the run recorded next to the
persisted outcome (ownership is released at the terminal transition so the slot
frees immediately, while attribution must survive).

A client compares this id against the run id its dispatch returned before
believing an outcome is its own, so a surface that omits or invents it makes a
client report another run's counters as its own import.

#### Scenario: a live run is reported by both surfaces

- **WHEN** a run owns the job's apply slot and has published progress
- **THEN** `GET /v1/ai-import/jobs/{id}` SHALL report that run's id as `apply_run_id`
- **AND** the `apply-events` frames SHALL report the same id as `run_id`

#### Scenario: a finished run keeps its identity after ownership is released

- **WHEN** a run reaches a terminal apply state
- **THEN** the slot SHALL free immediately (a subsequent dispatch is accepted without a staleness wait)
- **AND** both surfaces SHALL still report the finished run's id, not `null` and not the id of a run that has not started

#### Scenario: a later run supersedes the earlier one on both surfaces

- **WHEN** a second run claims the freed slot and finishes
- **THEN** both surfaces SHALL report the second run's id
- **AND** a client still holding the first run's id SHALL be able to detect the supersession by comparing them

#### Scenario: the composition of both surfaces is covered

- **WHEN** the CI runs the container-gated composition case for this chain
- **THEN** a handler that stops surfacing `apply_run_id` on the job read SHALL fail it
- **AND** a handler that stops surfacing `run_id` on the terminal frame SHALL fail it
