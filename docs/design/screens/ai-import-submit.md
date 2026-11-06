<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# AI-Import-Ziel (ai-import-submit) — Screen Spec

## Purpose & Context

The submission surface of the AI import: pick the document kind, pick the
file, state the AI disclosure and dispatch the upload. Since issue #771 it also
states — and resolves — the **write target**: the season and block the imported
episodes, scenes and shooting days will land in. Before that, the target was
ambient `X-Active-Block` state that the screen never named, so a user who
created a new season to isolate an import round saw the rows land in the
previous season.

## Navigation

Reached from four entries, all pushing with `RouteSettings(name:
'ai-import-submit')`: the season home's empty-state CTA (`SeasonsScreen`), the
season-setup wizard's completion CTA (which passes the CREATED `seasonId`), the
quick-create sheet, and the production overview. Back returns to the caller. The
AUTHZ-GATE runs before any protected call: the season piece-department
capability is resolved client-side and a denial renders the localized 403
narrative with **zero** requests issued.

## Location & Context

The shell's location strip and scope chip own the ambient scope. This screen
adds the *explicit* target surface (below) because the scope pill is not
necessarily on screen on every entry path, and because the wizard's freshly
created season is not yet the ambient scope.

## Layout

```plantuml
@startsalt
{
  "KI-Import"                  [⚙]
  ==
  { [Skript] | Drehplan }
  "Skripte: Wähle eine PDF-Datei."
  [PDF-Datei wählen]   "Keine Datei gewählt"
  --
  {^ "KI-Verarbeitung"
     "Die gewählte Datei wird von einem serverseitigen KI-Modell …"
     "Modell: … / …" }
  {^ "Importziel"
     "Staffel 2 · Block 3"
     "Episoden, Szenen und Drehtage dieses Imports landen in diesem Block."
     [Block wechseln]   [Block anlegen] }
  --
  [Zum Import senden]
}
@endsalt
```

The target card also renders two other static shapes: the **block picker**
(title + one selectable row per block of the target season, plus the create
action) and the **blocked** state (the explanatory line **and** the create
action, submit disabled). Issue #828: every RESOLVED state of the card carries
at least one action, and the switch sheet lists the same rows as the picker.
Expanded (window width class ≥ medium): the same single column, constrained to
a content max-width — the form never splits into panes.

## Components & Semantics

