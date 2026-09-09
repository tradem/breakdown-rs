# flutter-ai-config Specification

## Purpose
Defines the vault-backed AI configuration surface of the Flutter
client: the screen that manages the caller's per-user AI import
configuration (provider, assistant and image models, script/schedule
prompts) against the backend vault-backed settings routes, with
discovery-driven pickers (model ids are never hardcoded client-side),
a masked key field, secret-in-payload-only handling (the LLM key is
submitted once via the credential handoff and only the opaque
vault key id is referenced afterwards — it never persists on the
device), version-echo edits without automatic re-dispatch on 409,
credential-role denial surfaced as a localized narrative (the
documented D4 session-only gate exception), and an honest unresolved
state after an ambiguous revoke.

## Requirements
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
- **WHEN** the config list (`GET /v1/ai-import/config`, backend issue
  #337) is empty, or the remembered id 404s.
- **THEN** the screen renders the "not configured yet" state with the
  provider picker and the masked key field; create persists the
  returned id in `flutter_secure_storage` as a fast-path for the next
  launch (list-first discovery remains authoritative).

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

#### Scenario: Model catalog follows the discovery routes
- **WHEN** the backend refreshes the curated per-provider model sets
  (backend PR #360).
- **THEN** the pickers render the route-supplied models with honest
  degradation — no hardcoded model ids exist client-side.
