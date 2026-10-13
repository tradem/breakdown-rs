<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# health-checks Delta (637-vault-auth-health-attempt-history)

## ADDED Requirements

### Requirement: Public dependency health report
The API SHALL expose a public, unauthenticated readiness surface
`GET /v1/health` returning a structured report (modelled on .NET Health
Checks) with an aggregate `status`, a `total_duration_ms`, and an `entries`
map keyed by dependency name (`postgres`, `sierradb`, `vault`, `garage`), each
carrying its own `status`, `duration_ms`, optional static `description` and
`tags`. The report SHALL NOT expose credentials, tokens or internal addresses.

#### Scenario: A probe reads the report without a token
- **WHEN** `GET /v1/health` is called with no bearer token
- **THEN** the request is served (the route is classified `Public` and exempt
  from the auth/authz middleware) and returns the report

#### Scenario: Aggregate status selects the HTTP status
- **WHEN** every check is `Healthy` or any is `Degraded`
- **THEN** the response is `200`
- **WHEN** any check is `Unhealthy`
- **THEN** the response is `503`

#### Scenario: An invalid Vault token is visible before jobs fail
- **WHEN** Vault is reachable but the app token is invalid or expired
- **THEN** the `vault` entry is `Unhealthy` with the static description
  "Vault app token is invalid or expired"

### Requirement: In-process Vault app-token renewal
The API SHALL renew its periodic Vault app token in-process well before its
TTL lapses, so a long-running process does not lose Vault access without an
operator re-running the one-shot bootstrap. The cadence SHALL be configurable
via `VAULT_TOKEN_RENEW_INTERVAL_SECS` (default 12 h, clamped to `60`–`82800`
seconds, i.e. up to 23 h).

#### Scenario: A long-running API keeps Vault access
- **WHEN** the process has been up for longer than the token period
- **THEN** the background renewal has refreshed the token and Vault KV reads
  keep succeeding
