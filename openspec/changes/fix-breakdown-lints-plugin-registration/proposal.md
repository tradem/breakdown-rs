<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (neuralwatt) -->

# Proposal: Fix `breakdown_lints` plugin registration (issue #634)

## Problem

`frontend-flutter/analysis_options.yaml` declares the project's custom analyzer
plugin as:

```yaml
plugins:
  breakdown_lints: {}
```

An empty map is not a resolvable dependency spec. Per the Dart
`analysis_server_plugin` "Using plugins" documentation, the analysis server
builds a synthetic package from the top-level `plugins:` section and resolves
it with `dart pub upgrade`. `{}` resolves to nothing, so the plugin is
**silently never loaded** and all four custom rules are dead in every context.

Verified against the dev environment (Dart 3.13.2 / Flutter-bundled 3.13.1):

| Context | With `breakdown_lints: {}` | With `path: packages/breakdown_lints` |
|---|---|---|
| `dart analyze` (batch) | no custom diagnostics | `discard_result`, `no_throw_in_data_domain` reported |
| `dart language-server` (LSP) | no plugin instance in the session log | plugin instance + custom diagnostics |
| pi `lsp_diagnostics` | no custom diagnostics | `dart(discard_result)`, `dart(no_throw_in_data_domain)` |
| `dart mcp-server` `analyze_files` | no custom diagnostics | no custom diagnostics (MCP analyzer does not load plugins) |

Consequently:

- The `frontend-flutter/AGENTS.md` §6 claim that the plugin "only loads in
  IDE/LSP mode" is **wrong in both directions**: it does not load in LSP either
  today, and with a resolvable path it also loads in the batch `dart analyze`.
- The premise of the archived `2026-09-02-299-breakdown-lints-analyzer-plugin`
  change ("the batch CLI loads **no** plugin isolates at all") is **outdated**
  for Dart 3.13 — `dart analyze` does load `analysis_server_plugin` plugins.
- The `flutter-scaffold` spec states the plugin is registered under
  `analyzer > plugins`; the code uses the top-level `plugins:` section, and the
  legacy form triggers `analysis_options_deprecated_plugins`.

## What Changes

- **`frontend-flutter/analysis_options.yaml`** — replace the empty map with a
  resolvable path registration:

  ```yaml
  plugins:
    breakdown_lints:
      path: packages/breakdown_lints
  ```

- **Severity / enforcement reconciliation.** Plugin diagnostics carry the
  severity of their own `LintCode`; the `analyzer: errors:` map does **not**
  override plugin codes. Verified with both `discard_result: error` and
  `breakdown_lints/discard_result: error`: the rules stay at `INFO`, so
  `dart analyze` exits `0` on a violation. The spec's "hard error / non-zero
  exit" scenarios therefore do not hold today. The change decides whether the
  hard failure comes from the plugin (rules report `ErrorSeverity.ERROR`) or
  from the existing `tool/breakdown_lints_runner` CI step — see `design.md`.

- **`frontend-flutter/AGENTS.md`** §5/§6 and the #299 references — correct the
  loading description, the CI gate description, and the severity claim.

- **Spec reconciliation** — the `flutter-scaffold` requirement is rewritten to
  describe the top-level registration, the contexts that actually load the
  plugin, and the real severity/enforcement split.

- **Regression guard** — add a check that fails when `breakdown_lints` is
  registered without a resolvable path, plus a negative activation test that
  asserts all four rule IDs (the current `flutter analyze`-only gate cannot
  prove the plugin is active).

## Non-goals

- Rewriting the four rule implementations or their semantics.
- Changing the rule IDs or the suppression mechanism. The documented
  suppression syntax is corrected to the verified plugin-qualified form
  (`// ignore: breakdown_lints/<code>`), and the rules' `correctionMessage`s
  are fixed to match; the rule IDs themselves do not change.
- Removing `tool/breakdown_lints_runner` before the enforcement decision is
  made and validated.
- Making `dart mcp-server` load plugins (out of this repo's control; tracked as
  an upstream limitation).

## Impact

- `frontend-flutter/analysis_options.yaml` (one-block change)
- `frontend-flutter/AGENTS.md` (§5, §6, §11 cross-references)
- `openspec/specs/flutter-scaffold/spec.md` (via delta)
- `frontend-flutter/tool/breakdown_lints_runner/` (only if the enforcement
  decision retires it)
- `.github/workflows/flutter-ci.yml` (only if the CI gate changes)
- No wire-contract, backend, or user-facing change.
