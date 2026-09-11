<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: omen-alpha (opencode-go) -->

# Tasks: Projector dead-letter + health signal (issue #37)

## 1. kameo_es patch (`.patches/kameo_es`)

- [x] Add `EventErrorClassify` trait (`is_permanent_event_error`,
      `permanent_error_details`) + `sqlx::Error` impl (SQLSTATE class 23/22
      permanent; ColumnDecode permanent; rest transient) in
      `src/event_handler.rs`.
- [x] Add `EventHandlerError::is_permanent_event_error` (DeserializeEvent /
      ParseID permanent; Sierra / EventFromSierra / Processor transient;
      Handler delegates).
- [x] `PostgresProcessor` + `Worker`: `dead_letter_table` field (default
      `projection_dead_letter`) + builder override; bound propagation
      (`H::Error: EventErrorClassify`).
- [x] `Worker::handle_event`: destructure the retry-exhausted error *before*
      any await (Send-safety), classify, and route permanent errors through
      `Worker::dead_letter_event` (DLQ upsert + checkpoint advance in one
      transaction, idempotent via PK conflict → `attempts` bump, in-memory
      handled/flushed maps updated, `tracing::error!` with #37 marker).
- [x] Classification unit tests (9 cases: FK/unique/not-null/check, class 22,
      40001/40P01/08xxx transient, ColumnDecode, wrapper variants, details
      extraction).

## 2. infra

- [x] Migration `20260815000001_projection_dead_letter` (up/down).
- [x] `crates/infra/src/projectors/health.rs`:
      `ProjectorHealthRepository` (`list_dead_letters`, `dead_letter_count`,
      `checkpoint_progress`) + `DeadLetterEntry` / `CheckpointProgress`;
      re-exported at `infra::projectors`.
- [x] `ProjectorFlushConfig::apply` carries the new `EventErrorClassify`
      bound.

## 3. Tests

- [x] Tier-4 `crates/integration-tests/tests/projector_dead_letter_tests.rs`:
      FK-violation repro (assign costume to never-created character) →
      DLQ row (SQLSTATE 23503 + constraint), checkpoint advances past the
      poison event, trailing event on the same stream still processed,
      health queries surface the poison event; pre-poison unflushed event
      (DetailAdded) asserted to survive atomically (review finding).
- [x] Stream-layer dead-letter for undecodable Sierra messages (issue #411,
      review follow-up): raw event carried through
      `TryFromSierraEventError`/`NextEventError::UndecodableEvent`, new
      `EventProcessor::dead_letter_undecodable` (propagating default for
      in-process processors; `PostgresProcessor` writes DLQ + checkpoint
      atomically), corrupt-payload regression test.

## 4. Docs & governance

- [x] `docs/operations/runbooks.md` → new section "Projector dead-letter
      health (issue #37)" (DLQ SQL, reprocessing procedure, do-not-delete-
      events note); #404 replay section cross-references the DLQ.
- [x] Doctrine updated: `backend/AGENTS.md` §1 (c) and
      `backend/.github/instructions/architecture-hard-rules.instructions.md`
      (shipped state replaces the "#404 minimal / #37 target" wording).
- [x] `crates/infra/CHANGELOG.md` entry (rides the open 0.16.0 MINOR).
- [x] Follow-up issue for an operator-facing HTTP health endpoint (requires
      a new authorization capability — out of scope here).

## 5. Validation

- [x] `cargo check --workspace` clean.
- [x] `cargo clippy --workspace --all-targets -- -D warnings` clean.
- [x] `cargo test -p kameo_es --features postgres` (classification tests).
- [x] `cargo test -p infra` (all suites, including the new health module).
- [x] `cargo test -p integration-tests --test projector_dead_letter_tests`
      and the #404 skip regression suites (season numbering, scene-shoot
      pair) still green.
