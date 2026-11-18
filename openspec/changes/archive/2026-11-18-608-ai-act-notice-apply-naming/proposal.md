<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3-flash (opencode-go) -->

# 608 — EU AI Act notice in the apply section + configured provider/model naming across the AI import flow

## Why

Three transparency gaps in the Flutter client (issue #608, all frontend-only):

1. The EU-AI-Act notice (Regulation (EU) 2024/1689, Art. 4 literacy / Art. 50
   transparency) lives on the dedicated About-AI disclosure screen
   (`aiDisclosureActTitle` / `aiDisclosureActBody`) but is NOT present at the
   place where the reviewer actually commits AI-generated content into a real
   project: the apply section "Apply to episode".
2. The apply section and the preview do not state which provider/model the
   import machinery is configured with — only the About-AI screen does.
3. The import start (submission screen) names the AI processing but not the
   configured provider/model.

## Impact

- NO backend change; `backend/openapi.yaml` does not move. The label is
  honestly the CONFIGURED value (an approximation until a later backend issue
  snapshots provider + model per import job at claim time — `AiImportJob` and
  the preview payload carry no model metadata today).
- New l10n key `aiNamingLine` (de/en); everything else reuses existing copy
  (`aiDisclosureActTitle`, `aiDisclosureActBody`,
  `aiDisclosureNamingBodyUnconfigured`, `aiDisclosureNamingBodyLoading`).

## Decisions

1. **Collapsible Act panel in the apply section (user-confirmed).** A
   collapsed-by-default `ExpansionTile` (`ai-apply-act-panel`) inside the
   apply card, subtitle = truncated Act copy, expanded body =
   `aiDisclosureActBody`. The expand affordance is always visible — compact
   review section, transparency preserved, zero flow blockers (the review
   checkbox remains the only gate).
2. **One shared labelling widget.** `AiNamingLine`
   (`lib/features/ai_import/naming_line.dart`) watches the existing
   `configuredAiNamingProvider` (container-cached — ONE discovery shared by
   all three surfaces) and renders copy in every state: configured →
   `aiNamingLine`; unconfigured or discovery failure → the honest
   degradation copy; loading → the loading note (`skipLoadingOnReload`).

## Spec deltas

- `flutter-ai-import-workflow`: the apply section renders the EU AI Act
  panel and the configured provider/model labelling; the preview screen and
  the import submission render the same labelling line; degraded display
  when AI is unconfigured (never an invented name).

## Tasks

1. l10n: `aiNamingLine` in `app_de.arb` / `app_en.arb`, `flutter gen-l10n`.
2. Shared `AiNamingLine` widget + wiring into `_DisclosureCard` (submit),
   `AiPreviewScreen` (top of body), `AiApplySection` (title) and
   `_AiActPanel` (apply card).
3. Widget tests: configured naming on all three surfaces, degradation when
   unconfigured, panel expand behavior, no layout regression (review
   checkbox + submit in place); golden regeneration for the preview screen.
