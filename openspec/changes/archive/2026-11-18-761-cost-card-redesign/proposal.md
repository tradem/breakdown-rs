<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# 761 — The import cost card shows the money and the model, not a wall of numbers

## Why

Issue #761: the cost card of the job-status screen (`_JobCostCard` in
`frontend-flutter/lib/features/ai_import/import_jobs/job_status_screen.dart`)
was a flat column of equally weighted `bodySmall` lines. The two facts an
operator actually wants — **what the import cost** and **which model produced
it** — were buried between token counts, snapshot rates, energy figures and a
price date, and the provider was not rendered at all even though
`JobTelemetrySummary.provider` has been on the wire since #609.

Verified in the tree before the change:

- every row was `bodySmall` except a bold header; the only emphasis was a
  conditional `fontWeight.bold` on the token or energy total;
- `telemetry.provider` was never read by any Flutter widget;
- there were no icons, no grouping and no separation between "headline number"
  and "explanation";
- the wire already carried the #768 additions (`cost.total` with an explicit
  `CostTotalStatus`, and `cost.decision` with its own provider/model, usage and
  rate card) and **nothing** in `frontend-flutter/lib/` rendered either of
  them, so a job that used a Decision Model showed only part of what it cost.

The issue roadmap bundles the two
(`ISSUE-ROADMAP-2026-10-29-ai-import.md`: "#761 Kostenkarte-Redesign — Reine
Darstellung auf Basis von #768", acceptance "Hauptkosten + Modell, Split
Extraktion/Decision"), so this change does the presentation AND the #768
rendering in one PR instead of building the layout twice.

## What changes

1. **Extraction + hero.** `_JobCostCard` becomes a public, testable
   `AiJobCostCard` (`job_cost_card.dart`) built from a `Card` +
   `AppSpacing` tokens. The hero is a large, explicitly labelled figure: the
   money the user pays — `cost.total` when the snapshot publishes one, the
   extraction token cost otherwise — or, under
   `cost_display_preference = energy`, the energy figure
   (`effective_capped_nano`, the capped value). The decision is a pure function
   (`aiCostHero`) so the honesty matrix is unit-testable without widgets.

2. **Identity.** The model and the provider render as two labelled chips in a
   `Wrap` (`smart_toy_outlined` / `cloud_outlined`), two lines maximum,
   ellipsized, full value in a tooltip — the "wesentliches Modell" the issue
   asks for, and the first surface that renders the provider.

3. **Honest totals (#768).** `cost.total.status` `incomplete` /
   `mixed_currency` renders the priced component plus a note stating why no sum
   exists (no rate substitution, no conversion — design D2). `unknown` and an
   absent total (every pre-#768 row) render no note: an absence is not an
   error. `cost.status == unknown` keeps the localized "Unbekannt" as the HERO
   VALUE, never a fabricated `0`.

4. **The Decision component (#768).** When `cost.decision` is present, its own
   `provider / model`, its own usage counts and its own priced figures render as
   a subordinate group. An unpriced component keeps its usage counts and says
   "nicht bepreist" — it never borrows the extraction rate and never renders
   `0`.

5. **Nothing is dropped.** Token counts, cached count, snapshot rates,
   energy consumption, the energy-cap flag, the image component, `price_as_of`
   and the #767 Decision-Model outcome all keep rendering — now grouped,
   icon-prefixed and visually subordinate.

6. **The compact jobs list agrees with the card.** The one-line
   `aiJobCostCompactCopy` keeps its text and its zero-extra-request behaviour,
   and gains only the metric glyph of the same preference
   (`aiJobCostMetricIcon`), so list and detail cannot claim different primary
   metrics. A cached row carries `cost: null`, so the line (and its glyph) stays
   absent until the authoritative read.

## Out of scope / deliberate decisions

- **No inline token/energy toggle.** The preference is a settings value
  (`aiCostDisplayPreferenceProvider` is read-only); a switch on this screen
  would need a write path and a settings round trip for a purely presentational
  choice. The card follows the preference and the detail rows keep the selected
  figure emphasised.
- **No per-component currency conversion.** `mixed_currency` renders the
  refusal, not a made-up rate (design D2).
- **No new request.** The card renders `job.cost`, `job.telemetry` and
  `job.decision_telemetry` — the fields the job already carries — so the single
  SSE consumer stays the job-status controller (battery contract D5).
- **No wire change.** `backend/openapi.yaml` is untouched; the client renders
  fields that #768 already shipped.

## Impact

Client only: `frontend-flutter/lib/features/ai_import/import_jobs/job_cost_card.dart`
(new), `job_status_screen.dart` (the card is extracted, not duplicated),
`jobs_screen.dart` (metric glyph), `lib/design/material_icons.dart` (the shared
icon vocabulary), both ARB catalogs, the goldens of both screens,
`docs/design/glossary.md` and `docs/design/screens/ai-import-jobs.md`.
