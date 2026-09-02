# flutter-ci-coverage Specification

## Purpose
TBD - created by archiving change add-flutter-ci-tests. Update Purpose after archive.
## Requirements
### Requirement: coverde Coverage Gate on Changed Code
CI SHALL enforce a `coverde` line+branch coverage threshold on changed
`.dart` files. The threshold is the enforced substitute for the
mutation-testing gate that does not exist for Dart/Flutter (documented gap,
foundation `flutter-test-pyramid` spec).

#### Scenario: Changed code falls below threshold
- **WHEN** a PR's changed `.dart` files cover below the configured threshold.
- **THEN** CI fails `coverde check 80 --input coverage/lcov.info` (the coverage gate) with a per-file breakdown.

### Requirement: Coverage Gate Numeric Thresholds

CI SHALL enforce coverage on changed code with design targets of line coverage
>= 80% and branch coverage >= 70% (initial values, tunable). Because
`coverde check` only accepts a single pooled minimum, the enforced gate is
`coverde check 80` over `coverage/lcov.info` (line+branch pooled); the per-axis
targets are the design intent (documented in the workflow file) and MAY be split
via a thin `lcov`/`genhtml` post-step. These thresholds are the enforced
substitute for the mutation-testing gate that does not exist for Dart/Flutter
(documented gap, foundation `flutter-test-pyramid` spec D5).

#### Scenario: A changed hand-written file falls below threshold

- **WHEN** a changed `lib/.../use_case.dart` covers below 80% line / 70%
  branch.
- **THEN** CI fails `coverde check 80 --input coverage/lcov.info` with a per-file breakdown.

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

