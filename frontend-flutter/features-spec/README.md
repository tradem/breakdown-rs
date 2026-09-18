<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: hy3 (opencode-go) -->
<!-- Co-authored-by: omen-alpha (opencode-go) -->
<!-- Co-authored-by: deepseek-v4-flash (neuralwatt) -->

# Gherkin critical acceptance scenarios (`features-spec/`)

This directory holds the `.feature` files for the **designated
business-critical acceptance scopes** mandated by the `flutter-gherkin-hybrid`
decision (Q2→c) and `frontend-flutter/AGENTS.md` §6 — the three minimum
scopes plus the shoot-day execution scope shipped with
`flutter-shoot-day-execution` (same Soll-Ist family as the report scope,
own screen):

| Scope | File | Gates exercised |
| --- | --- | --- |
| Soll-Ist report | `soll_ist_report.feature` | planned vs actual; moved/missing/skipped/reshot; `final` from `wrapped_at` |
| Soll-Ist execution | `soll_ist_execution.feature` | plan → start → actual-order → finish; skip; wrap finality on the day board |
| Continuity photo capture | `continuity_photo_capture.feature` | AUTHZ-GATE preflight + server handler gate; upload → projector-lag → thumb |
| Costume assignment | `costume_assignment.feature` | optimistic update + projection refresh; role denial on the costume stream |
| Season setup wizard | `setup/season-wizard.feature` | smart defaults; sequential dispatch + per-step reconciliation; partial failure + in-session retry; destructive abort (shipped with `add-season-setup-wizard`) |

`smoke.feature` is **not** a critical scope — it is a harness-proof scenario
that uses only built-in `flutter_gherkin` steps against the already-landed
`SeasonsScreen`, so the on-device runner always has one green scenario proving
the harness works end-to-end.

## How the on-device runner works (not headless)

The suite is driven by `flutter_gherkin` v2.0.0 in its `flutter_driver`-based
on-device mode — the runner builds and installs the instrumented app on a
real device/emulator and drives it through the Flutter Driver extension. This
is inherently **on-device**, not a headless pure-Dart VM run.

- Entrypoint: `integration_test/gherkin/gherkin_runner.dart` →
  `GherkinRunner().execute(config)`.
- Instrumented app: `integration_test/gherkin/app.dart` (calls
  `enableFlutterDriverExtension()` then `bootstrap(Flavor.dev)`).
- The runner launches the app in **dev-auth mode** (`DEV_AUTH_SUB=dev-e2e`,
  `API_BASE=http://10.0.2.2:3000`) via `dartDefineArgs`, so the dummy user is
  treated as authenticated (AGENTS.md §7).
- Step definitions live in `integration_test/gherkin/steps/` and interact with
  the running app exclusively through `world.driver` + `find.byValueKey(...)`
  (widget keys) — they never import screen widgets and never call a pure
  function to satisfy an assertion.
- The runner launches the app **signed out at the auth gate** (spec
  `flutter-auth-shell`): the `Given the app is launched in dev-auth mode`
  step taps the gate's visible Continue action (`login-continue-button`,
  "Continue as dev-e2e") before asserting the home screen.

