<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: omen-alpha (opencode-go) -->

# Proposal: 380-gherkin-request-recorder — wire the request recorder into the instrumented app

## Summary

Issue #380: the watch-expired Gherkin scenario can assert UI state
(`Processing…`, recovery affordances) but cannot prove **polling stopped**,
and the `no network request leaves the device` AUTHZ-preflight step asserts a
counter (`AppWorld.requestsLeftDevice`) that nothing populates — it documents
the contract instead of observing it.

This change injects a recording Dio interceptor into the **instrumented
Gherkin app target only** (`integration_test/gherkin/app.dart`) and exposes
the recorded counts to the host-side runner through the FlutterDriver data
handler (`driver.requestData`), so both assertion kinds observe real traffic:

- **AUTHZ preflight** (`no network request leaves the device`): zero requests
  against the AUTHZ-GATED photo pipeline (`/photos`, `/continuity-photos`).
  Navigation read-model fetches are legitimate traffic and are deliberately
  NOT counted here — the gate must prevent capture-pipeline traffic, not page
  loads.
- **Post-budget quiescence** (new step `no further network requests leave the
  device`): the total request count stays stable across a 12-second window —
  analytically derived from the watch backoff cap (`2 × kPhotoWatchMaxDelay`,
  10s): if polling had NOT stopped after budget expiry, another refetch would
  land within 10s. No wall-clock jitter budgets; the window is the production
  backoff bound.

## Context and constraints

- The Gherkin runner and the app run in **separate processes** (host runner
  drives the on-device app via FlutterDriver), so the recorder cannot write
  `AppWorld` directly — the count travels over the driver channel.
- All real API traffic flows through Dios built by `buildPinnedDio`
  (bootstrap client + every `apiDioProvider` rebuild on runtime-base /
  active-block change), so the seam must sit there, not on the bootstrap
  instance alone.
- `restartAppBetweenScenarios = true`: the app process restarts per scenario,
  so the recorder resets with the fresh isolate — no host-side reset needed
  (resolves the `AppHook` TODO).
- Production must never carry the recorder: the interceptor is
  `@visibleForTesting` and only the gherkin app target registers it via the
  `debugDioInterceptors` seam; `main.dart` / prod builds stay untouched.
- In dev-auth mode the membership fetch is local (`devAuthMembership`) and
  the IdP transport is unused, so the quiescence window sees no unrelated
  background traffic.

## Non-goals

- No `backend/openapi.yaml` change, no client regeneration.
- No changes to production `lib/` behavior other than the (empty-by-default)
  interceptor seam and the exported backoff-cap constant.
- The D1 dev-IdP HTTP exception transport is not recorded (dev-only, unused
  in the gherkin dev-auth mode).

## Tasks

1. `lib/testing/request_recorder.dart`: recorder counters +
   `RequestRecorderInterceptor` (records total + photo-pipeline counts).
2. `lib/src/network/api_client.dart`: `@visibleForTesting
   debugDioInterceptors` seam appended in `buildPinnedDio` (and the dev IdP
   HTTP branch); export `kPhotoWatchMaxDelay` from `photo_repository.dart`.
3. `integration_test/gherkin/app.dart`: register the interceptor + driver
   data handler (`request-recorder:snapshot` / `:reset`).
4. Steps: populate `AppWorld.requestsLeftDevice` from the recorder; add the
   quiescence step; resolve the TODO comments.
5. `features-spec/continuity_photo_capture.feature`: add the quiescence
   assertion to the watch-expired scenario.
6. Tier-1 unit test for the recorder's route scoping (both branches).

## Affected packages / artifacts

| Package / Artifact | Action | Reason |
|---|---|---|
| `frontend-flutter` (`pubspec.yaml`) | bump 0.1.0+6 → 0.1.0+7 | New test-instrumentation seam |
| `breakdown_api` (`vendor/breakdown_api/`) | none | `backend/openapi.yaml` unchanged |
| `*.g.dart` / `*.freezed.dart` | none | No `@freezed`/`@riverpod`/drift edits |
