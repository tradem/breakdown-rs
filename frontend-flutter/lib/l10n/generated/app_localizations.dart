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

  /// No description provided for @characterCategoryEditTooltip.
  ///
  /// In de, this message translates to:
  /// **'Rollentyp ändern'**
  String get characterCategoryEditTooltip;

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

  /// No description provided for @pieceErrorChanged.
  ///
  /// In de, this message translates to:
  /// **'Woanders geändert – zum Aktualisieren ziehen und erneut versuchen.'**
  String get pieceErrorChanged;

  /// No description provided for @pieceErrorForbidden.
  ///
  /// In de, this message translates to:
  /// **'Du benötigst eine aktive Kostüm-Rolle in dieser Staffel.'**
  String get pieceErrorForbidden;

  /// No description provided for @pieceErrorMembership.
  ///
  /// In de, this message translates to:
  /// **'Berechtigungen konnten nicht überprüft werden – Verbindung prüfen und erneut versuchen.'**
  String get pieceErrorMembership;

  /// No description provided for @pieceErrorGeneric.
  ///
  /// In de, this message translates to:
  /// **'Das Kleidungsstück konnte nicht gespeichert werden ({code}).'**
  String pieceErrorGeneric(Object code);

  /// No description provided for @pieceErrorCategorySeason.
  ///
  /// In de, this message translates to:
  /// **'Diese Kategorie gehört zu einer anderen Staffel – wähle eine Kategorie dieser Staffel.'**
  String get pieceErrorCategorySeason;

  /// No description provided for @pieceErrorCategoryArchived.
  ///
  /// In de, this message translates to:
  /// **'Diese Kategorie ist archiviert – wähle eine aktive Kategorie.'**
  String get pieceErrorCategoryArchived;

  /// No description provided for @pieceErrorDetailNotFound.
  ///
  /// In de, this message translates to:
  /// **'Dieses Detail existiert nicht mehr – die Liste wurde aktualisiert.'**
  String get pieceErrorDetailNotFound;

  /// No description provided for @pieceDetailCategoryTitle.
  ///
  /// In de, this message translates to:
  /// **'Kategorie'**
  String get pieceDetailCategoryTitle;

  /// No description provided for @pieceDetailPickCategory.
  ///
  /// In de, this message translates to:
  /// **'Kategorie wählen'**
  String get pieceDetailPickCategory;

  /// No description provided for @pieceDetailCategorySaved.
  ///
  /// In de, this message translates to:
  /// **'Kategorie gespeichert.'**
  String get pieceDetailCategorySaved;

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
  /// **'Du benötigst eine aktive Kostüm-Rolle in dieser Produktion, um Fotos zu verwalten.'**
  String get photoErrorForbidden;

  /// No description provided for @photoErrorContainerUnresolved.
  ///
  /// In de, this message translates to:
  /// **'Für dieses Kleidungsstück kann kein zugehöriger Container ermittelt werden — lade die Garderobe neu und versuch es erneut.'**
  String get photoErrorContainerUnresolved;

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

  /// No description provided for @pieceAddFab.
  ///
  /// In de, this message translates to:
  /// **'Kleidungsstück erstellen'**
  String get pieceAddFab;

  /// No description provided for @piecesStaleBanner.
  ///
  /// In de, this message translates to:
  /// **'Zwischengespeicherte Daten sind möglicherweise veraltet.'**
  String get piecesStaleBanner;

  /// No description provided for @piecesFetchError.
  ///
  /// In de, this message translates to:
  /// **'Kleidungsstücke konnten nicht geladen werden ({code}).'**
  String piecesFetchError(Object code);

  /// No description provided for @pieceTileLabel.
  ///
  /// In de, this message translates to:
  /// **'Kleidungsstück {id}'**
  String pieceTileLabel(Object id);

  /// No description provided for @pieceTileLabelFallback.
  ///
  /// In de, this message translates to:
  /// **'Kleidungsstück'**
  String get pieceTileLabelFallback;

  /// No description provided for @costumeCategoryUncategorized.
  ///
  /// In de, this message translates to:
  /// **'Ohne Kategorie'**
  String get costumeCategoryUncategorized;

  /// No description provided for @pieceDetailSaved.
  ///
  /// In de, this message translates to:
  /// **'Kleidungsstück gespeichert.'**
  String get pieceDetailSaved;

  /// No description provided for @pieceDetailsCount.
  ///
  /// In de, this message translates to:
  /// **'{count} Details'**
  String pieceDetailsCount(Object count);

  /// No description provided for @piecePhotosCount.
  ///
  /// In de, this message translates to:
  /// **'{count} Fotos'**
  String piecePhotosCount(Object count);

  /// No description provided for @pieceTileSyncing.
  ///
  /// In de, this message translates to:
  /// **'Gerade gespeichert – wird synchronisiert …'**
  String get pieceTileSyncing;

  /// No description provided for @pieceTileSyncingStale.
  ///
  /// In de, this message translates to:
  /// **'Erstellt – die Liste wird noch aktualisiert. Ziehe zum Aktualisieren nach unten.'**
  String get pieceTileSyncingStale;

  /// No description provided for @piecesEmpty.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Kleidungsstücke'**
  String get piecesEmpty;

  /// No description provided for @createSeasonTitle.
  ///
  /// In de, this message translates to:
  /// **'Staffel erstellen'**
  String get createSeasonTitle;

  /// No description provided for @createSeasonTitleLabel.
  ///
  /// In de, this message translates to:
  /// **'Titel'**
  String get createSeasonTitleLabel;

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

  /// No description provided for @shootingDaysReportsLabel.
  ///
  /// In de, this message translates to:
  /// **'Berichte'**
  String get shootingDaysReportsLabel;

  /// No description provided for @reportsIndexTitle.
  ///
  /// In de, this message translates to:
  /// **'Berichte – {episode}'**
  String reportsIndexTitle(Object episode);

  /// No description provided for @reportsIndexDayFinal.
  ///
  /// In de, this message translates to:
  /// **'Abschließend'**
  String get reportsIndexDayFinal;

  /// No description provided for @reportsIndexDayOpen.
  ///
  /// In de, this message translates to:
  /// **'Offen'**
  String get reportsIndexDayOpen;

  /// No description provided for @reportsIndexEmpty.
  ///
  /// In de, this message translates to:
  /// **'Sobald ein Drehtag geplant ist, öffnet sich hier der Soll-/Ist-Bericht (geplant vs. tatsächlich) dieses Tages.'**
  String get reportsIndexEmpty;

  /// No description provided for @shootingDaysReportsAggregateLabel.
  ///
  /// In de, this message translates to:
  /// **'Soll-Ist gesamt'**
  String get shootingDaysReportsAggregateLabel;

  /// No description provided for @reportsAggregateTitle.
  ///
  /// In de, this message translates to:
  /// **'Soll-Ist-Vergleich – {scope}'**
  String reportsAggregateTitle(Object scope);

  /// No description provided for @reportsAggregateFinal.
  ///
  /// In de, this message translates to:
  /// **'Abschließend – alle Drehtage sind abgeschlossen.'**
  String get reportsAggregateFinal;

  /// No description provided for @reportsAggregateProvisional.
  ///
  /// In de, this message translates to:
  /// **'Vorläufig – {wrapped} von {total} Drehtagen abgeschlossen.'**
  String reportsAggregateProvisional(Object total, Object wrapped);

  /// No description provided for @reportsAggregateProgress.
  ///
  /// In de, this message translates to:
  /// **'{wrapped} von {total} Drehtagen abgeschlossen'**
  String reportsAggregateProgress(Object total, Object wrapped);

  /// No description provided for @reportsAggregatePdf.
  ///
  /// In de, this message translates to:
  /// **'Soll-Ist-Vergleich (PDF)'**
  String get reportsAggregatePdf;

  /// No description provided for @reportsAggregateSceneLabel.
  ///
  /// In de, this message translates to:
  /// **'Szenen-Nr: {number}'**
  String reportsAggregateSceneLabel(Object number);

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

  /// No description provided for @aiConfigErrorProviderMismatch.
  ///
  /// In de, this message translates to:
  /// **'Der API-Schlüssel gehört nicht zu diesem Anbieter. Wähle den Anbieter, zu dem der gespeicherte Schlüssel gehört, oder sende einen neuen Schlüssel.'**
  String get aiConfigErrorProviderMismatch;

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

  /// No description provided for @aiConfigNoImageModels.
  ///
  /// In de, this message translates to:
  /// **'Dieser Anbieter bietet keine Bildmodelle.'**
  String get aiConfigNoImageModels;

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

  /// No description provided for @aiJobsTitle.
  ///
  /// In de, this message translates to:
  /// **'KI-Import-Aufträge'**
  String get aiJobsTitle;

  /// No description provided for @aiJobsEmpty.
  ///
  /// In de, this message translates to:
  /// **'Noch kein KI-Import gestartet.'**
  String get aiJobsEmpty;

  /// No description provided for @aiJobsEmptyCta.
  ///
  /// In de, this message translates to:
  /// **'KI-Import starten'**
  String get aiJobsEmptyCta;

  /// No description provided for @aiJobsActiveBadge.
  ///
  /// In de, this message translates to:
  /// **'Aktive Aufträge: {count}'**
  String aiJobsActiveBadge(Object count);

  /// No description provided for @aiJobsRowSubtitle.
  ///
  /// In de, this message translates to:
  /// **'{kind} · {date}'**
  String aiJobsRowSubtitle(Object date, Object kind);

  /// No description provided for @aiJobsLoadError.
  ///
  /// In de, this message translates to:
  /// **'Die Auftragsliste konnte nicht geladen werden ({code}).'**
  String aiJobsLoadError(Object code);

  /// No description provided for @aiJobsDeleteTooltip.
  ///
  /// In de, this message translates to:
  /// **'Import löschen'**
  String get aiJobsDeleteTooltip;

  /// No description provided for @aiJobsDeleteConfirmTitle.
  ///
  /// In de, this message translates to:
  /// **'Import löschen?'**
  String get aiJobsDeleteConfirmTitle;

  /// No description provided for @aiJobsDeleteConfirmBody.
  ///
  /// In de, this message translates to:
  /// **'Dadurch wird auch die Duplikat-Sperre aufgehoben – das Dokument kann erneut importiert werden.'**
  String get aiJobsDeleteConfirmBody;

  /// No description provided for @aiJobsDeleteConfirmDelete.
  ///
  /// In de, this message translates to:
  /// **'Löschen'**
  String get aiJobsDeleteConfirmDelete;

  /// No description provided for @aiJobsDeleteConfirmCancel.
  ///
  /// In de, this message translates to:
  /// **'Abbrechen'**
  String get aiJobsDeleteConfirmCancel;

  /// No description provided for @aiJobsDeleteNotDeletable.
  ///
  /// In de, this message translates to:
  /// **'Dieser Import wird noch verarbeitet und kann noch nicht gelöscht werden.'**
  String get aiJobsDeleteNotDeletable;

  /// No description provided for @aiJobsDeleteFailed.
  ///
  /// In de, this message translates to:
  /// **'Der Import konnte nicht gelöscht werden ({code}).'**
  String aiJobsDeleteFailed(Object code);

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

  /// No description provided for @aiJobNextRetryImminent.
  ///
  /// In de, this message translates to:
  /// **'Erneuter Versuch steht kurz bevor.'**
  String get aiJobNextRetryImminent;

  /// No description provided for @aiJobNextRetryMinutes.
  ///
  /// In de, this message translates to:
  /// **'Erneuter Versuch in ~{count} min'**
  String aiJobNextRetryMinutes(Object count);

  /// No description provided for @aiJobNextRetryHours.
  ///
  /// In de, this message translates to:
  /// **'Erneuter Versuch in ~{count} h'**
  String aiJobNextRetryHours(Object count);

  /// No description provided for @aiJobNextRetryDays.
  ///
  /// In de, this message translates to:
  /// **'Erneuter Versuch in ~{count} d'**
  String aiJobNextRetryDays(Object count);

  /// No description provided for @aiJobNextRetryUnknown.
  ///
  /// In de, this message translates to:
  /// **'Erneuter Versuch geplant – Zeitpunkt noch unbekannt.'**
  String get aiJobNextRetryUnknown;

  /// No description provided for @aiJobReasonUnknown.
  ///
  /// In de, this message translates to:
  /// **'Der letzte Versuch ist aus unbekanntem Grund fehlgeschlagen.'**
  String get aiJobReasonUnknown;

  /// No description provided for @aiJobReasonDependencyAuth.
  ///
  /// In de, this message translates to:
  /// **'Eine Dienst-Anmeldung wurde abgelehnt – die Wiederholungen laufen weiter, aber sie braucht eventuell Aufmerksamkeit.'**
  String get aiJobReasonDependencyAuth;

  /// No description provided for @aiJobReasonServiceUnavailable.
  ///
  /// In de, this message translates to:
  /// **'Ein Dienst war vorübergehend nicht erreichbar – der nächste Versuch kann gelingen.'**
  String get aiJobReasonServiceUnavailable;

  /// No description provided for @aiJobReasonInternal.
  ///
  /// In de, this message translates to:
  /// **'Ein Serverfehler ist aufgetreten.'**
  String get aiJobReasonInternal;

  /// No description provided for @aiJobReasonGeneric.
  ///
  /// In de, this message translates to:
  /// **'Der letzte Versuch ist fehlgeschlagen ({code}).'**
  String aiJobReasonGeneric(Object code);

  /// No description provided for @aiJobAttemptHistoryLabel.
  ///
  /// In de, this message translates to:
  /// **'Bisherige Versuche'**
  String get aiJobAttemptHistoryLabel;

  /// No description provided for @aiJobAttemptRow.
  ///
  /// In de, this message translates to:
  /// **'Versuch {attemptNo}: {reason}'**
  String aiJobAttemptRow(Object attemptNo, Object reason);

  /// No description provided for @aiJobStageExtractingText.
  ///
  /// In de, this message translates to:
  /// **'Text wird extrahiert …'**
  String get aiJobStageExtractingText;

  /// No description provided for @aiJobStageExtracting.
  ///
  /// In de, this message translates to:
  /// **'Szenen werden extrahiert …'**
  String get aiJobStageExtracting;

  /// No description provided for @aiJobStageMerging.
  ///
  /// In de, this message translates to:
  /// **'Spielplan wird zusammengeführt …'**
  String get aiJobStageMerging;

  /// No description provided for @aiJobStageStoringPreview.
  ///
  /// In de, this message translates to:
  /// **'Vorschau wird gespeichert …'**
  String get aiJobStageStoringPreview;

  /// No description provided for @aiJobStageUnknown.
  ///
  /// In de, this message translates to:
  /// **'Unbekannte Phase ({name}).'**
  String aiJobStageUnknown(Object name);

  /// No description provided for @aiJobChunkProgress.
  ///
  /// In de, this message translates to:
  /// **'Abschnitt {chunk} von {chunksTotal}'**
  String aiJobChunkProgress(Object chunk, Object chunksTotal);

  /// No description provided for @aiJobEpisodesSeenLabel.
  ///
  /// In de, this message translates to:
  /// **'Gefundene Episoden:'**
  String get aiJobEpisodesSeenLabel;

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

  /// No description provided for @aiPreviewCostumeHeading.
  ///
  /// In de, this message translates to:
  /// **'Kostüme ({count})'**
  String aiPreviewCostumeHeading(Object count);

  /// No description provided for @aiPreviewCostumeFor.
  ///
  /// In de, this message translates to:
  /// **'{character}: {description}'**
  String aiPreviewCostumeFor(Object character, Object description);

  /// No description provided for @aiPreviewCostumeQuote.
  ///
  /// In de, this message translates to:
  /// **'Beleg: {quote}'**
  String aiPreviewCostumeQuote(Object quote);

  /// No description provided for @aiPreviewCostumeRejectedStatus.
  ///
  /// In de, this message translates to:
  /// **'verworfen'**
  String get aiPreviewCostumeRejectedStatus;

  /// No description provided for @aiPreviewCostumeToggleTooltip.
  ///
  /// In de, this message translates to:
  /// **'Dieses Kostüm unabhängig von der Szene übernehmen oder verwerfen'**
  String get aiPreviewCostumeToggleTooltip;

  /// No description provided for @aiApplyOutcomeScript.
  ///
  /// In de, this message translates to:
  /// **'Angewendet: {applied} Szene(n), {characters} Figur(en), {costumes} Kostüm(e).'**
  String aiApplyOutcomeScript(
    Object applied,
    Object characters,
    Object costumes,
  );

  /// No description provided for @aiApplyUnappliedCostume.
  ///
  /// In de, this message translates to:
  /// **'Nicht angewendet: {character} – {description} ({reason})'**
  String aiApplyUnappliedCostume(
    Object character,
    Object description,
    Object reason,
  );

  /// No description provided for @aiApplyUnappliedReasonCharacterNotPlanned.
  ///
  /// In de, this message translates to:
  /// **'Figur fehlt in dieser Zeile'**
  String get aiApplyUnappliedReasonCharacterNotPlanned;

  /// No description provided for @aiApplyUnappliedReasonCharacterUnavailable.
  ///
  /// In de, this message translates to:
  /// **'Figur konnte nicht angelegt werden'**
  String get aiApplyUnappliedReasonCharacterUnavailable;

  /// No description provided for @aiApplyUnappliedReasonCreateRejected.
  ///
  /// In de, this message translates to:
  /// **'Kostüm konnte nicht angelegt werden'**
  String get aiApplyUnappliedReasonCreateRejected;

  /// No description provided for @aiApplyUnappliedReasonNotesRejected.
  ///
  /// In de, this message translates to:
  /// **'Kostüm angelegt, Beschreibung abgelehnt'**
  String get aiApplyUnappliedReasonNotesRejected;

  /// No description provided for @aiApplyUnappliedReasonBindingRejected.
  ///
  /// In de, this message translates to:
  /// **'Kostüm angelegt, Bindung abgelehnt (unzugeordnet)'**
  String get aiApplyUnappliedReasonBindingRejected;

  /// No description provided for @aiApplyUnappliedReasonBeatRejected.
  ///
  /// In de, this message translates to:
  /// **'Kostüm angelegt, Kostümwechsel in der Szene abgelehnt'**
  String get aiApplyUnappliedReasonBeatRejected;

  /// No description provided for @aiConfigStoredPromptNote.
  ///
  /// In de, this message translates to:
  /// **'Gespeicherter Prompt aktiv – folgt nicht den Deployment-Voreinstellungen.'**
  String get aiConfigStoredPromptNote;

  /// No description provided for @aiConfigResetPrompt.
  ///
  /// In de, this message translates to:
  /// **'Auf Voreinstellung zurücksetzen'**
  String get aiConfigResetPrompt;

  /// No description provided for @aiConfigDefaultPromptNote.
  ///
  /// In de, this message translates to:
  /// **'Kein gespeicherter Prompt – die Deployment-Voreinstellung gilt.'**
  String get aiConfigDefaultPromptNote;

  /// No description provided for @aiModelPriceInOut.
  ///
  /// In de, this message translates to:
  /// **'{input} → {output} / 1M Tokens'**
  String aiModelPriceInOut(Object input, Object output);

  /// No description provided for @aiModelImageUnitRate.
  ///
  /// In de, this message translates to:
  /// **'{price} / Bild'**
  String aiModelImageUnitRate(Object price);

  /// No description provided for @aiModelImageOutputRate.
  ///
  /// In de, this message translates to:
  /// **'{price} / 1M Bild-Tokens'**
  String aiModelImageOutputRate(Object price);

  /// No description provided for @aiModelEnergyRate.
  ///
  /// In de, this message translates to:
  /// **'{price} / kWh'**
  String aiModelEnergyRate(Object price);

  /// No description provided for @aiConfigCostDisplayLabel.
  ///
  /// In de, this message translates to:
  /// **'Bevorzugte Kostenanzeige'**
  String get aiConfigCostDisplayLabel;

  /// No description provided for @aiConfigCostDisplayToken.
  ///
  /// In de, this message translates to:
  /// **'Tokens'**
  String get aiConfigCostDisplayToken;

  /// No description provided for @aiConfigCostDisplayEnergy.
  ///
  /// In de, this message translates to:
  /// **'Energie'**
  String get aiConfigCostDisplayEnergy;

  /// No description provided for @aiJobCostCompact.
  ///
  /// In de, this message translates to:
  /// **'Kosten: {value}'**
  String aiJobCostCompact(Object value);

  /// No description provided for @aiJobCostNotApplicable.
  ///
  /// In de, this message translates to:
  /// **'Kein KI-Modell abgerechnet – nativer CSV-Import ohne LLM.'**
  String get aiJobCostNotApplicable;

  /// No description provided for @aiJobCostTitle.
  ///
  /// In de, this message translates to:
  /// **'Kosten dieses Imports'**
  String get aiJobCostTitle;

  /// No description provided for @aiJobCostModel.
  ///
  /// In de, this message translates to:
  /// **'Modell: {model}'**
  String aiJobCostModel(Object model);

  /// No description provided for @aiJobCostTokensIn.
  ///
  /// In de, this message translates to:
  /// **'Tokens rein: {count}'**
  String aiJobCostTokensIn(Object count);

  /// No description provided for @aiJobCostTokensOut.
  ///
  /// In de, this message translates to:
  /// **'Tokens raus: {count}'**
  String aiJobCostTokensOut(Object count);

  /// No description provided for @aiJobCostCachedTokens.
  ///
  /// In de, this message translates to:
  /// **'davon aus dem Cache: {count}'**
  String aiJobCostCachedTokens(Object count);

  /// No description provided for @aiJobCostTokenTotal.
  ///
  /// In de, this message translates to:
  /// **'Token-Kosten: {price}'**
  String aiJobCostTokenTotal(Object price);

  /// No description provided for @aiJobCostEnergyTotal.
  ///
  /// In de, this message translates to:
  /// **'Energie-Kosten: {price}'**
  String aiJobCostEnergyTotal(Object price);

  /// No description provided for @aiJobCostEnergyConsumption.
  ///
  /// In de, this message translates to:
  /// **'Energieverbrauch: {wh} Wh'**
  String aiJobCostEnergyConsumption(Object wh);

  /// No description provided for @aiJobCostEnergyCapped.
  ///
  /// In de, this message translates to:
  /// **'Energiekosten durch Token-Kosten gedeckelt.'**
  String get aiJobCostEnergyCapped;

  /// No description provided for @aiJobCostRateInput.
  ///
  /// In de, this message translates to:
  /// **'Eingabepreis: {price} / 1M Tokens'**
  String aiJobCostRateInput(Object price);

  /// No description provided for @aiJobCostRateOutput.
  ///
  /// In de, this message translates to:
  /// **'Ausgabepreis: {price} / 1M Tokens'**
  String aiJobCostRateOutput(Object price);

  /// No description provided for @aiJobCostPriceAsOf.
  ///
  /// In de, this message translates to:
  /// **'Preisstand: {date}'**
  String aiJobCostPriceAsOf(Object date);

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

  /// No description provided for @aiApplyErrorApplyBlocked.
  ///
  /// In de, this message translates to:
  /// **'Der Vorschau sind noch ungelöste Prüffragen zugeordnet – bestätige sie unten, um anzuwenden.'**
  String get aiApplyErrorApplyBlocked;

  /// No description provided for @aiApplyErrorMissingMapping.
  ///
  /// In de, this message translates to:
  /// **'Eine Skriptzeile hat keine Prüfentscheidung – lade die Vorschau neu und übernimm erneut.'**
  String get aiApplyErrorMissingMapping;

  /// No description provided for @aiApplyErrorMissingEpisodeGroup.
  ///
  /// In de, this message translates to:
  /// **'Ein Episoden-Ziel passt nicht mehr zur Vorschau – lade die Vorschau neu und übernimm erneut.'**
  String get aiApplyErrorMissingEpisodeGroup;

  /// No description provided for @aiApplyUncertaintiesTitle.
  ///
  /// In de, this message translates to:
  /// **'Offene Prüffragen – zum Übernehmen bestätigen:'**
  String get aiApplyUncertaintiesTitle;

  /// No description provided for @aiApplyAcknowledgeUncertainty.
  ///
  /// In de, this message translates to:
  /// **'Als geklärt bestätigen und wie extrahiert übernehmen'**
  String get aiApplyAcknowledgeUncertainty;

  /// No description provided for @aiApplyAssignExistingInstead.
  ///
  /// In de, this message translates to:
  /// **'Stattdessen die vorhandene Episode zuordnen'**
  String get aiApplyAssignExistingInstead;

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

  /// No description provided for @aiApplyUngroupedHeading.
  ///
  /// In de, this message translates to:
  /// **'Ohne Episoden-Marker – Ziel: Episode {episode}'**
  String aiApplyUngroupedHeading(Object episode);

  /// No description provided for @aiApplyUngroupedHeadingNoTarget.
  ///
  /// In de, this message translates to:
  /// **'Ohne Episoden-Marker – Ziel unten wählen'**
  String get aiApplyUngroupedHeadingNoTarget;

  /// No description provided for @aiApplyGroupTargetChange.
  ///
  /// In de, this message translates to:
  /// **'Ziel ändern'**
  String get aiApplyGroupTargetChange;

  /// No description provided for @aiApplyGroupTargetPickExisting.
  ///
  /// In de, this message translates to:
  /// **'Vorhandene Episode wählen…'**
  String get aiApplyGroupTargetPickExisting;

  /// No description provided for @aiApplyGroupTargetEditCreate.
  ///
  /// In de, this message translates to:
  /// **'Neue Episode anlegen…'**
  String get aiApplyGroupTargetEditCreate;

  /// No description provided for @aiApplyGroupTargetCreate.
  ///
  /// In de, this message translates to:
  /// **'Neu anlegen: {label}'**
  String aiApplyGroupTargetCreate(Object label);

  /// No description provided for @aiApplyGroupTargetCreateNoNumber.
  ///
  /// In de, this message translates to:
  /// **'Neu anlegen – Episoden-Nummer fehlt noch'**
  String get aiApplyGroupTargetCreateNoNumber;

  /// No description provided for @aiApplyGroupTargetExisting.
  ///
  /// In de, this message translates to:
  /// **'Vorhandene Episode: {label}'**
  String aiApplyGroupTargetExisting(Object label);

  /// No description provided for @aiApplyGroupTargetSummary.
  ///
  /// In de, this message translates to:
  /// **'{group} → {target}'**
  String aiApplyGroupTargetSummary(Object group, Object target);

  /// No description provided for @aiApplyGroupCreateNumberLabel.
  ///
  /// In de, this message translates to:
  /// **'Episoden-Nummer'**
  String get aiApplyGroupCreateNumberLabel;

  /// No description provided for @aiApplyGroupCreateNameLabel.
  ///
  /// In de, this message translates to:
  /// **'Episoden-Titel (optional)'**
  String get aiApplyGroupCreateNameLabel;

  /// No description provided for @aiApplyGroupNumberInvalid.
  ///
  /// In de, this message translates to:
  /// **'Bitte eine ganze Zahl eingeben.'**
  String get aiApplyGroupNumberInvalid;

  /// No description provided for @aiApplyErrorEpisodeNumberTaken.
  ///
  /// In de, this message translates to:
  /// **'Diese Episoden-Nummer ist in der Staffel bereits vergeben.'**
  String get aiApplyErrorEpisodeNumberTaken;

  /// No description provided for @aiApplyErrorEpisodeNumberOtherBlock.
  ///
  /// In de, this message translates to:
  /// **'Diese Episodennummer ist bereits einem anderen Block zugeordnet. Wechsle den Block und lade das Dokument dort erneut hoch.'**
  String get aiApplyErrorEpisodeNumberOtherBlock;

  /// No description provided for @aiApplyErrorEpisodeNumberOtherBlockIn.
  ///
  /// In de, this message translates to:
  /// **'Diese Episodennummer gehört bereits zu {seasonLabel}, {blockLabel}. Wechsle in diesen Block und lade das Dokument dort erneut hoch.'**
  String aiApplyErrorEpisodeNumberOtherBlockIn(
    Object seasonLabel,
    Object blockLabel,
  );

  /// No description provided for @aiApplySwitchScopeRecovery.
  ///
  /// In de, this message translates to:
  /// **'Zum Herkunftsblock der Episode wechseln und dort erneut hochladen'**
  String get aiApplySwitchScopeRecovery;

  /// No description provided for @aiApplySwitchScopeFailed.
  ///
  /// In de, this message translates to:
  /// **'Der Wechsel zum Herkunftsblock ist fehlgeschlagen ({code}). Bitte prüfe deine Verbindung und versuche es erneut.'**
  String aiApplySwitchScopeFailed(Object code);

  /// No description provided for @aiApplyErrorEpisodeCreateFailed.
  ///
  /// In de, this message translates to:
  /// **'Die Episode konnte nicht automatisch erstellt werden. Bitte prüfe deine Verbindung und versuche es über „Ziel ändern“ erneut.'**
  String get aiApplyErrorEpisodeCreateFailed;

  /// No description provided for @aiApplyOutcome.
  ///
  /// In de, this message translates to:
  /// **'Angewendet: {applied} Entwurf(e): {days} Drehtag(e) erstellt, {shoots} Szenen-Dreh(e) geplant.'**
  String aiApplyOutcome(Object applied, Object days, Object shoots);

  /// No description provided for @aiApplyBackToImports.
  ///
  /// In de, this message translates to:
  /// **'Zurück zu den Importen'**
  String get aiApplyBackToImports;

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
  /// **'Episoden konnten nicht geladen werden ({error}).'**
  String aiEpisodePickerError(Object error);

  /// No description provided for @aiEpisodePickerEmpty.
  ///
  /// In de, this message translates to:
  /// **'Keine Episoden in diesem Block – lege zuerst eine Episode im Drehplan an.'**
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
  /// **'Drehpläne: Wähle eine CSV- oder PDF-Datei.'**
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
  /// **'Wähle zuerst eine Datei.'**
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
  /// **'Kamera-Zugriff ist deaktiviert. Aktiviere den Kamera-Zugriff in den Einstellungen, um Kleidungsstücke zu dokumentieren.'**
  String get captureDeniedCamera;

  /// No description provided for @captureDeniedGallery.
  ///
  /// In de, this message translates to:
  /// **'Foto-Zugriff ist deaktiviert. Aktiviere den Foto-Zugriff in den Einstellungen, um Kleidungsstücke zu dokumentieren.'**
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

  /// No description provided for @pieceDetailTitle.
  ///
  /// In de, this message translates to:
  /// **'Kleidungsstück'**
  String get pieceDetailTitle;

  /// No description provided for @pieceDetailTextRequired.
  ///
  /// In de, this message translates to:
  /// **'Text ist erforderlich'**
  String get pieceDetailTextRequired;

  /// No description provided for @pieceDetailTextRequiredHint.
  ///
  /// In de, this message translates to:
  /// **'Pflichtfeld – markiert mit *'**
  String get pieceDetailTextRequiredHint;

  /// No description provided for @pieceDetailSubjectOptional.
  ///
  /// In de, this message translates to:
  /// **'optional'**
  String get pieceDetailSubjectOptional;

  /// No description provided for @pieceDetailEditDetail.
  ///
  /// In de, this message translates to:
  /// **'Detail bearbeiten'**
  String get pieceDetailEditDetail;

  /// No description provided for @pieceDetailDeleteTitle.
  ///
  /// In de, this message translates to:
  /// **'Detail löschen?'**
  String get pieceDetailDeleteTitle;

  /// No description provided for @pieceDetailDeleteMessage.
  ///
  /// In de, this message translates to:
  /// **'„{detail}“ wird entfernt. Das kann nicht rückgängig gemacht werden.'**
  String pieceDetailDeleteMessage(Object detail);

  /// No description provided for @pieceDetailNotes.
  ///
  /// In de, this message translates to:
  /// **'Notizen'**
  String get pieceDetailNotes;

  /// No description provided for @pieceDetailNotesHint.
  ///
  /// In de, this message translates to:
  /// **'Anpassungsnotizen …'**
  String get pieceDetailNotesHint;

  /// No description provided for @pieceDetailSaveNotes.
  ///
  /// In de, this message translates to:
  /// **'Notizen speichern'**
  String get pieceDetailSaveNotes;

  /// No description provided for @pieceDetailDetails.
  ///
  /// In de, this message translates to:
  /// **'Details'**
  String get pieceDetailDetails;

  /// No description provided for @pieceDetailNoDetails.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Details – füge unten das erste hinzu.'**
  String get pieceDetailNoDetails;

  /// No description provided for @pieceDetailAddDetail.
  ///
  /// In de, this message translates to:
  /// **'Detail hinzufügen'**
  String get pieceDetailAddDetail;

  /// No description provided for @pieceDetailSubject.
  ///
  /// In de, this message translates to:
  /// **'Betreff'**
  String get pieceDetailSubject;

  /// No description provided for @pieceDetailText.
  ///
  /// In de, this message translates to:
  /// **'Text'**
  String get pieceDetailText;

  /// No description provided for @pieceDetailCategory.
  ///
  /// In de, this message translates to:
  /// **'Kategorie'**
  String get pieceDetailCategory;

  /// No description provided for @pieceDetailPhotos.
  ///
  /// In de, this message translates to:
  /// **'Fotos'**
  String get pieceDetailPhotos;

  /// No description provided for @pieceDetailCamera.
  ///
  /// In de, this message translates to:
  /// **'Kamera'**
  String get pieceDetailCamera;

  /// No description provided for @pieceDetailGallery.
  ///
  /// In de, this message translates to:
  /// **'Galerie'**
  String get pieceDetailGallery;

  /// No description provided for @pieceDetailPromptTitle.
  ///
  /// In de, this message translates to:
  /// **'Kleidungsstücke mit Fotos dokumentieren?'**
  String get pieceDetailPromptTitle;

  /// No description provided for @pieceDetailPromptBody.
  ///
  /// In de, this message translates to:
  /// **'Fotos helfen dem Garderobenteam, Kleidungsstücke zu dokumentieren und Kontinuität zu verfolgen. Als Nächstes fragt das System nach dem Kamera-Zugriff.'**
  String get pieceDetailPromptBody;

  /// No description provided for @pieceDetailRepertoire.
  ///
  /// In de, this message translates to:
  /// **'Repertoire'**
  String get pieceDetailRepertoire;

  /// No description provided for @pieceDetailRepertoireEmpty.
  ///
  /// In de, this message translates to:
  /// **'In keiner weiteren Staffel gelistet'**
  String get pieceDetailRepertoireEmpty;

  /// No description provided for @pieceDetailRepertoireAdd.
  ///
  /// In de, this message translates to:
  /// **'Zu Staffel hinzufügen'**
  String get pieceDetailRepertoireAdd;

  /// No description provided for @pieceDetailRepertoireAddTooltip.
  ///
  /// In de, this message translates to:
  /// **'Das Kleidungsstück zum Repertoire einer anderen Staffel hinzufügen'**
  String get pieceDetailRepertoireAddTooltip;

  /// No description provided for @pieceDetailRepertoireRemoveTooltip.
  ///
  /// In de, this message translates to:
  /// **'Aus Staffel entfernen'**
  String get pieceDetailRepertoireRemoveTooltip;

  /// No description provided for @pieceDetailRepertoireRemoveTitle.
  ///
  /// In de, this message translates to:
  /// **'Aus Staffel entfernen?'**
  String get pieceDetailRepertoireRemoveTitle;

  /// No description provided for @pieceDetailRepertoireRemoveMessage.
  ///
  /// In de, this message translates to:
  /// **'Das Kleidungsstück verschwindet aus dem Garderoben-Bestand dieser Staffel. Details und Fotos bleiben am Kleidungsstück.'**
  String get pieceDetailRepertoireRemoveMessage;

  /// No description provided for @pieceDetailRepertoirePick.
  ///
  /// In de, this message translates to:
  /// **'Staffel wählen'**
  String get pieceDetailRepertoirePick;

  /// No description provided for @pieceDetailRepertoireSaved.
  ///
  /// In de, this message translates to:
  /// **'Staffel zum Repertoire hinzugefügt.'**
  String get pieceDetailRepertoireSaved;

  /// No description provided for @pieceDetailRepertoireRemoved.
  ///
  /// In de, this message translates to:
  /// **'Das Kleidungsstück wurde aus dem Staffel-Repertoire entfernt.'**
  String get pieceDetailRepertoireRemoved;

  /// No description provided for @pieceErrorSeasonArchived.
  ///
  /// In de, this message translates to:
  /// **'Diese Staffel ist archiviert – ihr Repertoire kann nicht mehr geändert werden.'**
  String get pieceErrorSeasonArchived;

  /// No description provided for @pieceErrorSeasonNotFound.
  ///
  /// In de, this message translates to:
  /// **'Diese Staffel existiert nicht mehr – die Liste wurde aktualisiert.'**
  String get pieceErrorSeasonNotFound;

  /// No description provided for @pieceDetailNotNow.
  ///
  /// In de, this message translates to:
  /// **'Später'**
  String get pieceDetailNotNow;

  /// No description provided for @pieceDetailContinue.
  ///
  /// In de, this message translates to:
  /// **'Weiter'**
  String get pieceDetailContinue;

  /// No description provided for @pieceDetailOpenSettings.
  ///
  /// In de, this message translates to:
  /// **'Einstellungen öffnen'**
  String get pieceDetailOpenSettings;

  /// No description provided for @pieceDetailDeletePhotoMessage.
  ///
  /// In de, this message translates to:
  /// **'Das Foto und seine Varianten werden entfernt. Das kann nicht rückgängig gemacht werden.'**
  String get pieceDetailDeletePhotoMessage;

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

  /// No description provided for @continuityPieceHint.
  ///
  /// In de, this message translates to:
  /// **'Wähle das Kleidungsstück, zu dem das Foto gehört – es wird am Kleidungsstück gespeichert und mit diesem Shot verknüpft.'**
  String get continuityPieceHint;

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

  /// No description provided for @castNoSeason.
  ///
  /// In de, this message translates to:
  /// **'Wähle eine Staffel, um Kleidungsstücke und Figuren zu sehen.'**
  String get castNoSeason;

  /// No description provided for @castPickSeason.
  ///
  /// In de, this message translates to:
  /// **'Season wählen'**
  String get castPickSeason;

  /// No description provided for @castCategoriesTooltip.
  ///
  /// In de, this message translates to:
  /// **'Kostüm-Kategorien'**
  String get castCategoriesTooltip;

  /// No description provided for @castSegmentCharacters.
  ///
  /// In de, this message translates to:
  /// **'Figuren'**
  String get castSegmentCharacters;

  /// No description provided for @castSegmentOutfits.
  ///
  /// In de, this message translates to:
  /// **'Looks'**
  String get castSegmentOutfits;

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
  /// **'Foto von Kleidungsstück {pieceId}'**
  String photoTileSemantics(Object pieceId);

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
  /// **'Das Foto bleibt am Kleidungsstück – nur die Verknüpfung zu diesem Shoot wird entfernt.'**
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

  /// No description provided for @sceneShootsReportsLabel.
  ///
  /// In de, this message translates to:
  /// **'Berichte'**
  String get sceneShootsReportsLabel;

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

  /// No description provided for @sceneDetailNoShootingDaysReportHint.
  ///
  /// In de, this message translates to:
  /// **'Plane die Szene auf einem Drehtag – der Soll-/Ist-Bericht (geplant vs. tatsächlich) öffnet sich dann über das Day-Board dieses Tages.'**
  String get sceneDetailNoShootingDaysReportHint;

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

  /// No description provided for @sceneDetailNoDayCandidatesHint.
  ///
  /// In de, this message translates to:
  /// **'Noch kein Drehtag in dieser Episode — lege zuerst einen an oder importiere die Dispo.'**
  String get sceneDetailNoDayCandidatesHint;

  /// No description provided for @sceneDetailAllDaysScheduled.
  ///
  /// In de, this message translates to:
  /// **'Alle Drehtage dieser Episode sind bereits geplant oder archiviert.'**
  String get sceneDetailAllDaysScheduled;

  /// No description provided for @sceneDetailCreateFirstDay.
  ///
  /// In de, this message translates to:
  /// **'Drehtag anlegen'**
  String get sceneDetailCreateFirstDay;

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

  /// No description provided for @sceneDetailOutfitsTitle.
  ///
  /// In de, this message translates to:
  /// **'Looks ({count})'**
  String sceneDetailOutfitsTitle(Object count);

  /// No description provided for @sceneDetailAssignOutfit.
  ///
  /// In de, this message translates to:
  /// **'Look zuweisen'**
  String get sceneDetailAssignOutfit;

  /// No description provided for @sceneDetailAddChange.
  ///
  /// In de, this message translates to:
  /// **'+ Lookwechsel'**
  String get sceneDetailAddChange;

  /// No description provided for @sceneDetailRemoveOutfitTooltip.
  ///
  /// In de, this message translates to:
  /// **'Look entfernen'**
  String get sceneDetailRemoveOutfitTooltip;

  /// No description provided for @sceneDetailRemoveOutfitTitle.
  ///
  /// In de, this message translates to:
  /// **'Look entfernen?'**
  String get sceneDetailRemoveOutfitTitle;

  /// No description provided for @sceneDetailRemoveOutfitMessage.
  ///
  /// In de, this message translates to:
  /// **'„{name}“ wird aus dieser Szene entfernt.'**
  String sceneDetailRemoveOutfitMessage(Object name);

  /// No description provided for @sceneDetailNoOutfitInScene.
  ///
  /// In de, this message translates to:
  /// **'Kein Look in dieser Szene.'**
  String get sceneDetailNoOutfitInScene;

  /// No description provided for @sceneDetailPickOutfitTitle.
  ///
  /// In de, this message translates to:
  /// **'Look wählen'**
  String get sceneDetailPickOutfitTitle;

  /// No description provided for @sceneDetailOutfitCueHint.
  ///
  /// In de, this message translates to:
  /// **'Notiz für die Garderobe (optional)'**
  String get sceneDetailOutfitCueHint;

  /// No description provided for @sceneBeatErrorNotInScene.
  ///
  /// In de, this message translates to:
  /// **'Diese Figur ist nicht in der Szene.'**
  String get sceneBeatErrorNotInScene;

  /// No description provided for @sceneBeatErrorNotFound.
  ///
  /// In de, this message translates to:
  /// **'Dieser Lookwechsel existiert nicht (mehr).'**
  String get sceneBeatErrorNotFound;

  /// No description provided for @sceneBeatErrorValidation.
  ///
  /// In de, this message translates to:
  /// **'Dieser Lookwechsel ist ungültig (z. B. identischer Folge-Wechsel).'**
  String get sceneBeatErrorValidation;

  /// No description provided for @sceneBeatErrorNetwork.
  ///
  /// In de, this message translates to:
  /// **'Netzwerkproblem – die Änderung wurde nicht gespeichert. Versuch es erneut.'**
  String get sceneBeatErrorNetwork;

  /// No description provided for @sceneBeatErrorGeneric.
  ///
  /// In de, this message translates to:
  /// **'Der Lookwechsel konnte nicht gespeichert werden ({code}).'**
  String sceneBeatErrorGeneric(Object code);

  /// No description provided for @sceneBeatOverlaySyncing.
  ///
  /// In de, this message translates to:
  /// **'Lookwechsel wird gespeichert – die Liste wird noch aktualisiert.'**
  String get sceneBeatOverlaySyncing;

  /// No description provided for @sceneBeatOverlayStale.
  ///
  /// In de, this message translates to:
  /// **'Lookwechsel konnte noch nicht bestätigt werden – ziehe nach, um zu aktualisieren.'**
  String get sceneBeatOverlayStale;

  /// No description provided for @assignCharacterSheetTitle.
  ///
  /// In de, this message translates to:
  /// **'Figur zuweisen'**
  String get assignCharacterSheetTitle;

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

  /// No description provided for @episodeNumberName.
  ///
  /// In de, this message translates to:
  /// **'{number} · {name}'**
  String episodeNumberName(Object name, Object number);

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

  /// No description provided for @commonAiImportJobs.
  ///
  /// In de, this message translates to:
  /// **'KI-Import-Aufträge'**
  String get commonAiImportJobs;

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

  /// No description provided for @navCast.
  ///
  /// In de, this message translates to:
  /// **'Cast'**
  String get navCast;

  /// No description provided for @navScript.
  ///
  /// In de, this message translates to:
  /// **'Script'**
  String get navScript;

  /// No description provided for @viewTitleScript.
  ///
  /// In de, this message translates to:
  /// **'Szenen aus dem Skript'**
  String get viewTitleScript;

  /// No description provided for @navSchedule.
  ///
  /// In de, this message translates to:
  /// **'Schedule/Dispo'**
  String get navSchedule;

  /// No description provided for @navWardrobe.
  ///
  /// In de, this message translates to:
  /// **'Garderobe'**
  String get navWardrobe;

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

  /// No description provided for @shellPlusFabLabel.
  ///
  /// In de, this message translates to:
  /// **'Erstellen'**
  String get shellPlusFabLabel;

  /// No description provided for @offlinePillLabel.
  ///
  /// In de, this message translates to:
  /// **'Offline – Daten können veraltet sein'**
  String get offlinePillLabel;

  /// No description provided for @healthPillHealthy.
  ///
  /// In de, this message translates to:
  /// **'Backend bereit'**
  String get healthPillHealthy;

  /// No description provided for @healthPillDegraded.
  ///
  /// In de, this message translates to:
  /// **'Backend eingeschränkt'**
  String get healthPillDegraded;

  /// No description provided for @healthPillUnhealthy.
  ///
  /// In de, this message translates to:
  /// **'Backend gestört'**
  String get healthPillUnhealthy;

  /// No description provided for @healthPillOffline.
  ///
  /// In de, this message translates to:
  /// **'Backend nicht erreichbar'**
  String get healthPillOffline;

  /// No description provided for @healthPillOpenHint.
  ///
  /// In de, this message translates to:
  /// **'Details zum Backend-Status öffnen'**
  String get healthPillOpenHint;

  /// No description provided for @healthDetailTitle.
  ///
  /// In de, this message translates to:
  /// **'Backend-Status'**
  String get healthDetailTitle;

  /// No description provided for @healthDetailDependencies.
  ///
  /// In de, this message translates to:
  /// **'Abhängigkeiten'**
  String get healthDetailDependencies;

  /// No description provided for @healthDetailNoDependencies.
  ///
  /// In de, this message translates to:
  /// **'Der Server meldet keine Details zu den Abhängigkeiten.'**
  String get healthDetailNoDependencies;

  /// No description provided for @healthDetailOfflineBody.
  ///
  /// In de, this message translates to:
  /// **'Der Server ist nicht erreichbar. Sobald die Verbindung wieder steht, wird der Status erneut abgefragt.'**
  String get healthDetailOfflineBody;

  /// No description provided for @healthDetailPending.
  ///
  /// In de, this message translates to:
  /// **'Status wird abgefragt …'**
  String get healthDetailPending;

  /// No description provided for @healthCheckDatabase.
  ///
  /// In de, this message translates to:
  /// **'Datenbank'**
  String get healthCheckDatabase;

  /// No description provided for @healthCheckEventStore.
  ///
  /// In de, this message translates to:
  /// **'Ereignisspeicher'**
  String get healthCheckEventStore;

  /// No description provided for @healthCheckSecrets.
  ///
  /// In de, this message translates to:
  /// **'Geheimnisverwaltung'**
  String get healthCheckSecrets;

  /// No description provided for @healthCheckAiStorage.
  ///
  /// In de, this message translates to:
  /// **'KI-Dateispeicher'**
  String get healthCheckAiStorage;

  /// No description provided for @healthCheckOther.
  ///
  /// In de, this message translates to:
  /// **'Weitere Abhängigkeit'**
  String get healthCheckOther;

  /// No description provided for @healthCheckStatusHealthy.
  ///
  /// In de, this message translates to:
  /// **'bereit'**
  String get healthCheckStatusHealthy;

  /// No description provided for @healthCheckStatusDegraded.
  ///
  /// In de, this message translates to:
  /// **'eingeschränkt'**
  String get healthCheckStatusDegraded;

  /// No description provided for @healthCheckStatusUnhealthy.
  ///
  /// In de, this message translates to:
  /// **'gestört'**
  String get healthCheckStatusUnhealthy;

  /// No description provided for @quickCreateTitle.
  ///
  /// In de, this message translates to:
  /// **'Was möchtest du erstellen?'**
  String get quickCreateTitle;

  /// No description provided for @quickCreateAiImportSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Spielplan oder Skript per KI importieren'**
  String get quickCreateAiImportSubtitle;

  /// No description provided for @quickCreateWizardSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Season, Blöcke und Episoden geführt anlegen'**
  String get quickCreateWizardSubtitle;

  /// No description provided for @quickCreateSceneTitle.
  ///
  /// In de, this message translates to:
  /// **'Neue Szene'**
  String get quickCreateSceneTitle;

  /// No description provided for @quickCreateSceneSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Szene in der aktiven Episode anlegen'**
  String get quickCreateSceneSubtitle;

  /// No description provided for @quickCreateShootingDayTitle.
  ///
  /// In de, this message translates to:
  /// **'Neuer Drehtag'**
  String get quickCreateShootingDayTitle;

  /// No description provided for @quickCreateShootingDaySubtitle.
  ///
  /// In de, this message translates to:
  /// **'Drehtag in der aktiven Episode planen'**
  String get quickCreateShootingDaySubtitle;

  /// No description provided for @locationStripSemantics.
  ///
  /// In de, this message translates to:
  /// **'Position: {path}'**
  String locationStripSemantics(Object path);

  /// No description provided for @scopeChipBlock.
  ///
  /// In de, this message translates to:
  /// **'Filter: {block}'**
  String scopeChipBlock(Object block);

  /// No description provided for @scopeChipSeason.
  ///
  /// In de, this message translates to:
  /// **'Season: {season}'**
  String scopeChipSeason(Object season);

  /// No description provided for @scopeChipSeasonTooltip.
  ///
  /// In de, this message translates to:
  /// **'Aktive Season wählen'**
  String get scopeChipSeasonTooltip;

  /// No description provided for @scopeChipSeasonPickTitle.
  ///
  /// In de, this message translates to:
  /// **'Season wählen'**
  String get scopeChipSeasonPickTitle;

  /// No description provided for @scopeChipSeasonUnset.
  ///
  /// In de, this message translates to:
  /// **'Season wählen'**
  String get scopeChipSeasonUnset;

  /// No description provided for @seasonScopeManageSeasons.
  ///
  /// In de, this message translates to:
  /// **'Seasons verwalten'**
  String get seasonScopeManageSeasons;

  /// No description provided for @seasonScopeManageProduction.
  ///
  /// In de, this message translates to:
  /// **'Produktion verwalten'**
  String get seasonScopeManageProduction;

  /// No description provided for @seasonScopeEmpty.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Seasons vorhanden.'**
  String get seasonScopeEmpty;

  /// No description provided for @scopeChipUnknownBlock.
  ///
  /// In de, this message translates to:
  /// **'Filter: Block unbekannt'**
  String get scopeChipUnknownBlock;

  /// No description provided for @scopeChipForeignSeason.
  ///
  /// In de, this message translates to:
  /// **'Filter gilt hier nicht – andere Season'**
  String get scopeChipForeignSeason;

  /// No description provided for @scopeChipTooltip.
  ///
  /// In de, this message translates to:
  /// **'Aktiven Block-Filter ändern'**
  String get scopeChipTooltip;

  /// No description provided for @scopeChipPickTitle.
  ///
  /// In de, this message translates to:
  /// **'Block-Filter wählen'**
  String get scopeChipPickTitle;

  /// No description provided for @scopeChipBlockUnset.
  ///
  /// In de, this message translates to:
  /// **'Block wählen'**
  String get scopeChipBlockUnset;

  /// No description provided for @scopeChipBlockUnsetTooltip.
  ///
  /// In de, this message translates to:
  /// **'Aktiven Block-Filter wählen'**
  String get scopeChipBlockUnsetTooltip;

  /// No description provided for @episodeChipTooltip.
  ///
  /// In de, this message translates to:
  /// **'Aktive Episode ändern'**
  String get episodeChipTooltip;

  /// No description provided for @episodeChipPickTitle.
  ///
  /// In de, this message translates to:
  /// **'Episode wählen'**
  String get episodeChipPickTitle;

  /// No description provided for @episodeChipEmpty.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Episoden in diesem Block.'**
  String get episodeChipEmpty;

  /// No description provided for @episodeChipUnset.
  ///
  /// In de, this message translates to:
  /// **'Episode wählen'**
  String get episodeChipUnset;

  /// No description provided for @episodeChipUnsetTooltip.
  ///
  /// In de, this message translates to:
  /// **'Aktive Episode wählen'**
  String get episodeChipUnsetTooltip;

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

  /// No description provided for @seasonsCreateSeriesIdMissing.
  ///
  /// In de, this message translates to:
  /// **'Diese App wurde ohne DEFAULT_PROJECT_ID gebaut: Die neue Season kann keiner Serie zugeordnet werden. Baue die App mit --dart-define=DEFAULT_PROJECT_ID=<ID der Standardserie> neu.'**
  String get seasonsCreateSeriesIdMissing;

  /// No description provided for @seasonsSetupCta.
  ///
  /// In de, this message translates to:
  /// **'Season-Setup starten'**
  String get seasonsSetupCta;

  /// No description provided for @seasonsManualCreateCta.
  ///
  /// In de, this message translates to:
  /// **'Manuell'**
  String get seasonsManualCreateCta;

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

  /// No description provided for @seasonsMetaPieces.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Kleidungsstück} other{{count} Kleidungsstücke}}'**
  String seasonsMetaPieces(num count);

  /// No description provided for @productionTitle.
  ///
  /// In de, this message translates to:
  /// **'Produktion'**
  String get productionTitle;

  /// No description provided for @productionBlocksSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Blöcke und Episoden der aktiven Season'**
  String get productionBlocksSubtitle;

  /// No description provided for @productionNoActiveSeason.
  ///
  /// In de, this message translates to:
  /// **'Wähle zuerst eine Season.'**
  String get productionNoActiveSeason;

  /// No description provided for @planningImportSubtitle.
  ///
  /// In de, this message translates to:
  /// **'KI-Assistent: Spielplan importieren'**
  String get planningImportSubtitle;

  /// No description provided for @planningActiveJobRow.
  ///
  /// In de, this message translates to:
  /// **'KI-Import läuft – Status prüfen'**
  String get planningActiveJobRow;

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

  /// No description provided for @infoBackendVersions.
  ///
  /// In de, this message translates to:
  /// **'Backend-Komponenten'**
  String get infoBackendVersions;

  /// No description provided for @infoBackendVersionsSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Vom Backend gemeldete Versionen der Arbeitsbereich-Komponenten.'**
  String get infoBackendVersionsSubtitle;

  /// No description provided for @infoBackendVersionsError.
  ///
  /// In de, this message translates to:
  /// **'Backend-Versionen konnten nicht geladen werden.'**
  String get infoBackendVersionsError;

  /// No description provided for @infoCredits.
  ///
  /// In de, this message translates to:
  /// **'Mitwirkende'**
  String get infoCredits;

  /// No description provided for @infoCreditsSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Die Menschen und KI-Modelle hinter dieser App.'**
  String get infoCreditsSubtitle;

  /// No description provided for @creditsTitle.
  ///
  /// In de, this message translates to:
  /// **'Mitwirkende'**
  String get creditsTitle;

  /// No description provided for @creditsCloudTitle.
  ///
  /// In de, this message translates to:
  /// **'Dank an alle Mitwirkenden'**
  String get creditsCloudTitle;

  /// No description provided for @creditsCloudBody.
  ///
  /// In de, this message translates to:
  /// **'Die KI-Modelle (mit ihrem Anbieter) und die menschlichen Mitwirkenden (mit ihren Rollen), die an diesem Projekt mitgewirkt haben.'**
  String get creditsCloudBody;

  /// No description provided for @creditsError.
  ///
  /// In de, this message translates to:
  /// **'Mitwirkende konnten nicht geladen werden.'**
  String get creditsError;

  /// No description provided for @creditsRoleLabel.
  ///
  /// In de, this message translates to:
  /// **'Rollen'**
  String get creditsRoleLabel;

  /// No description provided for @creditsLlmLabel.
  ///
  /// In de, this message translates to:
  /// **'KI-Co-Autor'**
  String get creditsLlmLabel;

  /// No description provided for @creditsSemanticHuman.
  ///
  /// In de, this message translates to:
  /// **'{name}, {roles}'**
  String creditsSemanticHuman(Object name, Object roles);

  /// No description provided for @creditsSemanticLlm.
  ///
  /// In de, this message translates to:
  /// **'{name}, KI-Co-Autor von {provider}'**
  String creditsSemanticLlm(Object name, Object provider);

  /// No description provided for @creditsShouldersTitle.
  ///
  /// In de, this message translates to:
  /// **'Auf der Schulter von Riesen'**
  String get creditsShouldersTitle;

  /// No description provided for @creditsShouldersBody.
  ///
  /// In de, this message translates to:
  /// **'Diese App baut auf diesen freien Technologien auf.'**
  String get creditsShouldersBody;

  /// No description provided for @creditsRustLabel.
  ///
  /// In de, this message translates to:
  /// **'Rust — die Backend-Sprache'**
  String get creditsRustLabel;

  /// No description provided for @creditsFlutterLabel.
  ///
  /// In de, this message translates to:
  /// **'Flutter — das App-Framework'**
  String get creditsFlutterLabel;

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

  /// No description provided for @aiImportDisclosureTitle.
  ///
  /// In de, this message translates to:
  /// **'KI-Verarbeitung'**
  String get aiImportDisclosureTitle;

  /// No description provided for @aiImportDisclosureBody.
  ///
  /// In de, this message translates to:
  /// **'Die gewählte Datei wird von einem serverseitigen KI-Import verarbeitet. Die Ergebnisse sind KI-generiert und müssen vor dem Anwenden in der Vorschau geprüft werden.'**
  String get aiImportDisclosureBody;

  /// No description provided for @aiNamingLine.
  ///
  /// In de, this message translates to:
  /// **'Derzeit konfiguriert: Anbieter {provider}, Modell {model}.'**
  String aiNamingLine(Object model, Object provider);

  /// No description provided for @aiPreviewAiBanner.
  ///
  /// In de, this message translates to:
  /// **'KI-extrahierter Inhalt – sorgfältig prüfen'**
  String get aiPreviewAiBanner;

  /// No description provided for @aiPreviewAiNote.
  ///
  /// In de, this message translates to:
  /// **'Alle Zeilen sind maschinell extrahierte Entwürfe. Die Vorschau enthält keine maschinell verifizierten Zuverlässigkeitswerte.'**
  String get aiPreviewAiNote;

  /// No description provided for @aiApplyReviewCheckbox.
  ///
  /// In de, this message translates to:
  /// **'Ich habe den KI-extrahierten Inhalt geprüft'**
  String get aiApplyReviewCheckbox;

  /// No description provided for @aiProvenanceBadge.
  ///
  /// In de, this message translates to:
  /// **'KI-extrahiert'**
  String get aiProvenanceBadge;

  /// No description provided for @aiDisclosureTitle.
  ///
  /// In de, this message translates to:
  /// **'Über KI in der App'**
  String get aiDisclosureTitle;

  /// No description provided for @aiDisclosurePurposeTitle.
  ///
  /// In de, this message translates to:
  /// **'Zweck'**
  String get aiDisclosurePurposeTitle;

  /// No description provided for @aiDisclosurePurposeBody.
  ///
  /// In de, this message translates to:
  /// **'Der KI-Import extrahiert Strukturen (Szenen, Drehtage) aus von Dir bereitgestellten Drehplan- und Skript-Dokumenten, damit die Zusammenarbeit schneller beginnt.'**
  String get aiDisclosurePurposeBody;

  /// No description provided for @aiDisclosureFlowTitle.
  ///
  /// In de, this message translates to:
  /// **'Datenfluss'**
  String get aiDisclosureFlowTitle;

  /// No description provided for @aiDisclosureFlowBody.
  ///
  /// In de, this message translates to:
  /// **'Gerät → Backend → konfigurierter KI-Anbieter → Entwürfe → Vorschau → ausdrückliches Anwenden. Die App kommuniziert nie direkt mit dem KI-Anbieter.'**
  String get aiDisclosureFlowBody;

  /// No description provided for @aiDisclosureNamingTitle.
  ///
  /// In de, this message translates to:
  /// **'Anbieter und Modelle'**
  String get aiDisclosureNamingTitle;

  /// No description provided for @aiDisclosureNamingBodyConfigured.
  ///
  /// In de, this message translates to:
  /// **'Konfiguriert: Anbieter {provider}, Assistent-Modell {model}.'**
  String aiDisclosureNamingBodyConfigured(Object model, Object provider);

  /// No description provided for @aiDisclosureNamingBodyUnconfigured.
  ///
  /// In de, this message translates to:
  /// **'Für dieses Konto ist keine KI-Konfiguration eingerichtet.'**
  String get aiDisclosureNamingBodyUnconfigured;

  /// No description provided for @aiDisclosureNamingBodyLoading.
  ///
  /// In de, this message translates to:
  /// **'Anbieter und Modelle werden geladen …'**
  String get aiDisclosureNamingBodyLoading;

  /// No description provided for @aiDisclosureRetentionTitle.
  ///
  /// In de, this message translates to:
  /// **'Aufbewahrung'**
  String get aiDisclosureRetentionTitle;

  /// No description provided for @aiDisclosureRetentionBody.
  ///
  /// In de, this message translates to:
  /// **'Importierte Dokumentdaten werden nach 7 Tagen automatisch gelöscht; danach bleibt nur das ausdrücklich angewendete Ergebnis im Projekt.'**
  String get aiDisclosureRetentionBody;

  /// No description provided for @aiDisclosureActTitle.
  ///
  /// In de, this message translates to:
  /// **'EU-KI-Gesetz'**
  String get aiDisclosureActTitle;

  /// No description provided for @aiDisclosureActBody.
  ///
  /// In de, this message translates to:
  /// **'Dieser Hinweis folgt der KI-Verordnung (EU) 2024/1689, Artikel 4 (KI-Kompetenz) und Artikel 50 (Transparenz): KI-generierte Inhalte werden gekennzeichnet und müssen geprüft werden.'**
  String get aiDisclosureActBody;

  /// No description provided for @aiConfigLiteracyTitle.
  ///
  /// In de, this message translates to:
  /// **'KI-Kompetenz'**
  String get aiConfigLiteracyTitle;

  /// No description provided for @aiConfigLiteracyBody.
  ///
  /// In de, this message translates to:
  /// **'Diese Konfiguration steuert, welchen KI-Anbieter und welche Modelle der serverseitige Import nutzt und welche Extraktions-Prompts gelten. Der konfigurierte Anbieter verarbeitet die von Nutzenden bereitgestellten Dokumente — konfiguriere kuratierte Anbieter und Modelle ehrlich.'**
  String get aiConfigLiteracyBody;

  /// No description provided for @scriptFetchError.
  ///
  /// In de, this message translates to:
  /// **'Das Script konnte nicht geladen werden ({code}).'**
  String scriptFetchError(Object code);

  /// No description provided for @scriptPartialBlocks.
  ///
  /// In de, this message translates to:
  /// **'Teilweise geladen: {count, plural, =1{1 Block} other{{count} Blöcke}} konnten nicht gelesen werden.'**
  String scriptPartialBlocks(num count);

  /// No description provided for @scriptPartialLoad.
  ///
  /// In de, this message translates to:
  /// **'Teilweise geladen: {count, plural, =1{1 Episode} other{{count} Episoden}} konnten nicht gelesen werden.'**
  String scriptPartialLoad(num count);

  /// No description provided for @scriptSceneNumber.
  ///
  /// In de, this message translates to:
  /// **'Szene {number}'**
  String scriptSceneNumber(Object number);

  /// No description provided for @scriptSceneNumberUnknown.
  ///
  /// In de, this message translates to:
  /// **'Szene ohne Nummer'**
  String get scriptSceneNumberUnknown;

  /// No description provided for @scriptEpisodeLabel.
  ///
  /// In de, this message translates to:
  /// **'Episode {episode}'**
  String scriptEpisodeLabel(Object episode);

  /// No description provided for @scriptNoScenes.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Szenen in dieser Season.'**
  String get scriptNoScenes;

  /// No description provided for @scriptRowEpisodeScene.
  ///
  /// In de, this message translates to:
  /// **'{episode}, Szene {number}'**
  String scriptRowEpisodeScene(Object episode, Object number);

  /// No description provided for @scriptRowCharacters.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Figur} other{{count} Figuren}}'**
  String scriptRowCharacters(num count);

  /// No description provided for @scriptRowOutfits.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Look} other{{count} Looks}}'**
  String scriptRowOutfits(num count);

  /// No description provided for @scheduleFetchError.
  ///
  /// In de, this message translates to:
  /// **'Der Dispo konnte nicht geladen werden ({code}).'**
  String scheduleFetchError(Object code);

  /// No description provided for @scheduleNoDays.
  ///
  /// In de, this message translates to:
  /// **'Für diese Season sind noch keine Drehtage geplant.'**
  String get scheduleNoDays;

  /// No description provided for @schedulePartialBlocks.
  ///
  /// In de, this message translates to:
  /// **'Teilweise geladen: {count, plural, =1{1 Block} other{{count} Blöcke}} konnten nicht gelesen werden.'**
  String schedulePartialBlocks(num count);

  /// No description provided for @schedulePartialLoad.
  ///
  /// In de, this message translates to:
  /// **'Teilweise geladen: {count, plural, =1{1 Episode} other{{count} Episoden}} konnten nicht gelesen werden.'**
  String schedulePartialLoad(num count);

  /// No description provided for @scheduleDayLabel.
  ///
  /// In de, this message translates to:
  /// **'Drehtag {date}'**
  String scheduleDayLabel(Object date);

  /// No description provided for @scheduleDayUndated.
  ///
  /// In de, this message translates to:
  /// **'Drehtag ohne Datum'**
  String get scheduleDayUndated;

  /// No description provided for @profileTooltip.
  ///
  /// In de, this message translates to:
  /// **'Menü'**
  String get profileTooltip;

  /// No description provided for @profileTitle.
  ///
  /// In de, this message translates to:
  /// **'Profil'**
  String get profileTitle;

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
  /// **'{label}, Tab {position} von {total}'**
  String seasonTabSemantic(Object label, Object position, Object total);

  /// No description provided for @seasonTabSemanticEn.
  ///
  /// In de, this message translates to:
  /// **'{label}, Tab {position} of {total}'**
  String seasonTabSemanticEn(Object label, Object position, Object total);

  /// No description provided for @settingsGeneral.
  ///
  /// In de, this message translates to:
  /// **'Allgemein'**
  String get settingsGeneral;

  /// No description provided for @settingsEasterEggs.
  ///
  /// In de, this message translates to:
  /// **'Easter-Eggs'**
  String get settingsEasterEggs;

  /// No description provided for @settingsEasterEggsSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Kleine Überraschungen in der App lassen sich ein- und ausschalten.'**
  String get settingsEasterEggsSubtitle;

  /// No description provided for @settingsEasterEggsWriteError.
  ///
  /// In de, this message translates to:
  /// **'Die Einstellung konnte nicht gespeichert werden. Die Änderung gilt nur bis zum Neustart.'**
  String get settingsEasterEggsWriteError;

  /// No description provided for @settingsEasterEggsError.
  ///
  /// In de, this message translates to:
  /// **'Die Einstellung konnte nicht gelesen werden – Standard (eingeschaltet) bleibt aktiv.'**
  String get settingsEasterEggsError;

  /// No description provided for @settingsEasterEggsKarlKleiderbuegel.
  ///
  /// In de, this message translates to:
  /// **'Karl Kleiderbügel'**
  String get settingsEasterEggsKarlKleiderbuegel;

  /// No description provided for @settingsEasterEggsKarlKleiderbuegelSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Der Kleiderbügel-Assistent hilft im KI-Import mit Tipps und Sprüchen.'**
  String get settingsEasterEggsKarlKleiderbuegelSubtitle;

  /// No description provided for @settingsEasterEggsDejavuCat.
  ///
  /// In de, this message translates to:
  /// **'Déjà-vu-Katze'**
  String get settingsEasterEggsDejavuCat;

  /// No description provided for @settingsEasterEggsDejavuCatSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Im Oktober läuft eine schwarze Katze über den Startbildschirm und durch die leere Season-Liste. In der Vorschau hier ist sie jederzeit zu sehen.'**
  String get settingsEasterEggsDejavuCatSubtitle;

  /// No description provided for @settingsEasterEggsPreview.
  ///
  /// In de, this message translates to:
  /// **'Vorschau'**
  String get settingsEasterEggsPreview;

  /// No description provided for @settingsEasterEggsPreviewSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Jedes Ei lässt sich hier in Ruhe ansehen — unabhängig vom Monat.'**
  String get settingsEasterEggsPreviewSubtitle;

  /// No description provided for @settingsEasterEggsEntryTitle.
  ///
  /// In de, this message translates to:
  /// **'Easter-Eggs verwalten'**
  String get settingsEasterEggsEntryTitle;

  /// No description provided for @settingsEasterEggsEntrySubtitle.
  ///
  /// In de, this message translates to:
  /// **'Schalter und Vorschau für jedes Ei.'**
  String get settingsEasterEggsEntrySubtitle;

  /// No description provided for @settingsEasterEggsScreenTitle.
  ///
  /// In de, this message translates to:
  /// **'Easter-Eggs'**
  String get settingsEasterEggsScreenTitle;

  /// No description provided for @settingsAiConfig.
  ///
  /// In de, this message translates to:
  /// **'KI-Konfiguration'**
  String get settingsAiConfig;

  /// No description provided for @settingsAiConfigSubtitle.
  ///
  /// In de, this message translates to:
  /// **'KI-Anbieter und Modelle für den KI-Import verwalten.'**
  String get settingsAiConfigSubtitle;

  /// No description provided for @settingsAi.
  ///
  /// In de, this message translates to:
  /// **'KI'**
  String get settingsAi;

  /// No description provided for @settingsDev.
  ///
  /// In de, this message translates to:
  /// **'Entwicklung'**
  String get settingsDev;

  /// No description provided for @aiImportClippyNoConfig.
  ///
  /// In de, this message translates to:
  /// **'Es sieht so aus, als wolltest du einen Spielplan importieren… Willst du zuerst eine KI-Konfiguration einrichten?'**
  String get aiImportClippyNoConfig;

  /// No description provided for @aiImportClippyRunning.
  ///
  /// In de, this message translates to:
  /// **'Ich bin ganz Ohr!'**
  String get aiImportClippyRunning;

  /// No description provided for @aiImportClippyError.
  ///
  /// In de, this message translates to:
  /// **'Das hat leider nicht geklappt. Aber gemeinsam kriegen wir das hin!'**
  String get aiImportClippyError;

  /// No description provided for @aiImportClippySuccess.
  ///
  /// In de, this message translates to:
  /// **'Klasse! Der Import sitzt wie maßgeschneidert.'**
  String get aiImportClippySuccess;

  /// No description provided for @aiImportClippyQueued.
  ///
  /// In de, this message translates to:
  /// **'Hmm, lass mich kurz überlegen…'**
  String get aiImportClippyQueued;

  /// No description provided for @aiImportClippyIdle1.
  ///
  /// In de, this message translates to:
  /// **'Wusstest du, dass „Klamotten“ umgangssprachlich Kleidung bedeutet? Der Name sitzt also doppelt.'**
  String get aiImportClippyIdle1;

  /// No description provided for @aiImportClippyIdle2.
  ///
  /// In de, this message translates to:
  /// **'Ich bin ein Kleiderbügel mit Ambitionen.'**
  String get aiImportClippyIdle2;

  /// No description provided for @aiImportClippyIdle3.
  ///
  /// In de, this message translates to:
  /// **'Häng dich nicht auf – ich bin ja da.'**
  String get aiImportClippyIdle3;

  /// No description provided for @aiImportClippyIdle4.
  ///
  /// In de, this message translates to:
  /// **'Ein Kleiderbügel kommt selten allein – meistens hängt er mit Freunden rum.'**
  String get aiImportClippyIdle4;

  /// No description provided for @aiImportClippyIdle5.
  ///
  /// In de, this message translates to:
  /// **'Ordnung ist das halbe Leben. Die andere Hälfte ist der passende Bügel.'**
  String get aiImportClippyIdle5;

  /// No description provided for @aiImportClippyDismissTooltip.
  ///
  /// In de, this message translates to:
  /// **'Karl Kleiderbügel ausblenden'**
  String get aiImportClippyDismissTooltip;

  /// No description provided for @seasonsArchivedBadge.
  ///
  /// In de, this message translates to:
  /// **'Archiviert'**
  String get seasonsArchivedBadge;

  /// No description provided for @seasonsArchiveTooltip.
  ///
  /// In de, this message translates to:
  /// **'Staffel-Aktionen'**
  String get seasonsArchiveTooltip;

  /// No description provided for @seasonsArchiveCta.
  ///
  /// In de, this message translates to:
  /// **'Staffel archivieren'**
  String get seasonsArchiveCta;

  /// No description provided for @seasonsArchivedError.
  ///
  /// In de, this message translates to:
  /// **'Die Staffel ist archiviert und kann nicht mehr geändert werden.'**
  String get seasonsArchivedError;

  /// No description provided for @seasonsArchiveForbidden.
  ///
  /// In de, this message translates to:
  /// **'Dafür fehlt dir die aktive Kostüm-Rolle in dieser Staffel.'**
  String get seasonsArchiveForbidden;

  /// No description provided for @omniSearchTitle.
  ///
  /// In de, this message translates to:
  /// **'Suche'**
  String get omniSearchTitle;

  /// No description provided for @omniSearchTooltip.
  ///
  /// In de, this message translates to:
  /// **'Suchen'**
  String get omniSearchTooltip;

  /// No description provided for @omniSearchHint.
  ///
  /// In de, this message translates to:
  /// **'Suchen: Szenen, Rollen, Kleidungsstücke, Drehtage dieser Staffel'**
  String get omniSearchHint;

  /// No description provided for @omniSearchChipScene.
  ///
  /// In de, this message translates to:
  /// **'Szene'**
  String get omniSearchChipScene;

  /// No description provided for @omniSearchChipCharacter.
  ///
  /// In de, this message translates to:
  /// **'Rolle'**
  String get omniSearchChipCharacter;

  /// No description provided for @omniSearchChipPiece.
  ///
  /// In de, this message translates to:
  /// **'Kleidungsstück'**
  String get omniSearchChipPiece;

  /// No description provided for @omniSearchChipShootingDay.
  ///
  /// In de, this message translates to:
  /// **'Drehtag'**
  String get omniSearchChipShootingDay;

  /// No description provided for @omniSearchGroupScenes.
  ///
  /// In de, this message translates to:
  /// **'Szenen'**
  String get omniSearchGroupScenes;

  /// No description provided for @omniSearchGroupCharacters.
  ///
  /// In de, this message translates to:
  /// **'Rollen'**
  String get omniSearchGroupCharacters;

  /// No description provided for @omniSearchGroupPieces.
  ///
  /// In de, this message translates to:
  /// **'Kleidungsstücke'**
  String get omniSearchGroupPieces;

  /// No description provided for @omniSearchGroupShootingDays.
  ///
  /// In de, this message translates to:
  /// **'Drehtage'**
  String get omniSearchGroupShootingDays;

  /// No description provided for @omniSearchInitialEmpty.
  ///
  /// In de, this message translates to:
  /// **'Tippe, um die Szenen, Rollen, Kleidungsstücke und Drehtage dieser Staffel zu durchsuchen.'**
  String get omniSearchInitialEmpty;

  /// No description provided for @omniSearchZeroMatch.
  ///
  /// In de, this message translates to:
  /// **'Keine Treffer für „{query}“ in: {facets}.'**
  String omniSearchZeroMatch(String query, String facets);

  /// No description provided for @omniSearchNotLoaded.
  ///
  /// In de, this message translates to:
  /// **'Noch nicht geladen: {facets}. Öffne die zugehörige Ansicht, um die Daten zu laden.'**
  String omniSearchNotLoaded(String facets);

  /// No description provided for @omniSearchError.
  ///
  /// In de, this message translates to:
  /// **'Die Suche kann den lokalen Cache gerade nicht lesen.'**
  String get omniSearchError;

  /// No description provided for @omniSearchNoSeason.
  ///
  /// In de, this message translates to:
  /// **'Wähle zuerst eine Staffel, um sie zu durchsuchen.'**
  String get omniSearchNoSeason;

  /// No description provided for @omniSearchStaleBanner.
  ///
  /// In de, this message translates to:
  /// **'Diese Ergebnisse basieren auf dem lokalen Cache und können veraltet sein.'**
  String get omniSearchStaleBanner;

  /// No description provided for @omniSearchRefresh.
  ///
  /// In de, this message translates to:
  /// **'Aktualisieren'**
  String get omniSearchRefresh;

  /// No description provided for @fundusTitle.
  ///
  /// In de, this message translates to:
  /// **'Fundus'**
  String get fundusTitle;

  /// No description provided for @fundusTooltip.
  ///
  /// In de, this message translates to:
  /// **'Fundus durchsuchen'**
  String get fundusTooltip;

  /// No description provided for @fundusHint.
  ///
  /// In de, this message translates to:
  /// **'Fundus durchsuchen: Kleidungsstücke über alle Staffeln'**
  String get fundusHint;

  /// No description provided for @fundusEmpty.
  ///
  /// In de, this message translates to:
  /// **'Der Fundus dieses Projekts ist leer.'**
  String get fundusEmpty;

  /// No description provided for @fundusNotLoaded.
  ///
  /// In de, this message translates to:
  /// **'Der Fundus wird noch geladen.'**
  String get fundusNotLoaded;

  /// No description provided for @fundusZeroMatch.
  ///
  /// In de, this message translates to:
  /// **'Keine Treffer für „{query}“ im Fundus.'**
  String fundusZeroMatch(String query);

  /// No description provided for @fundusError.
  ///
  /// In de, this message translates to:
  /// **'Der Fundus kann den lokalen Cache gerade nicht lesen.'**
  String get fundusError;

  /// No description provided for @fundusNoSeason.
  ///
  /// In de, this message translates to:
  /// **'Wähle zuerst eine Staffel, um den Fundus zu durchsuchen.'**
  String get fundusNoSeason;

  /// No description provided for @fundusStaleBanner.
  ///
  /// In de, this message translates to:
  /// **'Diese Ergebnisse basieren auf dem lokalen Cache und können veraltet sein.'**
  String get fundusStaleBanner;

  /// No description provided for @fundusRepertoireSeasons.
  ///
  /// In de, this message translates to:
  /// **'Staffeln: {seasons}'**
  String fundusRepertoireSeasons(String seasons);

  /// No description provided for @aiPreviewShootingDay.
  ///
  /// In de, this message translates to:
  /// **'Drehtag: {day}'**
  String aiPreviewShootingDay(Object day);

  /// No description provided for @aiApplyShootingDaysHeading.
  ///
  /// In de, this message translates to:
  /// **'Drehtage aus dem Skript – anlegen?'**
  String get aiApplyShootingDaysHeading;

  /// No description provided for @aiApplyDayRejectedStatus.
  ///
  /// In de, this message translates to:
  /// **'Nicht anlegen – Szenen dieses Tages bleiben ohne Drehtag.'**
  String get aiApplyDayRejectedStatus;

  /// No description provided for @aiApplyDayCreateSummary.
  ///
  /// In de, this message translates to:
  /// **'Drehtag „{day}“ wird angelegt, die Szenen des Tages werden darauf geplant.'**
  String aiApplyDayCreateSummary(Object day);

  /// No description provided for @aiApplyDaySkipSummary.
  ///
  /// In de, this message translates to:
  /// **'Drehtag „{day}“ wird nicht angelegt – seine Szenen bleiben ohne Drehtag.'**
  String aiApplyDaySkipSummary(Object day);

  /// No description provided for @aiApplyErrorMissingShootingDayGroup.
  ///
  /// In de, this message translates to:
  /// **'Eine Drehtag-Gruppe passt nicht mehr zur Vorschau – lade die Vorschau neu und übernimm erneut.'**
  String get aiApplyErrorMissingShootingDayGroup;

  /// No description provided for @aiApplySkippedDayGroups.
  ///
  /// In de, this message translates to:
  /// **'{count} abgelehnte Drehtag-Gruppe(n) – ihre Szenen wurden ohne Drehtag angelegt.'**
  String aiApplySkippedDayGroups(Object count);

  /// No description provided for @shootingDayLinkInto.
  ///
  /// In de, this message translates to:
  /// **'In echten Drehtag überführen'**
  String get shootingDayLinkInto;

  /// No description provided for @shootingDayLinkIntoTitle.
  ///
  /// In de, this message translates to:
  /// **'In echten Drehtag überführen'**
  String get shootingDayLinkIntoTitle;

  /// No description provided for @shootingDayLinkIntoPick.
  ///
  /// In de, this message translates to:
  /// **'Ziel-Drehtag wählen – Szenen und Soll-Einträge werden überführt, der KI-Drehtag wird archiviert.'**
  String get shootingDayLinkIntoPick;

  /// No description provided for @shootingDayLinkIntoNoTarget.
  ///
  /// In de, this message translates to:
  /// **'Kein passender Drehtag vorhanden. Lege zuerst einen echten Drehtag an.'**
  String get shootingDayLinkIntoNoTarget;

  /// No description provided for @shootingDayLinkedInto.
  ///
  /// In de, this message translates to:
  /// **'{scenes} Szenen überführt, {shoots} Soll-Einträge geplant.'**
  String shootingDayLinkedInto(Object scenes, Object shoots);

  /// No description provided for @shootingDayErrorTargetWrapped.
  ///
  /// In de, this message translates to:
  /// **'Der Ziel-Drehtag ist bereits abgeschlossen – Überführen nicht möglich.'**
  String get shootingDayErrorTargetWrapped;

  /// No description provided for @shootingDayErrorEpisodeMismatch.
  ///
  /// In de, this message translates to:
  /// **'Die Drehtage gehören zu verschiedenen Episoden.'**
  String get shootingDayErrorEpisodeMismatch;

  /// No description provided for @aiConfigDecisionSectionTitle.
  ///
  /// In de, this message translates to:
  /// **'Decision-Modell (Bewertung)'**
  String get aiConfigDecisionSectionTitle;

  /// No description provided for @aiConfigDecisionHint.
  ///
  /// In de, this message translates to:
  /// **'Optionales Bewertungsmodell, das extrahierte Szenen, Kurzbeschreibungen und Spieltage mit einer 1–5-Sterne-Bewertung versieht. Die Sterne sind eine maschinell erstellte Entscheidungshilfe und ersetzen die menschliche Prüfung nicht.'**
  String get aiConfigDecisionHint;

  /// No description provided for @aiConfigDecisionProviderLabel.
  ///
  /// In de, this message translates to:
  /// **'Decision-Modell-Anbieter'**
  String get aiConfigDecisionProviderLabel;

  /// No description provided for @aiConfigDecisionDisabled.
  ///
  /// In de, this message translates to:
  /// **'— keine (Bewertung deaktiviert) —'**
  String get aiConfigDecisionDisabled;

  /// No description provided for @aiConfigDecisionModelLabel.
  ///
  /// In de, this message translates to:
  /// **'Decision-Modell'**
  String get aiConfigDecisionModelLabel;

  /// No description provided for @aiConfigDecisionSameKey.
  ///
  /// In de, this message translates to:
  /// **'Gleichen API-Schlüssel wie Extraktion verwenden'**
  String get aiConfigDecisionSameKey;

  /// No description provided for @aiConfigDecisionApiKeyLabel.
  ///
  /// In de, this message translates to:
  /// **'API-Schlüssel für Decision-Modell'**
  String get aiConfigDecisionApiKeyLabel;

  /// No description provided for @aiConfigDecisionKeyRemembered.
  ///
  /// In de, this message translates to:
  /// **'Gespeicherter Decision-Schlüssel für {provider} wird verwendet.'**
  String aiConfigDecisionKeyRemembered(Object provider);

  /// No description provided for @aiPreviewAiNoteScored.
  ///
  /// In de, this message translates to:
  /// **'Alle Zeilen sind maschinell extrahierte Entwürfe. Die Sternbewertungen (1–5) sind maschinell erstellte Qualitätseinschätzungen des Decision-Modells und ersetzen die menschliche Prüfung nicht.'**
  String get aiPreviewAiNoteScored;

  /// No description provided for @aiPreviewFilterAll.
  ///
  /// In de, this message translates to:
  /// **'Alle Szenen ({count})'**
  String aiPreviewFilterAll(Object count);

  /// No description provided for @aiPreviewFilterLowScore.
  ///
  /// In de, this message translates to:
  /// **'Niedrige Bewertung ≤ ★★★ ({count})'**
  String aiPreviewFilterLowScore(Object count);

  /// No description provided for @aiPreviewSceneScore.
  ///
  /// In de, this message translates to:
  /// **'Szenen-Bewertung:'**
  String get aiPreviewSceneScore;

  /// No description provided for @aiPreviewSynopsisScore.
  ///
  /// In de, this message translates to:
  /// **'Kurzbeschreibung (TL;DR):'**
  String get aiPreviewSynopsisScore;

  /// No description provided for @aiPreviewShootingDayScore.
  ///
  /// In de, this message translates to:
  /// **'Drehtag-Bewertung:'**
  String get aiPreviewShootingDayScore;

  /// No description provided for @aiScoreStarsLabel.
  ///
  /// In de, this message translates to:
  /// **'{stars} von 5 Sternen'**
  String aiScoreStarsLabel(Object stars);

  /// No description provided for @aiConfigDecisionKeyMissing.
  ///
  /// In de, this message translates to:
  /// **'Bitte gib einen API-Schlüssel für das Decision-Modell ein oder wähle „Gleichen API-Schlüssel wie Extraktion verwenden“.'**
  String get aiConfigDecisionKeyMissing;

  /// Marker next to a look that was forked from another look.
  ///
  /// In de, this message translates to:
  /// **'Variante'**
  String get outfitVariantMarker;

  /// Section title of a character's looks.
  ///
  /// In de, this message translates to:
  /// **'Looks'**
  String get outfitListTitle;

  /// Empty state of the character's look list.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Looks – erstelle den ersten.'**
  String get outfitListEmpty;

  /// Action that creates a new look for the character.
  ///
  /// In de, this message translates to:
  /// **'Look erstellen'**
  String get outfitCreateAction;

  /// Dialog title when creating a look.
  ///
  /// In de, this message translates to:
  /// **'Look erstellen'**
  String get outfitCreateTitle;

  /// Name field of a look.
  ///
  /// In de, this message translates to:
  /// **'Name'**
  String get outfitNameLabel;

  /// Validation message for a blank look name.
  ///
  /// In de, this message translates to:
  /// **'Es ist ein Name erforderlich'**
  String get outfitNameRequired;

  /// Screen title of the look detail.
  ///
  /// In de, this message translates to:
  /// **'Look'**
  String get outfitDetailTitle;

  /// Lineage line naming the source look.
  ///
  /// In de, this message translates to:
  /// **'Variante von {name}'**
  String outfitVariantOf(String name);

  /// Action that forks the look into an independent variant.
  ///
  /// In de, this message translates to:
  /// **'Variante erstellen'**
  String get outfitCreateVariant;

  /// Section title of the look's garments.
  ///
  /// In de, this message translates to:
  /// **'Kleidungsstücke ({count})'**
  String outfitPiecesTitle(String count);

  /// Empty state of the look's garment list.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Kleidungsstücke – füge das erste hinzu.'**
  String get outfitPiecesEmpty;

  /// Action that adds a garment to the look.
  ///
  /// In de, this message translates to:
  /// **'Kleidungsstück hinzufügen'**
  String get outfitAddPiece;

  /// Tooltip of the remove-garment icon button.
  ///
  /// In de, this message translates to:
  /// **'Entfernen'**
  String get outfitRemovePieceTooltip;

  /// Notes section title of a look.
  ///
  /// In de, this message translates to:
  /// **'Notizen'**
  String get outfitNotes;

  /// Hint inside the look notes field.
  ///
  /// In de, this message translates to:
  /// **'Notizen zum Look …'**
  String get outfitNotesHint;

  /// Action that saves the look notes.
  ///
  /// In de, this message translates to:
  /// **'Notizen speichern'**
  String get outfitSaveNotes;

  /// Fitting photos section title of a look.
  ///
  /// In de, this message translates to:
  /// **'Fotos'**
  String get outfitPhotos;

  /// Dialog title when renaming a look.
  ///
  /// In de, this message translates to:
  /// **'Look umbenennen'**
  String get outfitRenameTitle;

  /// Garment count of a look.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =1{1 Kleidungsstück} other{{count} Kleidungsstücke}}'**
  String outfitPieceCount(int count);

  /// Fallback error when a look command fails.
  ///
  /// In de, this message translates to:
  /// **'Der Look konnte nicht gespeichert werden ({code}).'**
  String outfitErrorGeneric(String code);

  /// Client-side 403 narrative for look commands.
  ///
  /// In de, this message translates to:
  /// **'Du benötigst eine aktive Kostüm-Rolle in dieser Staffel.'**
  String get outfitErrorForbidden;

  /// Membership could not be checked before a look command.
  ///
  /// In de, this message translates to:
  /// **'Berechtigungen konnten nicht überprüft werden – Verbindung prüfen und erneut versuchen.'**
  String get outfitErrorMembership;

  /// Confirmation after a look command succeeded.
  ///
  /// In de, this message translates to:
  /// **'Look gespeichert.'**
  String get outfitSaved;

  /// Confirmation after the look notes were saved.
  ///
  /// In de, this message translates to:
  /// **'Notizen gespeichert.'**
  String get outfitNotesSaved;

  /// Error banner when the look list fetch fails.
  ///
  /// In de, this message translates to:
  /// **'Looks konnten nicht geladen werden ({code}).'**
  String outfitListFetchError(String code);

  /// Stale cache banner above the look list.
  ///
  /// In de, this message translates to:
  /// **'Zwischengespeicherte Daten sind möglicherweise veraltet.'**
  String get outfitStaleBanner;

  /// Error banners when the garment list of the look section fails.
  ///
  /// In de, this message translates to:
  /// **'Kleidungsstücke konnten nicht geladen werden ({code}).'**
  String outfitPieceListFetchError(String code);

  /// Shown when the look is no longer available (deleted parent).
  ///
  /// In de, this message translates to:
  /// **'Dieser Look ist nicht mehr verfügbar.'**
  String get outfitDetailGone;

  /// Title of the garment picker sheet/dialog.
  ///
  /// In de, this message translates to:
  /// **'Kleidungsstück wählen'**
  String get outfitPickPieceTitle;

  /// Empty state of the garment picker.
  ///
  /// In de, this message translates to:
  /// **'Kein Kleidungsstück im Repertoire dieser Staffel.'**
  String get outfitPickPieceEmpty;

  /// Confirmation after a variant fork succeeded.
  ///
  /// In de, this message translates to:
  /// **'Variante erstellt.'**
  String get outfitVariantCreated;
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
