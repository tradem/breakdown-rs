<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# flutter-ai-import-workflow

## ADDED Requirements

### Requirement: The post-apply hop resolves its target from the persisted summary

The post-apply navigation hop SHALL resolve its target episode from the apply
response when that response names applied episodes, and otherwise from the job's
**persisted** applied-episode summary, read from the local cache. It SHALL NOT
drop straight to the request's episode while a durable answer exists.

The fallback is load-bearing and not cosmetic: a re-apply of an already-applied
preview dispatches nothing (every row is settled by its confirmed mapping), so
its response carries an empty list while the job still says where the rows are.

Because a persisted summary describes **earlier** applies, it SHALL only answer
WHERE to go: the report published at the destination SHALL list as "also
applied" only the episodes **this** request dispatched (the response's own
list), never the historical summary's remaining entries, so no earlier row count
is attributed to the request the user just confirmed.

The fallback SHALL remain a cache read: the navigation path SHALL NOT wait for,
or depend on, the network. An absent, offline or undecodable cached summary SHALL
degrade to the existing honest behaviour — navigation is skipped and the outcome
card stays in place. No id or number SHALL ever be invented.

The resolution SHALL tell the caller whether the server knows a target episode at
all, so the "the imported episode could not be opened" hint is shown exactly when
a target exists but does not resolve from the read caches. A job with no target
episode whatsoever — a schedule merge, or nothing ever applied — SHALL keep the
outcome card **without** that hint.

A successful apply SHALL reconcile the job projection (re-run the jobs list and
drop the job-scoped summary read) so the server-derived summary reaches the cache
for a later hop, without the hop itself awaiting it.

#### Scenario: A re-apply with an empty response still lands on the imported episode

- **WHEN** an apply answers an empty applied-episode list but the cached job row
  carries a persisted summary naming episode 299 "Erlösung"
- **THEN** the app leaves the review screen for the Script destination with that
  episode in scope

#### Scenario: A persisted target never donates its historical counts

- **WHEN** the persisted summary names two episodes with 57 and 4 rows
- **THEN** the destination report lists no "also applied" episode for this
  request, because it dispatched none

#### Scenario: A known target that cannot be resolved still says so

- **WHEN** the persisted summary names an episode whose season the read caches do
  not hold
- **THEN** the review screen stays with the outcome card AND the explicit hint

#### Scenario: An offline or unknown job degrades honestly

- **WHEN** the response names no episode and the cached job row is unknown or its
  summary undecodable
- **THEN** navigation is skipped, the outcome card stays, and nothing is invented
