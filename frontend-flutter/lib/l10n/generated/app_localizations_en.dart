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
  String get costumeErrorChanged =>
      'Changed elsewhere — pull to refresh and try again.';

  @override
  String get costumeErrorForbidden =>
      'You need an active costume role in this season.';

  @override
  String get costumeErrorMembership =>
      'Could not verify permissions — check the connection and retry.';

  @override
  String costumeErrorGeneric(Object code) {
    return 'The costume could not be saved ($code).';
  }

  @override
  String get photoErrorRequiresCharacter =>
      'Assign the costume to a character before managing photos.';

  @override
  String get photoErrorTooLarge =>
      'The image is too large even after resizing.';

  @override
  String get photoErrorUnsupported =>
      'Only JPEG, PNG and WebP photos are supported.';

  @override
  String get photoErrorForbidden =>
      'You need an active costume role in this season to manage photos.';

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
  String get costumeAddFab => 'Create costume';

  @override
  String get costumesStaleBanner => 'Cached data may be outdated';

  @override
  String costumesFetchError(Object code) {
    return 'Could not load costumes ($code).';
  }

  @override
  String costumeTileLabel(Object id) {
    return 'Costume $id';
  }

  @override
  String get costumeTileLabelFallback => 'Costume';

  @override
  String get costumeCategoryUncategorized => 'Uncategorized';

  @override
  String get costumeDetailSaved => 'Costume details saved.';

  @override
  String costumeWornBy(Object name) {
    return 'Worn by $name';
  }

  @override
  String costumeDetailsCount(Object count) {
    return '$count details';
  }

  @override
  String costumePhotosCount(Object count) {
    return '$count photos';
  }

  @override
  String get costumeTileSyncing => 'Just saved — syncing…';

  @override
  String get costumeTileSyncingStale =>
      'Created — the list is still catching up. Pull to refresh.';

  @override
  String get costumesEmpty => 'No costumes yet';

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
  String get aiJobReviewPreview => 'Review preview';

  @override
  String get aiJobCheckAgain => 'Check again';

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
  String aiApplyOutcome(Object applied, Object days, Object shoots) {
    return 'Applied $applied draft(s): $days shooting day(s) created, $shoots scene shoot(s) planned.';
  }

  @override
  String get aiApplyBackToStart => 'Back to start';

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
    return 'Cached episodes could not be read ($error).';
  }

  @override
  String get aiEpisodePickerEmpty =>
      'No cached episodes — open a production block first, then pick.';

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
  String get commonAdd => 'Add';

  @override
  String get captureDeniedCamera =>
      'Camera access is disabled. Enable camera access in settings to document costumes.';

  @override
  String get captureDeniedGallery =>
      'Photo library access is disabled. Enable photo access in settings to document costumes.';

  @override
  String get captureUnavailable =>
      'The camera is currently unavailable. Check settings and try again.';

  @override
  String get captureDeniedTitleCamera => 'Camera access disabled';

  @override
  String get captureDeniedTitleGallery => 'Photo library access disabled';

  @override
  String get costumeDetailTitle => 'Costume';

  @override
  String get costumeDetailCharacter => 'Character';

  @override
  String get costumeDetailAssignGate =>
      'You need an active costume role in this season to assign characters.';

  @override
  String get costumeDetailAssign => 'Assign';

  @override
  String get costumeDetailReassign => 'Reassign';

  @override
  String get costumeDetailTextRequired => 'Text is required';

  @override
  String get costumeDetailUnassigned => 'Unassigned';

  @override
  String get costumeDetailUnassignTooltip => 'Unassign';

  @override
  String get costumeDetailUnassignTitle => 'Unassign character?';

  @override
  String get costumeDetailUnassignMessage =>
      'The costume keeps its details and notes; only the character binding is removed.';

  @override
  String get costumeDetailNotes => 'Notes';

  @override
  String get costumeDetailNotesHint => 'Fitting notes…';

  @override
  String get costumeDetailSaveNotes => 'Save notes';

  @override
  String get costumeDetailDetails => 'Details';

  @override
  String get costumeDetailNoDetails =>
      'No details yet — add the first one below.';

  @override
  String get costumeDetailAddDetail => 'Add detail';

  @override
  String get costumeDetailSubject => 'Subject';

  @override
  String get costumeDetailText => 'Text';

  @override
  String get costumeDetailCategory => 'Category';

  @override
  String get costumeDetailPhotos => 'Photos';

  @override
  String get costumeDetailCamera => 'Camera';

  @override
  String get costumeDetailGallery => 'Gallery';

  @override
  String get costumeDetailPromptTitle => 'Document costumes with photos?';

  @override
  String get costumeDetailPromptBody =>
      'Photos let the wardrobe team document costumes and track continuity. The system will ask for camera access next.';

  @override
  String get costumeDetailNotNow => 'Not now';

  @override
  String get costumeDetailContinue => 'Continue';

  @override
  String get costumeDetailOpenSettings => 'Open settings';

  @override
  String get costumeDetailDeletePhotoMessage =>
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
  String get continuityStoreOn => 'Store photo on…';

  @override
  String get continuityCostumeHint =>
      'Pick the costume the photo belongs to — it is stored on the costume and linked to this shoot.';

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
  String get costumingTabNoSeason =>
      'Pick a season in the planning tab to see costumes and characters.';

  @override
  String get costumingTabPickSeason => 'Pick season in planning tab';

  @override
  String get photoGalleryAddPhoto => 'Add photo';

  @override
  String get photoGalleryProcessingFailed => 'Processing failed';

  @override
  String get photoGalleryCaptureAgain => 'Capture again';

  @override
  String get photoGalleryDeleteTooltip => 'Delete photo';

  @override
  String photoTileSemantics(Object costumeId) {
    return 'Photo of costume $costumeId';
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
      'The photo stays on its costume — only the link to this shoot is removed.';

  @override
  String get sceneShootDayFallback => 'Shooting day';

  @override
  String get sceneShootsReportsTooltip => 'Reports';

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
  String get sceneDetailOpenDayBoard => 'Open day board';

  @override
  String get sceneDetailScheduleOnDay => 'Schedule on day';

  @override
  String get sceneDetailScheduleTitle => 'Schedule on shooting day';

  @override
  String sceneDetailFetchError(Object code) {
    return 'Could not load the scene ($code).';
  }

  @override
  String get sceneDetailGone => 'This scene is no longer available.';

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
  String get navSeasons => 'Season';

  @override
  String get navPlanen => 'Plan';

  @override
  String get navCostumes => 'Wardrobe';

  @override
  String get navCharacters => 'Characters';

  @override
  String get navAiImport => 'Import';

  @override
  String get navMore => 'More';

  @override
  String get navShootingDays => 'Shooting days';

  @override
  String get navEpisodes => 'Episodes';

  @override
  String get navScenes => 'Scenes';

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
      'This app was built without DEFAULT_SERIES_ID: the new season cannot be assigned to a series. Rebuild the app with --dart-define=DEFAULT_SERIES_ID=<id of the default series>.';

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
  String seasonsMetaCostumes(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count costumes',
      one: '1 costume',
    );
    return '$_temp0';
  }

  @override
  String get planningNoSeasons => 'No seasons yet';

  @override
  String get planningLoadError => 'Seasons could not be loaded.';

  @override
  String planningSeasonNumber(Object number) {
    return 'Number $number';
  }

  @override
  String get planningImportSubtitle => 'AI assistant: import a schedule';

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
  String get infoAiUsage => 'AI usage';

  @override
  String get infoAiBody =>
      'When you explicitly submit an import, the text you provide is sent to a configured server-side AI provider. This app never communicates with an AI provider directly.';

  @override
  String get moreTitle => 'More';

  @override
  String get moreCategories => 'Costume categories';

  @override
  String get moreCategoriesOpenPlanen => 'Open season in the Plan tab';

  @override
  String get moreSignedIn => 'Signed in';

  @override
  String get moreSignedOut => 'Signed out';

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
  String seasonTabSemantic(Object label, Object position) {
    return '$label, Tab $position of 4';
  }

  @override
  String seasonTabSemanticEn(Object label, Object position) {
    return '$label, Tab $position of 4';
  }
}
