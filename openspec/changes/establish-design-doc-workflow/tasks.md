<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

## 1. Screen Spec Template and Location

- [ ] 1.1 Create `docs/design/screens/README.md`: template with the
      nine sections (Purpose & Context, Navigation, Layout, Components
      & Semantics, States, Interactions, Input & Validation,
      Accessibility & i18n, Tests) including a short description per
      section and one filled-in example (a minimal Salt wireframe in
      the Layout section)
- [ ] 1.2 Add the rule box to the template: Salt for static layout
      only; behavior/states/interactions live in Markdown sections
      and tests (team decision 7 from the research report)
- [ ] 1.3 Document the platform-neutrality rule: generic M3
      component vocabulary in specs; Flutter-specific details only in
      tasks and code

## 2. Glossary (Icons & Terminology)

- [ ] 2.1 Create `docs/design/glossary.md` with the table columns
      Material Symbols icon · visible label (German UI copy) ·
      context/screen · copy key; initial content from research
      report §4.5 (checkroom→"Kleidung", person_outline→"Figuren",
      smart_toy→"Import", cloud_off→"Verbindung gestört", FAB add→
      "Season erstellen")
- [ ] 2.2 Formulate the visible-label rule as a norm: every
      navigation destination and primary action gets a visible text
      label; icons reinforce, they never carry meaning alone
- [ ] 2.3 Audit the icons in use under `lib/features/**` against the
      glossary and fill the gaps (documentation only — no code
      changes)

## 3. Pi Skills

- [ ] 3.1 Create `frontend-flutter/.pi/skills/design-wireframe-salt/
      SKILL.md` (SPDX header + co-author): purpose (author, modify,
      and review Salt wireframes and screen specs per the template),
      workflow (read template → compile Salt via `plantuml
      -checkonly` → check glossary conformance), references to
      template and glossary
- [ ] 3.2 Extend the skill with a sample Salt block (from report
      §4.2 target wireframe) and the static-only rule as acceptance
      criteria
- [ ] 3.3 Extend `openspec-screen-prompt/SKILL.md`: (a) reference
      the screen spec template as a mandatory input for a change's
      design.md, (b) add the glossary as the mandatory copy source in
      the prompt template

## 4. CI Validation of Salt Diagrams

- [ ] 4.1 Small script `scripts/check-design-diagrams.sh`
      (monorepo root): extract ```plantuml blocks from
      `docs/design/**/*.md`, place them in temp files, run
      `plantuml -checkonly` per block; exit != 0 on failure with
      file name and line number
- [ ] 4.2 Provide PlantUML jar in a versioned way (download URL +
      SHA256 checksum verified in the script, cached under
      `$CI_CACHE_DIR/plantuml.jar` — follows the CI hardening
      ruleset: SHA pinning, no `curl | bash` patterns)
- [ ] 4.3 GitHub workflow `docs-design-lint.yml` (or extension of an
      existing docs workflow): triggered on `docs/design/**` and the
      script; SHA-pinned action setup, no `github.event.*`
      interpolation in `run:` (root AGENTS.md CI hardening)
- [ ] 4.4 Run the script locally against the research report and the
      template (prove all blocks compile) — the report's blocks
      serve as the test fixture

## 5. Documentation & Verification

- [ ] 5.1 Short note in `frontend-flutter/AGENTS.md` and the
      monorepo README: design docs live under `docs/design/`; screen
      specs are a mandatory part of every screen change (reference
      the `design-wireframe-salt` skill)
- [ ] 5.2 Run `openspec validate` for this change and check all
      artifacts (proposal ↔ specs ↔ tasks consistency)
- [ ] 5.3 Trial run: an agent authors a mini screen spec from the
      template (e.g. a fictional screen or the seasons IST as a
      probe) and validates it via skill/CI — verifies the workflow
      end to end
