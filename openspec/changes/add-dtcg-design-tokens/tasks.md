<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

## 1. Token Source (DTCG)

- [ ] 1.1 Create `design/tokens/` (monorepo root) with a README
      (purpose, rules, build invocation)
- [ ] 1.2 `design/tokens/color.json`: primitives (`color.brand.seed`
      = today's seed from `theme.dart`, carried over 1:1) and
      semantic colors with light/dark sets (`$value`,
      `$type: color`, `$description`, alias references)
- [ ] 1.3 `design/tokens/size.json`: dimension tokens for the
      spacing scale (1:1 from `lib/design/spacing.dart`) and corner
      radii (`$type: dimension`)
- [ ] 1.4 `design/tokens/typography.json` + `elevation.json`:
      type-scale and elevation tokens (aligned with M3 defaults)
- [ ] 1.5 Anchor a DTCG conformance check in the build script
      ($-prefixes, resolvable aliases)

## 2. Generation Pipeline

- [ ] 2.1 `scripts/build-tokens.sh` (monorepo root) as the single
      entry point: npm-ci with pinned versions from the committed
      lockfile, Style Dictionary invocation, temp-artifact cleanup;
      timestamps explicitly suppressed
- [ ] 2.2 Create `design/style-dictionary.config.json`: source
      `design/tokens/**/*.json`, target Flutter
      (`frontend-flutter/lib/design/gen/design_tokens.g.dart`),
      deterministic sorting/filtering of the output
- [ ] 2.3 Verify the generated file `design_tokens.g.dart`: pure
      data class (const Color/double), no ThemeExtension, no logic;
      `// GENERATED — do not edit` banner analogous to
      vendor/breakdown_api
- [ ] 2.4 Prove byte stability: a second script run without source
      changes must produce no diff

## 3. Migration of theme.dart / spacing.dart

- [ ] 3.1 `lib/design/theme.dart`: `ColorScheme.fromSeed` reads the
      seed from `DesignTokens.colorBrandSeed`; light/dark behavior
      unchanged (`themeMode: ThemeMode.system` stays)
- [ ] 3.2 `lib/design/spacing.dart`: values delegate to generated
      dimension tokens; public API (field names/types) unchanged
- [ ] 3.3 Compare goldens (login gate, dialogs, seasons screen)
      before/after — must remain pixel-identical (pure-refactor
      proof)
- [ ] 3.4 Existing widget tests pass green without modification
      (proof of stable call sites)

## 4. Skills

- [ ] 4.1 Create `frontend-flutter/.pi/skills/design-tokens-dtcg/
      SKILL.md` (SPDX + co-author): purpose (author/modify tokens,
      run the build, check drift locally), workflow (edit JSON →
      `build-tokens.sh` → commit the diff), format rules (DTCG,
      aliases, light/dark sets), reference to the non-goal (M3
      scheme roles stay Flutter-side)
- [ ] 4.2 Skill template: sample token JSON + sample diff (JSON
      change → generated Dart diff)

## 5. CI Drift Gate

- [ ] 5.1 CI job (extension of an existing workflow or a new minimal
      workflow): triggered on `design/tokens/**` and the generator
      config; regeneration into a throwaway directory; `diff -r`
      against the committed `frontend-flutter/lib/design/gen/`; FAIL
      with a regenerate instruction on difference (analogous to the
      OpenAPI client drift check)
- [ ] 5.2 Comply with CI hardening: SHA-pinned action setup, pinned
      npm versions (lockfile), no `github.event.*` interpolation in
      `run:`
- [ ] 5.3 Document job runtime (< 1 min, npm cache enabled)

## 6. Verification & Wrap-up

- [ ] 6.1 `openspec validate add-dtcg-design-tokens` — change valid
- [ ] 6.2 End-to-end proof: change a token value → build → theme
      renders the new value (widget test or manual run with
      screenshot); revert afterwards
- [ ] 6.3 Docs: README in `design/tokens/` referencing
      `establish-design-doc-workflow` (glossary/vocabulary) and vice
      versa
