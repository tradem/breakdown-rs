# Error Codes (problem+json registry)

<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: kimi-k3 (neuralwatt) -->

Stable machine codes for every failure the API can return. Each code is the
client contract: branch on `code`, never on `detail` text. The registry lives
in `crates/core/src/error_registry.rs` (the single source of truth); this page
is generated from the golden snapshots (`crates/api/tests/golden/problems/`),
so it cannot drift from what the server actually emits.

Every code is a section anchor (`<a id="{code}">`). The `type` URI
`{docs-base}/problems/{code}` dereferences to this page's anchor `{code}` via
the docs host's routing. See [README.md](README.md) for the envelope, status
semantics, the S0/S1/S2 privacy policy, and the deprecation rule.

## http

<a id="http.bad-json-body"></a>

### http.bad-json-body

- **Status**: `400`
- **Title**: Malformed JSON body
- **Extensions**: none
- **`type` anchor**: `https://docs.breakdown.example/problems/http.bad-json-body`

<a id="http.bad-path-param"></a>

### http.bad-path-param

- **Status**: `400`
- **Title**: Invalid path parameter
- **Extensions**: none
- **`type` anchor**: `https://docs.breakdown.example/problems/http.bad-path-param`

<a id="http.bad-query-param"></a>

### http.bad-query-param

- **Status**: `400`
- **Title**: Invalid query parameter
- **Extensions**: none
- **`type` anchor**: `https://docs.breakdown.example/problems/http.bad-query-param`

<a id="http.bad-request"></a>

### http.bad-request

- **Status**: `400`
- **Title**: Bad request
- **Extensions**: none
- **`type` anchor**: `https://docs.breakdown.example/problems/http.bad-request`

<a id="http.internal-error"></a>

### http.internal-error

- **Status**: `500`
- **Title**: Internal server error
- **Extensions**: none
- **`type` anchor**: `https://docs.breakdown.example/problems/http.internal-error`

<a id="http.payload-too-large"></a>

### http.payload-too-large

- **Status**: `413`
- **Title**: Payload too large
- **Extensions**: none
- **`type` anchor**: `https://docs.breakdown.example/problems/http.payload-too-large`

<a id="http.request-timeout"></a>

### http.request-timeout

- **Status**: `504`
- **Title**: Gateway timeout
- **Extensions**: none
- **`type` anchor**: `https://docs.breakdown.example/problems/http.request-timeout`

<a id="http.route-not-found"></a>

### http.route-not-found

- **Status**: `404`
- **Title**: Route not found
- **Extensions**: none
- **`type` anchor**: `https://docs.breakdown.example/problems/http.route-not-found`

<a id="http.unsupported-media-type"></a>

### http.unsupported-media-type

- **Status**: `415`
- **Title**: Unsupported media type
- **Extensions**: none
- **`type` anchor**: `https://docs.breakdown.example/problems/http.unsupported-media-type`

## auth

<a id="auth.idp-unavailable"></a>

### auth.idp-unavailable

- **Status**: `503`
- **Title**: Identity provider unavailable
- **Extensions**: none
- **`type` anchor**: `https://docs.breakdown.example/problems/auth.idp-unavailable`

<a id="auth.invalid-active-block"></a>

### auth.invalid-active-block

- **Status**: `400`
- **Title**: Invalid active block
- **Extensions**: none
- **`type` anchor**: `https://docs.breakdown.example/problems/auth.invalid-active-block`

<a id="auth.missing-active-block"></a>

### auth.missing-active-block

- **Status**: `400`
- **Title**: Missing active block
- **Extensions**: none
- **`type` anchor**: `https://docs.breakdown.example/problems/auth.missing-active-block`

<a id="auth.unauthenticated"></a>

### auth.unauthenticated

- **Status**: `401`
- **Title**: Authentication required
- **Extensions**: none
- **`type` anchor**: `https://docs.breakdown.example/problems/auth.unauthenticated`

## domain

<a id="domain.conflict"></a>

### domain.conflict

- **Status**: `409`
- **Title**: Conflict
- **Extensions**: none
- **`type` anchor**: `https://docs.breakdown.example/problems/domain.conflict`

<a id="domain.forbidden"></a>

### domain.forbidden

- **Status**: `403`
- **Title**: Forbidden
- **Extensions**: none
- **`type` anchor**: `https://docs.breakdown.example/problems/domain.forbidden`

<a id="domain.not-found"></a>

### domain.not-found

- **Status**: `404`
- **Title**: Not found
- **Extensions**: none
- **`type` anchor**: `https://docs.breakdown.example/problems/domain.not-found`

<a id="domain.service-unavailable"></a>

### domain.service-unavailable

- **Status**: `503`
- **Title**: Service unavailable
- **Extensions**: none
- **`type` anchor**: `https://docs.breakdown.example/problems/domain.service-unavailable`