| Element | M3 component | Semantics | Copy key |
|---|---|---|---|
| App bar title | Top app bar | Screen identity | `aiImportTitle` |
| Configure action | Icon button (top app bar) | Opens the AI configuration | `aiImportConfigure` |
| Kind picker | Segmented button | Script vs. schedule; the pending file is cleared on a switch (a carried-over body would upload under the wrong declared content type) | `aiImportScript` / `aiImportSchedule` |
| Kind hint | Body text | Names the accepted file types for the picked kind | `aiImportScriptHint` / `aiImportScheduleHint` |
| File row | Outlined button + text | Picks the document; the displayed name is DERIVED from the pending document's own `fileName` (never remembered locally), so it returns to `Keine Datei gewählt` as soon as the provider is cleared — a kind switch, or a successful submit | `aiImportPickPdf` / `aiImportPickCsvPdf` / `aiImportNoFile` |
| AI disclosure card | Card (tertiary container) + `smart_toy_outlined` icon | EU AI Act Art. 50 point-of-interaction disclosure, **above** the submit action, plus the configured provider/model naming line (degrading honestly when unconfigured) | `aiImportDisclosureTitle` / `aiImportDisclosureBody` |
| Target card | Card (surface container highest) | The write target of this import — the one fact that decides where every imported row lands. Rendered directly above the submit action, beside the disclosure | `aiImportTargetTitle` |
| Target line | Title-medium text | `{season} · {block}` from read DTOs only: the season number is resolved **cache-only** and degrades to `Staffel unbekannt`; the block number comes from the resolved scope and degrades to `Block unbekannt`. Never a fabricated number | `aiImportTargetLine` with `blockSeasonNumber` / `blockTileLabel` / `aiImportTargetUnknownSeason` / `aiImportTargetUnknownBlock` |
| Target hint | Body-small text | States the consequence ("episodes, scenes and shooting days land in this block") so the target is actionable, not decorative | `aiImportTargetHint` |
| Target picker | List items in the target card | Shown when the target season has **several** blocks: exactly one row per block, tapping adopts it as the sticky scope (the header then follows the line). The inline list IS the switch in this state, so the card renders no second switch affordance beside it | `aiImportTargetPickBlock` + `blockTileLabel` |
| Target blocked state | Body text | No block in the season → "create a block first" **plus the create action** (issue #828: the identical state used to be a dead end); no season context → "select a season first". Both disable the submit action | `aiImportTargetNoBlocks` / `aiImportTargetNoSeason` |
| Target switch action | Text button in the target card | **"Block wechseln"** (issue #828), rendered in the resolved state too (before, only the unset-scope picker could switch). Opens a bottom sheet listing the target season's blocks with the current one marked; the pick writes `activeBlockProvider` — the same seam as the inline picker, so the line, the declared season and `X-Active-Block` stay one value | `aiImportTargetSwitchBlock` |
| Target create action | Text button in the target card | **"Block anlegen"** (issue #828), the way out of a season without blocks and a secondary affordance everywhere else. Opens the EXISTING create-block form (never a second form) and adopts the acknowledged block as the target — the form resolves to the created `(id, number)` pair, because the create route answers with an id only | `aiImportTargetCreateBlock` |
| Season-unavailable report | Snackbar | The season row the create form pre-fills from could not be read: reported instead of opening a form with a guessed id | `aiImportTargetSeasonUnavailable` |
| Target retry | Text button | The block-list fetch failed while the target itself could not resolve: retry re-runs the season's block fetch, error copy keyed on the problem `code` | `blocksFetchError` + `commonRetry` |
| Target list-retry | Inline error line + text button | Review of #828: the block-list fetch failed but the sticky scope already matched the season, so the resolution is `ready` and the switch action would silently disappear. The failure is stated with the same code-keyed copy and a retry that re-runs the same season's fetch, so switching stays reachable without leaving the screen | `blocksFetchError` + `commonRetry` |
| Submit action | Filled button | Dispatches the upload; **disabled** while no target is resolved (loading, pending pick, no block, fetch failure) **or no document is picked** (issue #831: the picked file lives in `pendingDocumentProvider`, so the affordance states that fact instead of letting a tap discover it — a successful submit clears the provider and disables the button again). The missing-document guard inside the dispatch stays as a backstop | `aiImportSubmit` |
| Upload progress | Linear progress indicator | Indeterminate only — the wire carries no percentage | — |

## States

Loading: the target card states `Importziel wird ermittelt …` and the submit
action is disabled. Data: the target line (or the picker, when the season has
several blocks) plus the hint, and the switch/create actions. Empty (no block):
the "create a block first" line with the create action, submit disabled. Empty
(no season): the "select a season first" line, submit disabled. No file picked:
the file row states `Keine Datei gewählt` and the submit action is disabled —
for BOTH kinds (script PDF and schedule CSV/PDF), because one button and one
predicate serve both flows (issue #831).
Error: the block-list fetch failure renders its code-keyed copy
with a retry affordance, submit disabled. Optimistic: none — the screen
dispatches one command (the upload) and hands the projection reconciliation to
the job status screen.

## Interactions

Kind switch clears the pending document. File pick reads the bytes immediately
(nothing persists client-side beyond the in-flight upload). A pick in the
multi-block picker writes the sticky scope, which cascades into the
`X-Active-Block` header and the visible line at once — no manual pill switching.
The same holds for the switch sheet (issue #828): it exists because the resolved
state had no way back to another block without leaving the screen entirely, and
because the pick must reach the scope rather than ride beside the upload — the
dispatch refuses a target season the active block does not belong to
(`ai_import.scope_mismatch`, zero calls). Creating a block from the card
(issue #828) runs the shared form's own AUTHZ-GATE-backed command and then sets
the acknowledged block as the scope, so the very next tap submits into the block
the user just created. A NEWER explicit selection wins (review of #828): the
scope captured when the create interaction started must still be current, so a
scope change that landed while the form was open (a restore, or the shell's
block pill) is never overwritten by the created block.
Submit resolves the target first (one block → adopted automatically, several →
picker, none → blocked), then runs the AUTHZ-GATE, then dispatches the upload
with the declared season (`X-Declared-Season`). If the active block belongs to a
**different** season than the resolved target, the dispatch is refused
client-side with `ai-import.scope-mismatch` and zero requests — the server
answers the same code when a declaration contradicts the header, so one
narrative covers both provenances. A failed dispatch stays on the screen with a
code-keyed snackbar; a 202 opens the job status screen, a 200 opens it with the
duplicate callout.

## Input & Validation

No free-text fields. The dispatch guards, in order: no document → `aiImportDocMissing`
snackbar with zero calls; no season context → client code `ai_import.scope_missing`;
target season ≠ active block's season → `ai_import.scope_mismatch` (409); gate
denial → the gate's own code (`membership.pending` / the capability code); the
script route with a non-PDF source → `ai_import.unsupported_media_type` (415,
client-side, zero calls). Every server failure surfaces keyed on its stable
`code` (`http.payload-too-large`, `ai-import.unsupported-media-type`,
`ai-import.forbidden`, `ai-import.disabled`, `ai-import.scope-mismatch`).

## Accessibility & i18n

The target line is the primary label of the card and is announced as one
semantics node with the title, so a screen-reader user hears "Importziel,
Staffel 2, Block 3" before reaching the submit button. The submit action always
carries a visible label (glossary rule); the disabled state is a real
`onPressed: null` (announced as disabled, not merely dimmed). All copy comes
from the ARB catalogs (`aiImport*` keys); backend `detail` text never renders.
The target card uses theme colors only (`surfaceContainerHighest`), no inline
styles.

## Tests

Widget tests (`test/features/ai_import/import_submit_screen_test.dart`): the
target line renders season + block above the submit action; a wizard entry with
exactly one block adopts it and the dispatch declares that season; several
blocks render the picker, keep the submit disabled, and a pick publishes the
line and adopts the scope; the resolved state offers `Block wechseln` and
switching in the sheet re-targets the line **and** the dispatched scope (the
single seam, issue #828); a season without blocks offers `Block anlegen`, opens
the shared form and adopts the created block as the target; an unreadable season
row is reported instead of opening a form it cannot fill; a failed block-list
fetch on a RESOLVED target states the failure with a retry that brings the
switch back (and the recovered list is usable); a newer scope selection taken
while the create form is open is not clobbered by the created block; a screen
without a
season context blocks the upload with actionable copy; and the submit affordance
stays disabled until a document is picked, re-disables after the picked file is
cleared, and gates the same way on both kinds (issue #831). Unit tests
(`test/unit/ai_import_target_season_view_test.dart`): `aiImportSeasonView`
answers from the cache without a fetch, fetches only on a miss (with the asked
id — never a guess), ignores a cached row for another season, and yields `null`
when the row cannot be read (both Err arms). Controller tests
(`test/features/ai_import/import_jobs_test.dart`): a target season the ambient
block does not belong to is refused with `ai_import.scope_mismatch` and zero
repository calls; a matching season dispatches and declares it. Repository
tests (`test/unit/ai_import_repositories_test.dart`): the declared season rides
as `X-Declared-Season` on both upload routes and is absent when no target was
resolved. Job view: `test/features/ai_import/job_status_screen_test.dart`
asserts the recorded target line and the honest, cause-neutral "not recorded"
arm (goldens re-baselined with the target card; the target card additionally has
its own `matchesGoldenFile` coverage for the resolved, picker and blocked
states).
