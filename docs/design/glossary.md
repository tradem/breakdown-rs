<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: omen-alpha (opencode-go) -->
<!-- Co-authored-by: space-bunny-free (opencode-go) -->
<!-- Co-authored-by: deepseek-v4-flash (neuralwatt) -->

# Icon & Terminology Glossary

The single source of truth for **Material Symbols icons → user-facing
German labels → usage context → copy key** in the breakdown-rs
frontends. Screen specs (`docs/design/screens/`) MUST source their UI
copy keys and icon choices from this glossary; new screens record new
entries here in the same change.

## Localization catalog workflow

This glossary is the human-readable index of copy keys, icons, and usage
context. The actual localized strings live in
`frontend-flutter/lib/l10n/app_de.arb` (German template) and
`frontend-flutter/lib/l10n/app_en.arb` (English). A screen change records
its key in this glossary and its German/English values in the corresponding
ARB files in the same change. Run `flutter gen-l10n`; generated Dart output
is rebuild-only. ARB placeholders and plurals use ICU Message Syntax, and
the client never renders backend `detail` text.

### Two distinct key namespaces — do not mix them up

There are **two** key spaces, and the `Copy key` column above belongs to the
first one:

1. **Logical design namespace** (this glossary). Screen-scoped, dotted,
   human-authored, and part of the design vocabulary
   (`nav.seasons`, `characters.detail.measurements`, `reports.flags`).
   Some rows are *section markers* (`reports.*`, `wizard.*`) that name a
   group of entries rather than one catalog key, and some name copy that is
   designed but not implemented yet.
2. **ARB identifiers** (`frontend-flutter/lib/l10n/app_{de,en}.arb`). Flat
   `camelCase` keys that `flutter gen-l10n` turns into the
   `AppLocalizations` getters the code actually calls (`navSeasons`,
   `characterMeasurementHeight`, `reportsFlagMoved`).

The mapping is **not mechanical** — do not assume
`foo.barBaz` ⇄ `fooBarBaz`:

- Several logical keys legitimately **consolidate into one shared catalog
  entry** (e.g. the design's `blocks.create.first` and
  `blocks.create.title` are one ARB key each, while the seven per-field
  `characters.detail.measurements` rows became seven shared
  `characterMeasurement*` keys).
- A logical key may be implemented under different words
  (`characters.create` → `characterAddFab`), because the ARB key names the
  rendered string, not the design slot.

**Authoritative rule:** the ARB catalogs are the single source of truth for
what is implemented. When implementing a glossary row, add the real ARB key
and cite it in the pull request. `frontend-flutter/tool/check_glossary_catalog.py`
verifies that every ARB identifier listed in the implemented-inventory table
below still exists in both catalogs, so the table cannot silently rot.

### Implemented ARB inventory (authoritative)

<!-- implemented-inventory:start -->
<!-- Generated from lib/l10n/app_de.arb + actual call sites under lib/.
     Verified by frontend-flutter/tool/check_glossary_catalog.py. -->