**Known harness gap — resolved (Flutter ≥ 3.x, issue #440):**
`flutter_gherkin` 2.0.0 parses the legacy
`Observatory debugger … is available at:` launch output only; modern Flutter
prints `A Dart VM Service on … is available at: …`. There is no upstream fix
(`flutter_gherkin` 2.0.0, last published 2021). The VM-service regex patch is
**tracked in-tree** and applied to the pub-cache copy of the package by a
setup step, so a clean checkout + `bash tool/run_gherkin.sh` works without any
manual pub-cache edit:

- Patch file: `tool/patches/flutter_gherkin-2.0.0-vm-service.patch` (exactly
  the `lib/src/flutter/flutter_run_process_handler.dart` hunk that adds a
  `dart vm service` alternative to `_observatoryDebuggerUriRegex`).
- Setup step: `tool/patch_gherkin.sh` (idempotent; normalizes the pub archive's
  CRLF line endings, applies the patch, verifies). `tool/run_gherkin.sh`
  invokes it **after** `flutter pub get` (which re-fetches the pristine hosted
  package) and **before** launching the runner.
- CI gate: `tool/check_gherkin.sh` asserts the tracked patch file + helper
  exist and (when the package is cached) are applied; the `gherkin-critical`
  CI job additionally runs the apply step right after `pub get` to prove the
  patch applies to a fresh download.
- **UPGRADE ME:** both `tool/patch_gherkin.sh` and `tool/check_gherkin.sh`
  hard-reference the `flutter_gherkin-2.0.0` pub-cache path and the patch file.
  If the dependency is ever upgraded or resolved differently, update both in
  the same change.

### Run it

```bash
bash tool/run_gherkin.sh          # needs a connected device/emulator
```

The `@critical` acceptance scenarios whose screens have not landed carry
`@pending`; the runner's `tagExpression` is `not @pending`, so the default
on-device pass runs `smoke.feature` plus every **promoted** critical scope.
The costume assignment scope is fully promoted (issue #459): no `@pending`
left, so its scenarios now run in the default on-device pass. A screen ships
by **removing `@pending` from its Scenario(s)**; a critical scope may be
fully promoted (no `@pending` left — it then runs on device); the static
checker allows both the pending and the promoted states.

The API endpoint is **configurable**, not bound to the Android-emulator host
alias: `tool/run_gherkin.sh` reads `API_BASE` (and `DEV_AUTH_SUB`) from the
environment, defaulting to `http://10.0.2.2:3000` (emulator loopback) and the
dev dummy principal. A physical device or other target supplies a
network-reachable `API_BASE`.

## Task 5.1 — Review challenge rule

> A `.feature` step whose body only calls a pure function belongs in the
> unit-test tier, **not** in `features-spec/`.

The whole point of these scenarios is to exercise the **end-to-end device/HTTP
path** (AGENTS.md §6: "Steps must run on device via flutter_gherkin"). A step
that, say, calls a mapper and asserts on its return value with no device
interaction or HTTP path is a pure-function test masquerading as an acceptance
test. Such a step:

1. is flagged at review,
2. is moved to `test/` (unit tier, no Flutter imports) or deleted, and
3. the `.feature` is rewritten to drive the real on-device path or dropped.

**Challenge checklist (apply to every PR touching `features-spec/`):**

- [ ] Every `When`/`Then` step drives the device (taps/keys/text via
      `world.driver`) or issues/observes a real HTTP path.
- [ ] No step body is a pure-function assertion (mapper return, local state
      computation) with no device interaction.
- [ ] Setup/assertion steps that legitimately only establish state or verify
      rendered UI (no HTTP) are still allowed — they run on device, they just
      don't issue a request.
- [ ] The designated critical scopes each have a `.feature`; a PR that
      substantially changes one of those screens without an accompanying
      `.feature` (or a justified exclusion) is blocked.

## Task 5.2 — CI gate / review checklist

Two complementary gates enforce the on-device requirement:

1. **Static CI gate** (`gherkin-critical` job in `.github/workflows/flutter-ci.yml`):
   - `dart analyze integration_test/gherkin` — the runner, its configuration
     and every step definition must compile (cheap, non-flaky).
   - `bash tool/check_gherkin.sh` — enforces the discipline: the
     designated critical `.feature` files exist and are tagged
     `@critical` (as real Gherkin tags, not prose); each has at least one
     `Scenario`; and the runner config excludes `@pending`
     (`tagExpression: 'not @pending'`). A critical scope may be either still
     `@pending` (screen not landed) or **fully promoted** (no `@pending` left
     — it then runs on device). Both are valid; the checker no longer fails a
     promoted critical feature.

2. **On-device gate** (`tool/run_gherkin.sh`, run against a device/emulator):
   the authoritative execution of the acceptance scenarios. It is the
   human/device gate today and will be wired into CI against an emulator by the
   follow-up change that lands each critical screen (at which point its
   `@pending` tag is removed and the scenario enters the on-device pass).

The **pure-function-step rule (Task 5.1)** is a **review-only** gate: reliably
auto-detecting “a step body that only calls a pure function” is not feasible,
so `check_gherkin.sh` asserts the structural contract above and the reviewer
applies the 5.1 challenge checklist to every `.feature`/step change. A PR that
ships a critical screen without removing `@pending` from its scenario, or that
adds a `.feature` step whose body is a pure-function check, fails the static
gate or the review checklist.
