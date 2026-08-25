<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.2 (neuralwatt) -->

## 1. Test execution
- [ ] 1.1 `flutter test --coverage` step in `flutter-ci.yml`
- [ ] 1.2 Coverage artifact upload for inspection on failure

## 2. Coverage gate
- [ ] 2.1 `coverde` installed in CI; threshold configured (line + branch)
       on changed `.dart` files only
- [ ] 2.2 Threshold value documented in workflow comments + a note that it
       is the mutation-testing-gap substitute (per `flutter-test-pyramid`
       spec D5)

## 3. Drift check
- [ ] 3.1 Enable the OpenAPI-client drift step (if not already enabled by
       `wire-openapi-dart-client`); idempotent if both land

## 4. Documentation
- [ ] 4.1 Workflow comment documenting the mutation-testing gap and the four
       compensating practices (coverage / golden / Err-branch / semantic finders)
