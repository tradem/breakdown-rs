<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# 825 — The Season scope pill always shows the season number

## Why

The Season scope pill in the shell's top bar dropped the season **number**
whenever the season carried a title: it rendered `Season: Dreharbeiten 2026`,
so the season's position in the hierarchy was invisible — while the Episode
pill right next to it always leads with its number (issue #709). The
composition `season.title ?? l10n.seasonsDefaultTitle(season.number)` wrapped
in `l10n.scopeChipSeason` produced three distinct defects:

| Case | Rendered pill (before) | Defect |
|---|---|---|
| Season 1, title „Dreharbeiten 2026" | `Season: Dreharbeiten 2026` | number lost |
| Season 1, title `null` | `Season: Season 1` | term doubled |
| Season 1, title `""` | `Season: ` | nothing at all |

The empty-string arm is not hypothetical: the title arrives off the wire as
`String?`, so `''` is a legal value that defeats a `??` fallback. The live dev
season is exactly `number = 1, title = ''`.

`docs/design/screens/navigation-shell.md` already drew the bar as
`"Season: {n}"` — the implementation deviated from its own screen spec as soon
as a title existed. There was no season counterpart of `episodeNumberName`,
which is why the season side never had a number-plus-name form.

## Decision

Mirror the episode pill exactly, with one new ARB key and one shared helper.

- **D1 — the number always leads.** Named season → `seasonNumberName`
  (`{number} · {name}`), i.e. „1 · Dreharbeiten 2026". Unnamed season →
  `seasonsDefaultTitle` (`Season {number}`), i.e. „Season 1".
- **D2 — retire the `Season: ` wrapper.** `scopeChipSeason` is removed from
  both catalogs (it had exactly one call site). The pill must not read
  „Season: 1 · Dreharbeiten 2026" next to an episode pill that reads
  „3 · Impuls".
- **D3 — blank counts as unnamed.** `title.trim().isEmpty` takes the
  number-only arm, so a `null`, `''` or whitespace-only title all render
  „Season 1" — never a bare prefix and never an empty pill. (Normalizing an
  empty title to `null` at the backend projection boundary is a separate
  backend concern and is not required for the client to be correct.)
- **D4 — German keeps „Season" on the shell surface.** The catalog is mixed
  (`blockSeasonNumber` = „Staffel {number}", the shell surface says „Season"),
  but this change touches the shell surface only, so it stays with „Season"
  and introduces no fifth wording. App-wide terminology unification is
  recorded as a known drift in `docs/design/glossary.md`, not silently picked
  here.
- **D5 — one shared composition.** `seasonDisplayLabel(l10n, number:, title:)`
  in `lib/features/seasons/season_display_label.dart` is the single rule. The
  pill and the season picker rows one tap away both use it, so they can never
  disagree. The remaining `title ?? seasonsDefaultTitle(number)` sites
  (production overview, location strip, seasons cards, blocks AppBar, fundus,
  piece detail) converge on the helper later without drift — explicitly out of
  scope here.

## Alternatives rejected

- **Keep the `Season: ` prefix and only insert the number** („Season: 1 ·
  Name"): leaves the two adjacent pills with two different shapes.
- **Reuse `episodeNumberName` for seasons**: the string is identical today,
  but the key would claim an episode semantic; a later episode-copy change
  would silently move the season label.
- **Flip the German wording to „Staffel" in the pill**: the pill would then say
  „Staffel 1" inside a bar that says „Season wählen" — a fourth variant on the
  same row, in a change that is about removing one.

## Impact

- `lib/features/shell/season_scope_chip.dart` — pill label + picker rows.
- `lib/l10n/app_de.arb`, `lib/l10n/app_en.arb` — new `seasonNumberName`,
  removed `scopeChipSeason`; `lib/l10n/generated/` regenerated.
- `test/features/shell/scope_pill_test.dart`, `three_views_test.dart` — the
  two assertions that pinned the defect, plus the three label cases and the
  picker-row agreement.
- The three `scope pill` goldens are re-baselined: their setup called
  `setActiveSeason` **before** the first pump, which the controller's restored
  state discarded, so the „all levels selected" images had been capturing the
  neutral pill all along. They now pin the selected labels.
- `docs/design/screens/navigation-shell.md` (wireframe + components table) and
  `docs/design/glossary.md` (ARB inventory, new row, terminology-drift note).
