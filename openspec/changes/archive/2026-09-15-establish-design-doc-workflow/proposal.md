<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

## Why

The frontend's UI/UX has no durable, text-based design documentation
workflow. Design decisions live implicitly in widget code; there is no
screen-spec format, no wireframe convention, and no icon/terminology
glossary. The UI/UX research report (`docs/design/ui-ux-redesign-research-report.md`)
recommends a three-layer text-based design methodology (DTCG tokens,
PlantUML Salt wireframes, structured Markdown screen specs), and the
upcoming Redesign changes (`add-dtcg-design-tokens`,
`redesign-app-shell-navigation`, `add-season-setup-wizard`) need this
documentation foundation **before** implementation so every screen
redesign is specified before coded. New UI target platforms (Svelte,
Slint, GPUI) will reuse the same format.

## What Changes

- Introduce a **screen specification format** (Markdown template with
  fixed sections: purpose, navigation, layout, components/semantics,
  states, interactions, input validation, accessibility/i18n, tests),
  stored per screen at `docs/design/screens/<screen>.md`.
- Introduce **PlantUML Salt wireframes** as the mandatory layout language
  inside screen specs — with the ruled scope from team decision 7:
  Salt documents **static layout only**; behavior, states and timing live
  in the screen spec's structured sections and in tests, never in Salt.
- Introduce an **icon & terminology glossary**
  (`docs/design/glossary.md`): Material Symbols icon → user-facing
  German term → usage context. Rule: every navigation destination and
  primary action MUST have a visible label; icons are reinforcement,
  never the sole carrier of meaning.
- Add pi skills to drive the workflow:
  `design-wireframe-salt` (Salt + screen-spec authoring and validation)
  and extend `openspec-screen-prompt` to reference the new screen-spec
  template and glossary.
- CI-check the documentation: Salt blocks in `docs/design/` MUST compile
  (`plantuml -checkonly`), markdown lint SHALL pass at least for the new
  directory (`markdownlint` is revisited in a follow-up if needed) —
  minimal, deterministic gates only.

## Capabilities

### New Capabilities
- `design-doc-workflow`: rules for text-based design documentation —
  screen-spec format, Salt wireframe scope (static layout only),
  glossary (icon/terminology), storage locations, validation gates,
  and the agent skills that operate on them.

### Modified Capabilities
- `flutter-design-tokens`: no requirement changes (documentation-level
  change; the token-source migration is Change `add-dtcg-design-tokens`).

## Impact

- **New directories:** `docs/design/screens/`, `docs/design/glossary.md`
  (already partially exists: `docs/design/ui-ux-redesign-research-report.md`).
- **Skills:** new `frontend-flutter/.pi/skills/design-wireframe-salt/`;
  `openspec-screen-prompt` receives two new prompt-template sections
  (screen-spec reference, glossary as mandatory copy source).
- **CI:** optional/added step validating Salt diagrams compile. Requires a
  Java/PlantUML runtime in CI (or jar caching) — to be decided between
  a dedicated workflow step vs. reuse of an existing docs job.
- **No runtime code changes** — documentation and tooling only. No
  Flutter widget code is touched by this change.
