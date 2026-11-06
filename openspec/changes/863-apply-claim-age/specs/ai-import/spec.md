<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# ai-import

## ADDED Requirements

### Requirement: The blocked-apply age also covers a claim that published no frame

The `409 ai-import.apply-in-flight` refusal SHALL report
`apply_run_age_seconds` for **every** run that owns the apply-run slot,
including a run that claimed the slot and has published no progress frame
yet. The age SHALL be derived from the same owner-scoped timestamp the
single-flight claim's steal predicate judges an unpublished owner by — the
instant that run's own claim took the slot (`apply_claim_at`) — so the reported
age and the steal decision can never disagree, and no other run's write can move
either:

- a run that published a frame SHALL be aged from that payload's
  `updated_at` (the stamp the claim compares once a payload exists);
- a run without a payload SHALL be aged from its claim instant;
- a run whose slot reports no claim instant at all SHALL yield no age (the
  extension stays absent), never an age of zero.

The claim instant SHALL be written by the claim and by nothing else. It SHALL
NOT be the job row's `updated_at`, which every run-scoped write bumps —
including a previous apply's post-apply summary, which can land after the next
claim and would then understate that owner's silence. A claim predating the
column SHALL keep the pre-existing steal fallback (the row stamp) while
reporting no age, so a rolling deploy never makes a live claim stealable.
`stale_after_seconds` SHALL keep its meaning (`ApplyProgress::STALE_AFTER`), and
the refusal SHALL keep its status, code and extensions — the change is additive
metadata over an unchanged vocabulary.

#### Scenario: A claim that never published still carries its own age

- **WHEN** an apply claims the slot of a `succeeded` job and publishes no
  progress frame, and a second apply is refused inside the server's window
- **THEN** the refusal carries `stale_after_seconds` AND
  `apply_run_age_seconds` measured from the claim instant
- **AND** the client can reach its takeover affordance once that age exceeds
  the window, instead of waiting the window out with no information

#### Scenario: One timestamp decides both the age and the steal

- **WHEN** an unpublished owner's claim instant is older than the server's window
- **THEN** the next claim steals the slot
- **AND** the refusal reported the same instant as `apply_run_age_seconds`, so a
  client verdict of "abandoned" matches the server's own

#### Scenario: Another run's late write cannot extend the window

- **WHEN** a previous apply's post-apply summary (or any other run-scoped write)
  lands after the next claim took the slot
- **THEN** the reported `apply_run_age_seconds` is unchanged — the claim instant
  is owner-scoped
- **AND** the steal fires at the owner's own window, not later

#### Scenario: No stamp degrades to no age

- **WHEN** the apply-run slot reports neither a payload nor a claim instant
- **THEN** `apply_run_age_seconds` is absent rather than zero
- **AND** the client renders its unaged card, claiming neither liveness nor
  abandonment
