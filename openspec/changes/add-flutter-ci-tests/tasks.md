<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: hy3 (opencode-go) -->

## 1. Test execution
- [x] 1.1 `flutter test --coverage` step in `flutter-ci.yml`
- [x] 1.2 Coverage artifact upload for inspection on failure

## 2. Coverage gate
- [x] 2.1 `coverde` installed in CI; pooled `coverde check 80` gate over the
       filtered lcov (all non-generated `lib/**/*.dart`, changed + existing) —
       not a changed-files-only gate (`coverde` has no `--changed-only`;
       documented follow-up per proposal D3)
- [x] 2.2 Threshold value documented in workflow comments + a note that it
       is the mutation-testing-gap substitute (per `flutter-test-pyramid`
       spec D5)

## 3. Drift check
- [x] 3.1 Enable the OpenAPI-client drift step (if not already enabled by
       `wire-openapi-dart-client`); idempotent if both land
- [x] 3.2 Add `backend/openapi.yaml` to the workflow `paths:` filters so
       backend-only OpenAPI changes trigger the drift check

## 4. Documentation
- [x] 4.1 Workflow comment documenting the mutation-testing gap and the four
       compensating practices (coverage / golden / Err-branch / semantic finders)

## Spec-hardening (issue #272) — design resolved

The PR #269 review asked for the exact coverage gate. Resolved in
`proposal.md` (Design Decisions D1–D3) and encoded as requirements in
`specs/flutter-ci-coverage/spec.md`. Implementation Tasks 1–4 remain open;
the design gap is closed.
- [x] Exact coverage gate specified (D1: design targets line >= 80%, branch >=
      70%, both tunable; changed `lib/**/*.dart` only)
- [x] File-scope rules specified (D2: changed/new counted, deleted excluded,
      generated excluded, non-executable = 100%, test files excluded from
      required gate)
- [x] CI command specified (D3: `flutter test --coverage --branch-coverage` +
      `coverde check 80` pooled gate; unsupported line/branch/changed-only flags
      dropped; per-axis targets documented; artifact on failure)
