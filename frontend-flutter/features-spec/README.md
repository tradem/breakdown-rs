<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: hy3 (opencode-go) -->

# Gherkin critical acceptance scenarios (`features-spec/`)

This directory holds the `.feature` files for the three **designated
business-critical acceptance scopes** mandated by the `flutter-gherkin-hybrid`
decision (Q2→c) and `frontend-flutter/AGENTS.md` §6:

| Scope | File | Gates exercised |
| --- | --- | --- |
| Soll-Ist report | `soll_ist_report.feature` | planned vs actual; moved/missing/skipped/reshot; `final` from `wrapped_at` |
| Continuity photo capture | `continuity_photo_capture.feature` | AUTHZ-GATE preflight + server handler gate; upload → projector-lag → thumb |
| Costume assignment | `costume_assignment.feature` | optimistic update + projection refresh; role denial on the costume stream |

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

### Run it

```bash
bash tool/run_gherkin.sh          # needs a connected device/emulator
```

The `@critical` acceptance scenarios are currently tagged `@pending` because
their screens are not yet landed; the runner's `tagExpression` is
`not @pending`, so the default on-device pass runs only `smoke.feature`. When a
screen ships, **remove `@pending` from its Scenario(s)** to promote them into
the on-device pass.

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
- [ ] The three designated critical scopes each have a `.feature`; a PR that
      substantially changes one of those screens without an accompanying
      `.feature` (or a justified exclusion) is blocked.

## Task 5.2 — CI gate / review checklist

Two complementary gates enforce the on-device requirement:

1. **Static CI gate** (`gherkin-critical` job in `.github/workflows/flutter-ci.yml`):
   - `dart analyze integration_test/gherkin` — the runner, its configuration
     and every step definition must compile (cheap, non-flaky).
   - `bash tool/check_gherkin.sh` — enforces the discipline: the three
     designated critical `.feature` files exist; every `@critical` scenario is
     also `@pending` (i.e. not promoted into the on-device pass before its
     screen lands); and the runner config excludes `@pending`.

2. **On-device gate** (`tool/run_gherkin.sh`, run against a device/emulator):
   the authoritative execution of the acceptance scenarios. It is the
   human/device gate today and will be wired into CI against an emulator by the
   follow-up change that lands each critical screen (at which point its
   `@pending` tag is removed and the scenario enters the on-device pass).

A PR that ships a critical screen without removing `@pending` from its
scenario, or that adds a `.feature` step whose body is a pure-function check,
fails the static gate or the review checklist.
