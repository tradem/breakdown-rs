<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: space-bunny-free (opencode-go) -->

# Combined Costume Identity and Overview Change

## Why

Issues [#510](https://github.com/tradem/breakdown-rs/issues/510) and [#512](https://github.com/tradem/breakdown-rs/issues/512) describe one user-facing problem: a costume has no first-class name, the overview falls back to a raw UUID or notes, and the identity fields are hidden in a separate detail route. The first screen must make the de-facto name (`detail.subject`), category, and text immediately legible while preserving the existing detail save path and secondary notes/assignment/photo workflows.

## What Changes

- Replace the costume list rows with an adaptive photo-backed tile grid.
- Resolve the costume name from the first detail `subject`, then `notes`, and finally a localized generic label; never render a UUID as a user-facing name.
- Add a shared Material-icon catalog used by the shell and deterministic costume-category mapping.
- Render a themed placeholder card for costumes without a ready thumbnail.
- Merge the detail surface into the overview screen: selecting a tile reveals the existing assignment, detail editor, notes editor, and photo management controls inline on the same screen instead of pushing a separate route.
- Keep the existing `POST /v1/costumes/{id}/details` command and add explicit success confirmation for detail saves.
- Update the costume screen spec and glossary, then refresh widget/golden coverage for the new overview.

## Scope and Constraints

- No backend/OpenAPI change; generated API files remain untouched.
- Photo thumbnail bytes are rendered only when the existing client-side photo capability gate allows photo access.
- Costume commands continue to use the existing Result, AUTHZ-GATE, optimistic-after-2xx, and bounded-reconciliation paths.
- Category icons are client-side only. A backend `icon_key` remains a follow-up.

## Acceptance Criteria

- [ ] Compact and expanded layouts render an adaptive 2–3 column tile grid.
- [ ] Each tile shows subject-as-name, category label/icon, and detail text when available; UUIDs are not user-facing names.
- [ ] Photo-ready tiles use a thumbnail surface; photo-less/pending/failed/photo-gated tiles use a themed placeholder.
- [ ] The shell and category icon mapping reference one shared icon source.
- [ ] Detail, notes, assignment, and photo editing remain available from the first screen without the separate detail route.
- [ ] A successful detail save produces visible confirmation.
- [ ] Screen spec and glossary are updated; design diagrams compile.
- [ ] Widget and golden tests cover tile identity, category icon, placeholder, and merged editor; `dart format`, `flutter analyze`, and `flutter test` pass.

## Tasks

1. Add the shared Material icon catalog and category fallback mapping.
2. Add the combined costume screen spec and glossary entries.
3. Replace overview rows with an adaptive tile grid and placeholder/thumbnail surfaces.
4. Extract/reuse the detail surface inside `CostumesScreen`; remove route navigation from tile selection and add save confirmation.
5. Update localization catalogs and regenerate l10n output.
6. Update widget/golden tests and run the Flutter verification suite.
