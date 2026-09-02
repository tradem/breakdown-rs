<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# flutter-ai-config Specification (delta)

## ADDED Requirements

### Requirement: Vault-Backed AI Configuration Screens
The configuration screen SHALL manage the caller's AI import
configuration over the realized contract: provider discovery and
model pickers, assistant/image model fields, per-document-kind
prompts, credential submission, create/edit/revoke. The API-key
secret SHALL be submitted via the credentials route and ONLY the
returned opaque `vault_key_id` SHALL be referenced by the config; the
secret SHALL NOT be stored on the device, logged, or echoed back
after submission (masked input field).

#### Scenario: First-run configuration
- **WHEN** no config id is remembered (or the remembered id 404s).
- **THEN** the screen renders the "not configured yet" state with the
  provider picker and the masked key field; create persists the
  returned id in `flutter_secure_storage`.

#### Scenario: Editing the configuration
- **WHEN** the user changes the assistant model or prompts.
- **THEN** the PATCH carries the `version` echoed from the fetched
  `AiConfigView`; a 409 renders "changed elsewhere — refresh" copy
  keyed on `code` with no automatic version bump re-dispatch.

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
masquerading as "no providers exist".

#### Scenario: Unknown provider key
- **WHEN** a provider's model route returns 422.
- **THEN** the model step shows "provider unavailable" copy and the
  flow cannot proceed to that provider's config.