<a id="domain.validation"></a>

### domain.validation

- **Status**: `422`
- **Title**: Validation failed
- **Extensions**: none
- **`type` anchor**: `https://docs.breakdown.example/problems/domain.validation`

## concurrency

<a id="concurrency.version-mismatch"></a>

### concurrency.version-mismatch

- **Status**: `409`
- **Title**: Version conflict
- **Extensions**: `current_version` (S0), `expected_version` (S0)
- **`type` anchor**: `https://docs.breakdown.example/problems/concurrency.version-mismatch`

## season

<a id="season.not-found"></a>

### season.not-found

- **Status**: `404`
- **Title**: Season not found
- **Extensions**: `id` (S0)
- **`type` anchor**: `https://docs.breakdown.example/problems/season.not-found`

<a id="season.validation"></a>

### season.validation

- **Status**: `422`
- **Title**: Season validation failed
- **Extensions**: none
- **`type` anchor**: `https://docs.breakdown.example/problems/season.validation`

## block

<a id="block.not-found"></a>

### block.not-found

- **Status**: `404`
- **Title**: Block not found
- **Extensions**: `id` (S0)
- **`type` anchor**: `https://docs.breakdown.example/problems/block.not-found`

<a id="block.validation"></a>

### block.validation

- **Status**: `422`
- **Title**: Block validation failed
- **Extensions**: none
- **`type` anchor**: `https://docs.breakdown.example/problems/block.validation`

## episode

<a id="episode.not-found"></a>

### episode.not-found

- **Status**: `404`
- **Title**: Episode not found
- **Extensions**: `id` (S0)
- **`type` anchor**: `https://docs.breakdown.example/problems/episode.not-found`

<a id="episode.validation"></a>

### episode.validation

- **Status**: `422`
- **Title**: Episode validation failed
- **Extensions**: none
- **`type` anchor**: `https://docs.breakdown.example/problems/episode.validation`

## scene

<a id="scene.already-scheduled"></a>

### scene.already-scheduled

- **Status**: `409`
- **Title**: Scene schedule conflict
- **Extensions**: `offending_shooting_day_id` (S1)
- **`type` anchor**: `https://docs.breakdown.example/problems/scene.already-scheduled`

<a id="scene.character-already-assigned"></a>

### scene.character-already-assigned

- **Status**: `409`
- **Title**: Character already assigned to this scene
- **Extensions**: none
- **`type` anchor**: `https://docs.breakdown.example/problems/scene.character-already-assigned`

<a id="scene.character-not-found"></a>

### scene.character-not-found

- **Status**: `404`
- **Title**: Scene character not found
- **Extensions**: `id` (S0)
- **`type` anchor**: `https://docs.breakdown.example/problems/scene.character-not-found`

<a id="scene.not-found"></a>

### scene.not-found

- **Status**: `404`
- **Title**: Scene not found
- **Extensions**: `id` (S0)
- **`type` anchor**: `https://docs.breakdown.example/problems/scene.not-found`

<a id="scene.not-scheduled"></a>

### scene.not-scheduled

- **Status**: `409`
- **Title**: Scene not scheduled on this day
- **Extensions**: `shooting_day_id` (S1)
- **`type` anchor**: `https://docs.breakdown.example/problems/scene.not-scheduled`

<a id="scene.validation"></a>

### scene.validation

- **Status**: `422`
- **Title**: Scene validation failed
- **Extensions**: none
- **`type` anchor**: `https://docs.breakdown.example/problems/scene.validation`

## character

<a id="character.not-found"></a>

### character.not-found

- **Status**: `404`
- **Title**: Character not found
- **Extensions**: `id` (S0)
- **`type` anchor**: `https://docs.breakdown.example/problems/character.not-found`

<a id="character.validation"></a>

### character.validation

- **Status**: `422`
- **Title**: Character validation failed
- **Extensions**: none
- **`type` anchor**: `https://docs.breakdown.example/problems/character.validation`

## costume

<a id="costume.already-assigned"></a>

### costume.already-assigned

- **Status**: `409`
- **Title**: Costume already assigned
- **Extensions**: `assigned_character_id` (S1)
- **`type` anchor**: `https://docs.breakdown.example/problems/costume.already-assigned`

<a id="costume.not-found"></a>

### costume.not-found

- **Status**: `404`
- **Title**: Costume not found
- **Extensions**: `id` (S0)
- **`type` anchor**: `https://docs.breakdown.example/problems/costume.not-found`

<a id="costume.validation"></a>

### costume.validation

- **Status**: `422`
- **Title**: Costume validation failed
- **Extensions**: none
- **`type` anchor**: `https://docs.breakdown.example/problems/costume.validation`

## costume-category

<a id="costume-category.archived"></a>

### costume-category.archived

