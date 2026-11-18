<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# Remove the runtime-lifetime race in `audit_cross_cutting_tests` (issue #820)

## Why

`non_membership_events_produce_attributed_audit_rows` (6.1) intermittently failed
in the *Testcontainers integration tests (Postgres + SierraDB)* job with

```
Error: list_by_entity failed: conflict: error communicating with database:
       A Tokio 1.x context was found, but it is being shutdown.
```

right after 6.4 (`..._idempotent_under_redelivery`) finished; a re-run passed.
The failure is a **harness runtime-lifetime race**, not an assertion:

- the file shares one container pair + two `PgPool`s + the Redis client via
  `OnceLock<SharedContainers>`, all created on ONE long-lived runtime that is
  deliberately kept alive;
- every test was a `#[tokio::test]`, i.e. it built **and dropped its own
  runtime**;
- `sqlx`/`redis-rs` bind a connection's background task to the runtime the
  connection was *established* on. A pool connection sqlx lazily re-establishes
  inside such a test is owned by that test's runtime and dies at teardown — but
  stays in the shared pool. The next test reading it gets the shutdown error.

## Drift check

No prior fix exists: the file header only documents the *nested-runtime* problem
(containers initialised on a background thread), and #152 added retry on
transient `pool timed out` — a *shutdown* runtime is not covered by it (and a
retry would be handed the same dead connection again). `git log` on the file
shows the last touch was the wardrobe split (`709ad064`); the flake is older.
The shared-pool-across-tests pattern is unique to this file — `OnceLock` occurs
in no other integration-test file — so the fix is contained.

## What changes

`crates/integration-tests/tests/audit_cross_cutting_tests.rs` only:

1. `SharedContainers::_runtime` → `SharedContainers::runtime` (it is now used,
   not merely kept alive; the "must stay alive" contract moved into its doc
   comment).
2. New helper `run_on_shared_runtime(body)` — drives an async test body with
   `runtime.block_on(...)` on the shared runtime and asserts
   `Handle::current().id() == runtime.handle().id()`, so a body that ever ends up
   on a foreign runtime fails **immediately with the reason** instead of flaking
   one test later on a connection it never touched.
3. All five tests (`6.1`–`6.4`) become plain `#[test]` wrappers around their
   unchanged async bodies (`<name>_body()`); no assertion, sleep, deadline or
   event sequence was touched, nothing is `#[ignore]`d.
4. The module docs state the one-runtime rule; `is_retryable_pool_error`'s docs
   record why the shutdown class is *removed* rather than retried (criterion 2
   of the issue: "impossible **or** retried").
5. 6.2 keeps spawning `spawn_costume_category_projector`; it now outlives the
   test body on the shared runtime (previously a per-test runtime killed it).
   Documented in place: it owns no per-test state, writes only upserts to
   `projection_costume_category`, and no later test asserts that projection.
6. Spec delta in `specs/sierradb-round-trip-testing/spec.md`: the rule is now a
   requirement (one runtime per shared-pool harness, guard, no shutdown-runtime
   error reaching an assertion), so it is reviewable beyond this one file.

## Acceptance criteria mapping

| AC | How |
|---|---|
| No test can observe a pool connection bound to a dead runtime | The process has exactly one runtime; every body runs on it, so every connection is established on it. Guarded by the `Handle::id()` assertion in `run_on_shared_runtime`. |
| Shutdown error impossible **or** retried with a fresh connection | Impossible — chosen over retry, because a retry against the shared pool can be handed the same poisoned connection. Rationale recorded on `is_retryable_pool_error`. |
| 10 consecutive CI runs green | Not verifiable locally; 5/5 local runs green (4 sequential `--test-threads=1`, 1 parallel). The mechanism, not a symptom, was removed — CI history stays the evidence. |
| No assertion weakened, no `#[ignore]` | Diff is mechanical (attribute + wrapper + docs); zero assertion bodies changed. |

## Risks / non-goals

- Non-goal: other integration-test files. They create containers *inside* the
  test's own runtime, so their connections live and die with that test — no
  cross-test sharing, no dead-runtime window.
- `#[tokio::test]` in this file would reintroduce the bug; the guard converts
  that into a loud, immediate failure (message names issue #820).
