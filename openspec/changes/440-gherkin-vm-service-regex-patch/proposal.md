<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4-flash (neuralwatt) -->

# Proposal: Tracked flutter_gherkin 2.0.0 VM-service regex patch (issue #440)

## Problem

The on-device Gherkin harness (`features-spec/`, `tool/run_gherkin.sh`) depends
on `flutter_gherkin` 2.0.0. Its `FlutterRunProcessHandler` matches the app's
launch output with `_observatoryDebuggerUriRegex = RegExp(r'observatory .*[:] ...')`,
which only recognizes the legacy `An Observatory debugger and profiler on ... is
available at:` wording. Flutter ≥ 3.x prints `A Dart VM Service on ... is
available at: ...`, so the regex never matches and the runner deterministically
times out with `Timeout while waiting for observatory debugger uri` (default
`0:01:30`).

There is no upstream fix: `flutter_gherkin` 2.0.0 was last published 2021 (its
own pubspec declares `sdk: ">=2.12.0 <3.0.0"`), and the project is effectively
stalled. The only working fix today is a **one-line regex patch** hand-applied
to the pub-cache copy of the package (`lib/src/flutter/flutter_run_process_handler.dart`).
Because `tool/run_gherkin.sh` runs `flutter pub get` (which re-resolves the
pristine hosted package) before starting the runner, the hand-edit is wiped on
every invocation and is entirely absent on a clean contributor/CI checkout.
CodeRabbit flagged this on PR #439; the workaround was documented as a "Known
harness gap" in `features-spec/README.md`.

## Decision (user-confirmed)

**Mechanism: a tracked patch file + idempotent setup step, no re-vendor**
(option A of 3). We do NOT fork `flutter_gherkin` (`dependency_overrides` with
a git source) and do NOT vendor the 43-file package into the repo. Instead:

- The exact patch lives in-tree at
  `frontend-flutter/tool/patches/flutter_gherkin-2.0.0-vm-service.patch`
  (a 1-hunk unified diff against the pristine 2.0.0 source, adding a
  `dart vm service` alternative to `_observatoryDebuggerUriRegex`).
- `frontend-flutter/tool/patch_gherkin.sh` applies it to the pub-cache copy,
  idempotently, from a clean checkout (normalizes the pub archive's CRLF line
  endings so the patch applies, then verifies the resulting file).
- `tool/run_gherkin.sh` invokes the apply step **after** `flutter pub get` and
  **before** launching the runner. A clean checkout +
  `bash tool/run_gherkin.sh` therefore works with no manual pub-cache edits.
- `tool/check_gherkin.sh` asserts the tracked patch + helper exist and, when
  the package is cached, that it is applied. The `gherkin-critical` CI job
  additionally runs the apply step right after `pub get`, proving the patch
  applies to a fresh download on a clean runner.

## Design

### Flutter client

1. **Tracked patch** `tool/patches/flutter_gherkin-2.0.0-vm-service.patch`:
   unified diff against pristine `flutter_gherkin` 2.0.0
   (`lib/src/flutter/flutter_run_process_handler.dart`), one hunk:

   ```diff
   -    r'observatory .*[:] (http[s]?:.*\/).*',
   +    // Flutter <=2.x printed "An Observatory debugger and profiler on ...
   +    // is available at: ..."; Flutter 3.x prints "A Dart VM Service on ...
   +    // is available at: ...". Match both wordings (local patch — upstream
   +    // flutter_gherkin 2.0.0 only knows the legacy wording).
   +    r'(?:observatory|dart vm service) .*[:] (http[s]?:.*\/).*',
   ```

