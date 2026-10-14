<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (neuralwatt) -->
<!-- Co-authored-by: glm-5.3-flash (opencode-go) -->

# Settings — Screen Spec

## Purpose & Context
The app's dedicated full-screen settings: general app settings (every
flavor) and, dev-flavor-only, the development backend switch. It
replaces the former `SettingsDialog` (issue #516). Used occasionally by
every user (Easter-eggs preference) and regularly by developers
(backend override).

## Navigation
Pushed from the Mehr tab's labeled tile „Einstellungen" (`mehr-settings`)
via `Navigator.push` + `MaterialPageRoute`. Back: the AppBar back
button (`Navigator.pop`) and system back — the screen never pops the
session. Route parameters: none. AUTHZ-GATE: the screen itself is
post-authentication (Mehr tab lives inside the auth shell); the save /
reset actions issue requests against the configured backend through the
existing `SessionReset` coordinator, which owns the auth fence — no
additional client-side membership gate applies (server-ownership rule).

## Location & Context
N/A — settings are not a planning-hierarchy surface; the screen is
pushed without a `PlanningLocation` argument, so the location strip
stays hidden (graceful-degradation rule).

## Layout

```plantuml
@startsalt
{
  T "Einstellungen"
  --
  {^ "Allgemein"
    --
    "Easter-Eggs"
    { "Karl Klammer" | [x] }
    { "Déjà-vu-Katze" | [x] }
    "Kleine Überraschungen in der App lassen sich ein- und ausschalten."
    --
    "Vorschau"
    {^ [Karl-Klammer-Figur] }
    {^ [Déjà-vu-Katze auf einem Streifzug] }
    "Jedes Ei lässt sich hier in Ruhe ansehen — unabhängig vom Monat."
  }
  --
  {^ "Entwicklung"
    --
    "Serveradresse" | "http://10.0.2.2:3000"
    "Flavor" | "dev"
    "Backend-URI"
    "[https://api.example.com            ]"
    "Speichern" | "Zurücksetzen"
  }
}
@endsalt
```

In the `prod` flavor the „Entwicklung" section is absent; the read-only
rows Serveradresse + Flavor remain, followed by the explanatory prod
note (store compliance).

## Components & Semantics
| Element | M3 component | Semantics | Copy key |
|---|---|---|---|
| App bar title | Top app bar | Screen identity | `settings.title` |
| General section | Section header | Groups always-available settings | `settings.general` |
| Easter-eggs group | Section header | Labels the per-egg switch list | `settings.easterEggs` + `settings.easterEggsSubtitle` |
| Karl Klammer switch | Switch list tile | Per-egg preference (default ON) | `settings.easterEggsKarlKlammer` + `settings.easterEggsKarlKlammerSubtitle` |
| Deja-vu Cat switch | Switch list tile | Per-egg preference (default ON; October-only effect on live surfaces) | `settings.easterEggsDejavuCat` + `settings.easterEggsDejavuCatSubtitle` |
| Gallery preview header | Section header | Labels the replay/preview area (issue #640) | `settings.easterEggsPreview` |
| Gallery preview line | Text | Explains the month-independent preview | `settings.easterEggsPreviewSubtitle` |
| Karl Klammer preview | Preview card | Static figure render of the egg (issue #640) | n/a (graphic, no copy) |
| Deja-vu Cat preview | Preview card | Bounded walker render of the egg — shown only while the egg switch is ON (issue #640) | n/a (graphic, no copy) |
| Development section | Section header | Labels the dev-only area | `settings.dev` |
| Server address row | List item (read-only) | Active effective API base | `settings.serverAddress` |
| Flavor row | List item (read-only) | Active build flavor | `settings.flavor` |
| Backend-URI field | Text field | dev-only editable override with inline validation | `settings.backendUri` |
| Save button | Filled button | Persist → Dio rebuild → invalidate | `settings.save` |
| Reset button | Text button | Remove override, back to default | `settings.reset` |
| Prod note | Text | Explains the absent editor in prod | `settings.prodNote` |

## States
Loading: N/A — the screen reads local state synchronously (the
hydrated per-egg easter-eggs notifiers and the effective base). Data:
rows as above; each gallery preview renders its egg's figure regardless
of month, and only while that egg's switch is ON — a switched-off egg
renders no preview (the switch is the master gate; the gallery
bypasses only the October month gate, never the preference). Error: an Easter-eggs read failure surfaces as a visible
error state on each egg row (fallback default ON); backend-URI save
errors render inline keyed on `code` via the validation copy. Stale:
N/A. Optimistic: each easter-eggs switch flips instantly (local
preference, no projection involved); the matching preview appears /
disappears with the same flip.

## Interactions
- Flipping an Easter-eggs switch persists that egg's value and flips its
global notifier immediately — the matching consumer (Karl Klammer
overlay / splash + empty-state cat) updates live, the other egg is
unaffected; the egg's gallery preview follows the same flip.
- The gallery previews are static/bounded renders of the egg figures,
non-interactive, honoring the system "remove animations" setting —
they are explicit showcase surfaces, not live egg appearances (issue
#640: makes every egg discoverable and testable regardless of month).
- Save (dev): validates inline (`validateApiBase`); on success runs the
  `SessionReset.switchBackend` flow with a linear progress indicator,
  then re-reads the effective base.
- Reset (dev): `SessionReset.resetBackendToDefault`, restores the field
  to the effective base.
- Dismissing the save/reset while a progress run is active: buttons are
  disabled (previous dialog behavior carried over).

## Input & Validation
Backend-URI (dev only): absolute `http`/`https` URI; cleartext `http`
accepted only for emulator/loopback hosts (CWE-319 rule). Validation
errors and save errors surface via the existing `apiBaseValidationCopy`
mapping keyed on `code` — never on `detail` prose.

## Accessibility & i18n
Every destination/action carries a visible label; each switch announces
its state. All copy via glossary keys (`settings.*`); German template +
English catalog. The Easter-eggs switches are standard M3 switches —
screen-reader friendly by construction.

## Tests
- Widget: tile pushes the screen (no dialog); back navigation;
  general section in both flavors; one switch per egg; gallery preview
  per egg (visible when ON, absent when OFF, month-independent);
  dev section dev-only; flipping one egg leaves the other unchanged;
  save/reset/progress flows; per-egg read-failure error subtitle.
- Golden: `settings_dev_{light,dark}` + `settings_prod_{light,dark}`
  (replacing the former dialog goldens) + gallery-preview golden.
- Unit: per-egg store Ok/Err branches, legacy migration, default-ON
  fallback.
