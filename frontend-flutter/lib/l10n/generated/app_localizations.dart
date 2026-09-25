import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
  ];

  /// No description provided for @appTitleBreakdown.
  ///
  /// In de, this message translates to:
  /// **'Breakdown'**
  String get appTitleBreakdown;

  /// No description provided for @commonRetry.
  ///
  /// In de, this message translates to:
  /// **'Erneut versuchen'**
  String get commonRetry;

  /// No description provided for @costumeCategoriesTitle.
  ///
  /// In de, this message translates to:
  /// **'Kostüm-Kategorien'**
  String get costumeCategoriesTitle;

  /// No description provided for @costumeCategoryArchived.
  ///
  /// In de, this message translates to:
  /// **'Archiviert'**
  String get costumeCategoryArchived;

  /// No description provided for @costumeCategoryAddFab.
  ///
  /// In de, this message translates to:
  /// **'Kategorie hinzufügen'**
  String get costumeCategoryAddFab;

  /// No description provided for @costumeCategoryCreateTitle.
  ///
  /// In de, this message translates to:
  /// **'Kategorie erstellen'**
  String get costumeCategoryCreateTitle;

  /// No description provided for @costumeCategoryNameLabel.
  ///
  /// In de, this message translates to:
  /// **'Name'**
  String get costumeCategoryNameLabel;

  /// No description provided for @costumeCategoryNameRequired.
  ///
  /// In de, this message translates to:
  /// **'Es ist ein Name erforderlich'**
  String get costumeCategoryNameRequired;

  /// No description provided for @costumeCategoryRenameTitle.
  ///
  /// In de, this message translates to:
  /// **'Kategorie umbenennen'**
  String get costumeCategoryRenameTitle;

  /// No description provided for @costumeCategoryRenameButton.
  ///
  /// In de, this message translates to:
  /// **'Umbenennen'**
  String get costumeCategoryRenameButton;

  /// No description provided for @costumeCategoryArchiveTitle.
  ///
  /// In de, this message translates to:
  /// **'Kategorie archivieren?'**
  String get costumeCategoryArchiveTitle;

  /// No description provided for @costumeCategoryArchiveMessage.
  ///
  /// In de, this message translates to:
  /// **'\"{name}\" wird aus dem aktiven Vokabular ausgeblendet. Verwende den Umschalter „Archiviert“, um sie wieder anzuzeigen.'**
  String costumeCategoryArchiveMessage(Object name);

  /// No description provided for @costumeCategoryArchiveButton.
  ///
  /// In de, this message translates to:
  /// **'Archivieren'**
  String get costumeCategoryArchiveButton;

  /// No description provided for @costumeCategoriesFetchError.
  ///
  /// In de, this message translates to:
  /// **'Kategorien konnten nicht geladen werden ({code}).'**
  String costumeCategoriesFetchError(Object code);

  /// No description provided for @costumeCategoriesStaleBanner.
  ///
  /// In de, this message translates to:
  /// **'Zwischengespeicherte Daten sind möglicherweise veraltet.'**
  String get costumeCategoriesStaleBanner;

  /// No description provided for @costumeCategoryTileLabel.
  ///
  /// In de, this message translates to:
  /// **'Kategorie {name}'**
  String costumeCategoryTileLabel(Object name);

  /// No description provided for @costumeCategoriesTileSyncing.
  ///
  /// In de, this message translates to:
  /// **'Gerade erstellt – wird synchronisiert …'**
  String get costumeCategoriesTileSyncing;

  /// No description provided for @costumeCategoriesTileSyncingStale.
  ///
  /// In de, this message translates to:
  /// **'Erstellt – die Liste wird noch aktualisiert. Ziehe zum Aktualisieren nach unten.'**
  String get costumeCategoriesTileSyncingStale;

  /// No description provided for @shootingDayAddFab.
  ///
  /// In de, this message translates to:
  /// **'Drehtag erstellen'**
  String get shootingDayAddFab;

  /// No description provided for @shootingDayUnscheduleTitle.
  ///
  /// In de, this message translates to:
  /// **'Termin entfernen?'**
  String get shootingDayUnscheduleTitle;

  /// No description provided for @shootingDayUnscheduleMessage.
  ///
  /// In de, this message translates to:
  /// **'Das Kalenderdatum wird entfernt. Der Tag behält seine Reihenfolge und Bezeichnung.'**
  String get shootingDayUnscheduleMessage;

  /// No description provided for @shootingDayArchiveTitle.
  ///
  /// In de, this message translates to:
  /// **'Drehtag archivieren?'**
  String get shootingDayArchiveTitle;

  /// No description provided for @shootingDayArchiveMessage.
  ///
  /// In de, this message translates to:
  /// **'Archivierte Tage bleiben in der Projektion, werden aber in den Planungs-Auswahlen ausgeblendet.'**
  String get shootingDayArchiveMessage;

  /// No description provided for @shootingDayMoveNoRoom.
  ///
  /// In de, this message translates to:
  /// **'Hierher kann nicht verschoben werden – die benachbarten Ordnungsschlüssel lassen keinen Platz. Archiviere oder erstelle Drehtage neu, um neu auszubalancieren.'**
  String get shootingDayMoveNoRoom;

  /// No description provided for @shootingDayCreateTitle.
  ///
  /// In de, this message translates to:
  /// **'Drehtag erstellen'**
  String get shootingDayCreateTitle;

  /// No description provided for @shootingDayLabelHint.
  ///
  /// In de, this message translates to:
  /// **'Bezeichnung (z. B. 1. Tag)'**
  String get shootingDayLabelHint;

  /// No description provided for @shootingDayNoDate.
  ///
  /// In de, this message translates to:
  /// **'Noch kein Datum'**
  String get shootingDayNoDate;

  /// No description provided for @shootingDayDate.
  ///
  /// In de, this message translates to:
  /// **'Datum: {date}'**
  String shootingDayDate(Object date);

  /// No description provided for @shootingDayPickDate.
  ///
  /// In de, this message translates to:
  /// **'Datum wählen'**
  String get shootingDayPickDate;

  /// No description provided for @shootingDayRenameTitle.
  ///
  /// In de, this message translates to:
  /// **'Drehtag umbenennen'**
  String get shootingDayRenameTitle;

  /// No description provided for @shootingDayLabel.
  ///
  /// In de, this message translates to:
  /// **'Bezeichnung'**
  String get shootingDayLabel;

  /// No description provided for @shootingDayRenameButton.
  ///
  /// In de, this message translates to:
  /// **'Umbenennen'**
  String get shootingDayRenameButton;

  /// No description provided for @shootingDayArchiveButton.
  ///
  /// In de, this message translates to:
  /// **'Archivieren'**
  String get shootingDayArchiveButton;

  /// No description provided for @shootingDayUnscheduleButton.
  ///
  /// In de, this message translates to:
  /// **'Termin entfernen'**
  String get shootingDayUnscheduleButton;

  /// No description provided for @shootingDaysFetchError.
  ///
  /// In de, this message translates to:
  /// **'Drehtage konnten nicht geladen werden ({code}).'**
  String shootingDaysFetchError(Object code);

  /// No description provided for @shootingDaysStaleBanner.
  ///
  /// In de, this message translates to:
  /// **'Zwischengespeicherte Daten sind möglicherweise veraltet.'**
  String get shootingDaysStaleBanner;

  /// No description provided for @shootingDayErrorNetwork.
  ///
  /// In de, this message translates to:
  /// **'Netzwerkproblem – die Änderung wurde nicht gespeichert. Versuch es erneut.'**
  String get shootingDayErrorNetwork;

  /// No description provided for @shootingDayErrorGeneric.
  ///
  /// In de, this message translates to:
  /// **'Der Drehtag konnte nicht gespeichert werden ({code}).'**
  String shootingDayErrorGeneric(Object code);

  /// No description provided for @characterAddFab.
  ///
  /// In de, this message translates to:
  /// **'Figur erstellen'**
  String get characterAddFab;

  /// No description provided for @characterCreateTitle.
  ///
  /// In de, this message translates to:
  /// **'Figur erstellen'**
  String get characterCreateTitle;

  /// No description provided for @characterNameLabel.
  ///
  /// In de, this message translates to:
  /// **'Name'**
  String get characterNameLabel;

  /// No description provided for @characterNameRequired.
  ///
  /// In de, this message translates to:
  /// **'Es ist ein Name erforderlich'**
  String get characterNameRequired;

  /// No description provided for @characterCategoryLabelName.
  ///
  /// In de, this message translates to:
  /// **'Kategorie'**
  String get characterCategoryLabelName;

  /// No description provided for @characterCategoryMain.
  ///
  /// In de, this message translates to:
  /// **'Hauptbesetzung'**
  String get characterCategoryMain;

  /// No description provided for @characterCategoryGuest.
  ///
  /// In de, this message translates to:
  /// **'Gast'**
  String get characterCategoryGuest;

  /// No description provided for @characterCategoryExtra.
  ///
  /// In de, this message translates to:
  /// **'Komparse'**
  String get characterCategoryExtra;

  /// No description provided for @charactersFetchError.
  ///
  /// In de, this message translates to:
  /// **'Figuren konnten nicht geladen werden ({code}).'**
  String charactersFetchError(Object code);

  /// No description provided for @charactersEmpty.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Figuren'**
  String get charactersEmpty;

  /// No description provided for @charactersGone.
  ///
  /// In de, this message translates to:
  /// **'Die Staffel ist weg ({code}).'**
  String charactersGone(Object code);

  /// No description provided for @characterDetailTitleFallback.
  ///
  /// In de, this message translates to:
  /// **'Figur'**
  String get characterDetailTitleFallback;

  /// No description provided for @characterContact.
  ///
  /// In de, this message translates to:
  /// **'Kontakt'**
  String get characterContact;

  /// No description provided for @characterEmail.
  ///
  /// In de, this message translates to:
  /// **'E-Mail'**
  String get characterEmail;

  /// No description provided for @characterPhone.
  ///
  /// In de, this message translates to:
  /// **'Telefon'**
  String get characterPhone;

  /// No description provided for @characterSaveContact.
  ///
  /// In de, this message translates to:
  /// **'Kontakt speichern'**
  String get characterSaveContact;

  /// No description provided for @characterMeasurements.
  ///
  /// In de, this message translates to:
  /// **'Maße'**
  String get characterMeasurements;

  /// No description provided for @characterSaveMeasurements.
  ///
  /// In de, this message translates to:
  /// **'Maße speichern'**
  String get characterSaveMeasurements;

  /// No description provided for @characterTileLabel.
  ///
  /// In de, this message translates to:
  /// **'Figur {name}'**
  String characterTileLabel(Object name);

  /// No description provided for @characterTileSyncing.
  ///
  /// In de, this message translates to:
  /// **'Gerade erstellt – wird synchronisiert …'**
  String get characterTileSyncing;

  /// No description provided for @characterTileSyncingStale.
  ///
  /// In de, this message translates to:
  /// **'Erstellt – die Liste wird noch aktualisiert. Ziehe zum Aktualisieren nach unten.'**
  String get characterTileSyncingStale;

  /// No description provided for @charactersStaleBanner.
  ///
  /// In de, this message translates to:
  /// **'Zwischengespeicherte Daten sind möglicherweise veraltet.'**
  String get charactersStaleBanner;

  /// No description provided for @characterErrorNetwork.
  ///
  /// In de, this message translates to:
  /// **'Netzwerkproblem – die Änderung wurde nicht gespeichert. Versuch es erneut.'**
  String get characterErrorNetwork;

  /// No description provided for @characterErrorGeneric.
  ///
  /// In de, this message translates to:
  /// **'Die Figur konnte nicht gespeichert werden ({code}).'**
  String characterErrorGeneric(Object code);

  /// No description provided for @costumeErrorChanged.
  ///
  /// In de, this message translates to:
  /// **'Woanders geändert – zum Aktualisieren ziehen und erneut versuchen.'**
  String get costumeErrorChanged;

  /// No description provided for @costumeErrorForbidden.
  ///
  /// In de, this message translates to:
  /// **'Du benötigst eine aktive Kostüm-Rolle in dieser Staffel.'**
  String get costumeErrorForbidden;

  /// No description provided for @costumeErrorMembership.
  ///
  /// In de, this message translates to:
  /// **'Berechtigungen konnten nicht überprüft werden – Verbindung prüfen und erneut versuchen.'**
  String get costumeErrorMembership;

  /// No description provided for @costumeErrorGeneric.
  ///
  /// In de, this message translates to:
  /// **'Das Kostüm konnte nicht gespeichert werden ({code}).'**
  String costumeErrorGeneric(Object code);

  /// No description provided for @photoErrorRequiresCharacter.
  ///
  /// In de, this message translates to:
  /// **'Ordne das Kostüm einer Figur zu, bevor du Fotos verwaltest.'**
  String get photoErrorRequiresCharacter;

  /// No description provided for @photoErrorTooLarge.
  ///
  /// In de, this message translates to:
  /// **'Das Bild ist auch nach der Verkleinerung noch zu groß.'**
  String get photoErrorTooLarge;

  /// No description provided for @photoErrorUnsupported.
  ///
  /// In de, this message translates to:
  /// **'Nur JPEG-, PNG- und WebP-Fotos werden unterstützt.'**
  String get photoErrorUnsupported;

  /// No description provided for @photoErrorForbidden.
  ///
  /// In de, this message translates to:
  /// **'Du benötigst eine aktive Kostüm-Rolle in dieser Staffel, um Fotos zu verwalten.'**
  String get photoErrorForbidden;

  /// No description provided for @photoErrorNetwork.
  ///
  /// In de, this message translates to:
  /// **'Netzwerkproblem – die Fotoänderung wurde nicht gespeichert. Versuch es erneut.'**
  String get photoErrorNetwork;

  /// No description provided for @photoErrorGeneric.
  ///
  /// In de, this message translates to:
  /// **'Das Foto konnte nicht gespeichert werden ({code}).'**
  String photoErrorGeneric(Object code);

  /// No description provided for @photoDeleteTitle.
  ///
  /// In de, this message translates to:
  /// **'Foto löschen?'**
  String get photoDeleteTitle;

  /// No description provided for @photoDeleteMessage.
  ///
  /// In de, this message translates to:
  /// **'Das Foto wird dauerhaft gelöscht. Dieser Schritt kann nicht rückgängig gemacht werden.'**
  String get photoDeleteMessage;

  /// No description provided for @costumeAddFab.
  ///
  /// In de, this message translates to:
  /// **'Kostüm erstellen'**
  String get costumeAddFab;

  /// No description provided for @costumesStaleBanner.
  ///
  /// In de, this message translates to:
  /// **'Zwischengespeicherte Daten sind möglicherweise veraltet.'**
  String get costumesStaleBanner;

  /// No description provided for @costumesFetchError.
  ///
  /// In de, this message translates to:
  /// **'Kostüme konnten nicht geladen werden ({code}).'**
  String costumesFetchError(Object code);

  /// No description provided for @costumeTileLabel.
  ///
  /// In de, this message translates to:
  /// **'Kostüm {id}'**
  String costumeTileLabel(Object id);

  /// No description provided for @costumeTileLabelFallback.
  ///
  /// In de, this message translates to:
  /// **'Kostüm'**
  String get costumeTileLabelFallback;

  /// No description provided for @costumeCategoryUncategorized.
  ///
  /// In de, this message translates to:
  /// **'Ohne Kategorie'**
  String get costumeCategoryUncategorized;

  /// No description provided for @costumeDetailSaved.
  ///
  /// In de, this message translates to:
  /// **'Kostümdaten gespeichert.'**
  String get costumeDetailSaved;

  /// No description provided for @costumeWornBy.
  ///
  /// In de, this message translates to:
  /// **'Getragen von {name}'**
  String costumeWornBy(Object name);

  /// No description provided for @costumeDetailsCount.
  ///
  /// In de, this message translates to:
  /// **'{count} Details'**
  String costumeDetailsCount(Object count);

  /// No description provided for @costumePhotosCount.
  ///
  /// In de, this message translates to:
  /// **'{count} Fotos'**
  String costumePhotosCount(Object count);

  /// No description provided for @costumeTileSyncing.
  ///
  /// In de, this message translates to:
  /// **'Gerade gespeichert – wird synchronisiert …'**
  String get costumeTileSyncing;

  /// No description provided for @costumeTileSyncingStale.
  ///
  /// In de, this message translates to:
  /// **'Erstellt – die Liste wird noch aktualisiert. Ziehe zum Aktualisieren nach unten.'**
  String get costumeTileSyncingStale;

  /// No description provided for @costumesEmpty.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Kostüme'**
  String get costumesEmpty;

  /// No description provided for @createSeasonTitle.
  ///
  /// In de, this message translates to:
  /// **'Staffel erstellen'**
  String get createSeasonTitle;

  /// No description provided for @createSeasonSeriesId.
  ///
  /// In de, this message translates to:
  /// **'Serien-ID'**
  String get createSeasonSeriesId;

  /// No description provided for @createSeasonSeriesIdRequired.
  ///
  /// In de, this message translates to:
  /// **'Serien-ID ist erforderlich'**
  String get createSeasonSeriesIdRequired;

  /// No description provided for @createSeasonTitleLabel.
  ///
  /// In de, this message translates to:
  /// **'Titel'**
  String get createSeasonTitleLabel;

  /// No description provided for @createSeasonWizardCta.
  ///
  /// In de, this message translates to:
  /// **'Oder geführt einrichten: Season-Setup starten'**
  String get createSeasonWizardCta;

  /// No description provided for @reportsTitle.
  ///
  /// In de, this message translates to:
  /// **'Berichte – {label}'**
  String reportsTitle(Object label);

  /// No description provided for @reportsSollIstTitle.
  ///
  /// In de, this message translates to:
  /// **'Geplant vs. tatsächlich'**
  String get reportsSollIstTitle;

  /// No description provided for @reportsPlannedLabel.
  ///
  /// In de, this message translates to:
  /// **'Geplant '**
  String get reportsPlannedLabel;

  /// No description provided for @reportsActualLabel.
  ///
  /// In de, this message translates to:
  /// **'Tatsächlich '**
  String get reportsActualLabel;

  /// No description provided for @reportsCountsUnavailable.
  ///
  /// In de, this message translates to:
  /// **'Szenenzahlen nicht verfügbar.'**
  String get reportsCountsUnavailable;

  /// No description provided for @reportsFinal.
  ///
  /// In de, this message translates to:
  /// **'Abschließend – dieser Tag ist abgeschlossen.'**
  String get reportsFinal;

  /// No description provided for @reportsNoScenes.
  ///
  /// In de, this message translates to:
  /// **'Keine Szenen in diesem Bericht.'**
  String get reportsNoScenes;

  /// No description provided for @reportsDayPrefix.
  ///
  /// In de, this message translates to:
  /// **'Tag {day}'**
  String reportsDayPrefix(Object day);

  /// No description provided for @reportsFlagMoved.
  ///
  /// In de, this message translates to:
  /// **'verschoben'**
  String get reportsFlagMoved;

  /// No description provided for @reportsFlagMissing.
  ///
  /// In de, this message translates to:
  /// **'fehlend'**
  String get reportsFlagMissing;

  /// No description provided for @reportsFlagSkipped.
  ///
  /// In de, this message translates to:
  /// **'übersprungen'**
  String get reportsFlagSkipped;

  /// No description provided for @reportsFlagReshot.
  ///
  /// In de, this message translates to:
  /// **'erneut gedreht'**
  String get reportsFlagReshot;

  /// No description provided for @reportsPdfDispo.
  ///
  /// In de, this message translates to:
  /// **'Dispo (geplant)'**
  String get reportsPdfDispo;

  /// No description provided for @reportsPdfShootDay.
  ///
  /// In de, this message translates to:
  /// **'Drehtag (Ausführung)'**
  String get reportsPdfShootDay;

  /// No description provided for @reportsPdfPlannedVsActual.
  ///
  /// In de, this message translates to:
  /// **'Geplant vs. tatsächlich (PDF)'**
  String get reportsPdfPlannedVsActual;

  /// No description provided for @reportsPdfSection.
  ///
  /// In de, this message translates to:
  /// **'PDF-Berichte'**
  String get reportsPdfSection;

  /// No description provided for @reportsFetch.
  ///
  /// In de, this message translates to:
  /// **'Abrufen'**
  String get reportsFetch;

  /// No description provided for @reportsPreview.
  ///
  /// In de, this message translates to:
  /// **'Vorschau'**
  String get reportsPreview;

  /// No description provided for @reportsShare.
  ///
  /// In de, this message translates to:
  /// **'Teilen'**
  String get reportsShare;

  /// No description provided for @reportErrorUnknownStatus.
  ///
  /// In de, this message translates to:
  /// **'Der Bericht hat ein nicht erkanntes Format – aktualisiere die App, um ihn anzuzeigen.'**
  String get reportErrorUnknownStatus;

  /// No description provided for @reportErrorUnknownShape.
  ///
  /// In de, this message translates to:
  /// **'Der Bericht konnte nicht gelesen werden ({code}). Versuch es erneut.'**
  String reportErrorUnknownShape(Object code);

  /// No description provided for @reportErrorPdfTooLarge.
  ///
  /// In de, this message translates to:
  /// **'Das PDF ist zu groß, um es auf diesem Gerät als Vorschau anzuzeigen.'**
  String get reportErrorPdfTooLarge;

  /// No description provided for @reportErrorForbidden.
  ///
  /// In de, this message translates to:
  /// **'Du hast keinen Zugriff auf diese Berichte.'**
  String get reportErrorForbidden;

  /// No description provided for @reportErrorMembershipPending.
  ///
  /// In de, this message translates to:
  /// **'Berichtszugriff wird geprüft …'**
  String get reportErrorMembershipPending;

  /// No description provided for @reportErrorMembershipUnavailable.
  ///
  /// In de, this message translates to:
  /// **'Zugriffsprüfung fehlgeschlagen – erneut versuchen, um die Berichte zu laden.'**
  String get reportErrorMembershipUnavailable;

  /// No description provided for @reportErrorShareFailed.
  ///
  /// In de, this message translates to:
  /// **'Teilen fehlgeschlagen – die Datei wurde verworfen. Versuch es erneut.'**
  String get reportErrorShareFailed;

  /// No description provided for @reportErrorNetwork.
  ///
  /// In de, this message translates to:
  /// **'Netzwerkproblem – der Bericht wurde nicht geladen. Versuch es erneut.'**
  String get reportErrorNetwork;

  /// No description provided for @reportErrorLoad.
  ///
  /// In de, this message translates to:
  /// **'Der Bericht konnte nicht geladen werden ({code}).'**
  String reportErrorLoad(Object code);

  /// No description provided for @aiConfigErrorAdmin.
  ///
  /// In de, this message translates to:
  /// **'Administrator-Rolle erforderlich – frag deine Produktionsadmins.'**
  String get aiConfigErrorAdmin;

  /// No description provided for @aiConfigErrorChanged.
  ///
  /// In de, this message translates to:
  /// **'Woanders geändert – aktualisiere und wende deine Änderung erneut an.'**
  String get aiConfigErrorChanged;

  /// No description provided for @aiConfigErrorOrphaned.
  ///
  /// In de, this message translates to:
  /// **'Der API-Schlüssel konnte nach dem fehlgeschlagenen Setup nicht aus dem Server-Vault entfernt werden. Wiederhole die Bereinigung im Konfigurationsbildschirm.'**
  String get aiConfigErrorOrphaned;

  /// No description provided for @aiConfigErrorProvider.
  ///
  /// In de, this message translates to:
  /// **'Dieser Anbieter ist gerade nicht verfügbar.'**
  String get aiConfigErrorProvider;

  /// No description provided for @aiConfigErrorDisabled.
  ///
  /// In de, this message translates to:
  /// **'KI-Import ist auf dieser Instanz nicht aktiviert. Das ist eine Server-Konfiguration – hier gibt es nichts zu wiederholen.'**
  String get aiConfigErrorDisabled;

  /// No description provided for @aiConfigErrorNetwork.
  ///
  /// In de, this message translates to:
  /// **'Netzwerkproblem – die Änderung wurde nicht angewendet. Versuch es erneut.'**
  String get aiConfigErrorNetwork;

  /// No description provided for @aiConfigErrorGeneric.
  ///
  /// In de, this message translates to:
  /// **'Die Konfigurationsänderung ist fehlgeschlagen ({code}).'**
  String aiConfigErrorGeneric(Object code);

  /// No description provided for @aiConfigProvidersUnavailable.
  ///
  /// In de, this message translates to:
  /// **'Anbieter konnten nicht geladen werden.'**
  String get aiConfigProvidersUnavailable;

  /// No description provided for @aiConfigTitle.
  ///
  /// In de, this message translates to:
  /// **'KI-Import-Konfiguration'**
  String get aiConfigTitle;

  /// No description provided for @aiConfigKeyMissing.
  ///
  /// In de, this message translates to:
  /// **'Gib zuerst den API-Schlüssel ein.'**
  String get aiConfigKeyMissing;

  /// No description provided for @aiConfigPrefillHint.
  ///
  /// In de, this message translates to:
  /// **'Die Prompt-Felder sind mit den Server-Standardwerten vorausgefüllt – du kannst sie bearbeiten.'**
  String get aiConfigPrefillHint;

  /// No description provided for @aiConfigNotConfigured.
  ///
  /// In de, this message translates to:
  /// **'Noch nicht konfiguriert'**
  String get aiConfigNotConfigured;

  /// No description provided for @aiConfigFirstRunBody.
  ///
  /// In de, this message translates to:
  /// **'Wähle einen Anbieter, wähle das Assistentenmodell und sende deinen API-Schlüssel. Der Schlüssel wird an den Server-Vault gesendet und nie auf diesem Gerät gespeichert.'**
  String get aiConfigFirstRunBody;

  /// No description provided for @aiConfigApiKeyLabel.
  ///
  /// In de, this message translates to:
  /// **'API-Schlüssel (wird an den Server-Vault gesendet)'**
  String get aiConfigApiKeyLabel;

  /// No description provided for @aiConfigSaveConfiguration.
  ///
  /// In de, this message translates to:
  /// **'Konfiguration speichern'**
  String get aiConfigSaveConfiguration;

  /// No description provided for @aiConfigNoProviders.
  ///
  /// In de, this message translates to:
  /// **'Auf diesem Backend werden keine KI-Anbieter angeboten.'**
  String get aiConfigNoProviders;

  /// No description provided for @aiConfigProviderLabel.
  ///
  /// In de, this message translates to:
  /// **'Anbieter'**
  String get aiConfigProviderLabel;

  /// No description provided for @aiConfigAssistantModelLabel.
  ///
  /// In de, this message translates to:
  /// **'Assistentenmodell'**
  String get aiConfigAssistantModelLabel;

  /// No description provided for @aiConfigImageModelLabel.
  ///
  /// In de, this message translates to:
  /// **'Bildmodell (optional)'**
  String get aiConfigImageModelLabel;

  /// No description provided for @aiConfigNoModel.
  ///
  /// In de, this message translates to:
  /// **'— keine —'**
  String get aiConfigNoModel;

  /// No description provided for @aiConfigProviderUnavailable.
  ///
  /// In de, this message translates to:
  /// **'Anbieter nicht verfügbar – der Modellkatalog kann nicht gelesen werden.'**
  String get aiConfigProviderUnavailable;

  /// No description provided for @aiConfigModelCatalogUnavailable.
  ///
  /// In de, this message translates to:
  /// **'Der Modellkatalog konnte nicht geladen werden.'**
  String get aiConfigModelCatalogUnavailable;

  /// No description provided for @aiConfigScriptPromptLabel.
  ///
  /// In de, this message translates to:
  /// **'Skript-Prompt'**
  String get aiConfigScriptPromptLabel;

  /// No description provided for @aiConfigSchedulePromptLabel.
  ///
  /// In de, this message translates to:
  /// **'Drehplan-Prompt'**
  String get aiConfigSchedulePromptLabel;

  /// No description provided for @aiConfigRevokeTitle.
  ///
  /// In de, this message translates to:
  /// **'Konfiguration widerrufen?'**
  String get aiConfigRevokeTitle;

  /// No description provided for @aiConfigRevokeBody.
  ///
  /// In de, this message translates to:
  /// **'Die KI-Import-Konfiguration wird widerrufen. Der vom Server gehaltene API-Schlüssel wird vernichtet. Bereits angewendete Importe bleiben erhalten.'**
  String get aiConfigRevokeBody;

  /// No description provided for @aiConfigActiveTitle.
  ///
  /// In de, this message translates to:
  /// **'Aktive Konfiguration'**
  String get aiConfigActiveTitle;

  /// No description provided for @aiConfigProviderPrefix.
  ///
  /// In de, this message translates to:
  /// **'Anbieter: {provider}'**
  String aiConfigProviderPrefix(Object provider);

  /// No description provided for @aiConfigImageSuffix.
  ///
  /// In de, this message translates to:
  /// **' · Bild: {image}'**
  String aiConfigImageSuffix(Object image);

  /// No description provided for @aiConfigSaveChanges.
  ///
  /// In de, this message translates to:
  /// **'Änderungen speichern'**
  String get aiConfigSaveChanges;

  /// No description provided for @aiConfigRevokeButton.
  ///
  /// In de, this message translates to:
  /// **'Konfiguration widerrufen'**
  String get aiConfigRevokeButton;

  /// No description provided for @aiConfigUnresolvedTitle.
  ///
  /// In de, this message translates to:
  /// **'Konfigurationsstatus unbekannt – prüfen'**
  String get aiConfigUnresolvedTitle;

  /// No description provided for @aiConfigUnresolvedBody.
  ///
  /// In de, this message translates to:
  /// **'Das Setup wurde möglicherweise oder möglicherweise nicht abgeschlossen. Es wurde nichts gelöscht – prüfe erneut oder bereinige den vom Server gehaltenen Schlüssel, wenn du sicher bist, dass das Setup fehlgeschlagen ist.'**
  String get aiConfigUnresolvedBody;

  /// No description provided for @aiConfigRecheck.
  ///
  /// In de, this message translates to:
  /// **'Erneut prüfen'**
  String get aiConfigRecheck;

  /// No description provided for @aiConfigCleanup.
  ///
  /// In de, this message translates to:
  /// **'Bereinigen'**
  String get aiConfigCleanup;

  /// No description provided for @aiConfigDiscoveryError.
  ///
  /// In de, this message translates to:
  /// **'Die Konfiguration konnte nicht geladen werden ({code}).'**
  String aiConfigDiscoveryError(Object code);

  /// No description provided for @aiUploadTooLarge.
  ///
  /// In de, this message translates to:
  /// **'Das Dokument ist für den KI-Import zu groß.'**
  String get aiUploadTooLarge;

  /// No description provided for @aiUploadUnsupported.
  ///
  /// In de, this message translates to:
  /// **'Dieser Dateityp wird für die gewählte Art nicht unterstützt.'**
  String get aiUploadUnsupported;

  /// No description provided for @aiUploadDisabled.
  ///
  /// In de, this message translates to:
  /// **'KI-Import ist auf diesem Backend nicht aktiviert.'**
  String get aiUploadDisabled;

  /// No description provided for @aiUploadScopeMissing.
  ///
  /// In de, this message translates to:
  /// **'Öffne zuerst einen Produktionsblock – der KI-Import ist blockbezogen.'**
  String get aiUploadScopeMissing;

  /// No description provided for @aiUploadPermissions.
  ///
  /// In de, this message translates to:
  /// **'Deine Berechtigungen werden noch geladen – versuch es gleich noch einmal.'**
  String get aiUploadPermissions;

  /// No description provided for @aiUploadNetwork.
  ///
  /// In de, this message translates to:
  /// **'Netzwerkproblem – das Dokument wurde nicht übermittelt. Versuch es erneut.'**
  String get aiUploadNetwork;

  /// No description provided for @aiUploadGeneric.
  ///
  /// In de, this message translates to:
  /// **'Das Dokument konnte nicht übermittelt werden ({code}).'**
  String aiUploadGeneric(Object code);

  /// No description provided for @jobStatusPending.
  ///
  /// In de, this message translates to:
  /// **'Wartet – das Backend hat es übernommen.'**
  String get jobStatusPending;

  /// No description provided for @jobStatusRunning.
  ///
  /// In de, this message translates to:
  /// **'Dein Dokument wird verarbeitet …'**
  String get jobStatusRunning;

  /// No description provided for @jobStatusSucceeded.
  ///
  /// In de, this message translates to:
  /// **'Import-Vorschau bereit.'**
  String get jobStatusSucceeded;

  /// No description provided for @jobStatusFailed.
  ///
  /// In de, this message translates to:
  /// **'Fehlgeschlagen – ein erneuter Versuch ist geplant.'**
  String get jobStatusFailed;

  /// No description provided for @jobStatusDeadLetter.
  ///
  /// In de, this message translates to:
  /// **'Die Verarbeitung hat nach wiederholten Fehlern aufgegeben.'**
  String get jobStatusDeadLetter;

  /// No description provided for @jobStatusPayloadUnavailable.
  ///
  /// In de, this message translates to:
  /// **'Die extrahierten Daten sind auf dem Server nicht mehr verfügbar.'**
  String get jobStatusPayloadUnavailable;

  /// No description provided for @jobStatusUnknown.
  ///
  /// In de, this message translates to:
  /// **'Status unbekannt ({name}).'**
  String jobStatusUnknown(Object name);

  /// No description provided for @jobWatchForbidden.
  ///
  /// In de, this message translates to:
  /// **'Du hast keinen Zugriff auf diesen KI-Import-Auftrag.'**
  String get jobWatchForbidden;

  /// No description provided for @jobWatchExhausted.
  ///
  /// In de, this message translates to:
  /// **'Immer noch kein Update vom Backend – der Auftrag wird weiter verarbeitet. Arm den Watch erneut oder komm später zurück.'**
  String get jobWatchExhausted;

  /// No description provided for @jobWatchNotFound.
  ///
  /// In de, this message translates to:
  /// **'Dieser Auftrag existiert nicht (oder gehört einem anderen Konto).'**
  String get jobWatchNotFound;

  /// No description provided for @jobWatchNetwork.
  ///
  /// In de, this message translates to:
  /// **'Netzwerkproblem – der Status konnte nicht aktualisiert werden.'**
  String get jobWatchNetwork;

  /// No description provided for @jobWatchGeneric.
  ///
  /// In de, this message translates to:
  /// **'Der Status konnte nicht aktualisiert werden ({code}).'**
  String jobWatchGeneric(Object code);

  /// No description provided for @aiJobTitle.
  ///
  /// In de, this message translates to:
  /// **'KI-Import-Auftrag'**
  String get aiJobTitle;

  /// No description provided for @aiJobDuplicate.
  ///
  /// In de, this message translates to:
  /// **'Bereits importiert (Duplikat) – der bestehende Auftrag wird angezeigt. Es wurde kein zweiter Import erstellt.'**
  String get aiJobDuplicate;

  /// No description provided for @aiJobRetryBudget.
  ///
  /// In de, this message translates to:
  /// **'Versuch {retries} von {maxRetries}'**
  String aiJobRetryBudget(Object maxRetries, Object retries);

  /// No description provided for @aiJobReviewPreview.
  ///
  /// In de, this message translates to:
  /// **'Vorschau prüfen'**
  String get aiJobReviewPreview;

  /// No description provided for @aiJobCheckAgain.
  ///
  /// In de, this message translates to:
  /// **'Erneut prüfen'**
  String get aiJobCheckAgain;

  /// No description provided for @aiPreviewTitle.
  ///
  /// In de, this message translates to:
  /// **'Import-Vorschau'**
  String get aiPreviewTitle;

  /// No description provided for @aiPreviewKindUnknown.
  ///
  /// In de, this message translates to:
  /// **'Nicht erkannte Vorschau-Daten – das Backend hat eine Struktur erzeugt, die diese App-Version nicht darstellen kann. Es werden keine Zeilen geraten; aktualisiere die App oder führe den Import erneut aus.'**
  String get aiPreviewKindUnknown;

  /// No description provided for @aiPreviewMissing.
  ///
  /// In de, this message translates to:
  /// **'Für diesen Auftrag ist noch keine Vorschau verfügbar.'**
  String get aiPreviewMissing;

  /// No description provided for @aiPreviewLoadError.
  ///
  /// In de, this message translates to:
  /// **'Die Vorschau konnte nicht geladen werden ({code}).'**
  String aiPreviewLoadError(Object code);

  /// No description provided for @aiPreviewScriptTitle.
  ///
  /// In de, this message translates to:
  /// **'Skript-Vorschau'**
  String get aiPreviewScriptTitle;

  /// No description provided for @aiPreviewScriptSubtitle.
  ///
  /// In de, this message translates to:
  /// **'{count} Skript-Szene(n)'**
  String aiPreviewScriptSubtitle(Object count);

  /// No description provided for @aiPreviewScheduleTitle.
  ///
  /// In de, this message translates to:
  /// **'Drehplan-Vorschau (vor dem Zusammenführen)'**
  String get aiPreviewScheduleTitle;

  /// No description provided for @aiPreviewScheduleSubtitle.
  ///
  /// In de, this message translates to:
  /// **'{count} Drehplan-Zeile(n)'**
  String aiPreviewScheduleSubtitle(Object count);

  /// No description provided for @aiPreviewMergedTitle.
  ///
  /// In de, this message translates to:
  /// **'Zusammengeführte Vorschau'**
  String get aiPreviewMergedTitle;

  /// No description provided for @aiPreviewMergedSubtitle.
  ///
  /// In de, this message translates to:
  /// **'{count} passende Szene(n)'**
  String aiPreviewMergedSubtitle(Object count);

  /// No description provided for @aiPreviewFallbackTitle.
  ///
  /// In de, this message translates to:
  /// **'Vorschau'**
  String get aiPreviewFallbackTitle;

  /// No description provided for @aiPreviewUncertainty.
  ///
  /// In de, this message translates to:
  /// **'Unsicherheit ({field}): {note}'**
  String aiPreviewUncertainty(Object field, Object note);

  /// No description provided for @aiPreviewRowRef.
  ///
  /// In de, this message translates to:
  /// **'Zeile {ref}: {detail}'**
  String aiPreviewRowRef(Object detail, Object ref);

  /// No description provided for @aiPreviewUnmatchedScheduleRow.
  ///
  /// In de, this message translates to:
  /// **'Nicht zugeordnete Drehplan-Zeile: {ref}'**
  String aiPreviewUnmatchedScheduleRow(Object ref);

  /// No description provided for @aiPreviewUnmatchedScriptScene.
  ///
  /// In de, this message translates to:
  /// **'Nicht zugeordnete Skript-Szene: {id}'**
  String aiPreviewUnmatchedScriptScene(Object id);

  /// No description provided for @aiPreviewUnrecognizedShape.
  ///
  /// In de, this message translates to:
  /// **'Nicht erkannte Vorschau-Struktur.'**
  String get aiPreviewUnrecognizedShape;

  /// No description provided for @aiPreviewCreate.
  ///
  /// In de, this message translates to:
  /// **'Erstellen'**
  String get aiPreviewCreate;

  /// No description provided for @aiPreviewUpdate.
  ///
  /// In de, this message translates to:
  /// **'Aktualisieren'**
  String get aiPreviewUpdate;

  /// No description provided for @aiPreviewSkip.
  ///
  /// In de, this message translates to:
  /// **'Überspringen'**
  String get aiPreviewSkip;

  /// No description provided for @aiPreviewUpdatesScene.
  ///
  /// In de, this message translates to:
  /// **'Aktualisiert Szene {id} (v{version})'**
  String aiPreviewUpdatesScene(Object id, Object version);

  /// No description provided for @aiPreviewUnscheduled.
  ///
  /// In de, this message translates to:
  /// **'nicht eingeplant'**
  String get aiPreviewUnscheduled;

  /// No description provided for @aiPreviewScheduledRowCount.
  ///
  /// In de, this message translates to:
  /// **' · {count} Drehplan-Zeile(n)'**
  String aiPreviewScheduledRowCount(Object count);

  /// No description provided for @aiPreviewSceneWithSummary.
  ///
  /// In de, this message translates to:
  /// **'Szene {id}{summary}'**
  String aiPreviewSceneWithSummary(Object id, Object summary);

  /// No description provided for @aiApplyErrorNotSucceeded.
  ///
  /// In de, this message translates to:
  /// **'Die Vorschau kann nicht mehr angewendet werden – prüfe den Auftragsstatus.'**
  String get aiApplyErrorNotSucceeded;

  /// No description provided for @aiApplyErrorUnresolved.
  ///
  /// In de, this message translates to:
  /// **'Das Anwenden-Ergebnis ist unbekannt – der Server hat es möglicherweise trotzdem angewendet. Prüfe zuerst die betroffene Episode, bevor du es erneut versuchst.'**
  String get aiApplyErrorUnresolved;

  /// No description provided for @aiApplyErrorContextMissing.
  ///
  /// In de, this message translates to:
  /// **'Wähle zuerst die Zielepisode aus.'**
  String get aiApplyErrorContextMissing;

  /// No description provided for @aiApplyErrorNetwork.
  ///
  /// In de, this message translates to:
  /// **'Netzwerkproblem – das Anwenden wurde möglicherweise nicht abgeschlossen. Prüfe zuerst die betroffene Episode, bevor du es erneut versuchst.'**
  String get aiApplyErrorNetwork;

  /// No description provided for @aiApplyErrorGeneric.
  ///
  /// In de, this message translates to:
  /// **'Das Anwenden ist fehlgeschlagen ({code}).'**
  String aiApplyErrorGeneric(Object code);

  /// No description provided for @aiApplyTitle.
  ///
  /// In de, this message translates to:
  /// **'Auf Episode anwenden'**
  String get aiApplyTitle;

  /// No description provided for @aiApplyContextEpisode.
  ///
  /// In de, this message translates to:
  /// **'Episode {id}'**
  String aiApplyContextEpisode(Object id);

  /// No description provided for @aiApplyContextRemembered.
  ///
  /// In de, this message translates to:
  /// **'Mit diesem Auftrag gemerkt – unten bei Bedarf ändern.'**
  String get aiApplyContextRemembered;

  /// No description provided for @aiApplyNoContextTitle.
  ///
  /// In de, this message translates to:
  /// **'Für diesen Auftrag ist keine Zielepisode gemerkt.'**
  String get aiApplyNoContextTitle;

  /// No description provided for @aiApplyNoContextSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Wähle unten eine Episode, um das Anwenden zu aktivieren.'**
  String get aiApplyNoContextSubtitle;

  /// No description provided for @aiApplyAcceptAsIs.
  ///
  /// In de, this message translates to:
  /// **'Alle Entwürfe unverändert erstellen (ohne Bearbeitung).'**
  String get aiApplyAcceptAsIs;

  /// No description provided for @aiApplySelectionSummary.
  ///
  /// In de, this message translates to:
  /// **'{updates} Aktualisierung(en), {skips} Überspringen – Bearbeitungsabstand {distance}.'**
  String aiApplySelectionSummary(Object distance, Object skips, Object updates);

  /// No description provided for @aiApplySubmit.
  ///
  /// In de, this message translates to:
  /// **'Import anwenden'**
  String get aiApplySubmit;

  /// No description provided for @aiApplyPickEpisode.
  ///
  /// In de, this message translates to:
  /// **'Episode wählen…'**
  String get aiApplyPickEpisode;

  /// No description provided for @aiApplyOutcome.
  ///
  /// In de, this message translates to:
  /// **'Angewendet: {applied} Entwurf(e): {days} Drehtag(e) erstellt, {shoots} Szenen-Dreh(e) geplant.'**
  String aiApplyOutcome(Object applied, Object days, Object shoots);

  /// No description provided for @aiApplyBackToStart.
  ///
  /// In de, this message translates to:
  /// **'Zurück zum Start'**
  String get aiApplyBackToStart;

  /// No description provided for @aiScenePickerError.
  ///
  /// In de, this message translates to:
  /// **'Szenen konnten nicht geladen werden ({code}).'**
  String aiScenePickerError(Object code);

  /// No description provided for @aiScenePickerEmpty.
  ///
  /// In de, this message translates to:
  /// **'In dieser Episode gibt es noch keine Szenen.'**
  String get aiScenePickerEmpty;

  /// No description provided for @aiEpisodePickerTitle.
  ///
  /// In de, this message translates to:
  /// **'Zielepisode wählen'**
  String get aiEpisodePickerTitle;

  /// No description provided for @aiEpisodePickerError.
  ///
  /// In de, this message translates to:
  /// **'Zwischengespeicherte Episoden konnten nicht gelesen werden ({error}).'**
  String aiEpisodePickerError(Object error);

  /// No description provided for @aiEpisodePickerEmpty.
  ///
  /// In de, this message translates to:
  /// **'Keine zwischengespeicherten Episoden – öffne zuerst einen Produktionsblock und wähle dann.'**
  String get aiEpisodePickerEmpty;

  /// No description provided for @aiImportTitle.
  ///
  /// In de, this message translates to:
  /// **'KI-Import'**
  String get aiImportTitle;

  /// No description provided for @aiImportConfigure.
  ///
  /// In de, this message translates to:
  /// **'KI-Import konfigurieren'**
  String get aiImportConfigure;

  /// No description provided for @aiImportSchedule.
  ///
  /// In de, this message translates to:
  /// **'Drehplan'**
  String get aiImportSchedule;

  /// No description provided for @aiImportScript.
  ///
  /// In de, this message translates to:
  /// **'Skript'**
  String get aiImportScript;

  /// No description provided for @aiImportScheduleHint.
  ///
  /// In de, this message translates to:
  /// **'Drehpläne: Füge den CSV-/Board-Text ein oder wähle eine CSV- oder PDF-Datei.'**
  String get aiImportScheduleHint;

  /// No description provided for @aiImportScriptHint.
  ///
  /// In de, this message translates to:
  /// **'Skripte: Wähle eine PDF-Datei.'**
  String get aiImportScriptHint;

  /// No description provided for @aiImportOrPickFile.
  ///
  /// In de, this message translates to:
  /// **'— oder eine Datei wählen —'**
  String get aiImportOrPickFile;

  /// No description provided for @aiImportPasteLabel.
  ///
  /// In de, this message translates to:
  /// **'Drehplan einfügen (CSV oder Klartext)'**
  String get aiImportPasteLabel;

  /// No description provided for @aiImportPickCsvPdf.
  ///
  /// In de, this message translates to:
  /// **'CSV- oder PDF-Datei wählen'**
  String get aiImportPickCsvPdf;

  /// No description provided for @aiImportPickPdf.
  ///
  /// In de, this message translates to:
  /// **'PDF-Datei wählen'**
  String get aiImportPickPdf;

  /// No description provided for @aiImportNoFile.
  ///
  /// In de, this message translates to:
  /// **'Keine Datei gewählt'**
  String get aiImportNoFile;

  /// No description provided for @aiImportDocMissing.
  ///
  /// In de, this message translates to:
  /// **'Füge zuerst den Drehplan ein oder wähle eine Datei.'**
  String get aiImportDocMissing;

  /// No description provided for @aiImportStampWarning.
  ///
  /// In de, this message translates to:
  /// **'Import gestartet – der Episodenkontext konnte nicht gespeichert werden ({code}); wähle die Episode beim Anwenden.'**
  String aiImportStampWarning(Object code);

  /// No description provided for @aiImportSubmit.
  ///
  /// In de, this message translates to:
  /// **'Zum Import senden'**
  String get aiImportSubmit;

  /// No description provided for @commonAdd.
  ///
  /// In de, this message translates to:
  /// **'Hinzufügen'**
  String get commonAdd;

  /// No description provided for @captureDeniedCamera.
  ///
  /// In de, this message translates to:
  /// **'Kamera-Zugriff ist deaktiviert. Aktiviere den Kamera-Zugriff in den Einstellungen, um Kostüme zu dokumentieren.'**
  String get captureDeniedCamera;

  /// No description provided for @captureDeniedGallery.
  ///
  /// In de, this message translates to:
  /// **'Der Fotogalerie-Zugriff ist deaktiviert. Aktiviere den Foto-Zugriff in den Einstellungen, um Kostüme zu dokumentieren.'**
  String get captureDeniedGallery;

  /// No description provided for @captureUnavailable.
  ///
  /// In de, this message translates to:
  /// **'Die Kamera ist derzeit nicht verfügbar. Prüfe die Einstellungen und versuch es erneut.'**
  String get captureUnavailable;

  /// No description provided for @captureDeniedTitleCamera.
  ///
  /// In de, this message translates to:
  /// **'Kamera-Zugriff deaktiviert'**
  String get captureDeniedTitleCamera;

  /// No description provided for @captureDeniedTitleGallery.
  ///
  /// In de, this message translates to:
  /// **'Fotogalerie-Zugriff deaktiviert'**
  String get captureDeniedTitleGallery;

  /// No description provided for @costumeDetailTitle.
  ///
  /// In de, this message translates to:
  /// **'Kostüm'**
  String get costumeDetailTitle;

  /// No description provided for @costumeDetailCharacter.
  ///
  /// In de, this message translates to:
  /// **'Figur'**
  String get costumeDetailCharacter;

  /// No description provided for @costumeDetailAssignGate.
  ///
  /// In de, this message translates to:
  /// **'Du benötigst eine aktive Kostüm-Rolle in dieser Staffel, um Figuren zuzuweisen.'**
  String get costumeDetailAssignGate;

  /// No description provided for @costumeDetailAssign.
  ///
  /// In de, this message translates to:
  /// **'Zuweisen'**
  String get costumeDetailAssign;

  /// No description provided for @costumeDetailReassign.
  ///
  /// In de, this message translates to:
  /// **'Neu zuweisen'**
  String get costumeDetailReassign;

  /// No description provided for @costumeDetailTextRequired.
  ///
  /// In de, this message translates to:
  /// **'Text ist erforderlich'**
  String get costumeDetailTextRequired;

  /// No description provided for @costumeDetailUnassigned.
  ///
  /// In de, this message translates to:
  /// **'Nicht zugeordnet'**
  String get costumeDetailUnassigned;

  /// No description provided for @costumeDetailUnassignTooltip.
  ///
  /// In de, this message translates to:
  /// **'Zuordnung entfernen'**
  String get costumeDetailUnassignTooltip;

  /// No description provided for @costumeDetailUnassignTitle.
  ///
  /// In de, this message translates to:
  /// **'Figur-Zuordnung entfernen?'**
  String get costumeDetailUnassignTitle;

  /// No description provided for @costumeDetailUnassignMessage.
  ///
  /// In de, this message translates to:
  /// **'Das Kostüm behält seine Details und Notizen; nur die Figurenbindung wird entfernt.'**
  String get costumeDetailUnassignMessage;

  /// No description provided for @costumeDetailNotes.
  ///
  /// In de, this message translates to:
  /// **'Notizen'**
  String get costumeDetailNotes;

  /// No description provided for @costumeDetailNotesHint.
  ///
  /// In de, this message translates to:
  /// **'Anpassungsnotizen …'**
  String get costumeDetailNotesHint;

  /// No description provided for @costumeDetailSaveNotes.
  ///
  /// In de, this message translates to:
  /// **'Notizen speichern'**
  String get costumeDetailSaveNotes;

  /// No description provided for @costumeDetailDetails.
  ///
  /// In de, this message translates to:
  /// **'Details'**
  String get costumeDetailDetails;

  /// No description provided for @costumeDetailNoDetails.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Details – füge unten das erste hinzu.'**
  String get costumeDetailNoDetails;

  /// No description provided for @costumeDetailAddDetail.
  ///
  /// In de, this message translates to:
  /// **'Detail hinzufügen'**
  String get costumeDetailAddDetail;

  /// No description provided for @costumeDetailSubject.
  ///
  /// In de, this message translates to:
  /// **'Betreff'**
  String get costumeDetailSubject;

  /// No description provided for @costumeDetailText.
  ///
  /// In de, this message translates to:
  /// **'Text'**
  String get costumeDetailText;

  /// No description provided for @costumeDetailCategory.
  ///
  /// In de, this message translates to:
  /// **'Kategorie'**
  String get costumeDetailCategory;

  /// No description provided for @costumeDetailPhotos.
  ///
  /// In de, this message translates to:
  /// **'Fotos'**
  String get costumeDetailPhotos;

  /// No description provided for @costumeDetailCamera.
  ///
  /// In de, this message translates to:
  /// **'Kamera'**
  String get costumeDetailCamera;

  /// No description provided for @costumeDetailGallery.
  ///
  /// In de, this message translates to:
  /// **'Galerie'**
  String get costumeDetailGallery;

  /// No description provided for @costumeDetailPromptTitle.
  ///
  /// In de, this message translates to:
  /// **'Kostüme mit Fotos dokumentieren?'**
  String get costumeDetailPromptTitle;

  /// No description provided for @costumeDetailPromptBody.
  ///
  /// In de, this message translates to:
  /// **'Fotos helfen dem Garderobenteam, Kostüme zu dokumentieren und Kontinuität zu verfolgen. Als Nächstes fragt das System nach dem Kamera-Zugriff.'**
  String get costumeDetailPromptBody;

  /// No description provided for @costumeDetailNotNow.
  ///
  /// In de, this message translates to:
  /// **'Später'**
  String get costumeDetailNotNow;

  /// No description provided for @costumeDetailContinue.
  ///
  /// In de, this message translates to:
  /// **'Weiter'**
  String get costumeDetailContinue;

  /// No description provided for @costumeDetailOpenSettings.
  ///
  /// In de, this message translates to:
  /// **'Einstellungen öffnen'**
  String get costumeDetailOpenSettings;

  /// No description provided for @costumeDetailDeletePhotoMessage.
  ///
  /// In de, this message translates to:
  /// **'Das Foto und seine Varianten werden entfernt. Das kann nicht rückgängig gemacht werden.'**
  String get costumeDetailDeletePhotoMessage;

  /// No description provided for @wizardErrorSeasonExists.
  ///
  /// In de, this message translates to:
  /// **'Eine Season mit dieser Nummer existiert bereits.'**
  String get wizardErrorSeasonExists;

  /// No description provided for @wizardErrorBlockExistsSeries.
  ///
  /// In de, this message translates to:
  /// **'Ein Block mit dieser Nummer existiert bereits in der Serie.'**
  String get wizardErrorBlockExistsSeries;

  /// No description provided for @wizardErrorEpisodeExistsSeries.
  ///
  /// In de, this message translates to:
  /// **'Eine Episode mit dieser Nummer existiert bereits in der Serie.'**
  String get wizardErrorEpisodeExistsSeries;

  /// No description provided for @wizardErrorSeriesIdMissing.
  ///
  /// In de, this message translates to:
  /// **'Diese App wurde ohne DEFAULT_SERIES_ID gebaut: Die neue Season kann keiner Serie zugeordnet werden. Baue die App mit --dart-define=DEFAULT_SERIES_ID=<ID der Standardserie> neu.'**
  String get wizardErrorSeriesIdMissing;

  /// No description provided for @wizardErrorNetwork.
  ///
  /// In de, this message translates to:
  /// **'Netzwerkproblem – das Erstellen wurde abgebrochen. Versuche es erneut.'**
  String get wizardErrorNetwork;

  /// No description provided for @wizardErrorGeneric.
  ///
  /// In de, this message translates to:
  /// **'Das Erstellen ist fehlgeschlagen ({code}).'**
  String wizardErrorGeneric(Object code);

  /// No description provided for @wizardFieldPositive.
  ///
  /// In de, this message translates to:
  /// **'Eine ganze Zahl größer als 0 ist nötig.'**
  String get wizardFieldPositive;

  /// No description provided for @wizardFieldBlocks.
  ///
  /// In de, this message translates to:
  /// **'Mindestens ein Block ist nötig.'**
  String get wizardFieldBlocks;

  /// No description provided for @navBlocks.
  ///
  /// In de, this message translates to:
  /// **'Blöcke'**
  String get navBlocks;

  /// No description provided for @wizardTemplates.
  ///
  /// In de, this message translates to:
  /// **'Vorlagen'**
  String get wizardTemplates;

  /// No description provided for @wizardTitle.
  ///
  /// In de, this message translates to:
  /// **'Season-Setup'**
  String get wizardTitle;

  /// No description provided for @wizardCancelTitle.
  ///
  /// In de, this message translates to:
  /// **'Setup abbrechen?'**
  String get wizardCancelTitle;

  /// No description provided for @wizardCancelBody.
  ///
  /// In de, this message translates to:
  /// **'Deine Eingaben werden verworfen. Es wurde noch nichts gespeichert.'**
  String get wizardCancelBody;

  /// No description provided for @wizardKeepEditing.
  ///
  /// In de, this message translates to:
  /// **'Weiter bearbeiten'**
  String get wizardKeepEditing;

  /// No description provided for @wizardDiscard.
  ///
  /// In de, this message translates to:
  /// **'Verwerfen'**
  String get wizardDiscard;

  /// No description provided for @wizardStepOf.
  ///
  /// In de, this message translates to:
  /// **'Schritt {position} von {total}'**
  String wizardStepOf(Object position, Object total);

  /// No description provided for @wizardNext.
  ///
  /// In de, this message translates to:
  /// **'Weiter'**
  String get wizardNext;

  /// No description provided for @wizardRemoveBlock.
  ///
  /// In de, this message translates to:
  /// **'Block entfernen'**
  String get wizardRemoveBlock;

  /// No description provided for @wizardEpisodeTitlePlaceholder.
  ///
  /// In de, this message translates to:
  /// **'Titel (optional)'**
  String get wizardEpisodeTitlePlaceholder;

  /// No description provided for @wizardCompletionMissingConfig.
  ///
  /// In de, this message translates to:
  /// **'Build-Konfiguration fehlt'**
  String get wizardCompletionMissingConfig;

  /// No description provided for @wizardCompletionPartial.
  ///
  /// In de, this message translates to:
  /// **'Teilweise erstellt'**
  String get wizardCompletionPartial;

  /// No description provided for @wizardCompletionCreated.
  ///
  /// In de, this message translates to:
  /// **'Season angelegt'**
  String get wizardCompletionCreated;

  /// No description provided for @wizardCompletionSeasonCreated.
  ///
  /// In de, this message translates to:
  /// **'Season {number} angelegt'**
  String wizardCompletionSeasonCreated(Object number);

  /// No description provided for @wizardCompletionSummary.
  ///
  /// In de, this message translates to:
  /// **'{blocks} Blöcke · {episodes} Episoden'**
  String wizardCompletionSummary(Object blocks, Object episodes);

  /// No description provided for @wizardResume.
  ///
  /// In de, this message translates to:
  /// **'Fortsetzen'**
  String get wizardResume;

  /// No description provided for @wizardDone.
  ///
  /// In de, this message translates to:
  /// **'Fertig'**
  String get wizardDone;

  /// No description provided for @wizardAiImportCta.
  ///
  /// In de, this message translates to:
  /// **'KI-Import starten'**
  String get wizardAiImportCta;

  /// No description provided for @wizardAiImportNeedsConfig.
  ///
  /// In de, this message translates to:
  /// **'Für den KI-Import ist eine KI-Konfiguration nötig.'**
  String get wizardAiImportNeedsConfig;

  /// No description provided for @wizardOpenAiConfig.
  ///
  /// In de, this message translates to:
  /// **'KI-Konfiguration öffnen'**
  String get wizardOpenAiConfig;

  /// No description provided for @wizardDispatchProgress.
  ///
  /// In de, this message translates to:
  /// **'Season wird erstellt…'**
  String get wizardDispatchProgress;

  /// No description provided for @wizardDispatchSemantics.
  ///
  /// In de, this message translates to:
  /// **'{done} von {total} Befehlen bestätigt'**
  String wizardDispatchSemantics(Object done, Object total);

  /// No description provided for @wizardReviewSubmit.
  ///
  /// In de, this message translates to:
  /// **'Prüfen & erstellen'**
  String get wizardReviewSubmit;

  /// No description provided for @wizardReviewNumbersPending.
  ///
  /// In de, this message translates to:
  /// **'Nummern werden ermittelt …'**
  String get wizardReviewNumbersPending;

  /// No description provided for @wizardReviewCreateSeason.
  ///
  /// In de, this message translates to:
  /// **'Season erstellen'**
  String get wizardReviewCreateSeason;

  /// No description provided for @wizardReviewSeason.
  ///
  /// In de, this message translates to:
  /// **'Season {number}'**
  String wizardReviewSeason(Object number);

  /// No description provided for @wizardReviewSeasonNamed.
  ///
  /// In de, this message translates to:
  /// **'Season {number} · {name}'**
  String wizardReviewSeasonNamed(Object name, Object number);

  /// No description provided for @wizardReviewEpisodesInBlocks.
  ///
  /// In de, this message translates to:
  /// **'{episodes} Episoden in {blocks} Blöcke'**
  String wizardReviewEpisodesInBlocks(Object blocks, Object episodes);

  /// No description provided for @wizardReviewEpisodeCount.
  ///
  /// In de, this message translates to:
  /// **'{count} Episoden'**
  String wizardReviewEpisodeCount(Object count);

  /// No description provided for @continuityTitle.
  ///
  /// In de, this message translates to:
  /// **'Kontinuität ({count})'**
  String continuityTitle(Object count);

  /// No description provided for @continuityRoleGate.
  ///
  /// In de, this message translates to:
  /// **'Du benötigst eine aktive Kostüm-Rolle in dieser Staffel, um Kontinuitätsfotos zu verwalten.'**
  String get continuityRoleGate;

  /// No description provided for @continuityEmpty.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Kontinuitätsfotos verknüpft.'**
  String get continuityEmpty;

  /// No description provided for @continuityPhotoLabel.
  ///
  /// In de, this message translates to:
  /// **'Foto {id}'**
  String continuityPhotoLabel(Object id);

  /// No description provided for @continuityStoreOn.
  ///
  /// In de, this message translates to:
  /// **'Foto speichern unter …'**
  String get continuityStoreOn;

  /// No description provided for @continuityCostumeHint.
  ///
  /// In de, this message translates to:
  /// **'Wähle das Kostüm, zu dem das Foto gehört – es wird am Kostüm gespeichert und mit diesem Shot verknüpft.'**
  String get continuityCostumeHint;

  /// No description provided for @continuityRationaleTitle.
  ///
  /// In de, this message translates to:
  /// **'Kontinuität mit Fotos dokumentieren?'**
  String get continuityRationaleTitle;

  /// No description provided for @continuityRationaleBody.
  ///
  /// In de, this message translates to:
  /// **'Kontinuitätsfotos halten den Zustand am Set (Anschluss) an diesem Scene-Shoot fest. Als Nächstes fragt das System nach dem Kamera-Zugriff.'**
  String get continuityRationaleBody;

  /// No description provided for @continuityUnlinkTitle.
  ///
  /// In de, this message translates to:
  /// **'Kontinuitätsfoto-Verknüpfung entfernen?'**
  String get continuityUnlinkTitle;

  /// No description provided for @continuityUnlinkButton.
  ///
  /// In de, this message translates to:
  /// **'Verknüpfung entfernen'**
  String get continuityUnlinkButton;

  /// No description provided for @costumingTabNoSeason.
  ///
  /// In de, this message translates to:
  /// **'Wähle im Planen-Tab eine Season, um Kostüme und Figuren zu sehen.'**
  String get costumingTabNoSeason;

  /// No description provided for @costumingTabPickSeason.
  ///
  /// In de, this message translates to:
  /// **'Season im Planen-Tab wählen'**
  String get costumingTabPickSeason;

  /// No description provided for @photoGalleryAddPhoto.
  ///
  /// In de, this message translates to:
  /// **'Foto hinzufügen'**
  String get photoGalleryAddPhoto;

  /// No description provided for @photoGalleryProcessingFailed.
  ///
  /// In de, this message translates to:
  /// **'Verarbeitung fehlgeschlagen'**
  String get photoGalleryProcessingFailed;

  /// No description provided for @photoGalleryCaptureAgain.
  ///
  /// In de, this message translates to:
  /// **'Erneut aufnehmen'**
  String get photoGalleryCaptureAgain;

  /// No description provided for @photoGalleryDeleteTooltip.
  ///
  /// In de, this message translates to:
  /// **'Foto löschen'**
  String get photoGalleryDeleteTooltip;

  /// No description provided for @photoTileSemantics.
  ///
  /// In de, this message translates to:
  /// **'Foto von Kostüm {costumeId}'**
  String photoTileSemantics(Object costumeId);

  /// No description provided for @photoGalleryEmpty.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Fotos'**
  String get photoGalleryEmpty;

  /// No description provided for @seasonsOnlineRequired.
  ///
  /// In de, this message translates to:
  /// **'Online-Verbindung erforderlich'**
  String get seasonsOnlineRequired;

  /// No description provided for @seasonsStaleBanner.
  ///
  /// In de, this message translates to:
  /// **'Zwischengespeicherte Daten sind möglicherweise veraltet.'**
  String get seasonsStaleBanner;

  /// No description provided for @seasonsErrorBanner.
  ///
  /// In de, this message translates to:
  /// **'Aktualisierung fehlgeschlagen – zwischengespeicherte Daten werden angezeigt.'**
  String get seasonsErrorBanner;

  /// No description provided for @seasonsAddTooltip.
  ///
  /// In de, this message translates to:
  /// **'Season hinzufügen'**
  String get seasonsAddTooltip;

  /// No description provided for @seasonsEmpty.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Seasons'**
  String get seasonsEmpty;

  /// No description provided for @continuityUnlinkBody.
  ///
  /// In de, this message translates to:
  /// **'Das Foto bleibt am Kostüm – nur die Verknüpfung zu diesem Shoot wird entfernt.'**
  String get continuityUnlinkBody;

  /// No description provided for @sceneShootDayFallback.
  ///
  /// In de, this message translates to:
  /// **'Drehtag'**
  String get sceneShootDayFallback;

  /// No description provided for @sceneShootsReportsTooltip.
  ///
  /// In de, this message translates to:
  /// **'Berichte'**
  String get sceneShootsReportsTooltip;

  /// No description provided for @sceneShootWrapButton.
  ///
  /// In de, this message translates to:
  /// **'Drehtag abschließen'**
  String get sceneShootWrapButton;

  /// No description provided for @sceneShootWrapTitle.
  ///
  /// In de, this message translates to:
  /// **'Diesen Drehtag abschließen?'**
  String get sceneShootWrapTitle;

  /// No description provided for @sceneShootWrapMessage.
  ///
  /// In de, this message translates to:
  /// **'Beim Abschließen wird der Tag als endgültig markiert: Gestartet-, Fertig- und Übersprungen-Status können danach nicht mehr geändert werden. Das kann nicht rückgängig gemacht werden – ein Entfernen der Abschließung ist im Vertrag nicht vorgesehen.'**
  String get sceneShootWrapMessage;

  /// No description provided for @sceneShootWrapConfirm.
  ///
  /// In de, this message translates to:
  /// **'Drehtag abschließen'**
  String get sceneShootWrapConfirm;

  /// No description provided for @sceneShootActualOrder.
  ///
  /// In de, this message translates to:
  /// **'Tatsächlich {actual} (geplant {planned})'**
  String sceneShootActualOrder(Object actual, Object planned);

  /// No description provided for @sceneShootPlannedOrder.
  ///
  /// In de, this message translates to:
  /// **'Geplant {planned}'**
  String sceneShootPlannedOrder(Object planned);

  /// No description provided for @sceneShootCounts.
  ///
  /// In de, this message translates to:
  /// **'{notes} Notizen · {photos} Kontinuitätsfotos'**
  String sceneShootCounts(Object notes, Object photos);

  /// No description provided for @sceneShootStart.
  ///
  /// In de, this message translates to:
  /// **'Start'**
  String get sceneShootStart;

  /// No description provided for @sceneShootFinish.
  ///
  /// In de, this message translates to:
  /// **'Abschließen'**
  String get sceneShootFinish;

  /// No description provided for @sceneShootSkip.
  ///
  /// In de, this message translates to:
  /// **'Überspringen'**
  String get sceneShootSkip;

  /// No description provided for @sceneShootOrderTooltip.
  ///
  /// In de, this message translates to:
  /// **'Reihenfolge'**
  String get sceneShootOrderTooltip;

  /// No description provided for @sceneShootSetActualOrder.
  ///
  /// In de, this message translates to:
  /// **'Tatsächliche Reihenfolge festlegen…'**
  String get sceneShootSetActualOrder;

  /// No description provided for @sceneShootChangePlanned.
  ///
  /// In de, this message translates to:
  /// **'Geplante Position ändern…'**
  String get sceneShootChangePlanned;

  /// No description provided for @sceneShootSetActualTitle.
  ///
  /// In de, this message translates to:
  /// **'Tatsächliche Reihenfolge festlegen'**
  String get sceneShootSetActualTitle;

  /// No description provided for @sceneShootSetActualExplanation.
  ///
  /// In de, this message translates to:
  /// **'Der Ist-Ausführungsschlüssel – sortiert diesen Shoot in die tatsächliche Reihenfolge.'**
  String get sceneShootSetActualExplanation;

  /// No description provided for @sceneShootChangePlannedTitle.
  ///
  /// In de, this message translates to:
  /// **'Geplante Position ändern'**
  String get sceneShootChangePlannedTitle;

  /// No description provided for @sceneShootChangePlannedExplanation.
  ///
  /// In de, this message translates to:
  /// **'Der Soll-Positionsschlüssel für diesen Shoot.'**
  String get sceneShootChangePlannedExplanation;

  /// No description provided for @sceneShootOrderKeyHint.
  ///
  /// In de, this message translates to:
  /// **'Ordnungsschlüssel (druckbare ASCII-Zeichen)'**
  String get sceneShootOrderKeyHint;

  /// No description provided for @sceneShootNotesTitle.
  ///
  /// In de, this message translates to:
  /// **'Notizen ({count})'**
  String sceneShootNotesTitle(Object count);

  /// No description provided for @sceneShootEditNoteTooltip.
  ///
  /// In de, this message translates to:
  /// **'Notiz bearbeiten'**
  String get sceneShootEditNoteTooltip;

  /// No description provided for @sceneShootDeleteNoteTooltip.
  ///
  /// In de, this message translates to:
  /// **'Notiz löschen'**
  String get sceneShootDeleteNoteTooltip;

  /// No description provided for @sceneShootAddNote.
  ///
  /// In de, this message translates to:
  /// **'Notiz hinzufügen'**
  String get sceneShootAddNote;

  /// No description provided for @sceneShootDeleteNoteTitle.
  ///
  /// In de, this message translates to:
  /// **'Diese Notiz löschen?'**
  String get sceneShootDeleteNoteTitle;

  /// No description provided for @sceneShootDeleteNoteMessage.
  ///
  /// In de, this message translates to:
  /// **'„{body}“ wird aus dem Shoot entfernt.'**
  String sceneShootDeleteNoteMessage(Object body);

  /// No description provided for @sceneShootAddNoteTitle.
  ///
  /// In de, this message translates to:
  /// **'Notiz hinzufügen'**
  String get sceneShootAddNoteTitle;

  /// No description provided for @sceneShootEditNoteTitle.
  ///
  /// In de, this message translates to:
  /// **'Notiz bearbeiten'**
  String get sceneShootEditNoteTitle;

  /// No description provided for @sceneShootNoteHint.
  ///
  /// In de, this message translates to:
  /// **'Notiztext'**
  String get sceneShootNoteHint;

  /// No description provided for @sceneShootStatusInProgress.
  ///
  /// In de, this message translates to:
  /// **'In Arbeit'**
  String get sceneShootStatusInProgress;

  /// No description provided for @sceneShootStatusShot.
  ///
  /// In de, this message translates to:
  /// **'Abgedreht'**
  String get sceneShootStatusShot;

  /// No description provided for @sceneShootStatusSkipped.
  ///
  /// In de, this message translates to:
  /// **'Übersprungen'**
  String get sceneShootStatusSkipped;

  /// No description provided for @sceneShootStatusPlanned.
  ///
  /// In de, this message translates to:
  /// **'Geplant'**
  String get sceneShootStatusPlanned;

  /// No description provided for @sceneShootsEmpty.
  ///
  /// In de, this message translates to:
  /// **'Für diesen Tag sind noch keine Szenen-Drehs geplant.'**
  String get sceneShootsEmpty;

  /// No description provided for @sceneShootsPlanFirst.
  ///
  /// In de, this message translates to:
  /// **'Ersten Dreh planen'**
  String get sceneShootsPlanFirst;

  /// No description provided for @sceneShootsFetchError.
  ///
  /// In de, this message translates to:
  /// **'Das Day-Board konnte nicht geladen werden ({code}).'**
  String sceneShootsFetchError(Object code);

  /// No description provided for @sceneShootsNotFound.
  ///
  /// In de, this message translates to:
  /// **'Nicht mehr verfügbar ({code}).'**
  String sceneShootsNotFound(Object code);

  /// No description provided for @sceneShootsStaleBanner.
  ///
  /// In de, this message translates to:
  /// **'Zwischengespeicherte Daten sind möglicherweise veraltet.'**
  String get sceneShootsStaleBanner;

  /// No description provided for @sceneShootsWrappedBanner.
  ///
  /// In de, this message translates to:
  /// **'Dieser Tag ist abgeschlossen – die Ausführung ist endgültig und schreibgeschützt.'**
  String get sceneShootsWrappedBanner;

  /// No description provided for @sceneShootErrorNetwork.
  ///
  /// In de, this message translates to:
  /// **'Netzwerkproblem – die Änderung wurde nicht gespeichert. Versuch es erneut.'**
  String get sceneShootErrorNetwork;

  /// No description provided for @sceneShootErrorGeneric.
  ///
  /// In de, this message translates to:
  /// **'Der Szenen-Dreh konnte nicht gespeichert werden ({code}).'**
  String sceneShootErrorGeneric(Object code);

  /// No description provided for @sceneDetailTitleFallback.
  ///
  /// In de, this message translates to:
  /// **'Szene'**
  String get sceneDetailTitleFallback;

  /// No description provided for @sceneDetailScriptDay.
  ///
  /// In de, this message translates to:
  /// **'Drehtag im Skript: {day}'**
  String sceneDetailScriptDay(Object day);

  /// No description provided for @sceneDetailCharactersTitle.
  ///
  /// In de, this message translates to:
  /// **'Figuren ({count})'**
  String sceneDetailCharactersTitle(Object count);

  /// No description provided for @sceneDetailNoCharacters.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Figuren zugewiesen.'**
  String get sceneDetailNoCharacters;

  /// No description provided for @sceneDetailUnknownCharacter.
  ///
  /// In de, this message translates to:
  /// **'Unbekannte Figur'**
  String get sceneDetailUnknownCharacter;

  /// No description provided for @sceneDetailRemoveCharacterTooltip.
  ///
  /// In de, this message translates to:
  /// **'Entfernen'**
  String get sceneDetailRemoveCharacterTooltip;

  /// No description provided for @sceneDetailAssignCharacter.
  ///
  /// In de, this message translates to:
  /// **'Figur zuweisen'**
  String get sceneDetailAssignCharacter;

  /// No description provided for @sceneDetailRemoveCharacterTitle.
  ///
  /// In de, this message translates to:
  /// **'Figur entfernen?'**
  String get sceneDetailRemoveCharacterTitle;

  /// No description provided for @sceneDetailRemoveCharacterMessage.
  ///
  /// In de, this message translates to:
  /// **'{name} ist nicht mehr für diese Szene eingeplant.'**
  String sceneDetailRemoveCharacterMessage(Object name);

  /// No description provided for @sceneDetailThisCharacter.
  ///
  /// In de, this message translates to:
  /// **'Diese Figur'**
  String get sceneDetailThisCharacter;

  /// No description provided for @sceneDetailShootingDaysTitle.
  ///
  /// In de, this message translates to:
  /// **'Drehtage ({count})'**
  String sceneDetailShootingDaysTitle(Object count);

  /// No description provided for @sceneDetailNoShootingDays.
  ///
  /// In de, this message translates to:
  /// **'Noch keinem Drehtag zugeordnet.'**
  String get sceneDetailNoShootingDays;

  /// No description provided for @sceneDetailOpenDayBoard.
  ///
  /// In de, this message translates to:
  /// **'Day-Board öffnen'**
  String get sceneDetailOpenDayBoard;

  /// No description provided for @sceneDetailScheduleOnDay.
  ///
  /// In de, this message translates to:
  /// **'Auf Drehtag planen'**
  String get sceneDetailScheduleOnDay;

  /// No description provided for @sceneDetailScheduleTitle.
  ///
  /// In de, this message translates to:
  /// **'Auf Drehtag planen'**
  String get sceneDetailScheduleTitle;

  /// No description provided for @sceneDetailFetchError.
  ///
  /// In de, this message translates to:
  /// **'Szene konnte nicht geladen werden ({code}).'**
  String sceneDetailFetchError(Object code);

  /// No description provided for @sceneDetailGone.
  ///
  /// In de, this message translates to:
  /// **'Diese Szene ist nicht mehr verfügbar.'**
  String get sceneDetailGone;

  /// No description provided for @characterDetailFetchError.
  ///
  /// In de, this message translates to:
  /// **'Figur konnte nicht geladen werden ({code}).'**
  String characterDetailFetchError(Object code);

  /// No description provided for @characterDetailGone.
  ///
  /// In de, this message translates to:
  /// **'Diese Figur existiert nicht mehr.'**
  String get characterDetailGone;

  /// No description provided for @characterMeasurementHeight.
  ///
  /// In de, this message translates to:
  /// **'Höhe'**
  String get characterMeasurementHeight;

  /// No description provided for @characterMeasurementWeight.
  ///
  /// In de, this message translates to:
  /// **'Gewicht'**
  String get characterMeasurementWeight;

  /// No description provided for @characterMeasurementChest.
  ///
  /// In de, this message translates to:
  /// **'Brust'**
  String get characterMeasurementChest;

  /// No description provided for @characterMeasurementWaist.
  ///
  /// In de, this message translates to:
  /// **'Taille'**
  String get characterMeasurementWaist;

  /// No description provided for @characterMeasurementHips.
  ///
  /// In de, this message translates to:
  /// **'Hüfte'**
  String get characterMeasurementHips;

  /// No description provided for @characterMeasurementShoeSize.
  ///
  /// In de, this message translates to:
  /// **'Schuhgröße'**
  String get characterMeasurementShoeSize;

  /// No description provided for @characterMeasurementHatSize.
  ///
  /// In de, this message translates to:
  /// **'Hutgröße'**
  String get characterMeasurementHatSize;

  /// No description provided for @costumeCategoryRenameTooltip.
  ///
  /// In de, this message translates to:
  /// **'Umbenennen'**
  String get costumeCategoryRenameTooltip;

  /// No description provided for @costumeCategoryArchiveTooltip.
  ///
  /// In de, this message translates to:
  /// **'Archivieren'**
  String get costumeCategoryArchiveTooltip;

  /// No description provided for @costumeCategoriesEmpty.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Kategorien'**
  String get costumeCategoriesEmpty;

  /// No description provided for @costumeCategoriesCreateFirst.
  ///
  /// In de, this message translates to:
  /// **'Erste Kategorie erstellen'**
  String get costumeCategoriesCreateFirst;

  /// No description provided for @costumeCategoryErrorChanged.
  ///
  /// In de, this message translates to:
  /// **'Woanders geändert – aktualisiere und versuch es erneut.'**
  String get costumeCategoryErrorChanged;

  /// No description provided for @costumeCategoryErrorNetwork.
  ///
  /// In de, this message translates to:
  /// **'Netzwerkproblem – die Änderung wurde nicht gespeichert. Versuch es erneut.'**
  String get costumeCategoryErrorNetwork;

  /// No description provided for @costumeCategoryErrorGeneric.
  ///
  /// In de, this message translates to:
  /// **'Die Kategorie konnte nicht gespeichert werden ({code}).'**
  String costumeCategoryErrorGeneric(Object code);

  /// No description provided for @blockSeasonNumber.
  ///
  /// In de, this message translates to:
  /// **'Staffel {number}'**
  String blockSeasonNumber(Object number);

  /// No description provided for @blockTileLabel.
  ///
  /// In de, this message translates to:
  /// **'Block {number}'**
  String blockTileLabel(Object number);

  /// No description provided for @blocksStaleBanner.
  ///
  /// In de, this message translates to:
  /// **'Zwischengespeicherte Daten sind möglicherweise veraltet.'**
  String get blocksStaleBanner;

  /// No description provided for @blocksRoleCostume.
  ///
  /// In de, this message translates to:
  /// **'Kostüm-Rolle'**
  String get blocksRoleCostume;

  /// No description provided for @blocksRoleNone.
  ///
  /// In de, this message translates to:
  /// **'Keine Rolle in dieser Staffel'**
  String get blocksRoleNone;

  /// No description provided for @blocksRoleUnknown.
  ///
  /// In de, this message translates to:
  /// **'Rolle unbekannt ({code})'**
  String blocksRoleUnknown(Object code);

  /// No description provided for @blocksFetchError.
  ///
  /// In de, this message translates to:
  /// **'Blöcke konnten nicht geladen werden ({code}).'**
  String blocksFetchError(Object code);

  /// No description provided for @blocksEmpty.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Blöcke'**
  String get blocksEmpty;

  /// No description provided for @blocksCreateFirst.
  ///
  /// In de, this message translates to:
  /// **'Ersten Block erstellen'**
  String get blocksCreateFirst;

  /// No description provided for @blocksNotFound.
  ///
  /// In de, this message translates to:
  /// **'Diese Staffel existiert nicht mehr ({code}).'**
  String blocksNotFound(Object code);

  /// No description provided for @blocksBackToSeasons.
  ///
  /// In de, this message translates to:
  /// **'Zurück zu den Staffeln'**
  String get blocksBackToSeasons;

  /// No description provided for @blocksTileSyncing.
  ///
  /// In de, this message translates to:
  /// **'Gerade erstellt – wird synchronisiert …'**
  String get blocksTileSyncing;

  /// No description provided for @blocksTileSyncingStale.
  ///
  /// In de, this message translates to:
  /// **'Erstellt – die Liste wird noch aktualisiert. Ziehe zum Aktualisieren nach unten.'**
  String get blocksTileSyncingStale;

  /// No description provided for @blocksCreateTitle.
  ///
  /// In de, this message translates to:
  /// **'Block erstellen'**
  String get blocksCreateTitle;

  /// No description provided for @blocksNumberLabel.
  ///
  /// In de, this message translates to:
  /// **'Nummer'**
  String get blocksNumberLabel;

  /// No description provided for @blocksNumberRequired.
  ///
  /// In de, this message translates to:
  /// **'Es ist eine ganze Zahl erforderlich'**
  String get blocksNumberRequired;

  /// No description provided for @blocksStartDate.
  ///
  /// In de, this message translates to:
  /// **'Startdatum (YYYY-MM-DD, optional)'**
  String get blocksStartDate;

  /// No description provided for @blocksEndDate.
  ///
  /// In de, this message translates to:
  /// **'Enddatum (YYYY-MM-DD, optional)'**
  String get blocksEndDate;

  /// No description provided for @blocksDateFormatError.
  ///
  /// In de, this message translates to:
  /// **'Verwende YYYY-MM-DD'**
  String get blocksDateFormatError;

  /// No description provided for @blocksCreateButton.
  ///
  /// In de, this message translates to:
  /// **'Erstellen'**
  String get blocksCreateButton;

  /// No description provided for @blocksNoBlocksCreateFirst.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Blöcke – erstelle zuerst einen Block und komm dann zurück.'**
  String get blocksNoBlocksCreateFirst;

  /// No description provided for @blocksCreateErrorExists.
  ///
  /// In de, this message translates to:
  /// **'Ein Block mit dieser Nummer existiert bereits.'**
  String get blocksCreateErrorExists;

  /// No description provided for @blocksCreateErrorSignIn.
  ///
  /// In de, this message translates to:
  /// **'Bitte melde dich an, um fortzufahren.'**
  String get blocksCreateErrorSignIn;

  /// No description provided for @blocksCreateErrorNetwork.
  ///
  /// In de, this message translates to:
  /// **'Netzwerkproblem – der Block wurde nicht erstellt. Versuch es erneut.'**
  String get blocksCreateErrorNetwork;

  /// No description provided for @blocksCreateErrorGeneric.
  ///
  /// In de, this message translates to:
  /// **'Der Block konnte nicht erstellt werden ({code}).'**
  String blocksCreateErrorGeneric(Object code);

  /// No description provided for @blocksAddFab.
  ///
  /// In de, this message translates to:
  /// **'Block hinzufügen'**
  String get blocksAddFab;

  /// No description provided for @episodeTileLabel.
  ///
  /// In de, this message translates to:
  /// **'Episode {number}'**
  String episodeTileLabel(Object number);

  /// No description provided for @episodeNumberPrefix.
  ///
  /// In de, this message translates to:
  /// **'Nummer {number}'**
  String episodeNumberPrefix(Object number);

  /// No description provided for @episodesTileSyncing.
  ///
  /// In de, this message translates to:
  /// **'Gerade erstellt – wird synchronisiert …'**
  String get episodesTileSyncing;

  /// No description provided for @episodesTileSyncingStale.
  ///
  /// In de, this message translates to:
  /// **'Erstellt – die Liste wird noch aktualisiert. Ziehe zum Aktualisieren nach unten.'**
  String get episodesTileSyncingStale;

  /// No description provided for @episodesEmpty.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Episoden'**
  String get episodesEmpty;

  /// No description provided for @episodesCreateFirst.
  ///
  /// In de, this message translates to:
  /// **'Erste Episode erstellen'**
  String get episodesCreateFirst;

  /// No description provided for @episodesNotFound.
  ///
  /// In de, this message translates to:
  /// **'Dieser Block existiert nicht mehr ({code}).'**
  String episodesNotFound(Object code);

  /// No description provided for @episodesBackToBlocks.
  ///
  /// In de, this message translates to:
  /// **'Zurück zu den Blöcken'**
  String get episodesBackToBlocks;

  /// No description provided for @episodesAddFab.
  ///
  /// In de, this message translates to:
  /// **'Episode hinzufügen'**
  String get episodesAddFab;

  /// No description provided for @episodesFetchError.
  ///
  /// In de, this message translates to:
  /// **'Episoden konnten nicht geladen werden ({code}).'**
  String episodesFetchError(Object code);

  /// No description provided for @episodesStaleBanner.
  ///
  /// In de, this message translates to:
  /// **'Zwischengespeicherte Daten sind möglicherweise veraltet.'**
  String get episodesStaleBanner;

  /// No description provided for @episodesDismiss.
  ///
  /// In de, this message translates to:
  /// **'Ausblenden'**
  String get episodesDismiss;

  /// No description provided for @episodesCreateTitle.
  ///
  /// In de, this message translates to:
  /// **'Episode erstellen'**
  String get episodesCreateTitle;

  /// No description provided for @episodesNameLabel.
  ///
  /// In de, this message translates to:
  /// **'Name (optional)'**
  String get episodesNameLabel;

  /// No description provided for @episodesCreateErrorExists.
  ///
  /// In de, this message translates to:
  /// **'Eine Episode mit dieser Nummer existiert bereits.'**
  String get episodesCreateErrorExists;

  /// No description provided for @episodesCreateErrorNetwork.
  ///
  /// In de, this message translates to:
  /// **'Netzwerkproblem – die Episode wurde nicht erstellt. Versuch es erneut.'**
  String get episodesCreateErrorNetwork;

  /// No description provided for @episodesCreateErrorGeneric.
  ///
  /// In de, this message translates to:
  /// **'Die Episode konnte nicht erstellt werden ({code}).'**
  String episodesCreateErrorGeneric(Object code);

  /// No description provided for @sceneTileLabel.
  ///
  /// In de, this message translates to:
  /// **'Szene {identifier}'**
  String sceneTileLabel(Object identifier);

  /// No description provided for @sceneMood.
  ///
  /// In de, this message translates to:
  /// **'Stimmung: {mood}'**
  String sceneMood(Object mood);

  /// No description provided for @sceneLoc.
  ///
  /// In de, this message translates to:
  /// **'Ort: {loc}'**
  String sceneLoc(Object loc);

  /// No description provided for @sceneDay.
  ///
  /// In de, this message translates to:
  /// **'Tag: {day}'**
  String sceneDay(Object day);

  /// No description provided for @sceneScheduled.
  ///
  /// In de, this message translates to:
  /// **'Eingeplant'**
  String get sceneScheduled;

  /// No description provided for @sceneUnscheduled.
  ///
  /// In de, this message translates to:
  /// **'Nicht eingeplant'**
  String get sceneUnscheduled;

  /// No description provided for @sceneCharacterCount.
  ///
  /// In de, this message translates to:
  /// **'{count} Figuren'**
  String sceneCharacterCount(Object count);

  /// No description provided for @sceneShootingDayCount.
  ///
  /// In de, this message translates to:
  /// **'{count} Drehtage'**
  String sceneShootingDayCount(Object count);

  /// No description provided for @scenesTileSyncing.
  ///
  /// In de, this message translates to:
  /// **'Gerade erstellt – wird synchronisiert …'**
  String get scenesTileSyncing;

  /// No description provided for @scenesTileSyncingStale.
  ///
  /// In de, this message translates to:
  /// **'Erstellt – die Liste wird noch aktualisiert. Ziehe zum Aktualisieren nach unten.'**
  String get scenesTileSyncingStale;

  /// No description provided for @scenesEmpty.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Szenen'**
  String get scenesEmpty;

  /// No description provided for @scenesCreateFirst.
  ///
  /// In de, this message translates to:
  /// **'Erste Szene erstellen'**
  String get scenesCreateFirst;

  /// No description provided for @scenesNotFound.
  ///
  /// In de, this message translates to:
  /// **'Diese Episode existiert nicht mehr ({code}).'**
  String scenesNotFound(Object code);

  /// No description provided for @scenesBackToEpisodes.
  ///
  /// In de, this message translates to:
  /// **'Zurück zu den Episoden'**
  String get scenesBackToEpisodes;

  /// No description provided for @scenesAddFab.
  ///
  /// In de, this message translates to:
  /// **'Szene hinzufügen'**
  String get scenesAddFab;

  /// No description provided for @scenesFetchError.
  ///
  /// In de, this message translates to:
  /// **'Szenen konnten nicht geladen werden ({code}).'**
  String scenesFetchError(Object code);

  /// No description provided for @scenesCreateTitle.
  ///
  /// In de, this message translates to:
  /// **'Szene erstellen'**
  String get scenesCreateTitle;

  /// No description provided for @sceneNumberLabel.
  ///
  /// In de, this message translates to:
  /// **'Szenennummer (optional)'**
  String get sceneNumberLabel;

  /// No description provided for @sceneSummaryLabel.
  ///
  /// In de, this message translates to:
  /// **'Zusammenfassung (optional)'**
  String get sceneSummaryLabel;

  /// No description provided for @sceneMoodLabel.
  ///
  /// In de, this message translates to:
  /// **'Stimmung (optional)'**
  String get sceneMoodLabel;

  /// No description provided for @sceneLocationLabel.
  ///
  /// In de, this message translates to:
  /// **'Ort (optional)'**
  String get sceneLocationLabel;

  /// No description provided for @sceneScriptDayLabel.
  ///
  /// In de, this message translates to:
  /// **'Drehtag im Skript (optional)'**
  String get sceneScriptDayLabel;

  /// No description provided for @scenesCreateErrorNetwork.
  ///
  /// In de, this message translates to:
  /// **'Netzwerkproblem – die Szene wurde nicht erstellt. Versuch es erneut.'**
  String get scenesCreateErrorNetwork;

  /// No description provided for @scenesCreateErrorGeneric.
  ///
  /// In de, this message translates to:
  /// **'Die Szene konnte nicht erstellt werden ({code}).'**
  String scenesCreateErrorGeneric(Object code);

  /// No description provided for @scenesStaleBanner.
  ///
  /// In de, this message translates to:
  /// **'Zwischengespeicherte Daten sind möglicherweise veraltet.'**
  String get scenesStaleBanner;

  /// No description provided for @settingsTitle.
  ///
  /// In de, this message translates to:
  /// **'Einstellungen'**
  String get settingsTitle;

  /// No description provided for @settingsServerAddress.
  ///
  /// In de, this message translates to:
  /// **'Serveradresse'**
  String get settingsServerAddress;

  /// No description provided for @settingsFlavor.
  ///
  /// In de, this message translates to:
  /// **'Flavor'**
  String get settingsFlavor;

  /// No description provided for @settingsBackendUri.
  ///
  /// In de, this message translates to:
  /// **'Backend-URI'**
  String get settingsBackendUri;

  /// No description provided for @settingsProdNote.
  ///
  /// In de, this message translates to:
  /// **'Die Serveradresse wird von deiner Organisation sicherheitsbedingt festgelegt und kann hier nicht geändert werden.'**
  String get settingsProdNote;

  /// No description provided for @settingsReset.
  ///
  /// In de, this message translates to:
  /// **'Zurücksetzen'**
  String get settingsReset;

  /// No description provided for @settingsSave.
  ///
  /// In de, this message translates to:
  /// **'Speichern'**
  String get settingsSave;

  /// No description provided for @settingsClose.
  ///
  /// In de, this message translates to:
  /// **'Schließen'**
  String get settingsClose;

  /// No description provided for @commonDismiss.
  ///
  /// In de, this message translates to:
  /// **'Schließen'**
  String get commonDismiss;

  /// No description provided for @commonCancel.
  ///
  /// In de, this message translates to:
  /// **'Abbrechen'**
  String get commonCancel;

  /// No description provided for @commonSave.
  ///
  /// In de, this message translates to:
  /// **'Speichern'**
  String get commonSave;

  /// No description provided for @commonDelete.
  ///
  /// In de, this message translates to:
  /// **'Löschen'**
  String get commonDelete;

  /// No description provided for @commonEdit.
  ///
  /// In de, this message translates to:
  /// **'Bearbeiten'**
  String get commonEdit;

  /// No description provided for @commonClose.
  ///
  /// In de, this message translates to:
  /// **'Schließen'**
  String get commonClose;

  /// No description provided for @commonMore.
  ///
  /// In de, this message translates to:
  /// **'Mehr'**
  String get commonMore;

  /// No description provided for @commonSettings.
  ///
  /// In de, this message translates to:
  /// **'Einstellungen'**
  String get commonSettings;

  /// No description provided for @commonSignOut.
  ///
  /// In de, this message translates to:
  /// **'Abmelden'**
  String get commonSignOut;

  /// No description provided for @commonAbout.
  ///
  /// In de, this message translates to:
  /// **'Über die App'**
  String get commonAbout;

  /// No description provided for @commonNoResults.
  ///
  /// In de, this message translates to:
  /// **'Keine Treffer'**
  String get commonNoResults;

  /// No description provided for @commonSignedIn.
  ///
  /// In de, this message translates to:
  /// **'Angemeldet'**
  String get commonSignedIn;

  /// No description provided for @commonSignedOut.
  ///
  /// In de, this message translates to:
  /// **'Abgemeldet'**
  String get commonSignedOut;

  /// No description provided for @commonUnknown.
  ///
  /// In de, this message translates to:
  /// **'Unbekannt'**
  String get commonUnknown;

  /// No description provided for @navSeasons.
  ///
  /// In de, this message translates to:
  /// **'Season'**
  String get navSeasons;

  /// No description provided for @navPlanen.
  ///
  /// In de, this message translates to:
  /// **'Planen'**
  String get navPlanen;

  /// No description provided for @navCostumes.
  ///
  /// In de, this message translates to:
  /// **'Garderobe'**
  String get navCostumes;

  /// No description provided for @navCharacters.
  ///
  /// In de, this message translates to:
  /// **'Figuren'**
  String get navCharacters;

  /// No description provided for @navAiImport.
  ///
  /// In de, this message translates to:
  /// **'Import'**
  String get navAiImport;

  /// No description provided for @navMore.
  ///
  /// In de, this message translates to:
  /// **'Mehr'**
  String get navMore;

  /// No description provided for @navShootingDays.
  ///
  /// In de, this message translates to:
  /// **'Drehtage'**
  String get navShootingDays;

  /// No description provided for @navEpisodes.
  ///
  /// In de, this message translates to:
  /// **'Episoden'**
  String get navEpisodes;

  /// No description provided for @navScenes.
  ///
  /// In de, this message translates to:
  /// **'Szenen'**
  String get navScenes;

  /// No description provided for @seasonsTitle.
  ///
  /// In de, this message translates to:
  /// **'Seasons'**
  String get seasonsTitle;

  /// No description provided for @seasonsStaleJustNow.
  ///
  /// In de, this message translates to:
  /// **'gerade eben'**
  String get seasonsStaleJustNow;

  /// No description provided for @reconcileStaleWarning.
  ///
  /// In de, this message translates to:
  /// **'Erstellt – die Liste wird noch aktualisiert. Ziehe zum Aktualisieren nach unten.'**
  String get reconcileStaleWarning;

  /// No description provided for @seasonsStaleMinutes.
  ///
  /// In de, this message translates to:
  /// **'vor {count} min'**
  String seasonsStaleMinutes(Object count);

  /// No description provided for @seasonsStaleHours.
  ///
  /// In de, this message translates to:
  /// **'vor {count} h'**
  String seasonsStaleHours(Object count);

  /// No description provided for @seasonsStaleDays.
  ///
  /// In de, this message translates to:
  /// **'vor {count} d'**
  String seasonsStaleDays(Object count);

  /// No description provided for @seasonsCreate.
  ///
  /// In de, this message translates to:
  /// **'Season erstellen'**
  String get seasonsCreate;

  /// No description provided for @seasonsEmptyTitle.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Seasons'**
  String get seasonsEmptyTitle;

  /// No description provided for @seasonsEmptyGuidance.
  ///
  /// In de, this message translates to:
  /// **'Lege deine erste Season an — oder importiere einen bestehenden Spielplan per KI.'**
  String get seasonsEmptyGuidance;

  /// No description provided for @seasonsEmptySetupCta.
  ///
  /// In de, this message translates to:
  /// **'Season-Setup starten'**
  String get seasonsEmptySetupCta;

  /// No description provided for @seasonsEmptyImportCta.
  ///
  /// In de, this message translates to:
  /// **'KI-Import öffnen'**
  String get seasonsEmptyImportCta;

  /// No description provided for @seasonsLoadError.
  ///
  /// In de, this message translates to:
  /// **'Seasons konnten nicht geladen werden'**
  String get seasonsLoadError;

  /// No description provided for @seasonsStale.
  ///
  /// In de, this message translates to:
  /// **'Zwischengespeicherte Daten sind möglicherweise veraltet'**
  String get seasonsStale;

  /// No description provided for @seasonsCreateConflict.
  ///
  /// In de, this message translates to:
  /// **'Eine Season mit dieser Nummer existiert bereits.'**
  String get seasonsCreateConflict;

  /// No description provided for @seasonsCreateAuth.
  ///
  /// In de, this message translates to:
  /// **'Bitte melde dich an, um fortzufahren.'**
  String get seasonsCreateAuth;

  /// No description provided for @seasonsCreateNetwork.
  ///
  /// In de, this message translates to:
  /// **'Netzwerkproblem — die Season wurde nicht erstellt. Bitte versuche es erneut.'**
  String get seasonsCreateNetwork;

  /// No description provided for @seasonsCreateGeneric.
  ///
  /// In de, this message translates to:
  /// **'Die Season konnte nicht erstellt werden.'**
  String get seasonsCreateGeneric;

  /// No description provided for @seasonsDefaultTitle.
  ///
  /// In de, this message translates to:
  /// **'Season {number}'**
  String seasonsDefaultTitle(Object number);

  /// No description provided for @seasonsSyncing.
  ///
  /// In de, this message translates to:
  /// **'Wird erstellt — Synchronisierung läuft…'**
  String get seasonsSyncing;

  /// No description provided for @seasonsStaleAt.
  ///
  /// In de, this message translates to:
  /// **'Stand: {relative}'**
  String seasonsStaleAt(Object relative);

  /// No description provided for @seasonsMetaBlocks.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Block} other{{count} Blöcke}}'**
  String seasonsMetaBlocks(num count);

  /// No description provided for @seasonsMetaScenes.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Szene} other{{count} Szenen}}'**
  String seasonsMetaScenes(num count);

  /// No description provided for @seasonsMetaCostumes.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Kostüm} other{{count} Kostüme}}'**
  String seasonsMetaCostumes(num count);

  /// No description provided for @planningNoSeasons.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Seasons'**
  String get planningNoSeasons;

  /// No description provided for @planningLoadError.
  ///
  /// In de, this message translates to:
  /// **'Seasons konnten nicht geladen werden.'**
  String get planningLoadError;

  /// No description provided for @planningSeasonNumber.
  ///
  /// In de, this message translates to:
  /// **'Nummer {number}'**
  String planningSeasonNumber(Object number);

  /// No description provided for @planningImportSubtitle.
  ///
  /// In de, this message translates to:
  /// **'KI-Assistent: Spielplan importieren'**
  String get planningImportSubtitle;

  /// No description provided for @authSignIn.
  ///
  /// In de, this message translates to:
  /// **'Anmelden'**
  String get authSignIn;

  /// No description provided for @authContinue.
  ///
  /// In de, this message translates to:
  /// **'Weiter'**
  String get authContinue;

  /// No description provided for @authSignOut.
  ///
  /// In de, this message translates to:
  /// **'Abmelden'**
  String get authSignOut;

  /// No description provided for @authWip.
  ///
  /// In de, this message translates to:
  /// **'In Arbeit'**
  String get authWip;

  /// No description provided for @authDevNotice.
  ///
  /// In de, this message translates to:
  /// **'Entwickleranmeldung aktiv — Fortfahren als {subject}.'**
  String authDevNotice(Object subject);

  /// No description provided for @authContinueAs.
  ///
  /// In de, this message translates to:
  /// **'Als {subject} fortfahren'**
  String authContinueAs(Object subject);

  /// No description provided for @authSignedIn.
  ///
  /// In de, this message translates to:
  /// **'Angemeldet'**
  String get authSignedIn;

  /// No description provided for @authErrorConfiguration.
  ///
  /// In de, this message translates to:
  /// **'Die Anmeldung ist in diesem Build nicht verfügbar.'**
  String get authErrorConfiguration;

  /// No description provided for @authErrorRestore.
  ///
  /// In de, this message translates to:
  /// **'Die vorherige Sitzung konnte nicht wiederhergestellt werden. Bitte melde dich erneut an.'**
  String get authErrorRestore;

  /// No description provided for @authErrorSignInFailed.
  ///
  /// In de, this message translates to:
  /// **'Anmeldung fehlgeschlagen. Bitte versuche es erneut.'**
  String get authErrorSignInFailed;

  /// No description provided for @authErrorNetwork.
  ///
  /// In de, this message translates to:
  /// **'Netzwerkproblem — die Anmeldung wurde nicht abgeschlossen. Bitte versuche es erneut.'**
  String get authErrorNetwork;

  /// No description provided for @authErrorGeneric.
  ///
  /// In de, this message translates to:
  /// **'Etwas ist schiefgelaufen. Bitte versuche es erneut.'**
  String get authErrorGeneric;

  /// No description provided for @fatalConfigTitle.
  ///
  /// In de, this message translates to:
  /// **'TLS-Konfiguration ungültig'**
  String get fatalConfigTitle;

  /// No description provided for @fatalConfigBody.
  ///
  /// In de, this message translates to:
  /// **'Die App kann sicher nicht gestartet werden: {error}\nEs wurden keine Netzwerkanfragen gesendet.'**
  String fatalConfigBody(Object error);

  /// No description provided for @infoTitle.
  ///
  /// In de, this message translates to:
  /// **'Über Breakdown'**
  String get infoTitle;

  /// No description provided for @infoVersion.
  ///
  /// In de, this message translates to:
  /// **'Version'**
  String get infoVersion;

  /// No description provided for @infoLicense.
  ///
  /// In de, this message translates to:
  /// **'Lizenz'**
  String get infoLicense;

  /// No description provided for @infoLicenseBody.
  ///
  /// In de, this message translates to:
  /// **'GNU Affero General Public License v3.0. Dies ist freie Software: Du darfst sie verwenden, untersuchen, weitergeben und verändern.'**
  String get infoLicenseBody;

  /// No description provided for @infoSource.
  ///
  /// In de, this message translates to:
  /// **'Quellcode ansehen'**
  String get infoSource;

  /// No description provided for @infoSourceError.
  ///
  /// In de, this message translates to:
  /// **'Der Quellcode-Link konnte nicht geöffnet werden.'**
  String get infoSourceError;

  /// No description provided for @infoAiUsage.
  ///
  /// In de, this message translates to:
  /// **'KI-Nutzung'**
  String get infoAiUsage;

  /// No description provided for @infoAiBody.
  ///
  /// In de, this message translates to:
  /// **'Beim ausdrücklichen Absenden von Importen wird der von Dir bereitgestellte Text an einen konfigurierten serverseitigen KI-Anbieter gesendet. Diese App kontaktiert KI-Anbieter nicht direkt.'**
  String get infoAiBody;

  /// No description provided for @moreTitle.
  ///
  /// In de, this message translates to:
  /// **'Mehr'**
  String get moreTitle;

  /// No description provided for @moreCategories.
  ///
  /// In de, this message translates to:
  /// **'Kostüm-Kategorien'**
  String get moreCategories;

  /// No description provided for @moreCategoriesOpenPlanen.
  ///
  /// In de, this message translates to:
  /// **'Season im Planen-Tab öffnen'**
  String get moreCategoriesOpenPlanen;

  /// No description provided for @moreSignedIn.
  ///
  /// In de, this message translates to:
  /// **'Angemeldet'**
  String get moreSignedIn;

  /// No description provided for @moreSignedOut.
  ///
  /// In de, this message translates to:
  /// **'Abgemeldet'**
  String get moreSignedOut;

  /// No description provided for @genericProblemTitle.
  ///
  /// In de, this message translates to:
  /// **'Etwas ist schiefgelaufen'**
  String get genericProblemTitle;

  /// No description provided for @genericProblemBody.
  ///
  /// In de, this message translates to:
  /// **'Die Aktion konnte nicht abgeschlossen werden. Bitte versuche es erneut.'**
  String get genericProblemBody;

  /// No description provided for @genericProblemAction.
  ///
  /// In de, this message translates to:
  /// **'Erneut versuchen'**
  String get genericProblemAction;

  /// No description provided for @problemAuthzDenied.
  ///
  /// In de, this message translates to:
  /// **'Für diese Aktion fehlt dir die Berechtigung.'**
  String get problemAuthzDenied;

  /// No description provided for @problemAuthzSessionRequired.
  ///
  /// In de, this message translates to:
  /// **'Bitte melde dich an, um fortzufahren.'**
  String get problemAuthzSessionRequired;

  /// No description provided for @problemNetwork.
  ///
  /// In de, this message translates to:
  /// **'Die Verbindung zum Server ist fehlgeschlagen. Bitte versuche es erneut.'**
  String get problemNetwork;

  /// No description provided for @shootingDaySemantics.
  ///
  /// In de, this message translates to:
  /// **'Drehtag {label}'**
  String shootingDaySemantics(Object label);

  /// No description provided for @shootingDayUntitled.
  ///
  /// In de, this message translates to:
  /// **'Drehtag ohne Titel'**
  String get shootingDayUntitled;

  /// No description provided for @shootingDayArchived.
  ///
  /// In de, this message translates to:
  /// **'Archiviert'**
  String get shootingDayArchived;

  /// No description provided for @shootingDayWrapped.
  ///
  /// In de, this message translates to:
  /// **'Abgeschlossen'**
  String get shootingDayWrapped;

  /// No description provided for @shootingDayActions.
  ///
  /// In de, this message translates to:
  /// **'Tagesaktionen'**
  String get shootingDayActions;

  /// No description provided for @shootingDayMoveEarlier.
  ///
  /// In de, this message translates to:
  /// **'Nach vorne verschieben'**
  String get shootingDayMoveEarlier;

  /// No description provided for @shootingDayMoveLater.
  ///
  /// In de, this message translates to:
  /// **'Nach hinten verschieben'**
  String get shootingDayMoveLater;

  /// No description provided for @shootingDayRename.
  ///
  /// In de, this message translates to:
  /// **'Umbenennen'**
  String get shootingDayRename;

  /// No description provided for @shootingDayReschedule.
  ///
  /// In de, this message translates to:
  /// **'Neuer Drehtag'**
  String get shootingDayReschedule;

  /// No description provided for @shootingDayUnschedule.
  ///
  /// In de, this message translates to:
  /// **'Datum entfernen'**
  String get shootingDayUnschedule;

  /// No description provided for @shootingDayArchive.
  ///
  /// In de, this message translates to:
  /// **'Archivieren'**
  String get shootingDayArchive;

  /// No description provided for @shootingDayNew.
  ///
  /// In de, this message translates to:
  /// **'Neuer Drehtag'**
  String get shootingDayNew;

  /// No description provided for @shootingDaysEmpty.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Drehtage'**
  String get shootingDaysEmpty;

  /// No description provided for @shootingDaysCreate.
  ///
  /// In de, this message translates to:
  /// **'Drehtag erstellen'**
  String get shootingDaysCreate;

  /// No description provided for @shootingDaysGone.
  ///
  /// In de, this message translates to:
  /// **'Die Episode ist nicht mehr verfügbar.'**
  String get shootingDaysGone;

  /// No description provided for @commonBack.
  ///
  /// In de, this message translates to:
  /// **'Zurück'**
  String get commonBack;

  /// No description provided for @seasonTabSemantic.
  ///
  /// In de, this message translates to:
  /// **'{label}, Tab {position} von 4'**
  String seasonTabSemantic(Object label, Object position);

  /// No description provided for @seasonTabSemanticEn.
  ///
  /// In de, this message translates to:
  /// **'{label}, Tab {position} of 4'**
  String seasonTabSemanticEn(Object label, Object position);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
