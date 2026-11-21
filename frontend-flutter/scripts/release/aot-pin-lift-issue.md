<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

<!--
  Issue body template for `.github/workflows/flutter-aot-canary.yml`.
  The canary prepends one status line (the Dart version the probe ran on) and
  posts the rest verbatim. Keep it free of GitHub Actions expressions — the
  workflow never interpolates into `run:` blocks.
-->

That means [dart-lang/sdk#64917](https://github.com/dart-lang/sdk/issues/64917) — the AOT register-allocator crash (`linearscan.cc: 3013: error: unreachable code`, exit -6) that killed the v0.4.0 release build on all three ABIs — is fixed in the shipped SDK.

## What to do

1. Bump `flutter-version: 3.47.6` in **both** workflows (the gates and the build must see one SDK):

   - `.github/workflows/flutter-ci.yml`
   - `.github/workflows/flutter-release.yml`

   `grep -rn "flutter-version:" .github/workflows/` lists every occurrence.

2. Verify locally before pushing — it compiles the same probe with the SDK's own `gen_snapshot` (seconds, no Gradle, no Android SDK, no keystore):

   ```bash
   bash frontend-flutter/scripts/release/check-flutter-aot-regression.sh
   # exit 0 = fixed, 3 = still crashing, 1 = cannot judge
   ```

3. Push the bump through the normal PR gates, then re-run the release pipeline that was blocked (`Flutter Release` → *Re-run all jobs*) and confirm a green `Build & publish (prod flavor)` job.

4. Drop the pin comments that point at this issue and close it.

## Background

- Upstream: <https://github.com/dart-lang/sdk/issues/64917> (duplicate: #64922)
- Probe: `frontend-flutter/tool/aot-regressions/deferred_final_switch_closure.dart`
- Why no gate caught it: the failure only happens in a **release AOT** build — a deferred `final` assigned inside a pattern `switch` case and captured by a closure. JIT (`dart run`) and every debug/test gate stayed green, so the pipeline looked healthy until `gen_snapshot` ran.
- Pin history: Flutter 3.47.6 (Dart 3.13.x) built the green v0.3.0 release; Flutter 3.50.1 (Dart 3.14.0) aborted v0.4.0.
