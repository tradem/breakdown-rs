<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# ai-import

## ADDED Requirements

### Requirement: A live apply run keeps its single-flight slot while it executes

The apply slot SHALL be single-flight per job, and an owner that is still executing SHALL
keep it no matter how long the run takes. Because the slot's staleness predicate is
silence-based, an executing run SHALL renew its own claim (owner-fenced on the run
identity) while it works: a schedule apply publishes no progress frames, so silence alone
cannot distinguish it from a crashed owner.

The renewal SHALL only prove aliveness — it SHALL NOT write progress, advance the run
counter, or wake the apply stream. It SHALL be bounded by the same window the steal
predicate reads (`ApplyProgress::STALE_AFTER`), renewed at a strict fraction of it.

#### Scenario: A schedule run longer than the staleness window is not stolen

- **WHEN** a schedule apply has been executing for longer than `ApplyProgress::STALE_AFTER`
- **AND** it renews its claim during that time
- **THEN** a second dispatch SHALL be refused (`409 ai-import.apply-in-flight`)
- **AND** the worker poll SHALL NOT hand the slot to another replica

#### Scenario: A dead owner still becomes stealable

- **WHEN** the process owning a `running` apply slot dies
- **THEN** the renewals SHALL stop with that run's task
- **AND** after `ApplyProgress::STALE_AFTER` the next poll SHALL take the slot over
- **AND** the displaced run's renewal SHALL report `false` instead of renewing