| Area | ARB identifiers (AppLocalizations getters) |
|---|---|
| Auth & shell | `appTitleBreakdown`, `authContinueAs`, `authDevNotice`, `authErrorConfiguration`, `authErrorGeneric`, `authErrorNetwork`, `authErrorRestore`, `authErrorSignInFailed`, `authSignIn`, `commonAbout`, `commonAdd`, `commonBack`, `commonCancel`, `commonClose`, `commonDelete`, `commonRetry`, `commonSave`, `commonSettings`, `commonSignOut`, `commonUnknown`, `infoAiBody`, `infoAiUsage`, `infoLicense`, `infoLicenseBody`, `infoSource`, `infoSourceError`, `infoTitle`, `infoVersion`, `moreCategories`, `moreCategoriesOpenPlanen`, `moreSignedIn`, `moreSignedOut`, `moreTitle`, `navAiImport`, `navBlocks`, `navCharacters`, `navCostumes`, `navEpisodes`, `navMore`, `navPlanen`, `navSeasons`, `navShootingDays`, `seasonTabSemantic`, `seasonsAddTooltip`, `seasonsCreate`, `seasonsCreateAuth`, `seasonsCreateConflict`, `seasonsCreateGeneric`, `seasonsCreateNetwork`, `seasonsDefaultTitle`, `seasonsEmpty`, `seasonsEmptyGuidance`, `seasonsEmptyImportCta`, `seasonsEmptySetupCta`, `seasonsEmptyTitle`, `seasonsErrorBanner`, `seasonsLoadError`, `seasonsMetaBlocks`, `seasonsMetaCostumes`, `seasonsMetaScenes`, `seasonsOnlineRequired`, `seasonsStale`, `seasonsStaleAt`, `seasonsStaleBanner`, `seasonsStaleDays`, `seasonsStaleHours`, `seasonsStaleJustNow`, `seasonsStaleMinutes`, `seasonsSyncing`, `seasonsTitle`, `settingsBackendUri`, `settingsClose`, `settingsFlavor`, `settingsProdNote`, `settingsReset`, `settingsSave`, `settingsServerAddress`, `settingsTitle` |
| Hierarchy | `blockSeasonNumber`, `blockTileLabel`, `blocksAddFab`, `blocksBackToSeasons`, `blocksCreateButton`, `blocksCreateErrorExists`, `blocksCreateErrorGeneric`, `blocksCreateErrorNetwork`, `blocksCreateErrorSignIn`, `blocksCreateFirst`, `blocksCreateTitle`, `blocksDateFormatError`, `blocksEmpty`, `blocksEndDate`, `blocksFetchError`, `blocksNoBlocksCreateFirst`, `blocksNotFound`, `blocksNumberLabel`, `blocksNumberRequired`, `blocksRoleCostume`, `blocksRoleNone`, `blocksRoleUnknown`, `blocksStaleBanner`, `blocksStartDate`, `blocksTileSyncing`, `blocksTileSyncingStale`, `episodeNumberPrefix`, `episodeTileLabel`, `episodesAddFab`, `episodesBackToBlocks`, `episodesCreateErrorExists`, `episodesCreateErrorGeneric`, `episodesCreateErrorNetwork`, `episodesCreateFirst`, `episodesCreateTitle`, `episodesDismiss`, `episodesEmpty`, `episodesFetchError`, `episodesNameLabel`, `episodesNotFound`, `episodesStaleBanner`, `episodesTileSyncing`, `episodesTileSyncingStale`, `sceneCharacterCount`, `sceneDay`, `sceneDetailAssignCharacter`, `sceneDetailCharactersTitle`, `sceneDetailFetchError`, `sceneDetailGone`, `sceneDetailNoCharacters`, `sceneDetailNoShootingDays`, `sceneDetailOpenDayBoard`, `sceneDetailRemoveCharacterMessage`, `sceneDetailRemoveCharacterTitle`, `sceneDetailRemoveCharacterTooltip`, `sceneDetailScheduleOnDay`, `sceneDetailScheduleTitle`, `sceneDetailScriptDay`, `sceneDetailShootingDaysTitle`, `sceneDetailThisCharacter`, `sceneDetailTitleFallback`, `sceneDetailUnknownCharacter`, `sceneLoc`, `sceneLocationLabel`, `sceneMood`, `sceneMoodLabel`, `sceneNumberLabel`, `sceneScheduled`, `sceneScriptDayLabel`, `sceneShootActualOrder`, `sceneShootAddNote`, `sceneShootAddNoteTitle`, `sceneShootChangePlanned`, `sceneShootChangePlannedExplanation`, `sceneShootChangePlannedTitle`, `sceneShootCounts`, `sceneShootDayFallback`, `sceneShootDeleteNoteMessage`, `sceneShootDeleteNoteTitle`, `sceneShootDeleteNoteTooltip`, `sceneShootEditNoteTitle`, `sceneShootEditNoteTooltip`, `sceneShootErrorGeneric`, `sceneShootErrorNetwork`, `sceneShootFinish`, `sceneShootNoteHint`, `sceneShootNotesTitle`, `sceneShootOrderKeyHint`, `sceneShootOrderTooltip`, `sceneShootPlannedOrder`, `sceneShootSetActualExplanation`, `sceneShootSetActualOrder`, `sceneShootSetActualTitle`, `sceneShootSkip`, `sceneShootStart`, `sceneShootStatusInProgress`, `sceneShootStatusPlanned`, `sceneShootStatusShot`, `sceneShootStatusSkipped`, `sceneShootWrapButton`, `sceneShootWrapConfirm`, `sceneShootWrapMessage`, `sceneShootWrapTitle`, `sceneShootingDayCount`, `sceneShootsEmpty`, `sceneShootsFetchError`, `sceneShootsNotFound`, `sceneShootsPlanFirst`, `sceneShootsReportsTooltip`, `sceneShootsStaleBanner`, `sceneShootsWrappedBanner`, `sceneSummaryLabel`, `sceneTileLabel`, `sceneUnscheduled`, `scenesAddFab`, `scenesBackToEpisodes`, `scenesCreateErrorGeneric`, `scenesCreateErrorNetwork`, `scenesCreateFirst`, `scenesCreateTitle`, `scenesEmpty`, `scenesFetchError`, `scenesNotFound`, `scenesStaleBanner`, `scenesTileSyncing`, `scenesTileSyncingStale`, `wizardAiImportCta`, `wizardAiImportNeedsConfig`, `wizardCancelBody`, `wizardCancelTitle`, `wizardCompletionCreated`, `wizardCompletionMissingConfig`, `wizardCompletionPartial`, `wizardCompletionSeasonCreated`, `wizardCompletionSummary`, `wizardDiscard`, `wizardDispatchProgress`, `wizardDispatchSemantics`, `wizardDone`, `wizardEpisodeTitlePlaceholder`, `wizardErrorBlockExistsSeries`, `wizardErrorEpisodeExistsSeries`, `wizardErrorGeneric`, `wizardErrorNetwork`, `wizardErrorSeasonExists`, `wizardErrorSeriesIdMissing`, `wizardFieldBlocks`, `wizardFieldPositive`, `wizardKeepEditing`, `wizardNext`, `wizardOpenAiConfig`, `wizardRemoveBlock`, `wizardResume`, `wizardReviewCreateSeason`, `wizardReviewEpisodeCount`, `wizardReviewEpisodesInBlocks`, `wizardReviewNumbersPending`, `wizardReviewSeason`, `wizardReviewSeasonNamed`, `wizardReviewSubmit`, `wizardStepOf`, `wizardTemplates`, `wizardTitle` |
| Costumes & photos | `captureDeniedCamera`, `captureDeniedGallery`, `captureDeniedTitleCamera`, `captureDeniedTitleGallery`, `captureUnavailable`, `characterAddFab`, `characterCategoryExtra`, `characterCategoryGuest`, `characterCategoryLabelName`, `characterCategoryMain`, `characterContact`, `characterCreateTitle`, `characterDetailFetchError`, `characterDetailGone`, `characterDetailTitleFallback`, `characterEmail`, `characterErrorGeneric`, `characterErrorNetwork`, `characterMeasurementChest`, `characterMeasurementHatSize`, `characterMeasurementHeight`, `characterMeasurementHips`, `characterMeasurementShoeSize`, `characterMeasurementWaist`, `characterMeasurementWeight`, `characterMeasurements`, `characterNameLabel`, `characterNameRequired`, `characterPhone`, `characterSaveContact`, `characterSaveMeasurements`, `characterTileLabel`, `characterTileSyncing`, `characterTileSyncingStale`, `charactersEmpty`, `charactersFetchError`, `charactersGone`, `charactersStaleBanner`, `continuityCostumeHint`, `continuityEmpty`, `continuityPhotoLabel`, `continuityRationaleBody`, `continuityRationaleTitle`, `continuityRoleGate`, `continuityStoreOn`, `continuityTitle`, `continuityUnlinkBody`, `continuityUnlinkButton`, `continuityUnlinkTitle`, `costumeAddFab`, `costumeCategoriesCreateFirst`, `costumeCategoriesEmpty`, `costumeCategoriesFetchError`, `costumeCategoriesStaleBanner`, `costumeCategoriesTileSyncing`, `costumeCategoriesTileSyncingStale`, `costumeCategoriesTitle`, `costumeCategoryAddFab`, `costumeCategoryArchiveButton`, `costumeCategoryArchiveMessage`, `costumeCategoryArchiveTitle`, `costumeCategoryArchiveTooltip`, `costumeCategoryArchived`, `costumeCategoryCreateTitle`, `costumeCategoryErrorChanged`, `costumeCategoryErrorGeneric`, `costumeCategoryErrorNetwork`, `costumeCategoryNameLabel`, `costumeCategoryNameRequired`, `costumeCategoryRenameButton`, `costumeCategoryRenameTitle`, `costumeCategoryRenameTooltip`, `costumeCategoryTileLabel`, `costumeCategoryUncategorized`, `costumeDetailAddDetail`, `costumeDetailAssign`, `costumeDetailAssignGate`, `costumeDetailCamera`, `costumeDetailCategory`, `costumeDetailCharacter`, `costumeDetailContinue`, `costumeDetailDeletePhotoMessage`, `costumeDetailDetails`, `costumeDetailGallery`, `costumeDetailNoDetails`, `costumeDetailNotNow`, `costumeDetailNotes`, `costumeDetailNotesHint`, `costumeDetailOpenSettings`, `costumeDetailPhotos`, `costumeDetailPromptBody`, `costumeDetailPromptTitle`, `costumeDetailReassign`, `costumeDetailSaveNotes`, `costumeDetailSaved`, `costumeDetailSubject`, `costumeDetailText`, `costumeDetailTextRequired`, `costumeDetailTitle`, `costumeDetailUnassignMessage`, `costumeDetailUnassignTitle`, `costumeDetailUnassignTooltip`, `costumeDetailUnassigned`, `costumeDetailsCount`, `costumeErrorChanged`, `costumeErrorForbidden`, `costumeErrorGeneric`, `costumeErrorMembership`, `costumePhotosCount`, `costumeTileLabel`, `costumeTileLabelFallback`, `costumeTileSyncing`, `costumeTileSyncingStale`, `costumeWornBy`, `costumesEmpty`, `costumesFetchError`, `costumesStaleBanner`, `photoDeleteTitle`, `photoErrorForbidden`, `photoErrorGeneric`, `photoErrorNetwork`, `photoErrorRequiresCharacter`, `photoErrorTooLarge`, `photoErrorUnsupported`, `photoGalleryAddPhoto`, `photoGalleryCaptureAgain`, `photoGalleryDeleteTooltip`, `photoGalleryEmpty`, `photoGalleryProcessingFailed`, `photoTileSemantics` |
| Shooting / reports | `reportErrorForbidden`, `reportErrorLoad`, `reportErrorMembershipPending`, `reportErrorMembershipUnavailable`, `reportErrorNetwork`, `reportErrorPdfTooLarge`, `reportErrorShareFailed`, `reportErrorUnknownShape`, `reportErrorUnknownStatus`, `reportsActualLabel`, `reportsCountsUnavailable`, `reportsDayPrefix`, `reportsFetch`, `reportsFinal`, `reportsFlagMissing`, `reportsFlagMoved`, `reportsFlagReshot`, `reportsFlagSkipped`, `reportsNoScenes`, `reportsPdfDispo`, `reportsPdfPlannedVsActual`, `reportsPdfSection`, `reportsPdfShootDay`, `reportsPlannedLabel`, `reportsPreview`, `reportsShare`, `reportsSollIstTitle`, `reportsTitle`, `shootingDayActions`, `shootingDayAddFab`, `shootingDayArchive`, `shootingDayArchiveButton`, `shootingDayArchiveMessage`, `shootingDayArchiveTitle`, `shootingDayArchived`, `shootingDayCreateTitle`, `shootingDayDate`, `shootingDayErrorGeneric`, `shootingDayErrorNetwork`, `shootingDayLabel`, `shootingDayLabelHint`, `shootingDayMoveEarlier`, `shootingDayMoveLater`, `shootingDayMoveNoRoom`, `shootingDayNew`, `shootingDayNoDate`, `shootingDayPickDate`, `shootingDayRename`, `shootingDayRenameButton`, `shootingDayRenameTitle`, `shootingDayReschedule`, `shootingDaySemantics`, `shootingDayUnschedule`, `shootingDayUnscheduleButton`, `shootingDayUnscheduleMessage`, `shootingDayUnscheduleTitle`, `shootingDayUntitled`, `shootingDayWrapped`, `shootingDaysCreate`, `shootingDaysEmpty`, `shootingDaysFetchError`, `shootingDaysGone`, `shootingDaysStaleBanner` |
| AI import | `aiApplyAcceptAsIs`, `aiApplyBackToStart`, `aiApplyContextEpisode`, `aiApplyContextRemembered`, `aiApplyErrorContextMissing`, `aiApplyErrorGeneric`, `aiApplyErrorNetwork`, `aiApplyErrorNotSucceeded`, `aiApplyErrorUnresolved`, `aiApplyNoContextSubtitle`, `aiApplyNoContextTitle`, `aiApplyOutcome`, `aiApplyPickEpisode`, `aiApplySelectionSummary`, `aiApplySubmit`, `aiApplyTitle`, `aiConfigActiveTitle`, `aiConfigApiKeyLabel`, `aiConfigAssistantModelLabel`, `aiConfigCleanup`, `aiConfigDiscoveryError`, `aiConfigErrorAdmin`, `aiConfigErrorChanged`, `aiConfigErrorDisabled`, `aiConfigErrorGeneric`, `aiConfigErrorNetwork`, `aiConfigErrorOrphaned`, `aiConfigErrorProvider`, `aiConfigFirstRunBody`, `aiConfigImageModelLabel`, `aiConfigImageSuffix`, `aiConfigKeyMissing`, `aiConfigModelCatalogUnavailable`, `aiConfigNoModel`, `aiConfigNoProviders`, `aiConfigNotConfigured`, `aiConfigPrefillHint`, `aiConfigProviderLabel`, `aiConfigProviderPrefix`, `aiConfigProviderUnavailable`, `aiConfigProvidersUnavailable`, `aiConfigRecheck`, `aiConfigRevokeBody`, `aiConfigRevokeButton`, `aiConfigRevokeTitle`, `aiConfigSaveChanges`, `aiConfigSaveConfiguration`, `aiConfigSchedulePromptLabel`, `aiConfigScriptPromptLabel`, `aiConfigTitle`, `aiConfigUnresolvedBody`, `aiConfigUnresolvedTitle`, `aiEpisodePickerEmpty`, `aiEpisodePickerError`, `aiEpisodePickerTitle`, `aiImportConfigure`, `aiImportDocMissing`, `aiImportNoFile`, `aiImportOrPickFile`, `aiImportPasteLabel`, `aiImportPickCsvPdf`, `aiImportPickPdf`, `aiImportSchedule`, `aiImportScheduleHint`, `aiImportScript`, `aiImportScriptHint`, `aiImportStampWarning`, `aiImportSubmit`, `aiImportTitle`, `aiJobCheckAgain`, `aiJobDuplicate`, `aiJobRetryBudget`, `aiJobReviewPreview`, `aiJobTitle`, `aiPreviewCreate`, `aiPreviewFallbackTitle`, `aiPreviewKindUnknown`, `aiPreviewLoadError`, `aiPreviewMergedSubtitle`, `aiPreviewMergedTitle`, `aiPreviewMissing`, `aiPreviewRowRef`, `aiPreviewSceneWithSummary`, `aiPreviewScheduleSubtitle`, `aiPreviewScheduleTitle`, `aiPreviewScheduledRowCount`, `aiPreviewScriptSubtitle`, `aiPreviewScriptTitle`, `aiPreviewSkip`, `aiPreviewTitle`, `aiPreviewUncertainty`, `aiPreviewUnmatchedScheduleRow`, `aiPreviewUnmatchedScriptScene`, `aiPreviewUnrecognizedShape`, `aiPreviewUnscheduled`, `aiPreviewUpdate`, `aiPreviewUpdatesScene`, `aiScenePickerEmpty`, `aiScenePickerError`, `aiUploadDisabled`, `aiUploadGeneric`, `aiUploadNetwork`, `aiUploadPermissions`, `aiUploadScopeMissing`, `aiUploadTooLarge`, `aiUploadUnsupported`, `jobStatusDeadLetter`, `jobStatusFailed`, `jobStatusPayloadUnavailable`, `jobStatusPending`, `jobStatusRunning`, `jobStatusSucceeded`, `jobStatusUnknown`, `jobWatchExhausted`, `jobWatchForbidden`, `jobWatchGeneric`, `jobWatchNetwork`, `jobWatchNotFound` |
| Errors & shared | `problemAuthzSessionRequired`, `reconcileStaleWarning` |
| Other | `costumingTabNoSeason`, `costumingTabPickSeason`, `createSeasonSeriesId`, `createSeasonSeriesIdRequired`, `createSeasonTitle`, `createSeasonTitleLabel`, `createSeasonWizardCta`, `fatalConfigBody`, `fatalConfigTitle`, `planningImportSubtitle`, `planningLoadError`, `planningNoSeasons`, `planningSeasonNumber` |
<!-- implemented-inventory:end -->

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
| `checkroom` | **Kleidung** | Navigation shell destination 3 of 4 — costume domains (Kostüme, Figuren) scoped to the active season; costume navigation source shared with costume category fallback | `nav.costumes` |
| `add` (FAB) | **Kostüm erstellen** | Costumes FAB; selecting the action reveals the inline editor | `costumes.create` |
| `style_outlined` | **Ohne Kategorie / Kategorie** | Costume tile placeholder fallback and deterministic unknown-category icon; category text stays visible | `categories.icon` |
| `photo_library_outlined` | **Kein Foto** | Photo-less costume tile placeholder; a ready thumbnail replaces the surface | `costumes.placeholder` |
| `subject` / detail text | **Bezeichnung / Beschreibung** | Costume identity overlay; first detail subject is the de-facto costume name, followed by notes fallback, never the UUID | `costumes.tile.name` |
| — *(no icon)* | **Kostümdaten gespeichert** | Visible confirmation after a successful detail or notes save | `costumeDetail.saved` |
| `—` *(no icon)* | **Foto löschen?** | Photo delete confirmation (costume detail / continuity strip) | `photos.delete` |
| `—` *(no icon)* | **Kategorie/Foto-Fehler** | Code-keyed command-error narratives for costume and photo surfaces (never backend `detail`) | `costumes.photos.errors` |
| `—` *(no icon)* | **Berichte (Soll-Ist/PDF)** | Reports screen title, Soll-Ist rows, PDF cards | `reports.*` |
| `—` *(no icon)* | **verschoben / fehlend / übersprungen / erneut gedreht** | Soll-Ist flag chips (render projection verbatim, D2) | `reports.flags` |
| `—` *(no icon)* | **KI-Import-Konfiguration** | AI config screen + code-keyed error narratives (admin role, vault, provider) | `aiConfig.*` |
| `—` *(no icon)* | **KI-Import / Vorschau / Anwenden** | Import submit, preview, apply + job status screens | `aiImport.*` |
| `—` *(no icon)* | **Wartet / In Arbeit / Bereit / Fehlgeschlagen** | AI job status matrix (honest copy, D2) | `aiImport.jobStatus` |
| `rocket_launch_outlined` | **Season-Setup** | 4-Schritt-Assistent (Season → Blöcke → Prüfen → Fertig) inkl. Abbruch-Dialog | `wizard.*` |
| `—` *(no icon)* | **Schritt {n} von 4** | Wizard-Fortschrittskopf (Semantics + Text) | `wizard.stepOf` |
| `—` *(no icon)* | **Vorlagen / Block entfernen / Episoden** | Blöcke-Schritt des Wizards | `wizard.blocks` |
| `person_outline` | **Figuren** | Bottom-nav destination „Figuren"; character rows (branch term for Kostüm/Film — not „Rollen") | `nav.characters` |
| `add` (FAB) | **Figur erstellen** | Characters FAB + create-dialog title | `characters.create` |
| `—` *(no icon)* | **Figur {n}** | Character tile fallback label | `characters.tile` |
| `—` *(no icon)* | **Hauptbesetzung / Gast / Komparse** | Character category discriminator | `characters.category` |
| `—` *(no icon)* | **Noch keine Figuren** | Characters empty state | `characters.empty` |
| `—` *(no icon)* | **Kontakt / Maße** | Character-detail editor sections | `characters.detail.sections` |
| `—` *(no icon)* | **Höhe/Gewicht/Brust/Taille/Hüfte/Schuhgröße/Hutgröße** | Character measurement fields | `characters.detail.measurements` |
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
| `—` *(no icon)* | **Block erstellen** | Create-block dialog/sheet title (ephemeral form, IDs from navigation context) | `blocks.create.title` |
| `—` *(no icon)* | **Noch keine Blöcke** | Blocks list empty state | `blocks.empty` |
| `—` *(no icon)* | **Ersten Block erstellen** | Blocks empty-state create CTA | `blocks.create.first` |
| `—` *(no icon)* | **Zurück zu den Staffeln** | Deleted-parent (404) back affordance | `blocks.notFound.back` |
| `—` *(no icon)* | **Staffel {n}** | Season-number fallback title on the blocks AppBar | `blocks.seasonNumber` |
| `—` *(no icon)* | **Einstellungen** | Settings dialog title and entry label | `settings.title` |
| `cloud_off` | **Verbindung gestört** | Stale/optimistic overlay banner when sync hangs | `errors.connectionLost` |
| `style_outlined` | **Kategorien** | Season tile → costume categories. Redesign note (report §4.5): not a daily entry point — relocates into „Mehr"/season detail; then icon-only entry is removed | `nav.costumeCategories` |
| `add` (FAB) | **Kategorie hinzufügen** | Costume-categories FAB (same icon, per-screen label) | `costumeCategories.create` |
| `—` *(no icon)* | **Kategorie {n}** | Costume-category tile fallback label | `costumeCategories.tile` |
| `—` *(no icon)* | **Archiviert** | Archived-category visibility toggle + tile marker | `costumeCategories.archived` |
| `—` *(no icon)* | **Kategorie erstellen / umbenennen / archivieren** | Category command dialogs | `costumeCategories.dialogs` |
| `—` *(no icon)* | **Noch keine Kategorien** | Costume-categories empty state | `costumeCategories.empty` |
| `—` *(no icon)* | **Erste Kategorie erstellen** | Empty-state create CTA | `costumeCategories.create.first` |
| `calendar_month_outlined` | **Drehtage** | Shooting-day navigation from episodes/scene planning | `nav.shootingDays` |
| `add` (FAB) | **Drehtag erstellen** | Shooting-days FAB | `shootingDays.create` |
| `event_busy` | **Termin entfernen** | Shooting-day unschedule confirmation | `shootingDays.unschedule` |
| `archive_outlined` | **Drehtag archivieren** | Shooting-day archive confirmation | `shootingDays.archive` |
| `—` *(no icon)* | **Datum wählen / Noch kein Datum** | Shooting-day create-sheet date picker | `shootingDays.create.date` |
| `—` *(no icon)* | **Drehtag umbenennen** | Rename-shooting-day dialog | `shootingDays.rename` |
| `movie_creation_outlined` | **Episoden** | Drill-down label for episodes within blocks | `nav.episodes` |
| `view_agenda_outlined` | **Szenen** | Drill-down label for scenes within episodes | `nav.scenes` |
| `photo_camera` | **Foto aufnehmen** | Continuity photo capture (costume detail, continuity strip) — camera permission requested at point of use with rationale | `photos.capture` |
| `photo_library` | **Fotogalerie** | Photo gallery entry from costume detail / continuity strip | `photos.gallery` |
| `photo_library_outlined` | **Keine Fotos** | Empty state of the photo gallery | `photos.empty` |
| `summarize_outlined` | **Berichte** | Scene-shoot reports entry (Soll/Ist) | `reports.open` |
| `event_busy` | **Termin entfernen** | Scene detail — remove shooting-day assignment | `scenes.unschedule` |
| `unfold_more` | **Alle Szenen anzeigen** | Scene-shoots list — expand collapsed sections | `sceneShoots.expand` |
| `summarize_outlined` | **Berichte** | Scene-shoot Day-Board → reports entry | `sceneShoots.reports` |
| `event_available` | **Drehtag abschließen** | Wrap-day confirmation (final, read-only) | `sceneShoots.wrap` |
| `—` *(no icon)* | **Start / Abschließen / Überspringen** | Per-shoot execution actions | `sceneShoots.actions` |
| `unfold_more` | **Tatsächliche Reihenfolge festlegen… / Geplante Position ändern…** | Per-shoot order menu | `sceneShoots.order` |
| `—` *(no icon)* | **Notizen ({n})** | Shoot note list / add / edit / delete | `sceneShoots.notes` |
| `—` *(no icon)* | **In Arbeit / Abgedreht / Übersprungen / Geplant** | Ist status chip (projection verbatim, D2) | `sceneShoots.status` |
| `—` *(no icon)* | **Für diesen Tag sind noch keine Szenen-Drehs geplant.** | Day-board empty state | `sceneShoots.empty` |
| `more_horiz` | **Mehr** | Navigation shell destination 4 of 4 — Import, Kategorien, Über die App, Einstellungen, Abmelden (Berichte bleiben im Day-Board verankert) | `nav.more` |
| `add` (FAB) | **Episode hinzufügen** | Episodes FAB (same icon, per-screen label) | `episodes.create` |
| `—` *(no icon)* | **Episode {n}** | Episode list tile fallback title (named episodes use the stored name) | `episodes.tile` |
| `—` *(no icon)* | **Nummer {n}** | Episode tile subtitle | `episodes.tile.number` |
| `—` *(no icon)* | **Noch keine Episoden** | Episodes list empty state | `episodes.empty` |
| `—` *(no icon)* | **Erste Episode erstellen** | Episodes empty-state create CTA | `episodes.create.first` |
| `—` *(no icon)* | **Zurück zu den Blöcken** | Deleted-parent (404) back affordance | `episodes.notFound.back` |
| `—` *(no icon)* | **Episode erstellen** | Create-episode dialog/sheet title | `episodes.create.title` |
| `add` (FAB) | **Szene hinzufügen** | Scenes FAB (same icon, per-screen label) | `scenes.create` |
| `—` *(no icon)* | **Szene {id}** | Scene tile fallback title (summaries render when present) | `scenes.tile` |
| `—` *(no icon)* | **Stimmung: {v} / Ort: {v} / Tag: {v}** | Scene tile metadata | `scenes.tile.meta` |
| `—` *(no icon)* | **Eingeplant / Nicht eingeplant** | Scene schedule state | `scenes.tile.schedule` |
| `—` *(no icon)* | **Noch keine Szenen** | Scenes list empty state | `scenes.empty` |
| `—` *(no icon)* | **Erste Szene erstellen** | Scenes empty-state create CTA | `scenes.create.first` |
| `—` *(no icon)* | **Zurück zu den Episoden** | Deleted-parent (404) back affordance | `scenes.notFound.back` |
| `—` *(no icon)* | **Szene erstellen** | Create-scene dialog/sheet title | `scenes.create.title` |
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
| `‹` *(navigation arrow)* | **Zurück** | Setup wizard — previous step / back affordance | `wizard.back` |
| `—` *(no icon)* | **Season-Setup** | Setup wizard app bar title | `wizard.title` |
| `—` *(no icon)* | **Schritt {x} von {n}** | Setup wizard step progress indicator | `wizard.progress` |
| `—` *(no icon)* | **Nummer** | Wizard season step — number field | `wizard.season.numberLabel` |
| `—` *(no icon)* | **Name (optional)** | Wizard season step — name field | `wizard.season.nameLabel` |
| `—` *(no icon)* | **Season {n}** | Wizard season step — live preview of the resulting title | `wizard.season.preview` |
| `—` *(no icon)* | **Block {n}** | Wizard blocks step — one block draft card | `wizard.blocks.draft` |
| `—` *(no icon)* | **Episoden** | Wizard blocks step — episode-count field | `wizard.blocks.episodeCountLabel` |
| `—` *(no icon)* | **Titel (optional)** | Wizard blocks step — draft title field | `wizard.blocks.titleLabel` |
| `delete` | **Block entfernen** | Wizard blocks step — removes one draft | `wizard.blocks.remove` |
| `add` | **Block hinzufügen** | Wizard blocks step — appends a draft (same icon as the Blocks FAB, per-screen label) | `wizard.blocks.addDraft` |
| `bolt` | **4 Blöcke à 8 Episoden** | Wizard blocks step — template suggestion chip | `wizard.blocks.template4x8` |
| `bolt` | **3 Blöcke à 6 Episoden** | Wizard blocks step — template suggestion chip | `wizard.blocks.template3x6` |
| `arrow_forward` | **Weiter** | Wizard step advance button | `wizard.next` |
| `fact_check_outlined` | **Prüfen & erstellen** | Wizard review step — summary headline | `wizard.review.title` |
| `check` | **Season erstellen** | Wizard review step — dispatch confirm (same verb as the seasons create FAB) | `wizard.review.confirm` |
| `progress_activity` | **Season wird erstellt…** | Wizard dispatch overlay — per-command progress | `wizard.dispatching` |
| `check_circle_outline` | **Season {n} angelegt** | Wizard completion headline | `wizard.completion.title` |
| `—` *(no icon)* | **{n} Blöcke · {m} Episoden** | Wizard completion — created-structure summary | `wizard.completion.summary` |
| `smart_toy_outlined` | **KI-Import starten** | Wizard completion CTA (only with an AI configuration) | `wizard.completion.importCta` |
| `psychology_alt_outlined` | **Für den KI-Import ist eine KI-Konfiguration nötig.** | Wizard completion info card without config | `wizard.completion.aiInfo` |
| `psychology_alt_outlined` | **KI-Konfiguration öffnen** | Wizard completion info-card action → AI config screen | `wizard.completion.aiInfoCta` |
| `error_outline` | **Teilweise erstellt** | Wizard partial-failure headline (created-so-far summary) | `wizard.completion.partialTitle` |
| `refresh` | **Fortsetzen** | Wizard partial-failure retry of the remaining commands | `wizard.completion.retry` |
| `check` | **Fertig** | Wizard completion — closes the wizard | `wizard.completion.done` |
| `help_outline` | **Setup abbrechen?** | Wizard discard-confirmation dialog title | `wizard.abort.title` |
| `—` *(no icon)* | **Deine Eingaben werden verworfen. Es wurde noch nichts gespeichert.** | Wizard discard-confirmation body (names what is lost — decision 3) | `wizard.abort.body` |
| `delete` | **Verwerfen** | Wizard discard-confirmation destructive action | `wizard.abort.discard` |
| `close` | **Weiter bearbeiten** | Wizard discard-confirmation keep-editing action | `wizard.abort.keepEditing` |
| `—` *(no icon)* | **Eine ganze Zahl größer als 0 ist nötig.** | Wizard inline validation — season number / episode count | `wizard.errors.positiveNumber` |
| `—` *(no icon)* | **Mindestens ein Block ist nötig.** | Wizard inline validation — zero drafts at submit time | `wizard.errors.noBlocks` |
| `—` *(no icon)* | **Nummern werden ermittelt …** | Wizard review — derived series-scoped numbers still settling; confirm stays disabled until then | `wizard.review.numbersPending` |
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
