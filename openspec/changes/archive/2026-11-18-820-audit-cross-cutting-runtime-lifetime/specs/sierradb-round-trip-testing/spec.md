<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

## ADDED Requirements

### Requirement: Shared-pool test harnesses drive every body on one runtime
A Tier-4 integration test file that shares containers and pools across its tests
(a `OnceLock`-style harness) SHALL create them on **one** long-lived runtime and
SHALL drive **every** async test body on that same runtime. A test body SHALL NOT
run on a runtime the test itself built (i.e. `#[tokio::test]`), because
`sqlx`/`redis-rs` bind a connection's background work to the runtime that
established the connection: a connection lazily re-established inside a
per-test runtime is owned by that runtime, dies at its teardown, and is then
handed out of the shared pool to the next test — surfacing as
`A Tokio 1.x context was found, but it is being shutdown` (issue #820).

#### Scenario: A shared-harness body never runs on a foreign runtime
- **WHEN** a test of a shared-pool harness executes
- **THEN** its body is driven with `block_on` on the harness runtime
- **AND** the harness fails immediately — naming the runtime-lifetime rule and
  issue #820 — if the ambient runtime is not the harness runtime, instead of
  flaking one test later on a connection the test never touched

#### Scenario: No shutdown-runtime pool error reaches an assertion
- **WHEN** two tests of such a harness run sequentially (`--test-threads=1`)
  against the shared pools
- **THEN** no query of the second test observes a connection bound to the first
  test's torn-down runtime
- **AND** the failure class is removed at the source, not retried against the
  same poisoned pool
