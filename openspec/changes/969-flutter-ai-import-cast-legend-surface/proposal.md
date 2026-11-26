<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# 969 — Surface the cast legend, role-modifier badges and shot suffixes in the schedule review

## Why

Issue #960 (`[P4]`, ADR-041) made the multimodal schedule extractor deliver
additive preview metadata, and #968 added the EU/ZDR vision providers. The
regenerated Dart client (`vendor/breakdown_api`, **1.11.0**) already carries
every field — but no screen read them:

- `ShootingSchedule.castLegend` (`ROLLEN` legend: code → character name + role
  modifier) was invisible, so a reviewer could not tell whether a row's cast
  codes resolved or were silently dropped server-side (ADR-041 `D6`).
- `ShootingScheduleRow.shotSuffix` (`300.37N`) merges onto Scene 37 with no
  phantom scene, so the second row looked like a duplicate rather than a
  pick-up/insert shot.
- `ShootingScheduleRow.castRefs` (per-row resolved cast incl. `Dummy` /
  `Nur Stimme` / `(OT)`) was never shown, so the legend could not be checked
  against the rows.
- The three #968 providers (`scaleway`/`ovhcloud`/`nebius`) exist in the client
  enum; the AI-config screen needed verification as first-class options, and a
  curated-model VISION signal does not exist on the wire at all.

The boundary is unchanged: the Flutter app never talks to a VLM. This change is
review-side surfacing plus verification, not a new pipeline.

## Discovery evidence

- Index: project `breakdown-rs` (monorepo root); `scripts/check-graph-freshness.sh`
  → **FRESH** at `793320b` (2026-11-26T05:45:50Z).
- Graph (meaning): `search_code("AiPreviewPayloadOneOf1|AiPreviewPayloadOneOf2|ShootingScheduleRow|ScheduleRoleModifier|castLegend|castRefs|shotSuffix", regex=true)`
  → 92 results / 234 raw matches, **all backend** (`backend/crates/core/src/ai/preview.rs`,
  `infra/src/ai/{client,csv_schedule,decision_scoring,workers}.rs`) plus one
  Dart hit (`preview_screen.dart:1556`, `_PreviewTargetActionsState._scheduleAutoAdopt`)
  reached through the `ShootingSchedule` term. The generated DTOs live in
  `frontend-flutter/vendor/breakdown_api/**`, which the indexer prunes **by
  design** — read directly, never a graph claim.
- `get_file_outline(preview_screen.dart)` → the widget graph the change rides
  (`_TypedPreviewBodyState._payloadRows`, `_PreviewRowCard`, `_InfoRowCard`).
- `rg` (correct tool here, pure text): `castLegend|shotSuffix|castRefs|ScheduleRoleModifier`
  in `vendor/breakdown_api/lib` → `shooting_schedule.dart`, `shooting_schedule_row.dart`,
  `schedule_legend_entry.dart`, `schedule_cast_member.dart`, `schedule_role_modifier.dart`;
  `scaleway|ovhcloud|nebius` → `llm_provider.dart` (and `backend/openapi.yaml:3448-3450`).
  ARB keys and the `_providerWireKey` comment in `ai_config_screen.dart` are text, not symbols.
- Coverage: `check_index_coverage(paths=[preview_screen.dart, apply_screen.dart,
  ai_config_screen.dart, ai_config_controller.dart, ai_config_reachability.dart,
  preview_apply_test.dart, ai_config_screen_test.dart, app_de.arb, app_en.arb])`
  → `no_recorded_issue` for all nine; the two ARB files are `not_tracked` (the
  graph indexes symbols, not literals) and the code paths read
  `metadata_changed` because this change edited them. No negative claim in this
  proposal rests on the graph alone: "no other surface reads these fields" was
  verified with `rg`, which is the correct tool for a literal question.
- Not the graph (and why): `backend/openapi.yaml` (spec text),
  `docs/design/screens/ai-import-jobs.md` (prose) and `lib/l10n/*.arb` (literal
  keys) are read with `read`/`rg`.

## What changes

1. **Schedule preview — collapsible `ROLLEN` legend**
   (`preview_screen.dart`, schedule variant, directly under the payload header):
   `Card` + `ExpansionTile`, collapsed by default (a page carries ~35 entries),
   title = ICU-plural entry count, entries sorted **numerically** and rendered as
   tabular-figure code + character name + role-modifier badge. An absent/empty
   map renders **nothing** (no placeholder, no "no legend" sentence) — a
   pre-`[P4]` stored preview stays byte-identical.
