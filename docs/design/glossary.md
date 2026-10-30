<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (neuralwatt) -->
<!-- Co-authored-by: omen-alpha (opencode-go) -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->
<!-- Co-authored-by: glm-5.3-flash (opencode-go) -->
<!-- Co-authored-by: space-bunny-free (opencode-go) -->
<!-- Co-authored-by: deepseek-v4-flash (neuralwatt) -->
<!-- Co-authored-by: glm-5.3-flash (opencode-go) -->
<!-- Co-authored-by: glm-5.3-flash-flex (neuralwatt) -->
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

# Icon & Terminology Glossary

The single source of truth for **Material Symbols icons → user-facing
German labels → usage context → copy key** in the breakdown-rs
frontends. Screen specs (`docs/design/screens/`) MUST source their UI
copy keys and icon choices from this glossary; new screens record new
entries here in the same change.

## Domain terms — Piece and Outfit (issue #739)

The backend change `separate-piece-and-outfit-domain` split the retired
`Costume` aggregate in two. The client's user-facing German vocabulary follows
it, and this glossary is the source for both terms:

| Term (code) | German label | Meaning | Copy keys |
|---|---|---|---|
| `Piece` | **Kleidungsstück** (pl. *Kleidungsstücke*) | A single garment in the wardrobe fundus: one optional category, a season repertoire, details, notes, photos — and **no character**. Catalogued independently of any figure and reusable across looks and seasons. | `pieceAddFab`, `pieceDetailTitle`, `pieceTileLabelFallback`, `piecesEmpty` |
| `Outfit` | **Look** (pl. *Looks*) | A character's composed look: mandatory character, required name, `0..n` pieces (layering allowed), `variant_of` lineage, notes and fitting photos. This is what a scene **casts** (`SceneOutfitBeat`). | `outfitListTitle`, `outfitCreateAction`, `outfitDetailTitle`, `outfitPiecesTitle`, `outfitCreateVariant` |

