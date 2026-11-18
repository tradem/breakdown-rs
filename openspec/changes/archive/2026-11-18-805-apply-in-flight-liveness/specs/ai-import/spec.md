<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# ai-import

## ADDED Requirements

### Requirement: A blocked apply run names its own liveness

The registered `409 ai-import.apply-in-flight` refusal SHALL carry, as its
declared S1 extensions, the two facts that let a client tell a live apply run
from an abandoned one instead of waiting blindly:

- `stale_after_seconds` — the server's own staleness window
  (`ApplyProgress::STALE_AFTER`). It SHALL be emitted on every such refusal, so
  no client has to mirror the constant.
- `apply_run_age_seconds` — how long the owning run had been silent when the
  refusal was emitted, measured against the server's own clock from the owner's
  last published payload. It SHALL be omitted (never emitted as zero) when that
  run has published nothing yet, and a failure to read the run slot SHALL omit
  the age rather than change the refusal into a different error.

The age SHALL be a duration, not an absolute timestamp, so a client whose clock
is wrong cannot misclassify a live run as abandoned. A payload older than the
window SHALL mean the server itself considers it abandoned — the next atomic
claim would steal the slot — while a payload inside the window (including one
exactly AT it, because the claim's comparison is strict) means the run is live.

The refusal SHALL NOT change: it remains a `409` with no new problem code, and
the single-flight claim stays the authority. Emitting the extensions is additive
metadata over an unchanged status and code.

#### Scenario: A live run blocks the refusal and names its age

- **WHEN** a second apply of a `succeeded` job is refused while the owning run
  published its payload four minutes ago
- **THEN** the `409 ai-import.apply-in-flight` carries
  `stale_after_seconds = 600` and `apply_run_age_seconds` measured from that
  payload
- **AND** the client can conclude that the run is live, because the age is
  inside the server's window

#### Scenario: An owner that published nothing carries no age

- **WHEN** a second apply is refused while the owning run has claimed the slot
  but written no progress frame
- **THEN** the refusal carries `stale_after_seconds` and NO
  `apply_run_age_seconds`
- **AND** no age of zero is reported, because a run that said nothing has no
  liveness to report

#### Scenario: The window is the server's single definition

- **WHEN** `ApplyProgress::STALE_AFTER` changes
- **THEN** every refusal's `stale_after_seconds` follows it with no second
  constant to update, and no client-side mirror exists to drift
