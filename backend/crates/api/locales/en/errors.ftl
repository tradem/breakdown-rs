# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: kimi-k3 (neuralwatt)

# Problem-detail messages (ADR-031 D5). One message per registered
# problem code; the key is derived 1:1 from the code
# ({code} -> problem-{code with dashes}). Standard Fluent syntax only
# (Pontoon/Weblate-importable verbatim).

problem-ai-config-already-revoked =
    The AI configuration has already been revoked.

problem-ai-config-empty-model =
    The AI model must not be empty.

problem-ai-config-empty-prompt =
    The AI prompt must not be empty.

problem-ai-config-empty-provider =
    An AI provider must be selected.

problem-ai-config-empty-vault-key =
    The AI vault key reference must not be empty.

problem-ai-config-not-found =
    AI configuration not found.

problem-ai-config-provider-mismatch =
    The AI provider cannot be changed.

problem-auth-idp-unavailable =
    The identity provider is currently unavailable.

problem-auth-invalid-active-block =
    The X-Active-Block header is invalid.

problem-auth-missing-active-block =
    The X-Active-Block header is missing.

problem-auth-unauthenticated =
    Authentication required. Please sign in.

problem-block-not-found =
    Block not found.

problem-block-validation =
    The block request is not valid.

problem-character-not-found =
    Character not found.

problem-character-validation =
    The character request is not valid.

problem-concurrency-version-mismatch =
    The data changed in the meantime. Please reload and retry (expected { $expected_version }, current { $current_version }).

problem-costume-category-archived =
    The costume category is archived and can no longer be modified.

problem-costume-category-not-found =
    Costume category not found.

problem-costume-category-validation =
    The costume category request is not valid.

problem-costume-already-assigned =
    The costume is already assigned to a character (character { $assigned_character_id }).

problem-costume-not-found =
    Costume not found.

problem-costume-validation =
    The costume request is not valid.

problem-domain-conflict =
    The operation conflicts with the current state.

problem-domain-forbidden =
    You are not allowed to perform this action.

problem-domain-not-found =
    The requested resource was not found.

problem-domain-service-unavailable =
    The service is currently unavailable.

problem-domain-validation =
    The request is not valid.

problem-episode-not-found =
    Episode not found.

problem-episode-validation =
    The episode request is not valid.

problem-http-bad-json-body =
    The request body is not valid JSON.

problem-http-bad-path-param =
    Invalid path parameter.

problem-http-bad-query-param =
    Invalid or missing query parameter.

problem-http-bad-request =
    Bad request.

problem-http-internal-error =
    Internal server error.

problem-http-payload-too-large =
    The request exceeds the allowed size limit.

problem-http-request-timeout =
    The request exceeded the time limit.

problem-http-route-not-found =
    The requested route does not exist.

problem-http-unsupported-media-type =
    Unsupported media type.

problem-membership-already-invited =
    This person already has a pending invitation.

problem-membership-bootstrap-not-allowed =
    Bootstrap is only allowed on an empty block.

problem-membership-missing-actor =
    An authenticated user is required for this operation.

problem-membership-no-pending-invitation =
    There is no pending invitation.

problem-membership-not-active-member =
    You are not an active member of this block.

problem-membership-not-found =
    Membership not found.

problem-membership-validation =
    The membership request is not valid.

problem-photo-already-deleted =
    The photo has already been deleted.

problem-photo-not-found =
    Photo not found.

problem-photo-validation =
    The photo request is not valid.

problem-scene-shoot-already-linked =
    The continuity photo is already linked to this scene shoot.

problem-scene-shoot-already-started =
    The scene shoot has already started.

problem-scene-shoot-not-found =
    Scene shoot not found.

problem-scene-shoot-note-not-found =
    Note not found.

problem-scene-shoot-pair-already-exists =
    A scene shoot already exists for this scene and shooting day.

problem-scene-shoot-planned-order-frozen =
    The planned order is frozen once execution data has been recorded.

problem-scene-shoot-terminal-state =
    The scene shoot is in a terminal state.

problem-scene-shoot-validation =
    The scene shoot request is not valid.

problem-scene-already-scheduled =
    The scene is already scheduled on another shooting day (day { $offending_shooting_day_id }).

problem-scene-character-already-assigned =
    The character is already assigned to this scene.

problem-scene-character-not-found =
    Character not found.

problem-scene-not-found =
    Scene not found.

problem-scene-not-scheduled =
    The scene is not scheduled on this shooting day.

problem-scene-validation =
    The scene request is not valid.

problem-season-not-found =
    Season not found.

problem-season-validation =
    The season request is not valid.

problem-settings-already-revoked =
    The credentials have already been revoked.

problem-settings-empty-provider =
    The provider must not be empty.

problem-settings-empty-vault-key =
    The vault key reference must not be empty.

problem-settings-not-found =
    Credentials not found.

problem-settings-provider-mismatch =
    The provider cannot change during rotation.

problem-shooting-day-archived =
    The shooting day is archived and can no longer be modified.

problem-shooting-day-duplicate-order-key =
    This order key already exists for the episode.

problem-shooting-day-not-found =
    Shooting day not found.

problem-shooting-day-validation =
    The shooting day request is not valid.
