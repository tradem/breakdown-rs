<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.2 (neuralwatt) -->

# Proposal: Gherkin Critical Acceptance Scenarios

## Why
Foundation `flutter-gherkin-hybrid` (Q2→c) mandates `.feature` files under
`features-spec/` for three designated business-critical acceptance scopes,
driven by `flutter_gherkin` on device. This change lands the harness and
the three `.feature` sets.

## What changes
- `features-spec/` directory; `flutter_gherkin` config wired into
  `integration_test/`.
- `.feature` for Soll-Ist report acceptance scenarios.
- `.feature` for continuity photo capture (AUTHZ-GATE → upload →
  projector-lag reconciliation → thumb).
- `.feature` for costume assignment (optimistic update + role denial).
- CI gate: `.feature` step bodies must run on device (not pure functions);
  review challenge rule documented.

## Dependencies
- **Depends on:** `scaffold-flutter-project`, `wire-openapi-dart-client`,
  `wire-flutter-oidc-auth` (capture `.feature` needs auth).
- **Unblocks:** nothing (terminal acceptance layer).

## Non-goals
- No `.feature` for non-critical screens (default = widget test).
- No unit-tier scenario moving (steps that only call pure functions stay in
  unit tests).
