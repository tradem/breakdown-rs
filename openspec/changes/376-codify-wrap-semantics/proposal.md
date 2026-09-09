<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: omen-alpha (pi) -->

# Codify wrap semantics: planning stays allowed (201), execution frozen (409)

## Why

The on-emulator smoke for `flutter-shoot-day-execution` (task 4.1) observed:
post-wrap `plan` → 201, post-wrap `start` → 409. Issue #376 asked to codify
this split in the contract.

**Drift check finding:** the observed post-wrap 409 on `start` was *incidental*
(status/version conflict from the smoke sequence — start/finish/skip ran
before wrap), not a wrap freeze. No `wrapped_at` check existed anywhere in the
execution command path: a fresh, correctly-versioned `start` on a wrapped day
returned **200**. Documenting "execution 409 post-wrap" without code change
would have codified a false contract (option rejected by the user).

## What Changes

- **Implement the freeze** so the contract documents enforced behavior:
  execution transitions on a wrapped shooting day are rejected with **409
  `scene-shoot.shooting-day-wrapped`** — `start`, `actual-order`, `finish`,
  `skip`, and note add/update/remove.
- **Planning (Soll) stays supported post-wrap**: `plan` (201), `replan` (200),
  and continuity-photo link/unlink are NOT frozen.
- Enforcement lives at the **API edge** (handler-level gate reading the
  shooting-day projection) — the only CQRS-legal read-model consumer. The
  projector-lag race (wrap → immediate execution) is accepted: the wrap event
  is projected with version guards, the client's D3 finality copy keeps
  wrapped boards read-only, and the alternative (write-side projection read)
  is a hard-rule violation.
- **Document** the split via utoipa descriptions on the wrap/plan/execution
  handlers (flows into `backend/openapi.yaml` on regen).
- New problem code in the `problem_codes!` registry: `scene-shoot.shooting-day-wrapped`
  (409, `shooting_day_id` extension S0 — path-supplied).

## Impact

- Affected specs: `specs/scene-shoots` (behavior), `backend/openapi.yaml`
  (descriptions + 409 doc on execution handlers)
- Affected code: `crates/core` (registry + `DomainError`), `crates/api`
  (handler gate, problem rendering, locales, handler tests), `docs/errors`
- Dart client: regenerated via `scripts/regen-client.sh` if the generator
  output changes (descriptions do not alter DTO shapes)
- The Flutter client's D3 finality assumption ("wrapped day = read-only
  board, no undo") is now contractually enforced by the backend.
