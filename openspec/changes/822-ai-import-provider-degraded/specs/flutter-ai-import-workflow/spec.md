<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# flutter-ai-import-workflow

## ADDED Requirements

### Requirement: Aggregated provider-degraded state

The client SHALL derive one degraded-provider state from a job's own attempt
history and render it as a first-class state, instead of leaving the reviewer to
count identical per-attempt rows. The derivation SHALL:

- count the **consecutive newest** attempts whose stable `code` is the
  provider-attributed code (`ai-import.llm-provider-unavailable`) and stop at the
  first attempt with any other code, so an intervening non-provider failure ends
  the window rather than being absorbed into it;
- fire only at **two or more** such consecutive attempts — a single provider
  failure is a transient blip and keeps the per-attempt narrative alone;
- yield the attempt count, the failure window (oldest → newest of that run), the
  job's `next_attempt_at`, and whether the retry budget is spent;
- be keyed on the stable code ONLY. `last_error`/`error_summary` SHALL never
  participate in the derivation, and the legacy generic
  `domain.service-unavailable` SHALL NOT be folded in — it covers the mapping DB,
  the pricing read model and storage, so treating it as provider-attributed would
  name the wrong dependency.

The state SHALL name the dependency (the AI provider), never "a service", and
SHALL render:

- on the job-status screen as a banner carrying the attempt count, the window and
  the next attempt time (the existing live "next retry in …" affordance, never a
  second countdown), and
- on the jobs list row as a compact line derived by the SAME function, so the two
  surfaces cannot disagree about whether the provider is degraded.

A job whose attempts carry no code, an unknown code, or a single provider failure
SHALL render exactly as before.

#### Scenario: Repeated provider failures become one degraded state

- **WHEN** a `failed` job carries three consecutive newest attempts with
  `code = ai-import.llm-provider-unavailable`, ~17 minutes apart, with
  `next_attempt_at` set
- **THEN** the job-status screen renders a "AI provider degraded" banner naming
  the provider, the three attempts, their window and the next attempt time
- **AND** the jobs list row for the same job renders the compact form of the same
  state

#### Scenario: A single provider failure stays a transient per-attempt reason

- **WHEN** a job carries exactly one attempt with the provider code
- **THEN** no degraded banner renders; the retryable card shows the localized
  transient provider narrative for that attempt

#### Scenario: A non-provider failure in between ends the window

- **WHEN** the two newest attempts are a provider failure followed by a
  `domain.service-unavailable` attempt (a storage/database failure)
- **THEN** the degraded state does not render, because the consecutive
  provider-attributed run is shorter than two

### Requirement: Terminal copy after provider failures never promises a retry

A job in a terminal failure state (`dead_letter`, `payload_unavailable`) whose
history is provider-attributed SHALL render terminal copy that

- states that the retry budget is spent, **only where that is derivable** — a
  `dead_letter` whose newest attempt carries the retryable provider code — and
- names what the user can do: delete the failed job from the list (uploading the
  same bytes deduplicates onto it) and start again once the provider answers.

It SHALL NOT render "the next attempt may succeed" (or any other promise the
state cannot keep) on a terminal card, and the per-attempt terminal reasons SHALL
make no **exhaustion** claim: `dead_letter` also happens on a non-retryable
failure and `payload_unavailable` is terminal for a different reason. A
`dependency.auth-failed` history likewise SHALL NOT describe retries that cannot
happen (that failure is permanent).

#### Scenario: Dead-lettered provider outage reads as spent, not retryable

- **WHEN** a job reaches `dead_letter` after provider-attributed attempts
- **THEN** its terminal card names the provider, says the retry budget is spent,
  and offers the recovery narrative instead of the transient retry promise
