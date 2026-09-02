<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.2 (neuralwatt) -->

## ADDED Requirements

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
