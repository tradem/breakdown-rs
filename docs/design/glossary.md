<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: omen-alpha (opencode-go) -->

# Icon & Terminology Glossary

The single source of truth for **Material Symbols icons → user-facing
German labels → usage context → copy key** in the breakdown-rs
frontends. Screen specs (`docs/design/screens/`) MUST source their UI
copy keys and icon choices from this glossary; new screens record new
entries here in the same change.

Derived from the UI/UX research report §4.5
(`docs/design/ui-ux-redesign-research-report.md`) and audited against
the icons actually in use under `frontend-flutter/lib/features/**`
(audit noted per row; documentation only — no code changes in the
establishing change).

---

## Normative rule: visible labels

> **Every navigation destination and every primary action MUST render a
> visible text label.** Icons are reinforcement — they MAY accompany a
> label but SHALL NOT be the sole carrier of meaning. An icon whose
> meaning is only available as a tooltip or content description does
> not satisfy this rule.
>
> Rationale: the research report's core finding was information design,
> not visual polish. Icon-only navigation (the current Seasons-tile
> `checkroom`/`person`/`style` trio and the icon-only FAB) forces
> trial-and-error. Material guidelines likewise recommend labels on
> navigation bars as mandatory.
>
> Process rule: when a change adds a new screen action or navigation
> destination, its visible label, icon, and context are recorded in
> this glossary **and** the UI renders the label visibly — before the
> change's review can pass.

---

## Glossary table

