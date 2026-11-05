<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# Tasks: 831-ai-import-preview-naming-and-gates

## 1. Preview header names the USED provider/model (issue #831, defect 1)

- [x] 1.1 Add `aiJobTelemetryProvider(jobId)` (`job_telemetry.dart`): one
      `getJobAndCache` snapshot returning `JobTelemetrySummary?`, no auto-retry,
      no SSE watch.
- [x] 1.2 Add the pure helpers `aiNamingPairLabel` and `aiNamingComparison`
      (used pair + configured-differs pair, compared over the rendered labels).
- [x] 1.3 Rewrite `AiNamingCard` to take `jobId` and render the used pair as the
      primary line, the configured pair only when it differs, and to drop the
      caption that repeated the configured pair.
- [x] 1.4 Preserve the honest degradation arms: no telemetry / unreadable
      snapshot → the configured pair once in "currently configured" wording;
      unconfigured / failed discovery → `aiDisclosureNamingBodyUnconfigured`;
      pending discovery → the loading note.
- [x] 1.5 Wire the job id through `preview_screen.dart`.
- [x] 1.6 ARB (de/en): add `aiPreviewNamingUsed` and
      `aiPreviewNamingConfiguredDiffers`; remove the now-dead
      `aiPreviewNamingProvider`; regenerate `flutter gen-l10n` output.

## 2. The episode picker renders only while the context is missing (defect 2)

- [x] 2.1 `apply_screen.dart`: drop the unconditional picker `TextButton` below
      the submit button and render it in the missing-context branch, beside the
      notice (same `ai-apply-pick-episode` key).
- [x] 2.2 Extract the pick action into one local closure so the branch renders
      the behaviour unchanged.

## 3. The submit action requires a picked document (defect 3)

- [x] 3.1 `import_submit_screen.dart`: watch `pendingDocumentProvider` and
      include it in the `onPressed` predicate (both kinds share the button).
- [x] 3.2 Keep the in-dispatch missing-document guard as a documented backstop.

## 4. Tests and artifacts

- [x] 4.1 `ai_naming_line_test.dart`: unit coverage for the pair label and the
      comparison; widget coverage for differing / equal / provider-only /
      no-telemetry / failed-read / unconfigured-with-used-pair, plus the long-id
      ellipsis and the loading/degraded copies.
- [x] 4.2 `preview_apply_test.dart`: a telemetry fixture in `setupContainer`;
      the used-vs-configured wiring test; the picker visible with a missing
      context and absent with a resolved one.
- [x] 4.3 `import_submit_screen_test.dart`: the disabled-until-picked contract
      on both kinds; the multi-block test now also proves the document gate.
- [x] 4.4 Regenerate the affected goldens (`flutter test --update-goldens`) and
      eyeball the header/submit rendering.
- [x] 4.5 Update the screen specs (`docs/design/screens/ai-import-jobs.md`,
      `docs/design/screens/ai-import-submit.md`).
- [x] 4.6 Bump `frontend-flutter/pubspec.yaml` (release counter).
- [x] 4.7 `dart format`, `flutter analyze`, `flutter test`.
