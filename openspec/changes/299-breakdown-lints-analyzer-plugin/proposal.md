<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: hy3 (opencode-go) -->

# Change: Custom lint runner for breakdown_lints (issue #299)

## Why

The `breakdown_lints` analyzer plugin uses `analysis_server_plugin` (0.3.18),
which only loads inside the analysis server (IDE/LSP mode). The batch
`dart analyze` / `flutter analyze` CLI does not start an analysis server, so it
never loads `analysis_server_plugin` packages. This means the four custom lint
rules (`discard_result`, `no_throw_in_data_domain`, `no_insecure_tls`,
`no_hardcoded_secrets`) are not enforced in CI, contradicting foundation
decision D4 and the CI quality gates documented in AGENTS.md §6.

Verified: a probe file with one violation per rule produces **zero** custom
rule diagnostics under batch `flutter analyze`; only standard lints appear.

Investigation confirmed that the batch CLI loads **no** plugin isolates at all —
neither `analysis_server_plugin` nor `analyzer_plugin`. The plugin loading is
exclusively the analysis server's responsibility. Porting the plugin package
from `analysis_server_plugin` to `analyzer_plugin` was attempted but made no
difference: the batch CLI does not load plugins regardless of which package
they depend on.

## What

Introduce a **custom lint runner** — a standalone Dart script that re-implements
the four `breakdown_lints` rules using the `analyzer` package directly, bypassing
the plugin system entirely. This runner is invoked in CI alongside
`flutter analyze`.

The existing `breakdown_lints` package (using `analysis_server_plugin`) is
**kept as-is** for IDE/LSP enforcement. The custom runner duplicates the rule
logic for CI enforcement.

Concretely:

1. **`frontend-flutter/tool/breakdown_lints_runner/`** — new package with a
   `bin/run_lints.dart` script that uses `AnalysisContextCollection` to analyze
   all `lib/**/*.dart` files and applies the four rules.
2. **`frontend-flutter/analysis_options.yaml`** — re-adds the
   `analyzer > errors` severity block (previously omitted because the codes
   were unrecognized in batch mode). Adds `unrecognized_error_code: ignore` to
   suppress warnings about the custom codes in the batch CLI.
3. **`.github/workflows/flutter-ci.yml`** — adds a `breakdown_lints (custom
   runner)` step that runs the lint runner after `flutter analyze`. Removes
   `continue-on-error` from the analyze step.

## Affected Packages / Artifacts

| Package / Artifact | Action | Reason |
|---|---|---|
| `breakdown_lints_runner` (new) | created | CI enforcement of custom rules |
| `frontend-flutter` (`analysis_options.yaml`) | re-add `errors:` block | IDE severity config |
| `.github/workflows/flutter-ci.yml` | add runner step | CI enforcement |

## Acceptance

- `breakdown_lints` rules are reported by the CI step (via the custom runner).
- `analysis_options.yaml > analyzer > errors` re-applies the four severities.
- The custom runner exits non-zero on violations, zero on clean code.
- `flutter analyze` does not emit `unrecognized_error_code` warnings.
