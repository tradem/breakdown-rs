---
name: openspec-screen-prompt
description: Generate a screen-specific OpenSpec change for frontend-flutter/ using the screen design prompt template. Use when the user wants to plan, spec, or scaffold a new Flutter screen (UI, screen design, feature work) with Material 3 + dark mode, adaptive Android/macOS UX, and roadmap awareness.
allowed-tools: Bash(openspec:*), ask_user
---

<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: omen-alpha (opencode-go) -->

# Screen OpenSpec Prompt — flutter screen design & scaffolding

Generate a complete, self-contained OpenSpec change for a Flutter screen in this
repository, using the prompt template below. The template encodes the project's
non-negotiable conventions (Riverpod-only, Material 3 with dark mode, store
compliance, AUTHZ-GATE, Result discipline, test pyramid).

## Workflow

1. **Collect placeholders via `ask_user`** (one focused question per call):
   - Ask for the screen name (e.g. `CostumeListScreen`) — allow freeform.
   - Ask which feature domain it belongs to (e.g. `costumes`, `photos`,
     `ai_import`) — offer the roadmap phases below as options.
2. **Ground yourself before executing the template:**
   - Read `frontend-flutter/AGENTS.md` (the authoritative client spec).
   - Read the reference implementation `frontend-flutter/lib/features/seasons/`.
   - Look up the relevant read-model/command routes in `backend/openapi.yaml`.
   - Read the screen spec template `docs/design/screens/README.md` and
     the glossary `docs/design/glossary.md` (both mandatory inputs —
     see step 4).
3. **Sanity-check against the roadmap.** If the requested screen belongs to a
   later phase than work that is still unfinished in an earlier phase, challenge
   the priority in the `ask_user` exchange before proceeding.
4. **Execute the prompt template** with the placeholders filled in. Produce the
   OpenSpec change artifacts, then verify against the embedded self-check.
   - **Screen spec is a mandatory `design.md` input:** the change's
     `design.md` must reference the screen spec at
     `docs/design/screens/<screen-name>.md` (authored in the same
     change, following the template's nine sections and the
     `design-wireframe-salt` skill for the Salt wireframe). The spec
     is written before the implementation tasks.
   - **Glossary is the mandatory copy source:** every visible label,
     icon, and copy key in the change's artifacts comes from
     `docs/design/glossary.md`; new navigation destinations and
     primary actions must be recorded there in the same change, and
     must render a visible text label (icons reinforce only).
5. **Create the change** with the openspec CLI and show the artifact tree.

## Feature roadmap (priority order; later phases build on earlier ones)

- **Phase 1 — Foundation & navigation:** login/OIDC + membership UI,
  series→season→block→episode→scene hierarchy navigation, costume categories.
- **Phase 2 — Core costume domains:** costumes (assign/unassign), characters,
  photos (camera capture/upload, continuity binding), scene shoots (Soll/Ist).
- **Phase 3 — AI features (highest user value):** AI schedule import over
  `/v1/ai-import/*` — provider/model configuration, job submission from raw
  schedules, LLM preview/apply workflow, job status with terminal error states.
- **Phase 4 — Reporting:** Soll-Ist scene-shoot reports, shooting-day
  PDF reports.

## Prompt template

