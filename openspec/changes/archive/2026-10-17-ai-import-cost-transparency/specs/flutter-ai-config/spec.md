<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: gemini-4-argon (google) -->

## MODIFIED Requirements

### Requirement: Vault-Backed AI Configuration Screens
The configuration screen SHALL manage the caller's AI import
configuration over the realized contract: provider discovery and
model pickers, assistant/image model fields, per-document-kind
prompts, preferred cost display mode (`cost_display_preference`:
`token` vs `energy`), credential submission, create/edit/revoke. The API-key
secret SHALL be submitted via the credentials route and ONLY the
returned opaque `vault_key_id` SHALL be referenced by the config; the
secret SHALL NOT be stored on the device, logged, or echoed back
after submission (masked input field).

#### Scenario: First-run configuration
- **WHEN** the config list (`GET /v1/ai-import/config`, backend issue
  #337) is empty, or the remembered id 404s.
- **THEN** the screen renders the "not configured yet" state with the
  provider picker, model picker with price signals, cost-display
  preference selector (defaulting to `token`), and the masked key field;
  create persists the returned id in `flutter_secure_storage` as a
  fast-path for the next launch (list-first discovery remains authoritative).

#### Scenario: Editing the configuration and cost display preference
- **WHEN** the user changes the assistant model, prompts, or
  `cost_display_preference` (`token` ↔ `energy`).
- **THEN** the PATCH carries the updated fields and the `version` echoed
  from the fetched `AiConfigView`; a 409 renders "changed elsewhere — refresh"
  copy keyed on `code` with no automatic version bump re-dispatch.

#### Scenario: Credential-role denial
- **WHEN** the backend answers 403 on any config/credential call.
- **THEN** a localized "administrator role required" narrative
  renders. A client-side membership pre-gate is deliberately absent
  here because the contract exposes no capability surface for
  credential roles (documented exception; the call itself is
  denied server-side).

#### Scenario: Secret never persists
- **WHEN** the credential submission completes (or fails).
- **THEN** no store, cache or log entry on the device contains the
  secret (asserted in tests by store-write interception).

### Requirement: Provider and Model Discovery With Honest Degradation
Provider/model pickers SHALL read the discovery routes and render
degraded, honest copy on unavailability (unknown provider 422,
provider list empty, AI import disabled 404) — never empty pickers
masquerading as "no providers exist". Next to each discovered model in
the picker, the UI SHALL display its pricing signal derived from
`ModelInfo.pricing`:
- when `pricing` is present, the formatted input/output rate per 1M
  tokens in the model's `currency` (`USD` or `EUR`), plus the energy
  rate (`energy_nano_per_kwh`) when offered by the provider (e.g.
  Neuralwatt);
- when `pricing` is `null` (e.g. local Ollama models or unpriced models),
  explicit localized `"Unbekannt"` / `"Unknown"` copy — NEVER `$0.00` or `0`.

#### Scenario: Unknown provider key
- **WHEN** a provider's model route returns 422.
- **THEN** the model step shows "provider unavailable" copy and the
  flow cannot proceed to that provider's config.

#### Scenario: Model catalog follows the discovery routes and shows pricing signals
- **WHEN** the backend returns `ModelInfo` items carrying `pricing`
  (including token rates and optional `energy_nano_per_kwh`).
- **THEN** the picker renders the formatted input/output token rates (and
  energy rate where present) next to each model without hardcoding model IDs
  or prices client-side.

#### Scenario: Unpriced model in picker renders Unknown and never zero
- **WHEN** a `ModelInfo` item has `pricing == null` (such as an Ollama model).
- **THEN** the picker renders localized `"Unbekannt"` / `"Unknown"` price copy
  and never `0` or `$0.00`.
