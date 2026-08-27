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

### Requirement: Analysis Server Plugin Enforced Via `flutter analyze`
The scaffold SHALL ship a `breakdown_lints` analyzer-plugin package built with
`analysis_server_plugin`, registered in `analysis_options.yaml` under
`analyzer > plugins > analysis_server_plugin`, exposing the rules
`discard_result`, `no_throw_in_data_domain`, `no_insecure_tls`, and
`no_hardcoded_secrets` (severities set under `analyzer > errors`). CI SHALL
enforce them with `flutter analyze` / `dart analyze` — the analysis server
loads the plugin, so the four custom rules run as part of the normal analyzer
pass with **no separate runner command** (migrated from `custom_lint`, see
issue #289). A clean `flutter analyze` DOES prove the rules are active; the
negative activation tests (below) provide that proof.

#### Scenario: A throw appears in lib/data
- **WHEN** a `lib/data/**` file contains a `throw` expression.
- **THEN** `flutter analyze` reports `no_throw_in_data_domain` as a hard error
  (non-zero exit).

#### Scenario: An insecure TLS bypass is committed
- **WHEN** a file sets `badCertificateCallback = (...) => true` or disables
  client verification.
- **THEN** `flutter analyze` reports `no_insecure_tls` as a hard error
  (non-zero exit).

#### Scenario: A discarded future in a widget build
- **WHEN** a build method awaits nothing and leaves a `Future` as a statement.
- **THEN** `flutter analyze` reports `discard_result` unless suppressed with a
  `// ignore: discard_result` reason comment.

#### Scenario: Clean code passes analysis
- **WHEN** the seeded project contains no rule violations.
- **THEN** `flutter analyze` passes clean AND this proves `breakdown_lints` is
  loaded (the plugin is run by the analysis server), so the negative
  activation tests below assert per-rule behavior rather than mere loading.

#### Scenario: Negative activation test asserts each rule ID
- **WHEN** a fixture file intentionally triggers each rule (e.g. a discarded
  `Future` in `lib/features`, a `throw` in `lib/data`, a trust-all
  `SecurityContext`, and a secret-literal assignment).
- **THEN** running `flutter analyze` on the fixture fails unless every expected
  hard-error rule ID is emitted, proving each rule is registered and active;
  the clean fixture remains a separate passing case.

#### Scenario: Advisory rule is non-fatal
- **WHEN** a fixture contains ONLY a `no_hardcoded_secrets` violation (no
  hard-error rule).
- **THEN** `flutter analyze` exits successfully (zero exit, warning emitted) —
  proving the advisory rule is non-fatal via the `analyzer > errors` severity
  map.

#### Scenario: Hard-error rule fails the build
- **WHEN** a fixture contains any hard-error rule (`no_throw_in_data_domain`,
  `no_insecure_tls`, or `discard_result` without the mandatory ignore + reason).
- **THEN** `flutter analyze` exits unsuccessfully (non-zero exit) — proving
  hard-error rules fail the build.