| Material Symbols icon | Visible label (German UI copy) | Context / screen | Copy key |
|---|---|---|---|
| `home_outlined` | **Season** | Navigation shell destination 1 of 4 — home: seasons overview (team decision 2: term „Season" retained) | `nav.seasons` |
| `edit_calendar_outlined` | **Planen** | Navigation shell destination 2 of 4 — hierarchy Season→Block→Episode→Scene | `nav.planen` |
| `checkroom` | **Kleidung** | Navigation shell destination 3 of 4 — costume domains (Kostüme, Figuren) scoped to the active season; costume rows | `nav.costumes` |
| `person_outline` | **Figuren** | Bottom-nav destination „Figuren"; character rows (branch term for Kostüm/Film — not „Rollen") | `nav.characters` |
| `smart_toy_outlined` | **Import** | AppBar/menu entry → AI schedule import (verb > object: "what can I do here?") | `nav.aiImport` |
| `add` (FAB) | **Season erstellen** | Seasons extended FAB label — icon-only FABs are the weakest form for rare, high-priority actions | `seasons.create` |
| `—` *(no icon)* | **{n} Blöcke** | Season card metadata — cached block count (omitted when no cache entry) | `seasons.meta.blocks` |
| `—` *(no icon)* | **{n} Szenen** | Season card metadata — cached scene count (omitted when no cache entry) | `seasons.meta.scenes` |
| `—` *(no icon)* | **{n} Kostüme** | Season card metadata — cached costume count (omitted when no cache entry) | `seasons.meta.costumes` |
| `—` *(no icon)* | **Noch keine Seasons** | Seasons home empty-state headline | `seasons.empty.title` |
| `—` *(no icon)* | **Lege deine erste Season an — oder importiere einen bestehenden Spielplan per KI.** | Seasons home empty-state guidance sentence | `seasons.empty.guidance` |
| `rocket_launch_outlined` | **Season-Setup starten** | Seasons home empty-state setup CTA (create flow; later the setup wizard change's entry route) | `seasons.empty.setupCta` |
| `smart_toy_outlined` | **KI-Import öffnen** | Seasons home empty-state import CTA — jumps to the Mehr tab's labeled Import entry | `seasons.empty.importCta` |
| `add` (FAB) | **Block hinzufügen** | Blocks FAB (same icon, per-screen label) | `blocks.create` |
| `cloud_off` | **Verbindung gestört** | Stale/optimistic overlay banner when sync hangs | `errors.connectionLost` |
| `style_outlined` | **Kategorien** | Season tile → costume categories. Redesign note (report §4.5): not a daily entry point — relocates into „Mehr"/season detail; then icon-only entry is removed | `nav.costumeCategories` |
| `calendar_month_outlined` | **Drehtage** | Shooting-day navigation from episodes/scene planning | `nav.shootingDays` |
| `movie_creation_outlined` | **Episoden** | Drill-down label for episodes within blocks | `nav.episodes` |
| `view_agenda_outlined` | **Szenen** | Drill-down label for scenes within episodes | `nav.scenes` |
| `photo_camera` | **Foto aufnehmen** | Continuity photo capture (costume detail, continuity strip) — camera permission requested at point of use with rationale | `photos.capture` |
| `photo_library` | **Fotogalerie** | Photo gallery entry from costume detail / continuity strip | `photos.gallery` |
| `photo_library_outlined` | **Keine Fotos** | Empty state of the photo gallery | `photos.empty` |
| `summarize_outlined` | **Berichte** | Scene-shoot reports entry (Soll/Ist) | `reports.open` |
| `event_busy` | **Termin entfernen** | Scene detail — remove shooting-day assignment | `scenes.unschedule` |
| `unfold_more` | **Alle Szenen anzeigen** | Scene-shoots list — expand collapsed sections | `sceneShoots.expand` |
| `more_horiz` | **Mehr** | Navigation shell destination 4 of 4 — Import, Kategorien, Über die App, Einstellungen, Abmelden (Berichte bleiben im Day-Board verankert) | `nav.more` |
| `more_vert` | **Mehr** | Overflow menu (seasons, shooting days) | `common.overflow` |
| `settings_outlined` | **Einstellungen** | Seasons overflow → settings dialog; AI-import config | `common.settings` |
| `logout` | **Abmelden** | Seasons overflow → sign out | `common.signOut` |
| `account_circle` | **Profil** | Seasons overflow → account/membership entry | `common.profile` |
| `info_outline` | **Über die App** | Seasons overflow → app info | `common.about` |
| `edit` | **Bearbeiten** | Edit actions (costume categories, scene shoots) | `common.edit` |
| `delete` | **Löschen** | Destructive actions (scene shoots) — always with confirm dialog | `common.delete` |
| `archive_outlined` | **Archivieren** | Archive costume category | `categories.archive` |
| `person_remove_outlined` | **Figur entfernen** | Unassign character from costume / scene | `characters.remove` |
| `construction` | **In Arbeit** | Login screen — feature-not-yet-available notice | `auth.wip` |
| `search_off` | **Keine Treffer** | Empty search/filter results (blocks, categories, episodes) | `common.noResults` |
| `auto_awesome` | **Demo-Daten** | Seasons overflow → demo/seed data action (dev aid) | `common.demoData` |
| `open_in_new` | **Externe Quelle öffnen** | App info — external link | `common.externalLink` |
| `balance` | **Lizenz** | App info — license entry (AGPL-3.0) | `common.license` |
| `tag` | **Version** | App info — version entry | `common.version` |
| `dns_outlined` | **Serveradresse** | Settings — backend endpoint display | `settings.serverUrl` |
| `science_outlined` | **Experimentelle Funktionen** | Settings — experimental features | `settings.experimental` |
| `psychology_alt_outlined` | **KI-Konfiguration** | AI provider/model configuration | `ai.config` |
| `smart_toy_outlined` *(info)* | **KI-Assistent** | App info — AI attribution entry | `common.aiInfo` |
| `quickcheck.title` *(template example)* | **Schnell-Check** | Screen-spec template example screen (fictional `CostumeQuickCheck`) | `quickcheck.title` |
| `quickcheck.empty` *(template example)* | **Keine Figuren in dieser Szene** | Template example screen — empty state | `quickcheck.empty` |

### Status & result icons (no user-facing label required)

These are passive status/feedback glyphs — they are never the sole
carrier of a user action's meaning, so the visible-label rule does not
apply to them. Their meaning is conveyed by the message text they
accompany.

| Material Symbols icon | Context | Copy key (accompanying text) |
|---|---|---|
| `cloud_off` (stale variant) | Stale banner icon | `errors.connectionLost` |
| `history` | Season-card metadata stale indicator (accompanies "Stand: vor 2 h") | `seasons.stale` |
| `error_outline` | Error banners / photo errors | `errors.*` |
| `warning_amber_outlined` | AI-apply review warnings | `ai.review.warning` |
| `check` / `check_circle_outline` | Selection avatar, job success | context-specific |
| `broken_image` | Photo load failure fallback | `photos.loadError` |
| `link_off` | Continuity strip — photo binding lost | `photos.bindingLost` |
| `chevron_right` | List-item drill-down affordance | n/a (paired with visible title) |
| `close` | Dismiss action in snackbars/dialogs | paired with visible snackbar text |

### Audit gaps (documentation only — fixed by the redesign changes)

- `checkroom_outlined` (seasons tile) and `checkroom` (costume rows) are
  the same concept with two variants — the app-shell redesign
  (`redesign-app-shell-navigation`) unifies on `checkroom` with the
  visible label „Kleidung".
- `style_outlined` on the Seasons tile violates the visible-label rule
  today (icon-only entry); per report §4.5 it is *removed as an entry
  point* in the redesign and relocated under „Mehr"/season detail.
- The Seasons FAB is icon-only today; `redesign-seasons-home` replaces
  it with an extended FAB labeled **Season erstellen**.
- The AI-import AppBar icon is tooltip-only today; the redesign moves it
  to a labeled menu entry **Import**.

## Design tokens (values vs. vocabulary)

Theme-relevant **token names** referenced by screen specs (spacing keys,
semantic color roles, type-scale names) resolve against the W3C-DTCG token
source at `design/tokens/` (monorepo root) — see its README and the
`design-tokens-dtcg` skill. The glossary governs *vocabulary* (icons,
German copy keys); the token source governs *values* (`color`,
`dimension`) and their generated Flutter artifact
(`frontend-flutter/lib/design/gen/design_tokens.g.dart`, rebuild-only via
`bash scripts/build-tokens.sh`).
