<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# 761 — Tasks

## 1. The card: hero + identity + grouped details

- [x] 1.1 `lib/features/ai_import/import_jobs/job_cost_card.dart`: extract the
      private `_JobCostCard` of `job_status_screen.dart` into a public
      `AiJobCostCard` (`ConsumerWidget`) built from `Card` +
      `AppSpacing` tokens (`surfaceContainerHighest`, `space16` padding), and
      switch the screen to it — no duplicate implementation.
- [x] 1.2 Pure `aiCostHero(l10n, cost, preference)` → `AiCostHero` (label,
      value, optional note, `isUnknown`): money arm = `cost.total` when
      `known`, else the extraction token cost; energy arm =
      `energyCost.effectiveCappedNano`; `unknown` (or a `known` snapshot
      without currency) = the localized unknown as the hero VALUE; no priced
      component at all = the honest unknown.
- [x] 1.3 Hero widget: `labelLarge` visible label + `headlineMedium` bold
      value (`ai-job-cost-hero`, `-hero-label`, `-hero-value`;
      `ai-job-cost-unknown` keeps the #675 key on the unknown arm).
- [x] 1.4 Identity chips (model + provider) in a `Wrap`: labelled, two lines,
      ellipsized, full value in a tooltip, `maxWidth` capped so the compact
      layout wraps instead of overflowing.
- [x] 1.5 Detail rows as ONE icon + `bodySmall` primitive (`_CostLine`), in
      reading order: usage → token cost → energy (consumption, cost, capped
      flag) → rates → image → Decision component → `price_as_of` → the #767
      Decision-Model outcome. The preference-selected component row stays
      bold.

## 2. The #768 split and the explicit total

- [x] 2.1 `incomplete` / `mixed_currency` totals render the priced component
      PLUS a note stating why no sum exists (`ai-job-cost-total-note`);
      `unknown` and an absent `total` render no note.
- [x] 2.2 The Decision component group: own `provider / model`
      (`ai-job-cost-decision-identity`), own usage counts, own
      `token_cost_nano` / `energy_cost_nano` in the component's own currency;
      an unpriced component (`status != known` or no currency) keeps its counts
      and renders `aiJobCostDecisionUnpriced` — never `0`, never the extraction
      rate.
- [x] 2.3 The image component renders its own row (`ai-job-cost-image-total`),
      because `cost.total` includes it and a rendered total must stay
      explainable.
- [x] 2.4 Integer nano-currency math only (`formatNanoCurrency`,
      `formatMillijoulesAsWh`); no floats, no live rate lookup.

## 3. The compact jobs list

- [x] 3.1 `aiJobCostMetricIcon(cost, preference)` — pure, ONE resolution for
      both surfaces: token → `payments_outlined`, energy (and an energy
      component) → `bolt_outlined`, `unknown` → `help_outline`,
      `not_applicable` → `money_off_outlined`.
- [x] 3.2 `jobs_screen.dart`: the cost line renders as icon + text (key and
      copy unchanged), so the visible "Cost: …" text still carries the
      meaning. No extra request; a cached row (`cost: null`) renders no line.

## 4. Copy, icons, docs

- [x] 4.1 `app_de.arb` + `app_en.arb`: hero labels, chip labels, the two
      refused-total notes, the Decision component copy (title / token cost /
      energy cost / unpriced) and the image row; `aiJobCostModel` (the old
      "Modell: {model}" one-liner) removed because the chip renders label and
      value separately. Catalogs stay key-identical; `flutter gen-l10n` run.
- [x] 4.2 `lib/design/material_icons.dart`: the cost-card glyph vocabulary in
      one place (title, money, energy, usage in/out, cached, model, provider,
      rate, price date, Decision, image, note, unknown, nothing-billed).
- [x] 4.3 `docs/design/glossary.md`: one row per glyph group with the visible
      label, the context and the copy keys — icons reinforce only.
- [x] 4.4 `docs/design/screens/ai-import-jobs.md`: a "Job status — the cost
      card" section with a Salt wireframe, the compact-layout rule and the
      element/semantics/copy-key table (`scripts/check-design-diagrams.sh`
      passes).

## 5. Tests

- [x] 5.1 Tier-1 `job_cost_card_test.dart`: every arm of `aiCostHero`
      (total / component / energy preference / no energy / pre-#768 absence /
      `incomplete` / `mixed_currency` / `unknown` / no currency / energy-only /
      no priced component / de + en labels) and every arm of
      `aiJobCostMetricIcon`.
- [x] 5.2 Tier-2 `job_status_screen_test.dart` (rewritten cost group): the
      known hero + chips + all detail rows, the energy preference swapping the
      hero AND the emphasised row, a refused total with its reason, a
      mixed-currency refusal, a pre-#768 snapshot claiming no total, the priced
      and unpriced Decision component, the image row, the capped flag, the
      unknown arm (no `0`), `not_applicable`, a long model id at 360 dp
      (no overflow, two lines, tooltip), the terminal SSE frame, and the
      no-snapshot arm.
- [x] 5.3 Tier-2 `jobs_screen_test.dart`: the compact line's glyph follows the
      preference (`token` / `energy` / `unknown`) and renders no glyph for the
      nothing-billed row.
- [x] 5.4 Goldens regenerated: `ai_job_status_cost_{light,dark}_{android,macos}`
      and `ai_jobs_cost_{light,dark}_{android,macos}`.

## 6. Verification

- [x] 6.1 `dart format --set-exit-if-changed .`
- [x] 6.2 `flutter analyze`
- [x] 6.3 `flutter test` (full suite)
- [x] 6.4 `python3 tool/check_glossary_catalog.py`
- [x] 6.5 `scripts/check-design-diagrams.sh`
- [x] 6.6 CHANGELOG entry + `pubspec.yaml` version bump (ADR-033: the client
      build changes).
