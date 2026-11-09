<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# ai-import

## ADDED Requirements

### Requirement: A transient LLM-provider failure is attributed to the provider

A transient failure **of the LLM provider** SHALL be classified with the
registered problem code `ai-import.llm-provider-unavailable` (HTTP 503,
retryable) instead of the generic `domain.service-unavailable`, so the recorded
attempt names the failing dependency from a stable signal rather than from its
free-form summary. The code SHALL reuse the existing retryable service-unavailable
error shape, so retryability, backoff, the retry budget and the attempt-persistence
path are unchanged: only the attempt's `code` (and therefore the localized
client narrative) moves.

The provider attribution covers exactly the chat client's transient
classifications:

- an HTTP 429 or 5xx answer from the provider (with the bounded provider-detail
  suffix preserved), and
- a transport timeout or connect failure against the provider.

Every **other** import pipeline dependency SHALL keep
`domain.service-unavailable`: the mapping DB, the pricing read model, payload
storage and the model catalog are not the provider, and no attempt row can
honestly attribute a failure to it. A provider response that is a deterministic
policy rejection (permanent validation, redirect violation) and a rejected
credential (`dependency.auth-failed`, #637) keep their existing codes — this
change adds attribution, it does not reclassify retryability.

The code SHALL NOT be derived from `error_summary`/`last_error` anywhere: the
summary is log text and stays secondary detail.

#### Scenario: Consecutive provider 503s are recorded as provider failures

- **WHEN** a script import's LLM call answers HTTP 503 three times on
  consecutive attempts
- **THEN** each attempt row carries `code = ai-import.llm-provider-unavailable`
- **AND** each attempt is `retryable = true`, the job keeps backing off with
  `next_attempt_at`, and its retry budget is consumed exactly as before

#### Scenario: A storage-database failure is not attributed to the provider

- **WHEN** the mapping DB read fails while recording extracted rows
- **THEN** the attempt carries `code = domain.service-unavailable`
- **AND** it is not rendered as a provider outage (the generic transient
  narrative is used)

### Requirement: The jobs list read carries attempt history

`GET /v1/ai-import/jobs` SHALL populate every returned job's `attempts` with its
newest attempts (at least the two most recent, bounded by the existing history
limit) in one batch read for the page — never one query per job. The list
surface exists before the user opens any job, so a client that derives a
degraded-provider state from attempt history SHALL be able to derive the **same**
state from a list row as from the single-job read; publishing only `last_error`
(or nothing) would force either free-form parsing or a second per-row read, both
rejected.

The field is unchanged on the wire (`attempts`, already `serde(default)` and
already documented as additive), so a client that ignores it is unaffected, and
a pre-#822 row still reads.

#### Scenario: A list row names the provider failures it has

- **WHEN** a job has three recorded attempts whose codes are all
  `ai-import.llm-provider-unavailable`
- **THEN** the job appears in `GET /v1/ai-import/jobs` with those attempts
  (newest first) populated, and the page is read in a bounded number of queries
  regardless of its row count
