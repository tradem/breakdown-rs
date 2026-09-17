<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# 368 — On-device gates for flutter-costume-domains (Gherkin + smoke on emulator)

## Why

The `flutter-costume-domains` change shipped the costume-assignment critical
scenario (Tier 3) and the costume-domains integration smoke (Tier 4) with
harnesses compiling and static gates green — but the authoritative on-device
execution never ran (no emulator in that session). Commit `b1fa3b39`
(redesign-seasons-home) had re-tagged the scenarios `@pending` until the "4.1
emulator seed" landed; that seed now exists (first on-emulator smoke via PR
#441). This change lands the device run and un-blocks promotion.

## What Changes

- **Harness role override (test-support only):** the instrumented Gherkin app
  target gains a `dev-membership:role=<role>` command on its existing
  FlutterDriver data channel; `membershipFetchProvider` honors a
  dev-auth-only, `@visibleForTesting` `DebugMembershipRole` override so the
  `I am authenticated as a "viewer" user` step can flip the client-side
  membership to capability-less at runtime (dart-defines are compile-time and
  the app process is built once per run — a runtime channel is the only
  per-scenario role switch). Production (`main.dart`) never registers the
  handler, mirroring the `debugDioInterceptors` seam.
- **Host-side seeding step:** a new `Given the backend is seeded with costume
  "c-7" and character "ch-3" for season "1"` step creates the season, one
  block (which auto-bootstraps the dev principal as active `costume_assistant`
  in dev-auth mode — verified against the dev API), character and costume via
  real HTTP, then stores the resolved ids in `AppWorld` for the navigation and
  assertion steps (opaque backend ids mapped to the feature's symbolic ids).
- **Promotion:** the two `costume_assignment.feature` scenarios lose `@pending`
  and enter the default on-device pass; the feature prose documents the seed
  + role-override contract.
- **Execution (the issue's actual deliverable):** `tool/run_gherkin.sh` green
  on the emulator for both scenarios (optimistic overlay → projection
  refresh; viewer denial with zero costume-assign network traffic via the
  issue #380 recorder), and `costume_domains_smoke_test.dart` green on device
  via `dart run integration_test run-tests`.

## Capabilities

### New

(none)

### Modified

- `flutter-gherkin-hybrid`: promotion of the costume-assignment critical
  scope from pending to on-device; documented seed + role-override harness
  contract for scenarios that need role-shaped memberships.

## Impact

- Code: `lib/auth/membership/` (dev-auth membership override seam),
  `integration_test/gherkin/` (world, steps, configuration docs),
  `features-spec/costume_assignment.feature`.
- Tests: two scenarios promoted to the on-device gate; no unit-tier changes
  required (the override is test-support-only).
- Non-goals (unchanged from the issue): no new scenarios (continuity capture
  + Soll-Ist stay `@pending` in their own changes), no CI emulator job in
  this issue.

## Decisions

- **D1 (runtime role override vs. two app builds):** per-scenario roles need
  a runtime channel because the runner builds the app once with fixed
  dart-defines; `restartAppBetweenScenarios` restarts the same binary. The
  override rides the existing `enableFlutterDriverExtension(handler:)`
  protocol next to `request-recorder:*`. Guarded by `@visibleForTesting` and
  only wired in `integration_test/gherkin/app.dart`.
- **D2 (seeding via real HTTP from the host-side step):** mirrors the #443
  fault-arm step (`HttpClient` against `API_BASE` from the step body). The
  dev-auth backend bootstraps the dummy principal as active `costume_assistant`
  on block creation, so the seeded season immediately carries the
  `assign_costumes` capability for the happy-path scenario; the viewer
  scenario overrides membership client-side (D1) — the client-side AUTHZ-GATE
  fires before any network call, which is exactly the behavior the acceptance
  spec pins.
