<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: hy3 (opencode-go) -->

# Proposal: Scaffold the Flutter Project (Android-first)

## Why
The foundation change (`add-flutter-app-foundation`) landed the
`AGENTS.md` and conventions but intentionally produced **no Flutter code**.
This change creates the actual `flutter create` project under
`frontend-flutter/` so subsequent follow-ups (OpenAPI client, auth, cache,
screens) have a project to land into.

## What changes
- `flutter create` Android-first app (min SDK / Kotlin / AGP pinned; macOS
  stubbed for later).
- `pubspec.yaml` with a strict runtime/dev dependency split:
  - **dependencies** (runtime): `flutter_riverpod`, `riverpod_annotation`,
    `fpdart`, `flutter_secure_storage`, `drift`, `dio` (or `http`),
    `json_annotation`, `freezed_annotation`
  - **dev_dependencies** (generators/builders, not shipped):
    `riverpod_generator`, `freezed`, `build_runner`, `json_serializable`,
    `drift_dev`, plus the custom-lint plugin package that implements the
    foundation rules (`custom_lint` alone provides no rules — the plugin
    package + entrypoint + rule IDs are selected during this change's design
    phase; see tracking issue)
- `analysis_options.yaml` with the custom lint rules referenced by the
  foundation skills (`discard-result` analog, no-throw-in-`data/domain`).
- `lib/main.dart` composition root: `ProviderScope`, flavor wiring, pinned-CA
  `HttpClient` from `--dart-define`.
- Flavors `dev` and `prod` only (per foundation `design.md` §7).
- SPDX headers + co-authored-by on all seeded files; extend
  `scripts/add-spdx-headers.sh` to cover `frontend-flutter/`.

## Dependencies
- **Depends on:** `add-flutter-app-foundation` (merged).
- **Unblocks:** `wire-openapi-dart-client`, `add-flutter-ci-tests`,
  `wire-flutter-oidc-auth`, `add-drift-read-cache`,
  `add-gherkin-critical-scenarios`, `first-screen-seasons`.

## Non-goals
- No OpenAPI client wiring (`wire-openapi-dart-client`).
- No auth/OIDC wiring (`wire-flutter-oidc-auth`).
- No read-cache (`add-drift-read-cache`).
- No screens (`first-screen-seasons`).
- No macOS build configuration.

## Design Decisions (resolved during spec-hardening, issue #272)

The PR #269 review asked which custom-lint implementation to use and for the
exact rule IDs / wiring. Resolved here; encoded as a requirement in
`specs/flutter-scaffold/spec.md`.

### D1. Custom-lint implementation: `custom_lint` + `custom_lint_builder`

- We author a local lint **plugin package** `breakdown_lints` (dev-only)
  that depends on `custom_lint_builder` and exports a `PluginBase` subclass
  registering the rules. This is the maintained, recommended path.
- The legacy low-level `analysis_server_plugin` internal API is **not**
  chosen (harder to maintain, not recommended).
- **CI MUST run `flutter pub run custom_lint`** (or `dart run custom_lint`).
  `flutter analyze` / `dart analyze` do **not** execute custom_lint rules — the
  plugin only contributes diagnostics when the custom_lint runner is invoked.
  The `analysis_options.yaml` registration makes the rules *available*; the
  dedicated command enforces them. A clean `flutter analyze` therefore cannot
  prove the rules are active (see the spec's negative activation tests).

### D2. Entrypoint

- `lib/breakdown_lints.dart`:
  ```dart
  import 'package:custom_lint_builder/custom_lint_builder.dart';

  PluginBase createPlugin() => const BreakdownLints();

  class BreakdownLints extends PluginBase {
    @override
    List<LintRule> getLintRules(CustomLintConfigs configs) => const [
      DiscardResultLint(),
      NoThrowInDataDomainLint(),
      NoInsecureTlsLint(),
      NoHardcodedSecretsLint(),
    ];
  }
  ```
- `custom_lint_builder` generates the plugin registration and is a
  `dev_dependency` of the `breakdown_lints` package. The app's `pubspec.yaml`
  declares **both** `custom_lint` (the runner that executes the plugin) and
  `breakdown_lints` (this plugin package) as `dev_dependencies`.

### D3. Exact rule IDs and what they flag

- `discard_result` — analog of the backend `discard-result` lint: an
  un-awaited `Future` statement, a discarded `Result`/`Either` return value,
  or a swallowed future returned from a non-async function. Suppressible only
  with `// ignore: discard_result` (custom_lint's supported syntax) plus a
  reason comment on the line; a mandatory reason comment is enforced as a
  separate review convention (foundation §5).
- `no_throw_in_data_domain` — a `throw` whose enclosing file matches
  `lib/data/**` or `lib/domain/**` (these layers return `Result`/`Either`).
  Hard error.
- `no_insecure_tls` — any `badCertificateCallback = (...) => true`,
  `dangerouslyAllowInsecureCerts`, a trust-all `SecurityContext`, or a
  verification-disabled `HttpClient`. Hard error (fail-closed).
- `no_hardcoded_secrets` — heuristic match of string literals / field
  assignments against secret patterns (`apiKey`, `clientSecret`, `token`,
  `password`). **Advisory (warning, non-fatal in CI)**; `gitleaks` (a separate
  CI step) remains authoritative for secret detection. The other three rules
  (`no_throw_in_data_domain`, `no_insecure_tls`, and `discard_result` used
  without the mandatory `// ignore: discard_result` + reason) are **hard errors
  (fatal in CI)**, matching the documented exit policy.
- The four IDs above are the canonical enforcement contract. Any legacy names
  in CI docs (`no-throw-in-data/domain`, `no_hardcoded_colors`, `AUTHZ-GATE`)
  are superseded by this list and SHALL be migrated to it when the scaffold
  lands.

### D4. analysis_options.yaml wiring

```yaml
analyzer:
  plugins:
    - custom_lint
custom_lint:
  rules:
    - discard_result
    - no_throw_in_data_domain
    - no_insecure_tls
    - no_hardcoded_secrets
```
- CI command: `flutter pub run custom_lint --no-fatal-warnings` (the
  `--no-fatal-warnings` flag ensures advisory rules like `no_hardcoded_secrets`
  remain warnings/non-fatal while hard-error rules still fail the build). This
  flag is required to actually execute the rules. `flutter analyze` remains in
  CI for the built-in analyzer; custom_lint diagnostics only appear via the
  dedicated runner.
- **Advisory validation**: a fixture containing ONLY a `no_hardcoded_secrets`
  violation exits successfully (warning, non-fatal). A fixture containing each
  hard-error rule (`no_throw_in_data_domain`, `no_insecure_tls`, `discard_result`
  without the mandatory `// ignore: discard_result` + reason) exits
  unsuccessfully. This proves the exit policy is enforced per-rule, not via a
  global fatal setting.
