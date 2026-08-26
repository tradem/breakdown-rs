<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: hy3 (opencode-go) -->

## ADDED Requirements

### Requirement: coverde Coverage Gate on Changed Code
CI SHALL enforce a `coverde` line+branch coverage threshold on changed
`.dart` files. The threshold is the enforced substitute for the
mutation-testing gate that does not exist for Dart/Flutter (documented gap,
foundation `flutter-test-pyramid` spec).

#### Scenario: Changed code falls below threshold
- **WHEN** a PR's changed `.dart` files cover below the configured threshold.
- **THEN** CI fails on the coverage gate with a per-file breakdown.

### Requirement: Coverage Gate Numeric Thresholds
CI SHALL enforce numeric `coverde` line+branch thresholds on changed code:
line coverage >= 80% and branch coverage >= 70% (initial values, tunable).
These are the enforced substitute for the mutation-testing gate that does not
exist for Dart/Flutter (documented gap, foundation `flutter-test-pyramid`
spec D5). The values SHALL be documented in the workflow file.

#### Scenario: A changed hand-written file falls below threshold
- **WHEN** a changed `lib/.../use_case.dart` covers below 80% line / 70%
  branch.
- **THEN** CI fails the coverage gate with a per-file breakdown.

### Requirement: Coverage Gate File-Scope Rules
The `coverde` gate SHALL apply only to changed/new non-test `lib/**/*.dart`
files, SHALL exclude generated files (`lib/api/generated/**`, `*.g.dart`,
`*.freezed.dart`), SHALL treat deleted files as removed from measurement, and
SHALL exclude test files from the required gate while still collecting their
coverage. Non-executable files SHALL report 100%.

#### Scenario: A PR adds only generated files
- **WHEN** a PR's only changed `.dart` files are `*.g.dart` / generated
  client files.
- **THEN** the gate measures no required files and does not fail on the
  absence of hand-written coverage.

#### Scenario: A deleted file is no longer measured
- **WHEN** a previously-covered `lib/.../legacy.dart` is deleted by the PR.
- **THEN** it is excluded from measurement and does not drag the gate.
