<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: hy3 (opencode-go) -->

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

- Design targets: line coverage >= 80% and branch coverage >= 70% on
  **changed** `lib/**/*.dart` files (initial values, tunable). These are the
  substitute for the absent mutation gate (foundation D5): high enough to
  matter, low enough not to block landing; documented in a `flutter-ci.yml`
  workflow comment.
- `coverde check` enforces a **single pooled** minimum (positional `min`,
  `--input`, `--file-coverage-log-level`); it has no separate line/branch or
  changed-only flags. The CI gate therefore runs `coverde check 80` over
  `coverage/lcov.info` (pooled line+branch). If strict per-axis enforcement is
  required at implementation, add a thin `lcov`/`genhtml` post-step (out of
  scope for this change).

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

### D3. CI command (flags confirmed against the installed `coverde`
version at implementation)

The `flutter-ci.yml` step collects coverage **with branch data**, then enforces
the gate with `coverde`:

```sh
flutter test --coverage --branch-coverage
coverde check 80 --input coverage/lcov.info
```

`coverde check` accepts a single positional minimum (0–100) plus `--input` /
`--file-coverage-log-level`; it does **not** support `--min-line-coverage`,
`--min-branch-coverage`, `--changed-only`, `--base`, or `--exclude` (those
belong to other coverage tools). The `80` is a **pooled** line+branch minimum
computed from the `lcov.info` records. The `flutter test --coverage
--branch-coverage` flag is required so `coverage/lcov.info` contains `BRDA`
branch records before the gate runs; without it the branch target from D1 cannot
be met. The per-axis targets (line ≥ 80% / branch ≥ 70%) are the design intent
from D1; strict per-axis splitting is a documented follow-up (thin `lcov`/
`genhtml` post-step) and out of scope for this change.
- A coverage artifact is uploaded on failure for inspection.
- The workflow comment documents the mutation-testing gap (D5) and the four
  compensating practices (coverage / golden / Err-branch / semantic finders).
