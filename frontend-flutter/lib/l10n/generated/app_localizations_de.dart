// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appTitleBreakdown => 'Breakdown';

  @override
  String get commonRetry => 'Erneut versuchen';

  @override
  String get costumeCategoriesTitle => 'Kostüm-Kategorien';

  @override
  String get costumeCategoryArchived => 'Archiviert';

  @override
  String get costumeCategoryAddFab => 'Kategorie hinzufügen';

  @override
  String get costumeCategoryCreateTitle => 'Kategorie erstellen';

  @override
  String get costumeCategoryNameLabel => 'Name';

  @override
  String get costumeCategoryNameRequired => 'Es ist ein Name erforderlich';

  @override
  String get costumeCategoryRenameTitle => 'Kategorie umbenennen';

  @override
  String get costumeCategoryRenameButton => 'Umbenennen';

  @override
  String get costumeCategoryArchiveTitle => 'Kategorie archivieren?';

  @override
  String costumeCategoryArchiveMessage(Object name) {
    return '\"$name\" wird aus dem aktiven Vokabular ausgeblendet. Verwende den Umschalter „Archiviert“, um sie wieder anzuzeigen.';
  }

  @override
  String get costumeCategoryArchiveButton => 'Archivieren';

  @override
  String costumeCategoriesFetchError(Object code) {
    return 'Kategorien konnten nicht geladen werden ($code).';
  }

  @override
  String get costumeCategoriesStaleBanner =>
      'Zwischengespeicherte Daten sind möglicherweise veraltet.';

  @override
  String costumeCategoryTileLabel(Object name) {
    return 'Kategorie $name';
  }

  @override
  String get costumeCategoriesTileSyncing =>
      'Gerade erstellt – wird synchronisiert …';

  @override
  String get costumeCategoriesTileSyncingStale =>
      'Erstellt – die Liste wird noch aktualisiert. Ziehe zum Aktualisieren nach unten.';

  @override
  String get shootingDayAddFab => 'Drehtag erstellen';

  @override
  String get shootingDayUnscheduleTitle => 'Termin entfernen?';

  @override
  String get shootingDayUnscheduleMessage =>
      'Das Kalenderdatum wird entfernt. Der Tag behält seine Reihenfolge und Bezeichnung.';

  @override
  String get shootingDayArchiveTitle => 'Drehtag archivieren?';

  @override
  String get shootingDayArchiveMessage =>
      'Archivierte Tage bleiben in der Projektion, werden aber in den Planungs-Auswahlen ausgeblendet.';

  @override
  String get shootingDayMoveNoRoom =>
      'Hierher kann nicht verschoben werden – die benachbarten Ordnungsschlüssel lassen keinen Platz. Archiviere oder erstelle Drehtage neu, um neu auszubalancieren.';

  @override
  String get shootingDayCreateTitle => 'Drehtag erstellen';

  @override
  String get shootingDayLabelHint => 'Bezeichnung (z. B. 1. Tag)';

  @override
  String get shootingDayNoDate => 'Noch kein Datum';

  @override
  String shootingDayDate(Object date) {
    return 'Datum: $date';
  }

  @override
  String get shootingDayPickDate => 'Datum wählen';

  @override
  String get shootingDayRenameTitle => 'Drehtag umbenennen';

  @override
  String get shootingDayLabel => 'Bezeichnung';

  @override
  String get shootingDayRenameButton => 'Umbenennen';

  @override
  String get shootingDayArchiveButton => 'Archivieren';

  @override
  String get shootingDayUnscheduleButton => 'Termin entfernen';

  @override
  String shootingDaysFetchError(Object code) {
    return 'Drehtage konnten nicht geladen werden ($code).';
  }

  @override
  String get shootingDaysStaleBanner =>
      'Zwischengespeicherte Daten sind möglicherweise veraltet.';

  @override
  String get shootingDayErrorNetwork =>
      'Netzwerkproblem – die Änderung wurde nicht gespeichert. Versuch es erneut.';

  @override
  String shootingDayErrorGeneric(Object code) {
    return 'Der Drehtag konnte nicht gespeichert werden ($code).';
  }

  @override
  String get characterAddFab => 'Figur erstellen';

  @override
  String get characterCreateTitle => 'Figur erstellen';

  @override
  String get characterNameLabel => 'Name';

  @override
  String get characterNameRequired => 'Es ist ein Name erforderlich';

  @override
  String get characterCategoryLabelName => 'Kategorie';

  @override
  String get characterCategoryMain => 'Hauptbesetzung';

  @override
  String get characterCategoryEditTooltip => 'Rollentyp ändern';

  @override
  String get characterCategoryGuest => 'Gast';

  @override
  String get characterCategoryExtra => 'Komparse';

  @override
  String charactersFetchError(Object code) {
    return 'Figuren konnten nicht geladen werden ($code).';
  }

  @override
  String get charactersEmpty => 'Noch keine Figuren';

  @override
  String charactersGone(Object code) {
    return 'Die Staffel ist weg ($code).';
  }

  @override
  String get characterDetailTitleFallback => 'Figur';

  @override
  String get characterContact => 'Kontakt';

  @override
  String get characterEmail => 'E-Mail';

  @override
  String get characterPhone => 'Telefon';

  @override
  String get characterSaveContact => 'Kontakt speichern';

  @override
  String get characterMeasurements => 'Maße';

  @override
  String get characterSaveMeasurements => 'Maße speichern';

  @override
  String characterTileLabel(Object name) {
    return 'Figur $name';
  }

  @override
  String get characterTileSyncing => 'Gerade erstellt – wird synchronisiert …';

  @override
  String get characterTileSyncingStale =>
      'Erstellt – die Liste wird noch aktualisiert. Ziehe zum Aktualisieren nach unten.';

  @override
  String get charactersStaleBanner =>
      'Zwischengespeicherte Daten sind möglicherweise veraltet.';

  @override
  String get characterErrorNetwork =>
      'Netzwerkproblem – die Änderung wurde nicht gespeichert. Versuch es erneut.';

  @override
  String characterErrorGeneric(Object code) {
    return 'Die Figur konnte nicht gespeichert werden ($code).';
  }

  @override
  String get pieceErrorChanged =>
      'Woanders geändert – zum Aktualisieren ziehen und erneut versuchen.';

  @override
  String get pieceErrorForbidden =>
      'Du benötigst eine aktive Kostüm-Rolle in dieser Staffel.';

  @override
  String get pieceErrorMembership =>
      'Berechtigungen konnten nicht überprüft werden – Verbindung prüfen und erneut versuchen.';

  @override
  String pieceErrorGeneric(Object code) {
    return 'Das Kleidungsstück konnte nicht gespeichert werden ($code).';
  }

  @override
  String get pieceErrorCategorySeason =>
      'Diese Kategorie gehört zu einer anderen Staffel – wähle eine Kategorie dieser Staffel.';

  @override
  String get pieceErrorCategoryArchived =>
      'Diese Kategorie ist archiviert – wähle eine aktive Kategorie.';

  @override
  String get pieceErrorDetailNotFound =>
      'Dieses Detail existiert nicht mehr – die Liste wurde aktualisiert.';

  @override
  String get pieceDetailCategoryTitle => 'Kategorie';

  @override
  String get pieceDetailPickCategory => 'Kategorie wählen';

  @override
  String get pieceDetailCategorySaved => 'Kategorie gespeichert.';

  @override
  String get photoErrorTooLarge =>
      'Das Bild ist auch nach der Verkleinerung noch zu groß.';

  @override
  String get photoErrorUnsupported =>
      'Nur JPEG-, PNG- und WebP-Fotos werden unterstützt.';

  @override
  String get photoErrorForbidden =>
      'Du benötigst eine aktive Kostüm-Rolle in dieser Produktion, um Fotos zu verwalten.';

  @override
  String get photoErrorContainerUnresolved =>
      'Für dieses Kleidungsstück kann kein zugehöriger Container ermittelt werden — lade die Garderobe neu und versuch es erneut.';

  @override
  String get photoErrorNetwork =>
      'Netzwerkproblem – die Fotoänderung wurde nicht gespeichert. Versuch es erneut.';

  @override
  String photoErrorGeneric(Object code) {
    return 'Das Foto konnte nicht gespeichert werden ($code).';
  }

  @override
  String get photoDeleteTitle => 'Foto löschen?';

  @override
  String get photoDeleteMessage =>
      'Das Foto wird dauerhaft gelöscht. Dieser Schritt kann nicht rückgängig gemacht werden.';

  @override
  String get pieceAddFab => 'Kleidungsstück erstellen';

  @override
  String get piecesStaleBanner =>
      'Zwischengespeicherte Daten sind möglicherweise veraltet.';

  @override
  String piecesFetchError(Object code) {
    return 'Kleidungsstücke konnten nicht geladen werden ($code).';
  }

  @override
  String pieceTileLabel(Object id) {
    return 'Kleidungsstück $id';
  }

  @override
  String get pieceTileLabelFallback => 'Kleidungsstück';

  @override
  String get costumeCategoryUncategorized => 'Ohne Kategorie';

  @override
  String get pieceDetailSaved => 'Kleidungsstück gespeichert.';

  @override
  String pieceDetailsCount(Object count) {
    return '$count Details';
  }

  @override
  String piecePhotosCount(Object count) {
    return '$count Fotos';
  }

  @override
  String get pieceTileSyncing => 'Gerade gespeichert – wird synchronisiert …';

  @override
  String get pieceTileSyncingStale =>
      'Erstellt – die Liste wird noch aktualisiert. Ziehe zum Aktualisieren nach unten.';

  @override
  String get piecesEmpty => 'Noch keine Kleidungsstücke';

  @override
  String get createSeasonTitle => 'Staffel erstellen';

  @override
  String get createSeasonTitleLabel => 'Titel';

  @override
  String reportsTitle(Object label) {
    return 'Berichte – $label';
  }

  @override
  String get reportsSollIstTitle => 'Geplant vs. tatsächlich';

  @override
  String get reportsPlannedLabel => 'Geplant ';

  @override
  String get reportsActualLabel => 'Tatsächlich ';

  @override
  String get reportsCountsUnavailable => 'Szenenzahlen nicht verfügbar.';

  @override
  String get reportsFinal => 'Abschließend – dieser Tag ist abgeschlossen.';

  @override
  String get reportsNoScenes => 'Keine Szenen in diesem Bericht.';

  @override
  String reportsDayPrefix(Object day) {
    return 'Tag $day';
  }

  @override
  String get reportsFlagMoved => 'verschoben';

  @override
  String get reportsFlagMissing => 'fehlend';

  @override
  String get reportsFlagSkipped => 'übersprungen';

  @override
  String get reportsFlagReshot => 'erneut gedreht';

  @override
  String get reportsPdfDispo => 'Dispo (geplant)';

  @override
  String get reportsPdfShootDay => 'Drehtag (Ausführung)';

  @override
  String get reportsPdfPlannedVsActual => 'Geplant vs. tatsächlich (PDF)';

  @override
  String get reportsPdfSection => 'PDF-Berichte';

  @override
  String get reportsFetch => 'Abrufen';

  @override
  String get reportsPreview => 'Vorschau';

  @override
  String get reportsShare => 'Teilen';

  @override
  String get reportErrorUnknownStatus =>
      'Der Bericht hat ein nicht erkanntes Format – aktualisiere die App, um ihn anzuzeigen.';

  @override
  String reportErrorUnknownShape(Object code) {
    return 'Der Bericht konnte nicht gelesen werden ($code). Versuch es erneut.';
  }

  @override
  String get reportErrorPdfTooLarge =>
      'Das PDF ist zu groß, um es auf diesem Gerät als Vorschau anzuzeigen.';

  @override
  String get reportErrorForbidden =>
      'Du hast keinen Zugriff auf diese Berichte.';

  @override
  String get reportErrorMembershipPending => 'Berichtszugriff wird geprüft …';

  @override
  String get reportErrorMembershipUnavailable =>
      'Zugriffsprüfung fehlgeschlagen – erneut versuchen, um die Berichte zu laden.';

  @override
  String get reportErrorShareFailed =>
      'Teilen fehlgeschlagen – die Datei wurde verworfen. Versuch es erneut.';

  @override
  String get reportErrorNetwork =>
      'Netzwerkproblem – der Bericht wurde nicht geladen. Versuch es erneut.';

  @override
  String reportErrorLoad(Object code) {
    return 'Der Bericht konnte nicht geladen werden ($code).';
  }

  @override
  String get shootingDaysReportsLabel => 'Berichte';

  @override
  String reportsIndexTitle(Object episode) {
    return 'Berichte – $episode';
  }

  @override
  String get reportsIndexDayFinal => 'Abschließend';

  @override
  String get reportsIndexDayOpen => 'Offen';

  @override
  String get reportsIndexEmpty =>
      'Sobald ein Drehtag geplant ist, öffnet sich hier der Soll-/Ist-Bericht (geplant vs. tatsächlich) dieses Tages.';

  @override
  String get shootingDaysReportsAggregateLabel => 'Soll-Ist gesamt';

  @override
  String reportsAggregateTitle(Object scope) {
    return 'Soll-Ist-Vergleich – $scope';
  }

  @override
  String get reportsAggregateFinal =>
      'Abschließend – alle Drehtage sind abgeschlossen.';

  @override
  String reportsAggregateProvisional(Object total, Object wrapped) {
    return 'Vorläufig – $wrapped von $total Drehtagen abgeschlossen.';
  }

  @override
  String reportsAggregateProgress(Object total, Object wrapped) {
    return '$wrapped von $total Drehtagen abgeschlossen';
  }

  @override
  String get reportsAggregatePdf => 'Soll-Ist-Vergleich (PDF)';

  @override
  String reportsAggregateSceneLabel(Object number) {
    return 'Szenen-Nr: $number';
  }

  @override
  String get aiConfigErrorAdmin =>
      'Administrator-Rolle erforderlich – frag deine Produktionsadmins.';

  @override
  String get aiConfigErrorChanged =>
      'Woanders geändert – aktualisiere und wende deine Änderung erneut an.';

  @override
  String get aiConfigErrorOrphaned =>
      'Der API-Schlüssel konnte nach dem fehlgeschlagenen Setup nicht aus dem Server-Vault entfernt werden. Wiederhole die Bereinigung im Konfigurationsbildschirm.';

  @override
  String get aiConfigErrorProvider =>
      'Dieser Anbieter ist gerade nicht verfügbar.';

  @override
  String get aiConfigErrorProviderMismatch =>
      'Der API-Schlüssel gehört nicht zu diesem Anbieter. Wähle den Anbieter, zu dem der gespeicherte Schlüssel gehört, oder sende einen neuen Schlüssel.';

  @override
  String get aiConfigErrorDisabled =>
      'KI-Import ist auf dieser Instanz nicht aktiviert. Das ist eine Server-Konfiguration – hier gibt es nichts zu wiederholen.';

  @override
  String get aiConfigErrorNetwork =>
      'Netzwerkproblem – die Änderung wurde nicht angewendet. Versuch es erneut.';

  @override
  String aiConfigErrorGeneric(Object code) {
    return 'Die Konfigurationsänderung ist fehlgeschlagen ($code).';
  }

  @override
  String get aiConfigProvidersUnavailable =>
      'Anbieter konnten nicht geladen werden.';

  @override
  String get aiConfigTitle => 'KI-Import-Konfiguration';

  @override
  String get aiConfigKeyMissing => 'Gib zuerst den API-Schlüssel ein.';

  @override
  String get aiConfigPrefillHint =>
      'Die Prompt-Felder sind mit den Server-Standardwerten vorausgefüllt – du kannst sie bearbeiten.';

  @override
  String get aiConfigNotConfigured => 'Noch nicht konfiguriert';

  @override
  String get aiConfigFirstRunBody =>
      'Wähle einen Anbieter, wähle das Assistentenmodell und sende deinen API-Schlüssel. Der Schlüssel wird an den Server-Vault gesendet und nie auf diesem Gerät gespeichert.';

  @override
  String get aiConfigApiKeyLabel =>
      'API-Schlüssel (wird an den Server-Vault gesendet)';

  @override
  String get aiConfigSaveConfiguration => 'Konfiguration speichern';

  @override
  String get aiConfigNoProviders =>
      'Auf diesem Backend werden keine KI-Anbieter angeboten.';

  @override
  String get aiConfigProviderLabel => 'Anbieter';

  @override
  String get aiConfigAssistantModelLabel => 'Assistentenmodell';

  @override
  String get aiConfigImageModelLabel => 'Bildmodell (optional)';

  @override
  String get aiConfigNoModel => '— keine —';

  @override
  String get aiConfigNoImageModels =>
      'Dieser Anbieter bietet keine Bildmodelle.';

  @override
  String get aiConfigProviderUnavailable =>
      'Anbieter nicht verfügbar – der Modellkatalog kann nicht gelesen werden.';

  @override
  String get aiConfigModelCatalogUnavailable =>
      'Der Modellkatalog konnte nicht geladen werden.';

  @override
  String get aiConfigScriptPromptLabel => 'Skript-Prompt';

  @override
  String get aiConfigSchedulePromptLabel => 'Drehplan-Prompt';

  @override
  String get aiConfigRevokeTitle => 'Konfiguration widerrufen?';

  @override
  String get aiConfigRevokeBody =>
      'Die KI-Import-Konfiguration wird widerrufen. Der vom Server gehaltene API-Schlüssel wird vernichtet. Bereits angewendete Importe bleiben erhalten.';

  @override
  String get aiConfigActiveTitle => 'Aktive Konfiguration';

  @override
  String aiConfigProviderPrefix(Object provider) {
    return 'Anbieter: $provider';
  }

  @override
  String aiConfigImageSuffix(Object image) {
    return ' · Bild: $image';
  }

  @override
  String get aiConfigSaveChanges => 'Änderungen speichern';

  @override
  String get aiConfigRevokeButton => 'Konfiguration widerrufen';

  @override
  String get aiConfigUnresolvedTitle =>
      'Konfigurationsstatus unbekannt – prüfen';

  @override
  String get aiConfigUnresolvedBody =>
      'Das Setup wurde möglicherweise oder möglicherweise nicht abgeschlossen. Es wurde nichts gelöscht – prüfe erneut oder bereinige den vom Server gehaltenen Schlüssel, wenn du sicher bist, dass das Setup fehlgeschlagen ist.';

  @override
  String get aiConfigRecheck => 'Erneut prüfen';

  @override
  String get aiConfigCleanup => 'Bereinigen';

  @override
  String aiConfigDiscoveryError(Object code) {
    return 'Die Konfiguration konnte nicht geladen werden ($code).';
  }

  @override
  String get aiUploadTooLarge => 'Das Dokument ist für den KI-Import zu groß.';

  @override
  String get aiUploadUnsupported =>
      'Dieser Dateityp wird für die gewählte Art nicht unterstützt.';

  @override
  String get aiUploadDisabled =>
      'KI-Import ist auf diesem Backend nicht aktiviert.';

  @override
  String get aiUploadScopeMissing =>
      'Öffne zuerst einen Produktionsblock – der KI-Import ist blockbezogen.';

  @override
  String get aiUploadPermissions =>
      'Deine Berechtigungen werden noch geladen – versuch es gleich noch einmal.';

  @override
  String get aiUploadNetwork =>
      'Netzwerkproblem – das Dokument wurde nicht übermittelt. Versuch es erneut.';

  @override
  String aiUploadGeneric(Object code) {
    return 'Das Dokument konnte nicht übermittelt werden ($code).';
  }

  @override
  String get jobStatusPending => 'Wartet – das Backend hat es übernommen.';

  @override
  String get jobStatusRunning => 'Dein Dokument wird verarbeitet …';

  @override
  String get jobStatusSucceeded => 'Import-Vorschau bereit.';

  @override
  String get jobStatusFailed =>
      'Fehlgeschlagen – ein erneuter Versuch ist geplant.';

  @override
  String get jobStatusDeadLetter =>
      'Die Verarbeitung hat nach wiederholten Fehlern aufgegeben.';

  @override
  String get jobStatusPayloadUnavailable =>
      'Die extrahierten Daten sind auf dem Server nicht mehr verfügbar.';

  @override
  String jobStatusUnknown(Object name) {
    return 'Status unbekannt ($name).';
  }

  @override
  String get jobWatchForbidden =>
      'Du hast keinen Zugriff auf diesen KI-Import-Auftrag.';

  @override
  String get jobWatchExhausted =>
      'Immer noch kein Update vom Backend – der Auftrag wird weiter verarbeitet. Arm den Watch erneut oder komm später zurück.';

  @override
  String get jobWatchNotFound =>
      'Dieser Auftrag existiert nicht (oder gehört einem anderen Konto).';

  @override
  String get jobWatchNetwork =>
      'Netzwerkproblem – der Status konnte nicht aktualisiert werden.';

  @override
  String jobWatchGeneric(Object code) {
    return 'Der Status konnte nicht aktualisiert werden ($code).';
  }

  @override
  String get aiJobTitle => 'KI-Import-Auftrag';

  @override
  String get aiJobDuplicate =>
      'Bereits importiert (Duplikat) – der bestehende Auftrag wird angezeigt. Es wurde kein zweiter Import erstellt.';

  @override
  String aiJobRetryBudget(Object maxRetries, Object retries) {
    return 'Versuch $retries von $maxRetries';
  }

  @override
  String get aiJobsTitle => 'KI-Import-Aufträge';

  @override
  String get aiJobsEmpty => 'Noch kein KI-Import gestartet.';

  @override
  String get aiJobsEmptyCta => 'KI-Import starten';

  @override
  String aiJobsActiveBadge(Object count) {
    return 'Aktive Aufträge: $count';
  }

  @override
  String aiJobsRowSubtitle(Object date, Object kind) {
    return '$kind · $date';
  }

  @override
  String aiJobsLoadError(Object code) {
    return 'Die Auftragsliste konnte nicht geladen werden ($code).';
  }

  @override
  String get aiJobsDeleteTooltip => 'Import löschen';

  @override
  String get aiJobsDeleteConfirmTitle => 'Import löschen?';

  @override
  String get aiJobsDeleteConfirmBody =>
      'Dadurch wird auch die Duplikat-Sperre aufgehoben – das Dokument kann erneut importiert werden.';

  @override
  String get aiJobsDeleteConfirmDelete => 'Löschen';

  @override
  String get aiJobsDeleteConfirmCancel => 'Abbrechen';

  @override
  String get aiJobsDeleteNotDeletable =>
      'Dieser Import wird noch verarbeitet und kann noch nicht gelöscht werden.';

  @override
  String aiJobsDeleteFailed(Object code) {
    return 'Der Import konnte nicht gelöscht werden ($code).';
  }

  @override
  String get aiJobReviewPreview => 'Vorschau prüfen';

  @override
  String get aiJobCheckAgain => 'Erneut prüfen';

  @override
  String get aiJobNextRetryImminent => 'Erneuter Versuch steht kurz bevor.';

  @override
  String aiJobNextRetryMinutes(Object count) {
    return 'Erneuter Versuch in ~$count min';
  }

  @override
  String aiJobNextRetryHours(Object count) {
    return 'Erneuter Versuch in ~$count h';
  }

  @override
  String aiJobNextRetryDays(Object count) {
    return 'Erneuter Versuch in ~$count d';
  }

  @override
  String get aiJobNextRetryUnknown =>
      'Erneuter Versuch geplant – Zeitpunkt noch unbekannt.';

  @override
  String get aiJobReasonUnknown =>
      'Der letzte Versuch ist aus unbekanntem Grund fehlgeschlagen.';

  @override
  String get aiJobReasonDependencyAuth =>
      'Eine Dienst-Anmeldung wurde abgelehnt – die Wiederholungen laufen weiter, aber sie braucht eventuell Aufmerksamkeit.';

  @override
  String get aiJobReasonServiceUnavailable =>
      'Ein Dienst war vorübergehend nicht erreichbar – der nächste Versuch kann gelingen.';

  @override
  String get aiJobReasonInternal => 'Ein Serverfehler ist aufgetreten.';

  @override
  String aiJobReasonGeneric(Object code) {
    return 'Der letzte Versuch ist fehlgeschlagen ($code).';
  }

  @override
  String get aiJobAttemptHistoryLabel => 'Bisherige Versuche';

  @override
  String aiJobAttemptRow(Object attemptNo, Object reason) {
    return 'Versuch $attemptNo: $reason';
  }

  @override
  String get aiJobStageExtractingText => 'Text wird extrahiert …';

  @override
  String get aiJobStageExtracting => 'Szenen werden extrahiert …';

  @override
  String get aiJobStageMerging => 'Spielplan wird zusammengeführt …';

  @override
  String get aiJobStageStoringPreview => 'Vorschau wird gespeichert …';

  @override
  String aiJobStageUnknown(Object name) {
    return 'Unbekannte Phase ($name).';
  }

  @override
  String aiJobChunkProgress(Object chunk, Object chunksTotal) {
    return 'Abschnitt $chunk von $chunksTotal';
  }

  @override
  String get aiJobEpisodesSeenLabel => 'Gefundene Episoden:';

  @override
  String get aiPreviewTitle => 'Import-Vorschau';

  @override
  String get aiPreviewKindUnknown =>
      'Nicht erkannte Vorschau-Daten – das Backend hat eine Struktur erzeugt, die diese App-Version nicht darstellen kann. Es werden keine Zeilen geraten; aktualisiere die App oder führe den Import erneut aus.';

  @override
  String get aiPreviewMissing =>
      'Für diesen Auftrag ist noch keine Vorschau verfügbar.';

  @override
  String aiPreviewLoadError(Object code) {
    return 'Die Vorschau konnte nicht geladen werden ($code).';
  }

  @override
  String get aiPreviewScriptTitle => 'Skript-Vorschau';

  @override
  String aiPreviewScriptSubtitle(Object count) {
    return '$count Skript-Szene(n)';
  }

  @override
  String get aiPreviewScheduleTitle =>
      'Drehplan-Vorschau (vor dem Zusammenführen)';

  @override
  String aiPreviewScheduleSubtitle(Object count) {
    return '$count Drehplan-Zeile(n)';
  }

  @override
  String get aiPreviewMergedTitle => 'Zusammengeführte Vorschau';

  @override
  String aiPreviewMergedSubtitle(Object count) {
    return '$count passende Szene(n)';
  }

  @override
  String get aiPreviewFallbackTitle => 'Vorschau';

  @override
  String aiPreviewUncertainty(Object field, Object note) {
    return 'Unsicherheit ($field): $note';
  }

  @override
  String aiPreviewRowRef(Object detail, Object ref) {
    return 'Zeile $ref: $detail';
  }

  @override
  String aiPreviewUnmatchedScheduleRow(Object ref) {
    return 'Nicht zugeordnete Drehplan-Zeile: $ref';
  }

  @override
  String aiPreviewUnmatchedScriptScene(Object id) {
    return 'Nicht zugeordnete Skript-Szene: $id';
  }

  @override
  String get aiPreviewUnrecognizedShape => 'Nicht erkannte Vorschau-Struktur.';

  @override
  String get aiPreviewCreate => 'Erstellen';

  @override
  String get aiPreviewUpdate => 'Aktualisieren';

  @override
  String get aiPreviewSkip => 'Überspringen';

  @override
  String aiPreviewUpdatesScene(Object id, Object version) {
    return 'Aktualisiert Szene $id (v$version)';
  }

  @override
  String get aiPreviewUnscheduled => 'nicht eingeplant';

  @override
  String aiPreviewScheduledRowCount(Object count) {
    return ' · $count Drehplan-Zeile(n)';
  }

  @override
  String aiPreviewSceneWithSummary(Object id, Object summary) {
    return 'Szene $id$summary';
  }

  @override
  String aiPreviewOutfitHeading(Object count) {
    return 'Looks ($count)';
  }

  @override
  String aiPreviewOutfitFor(Object character, Object name) {
    return '$character: $name';
  }

  @override
  String aiPreviewOutfitQuote(Object quote) {
    return 'Beleg: $quote';
  }

  @override
  String aiPreviewOutfitPieces(Object pieces) {
    return 'Kleidungsstücke: $pieces';
  }

  @override
  String get aiPreviewOutfitRejectedStatus => 'verworfen';

  @override
  String get aiPreviewOutfitToggleTooltip =>
      'Diesen Look unabhängig von der Szene übernehmen oder verwerfen';

  @override
  String get aiPreviewOutfitOriginExplicit => 'wörtlich aus dem Skript';

  @override
  String get aiPreviewOutfitOriginDerived => 'aus dem Skript abgeleitet';

  @override
  String aiPreviewOutfitOriginContinued(Object scene) {
    return 'übernommen aus Szene $scene';
  }

  @override
  String get aiPreviewOutfitOriginContinuedNoScene =>
      'übernommen aus einer früheren Szene';

  @override
  String get aiPreviewOutfitOriginInferred =>
      'aus dem Szenenkontext abgeleitet';

  @override
  String aiPreviewContinuityGapTitle(Object character, Object scene) {
    return 'Garderoben-Lücke · Szene $scene · $character';
  }

  @override
  String get aiPreviewContinuityGapPrompt =>
      'Wähle einen Look oder lasse die Szene ohne Garderobe.';

  @override
  String aiPreviewContinuityCandidateContinued(Object name) {
    return 'Fortsetzung: $name';
  }

  @override
  String aiPreviewContinuityCandidateInferred(Object name) {
    return 'Kontext-Look: $name';
  }

  @override
  String aiPreviewContinuityCandidateConfidence(Object percent) {
    return '$percent % Sicherheit';
  }

  @override
  String get aiPreviewContinuityKeepEmpty => 'Szene ohne Look lassen';

  @override
  String aiApplyOutcomeScript(
    Object applied,
    Object characters,
    Object outfits,
    Object pieces,
  ) {
    return 'Angewendet: $applied Szene(n), $characters Figur(en), $pieces Kleidungsstück(e), $outfits Look(s).';
  }

  @override
  String aiApplyUnappliedOutfit(Object character, Object name, Object reason) {
    return 'Nicht angewendet: $character – $name ($reason)';
  }

  @override
  String get aiApplyUnappliedReasonCharacterNotPlanned =>
      'Figur fehlt in dieser Zeile';

  @override
  String get aiApplyUnappliedReasonCharacterUnavailable =>
      'Figur konnte nicht angelegt werden';

  @override
  String get aiApplyUnappliedReasonPieceRejected =>
      'ein Kleidungsstück konnte nicht angelegt werden';

  @override
  String get aiApplyUnappliedReasonCreateRejected =>
      'Look konnte nicht angelegt werden';

  @override
  String get aiApplyUnappliedReasonNotesRejected =>
      'Look angelegt, Beschreibung abgelehnt';

  @override
  String get aiApplyUnappliedReasonBindingRejected =>
      'Look angelegt, Zuordnung zum Dreh abgelehnt';

  @override
  String get aiApplyUnappliedReasonBeatRejected =>
      'Look angelegt, Einsatz in der Szene abgelehnt';

  @override
  String get aiConfigStoredPromptNote =>
      'Gespeicherter Prompt aktiv – folgt nicht den Deployment-Voreinstellungen.';

  @override
  String get aiConfigResetPrompt => 'Auf Voreinstellung zurücksetzen';

  @override
  String get aiConfigDefaultPromptNote =>
      'Kein gespeicherter Prompt – die Deployment-Voreinstellung gilt.';

  @override
  String aiModelPriceInOut(Object input, Object output) {
    return '$input → $output / 1M Tokens';
  }

  @override
  String aiModelImageUnitRate(Object price) {
    return '$price / Bild';
  }

  @override
  String aiModelImageOutputRate(Object price) {
    return '$price / 1M Bild-Tokens';
  }

  @override
  String aiModelEnergyRate(Object price) {
    return '$price / kWh';
  }

  @override
  String get aiConfigCostDisplayLabel => 'Bevorzugte Kostenanzeige';

  @override
  String get aiConfigCostDisplayToken => 'Tokens';

  @override
  String get aiConfigCostDisplayEnergy => 'Energie';

  @override
  String aiJobCostCompact(Object value) {
    return 'Kosten: $value';
  }

  @override
  String get aiJobCostNotApplicable =>
      'Kein KI-Modell abgerechnet – nativer CSV-Import ohne LLM.';

  @override
  String get aiJobCostTitle => 'Kosten dieses Imports';

  @override
  String aiJobCostModel(Object model) {
    return 'Modell: $model';
  }

  @override
  String aiJobCostTokensIn(Object count) {
    return 'Tokens rein: $count';
  }

  @override
  String aiJobCostTokensOut(Object count) {
    return 'Tokens raus: $count';
  }

  @override
  String aiJobCostCachedTokens(Object count) {
    return 'davon aus dem Cache: $count';
  }

  @override
  String aiJobCostTokenTotal(Object price) {
    return 'Token-Kosten: $price';
  }

  @override
  String aiJobCostEnergyTotal(Object price) {
    return 'Energie-Kosten: $price';
  }

  @override
  String aiJobCostEnergyConsumption(Object wh) {
    return 'Energieverbrauch: $wh Wh';
  }

  @override
  String get aiJobCostEnergyCapped =>
      'Energiekosten durch Token-Kosten gedeckelt.';

  @override
  String aiJobCostRateInput(Object price) {
    return 'Eingabepreis: $price / 1M Tokens';
  }

  @override
  String aiJobCostRateOutput(Object price) {
    return 'Ausgabepreis: $price / 1M Tokens';
  }

  @override
  String aiJobCostPriceAsOf(Object date) {
    return 'Preisstand: $date';
  }

  @override
  String get aiApplyErrorNotSucceeded =>
      'Die Vorschau kann nicht mehr angewendet werden – prüfe den Auftragsstatus.';

  @override
  String get aiApplyErrorUnresolved =>
      'Das Anwenden-Ergebnis ist unbekannt – der Server hat es möglicherweise trotzdem angewendet. Prüfe zuerst die betroffene Episode, bevor du es erneut versuchst.';

  @override
  String get aiApplyErrorContextMissing => 'Wähle zuerst die Zielepisode aus.';

  @override
  String get aiApplyErrorNetwork =>
      'Netzwerkproblem – das Anwenden wurde möglicherweise nicht abgeschlossen. Prüfe zuerst die betroffene Episode, bevor du es erneut versuchst.';

  @override
  String aiApplyErrorGeneric(Object code) {
    return 'Das Anwenden ist fehlgeschlagen ($code).';
  }

  @override
  String get aiApplyErrorApplyBlocked =>
      'Der Vorschau sind noch ungelöste Prüffragen zugeordnet – bestätige sie unten, um anzuwenden.';

  @override
  String get aiApplyErrorMissingMapping =>
      'Eine Skriptzeile hat keine Prüfentscheidung – lade die Vorschau neu und übernimm erneut.';

  @override
  String get aiApplyErrorMissingEpisodeGroup =>
      'Ein Episoden-Ziel passt nicht mehr zur Vorschau – lade die Vorschau neu und übernimm erneut.';

  @override
  String get aiApplyErrorUnknownContinuityCandidate =>
      'Die Vorschau bietet diese Garderoben-Wahl nicht mehr an – lade die Vorschau neu und übernimm erneut.';

  @override
  String get aiApplyUncertaintiesTitle =>
      'Offene Prüffragen – zum Übernehmen bestätigen:';

  @override
  String get aiApplyAcknowledgeUncertainty =>
      'Als geklärt bestätigen und wie extrahiert übernehmen';

  @override
  String aiApplyContinuityGapPicked(
    Object character,
    Object look,
    Object scene,
  ) {
    return 'Szene $scene · $character → $look';
  }

  @override
  String aiApplyContinuityGapLeftEmpty(Object character, Object scene) {
    return 'Szene $scene · $character → ohne Look (bewusst leer)';
  }

  @override
  String get aiApplyAssignExistingInstead =>
      'Stattdessen die vorhandene Episode zuordnen';

  @override
  String get aiApplyTitle => 'Auf Episode anwenden';

  @override
  String aiApplyContextEpisode(Object id) {
    return 'Episode $id';
  }

  @override
  String get aiApplyContextRemembered =>
      'Mit diesem Auftrag gemerkt – unten bei Bedarf ändern.';

  @override
  String get aiApplyNoContextTitle =>
      'Für diesen Auftrag ist keine Zielepisode gemerkt.';

  @override
  String get aiApplyNoContextSubtitle =>
      'Wähle unten eine Episode, um das Anwenden zu aktivieren.';

  @override
  String get aiApplyAcceptAsIs =>
      'Alle Entwürfe unverändert erstellen (ohne Bearbeitung).';

  @override
  String aiApplySelectionSummary(
    Object distance,
    Object skips,
    Object updates,
  ) {
    return '$updates Aktualisierung(en), $skips Überspringen – Bearbeitungsabstand $distance.';
  }

  @override
  String get aiApplySubmit => 'Import anwenden';

  @override
  String get aiApplyPickEpisode => 'Episode wählen…';

  @override
  String aiApplyUngroupedHeading(Object episode) {
    return 'Ohne Episoden-Marker – Ziel: Episode $episode';
  }

  @override
  String get aiApplyUngroupedHeadingNoTarget =>
      'Ohne Episoden-Marker – Ziel unten wählen';

  @override
  String get aiApplyGroupTargetChange => 'Ziel ändern';

  @override
  String get aiApplyGroupTargetPickExisting => 'Vorhandene Episode wählen…';

  @override
  String get aiApplyGroupTargetEditCreate => 'Neue Episode anlegen…';

  @override
  String aiApplyGroupTargetCreate(Object label) {
    return 'Neu anlegen: $label';
  }

  @override
  String get aiApplyGroupTargetCreateNoNumber =>
      'Neu anlegen – Episoden-Nummer fehlt noch';

  @override
  String aiApplyGroupTargetExisting(Object label) {
    return 'Vorhandene Episode: $label';
  }

  @override
  String aiApplyGroupTargetSummary(Object group, Object target) {
    return '$group → $target';
  }

  @override
  String get aiApplyGroupCreateNumberLabel => 'Episoden-Nummer';

  @override
  String get aiApplyGroupCreateNameLabel => 'Episoden-Titel (optional)';

  @override
  String get aiApplyGroupNumberInvalid => 'Bitte eine ganze Zahl eingeben.';

  @override
  String get aiApplyErrorEpisodeNumberTaken =>
      'Diese Episoden-Nummer ist in der Staffel bereits vergeben.';

  @override
  String get aiApplyErrorEpisodeNumberOtherBlock =>
      'Diese Episodennummer ist bereits einem anderen Block zugeordnet. Wechsle den Block und lade das Dokument dort erneut hoch.';

  @override
  String aiApplyErrorEpisodeNumberOtherBlockIn(
    Object seasonLabel,
    Object blockLabel,
  ) {
    return 'Diese Episodennummer gehört bereits zu $seasonLabel, $blockLabel. Wechsle in diesen Block und lade das Dokument dort erneut hoch.';
  }

  @override
  String get aiApplySwitchScopeRecovery =>
      'Zum Herkunftsblock der Episode wechseln und dort erneut hochladen';

  @override
  String aiApplySwitchScopeFailed(Object code) {
    return 'Der Wechsel zum Herkunftsblock ist fehlgeschlagen ($code). Bitte prüfe deine Verbindung und versuche es erneut.';
  }

  @override
  String get aiApplyErrorEpisodeCreateFailed =>
      'Die Episode konnte nicht automatisch erstellt werden. Bitte prüfe deine Verbindung und versuche es über „Ziel ändern“ erneut.';

  @override
  String aiApplyOutcome(Object applied, Object days, Object shoots) {
    return 'Angewendet: $applied Entwurf(e): $days Drehtag(e) erstellt, $shoots Szenen-Dreh(e) geplant.';
  }

  @override
  String get aiApplyBackToImports => 'Zurück zu den Importen';

  @override
  String aiScenePickerError(Object code) {
    return 'Szenen konnten nicht geladen werden ($code).';
  }

  @override
  String get aiScenePickerEmpty =>
      'In dieser Episode gibt es noch keine Szenen.';

  @override
  String get aiEpisodePickerTitle => 'Zielepisode wählen';

  @override
  String aiEpisodePickerError(Object error) {
    return 'Episoden konnten nicht geladen werden ($error).';
  }

  @override
  String get aiEpisodePickerEmpty =>
      'Keine Episoden in diesem Block – lege zuerst eine Episode im Drehplan an.';

  @override
  String get aiImportTitle => 'KI-Import';

  @override
  String get aiImportConfigure => 'KI-Import konfigurieren';

  @override
  String get aiImportSchedule => 'Drehplan';

  @override
  String get aiImportScript => 'Skript';

  @override
  String get aiImportScheduleHint =>
      'Drehpläne: Wähle eine CSV- oder PDF-Datei.';

  @override
  String get aiImportScriptHint => 'Skripte: Wähle eine PDF-Datei.';

  @override
  String get aiImportOrPickFile => '— oder eine Datei wählen —';

  @override
  String get aiImportPasteLabel => 'Drehplan einfügen (CSV oder Klartext)';

  @override
  String get aiImportPickCsvPdf => 'CSV- oder PDF-Datei wählen';

  @override
  String get aiImportPickPdf => 'PDF-Datei wählen';

  @override
  String get aiImportNoFile => 'Keine Datei gewählt';

  @override
  String get aiImportDocMissing => 'Wähle zuerst eine Datei.';

  @override
  String aiImportStampWarning(Object code) {
    return 'Import gestartet – der Episodenkontext konnte nicht gespeichert werden ($code); wähle die Episode beim Anwenden.';
  }

  @override
  String get aiImportSubmit => 'Zum Import senden';

  @override
  String get commonAdd => 'Hinzufügen';

  @override
  String get captureDeniedCamera =>
      'Kamera-Zugriff ist deaktiviert. Aktiviere den Kamera-Zugriff in den Einstellungen, um Kleidungsstücke zu dokumentieren.';

  @override
  String get captureDeniedGallery =>
      'Foto-Zugriff ist deaktiviert. Aktiviere den Foto-Zugriff in den Einstellungen, um Kleidungsstücke zu dokumentieren.';

  @override
  String get captureUnavailable =>
      'Die Kamera ist derzeit nicht verfügbar. Prüfe die Einstellungen und versuch es erneut.';

  @override
  String get captureDeniedTitleCamera => 'Kamera-Zugriff deaktiviert';

  @override
  String get captureDeniedTitleGallery => 'Fotogalerie-Zugriff deaktiviert';

  @override
  String get pieceDetailTitle => 'Kleidungsstück';

  @override
  String get pieceDetailTextRequired => 'Text ist erforderlich';

  @override
  String get pieceDetailTextRequiredHint => 'Pflichtfeld – markiert mit *';

  @override
  String get pieceDetailSubjectOptional => 'optional';

  @override
  String get pieceDetailEditDetail => 'Detail bearbeiten';

  @override
  String get pieceDetailDeleteTitle => 'Detail löschen?';

  @override
  String pieceDetailDeleteMessage(Object detail) {
    return '„$detail“ wird entfernt. Das kann nicht rückgängig gemacht werden.';
  }

  @override
  String get pieceDetailNotes => 'Notizen';

  @override
  String get pieceDetailNotesHint => 'Anpassungsnotizen …';

  @override
  String get pieceDetailSaveNotes => 'Notizen speichern';

  @override
  String get pieceDetailDetails => 'Details';

  @override
  String get pieceDetailNoDetails =>
      'Noch keine Details – füge unten das erste hinzu.';

  @override
  String get pieceDetailAddDetail => 'Detail hinzufügen';

  @override
  String get pieceDetailSubject => 'Betreff';

  @override
  String get pieceDetailText => 'Text';

  @override
  String get pieceDetailCategory => 'Kategorie';

  @override
  String get pieceDetailPhotos => 'Fotos';

  @override
  String get pieceDetailCamera => 'Kamera';

  @override
  String get pieceDetailGallery => 'Galerie';

  @override
  String get pieceDetailPromptTitle =>
      'Kleidungsstücke mit Fotos dokumentieren?';

  @override
  String get pieceDetailPromptBody =>
      'Fotos helfen dem Garderobenteam, Kleidungsstücke zu dokumentieren und Kontinuität zu verfolgen. Als Nächstes fragt das System nach dem Kamera-Zugriff.';

  @override
  String get pieceDetailRepertoire => 'Repertoire';

  @override
  String get pieceDetailRepertoireEmpty =>
      'In keiner weiteren Staffel gelistet';

  @override
  String get pieceDetailRepertoireAdd => 'Zu Staffel hinzufügen';

  @override
  String get pieceDetailRepertoireAddTooltip =>
      'Das Kleidungsstück zum Repertoire einer anderen Staffel hinzufügen';

  @override
  String get pieceDetailRepertoireRemoveTooltip => 'Aus Staffel entfernen';

  @override
  String get pieceDetailRepertoireRemoveTitle => 'Aus Staffel entfernen?';

  @override
  String get pieceDetailRepertoireRemoveMessage =>
      'Das Kleidungsstück verschwindet aus dem Garderoben-Bestand dieser Staffel. Details und Fotos bleiben am Kleidungsstück.';

  @override
  String get pieceDetailRepertoirePick => 'Staffel wählen';

  @override
  String get pieceDetailRepertoireSaved =>
      'Staffel zum Repertoire hinzugefügt.';

  @override
  String get pieceDetailRepertoireRemoved =>
      'Das Kleidungsstück wurde aus dem Staffel-Repertoire entfernt.';

  @override
  String get pieceErrorSeasonArchived =>
      'Diese Staffel ist archiviert – ihr Repertoire kann nicht mehr geändert werden.';

  @override
  String get pieceErrorSeasonNotFound =>
      'Diese Staffel existiert nicht mehr – die Liste wurde aktualisiert.';

  @override
  String get pieceDetailNotNow => 'Später';

  @override
  String get pieceDetailContinue => 'Weiter';

  @override
  String get pieceDetailOpenSettings => 'Einstellungen öffnen';

  @override
  String get pieceDetailDeletePhotoMessage =>
      'Das Foto und seine Varianten werden entfernt. Das kann nicht rückgängig gemacht werden.';

  @override
  String get wizardErrorSeasonExists =>
      'Eine Season mit dieser Nummer existiert bereits.';

  @override
  String get wizardErrorBlockExistsSeries =>
      'Ein Block mit dieser Nummer existiert bereits in der Serie.';

  @override
  String get wizardErrorEpisodeExistsSeries =>
      'Eine Episode mit dieser Nummer existiert bereits in der Serie.';

  @override
  String get wizardErrorNetwork =>
      'Netzwerkproblem – das Erstellen wurde abgebrochen. Versuche es erneut.';

  @override
  String wizardErrorGeneric(Object code) {
    return 'Das Erstellen ist fehlgeschlagen ($code).';
  }

  @override
  String get wizardFieldPositive => 'Eine ganze Zahl größer als 0 ist nötig.';

  @override
  String get wizardFieldBlocks => 'Mindestens ein Block ist nötig.';

  @override
  String get navBlocks => 'Blöcke';

  @override
  String get wizardTemplates => 'Vorlagen';

  @override
  String get wizardTitle => 'Season-Setup';

  @override
  String get wizardCancelTitle => 'Setup abbrechen?';

  @override
  String get wizardCancelBody =>
      'Deine Eingaben werden verworfen. Es wurde noch nichts gespeichert.';

  @override
  String get wizardKeepEditing => 'Weiter bearbeiten';

  @override
  String get wizardDiscard => 'Verwerfen';

  @override
  String wizardStepOf(Object position, Object total) {
    return 'Schritt $position von $total';
  }

  @override
  String get wizardNext => 'Weiter';

  @override
  String get wizardRemoveBlock => 'Block entfernen';

  @override
  String get wizardEpisodeTitlePlaceholder => 'Titel (optional)';

  @override
  String get wizardCompletionMissingConfig => 'Build-Konfiguration fehlt';

  @override
  String get wizardCompletionPartial => 'Teilweise erstellt';

  @override
  String get wizardCompletionCreated => 'Season angelegt';

  @override
  String wizardCompletionSeasonCreated(Object number) {
    return 'Season $number angelegt';
  }

  @override
  String wizardCompletionSummary(Object blocks, Object episodes) {
    return '$blocks Blöcke · $episodes Episoden';
  }

  @override
  String get wizardResume => 'Fortsetzen';

  @override
  String get wizardDone => 'Fertig';

  @override
  String get wizardAiImportCta => 'KI-Import starten';

  @override
  String get wizardAiImportNeedsConfig =>
      'Für den KI-Import ist eine KI-Konfiguration nötig.';

  @override
  String get wizardOpenAiConfig => 'KI-Konfiguration öffnen';

  @override
  String get wizardDispatchProgress => 'Season wird erstellt…';

  @override
  String wizardDispatchSemantics(Object done, Object total) {
    return '$done von $total Befehlen bestätigt';
  }

  @override
  String get wizardReviewSubmit => 'Prüfen & erstellen';

  @override
  String get wizardReviewNumbersPending => 'Nummern werden ermittelt …';

  @override
  String get wizardReviewCreateSeason => 'Season erstellen';

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
    return '$episodes Episoden in $blocks Blöcke';
  }

  @override
  String wizardReviewEpisodeCount(Object count) {
    return '$count Episoden';
  }

  @override
  String continuityTitle(Object count) {
    return 'Kontinuität ($count)';
  }

  @override
  String get continuityRoleGate =>
      'Du benötigst eine aktive Kostüm-Rolle in dieser Staffel, um Kontinuitätsfotos zu verwalten.';

  @override
  String get continuityEmpty => 'Noch keine Kontinuitätsfotos verknüpft.';

  @override
  String continuityPhotoLabel(Object id) {
    return 'Foto $id';
  }

  @override
  String continuityPieceLabel(String id) {
    return 'Kleidungsstück $id';
  }

  @override
  String continuityPieceLabelWithNotes(String id, String notes) {
    return 'Kleidungsstück $id — $notes';
  }

  @override
  String get continuityStoreOn => 'Foto speichern unter …';

  @override
  String get continuityPieceHint =>
      'Wähle das Kleidungsstück, zu dem das Foto gehört – es wird am Kleidungsstück gespeichert und mit diesem Shot verknüpft.';

  @override
  String get continuityRationaleTitle => 'Kontinuität mit Fotos dokumentieren?';

  @override
  String get continuityRationaleBody =>
      'Kontinuitätsfotos halten den Zustand am Set (Anschluss) an diesem Scene-Shoot fest. Als Nächstes fragt das System nach dem Kamera-Zugriff.';

  @override
  String get continuityUnlinkTitle => 'Kontinuitätsfoto-Verknüpfung entfernen?';

  @override
  String get continuityUnlinkButton => 'Verknüpfung entfernen';

  @override
  String get castNoSeason =>
      'Wähle eine Staffel, um Kleidungsstücke und Figuren zu sehen.';

  @override
  String get castPickSeason => 'Season wählen';

  @override
  String get castCategoriesTooltip => 'Kostüm-Kategorien';

  @override
  String get castSegmentCharacters => 'Figuren';

  @override
  String get castSegmentOutfits => 'Looks';

  @override
  String get photoGalleryAddPhoto => 'Foto hinzufügen';

  @override
  String get photoGalleryProcessingFailed => 'Verarbeitung fehlgeschlagen';

  @override
  String get photoGalleryCaptureAgain => 'Erneut aufnehmen';

  @override
  String get photoGalleryDeleteTooltip => 'Foto löschen';

  @override
  String photoTileSemantics(Object pieceId) {
    return 'Foto von Kleidungsstück $pieceId';
  }

  @override
  String get photoGalleryEmpty => 'Noch keine Fotos';

  @override
  String get seasonsOnlineRequired => 'Online-Verbindung erforderlich';

  @override
  String get seasonsStaleBanner =>
      'Zwischengespeicherte Daten sind möglicherweise veraltet.';

  @override
  String get seasonsErrorBanner =>
      'Aktualisierung fehlgeschlagen – zwischengespeicherte Daten werden angezeigt.';

  @override
  String get seasonsAddTooltip => 'Season hinzufügen';

  @override
  String get seasonsEmpty => 'Noch keine Seasons';

  @override
  String get continuityUnlinkBody =>
      'Das Foto bleibt am Kleidungsstück – nur die Verknüpfung zu diesem Shoot wird entfernt.';

  @override
  String get sceneShootDayFallback => 'Drehtag';

  @override
  String get sceneShootsReportsTooltip => 'Berichte';

  @override
  String get sceneShootsReportsLabel => 'Berichte';

  @override
  String get sceneShootWrapButton => 'Drehtag abschließen';

  @override
  String get sceneShootWrapTitle => 'Diesen Drehtag abschließen?';

  @override
  String get sceneShootWrapMessage =>
      'Beim Abschließen wird der Tag als endgültig markiert: Gestartet-, Fertig- und Übersprungen-Status können danach nicht mehr geändert werden. Das kann nicht rückgängig gemacht werden – ein Entfernen der Abschließung ist im Vertrag nicht vorgesehen.';

  @override
  String get sceneShootWrapConfirm => 'Drehtag abschließen';

  @override
  String sceneShootActualOrder(Object actual, Object planned) {
    return 'Tatsächlich $actual (geplant $planned)';
  }

  @override
  String sceneShootPlannedOrder(Object planned) {
    return 'Geplant $planned';
  }

  @override
  String sceneShootCounts(Object notes, Object photos) {
    return '$notes Notizen · $photos Kontinuitätsfotos';
  }

  @override
  String get sceneShootStart => 'Start';

  @override
  String get sceneShootFinish => 'Abschließen';

  @override
  String get sceneShootSkip => 'Überspringen';

  @override
  String get sceneShootOrderTooltip => 'Reihenfolge';

  @override
  String get sceneShootSetActualOrder => 'Tatsächliche Reihenfolge festlegen…';

  @override
  String get sceneShootChangePlanned => 'Geplante Position ändern…';

  @override
  String get sceneShootSetActualTitle => 'Tatsächliche Reihenfolge festlegen';

  @override
  String get sceneShootSetActualExplanation =>
      'Der Ist-Ausführungsschlüssel – sortiert diesen Shoot in die tatsächliche Reihenfolge.';

  @override
  String get sceneShootChangePlannedTitle => 'Geplante Position ändern';

  @override
  String get sceneShootChangePlannedExplanation =>
      'Der Soll-Positionsschlüssel für diesen Shoot.';

  @override
  String get sceneShootOrderKeyHint =>
      'Ordnungsschlüssel (druckbare ASCII-Zeichen)';

  @override
  String sceneShootNotesTitle(Object count) {
    return 'Notizen ($count)';
  }

  @override
  String get sceneShootEditNoteTooltip => 'Notiz bearbeiten';

  @override
  String get sceneShootDeleteNoteTooltip => 'Notiz löschen';

  @override
  String get sceneShootAddNote => 'Notiz hinzufügen';

  @override
  String get sceneShootDeleteNoteTitle => 'Diese Notiz löschen?';

  @override
  String sceneShootDeleteNoteMessage(Object body) {
    return '„$body“ wird aus dem Shoot entfernt.';
  }

  @override
  String get sceneShootAddNoteTitle => 'Notiz hinzufügen';

  @override
  String get sceneShootEditNoteTitle => 'Notiz bearbeiten';

  @override
  String get sceneShootNoteHint => 'Notiztext';

  @override
  String get sceneShootStatusInProgress => 'In Arbeit';

  @override
  String get sceneShootStatusShot => 'Abgedreht';

  @override
  String get sceneShootStatusSkipped => 'Übersprungen';

  @override
  String get sceneShootStatusPlanned => 'Geplant';

  @override
  String get sceneShootsEmpty =>
      'Für diesen Tag sind noch keine Szenen-Drehs geplant.';

  @override
  String get sceneShootsPlanFirst => 'Ersten Dreh planen';

  @override
  String sceneShootsFetchError(Object code) {
    return 'Das Day-Board konnte nicht geladen werden ($code).';
  }

  @override
  String sceneShootsNotFound(Object code) {
    return 'Nicht mehr verfügbar ($code).';
  }

  @override
  String get sceneShootsStaleBanner =>
      'Zwischengespeicherte Daten sind möglicherweise veraltet.';

  @override
  String get sceneShootsWrappedBanner =>
      'Dieser Tag ist abgeschlossen – die Ausführung ist endgültig und schreibgeschützt.';

  @override
  String get sceneShootErrorNetwork =>
      'Netzwerkproblem – die Änderung wurde nicht gespeichert. Versuch es erneut.';

  @override
  String sceneShootErrorGeneric(Object code) {
    return 'Der Szenen-Dreh konnte nicht gespeichert werden ($code).';
  }

  @override
  String get sceneDetailTitleFallback => 'Szene';

  @override
  String sceneDetailScriptDay(Object day) {
    return 'Drehtag im Skript: $day';
  }

  @override
  String sceneDetailCharactersTitle(Object count) {
    return 'Figuren ($count)';
  }

  @override
  String get sceneDetailNoCharacters => 'Noch keine Figuren zugewiesen.';

  @override
  String get sceneDetailUnknownCharacter => 'Unbekannte Figur';

  @override
  String get sceneDetailRemoveCharacterTooltip => 'Entfernen';

  @override
  String get sceneDetailAssignCharacter => 'Figur zuweisen';

  @override
  String get sceneDetailRemoveCharacterTitle => 'Figur entfernen?';

  @override
  String sceneDetailRemoveCharacterMessage(Object name) {
    return '$name ist nicht mehr für diese Szene eingeplant.';
  }

  @override
  String get sceneDetailThisCharacter => 'Diese Figur';

  @override
  String sceneDetailShootingDaysTitle(Object count) {
    return 'Drehtage ($count)';
  }

  @override
  String get sceneDetailNoShootingDays => 'Noch keinem Drehtag zugeordnet.';

  @override
  String get sceneDetailNoShootingDaysReportHint =>
      'Plane die Szene auf einem Drehtag – der Soll-/Ist-Bericht (geplant vs. tatsächlich) öffnet sich dann über das Day-Board dieses Tages.';

  @override
  String get sceneDetailOpenDayBoard => 'Day-Board öffnen';

  @override
  String get sceneDetailScheduleOnDay => 'Auf Drehtag planen';

  @override
  String get sceneDetailNoDayCandidatesHint =>
      'Noch kein Drehtag in dieser Episode — lege zuerst einen an oder importiere die Dispo.';

  @override
  String get sceneDetailAllDaysScheduled =>
      'Alle Drehtage dieser Episode sind bereits geplant oder archiviert.';

  @override
  String get sceneDetailCreateFirstDay => 'Drehtag anlegen';

  @override
  String get sceneDetailScheduleTitle => 'Auf Drehtag planen';

  @override
  String sceneDetailFetchError(Object code) {
    return 'Szene konnte nicht geladen werden ($code).';
  }

  @override
  String get sceneDetailGone => 'Diese Szene ist nicht mehr verfügbar.';

  @override
  String sceneDetailOutfitsTitle(Object count) {
    return 'Looks ($count)';
  }

  @override
  String get sceneDetailAssignOutfit => 'Look zuweisen';

  @override
  String get sceneDetailAddChange => '+ Lookwechsel';

  @override
  String get sceneDetailRemoveOutfitTooltip => 'Look entfernen';

  @override
  String get sceneDetailRemoveOutfitTitle => 'Look entfernen?';

  @override
  String sceneDetailRemoveOutfitMessage(Object name) {
    return '„$name“ wird aus dieser Szene entfernt.';
  }

  @override
  String get sceneDetailNoOutfitInScene => 'Kein Look in dieser Szene.';

  @override
  String get sceneDetailPickOutfitTitle => 'Look wählen';

  @override
  String get sceneDetailOutfitCueHint => 'Notiz für die Garderobe (optional)';

  @override
  String get sceneBeatErrorNotInScene => 'Diese Figur ist nicht in der Szene.';

  @override
  String get sceneBeatErrorNotFound =>
      'Dieser Lookwechsel existiert nicht (mehr).';

  @override
  String get sceneBeatErrorValidation =>
      'Dieser Lookwechsel ist ungültig (z. B. identischer Folge-Wechsel).';

  @override
  String get sceneBeatErrorNetwork =>
      'Netzwerkproblem – die Änderung wurde nicht gespeichert. Versuch es erneut.';

  @override
  String sceneBeatErrorGeneric(Object code) {
    return 'Der Lookwechsel konnte nicht gespeichert werden ($code).';
  }

  @override
  String get sceneBeatOverlaySyncing =>
      'Lookwechsel wird gespeichert – die Liste wird noch aktualisiert.';

  @override
  String get sceneBeatOverlayStale =>
      'Lookwechsel konnte noch nicht bestätigt werden – ziehe nach, um zu aktualisieren.';

  @override
  String get assignCharacterSheetTitle => 'Figur zuweisen';

  @override
  String characterDetailFetchError(Object code) {
    return 'Figur konnte nicht geladen werden ($code).';
  }

  @override
  String get characterDetailGone => 'Diese Figur existiert nicht mehr.';

  @override
  String get characterMeasurementHeight => 'Höhe';

  @override
  String get characterMeasurementWeight => 'Gewicht';

  @override
  String get characterMeasurementChest => 'Brust';

  @override
  String get characterMeasurementWaist => 'Taille';

  @override
  String get characterMeasurementHips => 'Hüfte';

  @override
  String get characterMeasurementShoeSize => 'Schuhgröße';

  @override
  String get characterMeasurementHatSize => 'Hutgröße';

  @override
  String get costumeCategoryRenameTooltip => 'Umbenennen';

  @override
  String get costumeCategoryArchiveTooltip => 'Archivieren';

  @override
  String get costumeCategoriesEmpty => 'Noch keine Kategorien';

  @override
  String get costumeCategoriesCreateFirst => 'Erste Kategorie erstellen';

  @override
  String get costumeCategoryErrorChanged =>
      'Woanders geändert – aktualisiere und versuch es erneut.';

  @override
  String get costumeCategoryErrorNetwork =>
      'Netzwerkproblem – die Änderung wurde nicht gespeichert. Versuch es erneut.';

  @override
  String costumeCategoryErrorGeneric(Object code) {
    return 'Die Kategorie konnte nicht gespeichert werden ($code).';
  }

  @override
  String blockSeasonNumber(Object number) {
    return 'Staffel $number';
  }

  @override
  String blockTileLabel(Object number) {
    return 'Block $number';
  }

  @override
  String get blocksStaleBanner =>
      'Zwischengespeicherte Daten sind möglicherweise veraltet.';

  @override
  String get blocksRoleCostume => 'Kostüm-Rolle';

  @override
  String get blocksRoleNone => 'Keine Rolle in dieser Staffel';

  @override
  String blocksRoleUnknown(Object code) {
    return 'Rolle unbekannt ($code)';
  }

  @override
  String blocksFetchError(Object code) {
    return 'Blöcke konnten nicht geladen werden ($code).';
  }

  @override
  String get blocksEmpty => 'Noch keine Blöcke';

  @override
  String get blocksCreateFirst => 'Ersten Block erstellen';

  @override
  String blocksNotFound(Object code) {
    return 'Diese Staffel existiert nicht mehr ($code).';
  }

  @override
  String get blocksBackToSeasons => 'Zurück zu den Staffeln';

  @override
  String get blocksTileSyncing => 'Gerade erstellt – wird synchronisiert …';

  @override
  String get blocksTileSyncingStale =>
      'Erstellt – die Liste wird noch aktualisiert. Ziehe zum Aktualisieren nach unten.';

  @override
  String get blocksCreateTitle => 'Block erstellen';

  @override
  String get blocksNumberLabel => 'Nummer';

  @override
  String get blocksNumberRequired => 'Es ist eine ganze Zahl erforderlich';

  @override
  String get blocksStartDate => 'Startdatum (YYYY-MM-DD, optional)';

  @override
  String get blocksEndDate => 'Enddatum (YYYY-MM-DD, optional)';

  @override
  String get blocksDateFormatError => 'Verwende YYYY-MM-DD';

  @override
  String get blocksCreateButton => 'Erstellen';

  @override
  String get blocksNoBlocksCreateFirst =>
      'Noch keine Blöcke – erstelle zuerst einen Block und komm dann zurück.';

  @override
  String get blocksCreateErrorExists =>
      'Ein Block mit dieser Nummer existiert bereits.';

  @override
  String get blocksCreateErrorSignIn => 'Bitte melde dich an, um fortzufahren.';

  @override
  String get blocksCreateErrorNetwork =>
      'Netzwerkproblem – der Block wurde nicht erstellt. Versuch es erneut.';

  @override
  String blocksCreateErrorGeneric(Object code) {
    return 'Der Block konnte nicht erstellt werden ($code).';
  }

  @override
  String get blocksAddFab => 'Block hinzufügen';

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
    return 'Nummer $number';
  }

  @override
  String get episodesTileSyncing => 'Gerade erstellt – wird synchronisiert …';

  @override
  String get episodesTileSyncingStale =>
      'Erstellt – die Liste wird noch aktualisiert. Ziehe zum Aktualisieren nach unten.';

  @override
  String get episodesEmpty => 'Noch keine Episoden';

  @override
  String get episodesCreateFirst => 'Erste Episode erstellen';

  @override
  String episodesNotFound(Object code) {
    return 'Dieser Block existiert nicht mehr ($code).';
  }

  @override
  String get episodesBackToBlocks => 'Zurück zu den Blöcken';

  @override
  String get episodesAddFab => 'Episode hinzufügen';

  @override
  String episodesFetchError(Object code) {
    return 'Episoden konnten nicht geladen werden ($code).';
  }

  @override
  String get episodesStaleBanner =>
      'Zwischengespeicherte Daten sind möglicherweise veraltet.';

  @override
  String get episodesDismiss => 'Ausblenden';

  @override
  String get episodesCreateTitle => 'Episode erstellen';

  @override
  String get episodesNameLabel => 'Name (optional)';

  @override
  String get episodesCreateErrorExists =>
      'Eine Episode mit dieser Nummer existiert bereits.';

  @override
  String get episodesCreateErrorNetwork =>
      'Netzwerkproblem – die Episode wurde nicht erstellt. Versuch es erneut.';

  @override
  String episodesCreateErrorGeneric(Object code) {
    return 'Die Episode konnte nicht erstellt werden ($code).';
  }

  @override
  String sceneTileLabel(Object identifier) {
    return 'Szene $identifier';
  }

  @override
  String sceneMood(Object mood) {
    return 'Stimmung: $mood';
  }

  @override
  String sceneLoc(Object loc) {
    return 'Ort: $loc';
  }

  @override
  String sceneDay(Object day) {
    return 'Tag: $day';
  }

  @override
  String get sceneScheduled => 'Eingeplant';

  @override
  String get sceneUnscheduled => 'Nicht eingeplant';

  @override
  String sceneCharacterCount(Object count) {
    return '$count Figuren';
  }

  @override
  String sceneShootingDayCount(Object count) {
    return '$count Drehtage';
  }

  @override
  String get scenesTileSyncing => 'Gerade erstellt – wird synchronisiert …';

  @override
  String get scenesTileSyncingStale =>
      'Erstellt – die Liste wird noch aktualisiert. Ziehe zum Aktualisieren nach unten.';

  @override
  String get scenesEmpty => 'Noch keine Szenen';

  @override
  String get scenesCreateFirst => 'Erste Szene erstellen';

  @override
  String scenesNotFound(Object code) {
    return 'Diese Episode existiert nicht mehr ($code).';
  }

  @override
  String get scenesBackToEpisodes => 'Zurück zu den Episoden';

  @override
  String get scenesAddFab => 'Szene hinzufügen';

  @override
  String scenesFetchError(Object code) {
    return 'Szenen konnten nicht geladen werden ($code).';
  }

  @override
  String get scenesCreateTitle => 'Szene erstellen';

  @override
  String get sceneNumberLabel => 'Szenennummer (optional)';

  @override
  String get sceneSummaryLabel => 'Zusammenfassung (optional)';

  @override
  String get sceneMoodLabel => 'Stimmung (optional)';

  @override
  String get sceneLocationLabel => 'Ort (optional)';

  @override
  String get sceneScriptDayLabel => 'Drehtag im Skript (optional)';

  @override
  String get scenesCreateErrorNetwork =>
      'Netzwerkproblem – die Szene wurde nicht erstellt. Versuch es erneut.';

  @override
  String scenesCreateErrorGeneric(Object code) {
    return 'Die Szene konnte nicht erstellt werden ($code).';
  }

  @override
  String get scenesStaleBanner =>
      'Zwischengespeicherte Daten sind möglicherweise veraltet.';

  @override
  String get settingsTitle => 'Einstellungen';

  @override
  String get settingsServerAddress => 'Serveradresse';

  @override
  String get settingsFlavor => 'Flavor';

  @override
  String get settingsBackendUri => 'Backend-URI';

  @override
  String get settingsProdNote =>
      'Die Serveradresse wird von deiner Organisation sicherheitsbedingt festgelegt und kann hier nicht geändert werden.';

  @override
  String get settingsReset => 'Zurücksetzen';

  @override
  String get settingsSave => 'Speichern';

  @override
  String get settingsClose => 'Schließen';

  @override
  String get commonDismiss => 'Schließen';

  @override
  String get commonCancel => 'Abbrechen';

  @override
  String get commonSave => 'Speichern';

  @override
  String get commonDelete => 'Löschen';

  @override
  String get commonEdit => 'Bearbeiten';

  @override
  String get commonClose => 'Schließen';

  @override
  String get commonMore => 'Mehr';

  @override
  String get commonSettings => 'Einstellungen';

  @override
  String get commonAiImportJobs => 'KI-Import-Aufträge';

  @override
  String get commonSignOut => 'Abmelden';

  @override
  String get commonAbout => 'Über die App';

  @override
  String get commonNoResults => 'Keine Treffer';

  @override
  String get commonSignedIn => 'Angemeldet';

  @override
  String get commonSignedOut => 'Abgemeldet';

  @override
  String get commonUnknown => 'Unbekannt';

  @override
  String get navCast => 'Cast';

  @override
  String get navScript => 'Script';

  @override
  String get viewTitleScript => 'Szenen aus dem Skript';

  @override
  String get navSchedule => 'Schedule/Dispo';

  @override
  String get navWardrobe => 'Garderobe';

  @override
  String get navCharacters => 'Figuren';

  @override
  String get navAiImport => 'Import';

  @override
  String get navShootingDays => 'Drehtage';

  @override
  String get navEpisodes => 'Episoden';

  @override
  String get navScenes => 'Szenen';

  @override
  String get shellPlusFabLabel => 'Erstellen';

  @override
  String get offlinePillLabel => 'Offline – Daten können veraltet sein';

  @override
  String get healthPillHealthy => 'Backend bereit';

  @override
  String get healthPillDegraded => 'Backend eingeschränkt';

  @override
  String get healthPillUnhealthy => 'Backend gestört';

  @override
  String get healthPillOffline => 'Backend nicht erreichbar';

  @override
  String get healthPillOpenHint => 'Details zum Backend-Status öffnen';

  @override
  String get healthDetailTitle => 'Backend-Status';

  @override
  String get healthDetailDependencies => 'Abhängigkeiten';

  @override
  String get healthDetailNoDependencies =>
      'Der Server meldet keine Details zu den Abhängigkeiten.';

  @override
  String get healthDetailOfflineBody =>
      'Der Server ist nicht erreichbar. Sobald die Verbindung wieder steht, wird der Status erneut abgefragt.';

  @override
  String get healthDetailPending => 'Status wird abgefragt …';

  @override
  String get healthCheckDatabase => 'Datenbank';

  @override
  String get healthCheckEventStore => 'Ereignisspeicher';

  @override
  String get healthCheckSecrets => 'Geheimnisverwaltung';

  @override
  String get healthCheckAiStorage => 'KI-Dateispeicher';

  @override
  String get healthCheckOther => 'Weitere Abhängigkeit';

  @override
  String get healthCheckStatusHealthy => 'bereit';

  @override
  String get healthCheckStatusDegraded => 'eingeschränkt';

  @override
  String get healthCheckStatusUnhealthy => 'gestört';

  @override
  String get quickCreateTitle => 'Was möchtest du erstellen?';

  @override
  String get quickCreateAiImportSubtitle =>
      'Spielplan oder Skript per KI importieren';

  @override
  String get quickCreateWizardSubtitle =>
      'Season, Blöcke und Episoden geführt anlegen';

  @override
  String get quickCreateSceneTitle => 'Neue Szene';

  @override
  String get quickCreateSceneSubtitle => 'Szene in der aktiven Episode anlegen';

  @override
  String get quickCreateShootingDayTitle => 'Neuer Drehtag';

  @override
  String get quickCreateShootingDaySubtitle =>
      'Drehtag in der aktiven Episode planen';

  @override
  String locationStripSemantics(Object path) {
    return 'Position: $path';
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
  String get scopeChipSeasonTooltip => 'Aktive Season wählen';

  @override
  String get scopeChipSeasonPickTitle => 'Season wählen';

  @override
  String get scopeChipSeasonUnset => 'Season wählen';

  @override
  String get seasonScopeManageSeasons => 'Seasons verwalten';

  @override
  String get seasonScopeManageProduction => 'Produktion verwalten';

  @override
  String get seasonScopeEmpty => 'Noch keine Seasons vorhanden.';

  @override
  String get scopeChipUnknownBlock => 'Filter: Block unbekannt';

  @override
  String get scopeChipForeignSeason => 'Filter gilt hier nicht – andere Season';

  @override
  String get scopeChipTooltip => 'Aktiven Block-Filter ändern';

  @override
  String get scopeChipPickTitle => 'Block-Filter wählen';

  @override
  String get scopeChipBlockUnset => 'Block wählen';

  @override
  String get scopeChipBlockUnsetTooltip => 'Aktiven Block-Filter wählen';

  @override
  String get episodeChipTooltip => 'Aktive Episode ändern';

  @override
  String get episodeChipPickTitle => 'Episode wählen';

  @override
  String get episodeChipEmpty => 'Noch keine Episoden in diesem Block.';

  @override
  String get episodeChipUnset => 'Episode wählen';

  @override
  String get episodeChipUnsetTooltip => 'Aktive Episode wählen';

  @override
  String get seasonsTitle => 'Seasons';

  @override
  String get seasonsStaleJustNow => 'gerade eben';

  @override
  String get reconcileStaleWarning =>
      'Erstellt – die Liste wird noch aktualisiert. Ziehe zum Aktualisieren nach unten.';

  @override
  String seasonsStaleMinutes(Object count) {
    return 'vor $count min';
  }

  @override
  String seasonsStaleHours(Object count) {
    return 'vor $count h';
  }

  @override
  String seasonsStaleDays(Object count) {
    return 'vor $count d';
  }

  @override
  String get seasonsEmptyTitle => 'Noch keine Seasons';

  @override
  String get seasonsEmptyGuidance =>
      'Lege deine erste Season an — oder importiere einen bestehenden Spielplan per KI.';

  @override
  String get seasonsEmptySetupCta => 'Season-Setup starten';

  @override
  String get seasonsEmptyImportCta => 'KI-Import öffnen';

  @override
  String get seasonsLoadError => 'Seasons konnten nicht geladen werden';

  @override
  String get seasonsStale =>
      'Zwischengespeicherte Daten sind möglicherweise veraltet';

  @override
  String get seasonsCreateConflict =>
      'Eine Season mit dieser Nummer existiert bereits.';

  @override
  String get seasonsCreateAuth => 'Bitte melde dich an, um fortzufahren.';

  @override
  String get seasonsCreateNetwork =>
      'Netzwerkproblem — die Season wurde nicht erstellt. Bitte versuche es erneut.';

  @override
  String get seasonsCreateGeneric => 'Die Season konnte nicht erstellt werden.';

  @override
  String get seasonsCreateSeriesIdMissing =>
      'Diese App wurde ohne DEFAULT_PROJECT_ID gebaut: Die neue Season kann keiner Serie zugeordnet werden. Baue die App mit --dart-define=DEFAULT_PROJECT_ID=<ID der Standardserie> neu.';

  @override
  String get seasonsSetupCta => 'Season-Setup starten';

  @override
  String get seasonsManualCreateCta => 'Manuell';

  @override
  String seasonsDefaultTitle(Object number) {
    return 'Season $number';
  }

  @override
  String get seasonsSyncing => 'Wird erstellt — Synchronisierung läuft…';

  @override
  String seasonsStaleAt(Object relative) {
    return 'Stand: $relative';
  }

  @override
  String seasonsMetaBlocks(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Blöcke',
      one: '1 Block',
    );
    return '$_temp0';
  }

  @override
  String seasonsMetaScenes(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Szenen',
      one: '1 Szene',
    );
    return '$_temp0';
  }

  @override
  String seasonsMetaPieces(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Kleidungsstücke',
      one: '1 Kleidungsstück',
    );
    return '$_temp0';
  }

  @override
  String get productionTitle => 'Produktion';

  @override
  String get productionBlocksSubtitle =>
      'Blöcke und Episoden der aktiven Season';

  @override
  String get productionNoActiveSeason => 'Wähle zuerst eine Season.';

  @override
  String get planningImportSubtitle => 'KI-Assistent: Spielplan importieren';

  @override
  String get planningActiveJobRow => 'KI-Import läuft – Status prüfen';

  @override
  String get authSignIn => 'Anmelden';

  @override
  String get authContinue => 'Weiter';

  @override
  String get authSignOut => 'Abmelden';

  @override
  String get authWip => 'In Arbeit';

  @override
  String authDevNotice(Object subject) {
    return 'Entwickleranmeldung aktiv — Fortfahren als $subject.';
  }

  @override
  String authContinueAs(Object subject) {
    return 'Als $subject fortfahren';
  }

  @override
  String get authSignedIn => 'Angemeldet';

  @override
  String get authErrorConfiguration =>
      'Die Anmeldung ist in diesem Build nicht verfügbar.';

  @override
  String get authErrorRestore =>
      'Die vorherige Sitzung konnte nicht wiederhergestellt werden. Bitte melde dich erneut an.';

  @override
  String get authErrorSignInFailed =>
      'Anmeldung fehlgeschlagen. Bitte versuche es erneut.';

  @override
  String get authErrorNetwork =>
      'Netzwerkproblem — die Anmeldung wurde nicht abgeschlossen. Bitte versuche es erneut.';

  @override
  String get authErrorGeneric =>
      'Etwas ist schiefgelaufen. Bitte versuche es erneut.';

  @override
  String get fatalConfigTitle => 'TLS-Konfiguration ungültig';

  @override
  String fatalConfigBody(Object error) {
    return 'Die App kann sicher nicht gestartet werden: $error\nEs wurden keine Netzwerkanfragen gesendet.';
  }

  @override
  String get infoTitle => 'Über Breakdown';

  @override
  String get infoVersion => 'Version';

  @override
  String get infoLicense => 'Lizenz';

  @override
  String get infoLicenseBody =>
      'GNU Affero General Public License v3.0. Dies ist freie Software: Du darfst sie verwenden, untersuchen, weitergeben und verändern.';

  @override
  String get infoSource => 'Quellcode ansehen';

  @override
  String get infoSourceError =>
      'Der Quellcode-Link konnte nicht geöffnet werden.';

  @override
  String get infoBackendVersions => 'Backend-Komponenten';

  @override
  String get infoBackendVersionsSubtitle =>
      'Vom Backend gemeldete Versionen der Arbeitsbereich-Komponenten.';

  @override
  String get infoBackendVersionsError =>
      'Backend-Versionen konnten nicht geladen werden.';

  @override
  String get infoCredits => 'Mitwirkende';

  @override
  String get infoCreditsSubtitle =>
      'Die Menschen und KI-Modelle hinter dieser App.';

  @override
  String get creditsTitle => 'Mitwirkende';

  @override
  String get creditsCloudTitle => 'Dank an alle Mitwirkenden';

  @override
  String get creditsCloudBody =>
      'Die KI-Modelle (mit ihrem Anbieter) und die menschlichen Mitwirkenden (mit ihren Rollen), die an diesem Projekt mitgewirkt haben.';

  @override
  String get creditsError => 'Mitwirkende konnten nicht geladen werden.';

  @override
  String get creditsRoleLabel => 'Rollen';

  @override
  String get creditsLlmLabel => 'KI-Co-Autor';

  @override
  String creditsSemanticHuman(Object name, Object roles) {
    return '$name, $roles';
  }

  @override
  String creditsSemanticLlm(Object name, Object provider) {
    return '$name, KI-Co-Autor von $provider';
  }

  @override
  String get creditsShouldersTitle => 'Auf der Schulter von Riesen';

  @override
  String get creditsShouldersBody =>
      'Diese App baut auf diesen freien Technologien auf.';

  @override
  String get creditsRustLabel => 'Rust — die Backend-Sprache';

  @override
  String get creditsFlutterLabel => 'Flutter — das App-Framework';

  @override
  String get infoAiUsage => 'KI-Nutzung';

  @override
  String get infoAiBody =>
      'Beim ausdrücklichen Absenden von Importen wird der von Dir bereitgestellte Text an einen konfigurierten serverseitigen KI-Anbieter gesendet. Diese App kontaktiert KI-Anbieter nicht direkt.';

  @override
  String get aiImportDisclosureTitle => 'KI-Verarbeitung';

  @override
  String get aiImportDisclosureBody =>
      'Die gewählte Datei wird von einem serverseitigen KI-Import verarbeitet. Die Ergebnisse sind KI-generiert und müssen vor dem Anwenden in der Vorschau geprüft werden.';

  @override
  String aiNamingLine(Object model, Object provider) {
    return 'Derzeit konfiguriert: Anbieter $provider, Modell $model.';
  }

  @override
  String get aiPreviewAiBanner => 'KI-extrahierter Inhalt – sorgfältig prüfen';

  @override
  String get aiPreviewAiNote =>
      'Alle Zeilen sind maschinell extrahierte Entwürfe. Die Vorschau enthält keine maschinell verifizierten Zuverlässigkeitswerte.';

  @override
  String get aiApplyReviewCheckbox =>
      'Ich habe den KI-extrahierten Inhalt geprüft';

  @override
  String get aiProvenanceBadge => 'KI-extrahiert';

  @override
  String get aiDisclosureTitle => 'Über KI in der App';

  @override
  String get aiDisclosurePurposeTitle => 'Zweck';

  @override
  String get aiDisclosurePurposeBody =>
      'Der KI-Import extrahiert Strukturen (Szenen, Drehtage) aus von Dir bereitgestellten Drehplan- und Skript-Dokumenten, damit die Zusammenarbeit schneller beginnt.';

  @override
  String get aiDisclosureFlowTitle => 'Datenfluss';

  @override
  String get aiDisclosureFlowBody =>
      'Gerät → Backend → konfigurierter KI-Anbieter → Entwürfe → Vorschau → ausdrückliches Anwenden. Die App kommuniziert nie direkt mit dem KI-Anbieter.';

  @override
  String get aiDisclosureNamingTitle => 'Anbieter und Modelle';

  @override
  String aiDisclosureNamingBodyConfigured(Object model, Object provider) {
    return 'Konfiguriert: Anbieter $provider, Assistent-Modell $model.';
  }

  @override
  String get aiDisclosureNamingBodyUnconfigured =>
      'Für dieses Konto ist keine KI-Konfiguration eingerichtet.';

  @override
  String get aiDisclosureNamingBodyLoading =>
      'Anbieter und Modelle werden geladen …';

  @override
  String get aiDisclosureRetentionTitle => 'Aufbewahrung';

  @override
  String get aiDisclosureRetentionBody =>
      'Importierte Dokumentdaten werden nach 7 Tagen automatisch gelöscht; danach bleibt nur das ausdrücklich angewendete Ergebnis im Projekt.';

  @override
  String get aiDisclosureActTitle => 'EU-KI-Gesetz';

  @override
  String get aiDisclosureActBody =>
      'Dieser Hinweis folgt der KI-Verordnung (EU) 2024/1689, Artikel 4 (KI-Kompetenz) und Artikel 50 (Transparenz): KI-generierte Inhalte werden gekennzeichnet und müssen geprüft werden.';

  @override
  String get aiConfigLiteracyTitle => 'KI-Kompetenz';

  @override
  String get aiConfigLiteracyBody =>
      'Diese Konfiguration steuert, welchen KI-Anbieter und welche Modelle der serverseitige Import nutzt und welche Extraktions-Prompts gelten. Der konfigurierte Anbieter verarbeitet die von Nutzenden bereitgestellten Dokumente — konfiguriere kuratierte Anbieter und Modelle ehrlich.';

  @override
  String scriptFetchError(Object code) {
    return 'Das Script konnte nicht geladen werden ($code).';
  }

  @override
  String scriptPartialBlocks(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Blöcke',
      one: '1 Block',
    );
    return 'Teilweise geladen: $_temp0 konnten nicht gelesen werden.';
  }

  @override
  String scriptPartialLoad(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Episoden',
      one: '1 Episode',
    );
    return 'Teilweise geladen: $_temp0 konnten nicht gelesen werden.';
  }

  @override
  String scriptSceneNumber(Object number) {
    return 'Szene $number';
  }

  @override
  String get scriptSceneNumberUnknown => 'Szene ohne Nummer';

  @override
  String scriptEpisodeLabel(Object episode) {
    return 'Episode $episode';
  }

  @override
  String get scriptNoScenes => 'Noch keine Szenen in dieser Season.';

  @override
  String scriptRowEpisodeScene(Object episode, Object number) {
    return '$episode, Szene $number';
  }

  @override
  String scriptRowCharacters(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Figuren',
      one: '1 Figur',
    );
    return '$_temp0';
  }

  @override
  String scriptRowOutfits(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Looks',
      one: '1 Look',
    );
    return '$_temp0';
  }

  @override
  String scheduleFetchError(Object code) {
    return 'Der Dispo konnte nicht geladen werden ($code).';
  }

  @override
  String get scheduleNoDays =>
      'Für diese Season sind noch keine Drehtage geplant.';

  @override
  String schedulePartialBlocks(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Blöcke',
      one: '1 Block',
    );
    return 'Teilweise geladen: $_temp0 konnten nicht gelesen werden.';
  }

  @override
  String schedulePartialLoad(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Episoden',
      one: '1 Episode',
    );
    return 'Teilweise geladen: $_temp0 konnten nicht gelesen werden.';
  }

  @override
  String scheduleDayLabel(Object date) {
    return 'Drehtag $date';
  }

  @override
  String get scheduleDayUndated => 'Drehtag ohne Datum';

  @override
  String get profileTooltip => 'Menü';

  @override
  String get profileTitle => 'Profil';

  @override
  String get genericProblemTitle => 'Etwas ist schiefgelaufen';

  @override
  String get genericProblemBody =>
      'Die Aktion konnte nicht abgeschlossen werden. Bitte versuche es erneut.';

  @override
  String get genericProblemAction => 'Erneut versuchen';

  @override
  String get problemAuthzDenied =>
      'Für diese Aktion fehlt dir die Berechtigung.';

  @override
  String get problemAuthzSessionRequired =>
      'Bitte melde dich an, um fortzufahren.';

  @override
  String get problemNetwork =>
      'Die Verbindung zum Server ist fehlgeschlagen. Bitte versuche es erneut.';

  @override
  String shootingDaySemantics(Object label) {
    return 'Drehtag $label';
  }

  @override
  String get shootingDayUntitled => 'Drehtag ohne Titel';

  @override
  String get shootingDayArchived => 'Archiviert';

  @override
  String get shootingDayWrapped => 'Abgeschlossen';

  @override
  String get shootingDayActions => 'Tagesaktionen';

  @override
  String get shootingDayMoveEarlier => 'Nach vorne verschieben';

  @override
  String get shootingDayMoveLater => 'Nach hinten verschieben';

  @override
  String get shootingDayRename => 'Umbenennen';

  @override
  String get shootingDayReschedule => 'Neuer Drehtag';

  @override
  String get shootingDayUnschedule => 'Datum entfernen';

  @override
  String get shootingDayArchive => 'Archivieren';

  @override
  String get shootingDayNew => 'Neuer Drehtag';

  @override
  String get shootingDaysEmpty => 'Noch keine Drehtage';

  @override
  String get shootingDaysCreate => 'Drehtag erstellen';

  @override
  String get shootingDaysGone => 'Die Episode ist nicht mehr verfügbar.';

  @override
  String get commonBack => 'Zurück';

  @override
  String seasonTabSemantic(Object label, Object position, Object total) {
    return '$label, Tab $position von $total';
  }

  @override
  String seasonTabSemanticEn(Object label, Object position, Object total) {
    return '$label, Tab $position of $total';
  }

  @override
  String get settingsGeneral => 'Allgemein';

  @override
  String get settingsEasterEggs => 'Easter-Eggs';

  @override
  String get settingsEasterEggsSubtitle =>
      'Kleine Überraschungen in der App lassen sich ein- und ausschalten.';

  @override
  String get settingsEasterEggsWriteError =>
      'Die Einstellung konnte nicht gespeichert werden. Die Änderung gilt nur bis zum Neustart.';

  @override
  String get settingsEasterEggsError =>
      'Die Einstellung konnte nicht gelesen werden – Standard (eingeschaltet) bleibt aktiv.';

  @override
  String get settingsEasterEggsKarlKleiderbuegel => 'Karl Kleiderbügel';

  @override
  String get settingsEasterEggsKarlKleiderbuegelSubtitle =>
      'Der Kleiderbügel-Assistent hilft im KI-Import mit Tipps und Sprüchen.';

  @override
  String get settingsEasterEggsDejavuCat => 'Déjà-vu-Katze';

  @override
  String get settingsEasterEggsDejavuCatSubtitle =>
      'Im Oktober läuft eine schwarze Katze über den Startbildschirm und durch die leere Season-Liste. In der Vorschau hier ist sie jederzeit zu sehen.';

  @override
  String get settingsEasterEggsPreview => 'Vorschau';

  @override
  String get settingsEasterEggsPreviewSubtitle =>
      'Jedes Ei lässt sich hier in Ruhe ansehen — unabhängig vom Monat.';

  @override
  String get settingsEasterEggsEntryTitle => 'Easter-Eggs verwalten';

  @override
  String get settingsEasterEggsEntrySubtitle =>
      'Schalter und Vorschau für jedes Ei.';

  @override
  String get settingsEasterEggsScreenTitle => 'Easter-Eggs';

  @override
  String get settingsAiConfig => 'KI-Konfiguration';

  @override
  String get settingsAiConfigSubtitle =>
      'KI-Anbieter und Modelle für den KI-Import verwalten.';

  @override
  String get settingsAi => 'KI';

  @override
  String get settingsDev => 'Entwicklung';

  @override
  String get aiImportClippyNoConfig =>
      'Es sieht so aus, als wolltest du einen Spielplan importieren… Willst du zuerst eine KI-Konfiguration einrichten?';

  @override
  String get aiImportClippyRunning => 'Ich bin ganz Ohr!';

  @override
  String get aiImportClippyError =>
      'Das hat leider nicht geklappt. Aber gemeinsam kriegen wir das hin!';

  @override
  String get aiImportClippySuccess =>
      'Klasse! Der Import sitzt wie maßgeschneidert.';

  @override
  String get aiImportClippyQueued => 'Hmm, lass mich kurz überlegen…';

  @override
  String get aiImportClippyIdle1 =>
      'Wusstest du, dass „Klamotten“ umgangssprachlich Kleidung bedeutet? Der Name sitzt also doppelt.';

  @override
  String get aiImportClippyIdle2 => 'Ich bin ein Kleiderbügel mit Ambitionen.';

  @override
  String get aiImportClippyIdle3 => 'Häng dich nicht auf – ich bin ja da.';

  @override
  String get aiImportClippyIdle4 =>
      'Ein Kleiderbügel kommt selten allein – meistens hängt er mit Freunden rum.';

  @override
  String get aiImportClippyIdle5 =>
      'Ordnung ist das halbe Leben. Die andere Hälfte ist der passende Bügel.';

  @override
  String get aiImportClippyDismissTooltip => 'Karl Kleiderbügel ausblenden';

  @override
  String get seasonsArchivedBadge => 'Archiviert';

  @override
  String get seasonsArchiveTooltip => 'Staffel-Aktionen';

  @override
  String get seasonsArchiveCta => 'Staffel archivieren';

  @override
  String get seasonsArchivedError =>
      'Die Staffel ist archiviert und kann nicht mehr geändert werden.';

  @override
  String get seasonsArchiveForbidden =>
      'Dafür fehlt dir die aktive Kostüm-Rolle in dieser Staffel.';

  @override
  String get omniSearchTitle => 'Suche';

  @override
  String get omniSearchTooltip => 'Suchen';

  @override
  String get omniSearchHint =>
      'Suchen: Szenen, Rollen, Kleidungsstücke, Drehtage dieser Staffel';

  @override
  String get omniSearchChipScene => 'Szene';

  @override
  String get omniSearchChipCharacter => 'Rolle';

  @override
  String get omniSearchChipPiece => 'Kleidungsstück';

  @override
  String get omniSearchChipShootingDay => 'Drehtag';

  @override
  String get omniSearchGroupScenes => 'Szenen';

  @override
  String get omniSearchGroupCharacters => 'Rollen';

  @override
  String get omniSearchGroupPieces => 'Kleidungsstücke';

  @override
  String get omniSearchGroupShootingDays => 'Drehtage';

  @override
  String get omniSearchInitialEmpty =>
      'Tippe, um die Szenen, Rollen, Kleidungsstücke und Drehtage dieser Staffel zu durchsuchen.';

  @override
  String omniSearchZeroMatch(String query, String facets) {
    return 'Keine Treffer für „$query“ in: $facets.';
  }

  @override
  String omniSearchNotLoaded(String facets) {
    return 'Noch nicht geladen: $facets. Öffne die zugehörige Ansicht, um die Daten zu laden.';
  }

  @override
  String get omniSearchError =>
      'Die Suche kann den lokalen Cache gerade nicht lesen.';

  @override
  String get omniSearchNoSeason =>
      'Wähle zuerst eine Staffel, um sie zu durchsuchen.';

  @override
  String get omniSearchStaleBanner =>
      'Diese Ergebnisse basieren auf dem lokalen Cache und können veraltet sein.';

  @override
  String get omniSearchRefresh => 'Aktualisieren';

  @override
  String get fundusTitle => 'Fundus';

  @override
  String get fundusTooltip => 'Fundus durchsuchen';

  @override
  String get fundusHint =>
      'Fundus durchsuchen: Kleidungsstücke über alle Staffeln';

  @override
  String get fundusEmpty => 'Der Fundus dieses Projekts ist leer.';

  @override
  String get fundusNotLoaded => 'Der Fundus wird noch geladen.';

  @override
  String fundusZeroMatch(String query) {
    return 'Keine Treffer für „$query“ im Fundus.';
  }

  @override
  String get fundusError =>
      'Der Fundus kann den lokalen Cache gerade nicht lesen.';

  @override
  String get fundusNoSeason =>
      'Wähle zuerst eine Staffel, um den Fundus zu durchsuchen.';

  @override
  String get fundusStaleBanner =>
      'Diese Ergebnisse basieren auf dem lokalen Cache und können veraltet sein.';

  @override
  String fundusRepertoireSeasons(String seasons) {
    return 'Staffeln: $seasons';
  }

  @override
  String aiPreviewShootingDay(Object day) {
    return 'Drehtag: $day';
  }

  @override
  String get aiApplyShootingDaysHeading => 'Drehtage aus dem Skript – anlegen?';

  @override
  String get aiApplyDayRejectedStatus =>
      'Nicht anlegen – Szenen dieses Tages bleiben ohne Drehtag.';

  @override
  String aiApplyDayCreateSummary(Object day) {
    return 'Drehtag „$day“ wird angelegt, die Szenen des Tages werden darauf geplant.';
  }

  @override
  String aiApplyDaySkipSummary(Object day) {
    return 'Drehtag „$day“ wird nicht angelegt – seine Szenen bleiben ohne Drehtag.';
  }

  @override
  String get aiApplyErrorMissingShootingDayGroup =>
      'Eine Drehtag-Gruppe passt nicht mehr zur Vorschau – lade die Vorschau neu und übernimm erneut.';

  @override
  String aiApplySkippedDayGroups(Object count) {
    return '$count abgelehnte Drehtag-Gruppe(n) – ihre Szenen wurden ohne Drehtag angelegt.';
  }

  @override
  String get shootingDayLinkInto => 'In echten Drehtag überführen';

  @override
  String get shootingDayLinkIntoTitle => 'In echten Drehtag überführen';

  @override
  String get shootingDayLinkIntoPick =>
      'Ziel-Drehtag wählen – Szenen und Soll-Einträge werden überführt, der KI-Drehtag wird archiviert.';

  @override
  String get shootingDayLinkIntoNoTarget =>
      'Kein passender Drehtag vorhanden. Lege zuerst einen echten Drehtag an.';

  @override
  String shootingDayLinkedInto(Object scenes, Object shoots) {
    return '$scenes Szenen überführt, $shoots Soll-Einträge geplant.';
  }

  @override
  String get shootingDayErrorTargetWrapped =>
      'Der Ziel-Drehtag ist bereits abgeschlossen – Überführen nicht möglich.';

  @override
  String get shootingDayErrorEpisodeMismatch =>
      'Die Drehtage gehören zu verschiedenen Episoden.';

  @override
  String get aiConfigDecisionSectionTitle => 'Decision-Modell (Bewertung)';

  @override
  String get aiConfigDecisionHint =>
      'Optionales Bewertungsmodell, das extrahierte Szenen, Kurzbeschreibungen und Spieltage mit einer 1–5-Sterne-Bewertung versieht. Die Sterne sind eine maschinell erstellte Entscheidungshilfe und ersetzen die menschliche Prüfung nicht.';

  @override
  String get aiConfigDecisionProviderLabel => 'Decision-Modell-Anbieter';

  @override
  String get aiConfigDecisionDisabled => '— keine (Bewertung deaktiviert) —';

  @override
  String get aiConfigDecisionModelLabel => 'Decision-Modell';

  @override
  String get aiConfigDecisionSameKey =>
      'Gleichen API-Schlüssel wie Extraktion verwenden';

  @override
  String get aiConfigDecisionApiKeyLabel => 'API-Schlüssel für Decision-Modell';

  @override
  String aiConfigDecisionKeyRemembered(Object provider) {
    return 'Gespeicherter Decision-Schlüssel für $provider wird verwendet.';
  }

  @override
  String get aiPreviewAiNoteScored =>
      'Alle Zeilen sind maschinell extrahierte Entwürfe. Die Sternbewertungen (1–5) sind maschinell erstellte Qualitätseinschätzungen des Decision-Modells und ersetzen die menschliche Prüfung nicht.';

  @override
  String aiPreviewFilterAll(Object count) {
    return 'Alle Szenen ($count)';
  }

  @override
  String aiPreviewFilterLowScore(Object count) {
    return 'Niedrige Bewertung ≤ ★★★ ($count)';
  }

  @override
  String get aiPreviewSceneScore => 'Szenen-Bewertung:';

  @override
  String get aiPreviewSynopsisScore => 'Kurzbeschreibung (TL;DR):';

  @override
  String get aiPreviewShootingDayScore => 'Drehtag-Bewertung:';

  @override
  String aiScoreStarsLabel(Object stars) {
    return '$stars von 5 Sternen';
  }

  @override
  String get aiConfigDecisionKeyMissing =>
      'Bitte gib einen API-Schlüssel für das Decision-Modell ein oder wähle „Gleichen API-Schlüssel wie Extraktion verwenden“.';

  @override
  String get outfitVariantMarker => 'Variante';

  @override
  String get outfitListTitle => 'Looks';

  @override
  String get outfitListEmpty => 'Noch keine Looks – erstelle den ersten.';

  @override
  String get outfitCreateAction => 'Look erstellen';

  @override
  String get outfitCreateTitle => 'Look erstellen';

  @override
  String get outfitNameLabel => 'Name';

  @override
  String get outfitNameRequired => 'Es ist ein Name erforderlich';

  @override
  String get outfitDetailTitle => 'Look';

  @override
  String outfitVariantOf(String name) {
    return 'Variante von $name';
  }

  @override
  String get outfitCreateVariant => 'Variante erstellen';

  @override
  String outfitPiecesTitle(String count) {
    return 'Kleidungsstücke ($count)';
  }

  @override
  String get outfitPiecesEmpty =>
      'Noch keine Kleidungsstücke – füge das erste hinzu.';

  @override
  String get outfitAddPiece => 'Kleidungsstück hinzufügen';

  @override
  String get outfitRemovePieceTooltip => 'Entfernen';

  @override
  String get outfitNotes => 'Notizen';

  @override
  String get outfitNotesHint => 'Notizen zum Look …';

  @override
  String get outfitSaveNotes => 'Notizen speichern';

  @override
  String get outfitPhotos => 'Fotos';

  @override
  String get outfitRenameTitle => 'Look umbenennen';

  @override
  String outfitPieceCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Kleidungsstücke',
      one: '1 Kleidungsstück',
    );
    return '$_temp0';
  }

  @override
  String outfitErrorGeneric(String code) {
    return 'Der Look konnte nicht gespeichert werden ($code).';
  }

  @override
  String get outfitErrorForbidden =>
      'Du benötigst eine aktive Kostüm-Rolle in dieser Staffel.';

  @override
  String get outfitErrorMembership =>
      'Berechtigungen konnten nicht überprüft werden – Verbindung prüfen und erneut versuchen.';

  @override
  String get outfitSaved => 'Look gespeichert.';

  @override
  String get outfitNotesSaved => 'Notizen gespeichert.';

  @override
  String outfitListFetchError(String code) {
    return 'Looks konnten nicht geladen werden ($code).';
  }

  @override
  String get outfitStaleBanner =>
      'Zwischengespeicherte Daten sind möglicherweise veraltet.';

  @override
  String outfitPieceListFetchError(String code) {
    return 'Kleidungsstücke konnten nicht geladen werden ($code).';
  }

  @override
  String get outfitDetailGone => 'Dieser Look ist nicht mehr verfügbar.';

  @override
  String get outfitPickPieceTitle => 'Kleidungsstück wählen';

  @override
  String get outfitPickPieceEmpty =>
      'Kein Kleidungsstück im Repertoire dieser Staffel.';

  @override
  String get outfitVariantCreated => 'Variante erstellt.';
}
