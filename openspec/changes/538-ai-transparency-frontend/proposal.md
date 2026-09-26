<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# Proposal: EU AI Act transparency surfaces for the Flutter client (issue #538)

## Why

The backend substratum merged in #540 (issue #517): `SceneView.source`
(`Manual` | `AiExtracted { document_id, external_ref, confidence }`), honest
`confidence: null` on `ShootingDaySource`, `SceneSource` in the regenerated
Dart client, provenance projection column + migration. The client renders NONE
of it today: no point-of-interaction disclosure, no AI framing in preview/apply,
no provenance badge on read surfaces, and the About AI notice is a single buried
ListTile.

## What Changes

- **Import submit screen:** persistent disclosure card before the submit
  action — localized copy via glossary/ARB keys, visible at the point of AI
  interaction ("processed by a server-side AI … results are AI-generated and
  must be verified in the preview").
- **Preview screen:** "AI-extracted content — review carefully" banner above
  the typed payload. The wire preview carries no model confidence values
  (`confidence` exists only on the recorded provenance after apply — the
  pipeline measures none), so no fabricated chips: the banner's review note
  states that nothing in the payload is machine-verified.
- **Apply confirmation:** explicit review checkbox ("I have reviewed the
  AI-extracted content") in the apply card; the submit button stays disabled
  until checked. Selection counts (create/update/skip + edit distance) sit
  next to the acknowledgement.
- **Provenance badges (read surfaces):** a shared l10n-keyed badge renders
  whenever a read row's `source` is `Some(AiExtracted)`: shooting-days day
  list tile, scene-detail shooting-days section (the day picker), scene
  tiles / detail (scene `source_`), and the Soll/Ist board (day-fallback
  title + wrapped banner surface).
- **Scene Drift cache column:** `SceneCacheRows.sourceJson` (nullable text,
  wire JSON stored verbatim — same shape as the existing
  `ShootingDayCacheRows.sourceJson`), cache schema v8 → v9 with the additive
  `from < 9` migration branch.
- **About AI screen:** dedicated `AiDisclosureScreen` (user decision: screen,
  not dialog) with six content blocks: purpose, data flow, provider/model
  naming (from the caller's configured non-secret `AiConfigView` when
  available), payload retention (7-day GC), AI Act reference (Art. 4/50,
  (EU) 2024/1689), and the existing AGPL/source link. The About dialog's AI
  ListTile becomes the doorway (push).
- **AI-config screen:** admin-facing AI-literacy helper card (Art. 4 support)
  above the forms — what the configuration controls, whose data the configured
  provider processes, and the admin's duty to configure honestly.
- **Spec deltas:** `flutter-ai-import-workflow`, `flutter-app-dialogs`
  (About-AI doorway + expanded disclosure), `flutter-ai-config` (literacy
  helper); screen spec `docs/design/screens/about-ai.md` + Salt wireframe.

## Capabilities

### Delta specs

```yaml
- flutter-ai-import-workflow:
  - Added Requirement: Point-of-interaction AI disclosure (submit)
  - Added Requirement: Preview AI-extracted banner
  - Added Requirement: Apply review acknowledgement
  - Added Requirement: Provenance badge on AI-derived read rows
- flutter-app-dialogs:
  - Modified Requirement: Info Dialog Contents (AI notice → About-AI screen doorway)
- flutter-ai-config:
  - Added Requirement: Admin AI-literacy helper text
```

## Impact

- `lib/features/ai_import/import_jobs/` (submit, preview, apply screens)
- `lib/features/app_info/` (About dialog + new About-AI screen)
- `lib/features/ai_import/ai_config/` (helper card)
- `lib/features/shooting_days/widgets/`, `lib/features/scenes/widgets/` +
  `scene_detail_screen.dart`, `lib/features/scene_shoots/` (badges)
- `lib/data/cache/hierarchy_cache*.dart` (scene `sourceJson` + migration)
- `lib/l10n/app_*.arb` (new keys, de template + en catalog)
- Tests: widget + unit + goldens for every touched surface
- No `backend/openapi.yaml` change (wire contract unchanged, additive fields
  consumed). No client regeneration needed: `vendor/breakdown_api` already
  carries `SceneSource` (landed with #540).

## Depends On

- Issue #517 / PR #540 (backend provenance substratum) — merged.
