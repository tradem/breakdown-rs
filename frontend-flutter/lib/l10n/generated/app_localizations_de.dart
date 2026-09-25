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
  String get costumeErrorChanged =>
      'Woanders geändert – zum Aktualisieren ziehen und erneut versuchen.';

  @override
  String get costumeErrorForbidden =>
      'Du benötigst eine aktive Kostüm-Rolle in dieser Staffel.';

  @override
  String get costumeErrorMembership =>
      'Berechtigungen konnten nicht überprüft werden – Verbindung prüfen und erneut versuchen.';

  @override
  String costumeErrorGeneric(Object code) {
    return 'Das Kostüm konnte nicht gespeichert werden ($code).';
  }

  @override
  String get photoErrorRequiresCharacter =>
      'Ordne das Kostüm einer Figur zu, bevor du Fotos verwaltest.';

  @override
  String get photoErrorTooLarge =>
      'Das Bild ist auch nach der Verkleinerung noch zu groß.';

  @override
  String get photoErrorUnsupported =>
      'Nur JPEG-, PNG- und WebP-Fotos werden unterstützt.';

  @override
  String get photoErrorForbidden =>
      'Du benötigst eine aktive Kostüm-Rolle in dieser Staffel, um Fotos zu verwalten.';

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
  String get costumeAddFab => 'Kostüm erstellen';

  @override
  String get costumesStaleBanner =>
      'Zwischengespeicherte Daten sind möglicherweise veraltet.';

  @override
  String costumesFetchError(Object code) {
    return 'Kostüme konnten nicht geladen werden ($code).';
  }

  @override
  String costumeTileLabel(Object id) {
    return 'Kostüm $id';
  }

  @override
  String get costumeTileLabelFallback => 'Kostüm';

  @override
  String get costumeCategoryUncategorized => 'Ohne Kategorie';

  @override
  String get costumeDetailSaved => 'Kostümdaten gespeichert.';

  @override
  String costumeWornBy(Object name) {
    return 'Getragen von $name';
  }

  @override
  String costumeDetailsCount(Object count) {
    return '$count Details';
  }

  @override
  String costumePhotosCount(Object count) {
    return '$count Fotos';
  }

  @override
  String get costumeTileSyncing => 'Gerade gespeichert – wird synchronisiert …';

  @override
  String get costumeTileSyncingStale =>
      'Erstellt – die Liste wird noch aktualisiert. Ziehe zum Aktualisieren nach unten.';

  @override
  String get costumesEmpty => 'Noch keine Kostüme';

  @override
  String get createSeasonTitle => 'Staffel erstellen';

  @override
  String get createSeasonSeriesId => 'Serien-ID';

  @override
  String get createSeasonSeriesIdRequired => 'Serien-ID ist erforderlich';

  @override
  String get createSeasonTitleLabel => 'Titel';

  @override
  String get createSeasonWizardCta =>
      'Oder geführt einrichten: Season-Setup starten';

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
  String get aiJobReviewPreview => 'Vorschau prüfen';

  @override
  String get aiJobCheckAgain => 'Erneut prüfen';

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
  String aiApplyOutcome(Object applied, Object days, Object shoots) {
    return 'Angewendet: $applied Entwurf(e): $days Drehtag(e) erstellt, $shoots Szenen-Dreh(e) geplant.';
  }

  @override
  String get aiApplyBackToStart => 'Zurück zum Start';

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
    return 'Zwischengespeicherte Episoden konnten nicht gelesen werden ($error).';
  }

  @override
  String get aiEpisodePickerEmpty =>
      'Keine zwischengespeicherten Episoden – öffne zuerst einen Produktionsblock und wähle dann.';

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
      'Kamera-Zugriff ist deaktiviert. Aktiviere den Kamera-Zugriff in den Einstellungen, um Kostüme zu dokumentieren.';

  @override
  String get captureDeniedGallery =>
      'Der Fotogalerie-Zugriff ist deaktiviert. Aktiviere den Foto-Zugriff in den Einstellungen, um Kostüme zu dokumentieren.';

  @override
  String get captureUnavailable =>
      'Die Kamera ist derzeit nicht verfügbar. Prüfe die Einstellungen und versuch es erneut.';

  @override
  String get captureDeniedTitleCamera => 'Kamera-Zugriff deaktiviert';

  @override
  String get captureDeniedTitleGallery => 'Fotogalerie-Zugriff deaktiviert';

  @override
  String get costumeDetailTitle => 'Kostüm';

  @override
  String get costumeDetailCharacter => 'Figur';

  @override
  String get costumeDetailAssignGate =>
      'Du benötigst eine aktive Kostüm-Rolle in dieser Staffel, um Figuren zuzuweisen.';

  @override
  String get costumeDetailAssign => 'Zuweisen';

  @override
  String get costumeDetailReassign => 'Neu zuweisen';

  @override
  String get costumeDetailTextRequired => 'Text ist erforderlich';

  @override
  String get costumeDetailUnassigned => 'Nicht zugeordnet';

  @override
  String get costumeDetailUnassignTooltip => 'Zuordnung entfernen';

  @override
  String get costumeDetailUnassignTitle => 'Figur-Zuordnung entfernen?';

  @override
  String get costumeDetailUnassignMessage =>
      'Das Kostüm behält seine Details und Notizen; nur die Figurenbindung wird entfernt.';

  @override
  String get costumeDetailNotes => 'Notizen';

  @override
  String get costumeDetailNotesHint => 'Anpassungsnotizen …';

  @override
  String get costumeDetailSaveNotes => 'Notizen speichern';

  @override
  String get costumeDetailDetails => 'Details';

  @override
  String get costumeDetailNoDetails =>
      'Noch keine Details – füge unten das erste hinzu.';

  @override
  String get costumeDetailAddDetail => 'Detail hinzufügen';

  @override
  String get costumeDetailSubject => 'Betreff';

  @override
  String get costumeDetailText => 'Text';

  @override
  String get costumeDetailCategory => 'Kategorie';

  @override
  String get costumeDetailPhotos => 'Fotos';

  @override
  String get costumeDetailCamera => 'Kamera';

  @override
  String get costumeDetailGallery => 'Galerie';

  @override
  String get costumeDetailPromptTitle => 'Kostüme mit Fotos dokumentieren?';

  @override
  String get costumeDetailPromptBody =>
      'Fotos helfen dem Garderobenteam, Kostüme zu dokumentieren und Kontinuität zu verfolgen. Als Nächstes fragt das System nach dem Kamera-Zugriff.';

  @override
  String get costumeDetailNotNow => 'Später';

  @override
  String get costumeDetailContinue => 'Weiter';

  @override
  String get costumeDetailOpenSettings => 'Einstellungen öffnen';

  @override
  String get costumeDetailDeletePhotoMessage =>
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
  String get wizardErrorSeriesIdMissing =>
      'Diese App wurde ohne DEFAULT_SERIES_ID gebaut: Die neue Season kann keiner Serie zugeordnet werden. Baue die App mit --dart-define=DEFAULT_SERIES_ID=<ID der Standardserie> neu.';

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
  String get continuityStoreOn => 'Foto speichern unter …';

  @override
  String get continuityCostumeHint =>
      'Wähle das Kostüm, zu dem das Foto gehört – es wird am Kostüm gespeichert und mit diesem Shot verknüpft.';

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
  String get costumingTabNoSeason =>
      'Wähle im Planen-Tab eine Season, um Kostüme und Figuren zu sehen.';

  @override
  String get costumingTabPickSeason => 'Season im Planen-Tab wählen';

  @override
  String get photoGalleryAddPhoto => 'Foto hinzufügen';

  @override
  String get photoGalleryProcessingFailed => 'Verarbeitung fehlgeschlagen';

  @override
  String get photoGalleryCaptureAgain => 'Erneut aufnehmen';

  @override
  String get photoGalleryDeleteTooltip => 'Foto löschen';

  @override
  String photoTileSemantics(Object costumeId) {
    return 'Foto von Kostüm $costumeId';
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
      'Das Foto bleibt am Kostüm – nur die Verknüpfung zu diesem Shoot wird entfernt.';

  @override
  String get sceneShootDayFallback => 'Drehtag';

  @override
  String get sceneShootsReportsTooltip => 'Berichte';

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
  String get sceneDetailOpenDayBoard => 'Day-Board öffnen';

  @override
  String get sceneDetailScheduleOnDay => 'Auf Drehtag planen';

  @override
  String get sceneDetailScheduleTitle => 'Auf Drehtag planen';

  @override
  String sceneDetailFetchError(Object code) {
    return 'Szene konnte nicht geladen werden ($code).';
  }

  @override
  String get sceneDetailGone => 'Diese Szene ist nicht mehr verfügbar.';

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
  String get navSeasons => 'Season';

  @override
  String get navPlanen => 'Planen';

  @override
  String get navCostumes => 'Garderobe';

  @override
  String get navCharacters => 'Figuren';

  @override
  String get navAiImport => 'Import';

  @override
  String get navMore => 'Mehr';

  @override
  String get navShootingDays => 'Drehtage';

  @override
  String get navEpisodes => 'Episoden';

  @override
  String get navScenes => 'Szenen';

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
  String get seasonsCreate => 'Season erstellen';

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
  String seasonsMetaCostumes(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Kostüme',
      one: '1 Kostüm',
    );
    return '$_temp0';
  }

  @override
  String get planningNoSeasons => 'Noch keine Seasons';

  @override
  String get planningLoadError => 'Seasons konnten nicht geladen werden.';

  @override
  String planningSeasonNumber(Object number) {
    return 'Nummer $number';
  }

  @override
  String get planningImportSubtitle => 'KI-Assistent: Spielplan importieren';

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
  String get infoAiUsage => 'KI-Nutzung';

  @override
  String get infoAiBody =>
      'Beim ausdrücklichen Absenden von Importen wird der von Dir bereitgestellte Text an einen konfigurierten serverseitigen KI-Anbieter gesendet. Diese App kontaktiert KI-Anbieter nicht direkt.';

  @override
  String get moreTitle => 'Mehr';

  @override
  String get moreCategories => 'Kostüm-Kategorien';

  @override
  String get moreCategoriesOpenPlanen => 'Season im Planen-Tab öffnen';

  @override
  String get moreSignedIn => 'Angemeldet';

  @override
  String get moreSignedOut => 'Abgemeldet';

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
  String seasonTabSemantic(Object label, Object position) {
    return '$label, Tab $position von 4';
  }

  @override
  String seasonTabSemanticEn(Object label, Object position) {
    return '$label, Tab $position of 4';
  }
}
