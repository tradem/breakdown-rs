<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# Delta: flutter-ai-import-provider-health (new)

## ADDED Requirements

### Requirement: The AI-configuration screen reports the provider's own state

The screen SHALL render the caller's provider health, remaining budget and paused
`(provider, model)` pairs above the configuration form, one card per configured
provider (extraction, plus the Decision provider when it differs).

#### Scenario: a usable account with a remaining budget
- **WHEN** the health read answers `probe_status: usable` with a figure
- **THEN** the card states the account is usable and shows the figure.

#### Scenario: three-valued budget
- **GIVEN** `budget: null`
- **THEN** the card says the budget is unknown (never `0`)
- **AND** with `budget.remaining: null` it says no limit is configured.

#### Scenario: an exhausted quota
- **GIVEN** `probe_status: not_usable`
- **THEN** the card names a rejected key or an exhausted balance
- **AND** the screen does NOT claim the backend is unreachable.

#### Scenario: a provider problem is not a backend problem
- **THEN** an unreachable, unpaid or paused provider never renders as
  "Backend noch nicht erreichbar" — that claim belongs to
  `aiConfigReachabilityProvider` (`GET /v1/health`) alone (issue #809).

### Requirement: A resolved capability denial suppresses the dispatch

The provider-health read SHALL consult the global credential capability first.

#### Scenario: a resolved denial
- **GIVEN** `myCapabilitiesProvider` resolves to `canManageAiConfig: false`
- **THEN** the read is NOT dispatched (no request leaves the device)
- **AND** the card renders the localized "Keine Berechtigung" narrative with no
  retry affordance.

#### Scenario: an unknown capability answer
- **GIVEN** a pending or failed capability read
- **THEN** the request proceeds and the server stays authoritative — an unknown
  answer is never a denial (issue #816).

### Requirement: Hold copy distinguishes the observed failure from a guess

The held-job copy SHALL state that the provider did not answer in time, SHALL NOT
assert that it was unreachable, SHALL state that no retry was consumed, and SHALL
state that whether the aborted call was still billed is not observable.

#### Scenario: a chunk-timeout hold
- **THEN** the title reads "{provider} hat nicht rechtzeitig geantwortet"
- **AND** the body points at the attempt history for the exact cause and names the
  cost question as open.

### Requirement: German and English copy stay at parity

Every new key SHALL exist in both `lib/l10n/app_de.arb` (template) and
`lib/l10n/app_en.arb`, with ICU placeholders, and the configured-state goldens
SHALL be regenerated.