Terms that deliberately keep the word **Kostüm** (the split did not touch
them): the `costume-category` vocabulary (**Kostüm-Kategorien**, its keys,
its icons), the costume-department role (**Kostüm-Rolle**, the
`assign_costumes` capability and the `hasActiveCostumeRole*` predicates) and
the AI-import draft vocabulary (`DraftCostume`/`PreviewCostume`, owned by the
sibling AI-import changes).

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
| Auth & shell | `aiDisclosureActBody`, `aiDisclosureActTitle`, `aiDisclosureFlowBody`, `aiDisclosureFlowTitle`, `aiDisclosureNamingBodyConfigured`, `aiDisclosureNamingBodyLoading`, `aiDisclosureNamingBodyUnconfigured`, `aiDisclosureNamingTitle`, `aiDisclosurePurposeBody`, `aiDisclosurePurposeTitle`, `aiDisclosureRetentionBody`, `aiDisclosureRetentionTitle`, `aiDisclosureTitle`, `appTitleBreakdown`, `authContinueAs`, `authDevNotice`, `authErrorConfiguration`, `authErrorGeneric`, `authErrorNetwork`, `authErrorRestore`, `authErrorSignInFailed`, `authSignIn`, `castCategoriesTooltip`, `castNoSeason`, `castPickSeason`, `castSegmentCharacters`, `castSegmentOutfits`, `commonAbout`, `commonAdd`, `commonBack`, `commonCancel`, `commonClose`, `commonDelete`, `commonRetry`, `commonSave`, `commonSettings`, `commonSignOut`, `commonUnknown`, `episodeChipEmpty`, `episodeChipPickTitle`, `episodeChipTooltip`, `episodeChipUnset`, `episodeChipUnsetTooltip`, `infoAiBody`, `infoAiUsage`, `infoLicense`, `infoLicenseBody`, `infoSource`, `infoSourceError`, `infoTitle`, `infoVersion`, `locationStripSemantics`, `navAiImport`, `navBlocks`, `navCast`, `navCharacters`, `navWardrobe`, `navEpisodes`, `navSchedule`, `navScript`, `navShootingDays`, `omniSearchTooltip`, `productionBlocksSubtitle`, `productionNoActiveSeason`, `productionTitle`, `profileTitle`, `profileTooltip`, `scheduleDayLabel`, `scheduleDayUndated`, `scheduleFetchError`, `scheduleNoDays`, `schedulePartialBlocks`, `schedulePartialLoad`, `scopeChipBlock`, `scopeChipBlockUnset`, `scopeChipBlockUnsetTooltip`, `scopeChipForeignSeason`, `scopeChipPickTitle`, `scopeChipSeason`, `scopeChipSeasonPickTitle`, `scopeChipSeasonTooltip`, `scopeChipSeasonUnset`, `scopeChipTooltip`, `scopeChipUnknownBlock`, `scriptEpisodeLabel`, `scriptFetchError`, `scriptNoScenes`, `scriptPartialBlocks`, `scriptPartialLoad`, `scriptSceneNumber`, `scriptSceneNumberUnknown`, `seasonScopeEmpty`, `seasonScopeManageProduction`, `seasonScopeManageSeasons`, `seasonTabSemantic`, `seasonsAddTooltip`, `seasonsCreateAuth`, `seasonsCreateConflict`, `seasonsCreateGeneric`, `seasonsCreateNetwork`, `seasonsCreateSeriesIdMissing`, `seasonsDefaultTitle`, `seasonsEmpty`, `seasonsEmptyGuidance`, `seasonsEmptyImportCta`, `seasonsEmptySetupCta`, `seasonsEmptyTitle`, `seasonsErrorBanner`, `seasonsLoadError`, `seasonsManualCreateCta`, `seasonsMetaBlocks`, `seasonsMetaPieces`, `seasonsMetaScenes`, `seasonsOnlineRequired`, `seasonsSetupCta`, `seasonsStale`, `seasonsStaleAt`, `seasonsStaleBanner`, `seasonsStaleDays`, `seasonsStaleHours`, `seasonsStaleJustNow`, `seasonsStaleMinutes`, `seasonsSyncing`, `seasonsTitle`, `settingsBackendUri`, `settingsClose`, `settingsFlavor`, `settingsProdNote`, `settingsReset`, `settingsSave`, `settingsServerAddress`, `settingsTitle` |
| Backend health | `healthCheckAiStorage`, `healthCheckDatabase`, `healthCheckEventStore`, `healthCheckOther`, `healthCheckSecrets`, `healthCheckStatusDegraded`, `healthCheckStatusHealthy`, `healthCheckStatusUnhealthy`, `healthDetailDependencies`, `healthDetailNoDependencies`, `healthDetailOfflineBody`, `healthDetailPending`, `healthDetailTitle`, `healthPillDegraded`, `healthPillHealthy`, `healthPillOffline`, `healthPillOpenHint`, `healthPillUnhealthy` |
| Hierarchy | `blockSeasonNumber`, `blockTileLabel`, `blocksAddFab`, `blocksBackToSeasons`, `blocksCreateButton`, `blocksCreateErrorExists`, `blocksCreateErrorGeneric`, `blocksCreateErrorNetwork`, `blocksCreateErrorSignIn`, `blocksCreateFirst`, `blocksCreateTitle`, `blocksDateFormatError`, `blocksEmpty`, `blocksEndDate`, `blocksFetchError`, `blocksNoBlocksCreateFirst`, `blocksNotFound`, `blocksNumberLabel`, `blocksNumberRequired`, `blocksRoleCostume`, `blocksRoleNone`, `blocksRoleUnknown`, `blocksStaleBanner`, `blocksStartDate`, `blocksTileSyncing`, `blocksTileSyncingStale`, `episodeNumberPrefix`, `episodeTileLabel`, `episodesAddFab`, `episodesBackToBlocks`, `episodesCreateErrorExists`, `episodesCreateErrorGeneric`, `episodesCreateErrorNetwork`, `episodesCreateFirst`, `episodesCreateTitle`, `episodesDismiss`, `episodesEmpty`, `episodesFetchError`, `episodesNameLabel`, `episodesNotFound`, `episodesStaleBanner`, `episodesTileSyncing`, `episodesTileSyncingStale`, `sceneCharacterCount`, `sceneDay`, `sceneDetailAssignCharacter`, `sceneDetailCharactersTitle`, `sceneDetailFetchError`, `sceneDetailGone`, `sceneDetailNoCharacters`, `sceneDetailNoShootingDays`, `sceneDetailNoShootingDaysReportHint`, `sceneDetailOpenDayBoard`, `sceneDetailRemoveCharacterMessage`, `sceneDetailRemoveCharacterTitle`, `sceneDetailRemoveCharacterTooltip`, `sceneDetailScheduleOnDay`, `sceneDetailScheduleTitle`, `sceneDetailScriptDay`, `sceneDetailShootingDaysTitle`, `sceneDetailThisCharacter`, `sceneDetailTitleFallback`, `sceneDetailUnknownCharacter`, `sceneLoc`, `sceneLocationLabel`, `sceneMood`, `sceneMoodLabel`, `sceneNumberLabel`, `sceneScheduled`, `sceneScriptDayLabel`, `sceneShootActualOrder`, `sceneShootAddNote`, `sceneShootAddNoteTitle`, `sceneShootChangePlanned`, `sceneShootChangePlannedExplanation`, `sceneShootChangePlannedTitle`, `sceneShootCounts`, `sceneShootDayFallback`, `sceneShootDeleteNoteMessage`, `sceneShootDeleteNoteTitle`, `sceneShootDeleteNoteTooltip`, `sceneShootEditNoteTitle`, `sceneShootEditNoteTooltip`, `sceneShootErrorGeneric`, `sceneShootErrorNetwork`, `sceneShootFinish`, `sceneShootNoteHint`, `sceneShootNotesTitle`, `sceneShootOrderKeyHint`, `sceneShootOrderTooltip`, `sceneShootPlannedOrder`, `sceneShootSetActualExplanation`, `sceneShootSetActualOrder`, `sceneShootSetActualTitle`, `sceneShootSkip`, `sceneShootStart`, `sceneShootStatusInProgress`, `sceneShootStatusPlanned`, `sceneShootStatusShot`, `sceneShootStatusSkipped`, `sceneShootWrapButton`, `sceneShootWrapConfirm`, `sceneShootWrapMessage`, `sceneShootWrapTitle`, `sceneShootingDayCount`, `sceneShootsEmpty`, `sceneShootsFetchError`, `sceneShootsNotFound`, `sceneShootsPlanFirst`, `sceneShootsReportsLabel`, `sceneShootsReportsTooltip`, `sceneShootsStaleBanner`, `sceneShootsWrappedBanner`, `sceneSummaryLabel`, `sceneTileLabel`, `sceneUnscheduled`, `scenesAddFab`, `scenesBackToEpisodes`, `scenesCreateErrorGeneric`, `scenesCreateErrorNetwork`, `scenesCreateFirst`, `scenesCreateTitle`, `scenesEmpty`, `scenesFetchError`, `scenesNotFound`, `scenesStaleBanner`, `scenesTileSyncing`, `scenesTileSyncingStale`, `wizardAiImportCta`, `wizardAiImportNeedsConfig`, `wizardCancelBody`, `wizardCancelTitle`, `wizardCompletionCreated`, `wizardCompletionMissingConfig`, `wizardCompletionPartial`, `wizardCompletionSeasonCreated`, `wizardCompletionSummary`, `wizardDiscard`, `wizardDispatchProgress`, `wizardDispatchSemantics`, `wizardDone`, `wizardEpisodeTitlePlaceholder`, `wizardErrorBlockExistsSeries`, `wizardErrorEpisodeExistsSeries`, `wizardErrorGeneric`, `wizardErrorNetwork`, `wizardErrorSeasonExists`, `wizardFieldBlocks`, `wizardFieldPositive`, `wizardKeepEditing`, `wizardNext`, `wizardOpenAiConfig`, `wizardRemoveBlock`, `wizardResume`, `wizardReviewCreateSeason`, `wizardReviewEpisodeCount`, `wizardReviewEpisodesInBlocks`, `wizardReviewNumbersPending`, `wizardReviewSeason`, `wizardReviewSeasonNamed`, `wizardReviewSubmit`, `wizardStepOf`, `wizardTemplates`, `wizardTitle` |
| Wardrobe — pieces | `pieceAddFab`, `pieceDetailAddDetail`, `pieceDetailCamera`, `pieceDetailCategory`, `pieceDetailCategorySaved`, `pieceDetailCategoryTitle`, `pieceDetailContinue`, `pieceDetailDeleteMessage`, `pieceDetailDeletePhotoMessage`, `pieceDetailDeleteTitle`, `pieceDetailDetails`, `pieceDetailEditDetail`, `pieceDetailGallery`, `pieceDetailNoDetails`, `pieceDetailNotNow`, `pieceDetailNotes`, `pieceDetailNotesHint`, `pieceDetailOpenSettings`, `pieceDetailPhotos`, `pieceDetailPickCategory`, `pieceDetailPromptBody`, `pieceDetailPromptTitle`, `pieceDetailRepertoire`, `pieceDetailRepertoireAdd`, `pieceDetailRepertoireAddTooltip`, `pieceDetailRepertoireEmpty`, `pieceDetailRepertoirePick`, `pieceDetailRepertoireRemoveMessage`, `pieceDetailRepertoireRemoveTitle`, `pieceDetailRepertoireRemoveTooltip`, `pieceDetailRepertoireRemoved`, `pieceDetailRepertoireSaved`, `pieceDetailSaveNotes`, `pieceDetailSaved`, `pieceDetailSubject`, `pieceDetailSubjectOptional`, `pieceDetailText`, `pieceDetailTextRequired`, `pieceDetailTextRequiredHint`, `pieceDetailTitle`, `pieceDetailsCount`, `pieceErrorCategoryArchived`, `pieceErrorCategorySeason`, `pieceErrorChanged`, `pieceErrorDetailNotFound`, `pieceErrorForbidden`, `pieceErrorGeneric`, `pieceErrorMembership`, `pieceErrorSeasonArchived`, `pieceErrorSeasonNotFound`, `piecePhotosCount`, `pieceTileLabel`, `pieceTileLabelFallback`, `pieceTileSyncing`, `pieceTileSyncingStale`, `piecesEmpty`, `piecesFetchError`, `piecesStaleBanner` |
| Wardrobe — outfits | `outfitAddPiece`, `outfitCreateAction`, `outfitCreateTitle`, `outfitCreateVariant`, `outfitDetailGone`, `outfitDetailTitle`, `outfitErrorForbidden`, `outfitErrorGeneric`, `outfitErrorMembership`, `outfitListEmpty`, `outfitListFetchError`, `outfitListTitle`, `outfitNameLabel`, `outfitNameRequired`, `outfitNotes`, `outfitNotesHint`, `outfitNotesSaved`, `outfitPhotos`, `outfitPickPieceEmpty`, `outfitPickPieceTitle`, `outfitPieceCount`, `outfitPieceListFetchError`, `outfitPiecesEmpty`, `outfitPiecesTitle`, `outfitRemovePieceTooltip`, `outfitRenameTitle`, `outfitSaveNotes`, `outfitSaved`, `outfitStaleBanner`, `outfitVariantCreated`, `outfitVariantMarker`, `outfitVariantOf` |
| Costumes & photos | `captureDeniedCamera`, `captureDeniedGallery`, `captureDeniedTitleCamera`, `captureDeniedTitleGallery`, `captureUnavailable`, `characterAddFab`, `characterCategoryExtra`, `characterCategoryGuest`, `characterCategoryLabelName`, `characterCategoryMain`, `characterContact`, `characterCreateTitle`, `characterDetailFetchError`, `characterDetailGone`, `characterDetailTitleFallback`, `characterEmail`, `characterErrorGeneric`, `characterErrorNetwork`, `characterMeasurementChest`, `characterMeasurementHatSize`, `characterMeasurementHeight`, `characterMeasurementHips`, `characterMeasurementShoeSize`, `characterMeasurementWaist`, `characterMeasurementWeight`, `characterMeasurements`, `characterNameLabel`, `characterNameRequired`, `characterPhone`, `characterSaveContact`, `characterSaveMeasurements`, `characterTileLabel`, `characterTileSyncing`, `characterTileSyncingStale`, `charactersEmpty`, `charactersFetchError`, `charactersGone`, `charactersStaleBanner`, `continuityPieceHint`, `continuityEmpty`, `continuityPhotoLabel`, `continuityRationaleBody`, `continuityRationaleTitle`, `continuityRoleGate`, `continuityStoreOn`, `continuityTitle`, `continuityUnlinkBody`, `continuityUnlinkButton`, `continuityUnlinkTitle`, `costumeCategoriesCreateFirst`, `costumeCategoriesEmpty`, `costumeCategoriesFetchError`, `costumeCategoriesStaleBanner`, `costumeCategoriesTileSyncing`, `costumeCategoriesTileSyncingStale`, `costumeCategoriesTitle`, `costumeCategoryAddFab`, `costumeCategoryArchiveButton`, `costumeCategoryArchiveMessage`, `costumeCategoryArchiveTitle`, `costumeCategoryArchiveTooltip`, `costumeCategoryArchived`, `costumeCategoryCreateTitle`, `costumeCategoryErrorChanged`, `costumeCategoryErrorGeneric`, `costumeCategoryErrorNetwork`, `costumeCategoryNameLabel`, `costumeCategoryNameRequired`, `costumeCategoryRenameButton`, `costumeCategoryRenameTitle`, `costumeCategoryRenameTooltip`, `costumeCategoryTileLabel`, `costumeCategoryUncategorized`, `photoDeleteTitle`, `photoErrorForbidden`, `photoErrorGeneric`, `photoErrorNetwork`, `photoErrorTooLarge`, `photoErrorUnsupported`, `photoGalleryAddPhoto`, `photoGalleryCaptureAgain`, `photoGalleryDeleteTooltip`, `photoGalleryEmpty`, `photoGalleryProcessingFailed`, `photoTileSemantics` |
| Shooting / reports | `reportErrorForbidden`, `reportErrorLoad`, `reportErrorMembershipPending`, `reportErrorMembershipUnavailable`, `reportErrorNetwork`, `reportErrorPdfTooLarge`, `reportErrorShareFailed`, `reportErrorUnknownShape`, `reportErrorUnknownStatus`, `reportsActualLabel`, `reportsCountsUnavailable`, `reportsDayPrefix`, `reportsFetch`, `reportsFinal`, `reportsFlagMissing`, `reportsFlagMoved`, `reportsFlagReshot`, `reportsFlagSkipped`, `reportsNoScenes`, `reportsPdfDispo`, `reportsPdfPlannedVsActual`, `reportsPdfSection`, `reportsPdfShootDay`, `reportsPlannedLabel`, `reportsPreview`, `reportsShare`, `reportsIndexDayFinal`, `reportsIndexDayOpen`, `reportsIndexEmpty`, `reportsIndexTitle`, `reportsSollIstTitle`, `reportsTitle`, `shootingDayActions`, `shootingDayAddFab`, `shootingDayArchive`, `shootingDayArchiveButton`, `shootingDayArchiveMessage`, `shootingDayArchiveTitle`, `shootingDayArchived`, `shootingDayCreateTitle`, `shootingDayDate`, `shootingDayErrorGeneric`, `shootingDayErrorNetwork`, `shootingDayLabel`, `shootingDayLabelHint`, `shootingDayMoveEarlier`, `shootingDayMoveLater`, `shootingDayMoveNoRoom`, `shootingDayNew`, `shootingDayNoDate`, `shootingDayPickDate`, `shootingDayRename`, `shootingDayRenameButton`, `shootingDayRenameTitle`, `shootingDayReschedule`, `shootingDaySemantics`, `shootingDayUnschedule`, `shootingDayUnscheduleButton`, `shootingDayUnscheduleMessage`, `shootingDayUnscheduleTitle`, `shootingDayUntitled`, `shootingDayWrapped`, `shootingDaysCreate`, `shootingDaysEmpty`, `shootingDaysFetchError`, `shootingDaysGone`, `shootingDaysReportsLabel`, `shootingDaysStaleBanner` |
| AI import | `aiApplyAcceptAsIs`, `aiApplyBackToImports`, `aiApplyContextEpisode`, `aiApplyContextRemembered`, `aiApplyContinuityGapLeftEmpty`, `aiApplyContinuityGapPicked`, `aiApplyErrorContextMissing`, `aiApplyErrorGeneric`, `aiApplyErrorNetwork`, `aiApplyErrorNotSucceeded`, `aiApplyErrorUnknownContinuityCandidate`, `aiApplyErrorUnresolved`, `aiApplyNoContextSubtitle`, `aiApplyNoContextTitle`, `aiApplyOutcome`, `aiApplyOutcomeScript`, `aiApplyPickEpisode`, `aiApplyReviewCheckbox`, `aiApplySelectionSummary`, `aiApplySubmit`, `aiApplyTitle`, `aiApplyUnappliedOutfit`, `aiApplyUnappliedReasonBindingRejected`, `aiApplyUnappliedReasonCharacterNotPlanned`, `aiApplyUnappliedReasonCharacterUnavailable`, `aiApplyUnappliedReasonCreateRejected`, `aiApplyUnappliedReasonNotesRejected`, `aiApplyUnappliedReasonPieceRejected`, `aiConfigActiveTitle`, `aiConfigApiKeyLabel`, `aiConfigAssistantModelLabel`, `aiConfigCleanup`, `aiConfigDecisionApiKeyLabel`, `aiConfigDecisionDisabled`, `aiConfigDecisionHint`, `aiConfigDecisionKeyMissing`, `aiConfigDecisionKeyRemembered`, `aiConfigDecisionModelLabel`, `aiConfigDecisionProviderLabel`, `aiConfigDecisionSameKey`, `aiConfigDecisionSectionTitle`, `aiConfigDefaultPromptNote`, `aiConfigDiscoveryError`, `aiConfigErrorAdmin`, `aiConfigErrorChanged`, `aiConfigErrorDisabled`, `aiConfigErrorGeneric`, `aiConfigErrorNetwork`, `aiConfigErrorOrphaned`, `aiConfigErrorProvider`, `aiConfigFirstRunBody`, `aiConfigImageModelLabel`, `aiConfigImageSuffix`, `aiConfigKeyMissing`, `aiConfigLiteracyBody`, `aiConfigLiteracyTitle`, `aiConfigModelCatalogUnavailable`, `aiConfigNoModel`, `aiConfigNoProviders`, `aiConfigNotConfigured`, `aiConfigPrefillHint`, `aiConfigProviderLabel`, `aiConfigProviderPrefix`, `aiConfigProvidersUnavailable`, `aiConfigProviderUnavailable`, `aiConfigRecheck`, `aiConfigResetPrompt`, `aiConfigRevokeBody`, `aiConfigRevokeButton`, `aiConfigRevokeTitle`, `aiConfigSaveChanges`, `aiConfigSaveConfiguration`, `aiConfigSchedulePromptLabel`, `aiConfigScriptPromptLabel`, `aiConfigStoredPromptNote`, `aiConfigTitle`, `aiConfigUnresolvedBody`, `aiConfigUnresolvedTitle`, `aiDecisionClientUnavailable`, `aiDecisionModelUnnamed`, `aiDecisionNotRecorded`, `aiDecisionRan`, `aiDecisionScoringFailed`, `aiDecisionSkippedNoConfig`, `aiDecisionSkippedNotApplicable`, `aiDecisionUnavailable`, `aiEpisodePickerEmpty`, `aiEpisodePickerError`, `aiEpisodePickerTitle`, `aiImportConfigure`, `aiImportDisclosureBody`, `aiImportDisclosureTitle`, `aiImportDocMissing`, `aiImportNoFile`, `aiImportOrPickFile`, `aiImportPasteLabel`, `aiImportPickCsvPdf`, `aiImportPickPdf`, `aiImportSchedule`, `aiImportScheduleHint`, `aiImportScopeMismatch`, `aiImportScript`, `aiImportScriptHint`, `aiImportStampWarning`, `aiImportSubmit`, `aiImportTargetHint`, `aiImportTargetLine`, `aiImportTargetLoading`, `aiImportTargetNoBlocks`, `aiImportTargetNoSeason`, `aiImportTargetNotRecorded`, `aiImportTargetPickBlock`, `aiImportTargetTitle`, `aiImportTargetUnknownBlock`, `aiImportTargetUnknownSeason`, `aiImportTitle`, `aiJobCheckAgain`, `aiJobDuplicate`, `aiJobEpisodesSeenLabel`, `aiJobEpisodesSeenValues`, `aiJobRetryBudget`, `aiJobReviewPreview`, `aiJobsActiveBadge`, `aiJobsEmpty`, `aiJobsEmptyCta`, `aiJobsLoadError`, `aiJobsRowApplied`, `aiJobsRowEpisodeMore`, `aiJobsRowEpisodeNumber`, `aiJobsRowEpisodeNumberName`, `aiJobsRowKindEpisode`, `aiJobsRowSubtitle`, `aiJobsTitle`, `aiJobTitle`, `aiPreviewAiBanner`, `aiPreviewAiNote`, `aiPreviewAiNoteScored`, `aiPreviewContinuityCandidateConfidence`, `aiPreviewContinuityCandidateContinued`, `aiPreviewContinuityCandidateInferred`, `aiPreviewContinuityGapPrompt`, `aiPreviewContinuityGapTitle`, `aiPreviewContinuityKeepEmpty`, `aiPreviewCreate`, `aiPreviewFallbackTitle`, `aiPreviewFilterAll`, `aiPreviewFilterLowScore`, `aiPreviewKindUnknown`, `aiPreviewLoadError`, `aiPreviewMergedSubtitle`, `aiPreviewMergedTitle`, `aiPreviewMissing`, `aiPreviewOutfitFor`, `aiPreviewOutfitHeading`, `aiPreviewOutfitOriginContinued`, `aiPreviewOutfitOriginContinuedNoScene`, `aiPreviewOutfitOriginDerived`, `aiPreviewOutfitOriginExplicit`, `aiPreviewOutfitOriginInferred`, `aiPreviewOutfitPieces`, `aiPreviewOutfitQuote`, `aiPreviewOutfitRejectedStatus`, `aiPreviewOutfitToggleTooltip`, `aiPreviewRowRef`, `aiPreviewSceneScore`, `aiPreviewSceneWithSummary`, `aiPreviewScheduledRowCount`, `aiPreviewScheduleSubtitle`, `aiPreviewScheduleTitle`, `aiPreviewScoringFailed`, `aiPreviewScriptSubtitle`, `aiPreviewScriptTitle`, `aiPreviewShootingDayScore`, `aiPreviewSkip`, `aiPreviewSynopsisScore`, `aiPreviewTitle`, `aiPreviewUncertainty`, `aiPreviewUnmatchedScheduleRow`, `aiPreviewUnmatchedScriptScene`, `aiPreviewUnrecognizedShape`, `aiPreviewUnscheduled`, `aiPreviewUpdate`, `aiPreviewUpdatesScene`, `aiProvenanceBadge`, `aiScenePickerEmpty`, `aiScenePickerError`, `aiScoreStarsLabel`, `aiUploadDisabled`, `aiUploadGeneric`, `aiUploadNetwork`, `aiUploadPermissions`, `aiUploadScopeMissing`, `aiUploadTooLarge`, `aiUploadUnsupported`, `jobStatusDeadLetter`, `jobStatusFailed`, `jobStatusPayloadUnavailable`, `jobStatusPending`, `jobStatusRunning`, `jobStatusSucceeded`, `jobStatusUnknown`, `jobWatchExhausted`, `jobWatchForbidden`, `jobWatchGeneric`, `jobWatchNetwork`, `jobWatchNotFound` |
| Errors & shared | `problemAuthzSessionRequired`, `reconcileStaleWarning` |
| Other | `createSeasonTitle`, `createSeasonTitleLabel`, `fatalConfigBody`, `fatalConfigTitle`, `planningActiveJobRow`, `planningImportSubtitle` |
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
| `face` | **Cast** | Navigation shell destination 1 of 3 (issue #610) — the actor roster AND the costume surface (season-scoped), plus the costume-category vocabulary on its app bar | `nav.cast` |
| `menu_book` | **Script** | Navigation shell destination 2 of 3 (issue #610) — the active season's chronological scene overview, continuously numbered | `nav.script` |
| `calendar_month` | **Schedule/Dispo** | Navigation shell destination 3 of 3 (issue #610) — the active season's shooting days in calendar order | `nav.schedule` |
| `add` (extended FAB) | **Erstellen** | Navigation shell's ONE plus action (issue #612, Spotify-style): an extended FAB visible in all three morphologies — docked above the bottom bar (compact), floating at the content's bottom-right (medium/expanded). An ACTION, not a destination — the destination contract (3 tabs, `shell-destination-*` keys) stays untouched. Auth-gated (only for a resolved session); opens the quick-create sheet | `shellPlusFabLabel` |
| `smart_toy_outlined` | **Import** | Quick-create sheet entry 1 of 2 (issue #612): the sheet → push deep-link to the existing AI-import submit flow (never embeds it; the submit controller gates internally) | `navAiImport` + `quickCreateAiImportSubtitle` |
| `rocket_launch_outlined` | **Season-Setup** | Quick-create sheet entry 2 of 2 (issue #612): the guided season setup wizard deep-link (sheet → push). Sheet asks „Was möchtest du erstellen?“; context-sensitive entries land later | `wizardTitle` + `quickCreateWizardSubtitle` (sheet title `quickCreateTitle`) |
| `view_agenda_outlined` | **Neue Szene** | Quick-create sheet context entry (issue #624): shown only when an active-episode scope is set; pushes the full-screen create scene page for that episode (never a modal) | `quickCreateSceneTitle` + `quickCreateSceneSubtitle` |
| `calendar_month_outlined` | **Neuer Drehtag** | Quick-create sheet context entry (issue #624): shown only when an active-episode scope is set; pushes the full-screen create shooting-day page for that episode | `quickCreateShootingDayTitle` + `quickCreateShootingDaySubtitle` |
| `person_outline` | **Figuren** / **Looks** | Cast view's roster/look switch (issue #610; segment re-termed by issue #739 — a scene casts a LOOK, garments are only its ingredients): the two segments switch between the season-scoped character surface (with each character's looks) and the garment wardrobe; both labels always visible | `cast.segment.characters` / `cast.segment.outfits` |
| `style_outlined` | **Kostüm-Kategorien** | Cast view toolbar action (issues #610/#638): the season-scoped costume-category vocabulary. **Explicitly NOT part of the profile/settings menu** — costume content lives with costumes and characters | `cast.categories.tooltip` |
| `checkroom_outlined` | **Fundus** | Cast view toolbar action (issues #625/#638): the **cross-season costume fundus** browse surface — a SEPARATE surface, deliberately NOT a fifth OmniSearch chip (OmniSearch stays exactly four chips + active-season scope). Season filter chips + a name prefilter over the costume notes/category; every row deep-links to the costume detail scoped to a repertoire season | `fundusTooltip` |
| `account_circle_outlined` | **Menü** | Profile affordance, LEFT-MOST in the shell's sticky top bar row 1 (issue #638; formerly one per view root's app bar, issue #610): the dissolved Mehr destination's entries — identity, Über die App, Einstellungen, Abmelden. Opens the settings screen inside the active destination's navigator | `profile.tooltip` |
| `check_circle` / `warning_amber_rounded` / `report` / `cloud_off` | **Backend bereit** / **Backend eingeschränkt** / **Backend gestört** / **Backend nicht erreichbar** | Account drawer backend health pill (issue #657; tappable since issue #730): the top-of-drawer quality signal derived from the public `GET /v1/health` readiness report. One row per tier — status icon + DTCG semantic status token + visible localized label (never color alone); the WHOLE pill is the tap target and opens the health detail sheet (`health.pill.open` is its screen-reader hint), so the pill stays a compact chip instead of a full-width banner | `health.pill.healthy` / `health.pill.degraded` / `health.pill.unhealthy` / `health.pill.offline` + `health.pill.open` |
| `report` (per-check status icon) | **Datenbank** / **Ereignisspeicher** / **Geheimnisverwaltung** / **KI-Dateispeicher** / **Weitere Abhängigkeit** | Backend health detail sheet (issue #730): functional, **topology-free** per-dependency labels — the backend's wire check keys (`postgres`, `sierradb`, `vault`, `garage`) are never rendered, unknown keys fall back to the generic label. Every row pairs the label with a visible localized status word and a status icon (`check_circle` bereit / `warning_amber_rounded` eingeschränkt / `report` gestört); the backend's sanitized English `description` is not displayed | `health.check.database` / `health.check.eventStore` / `health.check.secrets` / `health.check.aiStorage` / `health.check.other` + `health.check.status.healthy` / `health.check.status.degraded` / `health.check.status.unhealthy` |
| — *(no icon)* | **Backend-Status** / **Abhängigkeiten** / **Der Server meldet keine Details zu den Abhängigkeiten.** / **Der Server ist nicht erreichbar. Sobald die Verbindung wieder steht, wird der Status erneut abgefragt.** / **Status wird abgefragt …** | Backend health detail sheet (issue #730): sheet headline, dependency group header and the three explanatory bodies — a reported tier without `entries`, the offline tier (nothing was measured) and the first-probe-in-flight state. The sheet asserts no tier nobody measured | `health.detail.title` / `health.detail.dependencies` / `health.detail.empty` / `health.detail.offline` / `health.detail.pending` |
| `search` | **Suche** | Shell top-bar search affordance (issues #613/#616; row 2 trailing in #638): opens the OmniSearch surface (facet search over the active season's client cache) from anywhere inside the shell; never a bottom-bar destination | `omniSearch.tooltip` |
| `video_collection_outlined` | **{Season-Titel}** | Location strip segment — season level. Shell-owned hierarchy context strip (issue #548): icon AND visible text per segment, icons reinforce only; the strip is one merged semantics node announcing the full path | `locationStrip` |
| `folder_outlined` | **Block {n}** | Location strip segment — block level (`blockTileLabel`); compact ≤ 3, medium/expanded ≤ 4 segments, narrow widths collapse to the LAST segments | `locationStrip` |
| `movie_creation_outlined` | **{Episodenname / Episode n}** | Location strip segment — episode level (`episodeTileLabel` fallback) | `locationStrip` |
| `view_agenda_outlined` | **{Zusammenfassung / Szene n}** | Location strip segment — scene level (`sceneTileLabel` fallback) | `locationStrip` |
| `filter_alt_outlined` | **Filter: Block {n}** / **Filter: Block unbekannt** / **Filter gilt hier nicht – andere Season** / **Block wählen** | Block scope pill (issues #548/#638): the sticky active-block filter as a fully rounded pill, SEPARATE from the per-route strip; a set level is filled with the block container color, an unset level (season active, no block) is neutral and opens the block picker for the active season; a label-less scope backfills its number cache-only. Appears once a season is active | `scopeChip` / `scopeChip.unknown` / `scopeChip.foreignSeason` / `scopeChip.blockUnset` / `scopeChip.pick` |
| `movie_creation_outlined` | **{Episodenname / Episode n}** / **Filter gilt hier nicht – andere Season** / **Episode wählen** | Episode scope pill (issues #624/#638): the sticky active-episode target the quick-create entries act on; a set level is filled with the episode container color, an unset level (block scoped, no episode) is neutral and opens the episode picker for the scope block. Appears once a block is scoped; sits next to the season and block pills in the shell's first top-bar row | `episodeChipTooltip` / `episodeChipPickTitle` / `episodeChipEmpty` / `episodeChipUnset` / `episodeChipUnsetTooltip` |
| `video_collection_outlined` | **Season: {Titel/Nr}** / **Season wählen** | Season scope pill (issues #610/#638): the shell-owned season scope as a fully rounded pill SEPARATE from the per-route strip and from the block pill; ALWAYS present — neutral ("Season wählen") when no season is active, filled with the season container color otherwise — because it is also the only affordance that can SET a season; tap opens the season scope picker. The Season DESTINATION is dissolved — this pill is the sticky answer to „which season am I working in?" | `scopeChip.season` / `scopeChip.season.tooltip` / `scopeChip.seasonUnset` |
| `video_library_outlined` | **Seasons verwalten** | Season scope picker entry (issue #610): pushes the seasons overview (create/manage seasons) — the Season tab's former job | `seasonScope.manageSeasons` |
| `account_tree_outlined` | **Produktion verwalten** | Season scope picker entry (issue #610): pushes the production overview — the hierarchy spine (Block→Episode→Szene), the AI-import entry and the active-import-jobs row formerly on the Planen destination | `seasonScope.manageProduction` |
| — *(no icon)* | **Noch keine Seasons vorhanden.** | Season scope picker empty state (the picker has nothing to pick yet — a narrative, never an error) | `seasonScope.empty` |
| — *(no icon)* | **Wähle eine Season, um Kleidungsstücke und Figuren zu sehen.** / **Season wählen** | Season-selection empty state + CTA of the view roots with no active season; the CTA opens the season scope picker | `cast.noSeason` / `cast.pickSeason` |
| — *(no icon)* | **Noch keine Szenen in dieser Season.** | Script view empty state | `script.noScenes` |
| `warning_amber_outlined` | **Teilweise geladen: {n} Episoden konnten nicht gelesen werden.** / **Teilweise geladen: {n} Blöcke konnten nicht gelesen werden.** | Partial-load notice of the Script and Schedule/Dispo views (issue #610): the client-side fan-out failed at BLOCK level (episode list unreadable) or EPISODE level (scenes/days unreadable) — one notice per failed level, naming the level honestly (a block id is never counted as an episode). A shortened list is NEVER presented as the complete one | `script.partialLoad` / `script.partialBlocks` / `schedule.partialLoad` / `schedule.partialBlocks` |
| — *(no icon)* | **Szene {n}** / **Szene ohne Nummer** / **Episode {episode}** | Script view row label (projected scene number as the visible label; unnumbered scenes say so instead of jumping the queue) and the row's episode subtitle | `script.sceneNumber` / `script.sceneNumberUnknown` / `script.episodeLabel` |
| — *(no icon)* | **Für diese Season sind noch keine Drehtage geplant.** | Schedule/Dispo view empty state | `schedule.noDays` |
| — *(no icon)* | **Drehtag {date}** / **Drehtag ohne Datum** | Schedule/Dispo row label (server label wins; the date is the fallback) | `schedule.dayLabel` / `schedule.dayUndated` |
| — *(no icon)* | **Blöcke und Episoden der aktiven Season** | Production overview subtitle (the scope the spine lists) | `production.blocksSubtitle` |
| `add` (FAB) | **Kleidungsstück erstellen** | Wardrobe FAB; selecting the action reveals the inline piece editor (a garment carries no character binding since the Piece/Outfit split) | `piece.add` (`pieceAddFab`) |
| `style_outlined` | **Ohne Kategorie / Kategorie** | Piece tile uses the resolved category icon; unknown categories use this deterministic fallback; category text stays visible. **Every category display shows the icon next to the visible text** (issue #543): grid tile, editor category row, and the picker options — the same name-based resolution (`forCostumeCategory`), never icon-only. **The same icon-reinforces-text rule applies to the location strip segments** (issue #548): each strip segment renders its level icon (`locationSeason/Block/Episode/Scene`) next to the visible segment label — the icon never replaces the label | `categories.icon` |
| `subject` / detail text | **Bezeichnung / Beschreibung** | Piece identity overlay: the aggregate's required `name` is the identity; a legacy row without one falls back to the first detail subject, then notes, never the UUID | `piece.tile.name` (`pieceTileLabel` / `pieceTileLabelFallback`) |
| `edit` / `delete` | **Bearbeiten** / **Löschen** | Piece detail row trailing actions (inline editor opens on edit; delete ALWAYS asks via a confirm dialog — destructive rule `common.delete`) | `commonEdit` / `commonDelete` |
| `＋` / `save` | **Detail hinzufügen** / **Speichern** | Piece detail editor: `＋` create row opens the inline editor in create mode; save disabled while the required `text` is empty (`*`-marked required label vs. `(optional)` subject helper) | `costumeDetail.addDetail` / `commonSave` |
| *(resolved per category)* | **Kategorie wählen** | Piece editor identity section: bottom-sheet picker, one icon + visible text row per non-archived season category, plus the „Ohne Kategorie" clear row (issue #543) | `costumeDetail.pickCategory` |
| — *(no icon)* | **Kleidungsstück gespeichert** | Visible confirmation after a successful detail or notes save | `pieceDetailSaved` |
| `—` *(no icon)* | **Foto löschen?** | Photo delete confirmation (piece detail, outfit detail / continuity strip) | `photos.delete` |
| `—` *(no icon)* | **Kategorie/Foto-Fehler** | Code-keyed command-error narratives for costume and photo surfaces (never backend `detail`) | `costumes.photos.errors` |
| `—` *(no icon)* | **Berichte (Soll-Ist/PDF)** | Reports screen title, Soll-Ist rows, PDF cards | `reports.*` |
| `—` *(no icon)* | **verschoben / fehlend / übersprungen / erneut gedreht** | Soll-Ist flag chips (render projection verbatim, D2) | `reports.flags` |
| `—` *(no icon)* | **KI-Import-Konfiguration** | AI config screen + code-keyed error narratives (admin role, vault, provider) | `aiConfig.*` |
| `—` *(no icon)* | **KI-Import / Vorschau / Anwenden** | Import submit, preview, apply + job status screens | `aiImport.*` |
| `—` *(no icon)* | **Wartet / In Arbeit / Bereit / Fehlgeschlagen** | AI job status matrix (honest copy, D2) | `aiImport.jobStatus` |
| `smart_toy_outlined` | **KI-Verarbeitung** | Import submit screen — the PERSISTENT point-of-interaction disclosure card, scroll-ordered above the submit action (never skippable) | `aiImport.disclosure` |
| `smart_toy_outlined` | **KI-extrahierter Inhalt – sorgfältig prüfen** | Preview screen banner — the AI framing above every typed payload; notes that the wire carries no machine-verified confidence values | `aiImport.previewBanner` |
| `—` *(no icon)* | **Ich habe den KI-extrahierten Inhalt geprüft** | Apply review acknowledgement checkbox — gates the apply dispatch (EU AI Act Art. 50) | `aiImport.reviewAck` |
| `smart_toy_outlined` | **KI-extrahiert** | Provenance badge — one persistent chip per AI-derived day/scene row (day list, day picker, Soll/Ist board, scene tiles) | `ai.transparency.badge` |
| `smart_toy_outlined` | **Über KI in der App** | Dedicated About-AI disclosure screen (doorway from the About dialog AI notice): purpose, data flow, configured provider/model naming, 7-day payload retention, EU AI Act reference, source link | `ai.transparency.disclosure` |
| `psychology_alt_outlined` | **KI-Kompetenz** | AI-config screen helper card for the operating admin (EU AI Act Art. 4 support) | `aiConfig.literacy` |
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
| `rocket_launch_outlined` (FAB) | **Season-Setup starten** | Seasons extended FAB — the PRIMARY create entry (guided wizard), available in every state | `seasons.create.fab` |
| `—` *(no icon)* | **Manuell** | Seasons app-bar text action — the SECONDARY (advanced) create path: the manual number/title sheet | `seasons.create.manual` |
| `—` *(no icon)* | **{n} Blöcke** | Season card metadata — cached block count (omitted when no cache entry) | `seasons.meta.blocks` |
| `—` *(no icon)* | **{n} Szenen** | Season card metadata — cached scene count (omitted when no cache entry) | `seasons.meta.scenes` |
| `—` *(no icon)* | **{n} Kleidungsstücke** | Season card metadata — cached piece count (omitted when no cache entry) | `seasons.meta.pieces` (`seasonsMetaPieces`) |
| `—` *(no icon)* | **Noch keine Seasons** | Seasons home empty-state headline | `seasons.empty.title` |
| `—` *(no icon)* | **Lege deine erste Season an — oder importiere einen bestehenden Spielplan per KI.** | Seasons home empty-state guidance sentence | `seasons.empty.guidance` |
| `rocket_launch_outlined` | **Season-Setup starten** | Seasons home empty-state setup CTA (the wizard's entry route) | `seasons.empty.setupCta` |
| `smart_toy_outlined` | **KI-Import öffnen** | Seasons home empty-state import CTA — jumps to the Mehr tab's labeled Import entry | `seasons.empty.importCta` |
| `add` (FAB) | **Block hinzufügen** | Blocks FAB (same icon, per-screen label) | `blocks.create` |
| `—` *(no icon)* | **Block erstellen** | Create-block dialog/sheet title (ephemeral form, IDs from navigation context) | `blocks.create.title` |
| `—` *(no icon)* | **Noch keine Blöcke** | Blocks list empty state | `blocks.empty` |
| `—` *(no icon)* | **Ersten Block erstellen** | Blocks empty-state create CTA | `blocks.create.first` |
| `—` *(no icon)* | **Zurück zu den Staffeln** | Deleted-parent (404) back affordance | `blocks.notFound.back` |
| `—` *(no icon)* | **Staffel {n}** | Season-number fallback title on the blocks AppBar | `blocks.seasonNumber` |
| `—` *(no icon)* | **Einstellungen** | Mehr-tab tile (issue #516: pushes the settings screen — no dialog) and screen app-bar title | `settings.title` |
| `—` *(no icon)* | **Allgemein** | Settings screen — general app-settings section header (every flavor) | `settings.general` |
| `celebration_outlined` | **Easter-Eggs verwalten** | Settings (general section) — Easter-eggs entry tile pushing the dedicated Easter-eggs screen (issue #708, the counter-model of the AI-configuration entry #643) | `settings.easterEggsEntryTitle` |
| `—` *(no icon)* | **Schalter und Vorschau für jedes Ei.** | Settings (general section) — Easter-eggs entry tile explanatory line (issue #708) | `settings.easterEggsEntrySubtitle` |
| `—` *(no icon)* | **Easter-Eggs** | Easter-eggs screen — app-bar title (issue #708) and per-egg switches group header (default ON, issue #615) | `settings.easterEggsScreenTitle` / `settings.easterEggs` |
| `—` *(no icon)* | **Kleine Überraschungen in der App lassen sich ein- und ausschalten.** | Easter-eggs screen — switches group explanatory line (issue #708: moved from Settings) | `settings.easterEggsSubtitle` |
| `checkroom` | **Karl Kleiderbügel** | Easter-eggs screen — Karl Kleiderbügel egg switch (default ON) | `settings.easterEggsKarlKleiderbuegel` |
| `—` *(no icon)* | **Der Kleiderbügel-Assistent hilft im KI-Import mit Tipps und Sprüchen.** | Easter-eggs screen — Karl Kleiderbügel egg description | `settings.easterEggsKarlKleiderbuegelSubtitle` |
| `pets_outlined` | **Déjà-vu-Katze** | Easter-eggs screen — Deja-vu Cat egg switch (default ON; October-only effect) | `settings.easterEggsDejavuCat` |
| `—` *(no icon)* | **Im Oktober läuft eine schwarze Katze über den Startbildschirm und durch die leere Season-Liste. In der Vorschau hier ist sie jederzeit zu sehen.** | Easter-eggs screen — Deja-vu Cat egg description (issue #640: surfaces = splash + empty seasons home + gallery preview) | `settings.easterEggsDejavuCatSubtitle` |
| `—` *(no icon)* | **Vorschau** | Easter-eggs screen — gallery preview label (per-egg replay/preview regardless of month, issue #640; moved from Settings, issue #708) | `settings.easterEggsPreview` |
| `—` *(no icon)* | **Jedes Ei lässt sich hier in Ruhe ansehen — unabhängig vom Monat.** | Easter-eggs screen — gallery explanatory line (moved from Settings, issue #708) | `settings.easterEggsPreviewSubtitle` |
| `—` *(no icon)* | **Entwicklung** | Settings screen — dev-only section header (backend switch flow lives here) | `settings.dev` |
| `—` *(no icon)* | **Backend-URI** | Settings (dev) — editable backend-URI field label | `settings.backendUri` |
| `—` *(no icon)* | **Speichern** | Settings (dev) — save override action | `settings.save` |
| `—` *(no icon)* | **Zurücksetzen** | Settings (dev) — reset-to-default action | `settings.reset` |
| `—` *(no icon)* | **Die Serveradresse wird von deiner Organisation sicherheitsbedingt festgelegt und kann hier nicht geändert werden.** | Settings (prod) — explanatory note for the absent editor (store compliance) | `settings.prodNote` |
| `—` *(no icon)* | **KI** | Settings — AI section header (every flavor), grouping the AI-configuration entry (#643) and the AI-imports entry (#644) | `settings.ai` |
| `psychology_alt_outlined` | **KI-Konfiguration** | Settings (AI section) — central AI-configuration entry pushing `AiConfigScreen` (issue #643); visible only while the season-scoped membership resolves to an active costume-dept role | `settings.aiConfig` |
| `—` *(no icon)* | **KI-Anbieter und Modelle für den KI-Import verwalten.** | Settings (AI section) — AI-configuration entry explanatory line (issue #643) | `settings.aiConfigSubtitle` |
| `list_alt_outlined` | **KI-Import-Aufträge** | Settings (AI section) — persistent entry pushing the AI-import jobs list (route name `ai-import-jobs`, issue #644); NO client-side role gate — the read-only route's fetch seam resolves the session before the call and the tile dispatches no command | `settings.aiImports` + `settings.aiImportsSubtitle` |
| `—` *(no icon)* | **Status deiner KI-Importe ansehen.** | Settings (AI section) — AI-imports entry explanatory line (issue #644) | `settings.aiImportsSubtitle` |
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
| `summarize_outlined` | **Berichte** | Scene-shoot Day-Board → reports entry (Soll/Ist). Icon **and** always-visible label (glossary visible-label norm, issue #549); the label moves into a labelled overflow item — never icon-only — when the app bar is too narrow | `sceneShootsReportsLabel`, `sceneShootsReportsTooltip` |
| `more_vert` | *(overflow affordance)* | Day-Board → reports entry, shown only when the app bar cannot carry the visible label; the menu item itself is labelled **Berichte** | `sceneShootsReportsLabel` |
| `summarize_outlined` | **Berichte** | Shooting-Days-Screen → Episoden-Berichtsindex (Liste der Drehtage mit `Abschließend`/`Offen`, Tippen öffnet den Tagesbericht). Icon **and** always-visible label (glossary visible-label norm); the label moves into a labelled overflow item — never icon-only — when the app bar is too narrow. Kein Berichtsinhalt auf dem Index (D8) | `shootingDaysReportsLabel`, `reportsIndexTitle`, `reportsIndexDayFinal`, `reportsIndexDayOpen`, `reportsIndexEmpty` |
| `more_vert` | *(overflow affordance)* | Shooting-Days-Screen → Berichtsindex-Eintrag, shown only when the app bar cannot carry the visible label; the menu item itself is labelled **Berichte** | `shootingDaysReportsLabel` |
| `event_busy` | **Termin entfernen** | Scene detail — remove shooting-day assignment | `scenes.unschedule` |
| `unfold_more` | **Alle Szenen anzeigen** | Scene-shoots list — expand collapsed sections | `sceneShoots.expand` |
| `event_available` | **Drehtag abschließen** | Wrap-day confirmation (final, read-only) | `sceneShoots.wrap` |
| `—` *(no icon)* | **Start / Abschließen / Überspringen** | Per-shoot execution actions | `sceneShoots.actions` |
| `unfold_more` | **Tatsächliche Reihenfolge festlegen… / Geplante Position ändern…** | Per-shoot order menu | `sceneShoots.order` |
| `—` *(no icon)* | **Notizen ({n})** | Shoot note list / add / edit / delete | `sceneShoots.notes` |
| `—` *(no icon)* | **In Arbeit / Abgedreht / Übersprungen / Geplant** | Ist status chip (projection verbatim, D2) | `sceneShoots.status` |
| `—` *(no icon)* | **Für diesen Tag sind noch keine Szenen-Drehs geplant.** | Day-board empty state | `sceneShoots.empty` |
| `add` (FAB) | **Episode hinzufügen** | Episodes FAB (same icon, per-screen label) | `episodes.create` |
| `—` *(no icon)* | **Episode {n}** | Episode list tile fallback title (named episodes use the stored name) | `episodes.tile` |
| `—` *(no icon)* | **Nummer {n}** | Episode tile subtitle | `episodes.tile.number` |
| `—` *(no icon)* | **Noch keine Episoden** | Episodes list empty state | `episodes.empty` |
| `—` *(no icon)* | **Erste Episode erstellen** | Episodes empty-state create CTA | `episodes.create.first` |
| `—` *(no icon)* | **Zurück zu den Blöcken** | Deleted-parent (404) back affordance | `episodes.notFound.back` |
| `—` *(no icon)* | **Episode erstellen** | Create-episode dialog/sheet title | `episodes.create.title` |
| `add` (FAB) | **Szene hinzufügen** | Scenes FAB (same icon, per-screen label) | `scenes.create` |
| `—` *(no icon)* | **Szene {id}** | Scene tile fallback title (summaries render when present) | `scenes.tile` |
| `—` *(no icon)* | **Ort: {v} / Tag: {v}** | Scene tile metadata (the mood left the joined meta string in #721 — it renders as its own reinforcing icon + text line below) | `scenes.tile.meta` |
| `home_outlined` (I) / `park_outlined` (A) / `sensor_door_outlined` (I/A) + `wb_sunny_outlined` (T) / `dark_mode_outlined` (N) / `wb_twilight_outlined` (D, M) / `bedtime_outlined` (AB) | **I/T** (the canonical set shorthand itself) | Scene mood reinforcement (issue #721): the interior/exterior + time-of-day icons render NEXT TO the visible shorthand text on scene detail, script overview tiles and AI preview rows — icons reinforce only, they never replace the text, and a scene without a mood renders no line at all | `sceneMood` |
| `—` *(no icon)* | **Eingeplant / Nicht eingeplant** | Scene schedule state | `scenes.tile.schedule` |
| `—` *(no icon)* | **Noch keine Szenen** | Scenes list empty state | `scenes.empty` |
| `—` *(no icon)* | **Erste Szene erstellen** | Scenes empty-state create CTA | `scenes.create.first` |
| `—` *(no icon)* | **Zurück zu den Episoden** | Deleted-parent (404) back affordance | `scenes.notFound.back` |
| `—` *(no icon)* | **Szene erstellen** | Create-scene dialog/sheet title | `scenes.create.title` |
| `more_vert` | **Mehr** | Overflow menu (seasons, shooting days) | `common.overflow` |
| `settings_outlined` | **Einstellungen** | Mehr-tab settings entry; AI-import config | `common.settings` |
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
| `—` *(no icon)* | **Es sieht so aus, als wolltest du einen Spielplan importieren…** | Karl Kleiderbügel (Easter egg, AI Import) — no-config allusion offering the AI-config entry | `aiImport.clippy.noConfig` |
| `—` *(no icon)* | **Ich bin ganz Ohr!** | Karl Kleiderbügel — import-job-running reaction (excited swing pose) | `aiImport.clippy.running` |
| `—` *(no icon)* | **Hmm, lass mich kurz überlegen…** | Karl Kleiderbügel — job queued (not yet running) reaction (thinking pose, issue #614) | `aiImport.clippy.queued` |
| `—` *(no icon)* | **Das hat leider nicht geklappt. Aber gemeinsam kriegen wir das hin!** | Karl Kleiderbügel — error consolation (droop pose) | `aiImport.clippy.error` |
| `—` *(no icon)* | **Klasse! Der Import sitzt wie maßgeschneidert.** | Karl Kleiderbügel — success praise (proud pose) | `aiImport.clippy.success` |
| `—` *(no icon)* | *(fixed joke set of five)* | Karl Kleiderbügel — idle jokes from the Clippy canon (`aiImport.clippy.idle1..5`, issue #614) | `aiImport.clippy.idle` |
| `pets_outlined` | *(no copy — pure animation)* | Deja-vu Cat — original black cat crossing the splash in October (issue #615; no caption) | *(splash-only egg)* |
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
| `—` *(no icon)* | **Diese App wurde ohne DEFAULT_PROJECT_ID gebaut: …** | Build-misconfiguration notice — shared by the wizard's pre-dispatch guard and the manual create sheet (the project is derived, never typed) | `seasons.create.seriesIdMissing` |
| `quickcheck.title` *(template example)* | **Schnell-Check** | Screen-spec template example screen (fictional `CostumeQuickCheck`) | `quickcheck.title` |
| `quickcheck.empty` *(template example)* | **Keine Figuren in dieser Szene** | Template example screen — empty state | `quickcheck.empty` |

| `check_box` / `check_box_outline_blank` | **Looks (n)** — `{character}: {name}` + **Beleg: {quote}** + **Kleidungsstücke: …** | AI-Import-Vorschau: die extrahierten Looks einer Draft-Zeile, jeder Eintrag einzeln übernehmbar/ablehnbar; das Zitat ist die grounding-Evidenz neben dem Look (Review ohne Dokument öffnen), die daraus abgeleiteten Kleidungsstücke stehen daneben und sind nicht einzeln entscheidbar | `aiPreviewOutfitHeading`, `aiPreviewOutfitFor`, `aiPreviewOutfitQuote`, `aiPreviewOutfitToggleTooltip`, `aiPreviewOutfitPieces` |
| `—` *(no icon, error color)* | **verworfen** | Status-Suffix unter einem abgelehnten Look-Eintrag; die Szene selbst bleibt übernehmbar (Veto pro Look, nicht pro Szene) | `aiPreviewOutfitRejectedStatus` |
| `format_quote` / `auto_awesome_outlined` / `link` / `insights_outlined` | **wörtlich aus dem Skript** / **aus dem Skript abgeleitet** / **übernommen aus Szene {n}** / **aus dem Szenenkontext abgeleitet** | AI-Import-Vorschau: Herkunfts-Badge pro Look (`DraftOutfit.origin`, issue #745). Genau eine Zeile je Ursprung; ein Pass-2-Look (übernommen/abgeleitet) zeigt KEIN Beleg-Zitat, weil er keines hat — ein leeres Zitat würde wie eine Skript-Aussage lesen. Ein fehlender Ursprung (ältere Vorschau) rendert kein Badge | `aiPreviewOutfitOriginExplicit`, `aiPreviewOutfitOriginDerived`, `aiPreviewOutfitOriginContinued`, `aiPreviewOutfitOriginContinuedNoScene`, `aiPreviewOutfitOriginInferred` |
| `—` *(no icon)* | **Garderoben-Lücke · Szene {n} · {character}** + **Fortsetzung: {name} · {n} % Sicherheit** / **Kontext-Look: {name} · {n} % Sicherheit** / **Szene ohne Look lassen** | AI-Import-Vorschau: eine Garderoben-Lücke (Pass 2) mit genau den Looks, die das Skript hergibt — ein Tipp löst sie. Ohne Kandidaten bleibt es bei der reinen Unsicherheits-Notiz (nie eine erfundene Option); die gewählte Auflösung steht als Zusammenfassung an der Anwenden-Karte | `aiPreviewContinuityGapTitle`, `aiPreviewContinuityGapPrompt`, `aiPreviewContinuityCandidateContinued`, `aiPreviewContinuityCandidateInferred`, `aiPreviewContinuityCandidateConfidence`, `aiPreviewContinuityKeepEmpty`, `aiApplyContinuityGapPicked`, `aiApplyContinuityGapLeftEmpty`, `aiApplyErrorUnknownContinuityCandidate` |
| `—` *(no icon)* | **Gespeicherter Prompt aktiv – folgt nicht den Deployment-Voreinstellungen.** / **Kein gespeicherter Prompt – die Deployment-Voreinstellung gilt.** + **Auf Voreinstellung zurücksetzen** | AI-Konfiguration: says per Dokumenttyp, whether a stored prompt overrides the deployment default, and offers the reset (writes the fetched default into the editor; saving persists it) | `aiConfigStoredPromptNote`, `aiConfigDefaultPromptNote`, `aiConfigResetPrompt` |
| `—` *(no icon)* | **Angewendet: n Szene(n), n Figur(en), n Kleidungsstück(e), n Look(s).** + **Nicht angewendet: {character} – {name} ({reason})** | AI-Apply-Ergebnis: a partially applied row must never read as a fully applied one; the reason is localized from the typed wire enum (`UnappliedOutfit.reason`), never parsed out of server prose | `aiApplyOutcomeScript`, `aiApplyUnappliedOutfit`, `aiApplyUnappliedReason*` |

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
| `star` / `star_border` | AI score rating glyphs — the 1–5 star indicator in preview + apply (filled vs. outline pair) | `aiScoreStarsLabel` (`{stars} of 5 stars`) |

### Audit gaps (documentation only — fixed by the redesign changes)

- `checkroom_outlined` (seasons tile) and `checkroom` (costume rows) were
  the same concept with two variants; the four-destination shell
  (`redesign-app-shell-navigation`) unified them on `checkroom`. Issue
  #610 retires the „Kleidung" destination itself: the costume surface now
  lives inside the **Cast** view (visible labels „Figuren"/„Looks"),
  with `checkroom_outlined` as the costume segment's icon.
- `style_outlined` on the Seasons tile violated the visible-label rule
  (icon-only entry); it was removed as an entry point and issue #610 gives
  it its one remaining home — the **Cast** view's labelled **Kostüm-Kategorien**
  app-bar action (costume vocabulary, deliberately NOT in the profile menu).
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
