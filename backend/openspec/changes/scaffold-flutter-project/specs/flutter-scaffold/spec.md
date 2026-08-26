<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: hy3 (opencode-go) -->

## ADDED Requirements

### Requirement: Android-First Flutter Project Scaffold
The Flutter app SHALL be created via `flutter create` as an Android-first
project under `frontend-flutter/`, with min SDK, Kotlin, and AGP versions
pinned. macOS is stubbed (target present but not configured) for later.

#### Scenario: A fresh checkout builds on Android
- **WHEN** a contributor runs `flutter build apk --flavor dev` on a fresh
  clone.
- **THEN** the build succeeds against the pinned toolchain versions with no
  "version not pinned" warnings.

### Requirement: Composition Root Uses Riverpod ProviderScope
`lib/main.dart` SHALL wrap the app in a single `ProviderScope`, wire the
dev/prod flavor from `--dart-define`, and construct a pinned-CA HTTP client.
No disable-verification switch is permitted in any code path.

#### Scenario: A developer tries to add a "trust all certs" debug switch
- **WHEN** a PR adds a bypass of TLS verification outside the dev flavor's
  pinned-CA set.
- **THEN** review rejects it under `flutter-client-authz` / cert-pinning
  rule; dev trusts go into the dev flavor's pinned CA set only.

### Requirement: Custom Lint Plugin Enforced Via `flutter pub run custom_lint`
The scaffold SHALL ship a `breakdown_lints` custom-lint plugin package built
with `custom_lint_builder`, registered in `analysis_options.yaml` under
`analyzer > plugins > custom_lint`, exposing the rules `discard_result`,
`no_throw_in_data_domain`, `no_insecure_tls`, and `no_hardcoded_secrets`. CI
SHALL enforce them with `flutter pub run custom_lint` (the dedicated runner —
`flutter analyze` / `dart analyze` do NOT execute custom_lint rules). The legacy
`analysis_server_plugin` internal API SHALL NOT be used. A clean built-in
`flutter analyze` MUST NOT be treated as proof the rules are active; negative
activation tests (below) provide that proof.

#### Scenario: A throw appears in lib/data
- **WHEN** a `lib/data/**` file contains a `throw` expression.
- **THEN** `flutter pub run custom_lint` reports `no_throw_in_data_domain` as
  an error.

#### Scenario: An insecure TLS bypass is committed
- **WHEN** a file sets `badCertificateCallback = (...) => true` or disables
  client verification.
- **THEN** `flutter pub run custom_lint` reports `no_insecure_tls` as a hard
  error.

#### Scenario: A discarded future in a widget build
- **WHEN** a build method awaits nothing and leaves a `Future` as a statement.
- **THEN** `flutter pub run custom_lint` reports `discard_result` unless
  suppressed with a `// ignore: discard_result` reason comment.

#### Scenario: Clean code passes analysis
- **WHEN** the seeded project contains no rule violations.
- **THEN** `flutter analyze` passes clean (proving the built-in analyzer is
  happy), but this alone does NOT prove `breakdown_lints` is loaded — the
  negative activation tests below are required for that.

#### Scenario: Negative activation test asserts each rule ID
- **WHEN** a fixture file intentionally triggers each rule (e.g.
  `// expect_lint: discard_result` above a discarded future,
  `// expect_lint: no_throw_in_data_domain` above a `throw` in `lib/data`,
  `// expect_lint: no_insecure_tls` above a trust-all `SecurityContext`,
  `// expect_lint: no_hardcoded_secrets` above a secret-literal assignment).
- **THEN** running `flutter pub run custom_lint` on the fixture fails unless
  every expected rule ID is emitted, proving each rule is registered and
  active; the clean fixture remains a separate passing case.
