<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# flutter-ai-import-workflow

## ADDED Requirements

### Requirement: A blocked apply is a decision, not an error

When the apply dispatch is refused with `409 ai-import.apply-in-flight`, the
client SHALL classify the refusal from the server's own S1 extensions
(`apply_run_age_seconds`, `stale_after_seconds`) and SHALL render a decision
card inside the apply section, never the generic apply-error narrative:

- While `age <= stale_after`, the card SHALL state that an apply is running, name
  the owning run's last publication as a localized relative age, and show the
  whole minutes remaining until a takeover becomes possible (rounded up, never
  zero). The submit button SHALL be disabled in that state — a second dispatch
  could only be refused again — and NO takeover affordance SHALL be offered.
  The boundary is STRICT, mirroring the claim's own predicate: at exactly the
  window the server still refuses, so the run is still live.
- Once `age > stale_after` (including while the card stays open, derived from
  the server-measured age plus local elapsed time; no polling request), the card
  SHALL state that the run counts as abandoned and SHALL offer one explicit
  takeover action, which re-dispatches the same idempotent apply without a
  second confirmation dialog.
- When the refusal carries NO `apply_run_age_seconds` (an owner that published
  nothing), the card SHALL claim neither liveness nor abandonment: it SHALL say
  that no progress was reported, SHALL NOT fabricate an age or a countdown, and
  SHALL keep the apply action available while offering the same explicit action
  — the server's claim stays authoritative either way.

The classification SHALL NOT be mirrored client-side: a refusal that carries no
`stale_after_seconds` (a server predating the extensions) keeps the previous
bounded-wait behaviour and renders no takeover.

The reconciliation loop SHALL NOT steal an abandoned claim on its own: a refusal
older than the window SHALL end the loop after that single dispatch. A refusal
for a live run MAY consume the bounded attempt budget (the client's own earlier
POST may still be running), but the loop SHALL re-check the locally aged refusal
after each backoff and BEFORE the next dispatch: once the wait would carry the
age past the window, the loop SHALL stop and report the blocked run instead of
dispatching into a claim the server would hand over. If the budget ends on a
live refusal the outcome SHALL be reported as a blocked live run, never as an
unknown outcome; if it ends on an ambiguous timeout the earlier refusal SHALL be
discarded, so the outcome is reported as unknown.

#### Scenario: An abandoned run offers the takeover

- **WHEN** the refusal reports `apply_run_age_seconds = 700` and
  `stale_after_seconds = 600`
- **THEN** the apply card states that the run has stopped reporting progress and
  counts as abandoned, and names the 11-minute silence
- **AND** it offers the takeover action, and no apply-error line is rendered
- **AND** exactly one dispatch was made before the user's tap

#### Scenario: A live run still blocks

- **WHEN** the refusal reports an age inside the server's window
- **THEN** the card names the run and the remaining minutes until a takeover is
  possible
- **AND** the submit button is disabled and no takeover action is rendered
- **AND** an exhausted attempt budget leaves the card in that live state rather
  than reporting an unknown outcome

#### Scenario: The takeover re-runs the idempotent apply

- **WHEN** the user taps the takeover action
- **THEN** the client dispatches the same apply request again, with no second
  confirmation dialog
- **AND** a success clears the blocked-run card and follows the post-apply
  routing, because already-applied rows are skipped server-side

#### Scenario: A server without the extensions keeps the previous behaviour

- **WHEN** the refusal carries no `stale_after_seconds`
- **THEN** the client keeps its bounded wait and renders no takeover, because it
  never guesses a window the server did not state