2. **Role-modifier badges + cast pills + shot-suffix chip**: one badge per
   `ScheduleRoleModifier` (`secondaryContainer`/`tertiaryContainer`/
   `primaryContainer`, AA in both themes), reused in the legend and on the rows;
   one pill per resolved `ScheduleCastMember`; an outlined chip for
   `shotSuffix`. The chips render on **pre-merge schedule rows** (so the legend
   is verifiable where it is stated) and on **merged review rows** (one `Wrap`
   line per schedule row: verbatim `rowRef` + suffix chip + cast pills), which
   makes the Scene-37 `300.37` / `300.37N` double row self-explanatory.
   Unresolved codes render no chip — never an "unknown cast" warning.
3. **AI config — the #968 EU vision providers verified, not re-implemented.**
   The picker, reachability probe, per-provider health and credential entry are
   catalog/wire-key driven, so `scaleway`/`ovhcloud`/`nebius` are first-class
   automatically. Pinned by two widget tests (wire-key health probe per provider;
   picker lists all three from the catalogue). The curated-model dropdown is
   left untouched: `ModelInfo` carries no vision flag, so inventing one
   client-side is out.
4. **l10n**: seven new keys in `app_de.arb` + `app_en.arb` (`aiPreviewCastLegend*`,
   `aiPreviewRoleModifier*`, `aiPreviewShotSuffixSemantics`), ICU plural for the
   legend count, no hardcoded copy in widgets.

## Decisions

- **D1 — Legend under the payload header, not above the rows.** It is payload
  metadata; collapsed it costs one line and never sits between the reviewer and
  the dispatch button.
- **D2 — Chips on the pre-merge rows too.** The issue's stated purpose ("a wrong
  legend is caught before apply") is only verifiable if the rows show what they
  resolved; the legend alone cannot answer it. Same widgets, same copy.
- **D3 — No vision-capability signal invented.** `ModelInfo` has
  `id`/`display_name`/`pricing`/`recommended`/`supported_reasoning_efforts`; no
  vision flag exists. The gap is recorded on #968; the client does not guess.
  (§3 of the issue explicitly allows this branch.)
- **D4 — Chips/badges are inert.** Apply treats `300.37` and `300.37N`
  identically; no decision, no filter, no new apply field.
- **D5 — Four new goldens** (legend expanded, merged suffix, light + dark
  Android) because the badge colour roles are the review artefact; the existing
  schedule/merged goldens stay untouched (their fixtures carry no new fields,
  which is itself the regression proof).

## Affected packages / artifacts

| Package / Artifact | Action | Reason |
|---|---|---|
| `frontend-flutter` (`pubspec.yaml`) | **none** — no bump, no dependency | UI-only change; version bumps are release-time |
| `breakdown_api` (`vendor/breakdown_api/`) | **none** — read-only consumer | fields already shipped by the 1.11.0 regen (issues #960/#968) |
| `*.g.dart` / `*.freezed.dart` | **none** | no new provider/annotation |
| `lib/l10n/generated/**` | regenerated | 7 new ARB keys (`flutter gen-l10n`) |
| `design/tokens/**` + `lib/design/gen/**` | **none** (verified byte-identical) | only existing `AppSpacing` tokens used |
| `test/features/ai_import/goldens/*.png` | 4 added | legend + merged suffix, light + dark |

## Verification

- Widget tests (5): absent legend renders nothing; collapsed legend + numeric
  order + modifier vocabulary on expand; empty legend renders nothing; pre-merge
  rows show resolved cast + suffix and no chip for an unresolved row; merged
  Scene-37 double row with per-row cast, one suffix chip and both accessible
  names.
- Widget tests (4, AI config): health probe asks the wire key for each of
  `scaleway`/`ovhcloud`/`nebius`; the create-flow picker lists all three.
- Goldens: `ai_preview_cast_legend_{light,dark}_android.png`,
  `ai_preview_merged_cast_{light,dark}_android.png`.
- `flutter analyze` clean; `dart format --set-exit-if-changed .` clean;
  `flutter test test/features/ai_import/` → 718 passed;
  `tool/breakdown_lints_runner` → no violations; `scripts/build-tokens.sh` →
  no diff; `tool/check_inline_copy.sh` → clean; de/en ARB parity + gen-l10n
  drift → clean.