- **Status**: `409`
- **Title**: Costume category is archived
- **Extensions**: `id` (S0)
- **`type` anchor**: `https://docs.breakdown.example/problems/costume-category.archived`

<a id="costume-category.not-found"></a>

### costume-category.not-found

- **Status**: `404`
- **Title**: Costume category not found
- **Extensions**: `id` (S0)
- **`type` anchor**: `https://docs.breakdown.example/problems/costume-category.not-found`

<a id="costume-category.validation"></a>

### costume-category.validation

- **Status**: `422`
- **Title**: Costume category validation failed
- **Extensions**: none
- **`type` anchor**: `https://docs.breakdown.example/problems/costume-category.validation`

## shooting-day

<a id="shooting-day.archived"></a>

### shooting-day.archived

- **Status**: `409`
- **Title**: Shooting day is archived
- **Extensions**: `id` (S0)
- **`type` anchor**: `https://docs.breakdown.example/problems/shooting-day.archived`

<a id="shooting-day.duplicate-order-key"></a>

### shooting-day.duplicate-order-key

- **Status**: `409`
- **Title**: Duplicate order key
- **Extensions**: none
- **`type` anchor**: `https://docs.breakdown.example/problems/shooting-day.duplicate-order-key`

<a id="shooting-day.not-found"></a>

### shooting-day.not-found

- **Status**: `404`
- **Title**: Shooting day not found
- **Extensions**: `id` (S0)
- **`type` anchor**: `https://docs.breakdown.example/problems/shooting-day.not-found`

<a id="shooting-day.validation"></a>

### shooting-day.validation

- **Status**: `422`
- **Title**: Shooting day validation failed
- **Extensions**: none
- **`type` anchor**: `https://docs.breakdown.example/problems/shooting-day.validation`

## scene-shoot

<a id="scene-shoot.already-linked"></a>

### scene-shoot.already-linked

- **Status**: `409`
- **Title**: Continuity photo already linked
- **Extensions**: `photo_id` (S1)
- **`type` anchor**: `https://docs.breakdown.example/problems/scene-shoot.already-linked`

<a id="scene-shoot.already-started"></a>

### scene-shoot.already-started

- **Status**: `409`
- **Title**: Scene shoot already started
- **Extensions**: none
- **`type` anchor**: `https://docs.breakdown.example/problems/scene-shoot.already-started`

<a id="scene-shoot.not-found"></a>

### scene-shoot.not-found

- **Status**: `404`
- **Title**: Scene shoot not found
- **Extensions**: `id` (S0)
- **`type` anchor**: `https://docs.breakdown.example/problems/scene-shoot.not-found`

<a id="scene-shoot.note-not-found"></a>

### scene-shoot.note-not-found

- **Status**: `404`
- **Title**: Scene shoot note not found
- **Extensions**: `note_id` (S0)
- **`type` anchor**: `https://docs.breakdown.example/problems/scene-shoot.note-not-found`

<a id="scene-shoot.pair-already-exists"></a>

### scene-shoot.pair-already-exists

- **Status**: `409`
- **Title**: Scene shoot pair already exists
- **Extensions**: none
- **`type` anchor**: `https://docs.breakdown.example/problems/scene-shoot.pair-already-exists`

<a id="scene-shoot.planned-order-frozen"></a>

### scene-shoot.planned-order-frozen

- **Status**: `409`
- **Title**: Planned order is frozen
- **Extensions**: none
- **`type` anchor**: `https://docs.breakdown.example/problems/scene-shoot.planned-order-frozen`

<a id="scene-shoot.terminal-state"></a>

### scene-shoot.terminal-state

- **Status**: `409`
- **Title**: Scene shoot in terminal state
- **Extensions**: none
- **`type` anchor**: `https://docs.breakdown.example/problems/scene-shoot.terminal-state`

<a id="scene-shoot.validation"></a>

### scene-shoot.validation

- **Status**: `422`
- **Title**: Scene shoot validation failed
- **Extensions**: none
- **`type` anchor**: `https://docs.breakdown.example/problems/scene-shoot.validation`

## photo

<a id="photo.already-deleted"></a>

### photo.already-deleted

- **Status**: `409`
- **Title**: Photo already deleted
- **Extensions**: none
- **`type` anchor**: `https://docs.breakdown.example/problems/photo.already-deleted`

<a id="photo.not-found"></a>

### photo.not-found

- **Status**: `404`
- **Title**: Photo not found
- **Extensions**: `id` (S0)
- **`type` anchor**: `https://docs.breakdown.example/problems/photo.not-found`

<a id="photo.validation"></a>

### photo.validation

- **Status**: `422`
- **Title**: Photo validation failed
- **Extensions**: none
- **`type` anchor**: `https://docs.breakdown.example/problems/photo.validation`

## membership

<a id="membership.already-invited"></a>

### membership.already-invited

