<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.2 (neuralwatt) -->

## ADDED Requirements

### Requirement: coverde Coverage Gate on Changed Code
CI SHALL enforce a `coverde` line+branch coverage threshold on changed
`.dart` files. The threshold is the enforced substitute for the
mutation-testing gate that does not exist for Dart/Flutter (documented gap,
foundation `flutter-test-pyramid` spec).

#### Scenario: Changed code falls below threshold
- **WHEN** a PR's changed `.dart` files cover below the configured threshold.
- **THEN** CI fails on the coverage gate with a per-file breakdown.
