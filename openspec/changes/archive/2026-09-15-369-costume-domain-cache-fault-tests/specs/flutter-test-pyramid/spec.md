<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: omen-alpha (opencode-go) -->

## ADDED Requirements

### Requirement: Deterministic Fault-Seam Coverage for Defensive Cache-Fault Branches
Defensive cache-fault-mapping branches in `data/` repositories that translate
Drift/DAO failures into `Left(ProblemError(code: 'cache.*_failed'))`
(`cache.write_failed`, `cache.read_failed`, `cache.clear_failed`) SHALL be
covered by deterministic fault-injection tests exercising BOTH the `Ok` and
the `Err` branch, because a closed in-memory Drift database does not reliably
produce DAO faults. The fault seam SHALL be a scriptable DAO fake that
wraps a real in-memory DAO and throws on demand per operation phase
(write / read / clear); cache-untouched-on-failure SHALL be asserted against
the wrapped real DAO's persisted state. The seam is test-only: production
`try`/`on Object` mapping stays unchanged. Tests MUST be headless and
deterministic (fixed fake clock, scriptable transport, no wall-clock
budgets, no real network).

#### Scenario: A costume-domain repository cache write faults
- **WHEN** the DAO's snapshot/upsert write path throws while the network
  fetch succeeded.
- **THEN** the repository resolves `Left('cache.write_failed')` and the cache
  retains exactly its prior state (the faulted write never lands).

#### Scenario: A costume-domain repository cache read faults
- **WHEN** the DAO's read path throws.
- **THEN** the repository resolves `Left('cache.read_failed')` without
  issuing a network call.

#### Scenario: A costume-domain repository cache clear faults
- **WHEN** the DAO's clear path throws.
- **THEN** the repository resolves `Left('cache.clear_failed')` and the
  cached rows survive.
