# flutter-test-pyramid Specification

## Purpose
TBD - created by archiving change add-flutter-app-foundation. Update Purpose after archive.
## Requirements
### Requirement: Flutter Test Pyramid
The Flutter app SHALL enforce a four-tier test pyramid:
(1) **unit tests** for pure logic in `domain/` + `data/` (mappers, use-cases,
`Result` pipelines, no Flutter imports);
(2) **widget tests** (`flutter_test`) as the bulk, per-screen and
per-component, built on semantic finders (`find.text`/`byKey`/`byType`);
(3) **golden tests** (`matchesGoldenFile`) for any non-trivial widget to
catch rendering/logic drift a plain assertion misses;
(4) **integration tests** (`integration_test`, on device/emulator) for a few
full screen-flow scenarios against a real or mocked API.

#### Scenario: A non-trivial widget is added without a golden
- **WHEN** a PR adds any non-trivial widget that renders domain state —
  `ConsumerWidget`, `StatefulWidget`, or otherwise (not a leaf presentational
  widget).
- **THEN** CI requires an accompanying widget test and a golden test reference
  file for the non-trivial widget that renders domain state (the same
  predicate as the pyramid tier above; only leaf presentational widgets are
  exempt).

#### Scenario: A repository returns Err and the test only asserts Ok
- **WHEN** a `Result`-returning repo/use-case has a test that exercises only
  the `Ok` branch.
- **THEN** review flags it; the Err branch must be asserted explicitly
  (unmatched variant = visible hole).

### Requirement: Coverage Threshold via coverde
CI SHALL enforce a line+branch coverage threshold (enforced via `coverde`)
on changed code, because no maintained mutation-testing tool exists for
Dart/Flutter. The threshold is the *substitute* gate, not a patch for a
mutator that is assumed to exist.

#### Scenario: Changed code falls below threshold
- **WHEN** a PR's changed `.dart` files cover below the configured threshold.
- **THEN** CI fails on the coverage gate.

### Requirement: Mutation Testing Is a Documented Gap (Not a Gate)
The AGENTS.md SHALL explicitly state that no maintained production-grade
mutator exists for Dart/Flutter (a known gap versus the backend's
`cargo-mutants` gate), and that the four compensating practices (coverage
threshold, golden tests, explicit Err-branch assertions, semantic-finder
widget tests) are the enforced substitute. Mutation testing SHALL NOT be
codified as a rule with no tool behind it.

#### Scenario: A contributor proposes adding "run mutation tests" to CI
- **WHEN** the proposal names no maintained Dart mutator wired into CI.
- **THEN** it is rejected as cargo-cult; the contributor is pointed at the
  documented gap and the four substitutes. If a maintained mutator emerges,
  it is scoped to `lib/domain/` + `lib/data/` only (never widgets, never
  goldens).

### Requirement: CI Quality Gates
CI SHALL run `dart format --set-exit-if-changed`, `flutter analyze` (with
custom lint rules), `flutter test --coverage`, the OpenAPI-client drift
check (see `flutter-openapi-client`), `gitleaks` on
`.dart`/`.yaml`/`.arb`, and SHA-pinned GitHub Actions following the
backend's hardening rules.

#### Scenario: A PR introduces an unpinned third-party action
- **WHEN** a workflow uses `@v4` instead of a 40-char SHA.
- **THEN** CI fails (mirrors backend CI hardening rule).

