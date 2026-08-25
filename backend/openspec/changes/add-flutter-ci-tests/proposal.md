<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.2 (neuralwatt) -->

# Proposal: Enable Flutter Test + Coverage Gates in CI

## Why
Foundation `flutter-test-pyramid` mandates a `coverde` line+branch coverage
threshold on changed code (the mutation-testing-gap substitute). The
scaffold's `flutter-ci.yml` runs `analyze` + `format` + `gitleaks` only,
with test/coverage deferred "until a project exists." This change enables
`flutter test --coverage` and the `coverde` gate.

## What changes
- `flutter test --coverage` step in `flutter-ci.yml`.
- `coverde` threshold gate on changed `.dart` files (line + branch).
- OpenAPI-client drift check step enabled (co-owned with
  `wire-openapi-dart-client`; whichever lands second flips it on).
- Documentation of the threshold value and the mutation-testing gap in the
  workflow comments.

## Dependencies
- **Depends on:** `scaffold-flutter-project` (needs a project to test),
  `wire-openapi-dart-client` (drift check co-owned).

## Non-goals
- No mutation-testing tooling (documented gap; `flutter-test-pyramid` spec).
- No on-device integration_test in CI yet (separate follow-up).
- No golden-image regeneration pipeline (separate follow-up).
