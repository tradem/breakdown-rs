<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

## Context

The UI/UX research report (`docs/design/ui-ux-redesign-research-report.md`)
evaluated text-based design approaches (weighted scorecard: portability
to Svelte/Slint/GPUI 45 %, agent suitability 35 %, M3 coverage /
maintenance 20 %). Outcome: a three-layer methodology — DTCG design
tokens (separate change `add-dtcg-design-tokens`), PlantUML Salt layout
wireframes, and structured Markdown screen specs. This change
establishes the documentation layer only: no runtime code, no tokens
pipeline. Team decisions from the report's §8 handshake are normative
for this change (decision 7: Salt = static layout only).

Current state: design decisions live implicitly in widget code; the
seasons reference implementation is the de-facto convention; there is no
screen-spec format, glossary, or validation. The repo already hosts the
research report under `docs/design/`.

## Goals / Non-Goals

**Goals:**
- A durable, text-based, agent-operable design documentation workflow
  (Markdown screen specs + Salt wireframes + glossary).
- CI validation that Salt diagrams compile (deterministic gate).
- Pi skills so agents author and validate specs consistently:
  `design-wireframe-salt`; `openspec-screen-prompt` extension.
- Foundation for the redesign changes (app shell, seasons home, wizard).

**Non-Goals:**
- DTCG token pipeline (Change `add-dtcg-design-tokens`).
- Any Flutter widget/theme code changes.
- Backfilling screen specs for all existing screens (roadmap P5).
- Interactive/graphical design tooling of any kind.
- Mermaid rendering pipelines in CI (PlantUML only for now).

## Decisions

### D1 — Screen spec location & granularity
`docs/design/screens/<screen-name>.md`, one file per screen (kebab-case
name matching the feature screen). Authored within the implementing
OpenSpec change, merged together with the code.

*Why:* `openspec/changes/<change>/` artifacts are change-scoped and
archived; the living spec must survive archive, so it lives outside the
change tree. Alternative (spec in change artifacts only) rejected: it
destroys discoverability after archive.

### D2 — Salt scope: static layout only (team decision 7)
Salt wireframes express component arrangement, grouping, hierarchy.
Behavior/states/interactions/timing live in the Markdown sections and
tests.

*Why:* Research confirmed Salt cannot express M3 interactions (FAB
floating, bottom sheets, rail typography) — encoding behavior in Salt
would produce misleading wireframes. Alternatives: Mermaid (weaker
wireframing), D2 (viable, but PlantUML is already validated in-repo
research and has the Salt DSL purpose-built for wireframes).

### D3 — Glossary as the single copy source
`docs/design/glossary.md` maps Material Symbols icon → German term →
context; mandatory visible-label rule for navigation destinations and
primary actions.

*Why:* The report's core finding was information design (icon
semantics), not visual polish. A glossary is the cheapest mechanism
that prevents regression of icon-only navigation.

### D4 — CI gate: PlantUML `-checkonly` over `docs/design/**/*.md`
CI extracts fenced ```plantuml blocks and runs `plantuml -checkonly`.
Diagram content check (labels present, glossary conformance) is NOT
automated — reviewed by humans/agents at PR time.

*Why:* Deterministic, cheap, no rendering artifacts in CI. Full
rendering to SVG is unnecessary for the gate's purpose. Alternative
(deterministic png rendering + committed artifacts) deferred — doubles
repo size without adding gate value; re-visit if the docs get a
rendered site later.

### D5 — CI implementation details
PlantUML jar fetched SHA-pinned (or vendored via LFS/regular file;
decided in tasks: start with version-pinned download with checksum
verification, matching the repo's SHA-pinning CI hardening rules).
Runs as a step in an existing docs/validation workflow or a new minimal
one — decided during task execution, constrained by CI hardening rules
in the root AGENTS.md (`openspec/`-level rule files apply).

## Risks / Trade-offs

- [Docs rot if specs are written but never reviewed] → mandatory spec
  update is part of each screen change's review checklist; skills
  reference the location.
- [Team bypasses the format for "small" changes] → the format is
  deliberately minimal (9 sections, one page per screen); the skill
  scaffolds the file automatically.
- [CI PlantUML runtime adds build time/fragility] → only triggered on
  changes to `docs/design/**`; jar cached; `-checkonly` is CPU-cheap.
- [Dual toolchain Markdown + PlantUML] → accepted; both are plain text
  and diff well; the single-diagram-language rule prevents format
  proliferation.

## Migration Plan

Additive only. Existing research report stays; glossary and template
are new files; CI step added. No rollback beyond reverting the change.

## Open Questions

None blocking — resolved by team handshake §8 of the research report.
(PlantUML provisioning detail in CI resolved during implementation,
see D5.)
