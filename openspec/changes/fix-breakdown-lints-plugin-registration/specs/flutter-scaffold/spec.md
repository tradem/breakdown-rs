<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (neuralwatt) -->

# flutter-scaffold Delta (fix-breakdown-lints-plugin-registration)

## MODIFIED Requirements

### Requirement: Analysis Server Plugin Enforced Via `flutter analyze`

`frontend-flutter/analysis_options.yaml` SHALL register the project's
`breakdown_lints` analyzer plugin in the TOP-LEVEL `plugins:` section with a
RESOLVABLE dependency spec —
`breakdown_lints: { path: packages/breakdown_lints }` (relative to the
workspace root) or an equivalent resolvable form. An empty map
(`breakdown_lints: {}`) is a defect: it is not a resolvable dependency, the
analysis server silently skips the plugin, and all four custom rules go dead.
The legacy `analyzer > plugins` section is also a defect (it triggers
`analysis_options_deprecated_plugins`).

The plugin SHALL load in every analysis-server context that supports plugins —
batch `dart analyze` / `flutter analyze` and the `dart language-server` LSP —
exposing the rules `discard_result`, `no_throw_in_data_domain`,
`no_insecure_tls`, and `no_hardcoded_secrets`. The official `dart mcp-server`
does NOT load `analysis_server_plugin` plugins; that is a known limitation, not
a regression.

Severity is owned by each rule's `LintCode`. The `analyzer: errors:` map does
NOT override plugin diagnostic codes: with both `discard_result: error` and
`breakdown_lints/discard_result: error`, the rules stay at `INFO` and
`dart analyze` exits zero on a violation. Hard failure (non-zero exit) is
therefore provided by the dedicated `tool/breakdown_lints_runner` CI step, or
by the rules reporting `ErrorSeverity.ERROR` directly once migrated.
`flutter analyze` alone MUST NOT be cited as the hard gate until the rules
report at ERROR severity.

#### Scenario: Plugin registration resolves
- **WHEN** the analysis server parses `analysis_options.yaml`
- **THEN** `breakdown_lints` is registered with a resolvable path AND the
  server starts a plugin instance for the workspace (no silent skip)

#### Scenario: A throw appears in lib/data
- **WHEN** a `lib/data/**` file contains a `throw` expression
- **THEN** the analyzer reports `no_throw_in_data_domain` AND the CI lint gate
  exits non-zero

#### Scenario: An insecure TLS bypass is committed
- **WHEN** a file sets `badCertificateCallback = (...) => true` or disables
  client verification
- **THEN** the analyzer reports `no_insecure_tls` AND the CI lint gate exits
  non-zero

#### Scenario: A discarded future in a widget build
- **WHEN** a build method leaves a `Future` as a statement
- **THEN** the analyzer reports `discard_result` unless suppressed with a
  `// ignore: discard_result` reason comment

#### Scenario: Negative activation test asserts each rule ID
- **WHEN** a fixture file intentionally triggers all four rules (a discarded
  `Future`, a `throw` in `lib/data`, a trust-all `SecurityContext`, and a
  secret-literal assignment)
- **THEN** the analyzer diagnostics contain **all four** rule IDs, proving each
  rule is registered and active — not merely that the plugin is loaded

#### Scenario: Clean code passes analysis
- **WHEN** the seeded project contains no rule violations
- **THEN** `flutter analyze` and the CI lint gate pass clean (zero false
  positives)