2. **Setup step** `tool/patch_gherkin.sh`:
   - Resolves the repo root and the pub-cache path
     (`$PUB_CACHE`/`~/.pub-cache` → `hosted/pub.dev/flutter_gherkin-2.0.0/`).
   - **Idempotent:** if the target already carries the `dart vm service`
     alternative it is a no-op (`exit 0`).
   - **CRLF-robust:** pub archives ship CRLF; GNU `patch`/`git apply` reject
     CRLF targets, so the file is LF-normalized before applying (Dart is
     line-ending-agnostic). Works from a fresh download or a previously
     normalized cache.
   - Verifies the applied file; `--check` mode only verifies (no mutation),
     used by `check_gherkin.sh`.

3. **Runner wiring** `tool/run_gherkin.sh`: after `flutter pub get`, call
   `bash tool/patch_gherkin.sh` before
   `dart integration_test/gherkin/gherkin_runner.dart`.

4. **Static CI gate** `tool/check_gherkin.sh`: new `flutter_gherkin VM-service
   patch check` section asserts the tracked patch file + helper exist; if the
   package is present in the cache, asserts it is applied (via
   `patch_gherkin.sh --check`). If the package is not yet cached (fresh
   checkout before first `pub get`), it passes — the patch will apply on the
   first run. The section hard-references the 2.0.0 pub-cache path and is the
   designated UPGRADE-ME surface (updated in the same change as any
   `flutter_gherkin` version bump).

5. **CI workflow** `.github/workflows/flutter-ci.yml` (`gherkin-critical` job):
   a `Apply flutter_gherkin VM-service patch` step between `flutter pub get`
   and `dart analyze integration_test/gherkin` that runs the apply script.
   This proves the patch applies to a fresh download on a clean runner — the
   exact clean-emulator scenario from the issue — and keeps the discipline
   check deterministic regardless of pub-cache state.

6. **Docs** `features-spec/README.md`: replace the "Known harness gap (manual
   pub-cache edit)" paragraph with a "resolved, tracked patch" description,
   pointing at the patch file, the setup step, and the CI checks, with the
   UPGRADE-ME note.

## Guardrail compliance

- No re-vendor: `flutter_gherkin` remains a hosted pub dependency (`pubspec.lock`
  unchanged, still `source: hosted`). No license/analysis-surface implications.
- No changes to `vendor/breakdown_api/`, `*.g.dart`, or `*.freezed.dart`
  (rebuild-only boundary untouched).
- No hand-edit of the pub-cache copy is required on any contributing machine;
  the patch is applied from the tracked file by the setup step.
- `patch_gherkin.sh` uses only POSIX shell + `sed`/`grep`/`patch`/`mktemp` —
  no Python or other runtime beyond what the repo's shell tooling already
  assumes.
- Deterministic: idempotent, no network beyond `flutter pub get` (already
  required by the runner), no timing dependence.

## Version-bump plan

| Package | Previous | New | Bump | Reason |
|---|---|---|---|---|
| `frontend-flutter` | current | current | none | No version bump: issue-fix tooling/docs/CI change, no runtime or dependency change to the app package |
| `flutter_gherkin` | 2.0.0 | 2.0.0 | none | Hosted dependency unchanged; patch tracked in-tree |
| `breakdown_api` | — | — | none | Not touched |

## Validation plan

- `bash tool/patch_gherkin.sh` against a pristine CRLF copy and a pristine LF
  copy in isolated `PUB_CACHE` sandboxes: patch applies, file byte-identical
  to the known-good patched copy, idempotent re-run no-op, `--check` passes.
- `bash tool/check_gherkin.sh` with (a) patched cache → pass,
  (b) unpatched cached package → fail with actionable message, (c) no cache →
  pass (fresh checkout).
- `bash tool/run_gherkin.sh` on a device/emulator: patch step runs after
  `pub get` and the runner no longer times out on the VM-service URI.
- `dart analyze integration_test/gherkin` unchanged/clean (patch is applied to
  the pub-cache copy, tracked sources unaffected).
- CI `gherkin-critical` job: apply step + `check_gherkin.sh` pass on a clean
  runner (fresh download).
- No `backend/openapi.yaml` change → no OpenAPI-client regeneration.
