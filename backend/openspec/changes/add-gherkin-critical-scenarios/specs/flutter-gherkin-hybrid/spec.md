<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.2 (neuralwatt) -->

## ADDED Requirements

### Requirement: Three Designated Critical `.feature` Sets
The change SHALL land `.feature` files for the three business-critical
acceptance scopes: Soll-Ist report, continuity photo capture (with
AUTHZ-GATE), and costume assignment (with role denial). All steps run on
device via `flutter_gherkin`.

#### Scenario: A critical flow ships without a `.feature`
- **WHEN** a PR adds or substantially changes the Soll-Ist report screen
  and ships only widget tests.
- **THEN** review requires an accompanying `.feature` under `features-spec/`
  because this is a designated critical scope.

### Requirement: Steps Run on Device, Not as Pure-Function Tests
Every `.feature` step definition SHALL exercise the end-to-end device/HTTP
path via `flutter_gherkin` on device. A step whose body only calls a pure
function MUST be moved to the unit-test tier, not kept in `features-spec/`.

#### Scenario: A step body only asserts on a mapper return value
- **WHEN** a step definition calls a mapper and asserts on the return with
  no device interaction or HTTP path.
- **THEN** it is flagged and moved to a unit test; the `.feature` is
  rewritten to exercise the end-to-end path or deleted.
