<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# ai-import

## ADDED Requirements

### Requirement: The blocked-apply age also covers a claim that published no frame

The `409 ai-import.apply-in-flight` refusal SHALL report
`apply_run_age_seconds` for **every** run that owns the apply-run slot,
including a run that claimed the slot and has published no progress frame
yet. The age SHALL be derived from the same timestamp the single-flight
claim's steal predicate judges an unpublished owner by — the job row's
`updated_at` — so the reported age and the steal decision can never
disagree:

- a run that published a frame SHALL be aged from that payload's
  `updated_at` (the column the claim compares once a payload exists);
- a run without a payload SHALL be aged from the row's `updated_at`;
- a run whose slot reports no timestamp at all SHALL yield no age (the
  extension stays absent), never an age of zero.

The reported timestamp SHALL be documented as **the owner's last write on the
row**, not "the last progress frame": every run-scoped write (progress,
telemetry, applied-episode summary) bumps it. `stale_after_seconds` SHALL keep
its meaning (`ApplyProgress::STALE_AFTER`), and the refusal SHALL keep its
status, code and extensions — the change is additive metadata over an
unchanged vocabulary.

#### Scenario: A claim that never published still carries its own age

- **WHEN** an apply claims the slot of a `succeeded` job and publishes no
  progress frame, and a second apply is refused inside the server's window
- **THEN** the refusal carries `stale_after_seconds` AND
  `apply_run_age_seconds` measured from the claim's own row stamp
- **AND** the client can reach its takeover affordance once that age exceeds
  the window, instead of waiting the window out with no information

#### Scenario: One timestamp decides both the age and the steal

- **WHEN** an unpublished owner's row stamp is older than the server's window
- **THEN** the next claim steals the slot
- **AND** the refusal reported the same stamp as `apply_run_age_seconds`, so a
  client verdict of "abandoned" matches the server's own

#### Scenario: No stamp degrades to no age

- **WHEN** the apply-run slot reports neither a payload nor a row stamp
- **THEN** `apply_run_age_seconds` is absent rather than zero
- **AND** the client renders its unaged card, claiming neither liveness nor
  abandonment
