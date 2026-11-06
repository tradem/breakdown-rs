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

The fallback SHALL remain a cache read: the navigation path SHALL NOT wait for,
or depend on, the network. An absent, offline or undecodable cached summary SHALL
degrade to the existing honest behaviour — the request's episode, and then no
navigation at all with the outcome card kept in place. No id or number SHALL ever
be invented.

#### Scenario: A re-apply with an empty response still lands on the imported episode

- **WHEN** an apply answers an empty applied-episode list but the cached job row
  carries a persisted summary naming episode 299 "Erlösung"
- **THEN** the app leaves the review screen for the Script destination with that
  episode in scope

#### Scenario: An offline or unknown job degrades honestly

- **WHEN** the response names no episode and the cached job row is unknown or its
  summary undecodable
- **THEN** the existing fallback applies (the request's episode, else the outcome
  card with its hint) and nothing is invented
