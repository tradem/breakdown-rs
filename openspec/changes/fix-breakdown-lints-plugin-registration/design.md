<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (neuralwatt) -->

# Design: Fix `breakdown_lints` plugin registration

## Context

The `breakdown_lints` package is an `analysis_server_plugin` (framework
`0.3.18`, `analyzer ^13.3.0`) declared as a dev dependency at
`path: packages/breakdown_lints` and enabled through `analysis_options.yaml`.
The four rules are registered with `registerWarningRule`, so they are
**enabled by default** (unlike `registerLintRule`, which is disabled by
default), but each rule's `LintCode` carries the default `ErrorSeverity.INFO`.

## Findings (verified)

1. `plugins: breakdown_lints: {}` is not resolvable. The analysis server builds
   a synthetic package and resolves it with `dart pub upgrade`; an empty map
   yields no dependency. Result: no plugin isolate, no custom diagnostics.
2. `plugins: breakdown_lints: { path: packages/breakdown_lints }` resolves and
   loads the plugin. Verified in `dart analyze`, in the LSP session log
   (`plugin.status`, `plugin.versionCheck`), and through pi's
   `@ian-pascoe/pi-lsp` integration.
3. The plugin loads in the **batch CLI** as well (Dart 3.13), contradicting the
   #299 premise and `AGENTS.md` §6.
4. The `dart mcp-server`'s `analyze_files` does **not** surface plugin rules
   (it uses an analyzer context without plugin support). Standard errors,
   warnings and lints do surface.
5. The `analyzer: errors:` severity map does not apply to plugin codes. Both
   `discard_result: error` and `breakdown_lints/discard_result: error` leave the
   diagnostic at `INFO`; `dart analyze` exits `0`.
6. A plugin-lint rule can be configured under the plugin entry's `diagnostics:`
   map (`true`/`false`), but that map toggles enablement, not severity.
7. `analysis_options.yaml` already sets `unrecognized_error_code: ignore` to
   silence batch-CLI warnings about the custom codes — a workaround that is
   only needed because the codes are not recognized without a loaded plugin.

## Decision: enforcement path

Three options were considered:

- **(a) Plugin reports at `ErrorSeverity.ERROR`.** Change the three hard rules'
  `LintCode` severity to `ERROR` (keep `no_hardcoded_secrets` at `INFO`/
  `WARNING`). `dart analyze` / `flutter analyze` then exits non-zero and the
  spec's hard-error scenarios hold without a runner. Cost: rule-code change,
  and severity can no longer be tuned from `analysis_options.yaml`.
- **(b) Keep `tool/breakdown_lints_runner` as the hard gate.** Minimal code
  change; the analyzer still surfaces the rules as `INFO` in IDE/LSP/batch, and
  the runner provides the non-zero exit. Cost: duplicated rule logic (the
  runner re-implements all four rules) and the batch CLI already loads the
  plugin, so the runner's original justification is gone.
- **(c) Both.** Rules report `ERROR` and the runner remains as defence in
  depth. Cost: the duplication in (b) stays.

**Recommendation: (a)**, then retire `breakdown_lints_runner` if the analyzer
alone fails the build in CI (validate in the CI workflow, not locally). The
runner's own README and the #299 proposal justify it solely by "the batch CLI
does not load plugins", which is no longer true. Keeping a second copy of four
rules is a drift risk with no remaining purpose once the analyzer is the gate.

## Severity and the `analyzer: errors:` map

The `analysis_options.yaml` `analyzer: errors:` block must not be presented as
the enforcement mechanism. If (a) is chosen, the block can keep only the
`unrecognized_error_code: ignore` entry (and even that can go once the plugin
is always loaded). If (b) is chosen, the block's severity entries are
misleading and should be removed or commented as non-functional for plugin
codes.

## Registration syntax

Top-level `plugins:` with a path spec is the current, non-deprecated form. The
`flutter-scaffold` spec's `analyzer > plugins` wording is stale and triggers
`analysis_options_deprecated_plugins`; the delta corrects it.

The path is written relative to the workspace root (`packages/breakdown_lints`)
rather than absolute, so the registration is portable across checkouts and CI
machines.

## Risks

- **Plugin resolution cost on first LSP start.** The synthetic package
  resolution runs `dart pub upgrade`; the first analysis can exceed a short
  client timeout. pi's LSP configuration therefore raises `diagnosticsMs` to
  15 s.
- **Duplicate diagnostics.** Observed when two analysis contexts cover the same
  file; not a correctness issue, but watch for it in the regression test.
- **Severity change blast radius.** If (a) is chosen, existing `// ignore:
  discard_result` comments stay valid; but any code relying on a zero exit from
  `flutter analyze` will now fail, which is the intent.
