<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (neuralwatt) -->

# Tasks: Fix `breakdown_lints` plugin registration

## 1. Fix the registration

- [ ] 1.1 In `frontend-flutter/analysis_options.yaml`, replace
  `plugins: breakdown_lints: {}` with
  `plugins: breakdown_lints: { path: packages/breakdown_lints }` and update the
  surrounding comment (top-level section, resolvable path, loads in batch and
  LSP).
- [ ] 1.2 Verify the batch path: create a fixture with one violation per rule
  (discarded `Future`, `throw` in `lib/data`, trust-all `SecurityContext`,
  secret literal) and confirm `dart analyze` reports all four rule IDs.
- [ ] 1.3 Verify the LSP path: confirm `lsp_diagnostics` (pi
  `@ian-pascoe/pi-lsp`) reports the same rule IDs on the fixture.
- [ ] 1.4 Confirm `dart mcp-server` `analyze_files` does NOT surface the rules
  and record it as a known limitation in the docs.

## 2. Decide and implement the enforcement path

- [ ] 2.1 Re-confirm finding 5: neither `discard_result: error` nor
  `breakdown_lints/discard_result: error` raises a plugin diagnostic above
  `INFO`.
- [ ] 2.2 Decide between (a) rules report `ErrorSeverity.ERROR`, (b) keep
  `breakdown_lints_runner` as the hard gate, or (c) both — see `design.md`.
- [ ] 2.3 Verify and document the suppression syntax: only
  `// ignore: breakdown_lints/<code>` (and the `ignore_for_file` variant)
  suppress a plugin diagnostic; the unqualified form does not. Correct the four
  rules' `correctionMessage`/doc comments in
  `frontend-flutter/packages/breakdown_lints/lib/rules/*.dart` to advertise the
  qualified form. Confirm no existing `// ignore: <code>` comments need
  migration (none at proposal time).
- [ ] 2.4 Implement the decision. For (a): set the three hard rules'
  `LintCode` severity to `ERROR` and keep `no_hardcoded_secrets` advisory.
- [ ] 2.5 Clean up the `analyzer: errors:` block to match the decision (remove
  entries that have no effect on plugin codes).
- [ ] 2.6 If (a) is chosen, validate in CI that `flutter analyze` alone exits
  non-zero on a violating fixture, then retire
  `frontend-flutter/tool/breakdown_lints_runner/` and its CI step.

## 3. Reconcile documentation

- [ ] 3.1 `frontend-flutter/AGENTS.md` §5/§6: correct "only loads in IDE/LSP
  mode" and the CI-gate description.
- [ ] 3.2 Update the #299 references (the archived change premise and any
  issue text) to the corrected Dart 3.13 loading behavior.
- [ ] 3.3 Note the pi LSP setup (Dart MCP + `@ian-pascoe/pi-lsp`) where the
  agent-facing tooling is documented.

## 4. Regression guard

- [ ] 4.1 Add a check that fails when `breakdown_lints` is registered without a
  resolvable path (e.g. a shell/Dart assertion in the CI workflow).
- [ ] 4.2 Add the negative activation test asserting all four rule IDs, and
  keep the clean-fixture case as the zero-false-positive proof.
