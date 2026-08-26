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

## Design Decisions (resolved during spec-hardening, issue #272)
The PR #269 review asked for the exact coverage gate. Resolved here; encoded
as requirements in `specs/flutter-ci-coverage/spec.md`.

### D1. Coverage gate thresholds (initial, tunable)
- `coverde` line+branch gate on **changed** `lib/**/*.dart` files:
  - `--min-line-coverage 80`
  - `--min-branch-coverage 70`
- Initial values chosen as a reasonable substitute for the absent mutation
  gate (foundation D5): high enough to matter, low enough not to block
  landing. Tunable at implementation; the values live in `flutter-ci.yml` and
  are documented in a workflow comment.

### D2. File-scope rules for the gate
- **Changed** `lib/**/*.dart` (non-test): counted.
- **New** `lib/**/*.dart`: counted (treated as changed).
- **Deleted**: automatically excluded (no longer measured).
- **Generated** (`lib/api/generated/**`, `**/*.g.dart`, `**/*.freezed.dart`):
  excluded via `--exclude` globs — codegen-owned (foundation §2/§3/§9), never
  gated.
- **Non-executable**: `lib/**` files with zero executable statements (pure
  abstract classes / const holders / type-only) report 100% and do not drag
  the gate.
- **Test files** (`test/**`, `integration_test/**`): excluded from the
  *required* gate (not shipped; exercised by the suite); coverage still
  collected.

### D3. CI command (flag names confirmed against the installed `coverde`
version at implementation)
```
flutter test --coverage
coverde check \
  --input coverage/lcov.info \
  --min-line-coverage 80 \
  --min-branch-coverage 70 \
  --changed-only --base main \
  --exclude 'lib/api/generated/**' \
  --exclude '**/*.g.dart' \
  --exclude '**/*.freezed.dart'
```
- A coverage artifact is uploaded on failure for inspection.
- The workflow comment documents the mutation-testing gap (D5) and the four
  compensating practices (coverage / golden / Err-branch / semantic finders).
