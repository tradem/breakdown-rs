// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitleBreakdown => 'Breakdown';

  @override
  String get commonRetry => 'Retry';

  @override
  String get costumeCategoriesTitle => 'Costume categories';

  @override
  String get costumeCategoryArchived => 'Archived';

  @override
  String get costumeCategoryAddFab => 'Add category';

  @override
  String get costumeCategoryCreateTitle => 'Create category';

  @override
  String get costumeCategoryNameLabel => 'Name';

  @override
  String get costumeCategoryNameRequired => 'A name is required';

  @override
  String get costumeCategoryRenameTitle => 'Rename category';

  @override
  String get costumeCategoryRenameButton => 'Rename';

  @override
  String get costumeCategoryArchiveTitle => 'Archive category?';

  @override
  String costumeCategoryArchiveMessage(Object name) {
    return '\"$name\" will be hidden from the active vocabulary. Use the Archived toggle to reveal it.';
  }

  @override
  String get costumeCategoryArchiveButton => 'Archive';

  @override
  String costumeCategoriesFetchError(Object code) {
    return 'Could not load categories ($code).';
  }

  @override
  String get costumeCategoriesStaleBanner => 'Cached data may be outdated';

  @override
  String costumeCategoryTileLabel(Object name) {
    return 'Category $name';
  }

  @override
  String get costumeCategoriesTileSyncing => 'Just created — syncing…';

  @override
  String get costumeCategoriesTileSyncingStale =>
      'Created — the list is still catching up. Pull to refresh.';

  @override
  String get shootingDayAddFab => 'Create shooting day';

  @override
  String get shootingDayUnscheduleTitle => 'Unschedule date?';

  @override
  String get shootingDayUnscheduleMessage =>
      'The calendar date is removed. The day keeps its order and label.';

  @override
  String get shootingDayArchiveTitle => 'Archive shooting day?';

  @override
  String get shootingDayArchiveMessage =>
      'Archived days stay in the projection but hide from scheduling pickers.';

  @override
  String get shootingDayMoveNoRoom =>
      'Cannot move here — the neighboring order keys leave no room. Archive or recreate days to rebalance.';

  @override
  String get shootingDayCreateTitle => 'Create shooting day';

  @override
  String get shootingDayLabelHint => 'Label (e.g. 1. Tag)';

  @override
  String get shootingDayNoDate => 'No date yet';

  @override
  String shootingDayDate(Object date) {
    return 'Date: $date';
  }

  @override
  String get shootingDayPickDate => 'Pick date';

  @override
  String get shootingDayRenameTitle => 'Rename shooting day';

  @override
  String get shootingDayLabel => 'Label';

  @override
  String get shootingDayRenameButton => 'Rename';

  @override
  String get shootingDayArchiveButton => 'Archive';

  @override
  String get shootingDayUnscheduleButton => 'Unschedule';

  @override
  String shootingDaysFetchError(Object code) {
    return 'Could not load shooting days ($code).';
  }

  @override
  String get shootingDaysStaleBanner => 'Cached data may be outdated';

  @override
  String get shootingDayErrorNetwork =>
      'Network problem — the change was not saved. Try again.';

  @override
  String shootingDayErrorGeneric(Object code) {
    return 'The shooting day could not be saved ($code).';
  }

  @override
  String get characterAddFab => 'Create character';

  @override
  String get characterCreateTitle => 'Create character';

  @override
  String get characterNameLabel => 'Name';

  @override
  String get characterNameRequired => 'A name is required';

  @override
  String get characterCategoryLabelName => 'Category';

  @override
  String get characterCategoryMain => 'Main cast';

  @override
  String get characterCategoryEditTooltip => 'Change the role type';

  @override
  String get characterCategoryGuest => 'Guest';

  @override
  String get characterCategoryExtra => 'Extra';

  @override
  String charactersFetchError(Object code) {
    return 'Could not load characters ($code).';
  }

  @override
  String get charactersEmpty => 'No characters yet';

  @override
  String charactersGone(Object code) {
    return 'The season is gone ($code).';
  }

  @override
  String get characterDetailTitleFallback => 'Character';

  @override
  String get characterContact => 'Contact';

  @override
  String get characterEmail => 'Email';

  @override
  String get characterPhone => 'Phone';

  @override
  String get characterSaveContact => 'Save contact';

  @override
  String get characterMeasurements => 'Measurements';

  @override
  String get characterSaveMeasurements => 'Save measurements';

  @override
  String characterTileLabel(Object name) {
    return 'Character $name';
  }

  @override
  String get characterTileSyncing => 'Just created — syncing…';

  @override
  String get characterTileSyncingStale =>
      'Created — the list is still catching up. Pull to refresh.';

  @override
  String get charactersStaleBanner => 'Cached data may be outdated';

  @override
  String get characterErrorNetwork =>
      'Network problem — the change was not saved. Try again.';

  @override
  String characterErrorGeneric(Object code) {
    return 'The character could not be saved ($code).';
  }

  @override
  String get pieceErrorChanged =>
      'Changed elsewhere — pull to refresh and try again.';

  @override
  String get pieceErrorForbidden =>
      'You need an active costume role in this season.';

  @override
  String get pieceErrorMembership =>
      'permissions could not be verified — check the connection and retry.';

  @override
  String pieceErrorGeneric(Object code) {
    return 'The piece could not be saved ($code).';
  }

  @override
  String get pieceErrorCategorySeason =>
      'That category belongs to a different season — pick a category from this season.';

  @override
  String get pieceErrorCategoryArchived =>
      'That category is archived — pick an active category.';

  @override
  String get pieceErrorDetailNotFound =>
      'That piece detail no longer exists — the list was refreshed.';

  @override
  String get pieceDetailCategoryTitle => 'Category';

  @override
  String get pieceDetailPickCategory => 'Pick a category';

  @override
  String get pieceDetailCategorySaved => 'Category saved.';

  @override
  String get photoErrorTooLarge =>
      'The image is too large even after resizing.';

  @override
  String get photoErrorUnsupported =>
      'Only JPEG, PNG and WebP photos are supported.';

  @override
  String get photoErrorForbidden =>
      'You need an active costume role in this production to manage photos.';

  @override
  String get photoErrorContainerUnresolved =>
      'This piece has no resolvable container — refresh the wardrobe and try again.';

  @override
  String get photoErrorNetwork =>
      'Network problem — the photo change was not saved. Try again.';

  @override
  String photoErrorGeneric(Object code) {
    return 'The photo could not be saved ($code).';
  }

  @override
  String get photoDeleteTitle => 'Delete photo?';

  @override
  String get photoDeleteMessage =>
      'The photo will be permanently deleted. This cannot be undone.';

  @override
  String get pieceAddFab => 'Create piece';

  @override
  String get piecesStaleBanner => 'Cached data may be outdated.';

  @override
  String piecesFetchError(Object code) {
    return 'Could not load pieces ($code).';
  }

  @override
  String pieceTileLabel(Object id) {
    return 'Piece $id';
  }

  @override
  String get pieceTileLabelFallback => 'Piece';

  @override
  String get costumeCategoryUncategorized => 'Uncategorized';

  @override
  String get pieceDetailSaved => 'Piece details saved.';

  @override
  String pieceDetailsCount(Object count) {
    return '$count details';
  }

  @override
  String piecePhotosCount(Object count) {
    return '$count photos';
  }

  @override
  String get pieceTileSyncing => 'Just saved — syncing …';

  @override
  String get pieceTileSyncingStale =>
      'Created — the list is still catching up. Pull to refresh.';

  @override
  String get piecesEmpty => 'No pieces yet';

  @override
  String get createSeasonTitle => 'Create season';

  @override
  String get createSeasonTitleLabel => 'Title';

  @override
  String reportsTitle(Object label) {
    return 'Reports — $label';
  }

  @override
  String get reportsSollIstTitle => 'Planned vs actual';

  @override
  String get reportsPlannedLabel => 'Planned ';

  @override
  String get reportsActualLabel => 'Actual ';

  @override
  String get reportsCountsUnavailable => 'Scene counts unavailable.';

  @override
  String get reportsFinal => 'Final — this day is wrapped.';

  @override
  String get reportsNoScenes => 'No scenes in this report.';

  @override
  String reportsDayPrefix(Object day) {
    return 'Day $day';
  }

  @override
  String get reportsFlagMoved => 'moved';

  @override
  String get reportsFlagMissing => 'missing';

  @override
  String get reportsFlagSkipped => 'skipped';

  @override
  String get reportsFlagReshot => 'reshot';

  @override
  String get reportsPdfDispo => 'Dispo (planned)';

  @override
  String get reportsPdfShootDay => 'Shoot day (execution)';

  @override
  String get reportsPdfPlannedVsActual => 'Planned vs actual (PDF)';

  @override
  String get reportsPdfSection => 'PDF reports';

  @override
  String get reportsFetch => 'Fetch';

  @override
  String get reportsPreview => 'Preview';

  @override
  String get reportsShare => 'Share';

  @override
  String get reportErrorUnknownStatus =>
      'The report has an unrecognized format — update the app to view it.';

  @override
  String reportErrorUnknownShape(Object code) {
    return 'The report could not be read ($code). Try again.';
  }

  @override
  String get reportErrorPdfTooLarge =>
      'The PDF is too large to preview on this device.';

  @override
  String get reportErrorForbidden => 'You do not have access to these reports.';

  @override
  String get reportErrorMembershipPending => 'Checking report access…';

  @override
  String get reportErrorMembershipUnavailable =>
      'Access check failed — retry to load the reports.';

  @override
  String get reportErrorShareFailed =>
      'Sharing failed — the file was discarded. Try again.';

  @override
  String get reportErrorNetwork =>
      'Network problem — the report was not loaded. Try again.';

  @override
  String reportErrorLoad(Object code) {
    return 'The report could not be loaded ($code).';
  }

  @override
  String get shootingDaysReportsLabel => 'Reports';

  @override
  String reportsIndexTitle(Object episode) {
    return 'Reports — $episode';
  }

  @override
  String get reportsIndexDayFinal => 'Final';

  @override
  String get reportsIndexDayOpen => 'Open';

  @override
  String get reportsIndexEmpty =>
      'Once a shooting day is planned, that day\'s planned-vs-actual (Soll/Ist) report opens from here.';

  @override
  String get shootingDaysReportsAggregateLabel => 'Overall Soll-Ist';

  @override
  String reportsAggregateTitle(Object scope) {
    return 'Planned vs. actual – $scope';
  }

  @override
  String get reportsAggregateFinal => 'Final — every shooting day is wrapped.';

  @override
  String reportsAggregateProvisional(Object total, Object wrapped) {
    return 'Provisional — $wrapped of $total shooting days wrapped.';
  }

  @override
  String reportsAggregateProgress(Object total, Object wrapped) {
    return '$wrapped of $total shooting days wrapped';
  }

  @override
  String get reportsAggregatePdf => 'Planned vs. actual (PDF)';

  @override
  String reportsAggregateSceneLabel(Object number) {
    return 'Scene $number';
  }

  @override
  String get aiConfigErrorAdmin =>
      'Administrator role required — ask your production admin.';

  @override
  String get aiConfigErrorChanged =>
      'Changed elsewhere — refresh and re-apply your edit.';

  @override
  String get aiConfigErrorOrphaned =>
      'The API key could not be removed from the server vault after the failed setup. Retry the cleanup from the configuration screen.';

  @override
  String get aiConfigErrorProvider => 'This provider is unavailable right now.';

  @override
  String get aiConfigErrorProviderMismatch =>
      'This API key does not belong to that provider. Pick the provider the stored key belongs to, or submit a new key.';

  @override
  String get aiConfigErrorDisabled =>
      'AI import is not enabled on this instance. This is a server configuration — nothing to retry here.';

  @override
  String get aiConfigErrorNetwork =>
      'Network problem — the change was not applied. Try again.';

  @override
  String aiConfigErrorGeneric(Object code) {
    return 'The configuration change failed ($code).';
  }

  @override
  String get aiConfigProvidersUnavailable => 'Providers could not be loaded.';

  @override
  String get aiConfigTitle => 'AI import configuration';

  @override
  String get aiConfigKeyMissing => 'Enter the API key first.';

  @override
  String get aiConfigPrefillHint =>
      'Prompt fields are prefilled from the server defaults — you can edit them.';

  @override
  String get aiConfigNotConfigured => 'Not configured yet';

  @override
  String get aiConfigFirstRunBody =>
      'Pick a provider, choose the assistant model and submit your API key. The key is sent to the server vault and never stored on this device.';

  @override
  String get aiConfigApiKeyLabel => 'API key (sent to the server vault)';

  @override
  String get aiConfigSaveConfiguration => 'Save configuration';

  @override
  String get aiConfigNoProviders =>
      'No AI providers are offered on this backend.';

  @override
  String get aiConfigProviderLabel => 'Provider';

  @override
  String get aiConfigAssistantModelLabel => 'Assistant model';

  @override
  String get aiConfigImageModelLabel => 'Image model (optional)';

  @override
  String get aiConfigNoModel => '— none —';

  @override
  String get aiConfigNoImageModels => 'This provider offers no image models.';

  @override
  String get aiConfigProviderUnavailable =>
      'Provider unavailable — the model catalog cannot be read.';

  @override
  String get aiConfigModelCatalogUnavailable =>
      'The model catalog could not be loaded.';

  @override
  String get aiConfigScriptPromptLabel => 'Script prompt';

  @override
  String get aiConfigSchedulePromptLabel => 'Schedule prompt';

  @override
  String get aiConfigRevokeTitle => 'Revoke configuration?';

  @override
  String get aiConfigRevokeBody =>
      'The AI import configuration is revoked. The server-held API key is destroyed. Imports you already applied are kept.';

  @override
  String get aiConfigActiveTitle => 'Active configuration';

  @override
  String aiConfigProviderPrefix(Object provider) {
    return 'Provider: $provider';
  }

  @override
  String aiConfigImageSuffix(Object image) {
    return ' · Image: $image';
  }

  @override
  String get aiConfigSaveChanges => 'Save changes';

  @override
  String get aiConfigRevokeButton => 'Revoke configuration';

  @override
  String get aiConfigUnresolvedTitle => 'Configuration state unknown — verify';

  @override
  String get aiConfigUnresolvedBody =>
      'The setup may or may not have completed. Nothing was deleted — re-check, or clean up the server-held key if you are sure the setup failed.';

  @override
  String get aiConfigRecheck => 'Re-check';

  @override
  String get aiConfigCleanup => 'Clean up';

  @override
  String aiConfigDiscoveryError(Object code) {
    return 'The configuration could not be loaded ($code).';
  }

  @override
  String get aiUploadTooLarge => 'The document is too large for AI import.';

  @override
  String get aiUploadUnsupported =>
      'This file type is not supported for the selected kind.';

  @override
  String get aiUploadDisabled => 'AI import is not enabled on this backend.';

  @override
  String get aiUploadScopeMissing =>
      'Open a production block first — AI import is block-scoped.';

  @override
  String get aiUploadPermissions =>
      'Your permissions are still loading — try again in a moment.';

  @override
  String get aiUploadNetwork =>
      'Network problem — the document was not submitted. Try again.';

  @override
  String aiUploadGeneric(Object code) {
    return 'The document could not be submitted ($code).';
  }

  @override
  String get jobStatusPending => 'Queued — the backend picked it up.';

  @override
  String get jobStatusRunning => 'Processing your document…';

  @override
  String get jobStatusSucceeded => 'Import preview ready.';

  @override
  String get jobStatusFailed => 'Failed — a retry is scheduled.';

  @override
  String get jobStatusDeadLetter =>
      'Processing gave up after repeated failures.';

  @override
  String get jobStatusPayloadUnavailable =>
      'The extracted data is no longer available on the server.';

  @override
  String jobStatusUnknown(Object name) {
    return 'Status unknown ($name).';
  }

  @override
  String get jobWatchForbidden =>
      'You do not have access to this AI import job.';

  @override
  String get jobWatchExhausted =>
      'Still no update from the backend — the job keeps processing. Re-arm the watch or come back later.';

  @override
  String get jobWatchNotFound =>
      'This job does not exist (or belongs to another account).';

  @override
  String get jobWatchNetwork =>
      'Network problem — the status could not be refreshed.';

  @override
  String jobWatchGeneric(Object code) {
    return 'The status could not be refreshed ($code).';
  }

  @override
  String get aiJobTitle => 'AI import job';

  @override
  String get aiJobDuplicate =>
      'Already imported (duplicate) — showing the existing job. No second import was created.';

  @override
  String aiJobRetryBudget(Object maxRetries, Object retries) {
    return 'Retry $retries of $maxRetries';
  }

  @override
  String get aiJobsTitle => 'AI import jobs';

  @override
  String get aiJobsEmpty => 'No AI import started yet.';

  @override
  String get aiJobsEmptyCta => 'Start an AI import';

  @override
  String aiJobsActiveBadge(Object count) {
    return 'Active jobs: $count';
  }

  @override
  String aiJobsRowSubtitle(Object date, Object kind) {
    return '$kind · $date';
  }

  @override
  String aiJobsRowKindEpisode(Object episode, Object kind) {
    return '$kind · $episode';
  }

  @override
  String aiJobsRowEpisodeMore(Object count, Object episode) {
    return '$episode (+$count)';
  }

  @override
  String aiJobsRowEpisodeNumber(Object number) {
    return 'Episode $number';
  }

  @override
  String aiJobsRowEpisodeNumberName(Object name, Object number) {
    return '$number $name';
  }

  @override
  String aiJobsRowApplied(Object count) {
    return '$count applied';
  }

  @override
  String aiJobsRowScenesRebuilt(Object count) {
    return '$count scene(s) from document metadata only';
  }

  @override
  String aiJobEpisodesSeenValues(Object episodes) {
    return 'Episodes discovered: $episodes';
  }

  @override
  String aiJobsLoadError(Object code) {
    return 'The job list could not be loaded ($code).';
  }

  @override
  String get aiJobsDeleteTooltip => 'Delete import';

  @override
  String get aiJobsDeleteConfirmTitle => 'Delete import?';

  @override
  String get aiJobsDeleteConfirmBody =>
      'This also removes the duplicate lock — the document can be imported again.';

  @override
  String get aiJobsDeleteConfirmDelete => 'Delete';

  @override
  String get aiJobsDeleteConfirmCancel => 'Cancel';

  @override
  String get aiJobsDeleteNotDeletable =>
      'This import is still being processed and cannot be deleted yet.';

  @override
  String aiJobsDeleteFailed(Object code) {
    return 'The import could not be deleted ($code).';
  }

  @override
  String get aiJobReviewPreview => 'Review preview';

  @override
  String get aiJobCheckAgain => 'Check again';

  @override
  String get aiJobNextRetryImminent => 'Retry imminent.';

  @override
  String aiJobNextRetryMinutes(Object count) {
    return 'Retry in ~$count min';
  }

  @override
  String aiJobNextRetryHours(Object count) {
    return 'Retry in ~$count h';
  }

  @override
  String aiJobNextRetryDays(Object count) {
    return 'Retry in ~$count d';
  }

  @override
  String get aiJobNextRetryUnknown => 'Retry scheduled — time not known yet.';

  @override
  String get aiJobReasonUnknown =>
      'The last attempt failed for an unknown reason.';

  @override
  String get aiJobReasonDependencyAuth =>
      'A service credential was rejected — retries continue, but it may need attention.';

  @override
  String get aiJobReasonServiceUnavailable =>
      'An upstream service was temporarily unavailable — the next attempt may succeed.';

  @override
  String get aiJobReasonInternal => 'A server-side error occurred.';

  @override
  String aiJobReasonGeneric(Object code) {
    return 'The last attempt failed ($code).';
  }

  @override
  String get aiJobAttemptHistoryLabel => 'Previous attempts';

  @override
  String aiJobAttemptRow(Object attemptNo, Object reason) {
    return 'Attempt $attemptNo: $reason';
  }

  @override
  String get aiJobStageExtractingText => 'Extracting text …';

  @override
  String get aiJobStageExtracting => 'Extracting scenes …';

  @override
  String get aiJobStageMerging => 'Merging schedule …';

  @override
  String get aiJobStageStoringPreview => 'Storing preview …';

  @override
  String aiJobStageUnknown(Object name) {
    return 'Unknown stage ($name).';
  }

  @override
  String aiJobChunkProgress(Object chunk, Object chunksTotal) {
    return 'Chunk $chunk of $chunksTotal';
  }

  @override
  String get aiJobEpisodesSeenLabel => 'Episodes discovered:';

  @override
  String get aiPreviewTitle => 'Import preview';

  @override
  String get aiPreviewKindUnknown =>
      'Unrecognized preview payload — the backend produced a shape this app version cannot render. No rows are guessed; update the app or re-run the import.';

  @override
  String get aiPreviewMissing => 'No preview available for this job yet.';

  @override
  String aiPreviewLoadError(Object code) {
    return 'The preview could not be loaded ($code).';
  }

  @override
  String get aiPreviewScriptTitle => 'Script preview';

  @override
  String aiPreviewScriptSubtitle(Object count) {
    return '$count draft scene(s)';
  }

  @override
  String aiPreviewScriptReconciliation(Object detected, Object extracted) {
    return '$detected detected · $extracted extracted';
  }

  @override
  String aiPreviewScriptSynthesized(Object count) {
    return '$count rebuilt from document metadata';
  }

  @override
  String get aiPreviewScheduleTitle => 'Schedule preview (pre-merge)';

  @override
  String aiPreviewScheduleSubtitle(Object count) {
    return '$count schedule row(s)';
  }

  @override
  String get aiPreviewMergedTitle => 'Merged preview';

  @override
  String aiPreviewMergedSubtitle(Object count) {
    return '$count matched scene(s)';
  }

  @override
  String get aiPreviewFallbackTitle => 'Preview';

  @override
  String aiPreviewUncertainty(Object field, Object note) {
    return 'Uncertainty ($field): $note';
  }

  @override
  String aiPreviewRowRef(Object detail, Object ref) {
    return 'Row $ref: $detail';
  }

  @override
  String aiPreviewUnmatchedScheduleRow(Object ref) {
    return 'Unmatched schedule row: $ref';
  }

  @override
  String aiPreviewUnmatchedScriptScene(Object id) {
    return 'Unmatched script scene: $id';
  }

  @override
  String get aiPreviewUnrecognizedShape => 'Unrecognized payload shape.';

  @override
  String get aiPreviewCreate => 'Create';

  @override
  String get aiPreviewUpdate => 'Update';

  @override
  String get aiPreviewSkip => 'Skip';

  @override
  String aiPreviewUpdatesScene(Object id, Object version) {
    return 'Updates scene $id (v$version)';
  }

  @override
  String get aiPreviewUnscheduled => 'unscheduled';

  @override
  String aiPreviewScheduledRowCount(Object count) {
    return ' · $count schedule row(s)';
  }

  @override
  String aiPreviewSceneWithSummary(Object id, Object summary) {
    return 'Scene $id$summary';
  }

  @override
  String aiPreviewOutfitHeading(Object count) {
    return 'Outfits ($count)';
  }

  @override
  String aiPreviewOutfitFor(Object character, Object name) {
    return '$character: $name';
  }

  @override
  String aiPreviewOutfitQuote(Object quote) {
    return 'Source: $quote';
  }

  @override
  String aiPreviewOutfitPieces(Object pieces) {
    return 'Pieces: $pieces';
  }

  @override
  String get aiPreviewOutfitRejectedStatus => 'rejected';

  @override
  String get aiPreviewOutfitToggleTooltip =>
      'Accept or reject this outfit independently of its scene';

  @override
  String get aiPreviewOutfitOriginExplicit => 'quoted from the script';

  @override
  String get aiPreviewOutfitOriginDerived => 'derived from the script';

  @override
  String aiPreviewOutfitOriginContinued(Object scene) {
    return 'continued from scene $scene';
  }

  @override
  String get aiPreviewOutfitOriginContinuedNoScene =>
      'continued from an earlier scene';

  @override
  String get aiPreviewOutfitOriginInferred => 'inferred from the scene context';

  @override
  String aiPreviewContinuityGapTitle(Object character, Object scene) {
    return 'Wardrobe gap · scene $scene · $character';
  }

  @override
  String get aiPreviewContinuityGapPrompt =>
      'Pick a look or leave the scene without wardrobe.';

  @override
  String aiPreviewContinuityCandidateContinued(Object name) {
    return 'Continuation: $name';
  }

  @override
  String aiPreviewContinuityCandidateInferred(Object name) {
    return 'Context look: $name';
  }

  @override
  String aiPreviewContinuityCandidateConfidence(Object percent) {
    return '$percent% confidence';
  }

  @override
  String get aiPreviewContinuityKeepEmpty => 'Leave the scene without a look';

  @override
  String aiApplyOutcomeScript(
    Object applied,
    Object characters,
    Object outfits,
    Object pieces,
  ) {
    return 'Applied $applied scene(s), $characters character(s), $pieces piece(s), $outfits outfit(s).';
  }

  @override
  String aiApplyUnappliedOutfit(Object character, Object name, Object reason) {
    return 'Not applied: $character – $name ($reason)';
  }

  @override
  String get aiApplyUnappliedReasonCharacterNotPlanned =>
      'character missing from this row';

  @override
  String get aiApplyUnappliedReasonCharacterUnavailable =>
      'the character could not be created';

  @override
  String get aiApplyUnappliedReasonPieceRejected =>
      'a piece of the outfit could not be created';

  @override
  String get aiApplyUnappliedReasonCreateRejected =>
      'the outfit could not be created';

  @override
  String get aiApplyUnappliedReasonNotesRejected =>
      'outfit created, description refused';

  @override
  String get aiApplyUnappliedReasonBindingRejected =>
      'outfit created, binding to the shoot refused';

  @override
  String get aiApplyUnappliedReasonBeatRejected =>
      'outfit created, scene beat refused';

  @override
  String get aiConfigStoredPromptNote =>
      'A stored prompt is in effect — it does not follow deployment defaults.';

  @override
  String get aiConfigResetPrompt => 'Reset to default';

  @override
  String get aiConfigDefaultPromptNote =>
      'No stored prompt — the deployment default is in effect.';

  @override
  String aiModelPriceInOut(Object input, Object output) {
    return '$input → $output / 1M tokens';
  }

  @override
  String aiModelImageUnitRate(Object price) {
    return '$price / image';
  }

  @override
  String aiModelImageOutputRate(Object price) {
    return '$price / 1M image tokens';
  }

  @override
  String aiModelEnergyRate(Object price) {
    return '$price / kWh';
  }

  @override
  String get aiConfigCostDisplayLabel => 'Preferred cost display';

  @override
  String get aiConfigCostDisplayToken => 'Tokens';

  @override
  String get aiConfigCostDisplayEnergy => 'Energy';

  @override
  String aiJobCostCompact(Object value) {
    return 'Cost: $value';
  }

  @override
  String get aiJobCostNotApplicable =>
      'No AI model was billed — native CSV import without an LLM.';

  @override
  String get aiJobCostTitle => 'Cost of this import';

  @override
  String aiJobCostModel(Object model) {
    return 'Model: $model';
  }

  @override
  String aiJobCostTokensIn(Object count) {
    return 'Tokens in: $count';
  }

  @override
  String aiJobCostTokensOut(Object count) {
    return 'Tokens out: $count';
  }

  @override
  String aiJobCostCachedTokens(Object count) {
    return 'of which cached: $count';
  }

  @override
  String aiJobCostTokenTotal(Object price) {
    return 'Token cost: $price';
  }

  @override
  String aiJobCostEnergyTotal(Object price) {
    return 'Energy cost: $price';
  }

  @override
  String aiJobCostEnergyConsumption(Object wh) {
    return 'Energy consumption: $wh Wh';
  }

  @override
  String get aiJobCostEnergyCapped => 'Energy cost capped by the token cost.';

  @override
  String aiJobCostRateInput(Object price) {
    return 'Input rate: $price / 1M tokens';
  }

  @override
  String aiJobCostRateOutput(Object price) {
    return 'Output rate: $price / 1M tokens';
  }

  @override
  String aiJobCostPriceAsOf(Object date) {
    return 'Price as of: $date';
  }

  @override
  String get aiApplyErrorNotSucceeded =>
      'The preview can no longer be applied — check the job status.';

  @override
  String get aiApplyErrorUnresolved =>
      'The apply outcome is unknown — the server may still have applied it. Check the affected episode before retrying.';

  @override
  String get aiApplyErrorContextMissing =>
      'Pick the target episode before applying.';

  @override
  String get aiApplyErrorNetwork =>
      'Network problem — the apply may not have gone through. Check the affected episode before retrying.';

  @override
  String aiApplyErrorGeneric(Object code) {
    return 'The apply failed ($code).';
  }

  @override
  String get aiApplyErrorApplyBlocked =>
      'The preview still carries unresolved review questions — confirm them below to apply.';

  @override
  String get aiApplyErrorMissingMapping =>
      'A script row has no review decision — refresh the preview and re-apply.';

  @override
  String get aiApplyErrorMissingEpisodeGroup =>
      'An episode target no longer matches the preview — refresh the preview and re-apply.';

  @override
  String get aiApplyErrorUnknownContinuityCandidate =>
      'The preview no longer offers this wardrobe choice — refresh the preview and apply again.';

  @override
  String get aiApplyUncertaintiesTitle =>
      'Open review questions — confirm to apply:';

  @override
  String get aiApplyAcknowledgeUncertainty =>
      'Confirm as resolved and apply as extracted';

  @override
  String aiApplyContinuityGapPicked(
    Object character,
    Object look,
    Object scene,
  ) {
    return 'Scene $scene · $character → $look';
  }

  @override
  String aiApplyContinuityGapLeftEmpty(Object character, Object scene) {
    return 'Scene $scene · $character → no look (deliberately empty)';
  }

  @override
  String get aiApplyAssignExistingInstead =>
      'Assign the existing episode instead';

  @override
  String get aiApplyTitle => 'Apply to episode';

  @override
  String aiApplyContextEpisode(Object id) {
    return 'Episode $id';
  }

  @override
  String get aiApplyContextRemembered =>
      'Remembered with this job — change below if needed.';

  @override
  String get aiApplyNoContextTitle =>
      'No target episode remembered for this job.';

  @override
  String get aiApplyNoContextSubtitle =>
      'Pick an episode below to enable the apply.';

  @override
  String get aiApplyAcceptAsIs => 'Create all drafts as-is (no edits).';

  @override
  String aiApplySelectionSummary(
    Object distance,
    Object skips,
    Object updates,
  ) {
    return '$updates update(s), $skips skip(s) — edit distance $distance.';
  }

  @override
  String get aiApplySubmit => 'Apply import';

  @override
  String get aiApplyPickEpisode => 'Pick episode…';

  @override
  String aiApplyUngroupedHeading(Object episode) {
    return 'No episode marker — target: episode $episode';
  }

  @override
  String get aiApplyUngroupedHeadingNoTarget =>
      'No episode marker — pick the target below';

  @override
  String get aiApplyGroupTargetChange => 'Change target';

  @override
  String get aiApplyGroupTargetPickExisting => 'Pick an existing episode…';

  @override
  String get aiApplyGroupTargetEditCreate => 'Create a new episode…';

  @override
  String aiApplyGroupTargetCreate(Object label) {
    return 'Create new: $label';
  }

  @override
  String get aiApplyGroupTargetCreateNoNumber =>
      'Create new — episode number still missing';

  @override
  String aiApplyGroupTargetExisting(Object label) {
    return 'Existing episode: $label';
  }

  @override
  String aiApplyGroupTargetSummary(Object group, Object target) {
    return '$group → $target';
  }

  @override
  String get aiApplyGroupCreateNumberLabel => 'Episode number';

  @override
  String get aiApplyGroupCreateNameLabel => 'Episode title (optional)';

  @override
  String get aiApplyGroupNumberInvalid => 'Please enter a whole number.';

  @override
  String get aiApplyErrorEpisodeNumberTaken =>
      'This episode number is already taken in the series.';

  @override
  String get aiApplyErrorEpisodeNumberOtherBlock =>
      'This episode number already belongs to a different block. Switch the block and re-upload the document there.';

  @override
  String aiApplyErrorEpisodeNumberOtherBlockIn(
    Object seasonLabel,
    Object blockLabel,
  ) {
    return 'This episode number already belongs to $seasonLabel, $blockLabel. Switch to that block and re-upload the document there.';
  }

  @override
  String get aiApplySwitchScopeRecovery =>
      'Switch to the episode\'s home block and re-upload there';

  @override
  String aiApplySwitchScopeFailed(Object code) {
    return 'Switching to the episode\'s home block failed ($code). Check your connection and try again.';
  }

  @override
  String get aiApplyErrorEpisodeCreateFailed =>
      'The episode could not be created automatically. Check your connection and try again via “Change target”.';

  @override
  String aiApplyOutcome(Object applied, Object days, Object shoots) {
    return 'Applied $applied draft(s): $days shooting day(s) created, $shoots scene shoot(s) planned.';
  }

  @override
  String get aiApplyBackToImports => 'Back to imports';

  @override
  String aiScenePickerError(Object code) {
    return 'Scenes could not be loaded ($code).';
  }

  @override
  String get aiScenePickerEmpty => 'No existing scenes in this episode.';

  @override
  String get aiEpisodePickerTitle => 'Pick the target episode';

  @override
  String aiEpisodePickerError(Object error) {
    return 'Episodes could not be loaded ($error).';
  }

  @override
  String get aiEpisodePickerEmpty =>
      'No episodes in this block yet — create an episode in the schedule first.';

  @override
  String get aiImportTitle => 'AI import';

  @override
  String get aiImportConfigure => 'Configure AI import';

  @override
  String get aiImportSchedule => 'Schedule';

  @override
  String get aiImportScript => 'Script';

  @override
  String get aiImportScheduleHint => 'Schedules: pick a CSV or PDF file.';

  @override
  String get aiImportScriptHint => 'Scripts: pick a PDF file.';

  @override
  String get aiImportOrPickFile => '— or pick a file —';

  @override
  String get aiImportPasteLabel => 'Paste the schedule (CSV or plain text)';

  @override
  String get aiImportPickCsvPdf => 'Pick CSV or PDF file';

  @override
  String get aiImportPickPdf => 'Pick PDF file';

  @override
  String get aiImportNoFile => 'No file picked';

  @override
  String get aiImportDocMissing => 'Pick a file first.';

  @override
  String aiImportStampWarning(Object code) {
    return 'Import started — the episode context could not be saved ($code); pick the episode when applying.';
  }

  @override
  String get aiImportSubmit => 'Submit for import';

  @override
  String get aiImportTargetTitle => 'Import target';

  @override
  String aiImportTargetLine(Object seasonLabel, Object blockLabel) {
    return '$seasonLabel · $blockLabel';
  }

  @override
  String get aiImportTargetHint =>
      'The episodes, scenes and shooting days of this import land in this block. If that is not what you want, switch the block first.';

  @override
  String get aiImportTargetNotRecorded => 'Target not recorded.';

  @override
  String get aiImportTargetLoading => 'Resolving the import target …';

  @override
  String get aiImportTargetNoSeason =>
      'Select a season first — without one the import has no target.';

  @override
  String get aiImportTargetNoBlocks =>
      'This season has no block yet. Create a block first, then you can import.';

  @override
  String get aiImportTargetPickBlock => 'Choose the target block';

  @override
  String get aiImportTargetUnknownSeason => 'Season unknown';

  @override
  String get aiImportTargetUnknownBlock => 'Block unknown';

  @override
  String get aiImportScopeMismatch =>
      'The active block belongs to a different season than this import. Nothing was uploaded.';

  @override
  String get commonAdd => 'Add';

  @override
  String get captureDeniedCamera =>
      'Camera access is disabled. Enable camera access in settings to document pieces.';

  @override
  String get captureDeniedGallery =>
      'Photo library access is disabled. Enable photo access in settings to document pieces.';

  @override
  String get captureUnavailable =>
      'The camera is currently unavailable. Check settings and try again.';

  @override
  String get captureDeniedTitleCamera => 'Camera access disabled';

  @override
  String get captureDeniedTitleGallery => 'Photo library access disabled';

  @override
  String get pieceDetailTitle => 'Piece';

  @override
  String get pieceDetailTextRequired => 'Text is required';

  @override
  String get pieceDetailTextRequiredHint => 'Required field — marked with *';

  @override
  String get pieceDetailSubjectOptional => 'optional';

  @override
  String get pieceDetailEditDetail => 'Edit detail';

  @override
  String get pieceDetailDeleteTitle => 'Delete detail?';

  @override
  String pieceDetailDeleteMessage(Object detail) {
    return '“$detail” will be removed. This cannot be undone.';
  }

  @override
  String get pieceDetailNotes => 'Notes';

  @override
  String get pieceDetailNotesHint => 'Fitting notes …';

  @override
  String get pieceDetailSaveNotes => 'Save notes';

  @override
  String get pieceDetailDetails => 'Details';

  @override
  String get pieceDetailNoDetails =>
      'No details yet — add the first one below.';

  @override
  String get pieceDetailAddDetail => 'Add detail';

  @override
  String get pieceDetailSubject => 'Subject';

  @override
  String get pieceDetailText => 'Text';

  @override
  String get pieceDetailCategory => 'Category';

  @override
  String get pieceDetailPhotos => 'Photos';

  @override
  String get pieceDetailCamera => 'Camera';

  @override
  String get pieceDetailGallery => 'Gallery';

  @override
  String get pieceDetailPromptTitle => 'Document pieces with photos?';

  @override
  String get pieceDetailPromptBody =>
      'Photos let the wardrobe team document pieces and track continuity. The system will ask for camera access next.';

  @override
  String get pieceDetailRepertoire => 'Repertoire';

  @override
  String get pieceDetailRepertoireEmpty => 'Not listed in any other season';

  @override
  String get pieceDetailRepertoireAdd => 'Add to season';

  @override
  String get pieceDetailRepertoireAddTooltip =>
      'Add the piece to another season\'s repertoire';

  @override
  String get pieceDetailRepertoireRemoveTooltip => 'Remove from season';

  @override
  String get pieceDetailRepertoireRemoveTitle => 'Remove from season?';

  @override
  String get pieceDetailRepertoireRemoveMessage =>
      'The piece disappears from this season\'s wardrobe. Its details and photos stay on the piece.';

  @override
  String get pieceDetailRepertoirePick => 'Pick a season';

  @override
  String get pieceDetailRepertoireSaved => 'Season added to the repertoire.';

  @override
  String get pieceDetailRepertoireRemoved =>
      'The piece left the season\'s repertoire.';

  @override
  String get pieceErrorSeasonArchived =>
      'That season is archived — its repertoire can no longer be changed.';

  @override
  String get pieceErrorSeasonNotFound =>
      'That season no longer exists — the list was refreshed.';

  @override
  String get pieceDetailNotNow => 'Not now';

  @override
  String get pieceDetailContinue => 'Continue';

  @override
  String get pieceDetailOpenSettings => 'Open settings';

  @override
  String get pieceDetailDeletePhotoMessage =>
      'The photo and its variants are removed. This cannot be undone.';

  @override
  String get wizardErrorSeasonExists =>
      'A season with this number already exists.';

  @override
  String get wizardErrorBlockExistsSeries =>
      'A block with this number already exists in the series.';

  @override
  String get wizardErrorEpisodeExistsSeries =>
      'An episode with this number already exists in the series.';

  @override
  String get wizardErrorNetwork =>
      'Network problem — the create was cancelled. Try again.';

  @override
  String wizardErrorGeneric(Object code) {
    return 'The create failed ($code).';
  }

  @override
  String get wizardFieldPositive =>
      'A whole number greater than 0 is required.';

  @override
  String get wizardFieldBlocks => 'At least one block is required.';

  @override
  String get navBlocks => 'Blocks';

  @override
  String get wizardTemplates => 'Templates';

  @override
  String get wizardTitle => 'Season setup';

  @override
  String get wizardCancelTitle => 'Cancel setup?';

  @override
  String get wizardCancelBody =>
      'Your input will be discarded. Nothing has been saved yet.';

  @override
  String get wizardKeepEditing => 'Keep editing';

  @override
  String get wizardDiscard => 'Discard';

  @override
  String wizardStepOf(Object position, Object total) {
    return 'Step $position of $total';
  }

  @override
  String get wizardNext => 'Next';

  @override
  String get wizardRemoveBlock => 'Remove block';

  @override
  String get wizardEpisodeTitlePlaceholder => 'Title (optional)';

  @override
  String get wizardCompletionMissingConfig => 'Build configuration missing';

  @override
  String get wizardCompletionPartial => 'Partially created';

  @override
  String get wizardCompletionCreated => 'Season created';

  @override
  String wizardCompletionSeasonCreated(Object number) {
    return 'Season $number created';
  }

  @override
  String wizardCompletionSummary(Object blocks, Object episodes) {
    return '$blocks blocks · $episodes episodes';
  }

  @override
  String get wizardResume => 'Resume';

  @override
  String get wizardDone => 'Done';

  @override
  String get wizardAiImportCta => 'Start AI import';

  @override
  String get wizardAiImportNeedsConfig =>
      'AI import needs an AI configuration.';

  @override
  String get wizardOpenAiConfig => 'Open AI configuration';

  @override
  String get wizardDispatchProgress => 'Creating the season…';

  @override
  String wizardDispatchSemantics(Object done, Object total) {
    return '$done of $total commands confirmed';
  }

  @override
  String get wizardReviewSubmit => 'Review & create';

  @override
  String get wizardReviewNumbersPending => 'Determining numbers…';

  @override
  String get wizardReviewCreateSeason => 'Create season';

  @override
  String wizardReviewSeason(Object number) {
    return 'Season $number';
  }

  @override
  String wizardReviewSeasonNamed(Object name, Object number) {
    return 'Season $number · $name';
  }

  @override
  String wizardReviewEpisodesInBlocks(Object blocks, Object episodes) {
    return '$episodes episodes in $blocks blocks';
  }

  @override
  String wizardReviewEpisodeCount(Object count) {
    return '$count episodes';
  }

  @override
  String continuityTitle(Object count) {
    return 'Continuity ($count)';
  }

  @override
  String get continuityRoleGate =>
      'You need an active costume role in this season to manage continuity photos.';

  @override
  String get continuityEmpty => 'No continuity photos linked.';

  @override
  String continuityPhotoLabel(Object id) {
    return 'Photo $id';
  }

  @override
  String continuityPieceLabel(String id) {
    return 'Piece $id';
  }

  @override
  String continuityPieceLabelWithNotes(String id, String notes) {
    return 'Piece $id — $notes';
  }

  @override
  String get continuityStoreOn => 'Store photo on…';

  @override
  String get continuityPieceHint =>
      'Pick the look the photo belongs to — it is stored on the look and linked to this shoot.';

  @override
  String get continuityRationaleTitle => 'Document continuity with photos?';

  @override
  String get continuityRationaleBody =>
      'Continuity photos pin the on-set state to this scene shoot. The system will ask for camera access next.';

  @override
  String get continuityUnlinkTitle => 'Unlink continuity photo?';

  @override
  String get continuityUnlinkButton => 'Unlink';

  @override
  String get castNoSeason => 'Pick a season to see pieces and characters.';

  @override
  String get castPickSeason => 'Pick season';

  @override
  String get castCategoriesTooltip => 'Costume categories';

  @override
  String get castSegmentCharacters => 'Characters';

  @override
  String get castSegmentOutfits => 'Looks';

  @override
  String get photoGalleryAddPhoto => 'Add photo';

  @override
  String get photoGalleryProcessingFailed => 'Processing failed';

  @override
  String get photoGalleryCaptureAgain => 'Capture again';

  @override
  String get photoGalleryDeleteTooltip => 'Delete photo';

  @override
  String photoTileSemantics(Object pieceId) {
    return 'Photo of piece $pieceId';
  }

  @override
  String get photoGalleryEmpty => 'No photos yet';

  @override
  String get seasonsOnlineRequired => 'Online connection required';

  @override
  String get seasonsStaleBanner => 'Cached data may be outdated';

  @override
  String get seasonsErrorBanner => 'Couldn’t refresh — showing cached data';

  @override
  String get seasonsAddTooltip => 'Add season';

  @override
  String get seasonsEmpty => 'No seasons yet';

  @override
  String get continuityUnlinkBody =>
      'The photo stays on its piece — only the link to this shoot is removed.';

  @override
  String get sceneShootDayFallback => 'Shooting day';

  @override
  String get sceneShootsReportsTooltip => 'Reports';

  @override
  String get sceneShootsReportsLabel => 'Reports';

  @override
  String get sceneShootWrapButton => 'Wrap shooting day';

  @override
  String get sceneShootWrapTitle => 'Wrap this shooting day?';

  @override
  String get sceneShootWrapMessage =>
      'Wrapping marks the day as final: started, finished and skipped states can no longer be changed. This cannot be undone — there is no unwrap in the contract.';

  @override
  String get sceneShootWrapConfirm => 'Wrap day';

  @override
  String sceneShootActualOrder(Object actual, Object planned) {
    return 'Actual $actual (planned $planned)';
  }

  @override
  String sceneShootPlannedOrder(Object planned) {
    return 'Planned $planned';
  }

  @override
  String sceneShootCounts(Object notes, Object photos) {
    return '$notes notes · $photos continuity photos';
  }

  @override
  String get sceneShootStart => 'Start';

  @override
  String get sceneShootFinish => 'Finish';

  @override
  String get sceneShootSkip => 'Skip';

  @override
  String get sceneShootOrderTooltip => 'Order';

  @override
  String get sceneShootSetActualOrder => 'Set actual order…';

  @override
  String get sceneShootChangePlanned => 'Change planned position…';

  @override
  String get sceneShootSetActualTitle => 'Set actual order';

  @override
  String get sceneShootSetActualExplanation =>
      'The Ist execution key — sorts this shoot in the actual sequence.';

  @override
  String get sceneShootChangePlannedTitle => 'Change planned position';

  @override
  String get sceneShootChangePlannedExplanation =>
      'The Soll position key for this shoot.';

  @override
  String get sceneShootOrderKeyHint => 'Order key (printable ASCII)';

  @override
  String sceneShootNotesTitle(Object count) {
    return 'Notes ($count)';
  }

  @override
  String get sceneShootEditNoteTooltip => 'Edit note';

  @override
  String get sceneShootDeleteNoteTooltip => 'Delete note';

  @override
  String get sceneShootAddNote => 'Add note';

  @override
  String get sceneShootDeleteNoteTitle => 'Delete this note?';

  @override
  String sceneShootDeleteNoteMessage(Object body) {
    return '“$body” will be removed from the shoot.';
  }

  @override
  String get sceneShootAddNoteTitle => 'Add note';

  @override
  String get sceneShootEditNoteTitle => 'Edit note';

  @override
  String get sceneShootNoteHint => 'Note text';

  @override
  String get sceneShootStatusInProgress => 'In progress';

  @override
  String get sceneShootStatusShot => 'Shot';

  @override
  String get sceneShootStatusSkipped => 'Skipped';

  @override
  String get sceneShootStatusPlanned => 'Planned';

  @override
  String get sceneShootsEmpty => 'No scene shoots planned for this day yet.';

  @override
  String get sceneShootsPlanFirst => 'Plan first shoot';

  @override
  String sceneShootsFetchError(Object code) {
    return 'Could not load the day board ($code).';
  }

  @override
  String sceneShootsNotFound(Object code) {
    return 'No longer available ($code).';
  }

  @override
  String get sceneShootsStaleBanner => 'Cached data may be outdated';

  @override
  String get sceneShootsWrappedBanner =>
      'This day is wrapped — execution is final and read-only.';

  @override
  String get sceneShootErrorNetwork =>
      'Network problem — the change was not saved. Try again.';

  @override
  String sceneShootErrorGeneric(Object code) {
    return 'The scene shoot could not be saved ($code).';
  }

  @override
  String get sceneDetailTitleFallback => 'Scene';

  @override
  String sceneDetailScriptDay(Object day) {
    return 'Script day: $day';
  }

  @override
  String sceneDetailCharactersTitle(Object count) {
    return 'Characters ($count)';
  }

  @override
  String get sceneDetailNoCharacters => 'No characters assigned yet.';

  @override
  String get sceneDetailUnknownCharacter => 'Unknown character';

  @override
  String get sceneDetailRemoveCharacterTooltip => 'Remove';

  @override
  String get sceneDetailAssignCharacter => 'Assign character';

  @override
  String get sceneDetailRemoveCharacterTitle => 'Remove character?';

  @override
  String sceneDetailRemoveCharacterMessage(Object name) {
    return '$name is no longer scheduled for this scene.';
  }

  @override
  String get sceneDetailThisCharacter => 'This character';

  @override
  String sceneDetailShootingDaysTitle(Object count) {
    return 'Shooting days ($count)';
  }

  @override
  String get sceneDetailNoShootingDays =>
      'Not scheduled on any shooting day yet.';

  @override
  String get sceneDetailNoShootingDaysReportHint =>
      'Schedule the scene on a shooting day – the planned-vs-actual (Soll/Ist) report then opens from that day\'s board.';

  @override
  String get sceneDetailOpenDayBoard => 'Open day board';

  @override
  String get sceneDetailScheduleOnDay => 'Schedule on day';

  @override
  String get sceneDetailNoDayCandidatesHint =>
      'No shooting day in this episode yet — create one first or import the schedule.';

  @override
  String get sceneDetailAllDaysScheduled =>
      'All shooting days in this episode are already scheduled or archived.';

  @override
  String get sceneDetailCreateFirstDay => 'Create shooting day';

  @override
  String get sceneDetailScheduleTitle => 'Schedule on shooting day';

  @override
  String sceneDetailFetchError(Object code) {
    return 'Could not load the scene ($code).';
  }

  @override
  String get sceneDetailGone => 'This scene is no longer available.';

  @override
  String sceneDetailOutfitsTitle(Object count) {
    return 'Looks ($count)';
  }

  @override
  String get sceneDetailAssignOutfit => 'Assign look';

  @override
  String get sceneDetailAddChange => '+ Look change';

  @override
  String get sceneDetailRemoveOutfitTooltip => 'Remove look';

  @override
  String get sceneDetailRemoveOutfitTitle => 'Remove look?';

  @override
  String sceneDetailRemoveOutfitMessage(Object name) {
    return '“$name” will be removed from this scene.';
  }

  @override
  String get sceneDetailNoOutfitInScene => 'No look in this scene.';

  @override
  String get sceneDetailPickOutfitTitle => 'Pick look';

  @override
  String get sceneDetailOutfitCueHint =>
      'Note for the wardrobe crew (optional)';

  @override
  String get sceneBeatErrorNotInScene => 'This character is not in the scene.';

  @override
  String get sceneBeatErrorNotFound => 'This look change no longer exists.';

  @override
  String get sceneBeatErrorValidation =>
      'This look change is invalid (e.g. identical consecutive change).';

  @override
  String get sceneBeatErrorNetwork =>
      'Network problem – the change was not saved. Try again.';

  @override
  String sceneBeatErrorGeneric(Object code) {
    return 'The look change could not be saved ($code).';
  }

  @override
  String get sceneBeatOverlaySyncing =>
      'Look change is being saved – the list is still syncing.';

  @override
  String get sceneBeatOverlayStale =>
      'Look change could not be confirmed yet – pull to refresh.';

  @override
  String get assignCharacterSheetTitle => 'Assign character';

  @override
  String characterDetailFetchError(Object code) {
    return 'Could not load the character ($code).';
  }

  @override
  String get characterDetailGone => 'This character no longer exists.';

  @override
  String get characterMeasurementHeight => 'Height';

  @override
  String get characterMeasurementWeight => 'Weight';

  @override
  String get characterMeasurementChest => 'Chest';

  @override
  String get characterMeasurementWaist => 'Waist';

  @override
  String get characterMeasurementHips => 'Hips';

  @override
  String get characterMeasurementShoeSize => 'Shoe size';

  @override
  String get characterMeasurementHatSize => 'Hat size';

  @override
  String get costumeCategoryRenameTooltip => 'Rename';

  @override
  String get costumeCategoryArchiveTooltip => 'Archive';

  @override
  String get costumeCategoriesEmpty => 'No categories yet';

  @override
  String get costumeCategoriesCreateFirst => 'Create the first category';

  @override
  String get costumeCategoryErrorChanged =>
      'Changed elsewhere — refresh and try again.';

  @override
  String get costumeCategoryErrorNetwork =>
      'Network problem — the change was not saved. Try again.';

  @override
  String costumeCategoryErrorGeneric(Object code) {
    return 'The category could not be saved ($code).';
  }

  @override
  String blockSeasonNumber(Object number) {
    return 'Season $number';
  }

  @override
  String blockTileLabel(Object number) {
    return 'Block $number';
  }

  @override
  String get blocksStaleBanner => 'Cached data may be outdated';

  @override
  String get blocksRoleCostume => 'Costume role';

  @override
  String get blocksRoleNone => 'No role in this season';

  @override
  String blocksRoleUnknown(Object code) {
    return 'Role unknown ($code)';
  }

  @override
  String blocksFetchError(Object code) {
    return 'Could not load blocks ($code).';
  }

  @override
  String get blocksEmpty => 'No blocks yet';

  @override
  String get blocksCreateFirst => 'Create the first block';

  @override
  String blocksNotFound(Object code) {
    return 'This season no longer exists ($code).';
  }

  @override
  String get blocksBackToSeasons => 'Back to seasons';

  @override
  String get blocksTileSyncing => 'Just created — syncing…';

  @override
  String get blocksTileSyncingStale =>
      'Created — the list is still catching up. Pull to refresh.';

  @override
  String get blocksCreateTitle => 'Create block';

  @override
  String get blocksNumberLabel => 'Number';

  @override
  String get blocksNumberRequired => 'A whole number is required';

  @override
  String get blocksStartDate => 'Start date (YYYY-MM-DD, optional)';

  @override
  String get blocksEndDate => 'End date (YYYY-MM-DD, optional)';

  @override
  String get blocksDateFormatError => 'Use YYYY-MM-DD';

  @override
  String get blocksCreateButton => 'Create';

  @override
  String get blocksNoBlocksCreateFirst =>
      'No blocks yet — create a block first, then come back.';

  @override
  String get blocksCreateErrorExists =>
      'A block with that number already exists.';

  @override
  String get blocksCreateErrorSignIn => 'Please sign in to continue.';

  @override
  String get blocksCreateErrorNetwork =>
      'Network problem — the block was not created. Try again.';

  @override
  String blocksCreateErrorGeneric(Object code) {
    return 'The block could not be created ($code).';
  }

  @override
  String get blocksAddFab => 'Add block';

  @override
  String episodeTileLabel(Object number) {
    return 'Episode $number';
  }

  @override
  String episodeNumberName(Object name, Object number) {
    return '$number · $name';
  }

  @override
  String episodeNumberPrefix(Object number) {
    return 'Number $number';
  }

  @override
  String get episodesTileSyncing => 'Just created — syncing…';

  @override
  String get episodesTileSyncingStale =>
      'Created — the list is still catching up. Pull to refresh.';

  @override
  String get episodesEmpty => 'No episodes yet';

  @override
  String get episodesCreateFirst => 'Create the first episode';

  @override
  String episodesNotFound(Object code) {
    return 'This block no longer exists ($code).';
  }

  @override
  String get episodesBackToBlocks => 'Back to blocks';

  @override
  String get episodesAddFab => 'Add episode';

  @override
  String episodesFetchError(Object code) {
    return 'Could not load episodes ($code).';
  }

  @override
  String get episodesStaleBanner => 'Cached data may be outdated';

  @override
  String get episodesDismiss => 'Dismiss';

  @override
  String get episodesCreateTitle => 'Create episode';

  @override
  String get episodesNameLabel => 'Name (optional)';

  @override
  String get episodesCreateErrorExists =>
      'An episode with that number already exists.';

  @override
  String get episodesCreateErrorNetwork =>
      'Network problem — the episode was not created. Try again.';

  @override
  String episodesCreateErrorGeneric(Object code) {
    return 'The episode could not be created ($code).';
  }

  @override
  String sceneTileLabel(Object identifier) {
    return 'Scene $identifier';
  }

  @override
  String sceneMood(Object mood) {
    return 'Mood: $mood';
  }

  @override
  String sceneLoc(Object loc) {
    return 'Loc: $loc';
  }

  @override
  String sceneDay(Object day) {
    return 'Day: $day';
  }

  @override
  String get sceneScheduled => 'Scheduled';

  @override
  String get sceneUnscheduled => 'Unscheduled';

  @override
  String sceneCharacterCount(Object count) {
    return '$count characters';
  }

  @override
  String sceneShootingDayCount(Object count) {
    return '$count shooting days';
  }

  @override
  String get scenesTileSyncing => 'Just created — syncing…';

  @override
  String get scenesTileSyncingStale =>
      'Created — the list is still catching up. Pull to refresh.';

  @override
  String get scenesEmpty => 'No scenes yet';

  @override
  String get scenesCreateFirst => 'Create the first scene';

  @override
  String scenesNotFound(Object code) {
    return 'This episode no longer exists ($code).';
  }

  @override
  String get scenesBackToEpisodes => 'Back to episodes';

  @override
  String get scenesAddFab => 'Add scene';

  @override
  String scenesFetchError(Object code) {
    return 'Could not load scenes ($code).';
  }

  @override
  String get scenesCreateTitle => 'Create scene';

  @override
  String get sceneNumberLabel => 'Scene number (optional)';

  @override
  String get sceneSummaryLabel => 'Summary (optional)';

  @override
  String get sceneMoodLabel => 'Mood (optional)';

  @override
  String get sceneLocationLabel => 'Location (optional)';

  @override
  String get sceneScriptDayLabel => 'Script day (optional)';

  @override
  String get scenesCreateErrorNetwork =>
      'Network problem — the scene was not created. Try again.';

  @override
  String scenesCreateErrorGeneric(Object code) {
    return 'The scene could not be created ($code).';
  }

  @override
  String get scenesStaleBanner => 'Cached data may be outdated';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsServerAddress => 'Server address';

  @override
  String get settingsFlavor => 'Flavor';

  @override
  String get settingsBackendUri => 'Backend URI';

  @override
  String get settingsProdNote =>
      'The server address is set by your organization for security and cannot be changed here.';

  @override
  String get settingsReset => 'Reset';

  @override
  String get settingsSave => 'Save';

  @override
  String get settingsClose => 'Close';

  @override
  String get commonDismiss => 'Dismiss';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonSave => 'Save';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonEdit => 'Edit';

  @override
  String get commonClose => 'Close';

  @override
  String get commonMore => 'More';

  @override
  String get commonSettings => 'Settings';

  @override
  String get commonAiImportJobs => 'AI import jobs';

  @override
  String get commonSignOut => 'Sign out';

  @override
  String get commonAbout => 'About';

  @override
  String get commonNoResults => 'No results';

  @override
  String get commonSignedIn => 'Signed in';

  @override
  String get commonSignedOut => 'Signed out';

  @override
  String get commonUnknown => 'Unknown';

  @override
  String get navCast => 'Cast';

  @override
  String get navScript => 'Script';

  @override
  String get viewTitleScript => 'Scenes from the script';

  @override
  String get navSchedule => 'Schedule/Dispo';

  @override
  String get navWardrobe => 'Wardrobe';

  @override
  String get navCharacters => 'Characters';

  @override
  String get navAiImport => 'Import';

  @override
  String get navShootingDays => 'Shooting days';

  @override
  String get navEpisodes => 'Episodes';

  @override
  String get navScenes => 'Scenes';

  @override
  String get shellPlusFabLabel => 'Create';

  @override
  String get offlinePillLabel => 'Offline — data may be stale';

  @override
  String get healthPillHealthy => 'Backend ready';

  @override
  String get healthPillDegraded => 'Backend degraded';

  @override
  String get healthPillUnhealthy => 'Backend impaired';

  @override
  String get healthPillOffline => 'Backend unreachable';

  @override
  String get healthPillOpenHint => 'Open backend status details';

  @override
  String get healthDetailTitle => 'Backend status';

  @override
  String get healthDetailDependencies => 'Dependencies';

  @override
  String get healthDetailNoDependencies =>
      'The server reports no dependency details.';

  @override
  String get healthDetailOfflineBody =>
      'The server is unreachable. The status is re-checked as soon as the connection returns.';

  @override
  String get healthDetailPending => 'Checking status …';

  @override
  String get healthCheckDatabase => 'Database';

  @override
  String get healthCheckEventStore => 'Event store';

  @override
  String get healthCheckSecrets => 'Secret storage';

  @override
  String get healthCheckAiStorage => 'AI file storage';

  @override
  String get healthCheckOther => 'Other dependency';

  @override
  String get healthCheckStatusHealthy => 'ready';

  @override
  String get healthCheckStatusDegraded => 'degraded';

  @override
  String get healthCheckStatusUnhealthy => 'impaired';

  @override
  String get quickCreateTitle => 'What do you want to create?';

  @override
  String get quickCreateAiImportSubtitle =>
      'Import a schedule or script via AI';

  @override
  String get quickCreateWizardSubtitle =>
      'Create season, blocks and episodes step by step';

  @override
  String get quickCreateSceneTitle => 'New scene';

  @override
  String get quickCreateSceneSubtitle => 'Create a scene in the active episode';

  @override
  String get quickCreateShootingDayTitle => 'New shooting day';

  @override
  String get quickCreateShootingDaySubtitle =>
      'Plan a shooting day in the active episode';

  @override
  String locationStripSemantics(Object path) {
    return 'Location: $path';
  }

  @override
  String scopeChipBlock(Object block) {
    return 'Filter: $block';
  }

  @override
  String scopeChipSeason(Object season) {
    return 'Season: $season';
  }

  @override
  String get scopeChipSeasonTooltip => 'Choose active season';

  @override
  String get scopeChipSeasonPickTitle => 'Choose season';

  @override
  String get scopeChipSeasonUnset => 'Choose season';

  @override
  String get seasonScopeManageSeasons => 'Manage seasons';

  @override
  String get seasonScopeManageProduction => 'Manage production';

  @override
  String get seasonScopeEmpty => 'No seasons yet.';

  @override
  String get scopeChipUnknownBlock => 'Filter: unknown block';

  @override
  String get scopeChipForeignSeason =>
      'Filter applies elsewhere – different season';

  @override
  String get scopeChipTooltip => 'Change the active block filter';

  @override
  String get scopeChipPickTitle => 'Pick the block filter';

  @override
  String get scopeChipBlockUnset => 'Choose block';

  @override
  String get scopeChipBlockUnsetTooltip => 'Choose the active block filter';

  @override
  String get episodeChipTooltip => 'Change the active episode';

  @override
  String get episodeChipPickTitle => 'Choose episode';

  @override
  String get episodeChipEmpty => 'No episodes in this block yet.';

  @override
  String get episodeChipUnset => 'Choose episode';

  @override
  String get episodeChipUnsetTooltip => 'Choose the active episode';

  @override
  String get seasonsTitle => 'Seasons';

  @override
  String get seasonsStaleJustNow => 'just now';

  @override
  String get reconcileStaleWarning =>
      'Created — the list is still catching up. Pull to refresh.';

  @override
  String seasonsStaleMinutes(Object count) {
    return '$count min ago';
  }

  @override
  String seasonsStaleHours(Object count) {
    return '$count h ago';
  }

  @override
  String seasonsStaleDays(Object count) {
    return '$count d ago';
  }

  @override
  String get seasonsEmptyTitle => 'No seasons yet';

  @override
  String get seasonsEmptyGuidance =>
      'Create your first season or import an existing schedule with AI.';

  @override
  String get seasonsEmptySetupCta => 'Start season setup';

  @override
  String get seasonsEmptyImportCta => 'Open AI import';

  @override
  String get seasonsLoadError => 'Seasons could not be loaded';

  @override
  String get seasonsStale => 'Cached data may be outdated';

  @override
  String get seasonsCreateConflict =>
      'A season with that number already exists.';

  @override
  String get seasonsCreateAuth => 'Please sign in to continue.';

  @override
  String get seasonsCreateNetwork =>
      'Network problem — the season was not created. Try again.';

  @override
  String get seasonsCreateGeneric => 'The season could not be created.';

  @override
  String get seasonsCreateSeriesIdMissing =>
      'This app was built without DEFAULT_PROJECT_ID: the new season cannot be assigned to a series. Rebuild the app with --dart-define=DEFAULT_PROJECT_ID=<id of the default series>.';

  @override
  String get seasonsSetupCta => 'Start season setup';

  @override
  String get seasonsManualCreateCta => 'Manual';

  @override
  String seasonsDefaultTitle(Object number) {
    return 'Season $number';
  }

  @override
  String get seasonsSyncing => 'Just created — syncing…';

  @override
  String seasonsStaleAt(Object relative) {
    return 'As of $relative';
  }

  @override
  String seasonsMetaBlocks(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count blocks',
      one: '1 block',
    );
    return '$_temp0';
  }

  @override
  String seasonsMetaScenes(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count scenes',
      one: '1 scene',
    );
    return '$_temp0';
  }

  @override
  String seasonsMetaPieces(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count looks',
      one: '1 look',
    );
    return '$_temp0';
  }

  @override
  String get productionTitle => 'Production';

  @override
  String get productionBlocksSubtitle =>
      'Blocks and episodes of the active season';

  @override
  String get productionNoActiveSeason => 'Pick a season first.';

  @override
  String get planningImportSubtitle => 'AI assistant: import a schedule';

  @override
  String get planningActiveJobRow => 'AI import in progress — check status';

  @override
  String get authSignIn => 'Sign in';

  @override
  String get authContinue => 'Continue';

  @override
  String get authSignOut => 'Sign out';

  @override
  String get authWip => 'In progress';

  @override
  String authDevNotice(Object subject) {
    return 'Developer authentication is active — continuing as $subject.';
  }

  @override
  String authContinueAs(Object subject) {
    return 'Continue as $subject';
  }

  @override
  String get authSignedIn => 'Signed in';

  @override
  String get authErrorConfiguration =>
      'Sign-in is not available in this build.';

  @override
  String get authErrorRestore =>
      'Your previous session could not be restored. Please sign in again.';

  @override
  String get authErrorSignInFailed => 'Sign-in failed. Please try again.';

  @override
  String get authErrorNetwork =>
      'Network problem — sign-in did not complete. Try again.';

  @override
  String get authErrorGeneric => 'Something went wrong. Please try again.';

  @override
  String get fatalConfigTitle => 'TLS configuration invalid';

  @override
  String fatalConfigBody(Object error) {
    return 'The app cannot start safely: $error\nNo network requests were made.';
  }

  @override
  String get infoTitle => 'About Breakdown';

  @override
  String get infoVersion => 'Version';

  @override
  String get infoLicense => 'License';

  @override
  String get infoLicenseBody =>
      'GNU Affero General Public License v3.0. This is free software: you may run, study, share, and modify it.';

  @override
  String get infoSource => 'View source';

  @override
  String get infoSourceError => 'Could not open the source link.';

  @override
  String get infoBackendVersions => 'Backend components';

  @override
  String get infoBackendVersionsSubtitle =>
      'Workspace component versions as reported by the backend.';

  @override
  String get infoBackendVersionsError =>
      'Backend versions could not be loaded.';

  @override
  String get infoCredits => 'Credits';

  @override
  String get infoCreditsSubtitle => 'The people and AI models behind this app.';

  @override
  String get creditsTitle => 'Credits';

  @override
  String get creditsCloudTitle => 'Thanks to all contributors';

  @override
  String get creditsCloudBody =>
      'The AI models (with their provider) and the human contributors (with their roles) who helped build this project.';

  @override
  String get creditsError => 'Credits could not be loaded.';

  @override
  String get creditsRoleLabel => 'Roles';

  @override
  String get creditsLlmLabel => 'AI co-author';

  @override
  String creditsSemanticHuman(Object name, Object roles) {
    return '$name, $roles';
  }

  @override
  String creditsSemanticLlm(Object name, Object provider) {
    return '$name, AI co-author by $provider';
  }

  @override
  String get creditsShouldersTitle => 'On the shoulders of giants';

  @override
  String get creditsShouldersBody =>
      'This app is built on these free technologies.';

  @override
  String get creditsRustLabel => 'Rust — the backend language';

  @override
  String get creditsFlutterLabel => 'Flutter — the app framework';

  @override
  String get infoAiUsage => 'AI usage';

  @override
  String get infoAiBody =>
      'When you explicitly submit an import, the text you provide is sent to a configured server-side AI provider. This app never communicates with an AI provider directly.';

  @override
  String get aiImportDisclosureTitle => 'AI processing';

  @override
  String get aiImportDisclosureBody =>
      'The picked file is processed by a server-side AI import. The results are AI-generated and must be verified in the preview before they are applied.';

  @override
  String aiNamingLine(Object model, Object provider) {
    return 'Currently configured: provider $provider, model $model.';
  }

  @override
  String aiPreviewNamingProvider(Object provider) {
    return 'Provider: $provider';
  }

  @override
  String get aiPreviewDecisionModelWarningTitle =>
      'No Decision Model configured';

  @override
  String get aiPreviewDecisionModelWarningBody =>
      'Wardrobe continuity suggestions (Pass 2) and the scene and synopsis ratings are skipped. The import still runs.';

  @override
  String get aiPreviewDecisionModelWarningAction => 'Configure now';

  @override
  String get aiPreviewAiBanner => 'AI-extracted content — review carefully';

  @override
  String get aiPreviewAiNote =>
      'Every row is a machine-extracted draft. The preview carries no machine-verified confidence values.';

  @override
  String get aiApplyReviewCheckbox =>
      'I have reviewed the AI-extracted content';

  @override
  String get aiProvenanceBadge => 'AI-extracted';

  @override
  String get aiDisclosureTitle => 'About AI in this app';

  @override
  String get aiDisclosurePurposeTitle => 'Purpose';

  @override
  String get aiDisclosurePurposeBody =>
      'The AI import extracts structure (scenes, shooting days) from the schedule and script documents you provide, so collaboration can start faster.';

  @override
  String get aiDisclosureFlowTitle => 'Data flow';

  @override
  String get aiDisclosureFlowBody =>
      'Device → backend → configured AI provider → drafts → preview → explicit apply. This app never communicates with the AI provider directly.';

  @override
  String get aiDisclosureNamingTitle => 'Provider and models';

  @override
  String aiDisclosureNamingBodyConfigured(Object model, Object provider) {
    return 'Configured: provider $provider, assistant model $model.';
  }

  @override
  String get aiDisclosureNamingBodyUnconfigured =>
      'No AI configuration is set up for this account.';

  @override
  String get aiDisclosureNamingBodyLoading =>
      'Provider and models are loading …';

  @override
  String get aiDisclosureRetentionTitle => 'Retention';

  @override
  String get aiDisclosureRetentionBody =>
      'Imported document data is deleted automatically after 7 days; afterwards only the explicitly applied result remains in the project.';

  @override
  String get aiDisclosureActTitle => 'EU AI Act';

  @override
  String get aiDisclosureActBody =>
      'This disclosure follows the AI Regulation (EU) 2024/1689, Article 4 (AI literacy) and Article 50 (transparency): AI-generated content is labelled here and must be reviewed.';

  @override
  String get aiConfigLiteracyTitle => 'AI literacy';

  @override
  String get aiConfigLiteracyBody =>
      'This configuration controls which AI provider and models the server-side import uses and which extraction prompts apply. The configured provider processes documents provided by users — configure curated providers and models honestly.';

  @override
  String scriptFetchError(Object code) {
    return 'Could not load the script ($code).';
  }

  @override
  String scriptPartialBlocks(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count blocks',
      one: '1 block',
    );
    return 'Partially loaded: $_temp0 could not be read.';
  }

  @override
  String scriptPartialLoad(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count episodes',
      one: '1 episode',
    );
    return 'Partially loaded: $_temp0 could not be read.';
  }

  @override
  String scriptSceneNumber(Object number) {
    return 'Scene $number';
  }

  @override
  String get scriptSceneNumberUnknown => 'Scene without number';

  @override
  String scriptEpisodeLabel(Object episode) {
    return 'Episode $episode';
  }

  @override
  String get scriptNoScenes => 'No scenes in this season yet.';

  @override
  String scriptRowEpisodeScene(Object episode, Object number) {
    return '$episode, Scene $number';
  }

  @override
  String scriptRowCharacters(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count characters',
      one: '1 character',
    );
    return '$_temp0';
  }

  @override
  String scriptRowOutfits(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count looks',
      one: '1 look',
    );
    return '$_temp0';
  }

  @override
  String scheduleFetchError(Object code) {
    return 'Could not load the schedule ($code).';
  }

  @override
  String get scheduleNoDays => 'No shooting days planned for this season yet.';

  @override
  String schedulePartialBlocks(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count blocks',
      one: '1 block',
    );
    return 'Partially loaded: $_temp0 could not be read.';
  }

  @override
  String schedulePartialLoad(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count episodes',
      one: '1 episode',
    );
    return 'Partially loaded: $_temp0 could not be read.';
  }

  @override
  String scheduleDayLabel(Object date) {
    return 'Shooting day $date';
  }

  @override
  String get scheduleDayUndated => 'Shooting day without a date';

  @override
  String get profileTooltip => 'Menu';

  @override
  String get profileTitle => 'Profile';

  @override
  String get genericProblemTitle => 'Something went wrong';

  @override
  String get genericProblemBody =>
      'The action could not be completed. Please try again.';

  @override
  String get genericProblemAction => 'Try again';

  @override
  String get problemAuthzDenied =>
      'You do not have permission for this action.';

  @override
  String get problemAuthzSessionRequired => 'Please sign in to continue.';

  @override
  String get problemNetwork =>
      'The connection to the server failed. Please try again.';

  @override
  String shootingDaySemantics(Object label) {
    return 'Shooting day $label';
  }

  @override
  String get shootingDayUntitled => 'Untitled shooting day';

  @override
  String get shootingDayArchived => 'Archived';

  @override
  String get shootingDayWrapped => 'Wrapped';

  @override
  String get shootingDayActions => 'Day actions';

  @override
  String get shootingDayMoveEarlier => 'Move earlier';

  @override
  String get shootingDayMoveLater => 'Move later';

  @override
  String get shootingDayRename => 'Rename';

  @override
  String get shootingDayReschedule => 'Reschedule';

  @override
  String get shootingDayUnschedule => 'Unschedule date';

  @override
  String get shootingDayArchive => 'Archive';

  @override
  String get shootingDayNew => 'New shooting day';

  @override
  String get shootingDaysEmpty => 'No shooting days yet';

  @override
  String get shootingDaysCreate => 'Create shooting day';

  @override
  String get shootingDaysGone => 'The episode is gone.';

  @override
  String get commonBack => 'Back';

  @override
  String seasonTabSemantic(Object label, Object position, Object total) {
    return '$label, Tab $position of $total';
  }

  @override
  String seasonTabSemanticEn(Object label, Object position, Object total) {
    return '$label, Tab $position of $total';
  }

  @override
  String get settingsGeneral => 'General';

  @override
  String get settingsEasterEggs => 'Easter eggs';

  @override
  String get settingsEasterEggsSubtitle =>
      'Switch the little surprises in the app on or off.';

  @override
  String get settingsEasterEggsWriteError =>
      'The setting could not be saved. The change applies until the app restarts.';

  @override
  String get settingsEasterEggsError =>
      'The setting could not be read – the default (enabled) stays active.';

  @override
  String get settingsEasterEggsKarlKleiderbuegel => 'Karl Kleiderbügel';

  @override
  String get settingsEasterEggsKarlKleiderbuegelSubtitle =>
      'The clothes-hanger assistant helps in AI import with tips and quips.';

  @override
  String get settingsEasterEggsDejavuCat => 'Déjà-vu Cat';

  @override
  String get settingsEasterEggsDejavuCatSubtitle =>
      'In October a black cat crosses the launch screen and the empty seasons list. In the preview here you can see it any time.';

  @override
  String get settingsEasterEggsPreview => 'Preview';

  @override
  String get settingsEasterEggsPreviewSubtitle =>
      'Preview every egg here at your leisure — regardless of the month.';

  @override
  String get settingsEasterEggsEntryTitle => 'Manage Easter eggs';

  @override
  String get settingsEasterEggsEntrySubtitle =>
      'Switches and a preview for every egg.';

  @override
  String get settingsEasterEggsScreenTitle => 'Easter eggs';

  @override
  String get settingsAiConfig => 'AI configuration';

  @override
  String get settingsAiConfigSubtitle =>
      'Manage the AI provider and models for AI import.';

  @override
  String get settingsAi => 'AI';

  @override
  String get settingsDev => 'Development';

  @override
  String get aiImportClippyNoConfig =>
      'It looks like you\'re trying to import a schedule… Want to set up an AI configuration first?';

  @override
  String get aiImportClippyRunning => 'I\'m all ears!';

  @override
  String get aiImportClippyError =>
      'That didn\'t work out. But together we\'ll get there!';

  @override
  String get aiImportClippySuccess =>
      'Nice! The import fits like it\'s tailor-made.';

  @override
  String get aiImportClippyQueued => 'Hmm, let me think about that…';

  @override
  String get aiImportClippyIdle1 =>
      'Did you know \'Klamotten\' colloquially means clothes? The name fits twice.';

  @override
  String get aiImportClippyIdle2 => 'I\'m a clothes hanger with ambition.';

  @override
  String get aiImportClippyIdle3 => 'Don\'t hang around – I\'m here for you.';

  @override
  String get aiImportClippyIdle4 =>
      'A clothes hanger is rarely alone — it usually hangs out with friends.';

  @override
  String get aiImportClippyIdle5 =>
      'Order is half the battle. The other half is the right hanger.';

  @override
  String get aiImportClippyDismissTooltip => 'Hide Karl Kleiderbügel';

  @override
  String get seasonsArchivedBadge => 'Archived';

  @override
  String get seasonsArchiveTooltip => 'Season actions';

  @override
  String get seasonsArchiveCta => 'Archive season';

  @override
  String get seasonsArchivedError =>
      'The season is archived and can no longer be changed.';

  @override
  String get seasonsArchiveForbidden =>
      'You need an active costume role in this season.';

  @override
  String get omniSearchTitle => 'Search';

  @override
  String get omniSearchTooltip => 'Search';

  @override
  String get omniSearchHint =>
      'Search: scenes, roles, pieces, shooting days of this season';

  @override
  String get omniSearchChipScene => 'Scene';

  @override
  String get omniSearchChipCharacter => 'Role';

  @override
  String get omniSearchChipPiece => 'Piece';

  @override
  String get omniSearchChipShootingDay => 'Shooting day';

  @override
  String get omniSearchGroupScenes => 'Scenes';

  @override
  String get omniSearchGroupCharacters => 'Roles';

  @override
  String get omniSearchGroupPieces => 'Looks';

  @override
  String get omniSearchGroupShootingDays => 'Shooting days';

  @override
  String get omniSearchInitialEmpty =>
      'Type to search the scenes, roles, pieces and shooting days of this season.';

  @override
  String omniSearchZeroMatch(String query, String facets) {
    return 'No matches for \"$query\" in: $facets.';
  }

  @override
  String omniSearchNotLoaded(String facets) {
    return 'Not loaded yet: $facets. Open the related view to load its data.';
  }

  @override
  String get omniSearchError =>
      'The search cannot read the local cache right now.';

  @override
  String get omniSearchNoSeason => 'Pick a season first to search it.';

  @override
  String get omniSearchStaleBanner =>
      'These results are based on the local cache and may be stale.';

  @override
  String get omniSearchRefresh => 'Refresh';

  @override
  String get fundusTitle => 'Fundus';

  @override
  String get fundusTooltip => 'Browse the fundus';

  @override
  String get fundusHint => 'Browse the fundus: pieces across all seasons';

  @override
  String get fundusEmpty => 'This project\'s fundus is empty.';

  @override
  String get fundusNotLoaded => 'The fundus is still loading.';

  @override
  String fundusZeroMatch(String query) {
    return 'No matches for \"$query\" in the fundus.';
  }

  @override
  String get fundusError => 'The fundus cannot read the local cache right now.';

  @override
  String get fundusNoSeason => 'Pick a season first to browse the fundus.';

  @override
  String get fundusStaleBanner =>
      'These results are based on the local cache and may be outdated.';

  @override
  String fundusRepertoireSeasons(String seasons) {
    return 'Seasons: $seasons';
  }

  @override
  String aiPreviewShootingDay(Object day) {
    return 'Shooting day: $day';
  }

  @override
  String get aiApplyShootingDaysHeading =>
      'Shooting days from the script — create them?';

  @override
  String get aiApplyDayRejectedStatus =>
      'Do not create — this day\'s scenes stay unscheduled.';

  @override
  String aiApplyDayCreateSummary(Object day) {
    return 'Shooting day „$day“ will be created; its scenes will be scheduled onto it.';
  }

  @override
  String aiApplyDaySkipSummary(Object day) {
    return 'Shooting day „$day“ will not be created — its scenes stay unscheduled.';
  }

  @override
  String get aiApplyErrorMissingShootingDayGroup =>
      'A shooting-day group no longer matches the preview — reload the preview and apply again.';

  @override
  String aiApplySkippedDayGroups(Object count) {
    return '$count rejected shooting-day group(s) — their scenes were applied unscheduled.';
  }

  @override
  String get shootingDayLinkInto => 'Merge into actual shooting day';

  @override
  String get shootingDayLinkIntoTitle => 'Merge into actual shooting day';

  @override
  String get shootingDayLinkIntoPick =>
      'Pick the target day — scenes and planned entries move there; the AI day is archived.';

  @override
  String get shootingDayLinkIntoNoTarget =>
      'No eligible shooting day. Create an actual day first.';

  @override
  String shootingDayLinkedInto(Object scenes, Object shoots) {
    return '$scenes scenes moved, $shoots planned entries created.';
  }

  @override
  String get shootingDayErrorTargetWrapped =>
      'The target shooting day is already wrapped — merging is not possible.';

  @override
  String get shootingDayErrorEpisodeMismatch =>
      'The shooting days belong to different episodes.';

  @override
  String get aiConfigDecisionSectionTitle => 'Decision model (scoring)';

  @override
  String get aiConfigDecisionHint =>
      'Optional scoring model that rates extracted scenes, TL;DR summaries, and shooting days on a 1–5 star scale. The stars are a machine-generated review aid and never replace human review.';

  @override
  String get aiConfigDecisionProviderLabel => 'Decision model provider';

  @override
  String get aiConfigDecisionDisabled => '— none (scoring disabled) —';

  @override
  String get aiConfigDecisionModelLabel => 'Decision model';

  @override
  String get aiConfigDecisionSameKey => 'Use the same API key as extraction';

  @override
  String get aiConfigDecisionApiKeyLabel => 'API key for the decision model';

  @override
  String aiConfigDecisionKeyRemembered(Object provider) {
    return 'A stored decision key for $provider will be used.';
  }

  @override
  String get aiPreviewAiNoteScored =>
      'All rows are machine-extracted drafts. The star ratings (1–5) are machine-generated quality estimates from the decision model and never replace human review.';

  @override
  String aiPreviewFilterAll(Object count) {
    return 'All scenes ($count)';
  }

  @override
  String aiPreviewFilterLowScore(Object count) {
    return 'Low score ≤ ★★★ ($count)';
  }

  @override
  String aiDecisionRan(Object pair) {
    return 'Scored with $pair.';
  }

  @override
  String get aiDecisionSkippedNoConfig =>
      'Ran without a decision model — no stars (no model configured).';

  @override
  String aiDecisionClientUnavailable(Object pair) {
    return 'Decision model $pair unavailable — the preview was created without scoring.';
  }

  @override
  String aiDecisionScoringFailed(num count, Object pair) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count rows',
      one: '1 row',
    );
    return 'Scoring failed — $_temp0 without stars ($pair).';
  }

  @override
  String get aiDecisionSkippedNotApplicable => 'This import needed no scoring.';

  @override
  String get aiDecisionNotRecorded => 'Scoring outcome not recorded.';

  @override
  String get aiDecisionModelUnnamed => 'unnamed model';

  @override
  String get aiDecisionUnavailable => 'Scoring outcome could not be read.';

  @override
  String get aiPreviewScoringFailed => 'Scoring failed — no stars.';

  @override
  String get aiPreviewSceneScore => 'Scene score:';

  @override
  String get aiPreviewSynopsisScore => 'Synopsis (TL;DR):';

  @override
  String get aiPreviewShootingDayScore => 'Shooting day score:';

  @override
  String aiScoreStarsLabel(Object stars) {
    return '$stars of 5 stars';
  }

  @override
  String get aiConfigDecisionKeyMissing =>
      'Please enter an API key for the decision model or choose “Use the same API key as extraction”.';

  @override
  String get aiConfigDecisionNotPersisted =>
      'The decision model was not saved. The configuration was sent, but the server\'s read-back does not contain it — please check the selection and save again.';

  @override
  String get outfitVariantMarker => 'Variant';

  @override
  String get outfitListTitle => 'Looks';

  @override
  String get outfitListEmpty => 'No looks yet — create the first one.';

  @override
  String get outfitCreateAction => 'Create look';

  @override
  String get outfitCreateTitle => 'Create look';

  @override
  String get outfitNameLabel => 'Name';

  @override
  String get outfitNameRequired => 'A name is required';

  @override
  String get outfitDetailTitle => 'Look';

  @override
  String outfitVariantOf(String name) {
    return 'Variant of $name';
  }

  @override
  String get outfitCreateVariant => 'Create variant';

  @override
  String outfitPiecesTitle(String count) {
    return 'Pieces ($count)';
  }

  @override
  String get outfitPiecesEmpty => 'No pieces yet — add the first one.';

  @override
  String get outfitAddPiece => 'Add piece';

  @override
  String get outfitRemovePieceTooltip => 'Remove';

  @override
  String get outfitNotes => 'Notes';

  @override
  String get outfitNotesHint => 'Notes on the look …';

  @override
  String get outfitSaveNotes => 'Save notes';

  @override
  String get outfitPhotos => 'Photos';

  @override
  String get outfitRenameTitle => 'Rename look';

  @override
  String outfitPieceCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pieces',
      one: '1 piece',
    );
    return '$_temp0';
  }

  @override
  String outfitErrorGeneric(String code) {
    return 'The look could not be saved ($code).';
  }

  @override
  String get outfitErrorForbidden =>
      'You need an active costume role in this season.';

  @override
  String get outfitErrorMembership =>
      'permissions could not be verified — check the connection and try again.';

  @override
  String get outfitSaved => 'Look saved.';

  @override
  String get outfitNotesSaved => 'Notes saved.';

  @override
  String outfitListFetchError(String code) {
    return 'Could not load looks ($code).';
  }

  @override
  String get outfitStaleBanner => 'Cached data may be outdated.';

  @override
  String outfitPieceListFetchError(String code) {
    return 'Could not load pieces ($code).';
  }

  @override
  String get outfitDetailGone => 'This look is no longer available.';

  @override
  String get outfitPickPieceTitle => 'Pick piece';

  @override
  String get outfitPickPieceEmpty => 'No piece in this season\'s repertoire.';

  @override
  String get outfitVariantCreated => 'Variant created.';
}
