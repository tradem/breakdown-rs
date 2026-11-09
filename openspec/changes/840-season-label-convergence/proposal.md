<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# 840 — Every season label comes from one rule, and the level has one German word

## Why

Issue #825 fixed the Season scope pill and the picker rows it opens and
introduced `seasonDisplayLabel(l10n, number:, title:)` as the single
composition rule (number always leads; a `null`/`''`/whitespace title takes
the number-only arm). It deliberately left two follow-ups open, both taken
here.

**1. The same composition is still inlined at ten further sites**, each with
the pre-#825 `title ?? <number-only key>` shape that a blank title defeats:

| Surface | Site | Old expression |
|---|---|---|
| Production overview | `shell/production_overview_screen.dart` | `title ?? seasonsDefaultTitle(number)` |
| Location strip | `shell/location_strip.dart` (`L10nPlanningLocationCopy.seasonLabel`) | `title ?? seasonsDefaultTitle('$number')` |
| Seasons cards | `seasons/seasons_screen.dart` (projected + overlay arms) | `title ?? seasonsDefaultTitle(number)` / `name.isNotEmpty ? name : seasonsDefaultTitle(number ?? '')` |
| Seasons list (cache view) | `seasons/seasons_view_widget.dart` | `title ?? wizardReviewSeason('$number')` |
| Blocks AppBar + reports entry | `blocks/blocks_screen.dart` | `title ?? blockSeasonNumber('$number')` |
| Fundus chips + repertoire rows | `fundus/fundus_screen.dart` | `title ?? seasonsDefaultTitle(number)` |
| Piece detail repertoire | `pieces/piece_detail_screen.dart` (rows + picker) | `title ?? seasonsDefaultTitle(number)` |

A season titled `''` — the live dev season is exactly `number = 1, title = ''`
— renders an empty label on each of them. That is the defect #825 removed from
the pill, still present one tap away.

**2. German used two words for the level.** `blockSeasonNumber` said
„Staffel {number}" (blocks AppBar, hierarchy prose „Zurück zu den Staffeln",
„Kostüm-Rolle in dieser Staffel") while the shell surface said „Season"
(`seasonsDefaultTitle`, `scopeChipSeasonUnset`, „Season-Setup"). #825 recorded
the drift in `docs/design/glossary.md` instead of silently picking a side.

## Decision

**D1 — one composition, everywhere.** Every surface that renders a season
label calls `seasonDisplayLabel`. No call site derives the fallback itself.
This also imports #825's number-first rule into those surfaces: a titled
season reads „1 · Dreharbeiten 2026" on the cards, the AppBar, the chips and
the repertoire rows, exactly as the pill already did. The overlay arm of the
seasons cards keeps an explicit `number == null` branch (the overlay's number
is display-only; every creation path sets it, and a missing one renders the
name alone rather than the blank „Season " the old `?? ''` produced).

**D2 — the level is called „Season".** `Staffel` is retired from the German
catalog. The English catalog already said `Season` everywhere and is unchanged,
so de/en parity is preserved by construction. Rationale: „Season" is what the
shell — the surface a season is picked and managed on — already used, it maps
one-to-one onto the English catalog, and the key/type names
(`seasonsDefaultTitle`, `SeasonView`, `scopeChipSeason*`) never had a
`Staffel` spelling. The anglicism is accepted as the price of one word.

**D3 — the catalog, not just the label keys.** The unification covers all 40
German values that named the level, not only the visible label keys: hierarchy
prose („Zurück zu den Seasons", „Keine Rolle in dieser Season"), repertoire copy
(„Zu Season hinzufügen"), AI-import copy („Wähle zuerst eine Season aus") and
error copy. A value that still says „Staffel" is a regression.

**D4 — the decision is recorded where the drift was.** The glossary's
„Known terminology drift" section becomes the decision record (word, rationale,
the single composition rule, both-catalog parity), and the two glossary rows
that quoted „Staffel" copy are corrected.

## Consequences

- 26 goldens re-baselined (blocks, seasons, shell, fundus, AI-import target
  card). Issue #839 untracked the stale `failures/` artifacts first, so this
  re-baseline is a reviewable 26-PNG diff.
- Widget assertions that expected a bare title (`'Spring'`, `'Sommerkomödie'`,
  `'Season Two'`) now expect the composed label (`'1 · Spring'`,
  `'1 · Sommerkomödie'`, `'2 · Season Two'`).
- `blockSeasonNumber` stays in the catalog: the AI-import surfaces render a
  season *number* from a scope the projection may not know, and have no title
  to compose. Its German value is now „Season {number}".

## Non-goals

- No new label for the setup wizard: it composes its own review line from
  `wizardReviewSeason` / `wizardReviewSeasonNamed` (a create-form preview, not
  a projected season) and already says „Season".
- No backend change: normalizing an empty season title at the projection
  boundary remains a server-side concern.
- No renaming of the `blockSeasonNumber` ARB key or the `seasons*` key family —
  the keys never carried the German word.
- No edits to other changes' OpenSpec artifacts: `Staffel` mentions in
  `openspec/changes/**` describe past decisions and stay as written.
