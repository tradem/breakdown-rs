<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# 831 — The preview names the model the job USED, and two affordances stop lying about their preconditions

## Why

Issue #831 (live 2026-11-05). Three small client defects in
`frontend-flutter/lib/features/ai_import/`, grouped because they meet in the
same feature folder, the same ARB files and the same widget-test families.

1. **The preview names the configured model twice and the used model never.**
   `AiNamingCard` rendered the currently configured `AiConfigView`:
   `assistantModel` as the primary line, `provider.name` as the secondary line,
   and then `aiNamingLine` ("Derzeit konfiguriert: Anbieter …, Modell …") as the
   caption — the same pair again. The model that actually produced the rows was
   not rendered at all, although it is on the wire
   (`AiImportJob.telemetry.provider` / `.model`) and already displayed as
   identity chips on the job cost card.
2. **A stray "Episode wählen…" button under "Import anwenden".**
   `apply_screen.dart` rendered the picker `TextButton` unconditionally, i.e.
   also when the apply context was already resolved (the normal case: the
   context arrives from `aiJobContextProvider` plus the in-preview episode
   creation before the review). A blind removal was not an option either: the
   missing-context notice is an actionless `ListTile`, so the stray button was
   the only way into the episode picker for the `state.context == null`
   recovery.
3. **"Zum Import senden" was enabled with no file picked.** Both flows
   (script PDF / schedule CSV-PDF) enabled the submit button before a document
   was chosen; pressing it produced an error snackbar instead of being
   impossible. The picked document lives in `pendingDocumentProvider` and was
   only checked *inside* the dispatch.

## What Changes

- **Client — the preview names the USED pair.** A new
  `aiJobTelemetryProvider(jobId)` reads the job's content-free telemetry through
  `getJobAndCache` (the same snapshot discipline the Decision-Model line uses —
  one cheap GET, no SSE watch, no projection lookup, no fallback to the
  configuration). `AiNamingCard(jobId:)` renders:
  - primary line `aiPreviewNamingUsed` — `Verwendetes Modell: {model} ({provider})`;
  - a second line `aiPreviewNamingConfiguredDiffers` — `Derzeit konfiguriertes,
    abweichendes Modell: {model} ({provider})` — ONLY when the configured pair
    differs from the used one by provider or model;
  - the caption that repeated the configured pair is gone: each pair is named at
    most once.
  The comparison is FIELD-WISE and treats a blank telemetry half as unknown
  (`aiNamingPairLabel` / `aiNamingComparison`, pure and Tier-1 testable): a
  snapshot carrying only the provider never claims the configured model differs,
  so no half-empty "differs" claim is invented.
- **Client — honest degradation preserved.** A job without telemetry (an old
  job) or an unreadable snapshot names no used model and claims no comparison:
  the card names the configured pair ONCE in the explicit "currently
  configured" wording (`aiNamingLine`). An unconfigured account or a failed
  discovery (with no used pair) keeps `aiDisclosureNamingBodyUnconfigured`; a
  pending discovery keeps the loading note. A used pair survives an unconfigured
  account — deleting a configuration does not undo the import that ran.
- **Client — the episode picker lives with the notice that needs it.**
  `ai-apply-pick-episode` renders only in the missing-context branch, next to
  `ai-apply-context-missing`; a resolved context leaves nothing under the submit
  button. Same test key, moved with the affordance.
- **Client — the submit affordance states its document precondition.**
  `_SubmitButton` watches `pendingDocumentProvider` and includes it in the
  enablement predicate, so the button stays `onPressed: null` until a file
  exists (and after a successful submit clears it again) — for both kinds, one
  predicate, one button. The in-dispatch missing-document guard stays as a
  backstop; the pick row already renders "Keine Datei gewählt", so the disabled
  state has a visible reason.
- **Copy.** Two new de/en ARB keys (`aiPreviewNamingUsed`,
  `aiPreviewNamingConfiguredDiffers`); the now-unused `aiPreviewNamingProvider`
  ("Anbieter: {provider}") is removed. The obtainable copy sizes are stated
  once, not per surface.

Non-goals: no change to the Decision-Model line (#767), the cost card's
identity chips (#761), the import target resolution (#771), the
`ai-import.apply-blocked` gate (#663) or the apply request; no backend change, no
`backend/openapi.yaml` change, therefore no vendored Dart client regeneration.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `flutter-ai-import-workflow`: the preview header names the job's used
  provider/model and reports the configured pair only as a difference; the
  episode picker is scoped to the missing-context state; the submit action
  requires a picked document.

## Impact

- `frontend-flutter/lib/features/ai_import/import_jobs/job_telemetry.dart` —
  new `aiJobTelemetryProvider` (its own `.g.dart`, regenerated with
  `build_runner`).
- `frontend-flutter/lib/features/ai_import/naming_line.dart` — `aiNamingPairLabel`,
  `AiNamingComparison`, `aiNamingComparison`, rewritten `AiNamingCard(jobId:)`.
- `frontend-flutter/lib/features/ai_import/import_jobs/preview_screen.dart` —
  passes the job id to the card.
- `frontend-flutter/lib/features/ai_import/import_jobs/apply_screen.dart` — the
  picker renders with the missing-context notice only.
- `frontend-flutter/lib/features/ai_import/import_jobs/import_submit_screen.dart`
  — `pendingDocumentProvider` in the enablement predicate.
- `frontend-flutter/lib/l10n/app_de.arb`, `app_en.arb` (+ regenerated
  `lib/l10n/generated/`) — two keys added, one dead key removed.
- Tests: `ai_naming_line_test.dart` (unit + widget for
  differing/equal/no-telemetry/failed-read/unconfigured-with-used-pair),
  `preview_apply_test.dart` (used-vs-configured wiring, picker visibility with a
  resolved and a missing context), `import_submit_screen_test.dart` (disabled
  until a pick, on both kinds). Regenerated goldens:
  `test/features/ai_import/goldens/ai_preview_{merged,continuity}_*.png` (the
  header is one line for a job without telemetry) and
  `ai_import_target_resolved_dark.png` (the submit button is honestly disabled
  before a pick).
- `docs/design/screens/ai-import-jobs.md`, `ai-import-submit.md` — the screen
  specs state the new naming contract, the picker placement and the document
  precondition.
- `frontend-flutter/pubspec.yaml` — version bump for the release counter.
