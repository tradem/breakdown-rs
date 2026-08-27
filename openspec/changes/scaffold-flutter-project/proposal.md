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

### D1. Analyzer-plugin implementation: `analysis_server_plugin` (migrated from `custom_lint`)

> **Migration decision (issue #289):** `custom_lint` (Invertase) is now
> **archived and explicitly declared "no longer under active development"**
> (repo `invertase/dart_custom_lint` → `archived: true`, last commit
> `docs: add notice`, 2026-03-24). Its README warning and the maintainer's
> comment (issue #379) both name the official
> [`analysis_server_plugin`](https://pub.dev/packages/analysis_server_plugin)
> (part of `dart-lang/sdk`, latest 0.3.20, actively maintained) as the
> **recommended** path for custom lints. We therefore **migrate** the
> `breakdown_lints` plugin from `custom_lint` to `analysis_server_plugin`.
> The four rule IDs and the hard-error / advisory exit policy (D3) are
> unchanged by this migration.

- We author a local analyzer **plugin package** `breakdown_lints` (dev-only)
  that depends on `analysis_server_plugin` and exports a `Plugin` subclass
  (registered via a top-level `plugin` variable in `lib/main.dart`) that
  registers `AnalysisRule` instances. This is now the official, maintained,
  recommended path.
- The previously-chosen `custom_lint` + `custom_lint_builder` stack is
  **superseded** by this decision; the earlier rationale ("legacy
  `analysis_server_plugin` is harder to maintain, not recommended") is
  reversed by the upstream deprecation. `custom_lint` 0.8.1 remains on
  pub.dev but is archived and will not track future Dart SDK / analyzer
  releases, so it is no longer a viable long-term dependency.
- **CI enforces the rules via `flutter analyze` / `dart analyze`** — the
  analysis server loads the `analysis_server_plugin` package declared in
  `analysis_options.yaml`, so the four custom rules run as part of the
  normal analyzer pass with **no separate runner command**.
  - This is a strict improvement over the prior `custom_lint` design: a
    clean `flutter analyze` now *does* prove the rules are active (the
    dedicated-runner gap called out in the original D1 is closed).
  - `// ignore: <rule_id>` and `// ignore_for_file:` are handled natively
    by the analyzer's `LintCode`/`ErrorReporter` machinery, so the
    suppression syntax from D3 is unchanged.

### D2. Entrypoint

- `lib/main.dart` (the plugin package entrypoint, per
  `analysis_server_plugin`'s `writing_a_plugin` doc):
  ```dart
  import 'package:analysis_server_plugin/plugin.dart';
  import 'package:analysis_server_plugin/registry.dart';

  final plugin = BreakdownLints();

  class BreakdownLints extends Plugin {
    @override
    String get name => 'breakdown_lints';

    @override
    void register(PluginRegistry registry) {
      registry.registerRule(DiscardResultRule());
      registry.registerRule(NoThrowInDataDomainRule());
      registry.registerRule(NoInsecureTlsRule());
      registry.registerRule(NoHardcodedSecretsRule());
    }
  }
  ```
  - Each `*Rule` extends `AnalysisRule` and registers a `SimpleAstVisitor`
    via `RuleVisitorRegistry` in `registerNodeProcessors` (see
    `analysis_server_plugin`'s `writing_rules` doc). `LintCode` instances are
    declared as `static const` so `// ignore:` suppression works.
- `analysis_server_plugin` is a `dev_dependency` of the `breakdown_lints`
  package. The app's `pubspec.yaml` declares `breakdown_lints` (this analyzer
  plugin package) as a `dev_dependency`; the plugin is loaded by the
  analysis server, so **no separate runner binary** is needed (contrast the
  prior `custom_lint` + `custom_lint_builder` design which required
  `flutter pub run custom_lint`).

### D3. Exact rule IDs and what they flag

- `discard_result` — analog of the backend `discard-result` lint: an
  un-awaited `Future` statement, a discarded `Result`/`Either` return value,
  or a swallowed future returned from a non-async function. Suppressible only
  with `// ignore: discard_result` (the analyzer's native ignore syntax,
  unchanged under `analysis_server_plugin`) plus a reason comment on the
  line; a mandatory reason comment is enforced as a separate review
  convention (foundation §5).
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
    - breakdown_lints
  errors:
    discard_result: error
    no_throw_in_data_domain: error
    no_insecure_tls: error
    no_hardcoded_secrets: warning
```
- The `breakdown_lints` plugin package (which depends on the
  `analysis_server_plugin` framework) is registered under `analyzer >
  plugins`, so the analysis server loads it. The four rule IDs
  are mapped to severities under `analyzer > errors`: the three hard-error
  rules are `error` (fatal in CI) and `no_hardcoded_secrets` is `warning`
  (advisory, non-fatal), mirroring the exit policy in D3. (Severity mapping
  via `analyzer > errors` is the `analysis_server_plugin` equivalent of the
  prior `--no-fatal-warnings` runner flag. Note: the registered plugin key is
  the project package `breakdown_lints`, not the `analysis_server_plugin`
  framework dependency — the latter is only a `dev_dependency` of
  `breakdown_lints`.)
- **CI command:** `flutter analyze` (or `dart analyze`) — the single command
  now runs BOTH the built-in analyzer AND the four `breakdown_lints` rules,
  because the plugin is loaded by the analysis server. No dedicated runner is
  required. A clean `flutter analyze` therefore proves the rules are active
  (the prior `custom_lint` design could not prove this; see D1).
- **Advisory validation**: a fixture containing ONLY a `no_hardcoded_secrets`
  violation exits successfully (warning, non-fatal). A fixture containing each
  hard-error rule (`no_throw_in_data_domain`, `no_insecure_tls`, `discard_result`
  without the mandatory `// ignore: discard_result` + reason) exits
  unsuccessfully. This proves the exit policy is enforced per-rule via the
  `analyzer > errors` severity map, not via a global fatal setting.