```text
<role>
You are a senior Flutter architect with deep expertise in Material 3 (light and
dark), adaptive layouts for Android and macOS, Riverpod, and OpenSpec-driven
feature development. You work exclusively within this repository and its
established conventions.
</role>

<context>
This is the Flutter client of breakdown-rs (CQRS/event-sourced backend,
generated Dart API client from backend/openapi.yaml consumed as vendor package
breakdown_api, flutter_riverpod as the ONLY state-management and DI mechanism,
fpdart Result types, Drift read-model cache, Material 3 design tokens under
lib/design/). The reference implementation for every screen convention is
lib/features/seasons/ (SeasonsScreen + SeasonsController + SeasonRepository).
Target platforms: Android (primary) and macOS (secondary).

Feature roadmap (in priority order — later phases build on earlier ones):
Phase 1 — Foundation & navigation: login/OIDC + membership UI, hierarchy
navigation, costume categories.
Phase 2 — Core costume domains: costumes, characters, photos (camera,
continuity), scene shoots.
Phase 3 — AI features (highest user value): AI schedule import over
/v1/ai-import/* — provider/model config, job submission, LLM preview/apply
workflow, terminal error states.
Phase 4 — Reporting: Soll-Ist scene-shoot reports, shooting-day PDF reports.
</context>

<task>
Create a complete, self-contained OpenSpec change for the screen [SCREEN_NAME]
of feature domain [FEATURE] that documents the implementation thoroughly,
contradiction-free, and enforces a consistent, contemporary Material 3 UX:

1. Ground yourself first: read frontend-flutter/AGENTS.md, the seasons
   reference implementation, and the relevant routes in backend/openapi.yaml.
   Place the screen within the roadmap; a screen from a later phase must not
   assume unfinished work from earlier phases.
2. Produce the OpenSpec change artifacts (proposal.md, design.md, delta specs
   with machine-checkable requirements and scenarios, tasks.md) separating
   orchestration, presentation, and all test tiers (unit / widget+golden /
   integration).
3. Apply the established screen pattern: ConsumerWidget container with
   asyncValue.when for loading/error/data; pure presentation widgets in
   widgets/ with no Riverpod imports, receiving plain data and callbacks;
   Result-typed repositories; AUTHZ-GATE via currentMembershipProvider before
   every protected handler call; optimistic-after-2xx with bounded-retry
   reconciliation.
4. Design for both light AND dark theme correctness (test both), adaptive
   layouts (Android phones and macOS desktop: navigation, pointer/keyboard
   support), and accessibility — no dark patterns of any kind.
</task>

<constraints>
- Follow frontend-flutter/AGENTS.md strictly; backend/AGENTS.md wins on
  server-owned concerns (API shape, error surface).
- Never edit generated code (vendor/breakdown_api/, *.g.dart, *.freezed.dart)
  and never introduce new state-management or routing packages (no BLoC,
  GetIt, go_router — unless already present in pubspec.yaml; routing decisions
  require their own OpenSpec change).
- No hardcoded colors, spacing, or typography — Theme.of(context) and project
  design tokens only.
- Visible-label rule: every navigation destination and primary action shows
  a visible text label (icon + label); icon-only navigation or actions are
  rejected. All UI copy keys and icon choices come from
  docs/design/glossary.md — new destinations/actions are recorded there in
  this change.
- Salt discipline: the screen spec's wireframe is static layout only;
  behavior/states/timing live in the spec's Markdown sections and tests.
  Every PlantUML block under docs/design/ must compile (CI gate:
  scripts/check-design-diagrams.sh).
- Store compliance (Google Play, Apple App Store, F-Droid): nothing that
  violates their policies. In particular: camera permission requested only at
  the point of use with user-facing rationale; no battery-draining behavior
  (no background polling, no unnecessary wake-ups); FOSS-compatible choices
  only.
- Never block the UI thread. Operations that may take longer than ~100 ms
  expose progress via Material best practice (CircularProgressIndicator /
  LinearProgressIndicator / shimmer skeleton); the UI must never freeze or
  jank on either platform.
- If an existing structure conflicts with your solution, document the
  conflict in the change instead of working around it.
</constraints>

<output_format>
A complete OpenSpec change folder under openspec/changes/<change-slug>/:
- proposal.md — problem, solution, decisions
- design.md — technical decisions, deviations, honestly documented gaps
- specs/<capability>/spec.md — ADDED/MODIFIED requirements with scenarios,
  machine-checkable
- tasks.md — numbered, verifiable work steps including test tasks for every
  requirement

Factual, detailed, complete, contradiction-free. English only.

Few-shot reference for the tasks.md style (excerpt from the archived
first-screen-seasons change):

  ## 1. Controller
  - [ ] 1.1 `features/seasons/seasons_controller.dart` — `@riverpod`
        `SeasonsController` returning `AsyncValue<List<SeasonDto>>`
  - [ ] 1.2 `create(name)` returns `Result<SeasonDto, ProblemError>`;
        Ok → optimistic insert, Err → propagated to widget
  ## 2. Repository
  - [ ] 2.1 `SeasonRepository` wrapping the generated client + Drift cache
  - [ ] 2.2 `list()` → `Result<List<SeasonDto>, ProblemError>`
</output_format>

<edge_cases>
- Screen without auth gate: explicitly justify why no AUTHZ-GATE applies.
- Missing or broken API route in the OpenAPI schema: document as a blocker,
  never improvise client-side workarounds or retype DTOs.
- Empty states, projector-lag windows, and retry paths must appear explicitly
  in specs and tasks.
- Camera/photo flows: permission denial, granted-but-revoked, and large-image
  performance must be specified scenarios.
- AI-import flows: LLM processing latency (progress + cancellation), partial
  preview results, and terminal processing errors must be specified scenarios.
- macOS-specific deviations (e.g. NavigationRail instead of BottomNavigation)
  are their own design decision, documented in design.md.
</edge_cases>

Before delivering, verify your output against this checklist:
- Every requirement in specs/ has at least one matching task in tasks.md (and
  test tasks at every applicable tier).
- Both themes (light/dark) and both platforms are addressed.
- No requirement contradicts AGENTS.md or the seasons reference implementation.
```

## Notes

- The template is Reasoning-model-optimized: goal-oriented, no redundant
  step-by-step hand-holding; the model is expected to derive file-level
  details from the codebase, not from the prompt.
- Keep the prompt in sync with changes to `AGENTS.md`, the seasons reference
  implementation, or the roadmap.
