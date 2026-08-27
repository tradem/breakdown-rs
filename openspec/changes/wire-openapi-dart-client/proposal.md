<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.2 (neuralwatt) -->

# Proposal: Wire the OpenAPI-Generated Dart Client

## Why
Foundation spec `flutter-openapi-client` mandates a generated typed client
as the sole API surface, regenerated from `backend/openapi.yaml`, with a CI
drift check. This change lands the generator wiring, the first generated
client tree, and the `data/` repository wrappers that surface `Result` /
`ProblemError` to the rest of the app.

## What changes
- `frontend-flutter/scripts/regen-client.sh` invoking
  `openapi-generator-cli` against `../backend/openapi.yaml` →
  `lib/api/generated/` (package `breakdown_api`), with a
  `// GENERATED — do not edit` banner.
- First regeneration committed.
- `data/` repository wrappers per aggregate boundary, returning
  `Result<Dto, ProblemError>` — never surfacing raw `http` types to
  `domain/` / `features/`.
- CI drift-check step enabled in `flutter-ci.yml` (regenerate into
  throwaway, `diff` against committed, fail on difference).

## Dependencies
- **Depends on:** `scaffold-flutter-project` (project must exist).
- **Unblocks:** `add-drift-read-cache` (DTOs), `first-screen-seasons`,
  `add-gherkin-critical-scenarios`.

## Non-goals
- No backend OpenAPI spec changes.
- No feature screens (only repository wrappers).
