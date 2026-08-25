<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.2 (neuralwatt) -->

## ADDED Requirements

### Requirement: Hybrid BDD — Gherkin for Business-Critical Acceptance Scenarios Only
The Flutter app SHALL use Gherkin (`.feature` files under
`frontend-flutter/features-spec/`) for business-critical acceptance
scenarios only, driven via `flutter_gherkin` on device. All other behavior is covered by the
remaining pyramid tiers as appropriate — unit, widget, golden, or
integration tests (`flutter-test-pyramid`).

> Rationale: full Gherkin-as-TDD adds heavy ceremony per screen with
> marginal value for UI mechanics; skipping it entirely loses a
> stakeholder-readable acceptance artifact for the flows that matter most
> (continuity authz, soll/ist correctness, costume assignment invariants).
> Hybrid covers the few flows where natural-language acceptance criteria
> genuinely pay for their upkeep.

The designated business-critical `.feature` scopes are, at minimum:

- **Soll-Ist report** (scene_shoot reports: planned vs actual, moved/missing/
  skipped/reshot flags, `final` from `wrapped_at`).
- **Continuity photo capture** (end-to-end: AUTHZ-GATE → multipart upload →
  projector-lag reconciliation → thumb appears).
- **Costume assignment** (command → optimistic update → projection refresh;
  role denial on the costume stream).

Adding a `.feature` for a non-critical screen (e.g. a settings sub-page) is
*not* forbidden, but reviewers challenge it: the default is a widget test.

#### Scenario: A business-critical flow is added without a `.feature`
- **WHEN** a PR changes acceptance behavior in the Soll-Ist report screen — or
  any other designated critical scope (authz, reconciliation, or report
  semantics), not merely a presentation-only edit — and ships only widget
  tests.
- **THEN** review requires an accompanying `.feature` scenario under
  `features-spec/` because this is a designated critical scope.

#### Scenario: A UI-mechanics-only screen is given a `.feature`
- **WHEN** a PR adds a `.feature` for a presentational-only screen (e.g. a
  static about page, a list filter UI).
- **THEN** review challenges it and asks for a widget test instead; the
  `.feature` is moved or removed.

### Requirement: Gherkin Steps Run on Device via flutter_gherkin
`.feature` step definitions SHALL run via `flutter_gherkin` against an
emulator/device (not a headless logic-only runner), because the designated
critical flows hinge on auth-gated HTTP calls and projector-lag
reconciliation that are only meaningful end-to-end. A `.feature` whose steps
could be satisfied by a pure unit test belongs in the unit-test tier, not
in `features-spec/`.

#### Scenario: A .feature step only exercises a pure function
- **WHEN** a step definition's body just calls a mapper and asserts on the
  return value, with no device interaction or HTTP path.
- **THEN** it is flagged and moved to a unit test; the `.feature` is either
  rewritten to exercise the end-to-end path or deleted.
