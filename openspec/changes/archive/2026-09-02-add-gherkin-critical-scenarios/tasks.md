<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.2 (neuralwatt) -->

## 1. Harness
- [x] 1.1 `features-spec/` directory
- [x] 1.2 `flutter_gherkin` config wired into `integration_test/`
- [x] 1.3 On-device runner (not headless)

## 2. Soll-Ist report `.feature`
- [x] 2.1 Scenarios: planned vs actual, moved/missing/skipped/reshot flags,
       `final` from `wrapped_at`
- [x] 2.2 Steps defined to exercise the report screen end-to-end on device
       (scaffolded; gated @pending until the screen lands)

## 3. Continuity photo capture `.feature`
- [x] 3.1 Scenario: unprivileged user's capture request is sent to the
       backend and the server-side handler gate (SeasonPhotoAccessPolicy
       inside the HTTP handler) rejects it — assert the denial response, not
       just the absence of a local call; keep the client-side preflight (no
       network call leaves the device) as a separate assertion so BOTH gates
       are exercised
- [x] 3.2 Scenario: upload → projector-lag reconciliation → thumb appears
- [x] 3.3 Steps defined to run via `flutter_gherkin` on device (scaffolded;
       gated @pending until the screen lands)

## 4. Costume assignment `.feature`
- [x] 4.1 Scenario: command → optimistic update → projection refresh
- [x] 4.2 Scenario: role denial on the costume stream

## 5. Discipline
- [x] 5.1 Review challenge rule documented: a `.feature` step whose body
       only calls a pure function belongs in the unit-test tier
- [x] 5.2 CI gate (or review checklist) enforcing the on-device requirement:
       structural gate (`dart analyze` + `check_gherkin.sh`) plus the
       review-only pure-function rule (5.1)
