# flutter-openapi-client Specification

## Purpose
TBD - created by archiving change add-flutter-app-foundation. Update Purpose after archive.
## Requirements
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
> the actual checked-in `openapi.yaml`. The ADR-007 sketch has since been
> corrected by the `amend-adr-007-rest-sketch` change.

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

### Requirement: Repository Wrappers Surface Result/ProblemError
Each aggregate-boundary repository in `data/` SHALL wrap the generated
`breakdown_api` client and return `Result<Dto, ProblemError>` (fpdart). Raw
HTTP types never leak into `domain/` / `features/`. RFC 9457 problem
responses are mapped to `ProblemError(code, ...)` exposing the stable
`{context}.{reason}` code; `detail` is never branched on.

#### Scenario: A 409 conflict is returned
- **WHEN** `POST /seasons` returns `409` with `code: seasons.conflict`.
- **THEN** the repository returns `Err(ProblemError(code:
  "seasons.conflict"))` (never throws); the calling provider surfaces
  `AsyncError` and the widget branches on `code`, never on `detail`.

### Requirement: CI Drift Check Enforced
CI SHALL regenerate the Dart client into a throwaway tree and `diff` against
the committed `lib/api/generated/`; any difference fails the build with a
regenerate instruction. A hand-edit to a generated file fails the same
check.

#### Scenario: Spec changed, client not regenerated
- **WHEN** a PR modifies `backend/openapi.yaml` but `lib/api/generated/` is
  unchanged.
- **THEN** CI fails on diff with a regenerate instruction.

### Requirement: ADR-007 REST Sketch Corrected
ADR-007 §"CQRS-Aware API Design" SHALL describe the API as resource-oriented
REST with CQRS semantics (write = `POST` to resource/collection routes, read
= `GET` to projection-backed routes), citing `backend/openapi.yaml` as the
source of truth — replacing the stylized `POST /commands/{aggregate}/{action}`
command-bus sketch.

#### Scenario: A reader consults ADR-007 for the API shape
- **WHEN** a contributor reads ADR-007 to understand the client API contract.
- **THEN** the section describes resource-REST matching `openapi.yaml`, with
  a "Supersedes" note linking to the `flutter-openapi-client` spec, and no
  stale command-bus sketch remains.

