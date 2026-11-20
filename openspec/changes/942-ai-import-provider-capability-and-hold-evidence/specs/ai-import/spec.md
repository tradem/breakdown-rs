<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# Delta: ai-import — provider capability, hold evidence, quota taxonomy

## ADDED Requirements

### Requirement: A preflight verdict is capability-accurate

The provider preflight SHALL measure account usability on a curated, verified
endpoint per provider, and SHALL NOT treat a publicly served endpoint as proof
of usability.

#### Scenario: an invalid credential on a public catalog endpoint
- **GIVEN** `eurouter` answers `200` on `GET {base}/models` for a bogus bearer token
- **AND** it answers `401` on `GET {base}/key`
- **WHEN** the probe runs for the pair
- **THEN** the verdict is `NotUsable` and the breaker stays `open`.

#### Scenario: a healthy account on a broken model path
- **GIVEN** `GET {base}/key` answers `200` with a positive remaining budget
- **AND** the model's `POST /chat/completions` still times out
- **WHEN** the probe runs
- **THEN** the breaker moves `open → half_open` and grants exactly one trial
- **AND** it does NOT become `closed`.

#### Scenario: an exhausted account
- **GIVEN** `GET {base}/key` answers `200` with `limit_remaining <= 0`
- **WHEN** the probe runs
- **THEN** the verdict is `NotUsable` and the window is re-armed.

### Requirement: `half_open` admits exactly one trial job

While a `(provider, model)` breaker is `half_open`, only the job holding the
trial token SHALL be claimable, and its attempt SHALL run one request without
in-attempt retries.

#### Scenario: two held jobs, one trial
- **GIVEN** two held jobs of one pair and a granted trial token
- **WHEN** the queue is claimed twice
- **THEN** only the token holder is claimable
- **AND** the other job stays held.

#### Scenario: a failed trial
- **GIVEN** the trial holder's paid call fails retryably
- **THEN** the breaker re-opens immediately with `flap_count + 1`
- **AND** exactly one provider call was made for that trial.

#### Scenario: a paid call answers
- **GIVEN** the breaker is `half_open`
- **WHEN** a paid call succeeds
- **THEN** the breaker becomes `closed` and the pair's held jobs are released.

### Requirement: A hold persists the failure that caused it

Every hold SHALL record a bounded failure narrative and the registered problem
code of the failure that fired it, exactly once per hold *series*, without
charging a retry.

#### Scenario: a chunk-timeout hold
- **GIVEN** a chunk call times out three times and opens the breaker
- **WHEN** the job is held
- **THEN** `retries` is unchanged
- **AND** exactly one attempt row exists whose `error_summary` names the client
  timeout and whose `error_code` is `ai-import.llm-provider-unavailable`.

#### Scenario: a re-hold in the same series
- **GIVEN** a job already held once in a series
- **WHEN** it is held again in the same series
- **THEN** no second attempt row is appended
- **AND** `retries` is still unchanged.

### Requirement: Quota exhaustion is distinct from an outage

A quota-exhausted provider SHALL render `ai-import.provider-quota-exhausted`
(402) with localized copy, SHALL be terminal, and SHALL NOT move the
`(provider, model)` breaker.

#### Scenario: an upstream 402
- **GIVEN** a provider answers `402 Payment Required`
- **WHEN** the failure is classified
- **THEN** the error is `LlmProviderQuotaExhausted` with code
  `ai-import.provider-quota-exhausted`
- **AND** `is_retryable()` is `false` and no `retry_after` is set
- **AND** the job dead-letters without touching the breaker.

#### Scenario: a quota-bearing 429
- **GIVEN** a `429` whose body matches the provider's quota marker
- **THEN** the same terminal code is rendered (not the outage code).

## ADDED Requirements (W4 — provider health + budget read)

### Requirement: Provider health is a per-caller, per-pair read

`GET /v1/ai-import/providers/{provider}/health?model=` SHALL answer the caller's
own account usability, the remaining budget and the `(provider, model)` breaker
rows, and SHALL resolve the credential strictly from the caller's own
configuration.

#### Scenario: the caller's own credential is probed
- **GIVEN** a caller with an active `AiConfig` whose `vault_key_id` names a
  settings binding the caller owns
- **WHEN** the health route is read
- **THEN** `credential_configured` is `true`, `probe_status` reflects the
  zero-token preflight, and the upstream call carried THAT credential.

#### Scenario: a binding owned by somebody else
- **GIVEN** a caller whose config references another user's settings binding
- **WHEN** the health route is read
- **THEN** the answer is `200` with `credential_configured: false`,
  `probe_status: unknown` and `budget: null`
- **AND** no upstream probe ran at all.

#### Scenario: an unconfigured caller
- **GIVEN** a caller with no AI configuration for the provider
- **THEN** the answer is `200` with `credential_configured: false` — never
  `404`/`500` — and `budget` is `null`, never a fabricated `0`.

#### Scenario: the breaker list is `(provider, model)`-shaped
- **GIVEN** a pair with `state = half_open` and a granted trial
- **WHEN** the route answers
- **THEN** the row carries `trial_granted: true` and **no** job id
- **AND** every non-`closed` row of the provider is included even when the
  caller has no configuration for that pair.

#### Scenario: the response never carries tenant material
- **THEN** no `vault_key_id`, bearer token, raw upstream body or `trial_job_id`
  appears in the document
- **AND** the response is served with `Cache-Control: no-store`.

### Requirement: An unmeasured account state is `unknown`, never a denial

The health read SHALL distinguish a rejected credential from an unmeasured one.

#### Scenario: a provider without a zero-token endpoint
- **GIVEN** a provider whose curated capability is `NoPreflight`
- **THEN** `probe_status` is `unknown` and `budget` is `null`
- **AND** the route still answers `200`.

#### Scenario: a transport failure or timeout inside the probe
- **THEN** `probe_status` is `unknown` (never `not_usable`), while the breaker
  gate still maps the same observation to `NotUsable` so no money is spent on an
  unknown.

### Requirement: The budget cache is identity-scoped

The account probe SHALL cache its answer for at most 60 seconds keyed by
`(user_id, provider, vault_key_id)`.

#### Scenario: two callers of the same provider
- **GIVEN** two callers with different bindings on the same provider
- **THEN** neither receives the other's cached budget figure, and rotating a key
  is a cache miss rather than a stale number.