- **Status**: `409`
- **Title**: Already invited
- **Extensions**: none
- **`type` anchor**: `https://docs.breakdown.example/problems/membership.already-invited`

<a id="membership.bootstrap-not-allowed"></a>

### membership.bootstrap-not-allowed

- **Status**: `409`
- **Title**: Bootstrap not allowed
- **Extensions**: none
- **`type` anchor**: `https://docs.breakdown.example/problems/membership.bootstrap-not-allowed`

<a id="membership.missing-actor"></a>

### membership.missing-actor

- **Status**: `422`
- **Title**: Authenticated actor required
- **Extensions**: none
- **`type` anchor**: `https://docs.breakdown.example/problems/membership.missing-actor`

<a id="membership.no-pending-invitation"></a>

### membership.no-pending-invitation

- **Status**: `409`
- **Title**: No pending invitation
- **Extensions**: none
- **`type` anchor**: `https://docs.breakdown.example/problems/membership.no-pending-invitation`

<a id="membership.not-active-member"></a>

### membership.not-active-member

- **Status**: `409`
- **Title**: Not an active member
- **Extensions**: none
- **`type` anchor**: `https://docs.breakdown.example/problems/membership.not-active-member`

<a id="membership.not-found"></a>

### membership.not-found

- **Status**: `404`
- **Title**: Membership not found
- **Extensions**: none
- **`type` anchor**: `https://docs.breakdown.example/problems/membership.not-found`

<a id="membership.validation"></a>

### membership.validation

- **Status**: `422`
- **Title**: Membership validation failed
- **Extensions**: none
- **`type` anchor**: `https://docs.breakdown.example/problems/membership.validation`

## settings

<a id="settings.already-revoked"></a>

### settings.already-revoked

- **Status**: `409`
- **Title**: Credential already revoked
- **Extensions**: none
- **`type` anchor**: `https://docs.breakdown.example/problems/settings.already-revoked`

<a id="settings.empty-provider"></a>

### settings.empty-provider

- **Status**: `422`
- **Title**: Credential provider must not be empty
- **Extensions**: none
- **`type` anchor**: `https://docs.breakdown.example/problems/settings.empty-provider`

<a id="settings.empty-vault-key"></a>

### settings.empty-vault-key

- **Status**: `422`
- **Title**: Vault key reference must not be empty
- **Extensions**: none
- **`type` anchor**: `https://docs.breakdown.example/problems/settings.empty-vault-key`

<a id="settings.not-found"></a>

### settings.not-found

- **Status**: `404`
- **Title**: Credential not found
- **Extensions**: none
- **`type` anchor**: `https://docs.breakdown.example/problems/settings.not-found`

<a id="settings.provider-mismatch"></a>

### settings.provider-mismatch

- **Status**: `409`
- **Title**: Credential provider cannot change during rotation
- **Extensions**: none
- **`type` anchor**: `https://docs.breakdown.example/problems/settings.provider-mismatch`

## ai-config

<a id="ai-config.already-revoked"></a>

### ai-config.already-revoked

- **Status**: `409`
- **Title**: AI configuration already revoked
- **Extensions**: none
- **`type` anchor**: `https://docs.breakdown.example/problems/ai-config.already-revoked`

<a id="ai-config.empty-model"></a>

### ai-config.empty-model

- **Status**: `422`
- **Title**: AI assistant model must not be empty
- **Extensions**: none
- **`type` anchor**: `https://docs.breakdown.example/problems/ai-config.empty-model`

<a id="ai-config.empty-prompt"></a>

### ai-config.empty-prompt

- **Status**: `422`
- **Title**: AI prompt must not be empty
- **Extensions**: none
- **`type` anchor**: `https://docs.breakdown.example/problems/ai-config.empty-prompt`

<a id="ai-config.empty-provider"></a>

### ai-config.empty-provider

- **Status**: `422`
- **Title**: AI provider must be selected
- **Extensions**: none
- **`type` anchor**: `https://docs.breakdown.example/problems/ai-config.empty-provider`

<a id="ai-config.empty-vault-key"></a>

### ai-config.empty-vault-key

- **Status**: `422`
- **Title**: AI vault key reference must not be empty
- **Extensions**: none
- **`type` anchor**: `https://docs.breakdown.example/problems/ai-config.empty-vault-key`

<a id="ai-config.not-found"></a>

### ai-config.not-found

- **Status**: `404`
- **Title**: AI configuration not found
- **Extensions**: none
- **`type` anchor**: `https://docs.breakdown.example/problems/ai-config.not-found`

<a id="ai-config.provider-mismatch"></a>

### ai-config.provider-mismatch

- **Status**: `409`
- **Title**: AI provider cannot be changed
- **Extensions**: none
- **`type` anchor**: `https://docs.breakdown.example/problems/ai-config.provider-mismatch`
