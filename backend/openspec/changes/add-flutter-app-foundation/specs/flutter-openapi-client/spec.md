<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.2 (neuralwatt) -->

## ADDED Requirements

### Requirement: OpenAPI-Generated Dart Client
The Flutter app SHALL consume the backend's checked-in `backend/openapi.yaml`
as the single source of truth for its API surface, generating a typed Dart
client into `frontend-flutter/lib/api/generated/` (package
`breakdown_api`). Hand-edits to generated files are forbidden — the directory
is rebuild-only.

#### Scenario: Regenerating the client against an updated spec
- **WHEN** `backend/openapi.yaml` changes.
- **THEN** the Dart client is regenerated via `openapi-generator-cli` (the
  sole regeneration path — `dart pub run build_runner build` is not used, as
  no OpenAPI `build_runner` builder is configured) and the diff is reviewed
  as part of the PR that changed the spec.

#### Scenario: A developer hand-edits a generated file
- **WHEN** a hand-edit is detected in `lib/api/generated/` (drift check in CI).
- **THEN** CI fails, directing the developer to regenerate rather than edit.

### Requirement: Resource-REST CQRS Client
The generated client SHALL treat HTTP routes as resource-oriented REST with
CQRS semantics — write actions as `POST` to resource/collection routes,
reads as `GET` to projection-backed resource routes — *not* as a stylized
`POST /commands/{aggregate}/{action}` command bus. Route paths are written
below with the API's actual `/v1` context path (ADR-021), matching
`backend/openapi.yaml`.

> Note: this corrects the sketch in ADR-007 §"CQRS-Aware API Design" against
> the actual checked-in `openapi.yaml`. A separate ADR-007 amendment is
> tracked as a follow-up, not in this change.

#### Scenario: Creating a season (write side)
- **WHEN** the user confirms the Create Season form.
- **THEN** the client issues `POST /v1/seasons` carrying the command payload
  and treats the response as command acknowledgement (immediate) distinct
  from the eventual projection update.

#### Scenario: Listing seasons (read side)
- **WHEN** the SeasonsScreen loads.
- **THEN** the client issues `GET` against the read projection under `/v1`
  and reconciles eventual projector lag with optimistic state (see
  `flutter-state-management`).

### Requirement: OpenAPI Drift Check in CI
CI SHALL enforce that the committed Dart client matches the committed
`backend/openapi.yaml`, mirroring the backend's `UPDATE_OPENAPI=1
openapi_drift` discipline. A PR that changes the spec without regenerating
the client, or that hand-edits generated files, fails CI.

#### Scenario: Spec changed but client not regenerated
- **WHEN** a PR modifies `backend/openapi.yaml` but `lib/api/generated/` is
  unchanged.
- **THEN** CI regenerates into a throwaway, diffs against the committed tree,
  and fails on difference with a regenerate instruction.
