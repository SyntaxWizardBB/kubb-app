import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';

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
  static const List<Locale> supportedLocales = <Locale>[Locale('de')];

  /// Application title
  ///
  /// In de, this message translates to:
  /// **'Kubb'**
  String get appTitle;

  /// Placeholder home screen message during initial setup
  ///
  /// In de, this message translates to:
  /// **'Willkommen — Projekt-Setup läuft.'**
  String get welcomeMessage;

  /// Onboarding greeting line above the title
  ///
  /// In de, this message translates to:
  /// **'Willkommen'**
  String get onboardingGreeting;

  /// Onboarding screen title prompting for the player name
  ///
  /// In de, this message translates to:
  /// **'Wie heisst du?'**
  String get onboardingTitle;

  /// Onboarding name field placeholder
  ///
  /// In de, this message translates to:
  /// **'z.B. Lukas'**
  String get onboardingHint;

  /// Onboarding confirm button label
  ///
  /// In de, this message translates to:
  /// **'Weiter'**
  String get onboardingConfirm;

  /// Snackbar shown when profile creation fails on the onboarding screen
  ///
  /// In de, this message translates to:
  /// **'Profil konnte nicht erstellt werden — bitte erneut versuchen.'**
  String get onboardingCreateError;

  /// Profile screen title
  ///
  /// In de, this message translates to:
  /// **'Profil'**
  String get profileTitle;

  /// Fallback shown on the profile screen when no profile is available
  ///
  /// In de, this message translates to:
  /// **'Kein Profil'**
  String get profileNotLoaded;

  /// Profile device id label
  ///
  /// In de, this message translates to:
  /// **'Geräte-ID'**
  String get profileDeviceLabel;

  /// Profile created-at label
  ///
  /// In de, this message translates to:
  /// **'Mitglied seit'**
  String get profileSinceLabel;

  /// Read-mode edit toggle button
  ///
  /// In de, this message translates to:
  /// **'Bearbeiten'**
  String get profileEditButton;

  /// Save edits to profile
  ///
  /// In de, this message translates to:
  /// **'Speichern'**
  String get profileSaveButton;

  /// Discard edits to profile
  ///
  /// In de, this message translates to:
  /// **'Abbrechen'**
  String get profileCancelButton;

  /// Label above the name field in edit mode
  ///
  /// In de, this message translates to:
  /// **'Anzeigename'**
  String get profileNameLabel;

  /// Label above the color chips in edit mode
  ///
  /// In de, this message translates to:
  /// **'Avatar-Farbe'**
  String get profileColorLabel;

  /// Snackbar shown when profile update fails
  ///
  /// In de, this message translates to:
  /// **'Profil konnte nicht gespeichert werden — bitte erneut versuchen.'**
  String get profileUpdateError;

  /// App settings modal title
  ///
  /// In de, this message translates to:
  /// **'Einstellungen'**
  String get settingsTitle;

  /// Language row label
  ///
  /// In de, this message translates to:
  /// **'Sprache'**
  String get settingsLanguage;

  /// Language read-only value
  ///
  /// In de, this message translates to:
  /// **'Deutsch'**
  String get settingsLanguageValue;

  /// Theme row label
  ///
  /// In de, this message translates to:
  /// **'Erscheinungsbild'**
  String get settingsTheme;

  /// Heli tracking row label
  ///
  /// In de, this message translates to:
  /// **'Helikopter zählen'**
  String get settingsHeli;

  /// Vibration row label
  ///
  /// In de, this message translates to:
  /// **'Vibration'**
  String get settingsVibration;

  /// Long-dubbie tracking row label
  ///
  /// In de, this message translates to:
  /// **'Long Dubbie zählen'**
  String get settingsLongDubbie;

  /// Penalty-kubb tracking row label
  ///
  /// In de, this message translates to:
  /// **'Strafkubb zählen'**
  String get settingsPenaltyKubb;

  /// King-throw tracking row label
  ///
  /// In de, this message translates to:
  /// **'Königswurf zählen'**
  String get settingsKingThrow;

  /// Allow continuing beyond stick 6 row label
  ///
  /// In de, this message translates to:
  /// **'Über Stock 6 hinaus weiterspielen'**
  String get settingsAllowContinue;

  /// Allow continuing beyond stick 6 row description
  ///
  /// In de, this message translates to:
  /// **'Nach Stock 6 weiterspielen bis fertig'**
  String get settingsAllowContinueSub;

  /// Finisseur tracking section title inside the app block
  ///
  /// In de, this message translates to:
  /// **'Finisseur'**
  String get settingsFinisseurSection;

  /// Theme choice — light
  ///
  /// In de, this message translates to:
  /// **'Hell'**
  String get themeLight;

  /// Theme choice — dark
  ///
  /// In de, this message translates to:
  /// **'Dunkel'**
  String get themeDark;

  /// Theme choice — high contrast / sunlight
  ///
  /// In de, this message translates to:
  /// **'Sonnenlicht'**
  String get themeHighContrast;

  /// App version footer
  ///
  /// In de, this message translates to:
  /// **'Version {version} ({build})'**
  String settingsVersion(String version, String build);

  /// Training sheet eyebrow above title
  ///
  /// In de, this message translates to:
  /// **'Neue Session'**
  String get trainingSheetEyebrow;

  /// Training sheet title
  ///
  /// In de, this message translates to:
  /// **'Welcher Modus?'**
  String get trainingSheetTitle;

  /// Footer link below the mode cards that opens the stats screen
  ///
  /// In de, this message translates to:
  /// **'Statistik anzeigen'**
  String get trainingSheetStatsLink;

  /// Sniper mode title
  ///
  /// In de, this message translates to:
  /// **'Sniper-Training'**
  String get modeSniperTitle;

  /// Sniper mode subtitle
  ///
  /// In de, this message translates to:
  /// **'Trefferquote · Konstanz'**
  String get modeSniperSubtitle;

  /// Finisseur mode title
  ///
  /// In de, this message translates to:
  /// **'Finisseur'**
  String get modeFinisseurTitle;

  /// Finisseur mode subtitle
  ///
  /// In de, this message translates to:
  /// **'Match-Endspiel · 6 Stöcke'**
  String get modeFinisseurSubtitle;

  /// Snackbar message when tapping finisseur (not yet implemented)
  ///
  /// In de, this message translates to:
  /// **'In Vorbereitung'**
  String get modeFinisseurComingSoon;

  /// Tournament mode title in the training sheet
  ///
  /// In de, this message translates to:
  /// **'Turnier'**
  String get homeModeTournamentTitle;

  /// Tournament mode subtitle in the training sheet
  ///
  /// In de, this message translates to:
  /// **'Mehrere Teams · Tabelle'**
  String get homeModeTournamentSubtitle;

  /// Match mode title on the training hub tab
  ///
  /// In de, this message translates to:
  /// **'Match'**
  String get trainingHubMatchTitle;

  /// Match mode subtitle on the training hub tab
  ///
  /// In de, this message translates to:
  /// **'Mehrspieler · Bo1/3/5'**
  String get trainingHubMatchSubtitle;

  /// Stats tile subtitle on the training hub tab
  ///
  /// In de, this message translates to:
  /// **'Verlauf & Bestwerte'**
  String get trainingHubStatsSubtitle;

  /// Eyebrow on the finisseur config screen
  ///
  /// In de, this message translates to:
  /// **'Finisseur'**
  String get finisseurConfigEyebrow;

  /// Finisseur config screen title
  ///
  /// In de, this message translates to:
  /// **'Konfiguration'**
  String get finisseurConfigTitle;

  /// Field-kubb stepper label
  ///
  /// In de, this message translates to:
  /// **'Feldkubbs (eingeworfen)'**
  String get finisseurConfigFieldLabel;

  /// Base-kubb stepper label with current max
  ///
  /// In de, this message translates to:
  /// **'Basiskubbs · max {max}'**
  String finisseurConfigBaseLabel(int max);

  /// Constraint hint under the stepper
  ///
  /// In de, this message translates to:
  /// **'Total maximal 10 Kubbs · Basis maximal 5. Aktuell {current} / 10.'**
  String finisseurConfigConstraint(int current);

  /// Preset section header (currently unused; built-in presets removed)
  ///
  /// In de, this message translates to:
  /// **'Presets'**
  String get finisseurConfigPresets;

  /// Legacy built-in preset 7/3 label (built-ins removed)
  ///
  /// In de, this message translates to:
  /// **'Standard'**
  String get finisseurConfigPresetStandard;

  /// Legacy built-in preset 5/5 label (built-ins removed)
  ///
  /// In de, this message translates to:
  /// **'5/5'**
  String get finisseurConfigPresetEven;

  /// Legacy built-in preset 10/0 label (built-ins removed)
  ///
  /// In de, this message translates to:
  /// **'10/0'**
  String get finisseurConfigPresetAllField;

  /// Legacy built-in preset 3/5 label (built-ins removed)
  ///
  /// In de, this message translates to:
  /// **'Spät'**
  String get finisseurConfigPresetLate;

  /// Preview caption under the visual kubb stack
  ///
  /// In de, this message translates to:
  /// **'{field} / {base} · 6 Stöcke'**
  String finisseurConfigPreviewSubtitle(int field, int base);

  /// Start session button
  ///
  /// In de, this message translates to:
  /// **'Finisseur starten'**
  String get finisseurConfigStartButton;

  /// Stick screen title showing current stick number
  ///
  /// In de, this message translates to:
  /// **'Stock {n} / 6'**
  String finisseurStickTitle(int n);

  /// Stick screen eyebrow with active config
  ///
  /// In de, this message translates to:
  /// **'Finisseur · {field}/{base}'**
  String finisseurStickEyebrow(int field, int base);

  /// Remaining field-kubb label
  ///
  /// In de, this message translates to:
  /// **'Feldkubbs übrig'**
  String get finisseurStickRemainingField;

  /// Remaining base-kubb label
  ///
  /// In de, this message translates to:
  /// **'Basiskubbs übrig'**
  String get finisseurStickRemainingBase;

  /// Field-kubb section header
  ///
  /// In de, this message translates to:
  /// **'Feldkubbs umgeworfen'**
  String get finisseurStickFieldHeader;

  /// Field-kubb chip range
  ///
  /// In de, this message translates to:
  /// **'0–{max}'**
  String finisseurStickFieldRange(int max);

  /// Empty field-kubb state
  ///
  /// In de, this message translates to:
  /// **'keine Feldkubbs mehr — direkt 8m oder König'**
  String get finisseurStickFieldEmpty;

  /// Legacy 8m hit toggle label (deprecated by long dubbie)
  ///
  /// In de, this message translates to:
  /// **'8m-Treffer'**
  String get finisseurStick8mLabel;

  /// Legacy 8m hit toggle subtitle (deprecated by long dubbie)
  ///
  /// In de, this message translates to:
  /// **'Wurf auf Basiskubb'**
  String get finisseurStick8mSub;

  /// Long-dubbie toggle label — feldkubb plus basiskubb in one throw
  ///
  /// In de, this message translates to:
  /// **'Long Dubbie'**
  String get finisseurStickLongDubbieLabel;

  /// Long-dubbie toggle subtitle
  ///
  /// In de, this message translates to:
  /// **'Feldkubb + Basiskubb in einem'**
  String get finisseurStickLongDubbieSub;

  /// Heli toggle label
  ///
  /// In de, this message translates to:
  /// **'Helikopter'**
  String get finisseurStickHeliLabel;

  /// Heli toggle subtitle
  ///
  /// In de, this message translates to:
  /// **'ungültig, Stock weg'**
  String get finisseurStickHeliSub;

  /// King toggle label
  ///
  /// In de, this message translates to:
  /// **'Königswurf'**
  String get finisseurStickKingLabel;

  /// King toggle subtitle when not yet detailed
  ///
  /// In de, this message translates to:
  /// **'am Ende'**
  String get finisseurStickKingSubDefault;

  /// King position row label
  ///
  /// In de, this message translates to:
  /// **'Position'**
  String get finisseurStickKingPosition;

  /// King outcome row label
  ///
  /// In de, this message translates to:
  /// **'Outcome'**
  String get finisseurStickKingOutcome;

  /// King position oben
  ///
  /// In de, this message translates to:
  /// **'oben'**
  String get finisseurStickKingOben;

  /// King position unten
  ///
  /// In de, this message translates to:
  /// **'unten'**
  String get finisseurStickKingUnten;

  /// King outcome hit
  ///
  /// In de, this message translates to:
  /// **'Treffer'**
  String get finisseurStickKingHit;

  /// King outcome miss
  ///
  /// In de, this message translates to:
  /// **'verfehlt'**
  String get finisseurStickKingMiss;

  /// Penalty kubb section header
  ///
  /// In de, this message translates to:
  /// **'Strafkubbs (vom letzten Halbsatz)'**
  String get finisseurStickPenaltyHeader;

  /// Penalty kubb meta
  ///
  /// In de, this message translates to:
  /// **'{sum} / {base} umgeworfen'**
  String finisseurStickPenaltyMeta(int sum, int base);

  /// First penalty throw row label
  ///
  /// In de, this message translates to:
  /// **'1× geworfen'**
  String get finisseurStickPenaltyFirst;

  /// First penalty throw subtitle
  ///
  /// In de, this message translates to:
  /// **'erster Strafkubb-Wurf'**
  String get finisseurStickPenaltyFirstSub;

  /// Second penalty throw row label
  ///
  /// In de, this message translates to:
  /// **'2× geworfen'**
  String get finisseurStickPenaltySecond;

  /// Second penalty throw subtitle
  ///
  /// In de, this message translates to:
  /// **'zweiter Strafkubb-Wurf'**
  String get finisseurStickPenaltySecondSub;

  /// Next-stick button label
  ///
  /// In de, this message translates to:
  /// **'Stock {n}'**
  String finisseurStickNextStock(int n);

  /// Final stick button label
  ///
  /// In de, this message translates to:
  /// **'Session abschliessen'**
  String get finisseurStickFinish;

  /// Commit-stick button shown during the king flow in base phase
  ///
  /// In de, this message translates to:
  /// **'Stock abschliessen'**
  String get finisseurStickFinishStick;

  /// Continue-beyond-sticks dialog title
  ///
  /// In de, this message translates to:
  /// **'6 Stöcke verbraucht'**
  String get continueDecisionTitle;

  /// Continue-beyond-sticks dialog body
  ///
  /// In de, this message translates to:
  /// **'Möchtest du bis zum Ende weiterspielen?'**
  String get continueDecisionBody;

  /// Continue-beyond-sticks primary action
  ///
  /// In de, this message translates to:
  /// **'Weiterspielen'**
  String get continueDecisionContinue;

  /// Continue-beyond-sticks secondary action
  ///
  /// In de, this message translates to:
  /// **'Aufgeben'**
  String get continueDecisionGiveUp;

  /// Header above the simplified base-phase pad
  ///
  /// In de, this message translates to:
  /// **'Wurf auf Basiskubb'**
  String get finisseurStickBasePadHeader;

  /// Hit button on the simplified base-phase pad
  ///
  /// In de, this message translates to:
  /// **'Treffer'**
  String get finisseurStickBasePadHit;

  /// Miss button on the simplified base-phase pad
  ///
  /// In de, this message translates to:
  /// **'Verfehlt'**
  String get finisseurStickBasePadMiss;

  /// Single penalty kubb row label after the second-chance reduction
  ///
  /// In de, this message translates to:
  /// **'Strafkubb'**
  String get finisseurStickPenaltyLabel;

  /// Single penalty kubb row subtitle
  ///
  /// In de, this message translates to:
  /// **'Strafwurf umgeworfen'**
  String get finisseurStickPenaltySub;

  /// Title for the confirm dialog when leaving a dirty finisseur session
  ///
  /// In de, this message translates to:
  /// **'Session verwerfen?'**
  String get finisseurAbortConfirmTitle;

  /// Body for the abort confirm dialog
  ///
  /// In de, this message translates to:
  /// **'Die bisherigen Stöcke werden gelöscht. Trotzdem zurück?'**
  String get finisseurAbortConfirmBody;

  /// Cancel option of the abort confirm dialog
  ///
  /// In de, this message translates to:
  /// **'Weitertrainieren'**
  String get finisseurAbortConfirmStay;

  /// Discard option of the abort confirm dialog
  ///
  /// In de, this message translates to:
  /// **'Verwerfen'**
  String get finisseurAbortConfirmDiscard;

  /// Summary tag for successful finisseur
  ///
  /// In de, this message translates to:
  /// **'Sauber finished'**
  String get finisseurSummarySuccess;

  /// Summary tag for failed finisseur
  ///
  /// In de, this message translates to:
  /// **'Nicht geschafft'**
  String get finisseurSummaryFail;

  /// Sticks used readout
  ///
  /// In de, this message translates to:
  /// **'{n} / 6'**
  String finisseurSummarySticksUsed(int n);

  /// Sticks used subtitle
  ///
  /// In de, this message translates to:
  /// **'Stöcke benötigt · {duration}'**
  String finisseurSummarySticksUsedSubtitle(String duration);

  /// Sticks used subtitle when player continued past stock 6
  ///
  /// In de, this message translates to:
  /// **'Stöcke benötigt (Verlängerung) · {duration}'**
  String finisseurSummaryOverstickSubtitle(String duration);

  /// Summary row for king throw
  ///
  /// In de, this message translates to:
  /// **'Königswurf'**
  String get finisseurSummaryKingRow;

  /// King hit value
  ///
  /// In de, this message translates to:
  /// **'{position} durch · Treffer'**
  String finisseurSummaryKingHit(String position);

  /// King miss value on summary
  ///
  /// In de, this message translates to:
  /// **'verfehlt'**
  String get finisseurSummaryKingMiss;

  /// No king throw value on summary
  ///
  /// In de, this message translates to:
  /// **'kein Wurf'**
  String get finisseurSummaryKingNone;

  /// Penalty count row label
  ///
  /// In de, this message translates to:
  /// **'Strafkubbs'**
  String get finisseurSummaryPenalties;

  /// Heli count row label
  ///
  /// In de, this message translates to:
  /// **'Heli'**
  String get finisseurSummaryHeli;

  /// Mode row label on the finisseur summary (replaces distance for finisseurs)
  ///
  /// In de, this message translates to:
  /// **'Modus'**
  String get finisseurSummaryModeLabel;

  /// Summary screen title for finisseur
  ///
  /// In de, this message translates to:
  /// **'Finisseur · {field}/{base}'**
  String finisseurSummaryConfig(int field, int base);

  /// Recent list subtitle for finisseur
  ///
  /// In de, this message translates to:
  /// **'{field}/{base} · {sticks} Stöcke · {when}'**
  String finisseurRecentSubtitle(int field, int base, int sticks, String when);

  /// Home screen app bar title
  ///
  /// In de, this message translates to:
  /// **'Kubb Club'**
  String get homeAppTitle;

  /// Eyebrow above greeting on home
  ///
  /// In de, this message translates to:
  /// **'Kubb Club'**
  String get homeEyebrow;

  /// Greeting on home screen
  ///
  /// In de, this message translates to:
  /// **'Hallo, {name}.'**
  String homeGreeting(String name);

  /// Fallback greeting without name
  ///
  /// In de, this message translates to:
  /// **'Hallo.'**
  String get homeGreetingFallback;

  /// Eyebrow on the tournament card
  ///
  /// In de, this message translates to:
  /// **'Tournier'**
  String get homeTournierEyebrow;

  /// Tournament card title
  ///
  /// In de, this message translates to:
  /// **'Match-Modus'**
  String get homeTournierTitle;

  /// Tournament card subtitle (not yet implemented)
  ///
  /// In de, this message translates to:
  /// **'In Vorbereitung'**
  String get homeTournierComingSoon;

  /// Snackbar shown when tapping tournament card
  ///
  /// In de, this message translates to:
  /// **'In Vorbereitung'**
  String get homeTournierTapToast;

  /// Eyebrow on the news card
  ///
  /// In de, this message translates to:
  /// **'News · Kubbtour.ch'**
  String get homeNewsEyebrow;

  /// News card title
  ///
  /// In de, this message translates to:
  /// **'Saison 2026 — Termine sind raus'**
  String get homeNewsTitle;

  /// News card subtitle
  ///
  /// In de, this message translates to:
  /// **'tippen für alle Turniere & Anmeldung'**
  String get homeNewsSubtitle;

  /// Section header for the recent sessions list
  ///
  /// In de, this message translates to:
  /// **'Zuletzt'**
  String get homeRecentTitle;

  /// FAB label on home screen
  ///
  /// In de, this message translates to:
  /// **'Training'**
  String get homeFabLabel;

  /// Eyebrow above title on sniper config screen
  ///
  /// In de, this message translates to:
  /// **'Sniper-Training'**
  String get sniperConfigEyebrow;

  /// Sniper config screen title
  ///
  /// In de, this message translates to:
  /// **'Einstellungen'**
  String get sniperConfigTitle;

  /// Distance row label
  ///
  /// In de, this message translates to:
  /// **'Distanz'**
  String get sniperConfigDistanceLabel;

  /// Throw-target row label
  ///
  /// In de, this message translates to:
  /// **'Ziel-Wurfzahl'**
  String get sniperConfigTargetLabel;

  /// Throw-target value when none is set
  ///
  /// In de, this message translates to:
  /// **'kein Ziel'**
  String get sniperConfigTargetNone;

  /// Custom throw-target field hint
  ///
  /// In de, this message translates to:
  /// **'Eigener Wert'**
  String get sniperConfigTargetCustomHint;

  /// Start button label on sniper config screen
  ///
  /// In de, this message translates to:
  /// **'Sniper starten'**
  String get sniperConfigStartButton;

  /// Counter label for hits during a sniper session
  ///
  /// In de, this message translates to:
  /// **'Treffer'**
  String get sniperCounterHit;

  /// Counter label for misses during a sniper session
  ///
  /// In de, this message translates to:
  /// **'Miss'**
  String get sniperCounterMiss;

  /// Counter label for helicopter throws during a sniper session
  ///
  /// In de, this message translates to:
  /// **'Heli'**
  String get sniperCounterHeli;

  /// Remaining throws to target
  ///
  /// In de, this message translates to:
  /// **'noch {count} Würfe'**
  String sniperRemaining(int count);

  /// Hint shown when the eye-toggle masks counters
  ///
  /// In de, this message translates to:
  /// **'Trefferzahl verdeckt — du wirfst blind.'**
  String get sniperBlindHint;

  /// Primary end-session button label
  ///
  /// In de, this message translates to:
  /// **'Session beenden'**
  String get sniperEndButton;

  /// Secondary abort button label
  ///
  /// In de, this message translates to:
  /// **'Abbrechen'**
  String get sniperAbortButton;

  /// Abort dialog title
  ///
  /// In de, this message translates to:
  /// **'Session abbrechen?'**
  String get abortDialogTitle;

  /// Abort dialog explanatory body
  ///
  /// In de, this message translates to:
  /// **'Möchtest du die bisherige Session speichern oder verwerfen?'**
  String get abortDialogContent;

  /// Abort dialog cancel button
  ///
  /// In de, this message translates to:
  /// **'Zurück'**
  String get abortDialogCancel;

  /// Abort dialog discard button
  ///
  /// In de, this message translates to:
  /// **'Verwerfen'**
  String get abortDialogDiscard;

  /// Abort dialog save-and-finish button
  ///
  /// In de, this message translates to:
  /// **'Speichern'**
  String get abortDialogSave;

  /// Eyebrow above title on summary screen
  ///
  /// In de, this message translates to:
  /// **'Sniper-Training'**
  String get summaryEyebrow;

  /// Summary screen title
  ///
  /// In de, this message translates to:
  /// **'Zusammenfassung'**
  String get summaryTitle;

  /// Caption under the big hit-rate number
  ///
  /// In de, this message translates to:
  /// **'Trefferquote'**
  String get summaryHitRateLabel;

  /// Hit count row label on summary
  ///
  /// In de, this message translates to:
  /// **'Treffer'**
  String get summaryHits;

  /// Miss count row label on summary
  ///
  /// In de, this message translates to:
  /// **'Miss'**
  String get summaryMisses;

  /// Heli count row label on summary
  ///
  /// In de, this message translates to:
  /// **'Heli'**
  String get summaryHelis;

  /// Distance row label on summary
  ///
  /// In de, this message translates to:
  /// **'Distanz'**
  String get summaryDistance;

  /// Duration row label on summary
  ///
  /// In de, this message translates to:
  /// **'Dauer'**
  String get summaryDuration;

  /// Primary save button on summary
  ///
  /// In de, this message translates to:
  /// **'Speichern'**
  String get summarySave;

  /// Hard-delete button on summary
  ///
  /// In de, this message translates to:
  /// **'Verwerfen'**
  String get summaryDiscard;

  /// Restart-with-same-config button on summary
  ///
  /// In de, this message translates to:
  /// **'Neu starten'**
  String get summaryRestart;

  /// Crash recovery dialog title
  ///
  /// In de, this message translates to:
  /// **'Letzte Session unterbrochen'**
  String get crashRecoveryTitle;

  /// Crash recovery dialog content with session start date
  ///
  /// In de, this message translates to:
  /// **'Eine Session vom {date} ist noch offen. Was möchtest du tun?'**
  String crashRecoveryContent(String date);

  /// Crash recovery resume button
  ///
  /// In de, this message translates to:
  /// **'Fortsetzen'**
  String get crashRecoveryResume;

  /// Crash recovery save-as-finished button
  ///
  /// In de, this message translates to:
  /// **'Als beendet speichern'**
  String get crashRecoverySave;

  /// Crash recovery discard button
  ///
  /// In de, this message translates to:
  /// **'Verwerfen'**
  String get crashRecoveryDiscard;

  /// Bootstrap error screen title
  ///
  /// In de, this message translates to:
  /// **'App konnte nicht starten'**
  String get bootstrapErrorTitle;

  /// Bootstrap error screen body
  ///
  /// In de, this message translates to:
  /// **'Bitte App neu starten. Wenn das Problem bleibt, melde dich beim Support.'**
  String get bootstrapErrorBody;

  /// Stats screen title and settings menu entry
  ///
  /// In de, this message translates to:
  /// **'Statistik'**
  String get statsTitle;

  /// Eyebrow above stats title
  ///
  /// In de, this message translates to:
  /// **'Profil'**
  String get statsEyebrow;

  /// Distance filter pill label
  ///
  /// In de, this message translates to:
  /// **'Distanz'**
  String get statsFilterDistance;

  /// Distance filter — show all
  ///
  /// In de, this message translates to:
  /// **'Alle'**
  String get statsFilterAllDistances;

  /// Date range filter pill label
  ///
  /// In de, this message translates to:
  /// **'Zeitraum'**
  String get statsFilterDateRange;

  /// Filter modal title in stats
  ///
  /// In de, this message translates to:
  /// **'Filter'**
  String get statsFilterTitle;

  /// Apply button on the stats filter modal
  ///
  /// In de, this message translates to:
  /// **'Anwenden'**
  String get statsFilterApply;

  /// Reset button on the stats filter modal
  ///
  /// In de, this message translates to:
  /// **'Zurücksetzen'**
  String get statsFilterReset;

  /// Active distance range chip on stats screen
  ///
  /// In de, this message translates to:
  /// **'Distanz {lo}–{hi} m'**
  String statsFilterDistanceRange(String lo, String hi);

  /// Active field-kubb range chip
  ///
  /// In de, this message translates to:
  /// **'Feldkubbs {lo}–{hi}'**
  String statsFilterFieldRange(int lo, int hi);

  /// Active base-kubb range chip
  ///
  /// In de, this message translates to:
  /// **'Basiskubbs {lo}–{hi}'**
  String statsFilterBaseRange(int lo, int hi);

  /// Field-kubb range slider label inside filter modal
  ///
  /// In de, this message translates to:
  /// **'Feldkubbs'**
  String get statsFilterFinisseurField;

  /// Base-kubb range slider label inside filter modal
  ///
  /// In de, this message translates to:
  /// **'Basiskubbs'**
  String get statsFilterFinisseurBase;

  /// Date range — all time
  ///
  /// In de, this message translates to:
  /// **'Gesamt'**
  String get statsRangeAll;

  /// Date range — last 7 days
  ///
  /// In de, this message translates to:
  /// **'7 Tage'**
  String get statsRangeLast7Days;

  /// Date range — last 30 days
  ///
  /// In de, this message translates to:
  /// **'30 Tage'**
  String get statsRangeLast30Days;

  /// Big hero label for overall hit rate
  ///
  /// In de, this message translates to:
  /// **'Trefferrate'**
  String get statsHitRateLabel;

  /// Hero label for total throws
  ///
  /// In de, this message translates to:
  /// **'Würfe'**
  String get statsTotalThrowsLabel;

  /// Hero label for total session count
  ///
  /// In de, this message translates to:
  /// **'Sessions'**
  String get statsTotalSessionsLabel;

  /// Hero label for longest hit streak
  ///
  /// In de, this message translates to:
  /// **'Längste Serie'**
  String get statsLongestStreakLabel;

  /// Trend chart section title
  ///
  /// In de, this message translates to:
  /// **'Verlauf'**
  String get statsTrendTitle;

  /// Personal bests section title
  ///
  /// In de, this message translates to:
  /// **'Bestmarken'**
  String get statsBestsTitle;

  /// Personal best — highest hit rate label
  ///
  /// In de, this message translates to:
  /// **'Beste Trefferrate'**
  String get statsBestRate;

  /// Personal best — longest streak label
  ///
  /// In de, this message translates to:
  /// **'Längste Serie'**
  String get statsBestStreak;

  /// Personal best — most throws in one day label
  ///
  /// In de, this message translates to:
  /// **'Meiste Würfe an einem Tag'**
  String get statsBestDay;

  /// Session list section title
  ///
  /// In de, this message translates to:
  /// **'Letzte Sessions'**
  String get statsSessionsTitle;

  /// Sniper tab label on stats screen
  ///
  /// In de, this message translates to:
  /// **'Sniper'**
  String get statsTabSniper;

  /// Finisseur tab label on stats screen
  ///
  /// In de, this message translates to:
  /// **'Finisseur'**
  String get statsTabFinisseur;

  /// Match tab label on stats screen
  ///
  /// In de, this message translates to:
  /// **'Match'**
  String get statsTabMatch;

  /// Empty state title on the match tab when no finished matches exist
  ///
  /// In de, this message translates to:
  /// **'Noch keine Matches'**
  String get statsMatchEmptyTitle;

  /// Empty state body on the match tab
  ///
  /// In de, this message translates to:
  /// **'Spiele dein erstes Match — die Statistik füllt sich automatisch.'**
  String get statsMatchEmptyBody;

  /// Match wins metric label
  ///
  /// In de, this message translates to:
  /// **'Siege'**
  String get statsMatchWins;

  /// Match losses metric label
  ///
  /// In de, this message translates to:
  /// **'Niederlagen'**
  String get statsMatchLosses;

  /// Match ties metric label
  ///
  /// In de, this message translates to:
  /// **'Unentschieden'**
  String get statsMatchTies;

  /// Match win rate metric label
  ///
  /// In de, this message translates to:
  /// **'Siegquote'**
  String get statsMatchWinRate;

  /// Section title above the recent match list
  ///
  /// In de, this message translates to:
  /// **'Letzte Matches'**
  String get statsMatchRecentTitle;

  /// Match outcome chip — caller won
  ///
  /// In de, this message translates to:
  /// **'Gewonnen'**
  String get statsMatchOutcomeWon;

  /// Match outcome chip — caller lost
  ///
  /// In de, this message translates to:
  /// **'Verloren'**
  String get statsMatchOutcomeLost;

  /// Match outcome chip — tied match
  ///
  /// In de, this message translates to:
  /// **'Unentschieden'**
  String get statsMatchOutcomeTie;

  /// Opponent indication on a match row
  ///
  /// In de, this message translates to:
  /// **'vs {n} Spieler'**
  String statsMatchOpponent(int n);

  /// Hero label for finisseur success rate
  ///
  /// In de, this message translates to:
  /// **'Erfolgsrate'**
  String get statsFinisseurSuccessRate;

  /// Total sticks across all finisseur sessions
  ///
  /// In de, this message translates to:
  /// **'Stöcke total'**
  String get statsFinisseurTotalSticks;

  /// Average sticks per finisseur session
  ///
  /// In de, this message translates to:
  /// **'Stöcke pro Session'**
  String get statsFinisseurAvgSticks;

  /// Average long dubbies per finisseur session
  ///
  /// In de, this message translates to:
  /// **'Long Dubbies pro Session'**
  String get statsFinisseurLongDubbies;

  /// Total heli throws across finisseur sessions
  ///
  /// In de, this message translates to:
  /// **'Helikopter'**
  String get statsFinisseurHeli;

  /// Total penalty kubbs across finisseur sessions
  ///
  /// In de, this message translates to:
  /// **'Strafkubb'**
  String get statsFinisseurPenalty;

  /// King-throw hit rate across finisseur sessions
  ///
  /// In de, this message translates to:
  /// **'Königswurf-Quote'**
  String get statsFinisseurKingRate;

  /// Sticks without any hit — heli-only or full duds
  ///
  /// In de, this message translates to:
  /// **'Misses (0-Treffer-Stöcke)'**
  String get statsFinisseurMisses;

  /// Share of sticks that produced at least one hit
  ///
  /// In de, this message translates to:
  /// **'Stock-Trefferquote'**
  String get statsFinisseurStickRate;

  /// Section title for the finisseur session list
  ///
  /// In de, this message translates to:
  /// **'Letzte Finisseurs'**
  String get statsFinisseurSessionsTitle;

  /// Compact field/base label for a finisseur session row
  ///
  /// In de, this message translates to:
  /// **'{field}/{base}'**
  String statsFinisseurRowConfig(int field, int base);

  /// Sticks count in a finisseur session row
  ///
  /// In de, this message translates to:
  /// **'{n} Stöcke'**
  String statsFinisseurRowSticks(int n);

  /// Empty state title when no sessions exist
  ///
  /// In de, this message translates to:
  /// **'Noch keine Sessions'**
  String get statsEmptyTitle;

  /// Empty state body
  ///
  /// In de, this message translates to:
  /// **'Starte dein erstes Training — die Statistik füllt sich automatisch.'**
  String get statsEmptyBody;

  /// Empty state for trend chart
  ///
  /// In de, this message translates to:
  /// **'Noch zu wenig Daten — mindestens 2 Sessions für den Verlauf.'**
  String get statsTrendEmpty;

  /// Throw count in the session row
  ///
  /// In de, this message translates to:
  /// **'{n} Würfe'**
  String statsRowThrows(int n);

  /// Title of the CSV export bottom sheet
  ///
  /// In de, this message translates to:
  /// **'CSV-Export'**
  String get csvExportTitle;

  /// Section label for date range filter
  ///
  /// In de, this message translates to:
  /// **'Zeitraum'**
  String get csvExportRangeLabel;

  /// Date range — all
  ///
  /// In de, this message translates to:
  /// **'Alle'**
  String get csvExportRangeAll;

  /// Date range — last 30 days
  ///
  /// In de, this message translates to:
  /// **'30 Tage'**
  String get csvExportRange30;

  /// Date range — last 90 days
  ///
  /// In de, this message translates to:
  /// **'90 Tage'**
  String get csvExportRange90;

  /// Date range — last year
  ///
  /// In de, this message translates to:
  /// **'Jahr'**
  String get csvExportRangeYear;

  /// Section label for mode checkboxes
  ///
  /// In de, this message translates to:
  /// **'Modi'**
  String get csvExportModesLabel;

  /// Mode checkbox — sniper
  ///
  /// In de, this message translates to:
  /// **'Sniper-Training'**
  String get csvExportModeSniper;

  /// Mode checkbox — finisseur
  ///
  /// In de, this message translates to:
  /// **'Finisseur'**
  String get csvExportModeFinisseur;

  /// Live count of sessions matching the filter
  ///
  /// In de, this message translates to:
  /// **'{n} Sessions im Filter'**
  String csvExportCount(int n);

  /// Trigger download / share
  ///
  /// In de, this message translates to:
  /// **'Herunterladen'**
  String get csvExportDownload;

  /// Hint when filter matches no sessions
  ///
  /// In de, this message translates to:
  /// **'Keine Sessions zum Exportieren'**
  String get csvExportEmpty;

  /// Snackbar shown on desktop after CSV is written to disk
  ///
  /// In de, this message translates to:
  /// **'Export gespeichert: {path}'**
  String csvExportSavedTo(String path);

  /// Eyebrow above settings title
  ///
  /// In de, this message translates to:
  /// **'Menü'**
  String get settingsScreenEyebrow;

  /// Account section header
  ///
  /// In de, this message translates to:
  /// **'Account'**
  String get settingsAccountSection;

  /// Data section header
  ///
  /// In de, this message translates to:
  /// **'Daten'**
  String get settingsDataSection;

  /// App section header
  ///
  /// In de, this message translates to:
  /// **'App'**
  String get settingsAppSection;

  /// Legal section header (privacy + imprint)
  ///
  /// In de, this message translates to:
  /// **'Rechtliches'**
  String get settingsLegalSection;

  /// Profile row label
  ///
  /// In de, this message translates to:
  /// **'Profil'**
  String get settingsRowProfile;

  /// Profile row subtitle
  ///
  /// In de, this message translates to:
  /// **'Name, Avatar-Farbe'**
  String get settingsRowProfileSub;

  /// Device id row label
  ///
  /// In de, this message translates to:
  /// **'Geräte-ID'**
  String get settingsRowDeviceLabel;

  /// Stats row label
  ///
  /// In de, this message translates to:
  /// **'Statistik'**
  String get settingsRowStats;

  /// Stats row subtitle
  ///
  /// In de, this message translates to:
  /// **'Trefferquote, Streaks, Verlauf'**
  String get settingsRowStatsSub;

  /// Export row label
  ///
  /// In de, this message translates to:
  /// **'CSV-Export'**
  String get settingsRowExport;

  /// Export row subtitle
  ///
  /// In de, this message translates to:
  /// **'Sessions als .csv-Datei'**
  String get settingsRowExportSub;

  /// Reset sessions row label. Deletes Sniper and Finisseur training sessions both locally and on the server.
  ///
  /// In de, this message translates to:
  /// **'Trainings-Sessions zurücksetzen'**
  String get settingsRowResetSessions;

  /// Reset sessions row subtitle. Local drift rows plus the server-stored cloud aggregates.
  ///
  /// In de, this message translates to:
  /// **'lokal und auf dem Server löschen'**
  String get settingsRowResetSessionsSub;

  /// Delete profile row label
  ///
  /// In de, this message translates to:
  /// **'Profil löschen'**
  String get settingsRowDeleteProfile;

  /// Delete profile row subtitle
  ///
  /// In de, this message translates to:
  /// **'Profil und alle Sessions entfernen'**
  String get settingsRowDeleteProfileSub;

  /// Privacy mini-section header
  ///
  /// In de, this message translates to:
  /// **'Datenschutz'**
  String get settingsPrivacyHeader;

  /// Static privacy notice
  ///
  /// In de, this message translates to:
  /// **'Lokale Daten (Trainings-Sessions, lokale Drafts) bleiben auf deinem Gerät. Matches, Turniere, Freundschaften und Inbox-Nachrichten werden mit unserem Supabase-Backend in der EU synchronisiert, damit du Geräte wechseln kannst und Mitspieler dich sehen können.'**
  String get settingsPrivacyBody;

  /// CTA label that opens the privacy policy screen
  ///
  /// In de, this message translates to:
  /// **'Datenschutzerklärung öffnen'**
  String get settingsPrivacyLinkLabel;

  /// Header of the profile-visibility section in settings
  ///
  /// In de, this message translates to:
  /// **'Profil'**
  String get settingsVisibilitySection;

  /// Label of the profile-visibility settings row
  ///
  /// In de, this message translates to:
  /// **'Profil-Sichtbarkeit'**
  String get settingsRowVisibility;

  /// Subtitle below the visibility row
  ///
  /// In de, this message translates to:
  /// **'Wer dein Profil sehen kann'**
  String get settingsRowVisibilitySub;

  /// Visibility picker option: public
  ///
  /// In de, this message translates to:
  /// **'Öffentlich'**
  String get settingsVisibilityPublic;

  /// Visibility picker option: friends-only (default)
  ///
  /// In de, this message translates to:
  /// **'Nur Freunde'**
  String get settingsVisibilityFriendsOnly;

  /// Visibility picker option: private (owner only)
  ///
  /// In de, this message translates to:
  /// **'Privat'**
  String get settingsVisibilityPrivate;

  /// Picker dialog title
  ///
  /// In de, this message translates to:
  /// **'Profil-Sichtbarkeit'**
  String get settingsVisibilityPickerTitle;

  /// Snackbar shown after a successful visibility save
  ///
  /// In de, this message translates to:
  /// **'Sichtbarkeit gespeichert'**
  String get settingsVisibilitySavedSnack;

  /// Snackbar shown after a failed visibility save
  ///
  /// In de, this message translates to:
  /// **'Sichtbarkeit konnte nicht gespeichert werden'**
  String get settingsVisibilityErrorSnack;

  /// Footer tagline below version
  ///
  /// In de, this message translates to:
  /// **'Für die Wiese gebaut.'**
  String get settingsFooterTagline;

  /// Generic confirm dialog cancel button
  ///
  /// In de, this message translates to:
  /// **'Abbrechen'**
  String get confirmCancel;

  /// Generic confirm dialog delete button
  ///
  /// In de, this message translates to:
  /// **'Löschen'**
  String get confirmDelete;

  /// Reset sessions confirm title
  ///
  /// In de, this message translates to:
  /// **'Sessions löschen?'**
  String get confirmResetSessionsTitle;

  /// Reset sessions confirm body
  ///
  /// In de, this message translates to:
  /// **'Alle Trainings-Sessions werden unwiderruflich gelöscht — lokal und auf dem Server. Dein Profil bleibt bestehen.'**
  String get confirmResetSessionsBody;

  /// Delete profile confirm title
  ///
  /// In de, this message translates to:
  /// **'Profil löschen?'**
  String get confirmDeleteProfileTitle;

  /// Delete profile confirm body
  ///
  /// In de, this message translates to:
  /// **'Profil und alle Trainings-Sessions werden unwiderruflich gelöscht. Du landest danach im Onboarding.'**
  String get confirmDeleteProfileBody;

  /// No description provided for @settingsResetDoneSnack.
  ///
  /// In de, this message translates to:
  /// **'Sessions zurückgesetzt.'**
  String get settingsResetDoneSnack;

  /// SignInScreen brand tagline
  ///
  /// In de, this message translates to:
  /// **'Trainings-Tracker für die Wiese'**
  String get authSigninTagline;

  /// Google OAuth CTA
  ///
  /// In de, this message translates to:
  /// **'Mit Google anmelden'**
  String get authSigninGoogle;

  /// Apple OAuth CTA, iOS only
  ///
  /// In de, this message translates to:
  /// **'Mit Apple anmelden'**
  String get authSigninApple;

  /// Anonymous keypair flow CTA
  ///
  /// In de, this message translates to:
  /// **'Ohne Konto starten (anonym)'**
  String get authSigninAnonymous;

  /// Anonymous CTA while submitting
  ///
  /// In de, this message translates to:
  /// **'Konto wird angelegt …'**
  String get authSigninAnonymousLoading;

  /// Restore-account footer link
  ///
  /// In de, this message translates to:
  /// **'Konto auf neuem Gerät wiederherstellen'**
  String get authSigninRestore;

  /// Offline-state warning banner
  ///
  /// In de, this message translates to:
  /// **'Du bist offline. Provider-Anmeldung wird nicht funktionieren — Anonym-Account legt offline an, lädt später hoch.'**
  String get authSigninOffline;

  /// Divider between OAuth and anonymous CTAs
  ///
  /// In de, this message translates to:
  /// **'oder'**
  String get authSigninOr;

  /// Stable error banner shown when the OAuth flow fails on SignInScreen
  ///
  /// In de, this message translates to:
  /// **'Anmeldung fehlgeschlagen. Versuch es nochmals.'**
  String get authSigninOauthError;

  /// App brand name on SignInScreen
  ///
  /// In de, this message translates to:
  /// **'Kubb Club'**
  String get authAppName;

  /// Generic Continue button
  ///
  /// In de, this message translates to:
  /// **'Weiter'**
  String get authCommonContinue;

  /// Generic Back button
  ///
  /// In de, this message translates to:
  /// **'Zurück'**
  String get authCommonBack;

  /// Generic Close action
  ///
  /// In de, this message translates to:
  /// **'Abbrechen'**
  String get authCommonClose;

  /// Wizard header eyebrow
  ///
  /// In de, this message translates to:
  /// **'Anonym anlegen'**
  String get authSignupEyebrow;

  /// Step 1 title
  ///
  /// In de, this message translates to:
  /// **'Wähle einen Spielnamen'**
  String get authSignupNicknameTitle;

  /// Step 1 input label
  ///
  /// In de, this message translates to:
  /// **'Spielname'**
  String get authSignupNicknameLabel;

  /// Step 1 input placeholder
  ///
  /// In de, this message translates to:
  /// **'z. B. wiese-marc'**
  String get authSignupNicknamePlaceholder;

  /// Step 1 helper text
  ///
  /// In de, this message translates to:
  /// **'Andere Spielerinnen sehen diesen Namen'**
  String get authSignupNicknameHelper;

  /// Nickname error
  ///
  /// In de, this message translates to:
  /// **'Mindestens 3 Zeichen.'**
  String get authSignupNicknameTooShort;

  /// Nickname error
  ///
  /// In de, this message translates to:
  /// **'Maximal 30 Zeichen.'**
  String get authSignupNicknameTooLong;

  /// Nickname error
  ///
  /// In de, this message translates to:
  /// **'Nur Buchstaben, Zahlen, \'-\' und \'_\'.'**
  String get authSignupNicknameInvalidChars;

  /// Caption under the avatar-initial preview before the user has typed a nickname
  ///
  /// In de, this message translates to:
  /// **'Dein Avatar-Buchstabe'**
  String get authSignupNicknameAvatarHint;

  /// Inline reassurance shown on step 1 of the anonymous signup wizard
  ///
  /// In de, this message translates to:
  /// **'Anonyme Sessions kannst du via Recovery-Phrase auf ein neues Gerät übertragen — die Wörter generieren wir gleich.'**
  String get authSignupNicknameRecoveryHint;

  /// Step 2 title
  ///
  /// In de, this message translates to:
  /// **'Sichere deine Passphrase'**
  String get authSignupDisclaimerTitle;

  /// Disclaimer block heading
  ///
  /// In de, this message translates to:
  /// **'Wichtig — bitte lesen'**
  String get authDisclaimerHeading;

  /// Disclaimer bullet 1
  ///
  /// In de, this message translates to:
  /// **'Diese Passphrase kann nicht zurückgesetzt werden.'**
  String get authDisclaimerNoReset;

  /// Disclaimer bullet 2
  ///
  /// In de, this message translates to:
  /// **'Wir empfehlen dringend einen Passwort-Manager.'**
  String get authDisclaimerPasswordManager;

  /// Disclaimer bullet 3
  ///
  /// In de, this message translates to:
  /// **'Die App-Betreiber haften nicht.'**
  String get authDisclaimerNoLiability;

  /// Acknowledgement checkbox
  ///
  /// In de, this message translates to:
  /// **'Ich habe verstanden, dass diese Passphrase nicht zurückgesetzt werden kann.'**
  String get authDisclaimerAcknowledge;

  /// Passphrase field label
  ///
  /// In de, this message translates to:
  /// **'Passphrase'**
  String get authPassphraseLabel;

  /// Passphrase placeholder
  ///
  /// In de, this message translates to:
  /// **'mindestens 12 Zeichen'**
  String get authPassphrasePlaceholder;

  /// Passphrase helper
  ///
  /// In de, this message translates to:
  /// **'Mindestens 12 Zeichen. Wir empfehlen, sie direkt im Passwort-Manager zu speichern.'**
  String get authPassphraseHelper;

  /// Passphrase too short
  ///
  /// In de, this message translates to:
  /// **'Mindestens 12 Zeichen.'**
  String get authPassphraseMinError;

  /// Show toggle aria label
  ///
  /// In de, this message translates to:
  /// **'Passphrase anzeigen'**
  String get authPassphraseShow;

  /// Hide toggle aria label
  ///
  /// In de, this message translates to:
  /// **'Passphrase verbergen'**
  String get authPassphraseHide;

  /// Strength meter weak
  ///
  /// In de, this message translates to:
  /// **'Schwach'**
  String get authPassphraseStrengthWeak;

  /// Strength meter medium
  ///
  /// In de, this message translates to:
  /// **'Mittel'**
  String get authPassphraseStrengthMedium;

  /// Strength meter strong
  ///
  /// In de, this message translates to:
  /// **'Stark'**
  String get authPassphraseStrengthStrong;

  /// Step 2 submit button
  ///
  /// In de, this message translates to:
  /// **'Account erstellen'**
  String get authSignupSubmit;

  /// Step 2 submit button while submitting
  ///
  /// In de, this message translates to:
  /// **'Account wird angelegt …'**
  String get authSignupSubmitting;

  /// Step 2 submit progress hint
  ///
  /// In de, this message translates to:
  /// **'Verschlüsselungsschlüssel werden erzeugt — bis zu 4 s.'**
  String get authSignupSubmittingHint;

  /// Step 2 failure banner
  ///
  /// In de, this message translates to:
  /// **'Konto konnte nicht angelegt werden. Prüfe deine Verbindung und versuch es nochmals.'**
  String get authSignupErrorBanner;

  /// Step 3 title
  ///
  /// In de, this message translates to:
  /// **'Account angelegt'**
  String get authSignupSuccessTitle;

  /// Step 3 reminder body
  ///
  /// In de, this message translates to:
  /// **'Speichere deine Passphrase im Passwort-Manager. Ohne sie kommst du nicht mehr an dein Konto.'**
  String get authSignupSuccessReminder;

  /// Step 3 continue button
  ///
  /// In de, this message translates to:
  /// **'Weiter zur Tour'**
  String get authSignupSuccessContinue;

  /// Wizard header step counter
  ///
  /// In de, this message translates to:
  /// **'Schritt {step} / {total}'**
  String authWizardStepCount(int step, int total);

  /// Restore-flow eyebrow above the step title
  ///
  /// In de, this message translates to:
  /// **'Konto wiederherstellen'**
  String get authRestoreEyebrow;

  /// Restore step 1 title
  ///
  /// In de, this message translates to:
  /// **'Spielname'**
  String get authRestoreNicknameTitle;

  /// Restore step 2 title
  ///
  /// In de, this message translates to:
  /// **'Passphrase'**
  String get authRestorePassphraseTitle;

  /// Restore step 1 nickname placeholder
  ///
  /// In de, this message translates to:
  /// **'dein Spielname'**
  String get authRestoreNicknamePlaceholder;

  /// Restore step 1 helper text
  ///
  /// In de, this message translates to:
  /// **'Genau wie beim Anlegen des Kontos.'**
  String get authRestoreNicknameHelper;

  /// Restore step 2 passphrase helper
  ///
  /// In de, this message translates to:
  /// **'Genau wie beim Anlegen — Gross-/Kleinschreibung beachten.'**
  String get authRestorePassphraseHelper;

  /// Restore submit button label
  ///
  /// In de, this message translates to:
  /// **'Konto entsperren'**
  String get authRestoreSubmit;

  /// Restore submit button label while restoring
  ///
  /// In de, this message translates to:
  /// **'Konto wird entsperrt …'**
  String get authRestoreSubmitting;

  /// Restore failure banner
  ///
  /// In de, this message translates to:
  /// **'Wiederherstellung fehlgeschlagen.'**
  String get authRestoreError;

  /// Cooldown badge title after 3 failed attempts
  ///
  /// In de, this message translates to:
  /// **'Zu viele Versuche'**
  String get authRestoreCooldownTitle;

  /// Cooldown badge body with remaining seconds
  ///
  /// In de, this message translates to:
  /// **'Bitte warte {seconds} Sekunden, dann versuch es erneut.'**
  String authRestoreCooldownMessage(int seconds);

  /// Link-screen eyebrow above the title
  ///
  /// In de, this message translates to:
  /// **'Account'**
  String get authLinkEyebrow;

  /// Link-screen header title
  ///
  /// In de, this message translates to:
  /// **'Konto verknüpfen'**
  String get authLinkTitle;

  /// Link-screen large heading
  ///
  /// In de, this message translates to:
  /// **'Verknüpfe dein Konto\nfür sichereres Backup'**
  String get authLinkHeading;

  /// Link-screen explanatory body
  ///
  /// In de, this message translates to:
  /// **'Du bist aktuell anonym mit deiner Passphrase angemeldet. Wenn du Google oder Apple verknüpfst, kannst du dein Konto auch ohne Passphrase wiederherstellen.'**
  String get authLinkExplanation;

  /// Google upgrade button label
  ///
  /// In de, this message translates to:
  /// **'Google verknüpfen'**
  String get authLinkGoogleLabel;

  /// Apple upgrade button label
  ///
  /// In de, this message translates to:
  /// **'Apple verknüpfen'**
  String get authLinkAppleLabel;

  /// Link-screen error banner
  ///
  /// In de, this message translates to:
  /// **'Verknüpfen fehlgeschlagen. Versuch es nochmals.'**
  String get authLinkErrorBanner;

  /// Link-screen success banner
  ///
  /// In de, this message translates to:
  /// **'Konto erfolgreich verknüpft.'**
  String get authLinkSuccessBanner;

  /// Link-screen reassurance note that the keypair is still usable
  ///
  /// In de, this message translates to:
  /// **'Dein bisheriger Zugang per Passphrase bleibt als Backup erhalten.'**
  String get authLinkFallbackKept;

  /// Passphrase-change screen eyebrow
  ///
  /// In de, this message translates to:
  /// **'Sicherheit'**
  String get authPassphraseChangeEyebrow;

  /// Passphrase-change screen title
  ///
  /// In de, this message translates to:
  /// **'Passphrase ändern'**
  String get authPassphraseChangeTitle;

  /// Label for old-passphrase field
  ///
  /// In de, this message translates to:
  /// **'Alte Passphrase'**
  String get authPassphraseChangeOldLabel;

  /// Helper text under old-passphrase field
  ///
  /// In de, this message translates to:
  /// **'Wir prüfen erst, dann setzen wir die neue.'**
  String get authPassphraseChangeOldHelper;

  /// Inline error on the old-passphrase field after a failed change
  ///
  /// In de, this message translates to:
  /// **'Konnte nicht ändern.'**
  String get authPassphraseChangeError;

  /// Label for new-passphrase field
  ///
  /// In de, this message translates to:
  /// **'Neue Passphrase'**
  String get authPassphraseChangeNewLabel;

  /// Helper text under new-passphrase field
  ///
  /// In de, this message translates to:
  /// **'Mindestens 12 Zeichen. Sie sollte sich von der bisherigen unterscheiden.'**
  String get authPassphraseChangeNewHelper;

  /// Label for confirm-passphrase field
  ///
  /// In de, this message translates to:
  /// **'Neue Passphrase bestätigen'**
  String get authPassphraseChangeConfirmLabel;

  /// Helper text under confirm-passphrase field
  ///
  /// In de, this message translates to:
  /// **'Erneut eingeben — exakt gleich.'**
  String get authPassphraseChangeConfirmHelper;

  /// Inline error when confirm differs from new
  ///
  /// In de, this message translates to:
  /// **'Stimmt nicht überein.'**
  String get authPassphraseChangeConfirmMismatch;

  /// Success banner after passphrase change
  ///
  /// In de, this message translates to:
  /// **'Passphrase aktualisiert.'**
  String get authPassphraseChangeSuccess;

  /// Submit button label
  ///
  /// In de, this message translates to:
  /// **'Speichern'**
  String get authPassphraseChangeSubmit;

  /// Submit button label while saving
  ///
  /// In de, this message translates to:
  /// **'Speichere …'**
  String get authPassphraseChangeSubmitting;

  /// Cancel button label
  ///
  /// In de, this message translates to:
  /// **'Abbrechen'**
  String get authPassphraseChangeCancel;

  /// Delete-account flow eyebrow
  ///
  /// In de, this message translates to:
  /// **'Konto löschen'**
  String get authDeleteEyebrow;

  /// Page 1 title
  ///
  /// In de, this message translates to:
  /// **'Konto löschen?'**
  String get authDeleteWarningTitle;

  /// Page 2 title
  ///
  /// In de, this message translates to:
  /// **'Endgültig bestätigen'**
  String get authDeleteConfirmTitle;

  /// Page 1 large headline
  ///
  /// In de, this message translates to:
  /// **'Diese Aktion ist endgültig'**
  String get authDeleteWarningHeadline;

  /// Page 1 introduction to the consequences list
  ///
  /// In de, this message translates to:
  /// **'Wenn du fortfährst, geht Folgendes verloren:'**
  String get authDeleteWarningSub;

  /// Consequence bullet 1
  ///
  /// In de, this message translates to:
  /// **'Alle gespeicherten Trainings-Sessions'**
  String get authDeleteConsequenceSessions;

  /// Consequence bullet 2
  ///
  /// In de, this message translates to:
  /// **'Statistiken, Streaks, Erfolge'**
  String get authDeleteConsequenceStats;

  /// Consequence bullet 3
  ///
  /// In de, this message translates to:
  /// **'Dein Spielername und Profil'**
  String get authDeleteConsequenceProfile;

  /// Consequence bullet 4
  ///
  /// In de, this message translates to:
  /// **'Verknüpfte Konten (Google / Apple)'**
  String get authDeleteConsequenceLinkedAccounts;

  /// Consequence bullet 5
  ///
  /// In de, this message translates to:
  /// **'Anonymer Keypair-Zugang — nicht wiederherstellbar'**
  String get authDeleteConsequenceKeypair;

  /// Page 1 primary button
  ///
  /// In de, this message translates to:
  /// **'Weiter zur Bestätigung'**
  String get authDeleteContinueToConfirm;

  /// Page 2 acknowledgement checkbox label
  ///
  /// In de, this message translates to:
  /// **'Ich verstehe, dass alle Daten dauerhaft gelöscht werden.'**
  String get authDeleteAcknowledge;

  /// Page 2 error banner
  ///
  /// In de, this message translates to:
  /// **'Löschen fehlgeschlagen. Bitte später erneut versuchen.'**
  String get authDeleteErrorBanner;

  /// Page 2 destructive submit
  ///
  /// In de, this message translates to:
  /// **'Konto endgültig löschen'**
  String get authDeleteSubmit;

  /// Page 2 destructive submit while deleting
  ///
  /// In de, this message translates to:
  /// **'Konto wird gelöscht …'**
  String get authDeleteSubmitting;

  /// Page 2 cancel button
  ///
  /// In de, this message translates to:
  /// **'Abbrechen'**
  String get authDeleteCancel;

  /// Onboarding next button
  ///
  /// In de, this message translates to:
  /// **'Weiter'**
  String get authOnboardingNext;

  /// Onboarding finish button
  ///
  /// In de, this message translates to:
  /// **'Fertig'**
  String get authOnboardingDone;

  /// Onboarding skip link
  ///
  /// In de, this message translates to:
  /// **'Überspringen'**
  String get authOnboardingSkip;

  /// Slide 1 title
  ///
  /// In de, this message translates to:
  /// **'Willkommen.'**
  String get authOnboardingWelcomeTitle;

  /// Slide 1 body text
  ///
  /// In de, this message translates to:
  /// **'Kubb Club hilft dir, deine Würfe systematisch zu verbessern — Sniper, Finisseur, und bald mehr.'**
  String get authOnboardingWelcomeBody;

  /// Status badge for anonymous keypair sessions
  ///
  /// In de, this message translates to:
  /// **'Anonymes Konto'**
  String get authOnboardingBadgeAnon;

  /// Status badge for Google OAuth sessions
  ///
  /// In de, this message translates to:
  /// **'Mit Google verknüpft'**
  String get authOnboardingBadgeGoogle;

  /// Status badge for Apple OAuth sessions
  ///
  /// In de, this message translates to:
  /// **'Mit Apple verknüpft'**
  String get authOnboardingBadgeApple;

  /// Compact app-bar badge label for anonymous keypair sessions
  ///
  /// In de, this message translates to:
  /// **'Anonym'**
  String get authBadgeAnonShort;

  /// Compact app-bar badge label for Google OAuth sessions
  ///
  /// In de, this message translates to:
  /// **'Google'**
  String get authBadgeGoogleShort;

  /// Compact app-bar badge label for Apple OAuth sessions
  ///
  /// In de, this message translates to:
  /// **'Apple'**
  String get authBadgeAppleShort;

  /// Screen reader label for the account status badge
  ///
  /// In de, this message translates to:
  /// **'Konto-Status: {label}'**
  String authBadgeStatusSemantic(String label);

  /// Slide 2 title
  ///
  /// In de, this message translates to:
  /// **'Trainingsmodi'**
  String get authOnboardingModesTitle;

  /// Mode 1 name
  ///
  /// In de, this message translates to:
  /// **'Sniper'**
  String get authOnboardingModeSniperName;

  /// Mode 1 subtitle
  ///
  /// In de, this message translates to:
  /// **'8 m gerade Treffer trainieren'**
  String get authOnboardingModeSniperSub;

  /// Mode 2 name
  ///
  /// In de, this message translates to:
  /// **'Finisseur'**
  String get authOnboardingModeFinisseurName;

  /// Mode 2 subtitle
  ///
  /// In de, this message translates to:
  /// **'Königswurf-Sequenzen üben'**
  String get authOnboardingModeFinisseurSub;

  /// Mode 3 name
  ///
  /// In de, this message translates to:
  /// **'4 m-Linie'**
  String get authOnboardingMode4mName;

  /// Mode 3 subtitle
  ///
  /// In de, this message translates to:
  /// **'Strafkubb-Distanz präzisieren'**
  String get authOnboardingMode4mSub;

  /// Pill label on upcoming modes
  ///
  /// In de, this message translates to:
  /// **'künftig'**
  String get authOnboardingSoonPill;

  /// Slide 3 title
  ///
  /// In de, this message translates to:
  /// **'Bald verfügbar'**
  String get authOnboardingSoonTitle;

  /// Slide 3 chip 1
  ///
  /// In de, this message translates to:
  /// **'Tournaments'**
  String get authOnboardingSoonTournaments;

  /// Slide 3 chip 2
  ///
  /// In de, this message translates to:
  /// **'Friend-Match'**
  String get authOnboardingSoonFriendMatch;

  /// Slide 3 body text
  ///
  /// In de, this message translates to:
  /// **'Mit Freundinnen und Klubs spielen, Resultate teilen, Ranglisten verfolgen — kommt bald.'**
  String get authOnboardingSoonBody;

  /// Slide 4 title (anonymous-only reminder)
  ///
  /// In de, this message translates to:
  /// **'Eine letzte Sache.'**
  String get authOnboardingReminderTitle;

  /// Slide 4 reinforcement question
  ///
  /// In de, this message translates to:
  /// **'Hast du deine Passphrase im Passwort-Manager gespeichert?'**
  String get authOnboardingReminderQuestion;

  /// Slide 4 reinforcement body
  ///
  /// In de, this message translates to:
  /// **'Ohne sie kommst du nicht mehr an dein anonymes Konto.'**
  String get authOnboardingReminderBody;

  /// Section heading above the account block in settings
  ///
  /// In de, this message translates to:
  /// **'Konto'**
  String get authAccountSectionLabel;

  /// Provider badge for anonymous keypair sessions
  ///
  /// In de, this message translates to:
  /// **'Anonym (Passphrase)'**
  String get authAccountProviderAnonymous;

  /// Provider badge for Google OAuth sessions
  ///
  /// In de, this message translates to:
  /// **'Google'**
  String get authAccountProviderGoogle;

  /// Provider badge for Apple OAuth sessions
  ///
  /// In de, this message translates to:
  /// **'Apple'**
  String get authAccountProviderApple;

  /// Nav-row label leading to account-link screen
  ///
  /// In de, this message translates to:
  /// **'Konto verknüpfen'**
  String get authAccountLinkLabel;

  /// Nav-row subtitle for account link
  ///
  /// In de, this message translates to:
  /// **'Mit Google oder Apple für sichereres Backup'**
  String get authAccountLinkSub;

  /// Nav-row label leading to passphrase change
  ///
  /// In de, this message translates to:
  /// **'Passphrase ändern'**
  String get authAccountPassphraseLabel;

  /// Nav-row subtitle for passphrase change
  ///
  /// In de, this message translates to:
  /// **'Neue Passphrase für dein Keypair'**
  String get authAccountPassphraseSub;

  /// Nav-row label that signs the user out
  ///
  /// In de, this message translates to:
  /// **'Abmelden'**
  String get authAccountSignOutLabel;

  /// Nav-row subtitle for sign-out, with current provider
  ///
  /// In de, this message translates to:
  /// **'Beendet die Session — {provider}'**
  String authAccountSignOutSub(String provider);

  /// Nav-row label leading to account delete
  ///
  /// In de, this message translates to:
  /// **'Konto löschen'**
  String get authAccountDeleteLabel;

  /// Nav-row subtitle for account delete
  ///
  /// In de, this message translates to:
  /// **'Alle Daten dauerhaft entfernen'**
  String get authAccountDeleteSub;

  /// Title of the yellow backup-warning surface in the account section
  ///
  /// In de, this message translates to:
  /// **'Backup empfohlen'**
  String get authBackupWarningTitle;

  /// Body of the backup-warning when no backup row exists
  ///
  /// In de, this message translates to:
  /// **'Dein anonymes Konto hat noch kein Backup auf dem Server.'**
  String get authBackupWarningMissing;

  /// Body of the backup-warning when last backup is older than 90 days
  ///
  /// In de, this message translates to:
  /// **'Letztes Backup vor {days} Tagen — bitte aktualisieren.'**
  String authBackupWarningStale(int days);

  /// Edit-profile screen eyebrow
  ///
  /// In de, this message translates to:
  /// **'Account'**
  String get authEditProfileEyebrow;

  /// Edit-profile screen title
  ///
  /// In de, this message translates to:
  /// **'Profil bearbeiten'**
  String get authEditProfileTitle;

  /// Nickname field label
  ///
  /// In de, this message translates to:
  /// **'Spielname'**
  String get authEditProfileNicknameLabel;

  /// Nickname field helper text
  ///
  /// In de, this message translates to:
  /// **'3–30 Zeichen, Buchstaben, Zahlen, \'-\', \'_\'.'**
  String get authEditProfileNicknameHelper;

  /// Save failure banner
  ///
  /// In de, this message translates to:
  /// **'Konnte nicht speichern.'**
  String get authEditProfileError;

  /// Save success banner
  ///
  /// In de, this message translates to:
  /// **'Profil aktualisiert.'**
  String get authEditProfileSuccess;

  /// Save button label
  ///
  /// In de, this message translates to:
  /// **'Speichern'**
  String get authEditProfileSubmit;

  /// Save button label while saving
  ///
  /// In de, this message translates to:
  /// **'Speichere …'**
  String get authEditProfileSubmitting;

  /// Tournament setup wizard title
  ///
  /// In de, this message translates to:
  /// **'Neues Turnier'**
  String get tournamentWizardTitle;

  /// Wizard step 1 eyebrow
  ///
  /// In de, this message translates to:
  /// **'Stammdaten'**
  String get tournamentWizardStep1Title;

  /// Wizard step 2 eyebrow
  ///
  /// In de, this message translates to:
  /// **'Teilnehmer'**
  String get tournamentWizardStep2Title;

  /// Wizard step 3 title (Vorrunde + KO axis)
  ///
  /// In de, this message translates to:
  /// **'Vorrunde'**
  String get tournamentWizardStep3Title;

  /// Wizard group-phase step title
  ///
  /// In de, this message translates to:
  /// **'Gruppenphase'**
  String get tournamentWizardStepGroupPhaseTitle;

  /// Wizard step 4 eyebrow
  ///
  /// In de, this message translates to:
  /// **'Übersicht'**
  String get tournamentWizardStep4Title;

  /// Progress bar caption
  ///
  /// In de, this message translates to:
  /// **'Schritt {step} von {total}'**
  String tournamentWizardStepLabel(int step, int total);

  /// Display-name input label
  ///
  /// In de, this message translates to:
  /// **'Turniername'**
  String get tournamentWizardDisplayNameLabel;

  /// Helper text explaining the auto-appended year suffix (K01)
  ///
  /// In de, this message translates to:
  /// **'Die Jahreszahl wird automatisch angehängt (z.B. 2026).'**
  String get tournamentWizardDisplayNameYearHint;

  /// Optional organizing-club picker label on the Stammdaten step
  ///
  /// In de, this message translates to:
  /// **'Ausrichtender Verein'**
  String get tournamentWizardClubLabel;

  /// Helper text under the organizing-club picker
  ///
  /// In de, this message translates to:
  /// **'Vereine, die du verwalten kannst, können dieses Turnier ebenfalls verwalten. Ohne Verein (Spasstournier) zählt das Turnier nicht für die Wertung.'**
  String get tournamentWizardClubHint;

  /// Dropdown option for no organizing club; a non-rated fun tournament (K02)
  ///
  /// In de, this message translates to:
  /// **'Spasstournier – ohne Wertung'**
  String get tournamentWizardClubNone;

  /// Hint shown in the club picker until the organizer actively picks (K03)
  ///
  /// In de, this message translates to:
  /// **'Bitte wählen'**
  String get tournamentWizardClubChoosePrompt;

  /// Venue / town input label on the Stammdaten step
  ///
  /// In de, this message translates to:
  /// **'Ort'**
  String get tournamentWizardLocationLabel;

  /// Placeholder for the location field
  ///
  /// In de, this message translates to:
  /// **'z.B. Sportplatz Esp, Fislisbach'**
  String get tournamentWizardLocationHint;

  /// Tournament start date+time field label
  ///
  /// In de, this message translates to:
  /// **'Datum & Startzeit'**
  String get tournamentWizardEventDateLabel;

  /// In-app registration deadline field label
  ///
  /// In de, this message translates to:
  /// **'Anmeldeschluss'**
  String get tournamentWizardRegistrationDeadlineLabel;

  /// On-site check-in deadline (Speakerpult) field label
  ///
  /// In de, this message translates to:
  /// **'Vor-Ort-Check-in bis'**
  String get tournamentWizardCheckinUntilLabel;

  /// Placeholder shown on a date field before a value is picked
  ///
  /// In de, this message translates to:
  /// **'Nicht gesetzt'**
  String get tournamentWizardDateNotSet;

  /// Small badge marking an optional setup field
  ///
  /// In de, this message translates to:
  /// **'optional'**
  String get tournamentWizardOptional;

  /// League categories (A/B/C) multi-select label
  ///
  /// In de, this message translates to:
  /// **'Liga-Kategorien'**
  String get tournamentWizardLeagueCategoriesLabel;

  /// Helper text under the league categories selector
  ///
  /// In de, this message translates to:
  /// **'Für welche Liga zählt dieses Turnier? Mehrfachauswahl möglich.'**
  String get tournamentWizardLeagueCategoriesHint;

  /// League tier chip label
  ///
  /// In de, this message translates to:
  /// **'Liga {category}'**
  String tournamentWizardLeagueCategory(String category);

  /// Scoring system selector label
  ///
  /// In de, this message translates to:
  /// **'Wertung'**
  String get tournamentWizardScoringLabel;

  /// EKC scoring option title
  ///
  /// In de, this message translates to:
  /// **'EKC'**
  String get tournamentWizardScoringEkc;

  /// EKC scoring option subtitle
  ///
  /// In de, this message translates to:
  /// **'1 Punkt pro Basekubb + 3 für den Satz'**
  String get tournamentWizardScoringEkcHint;

  /// Classic scoring option title
  ///
  /// In de, this message translates to:
  /// **'Klassisch'**
  String get tournamentWizardScoringClassic;

  /// Classic scoring option subtitle
  ///
  /// In de, this message translates to:
  /// **'Nur Satzsieg zählt'**
  String get tournamentWizardScoringClassicHint;

  /// Section header: fee / payment / contact
  ///
  /// In de, this message translates to:
  /// **'Teilnahme'**
  String get tournamentWizardSectionParticipation;

  /// Section header: rule variants + PDFs
  ///
  /// In de, this message translates to:
  /// **'Regeln & Dokumente'**
  String get tournamentWizardSectionRules;

  /// Section header: free-text info blocks
  ///
  /// In de, this message translates to:
  /// **'Infos für Teilnehmer'**
  String get tournamentWizardSectionInfo;

  /// Venue address field label
  ///
  /// In de, this message translates to:
  /// **'Adresse'**
  String get tournamentWizardVenueAddressLabel;

  /// Venue address placeholder
  ///
  /// In de, this message translates to:
  /// **'Strasse, PLZ Ort'**
  String get tournamentWizardVenueAddressHint;

  /// Entry fee field label
  ///
  /// In de, this message translates to:
  /// **'Teilnahmegebühr (CHF)'**
  String get tournamentWizardEntryFeeLabel;

  /// Entry fee placeholder
  ///
  /// In de, this message translates to:
  /// **'z.B. 10'**
  String get tournamentWizardEntryFeeHint;

  /// Payment methods multi-select label
  ///
  /// In de, this message translates to:
  /// **'Zahlungsarten'**
  String get tournamentWizardPaymentMethodsLabel;

  /// Cash payment chip
  ///
  /// In de, this message translates to:
  /// **'Bar'**
  String get tournamentWizardPaymentCash;

  /// Twint payment chip
  ///
  /// In de, this message translates to:
  /// **'Twint'**
  String get tournamentWizardPaymentTwint;

  /// Card payment chip
  ///
  /// In de, this message translates to:
  /// **'Karte'**
  String get tournamentWizardPaymentCard;

  /// Contact person name field label
  ///
  /// In de, this message translates to:
  /// **'Kontaktperson'**
  String get tournamentWizardContactNameLabel;

  /// Contact phone field label
  ///
  /// In de, this message translates to:
  /// **'Kontakt-Telefon'**
  String get tournamentWizardContactPhoneLabel;

  /// Contact phone placeholder
  ///
  /// In de, this message translates to:
  /// **'Für kurzfristige Ab-/Ummeldungen'**
  String get tournamentWizardContactPhoneHint;

  /// Food/catering info field label
  ///
  /// In de, this message translates to:
  /// **'Verpflegung'**
  String get tournamentWizardInfoFoodLabel;

  /// Travel/arrival info field label
  ///
  /// In de, this message translates to:
  /// **'Anfahrt'**
  String get tournamentWizardInfoTravelLabel;

  /// Accommodation info field label
  ///
  /// In de, this message translates to:
  /// **'Übernachtung'**
  String get tournamentWizardInfoAccommodationLabel;

  /// Weather note field label
  ///
  /// In de, this message translates to:
  /// **'Wetter-Hinweis'**
  String get tournamentWizardWeatherLabel;

  /// Opening rule field label
  ///
  /// In de, this message translates to:
  /// **'Anspielregel'**
  String get tournamentWizardOpeningRuleLabel;

  /// Sureshot rule toggle title
  ///
  /// In de, this message translates to:
  /// **'Sureshot'**
  String get tournamentWizardRuleSureshot;

  /// Sureshot rule toggle subtitle
  ///
  /// In de, this message translates to:
  /// **'König muss rückwärts zwischen den Beinen geworfen werden'**
  String get tournamentWizardRuleSureshotHint;

  /// Diggy rule toggle title
  ///
  /// In de, this message translates to:
  /// **'Diggy-Regel'**
  String get tournamentWizardRuleDiggy;

  /// Diggy rule toggle subtitle
  ///
  /// In de, this message translates to:
  /// **'Doppel-Chriesi dürfen aufgestellt werden'**
  String get tournamentWizardRuleDiggyHint;

  /// Opening-rule (Anspielregel) selector label (K06)
  ///
  /// In de, this message translates to:
  /// **'Anspielregel'**
  String get tournamentWizardRuleOpeningLabel;

  /// Opening-rule option: 2-4-6 (K06)
  ///
  /// In de, this message translates to:
  /// **'2-4-6'**
  String get tournamentWizardRuleOpening246;

  /// Opening-rule option: free opening (K06)
  ///
  /// In de, this message translates to:
  /// **'Frei'**
  String get tournamentWizardRuleOpeningFree;

  /// Helper text under the opening-rule selector (K06)
  ///
  /// In de, this message translates to:
  /// **'Reihenfolge beim Anspiel (Standard: 2-4-6).'**
  String get tournamentWizardRuleOpeningHint;

  /// Penalty kubb rule toggle title
  ///
  /// In de, this message translates to:
  /// **'Strafkubb mit Abstand'**
  String get tournamentWizardRuleStrafkubb;

  /// Penalty kubb rule toggle subtitle
  ///
  /// In de, this message translates to:
  /// **'Strafkubb mind. eine Stocklänge von der Grundlinie'**
  String get tournamentWizardRuleStrafkubbHint;

  /// Rules PDF upload field label
  ///
  /// In de, this message translates to:
  /// **'Regelwerk (PDF)'**
  String get tournamentWizardRulesPdfLabel;

  /// Site map PDF upload field label
  ///
  /// In de, this message translates to:
  /// **'Lageplan (PDF)'**
  String get tournamentWizardSiteMapPdfLabel;

  /// PDF upload button label
  ///
  /// In de, this message translates to:
  /// **'PDF hochladen'**
  String get tournamentWizardPdfUpload;

  /// Badge shown once a PDF is uploaded
  ///
  /// In de, this message translates to:
  /// **'Hochgeladen'**
  String get tournamentWizardPdfUploaded;

  /// Status while a PDF uploads
  ///
  /// In de, this message translates to:
  /// **'Lädt hoch …'**
  String get tournamentWizardPdfUploading;

  /// Remove uploaded PDF action
  ///
  /// In de, this message translates to:
  /// **'Entfernen'**
  String get tournamentWizardPdfRemove;

  /// Snackbar message when a PDF upload fails
  ///
  /// In de, this message translates to:
  /// **'Upload fehlgeschlagen'**
  String get tournamentWizardPdfUploadError;

  /// Minimum players per team stepper label
  ///
  /// In de, this message translates to:
  /// **'Min. Spieler / Team'**
  String get tournamentWizardMinTeamSizeLabel;

  /// Maximum players per team stepper label
  ///
  /// In de, this message translates to:
  /// **'Max. Spieler / Team'**
  String get tournamentWizardMaxTeamSizeLabel;

  /// Helper text under the team size steppers
  ///
  /// In de, this message translates to:
  /// **'Spieler pro Team — Min. = Max. = feste Grösse, 1 = Einzelturnier'**
  String get tournamentWizardTeamSizeHint;

  /// Section header for pitch configuration
  ///
  /// In de, this message translates to:
  /// **'Pitches / Spielfelder'**
  String get tournamentWizardSectionPitches;

  /// Helper text under the pitch section
  ///
  /// In de, this message translates to:
  /// **'Auf welchen Feldern wird gespielt? Kann auch später gesetzt werden.'**
  String get tournamentWizardPitchHint;

  /// Pitch mode: contiguous number range
  ///
  /// In de, this message translates to:
  /// **'Nummernbereich'**
  String get tournamentWizardPitchModeRange;

  /// Pitch mode: manual list of numbers
  ///
  /// In de, this message translates to:
  /// **'Manuelle Liste'**
  String get tournamentWizardPitchModeManual;

  /// Pitch range lower bound label
  ///
  /// In de, this message translates to:
  /// **'Von'**
  String get tournamentWizardPitchRangeFrom;

  /// Pitch range upper bound label
  ///
  /// In de, this message translates to:
  /// **'Bis'**
  String get tournamentWizardPitchRangeTo;

  /// Manual pitch numbers field label
  ///
  /// In de, this message translates to:
  /// **'Pitch-Nummern'**
  String get tournamentWizardPitchNumbersLabel;

  /// Manual pitch numbers placeholder
  ///
  /// In de, this message translates to:
  /// **'z.B. 1, 2, 5, 8'**
  String get tournamentWizardPitchNumbersHint;

  /// Pitch sort strategy label
  ///
  /// In de, this message translates to:
  /// **'Sortierung'**
  String get tournamentWizardPitchSortLabel;

  /// Pitch sort: top seeds on lowest pitch numbers
  ///
  /// In de, this message translates to:
  /// **'Beste auf tiefsten Nummern'**
  String get tournamentWizardPitchSortTopSeeds;

  /// Pitch sort: manual order
  ///
  /// In de, this message translates to:
  /// **'Manuelle Reihenfolge'**
  String get tournamentWizardPitchSortManual;

  /// Title of the manual pitch-order editor
  ///
  /// In de, this message translates to:
  /// **'Reihenfolge der Felder'**
  String get tournamentWizardPitchOrderLabel;

  /// Helper text explaining how to reorder pitches by dragging
  ///
  /// In de, this message translates to:
  /// **'Per Drag die gewünschte Reihenfolge der Feldnummern festlegen.'**
  String get tournamentWizardPitchOrderHint;

  /// Label for a single pitch row in the manual order editor
  ///
  /// In de, this message translates to:
  /// **'Feld {number}'**
  String tournamentWizardPitchOrderItem(int number);

  /// Count of configured pitches
  ///
  /// In de, this message translates to:
  /// **'{count} Pitches'**
  String tournamentWizardPitchSummary(int count);

  /// Section title for assigning pitch numbers to pool groups
  ///
  /// In de, this message translates to:
  /// **'Pitch-Zuteilung pro Gruppe'**
  String get tournamentWizardPoolPitchAssignmentLabel;

  /// Helper text explaining per-group pitch assignment and seeding placement
  ///
  /// In de, this message translates to:
  /// **'Wähle pro Gruppe die Pitch-Nummern. Die höchstgerankten Spieler werden auf die zuerst gelisteten Pitches gesetzt (Sortierung folgt der Pitch-Strategie).'**
  String get tournamentWizardPoolPitchAssignmentHint;

  /// Label for a single pool group in the pitch-assignment section
  ///
  /// In de, this message translates to:
  /// **'Gruppe {label}'**
  String tournamentWizardPoolGroupLabel(String label);

  /// Label for the group-count input in the Vorrunde step (K12)
  ///
  /// In de, this message translates to:
  /// **'Anzahl Gruppen'**
  String get tournamentWizardPoolGroupCountLabel;

  /// Validation error when the group count is out of range
  ///
  /// In de, this message translates to:
  /// **'Wert zwischen {min} und {max} erforderlich.'**
  String tournamentWizardPoolGroupCountRangeError(int min, int max);

  /// Validation error when the group count does not evenly divide the KO bracket size
  ///
  /// In de, this message translates to:
  /// **'Gruppen müssen die KO-Grösse ({koSize}) glatt teilen.'**
  String tournamentWizardPoolDivisibilityError(int koSize);

  /// Read-only label for the derived qualifiers-per-group value
  ///
  /// In de, this message translates to:
  /// **'Qualifier pro Gruppe'**
  String get tournamentWizardPoolQualifiersPerGroupLabel;

  /// Label for the pool grouping-strategy selector
  ///
  /// In de, this message translates to:
  /// **'Grouping-Strategie'**
  String get tournamentWizardPoolStrategyLabel;

  /// Snake grouping-strategy option
  ///
  /// In de, this message translates to:
  /// **'Snake (Schweizer-Liga)'**
  String get tournamentWizardPoolStrategySnake;

  /// Seeded grouping-strategy option
  ///
  /// In de, this message translates to:
  /// **'Seeded (Blockweise)'**
  String get tournamentWizardPoolStrategySeeded;

  /// Random grouping-strategy option
  ///
  /// In de, this message translates to:
  /// **'Random (deterministisch)'**
  String get tournamentWizardPoolStrategyRandom;

  /// Label for the optional random-seed input shown for the random strategy
  ///
  /// In de, this message translates to:
  /// **'Random-Seed (optional)'**
  String get tournamentWizardPoolRandomSeedLabel;

  /// Prelim time limit per match stepper label
  ///
  /// In de, this message translates to:
  /// **'Zeit pro Match (Min.)'**
  String get tournamentWizardMatchTimeLabel;

  /// Prelim tiebreak toggle title
  ///
  /// In de, this message translates to:
  /// **'Tiebreak'**
  String get tournamentWizardTiebreakLabel;

  /// Prelim tiebreak toggle subtitle
  ///
  /// In de, this message translates to:
  /// **'Bei Zeitablauf wird ein Tiebreak gespielt'**
  String get tournamentWizardTiebreakHint;

  /// Prelim tiebreak trigger time stepper label
  ///
  /// In de, this message translates to:
  /// **'Tiebreak nach (Min.)'**
  String get tournamentWizardTiebreakAfterLabel;

  /// Break between matches stepper label
  ///
  /// In de, this message translates to:
  /// **'Pause zwischen Matches (Min.)'**
  String get tournamentWizardBreakBetweenLabel;

  /// Bracket type label
  ///
  /// In de, this message translates to:
  /// **'Bracket-Typ'**
  String get tournamentWizardBracketTypeLabel;

  /// Single elimination
  ///
  /// In de, this message translates to:
  /// **'Single-KO'**
  String get tournamentWizardBracketSingle;

  /// Double elimination
  ///
  /// In de, this message translates to:
  /// **'Double-KO'**
  String get tournamentWizardBracketDouble;

  /// KO matchup label
  ///
  /// In de, this message translates to:
  /// **'Begegnungen'**
  String get tournamentWizardKoMatchupLabel;

  /// Seed high vs low
  ///
  /// In de, this message translates to:
  /// **'Beste vs Schlechteste'**
  String get tournamentWizardKoMatchupHighLow;

  /// Adjacent placements
  ///
  /// In de, this message translates to:
  /// **'1. vs 2.'**
  String get tournamentWizardKoMatchupOneTwo;

  /// KO tiebreak method
  ///
  /// In de, this message translates to:
  /// **'KO-Tiebreak-Methode'**
  String get tournamentWizardKoTiebreakMethodLabel;

  /// Classic tiebreak
  ///
  /// In de, this message translates to:
  /// **'Klassisch'**
  String get tournamentWizardKoTiebreakClassic;

  /// Mighty finisher shootout
  ///
  /// In de, this message translates to:
  /// **'Mighty-Finisher'**
  String get tournamentWizardKoTiebreakMighty;

  /// KO match rules section
  ///
  /// In de, this message translates to:
  /// **'KO-Regelsatz'**
  String get tournamentWizardKoRulesLabel;

  /// Per-KO-round rules section header
  ///
  /// In de, this message translates to:
  /// **'Regeln pro KO-Runde'**
  String get tournamentWizardKoRoundRulesLabel;

  /// Per-KO-round rules section helper
  ///
  /// In de, this message translates to:
  /// **'Sätze, Zeit und Pause können pro Runde gewählt werden.'**
  String get tournamentWizardKoRoundRulesHint;

  /// KO round label: final
  ///
  /// In de, this message translates to:
  /// **'Final'**
  String get tournamentWizardKoRoundFinal;

  /// KO round label: semifinal
  ///
  /// In de, this message translates to:
  /// **'Halbfinale'**
  String get tournamentWizardKoRoundSemi;

  /// KO round label: quarterfinal
  ///
  /// In de, this message translates to:
  /// **'Viertelfinale'**
  String get tournamentWizardKoRoundQuarter;

  /// KO round label: round of 16
  ///
  /// In de, this message translates to:
  /// **'Achtelfinale'**
  String get tournamentWizardKoRoundEighth;

  /// Generic KO round label for large brackets, e.g. 1/16-Final
  ///
  /// In de, this message translates to:
  /// **'1/{size}-Final'**
  String tournamentWizardKoRoundOf(int size);

  /// Per-round break-after label
  ///
  /// In de, this message translates to:
  /// **'Pause danach (Min.)'**
  String get tournamentWizardKoRoundPauseLabel;

  /// Per-round tiebreak toggle
  ///
  /// In de, this message translates to:
  /// **'Tiebreak'**
  String get tournamentWizardKoRoundTiebreakLabel;

  /// Per-round tiebreak-after label
  ///
  /// In de, this message translates to:
  /// **'Tiebreak nach (Min.)'**
  String get tournamentWizardKoRoundTiebreakAfterLabel;

  /// Final/semifinal without tiebreak toggle
  ///
  /// In de, this message translates to:
  /// **'Ab Halbfinale ohne Tiebreak'**
  String get tournamentWizardKoFinalNoTiebreak;

  /// Min participants stepper label
  ///
  /// In de, this message translates to:
  /// **'Min. Teilnehmer'**
  String get tournamentWizardMinParticipantsLabel;

  /// Max participants stepper label
  ///
  /// In de, this message translates to:
  /// **'Max. Teilnehmer'**
  String get tournamentWizardMaxParticipantsLabel;

  /// Format radio group label
  ///
  /// In de, this message translates to:
  /// **'Turnierformat'**
  String get tournamentWizardFormatLabel;

  /// Round robin format label
  ///
  /// In de, this message translates to:
  /// **'Round Robin'**
  String get tournamentWizardFormatRoundRobin;

  /// Pill on disabled formats
  ///
  /// In de, this message translates to:
  /// **'Folgt in M2+'**
  String get tournamentWizardFormatComingSoon;

  /// Preliminary stage selector label
  ///
  /// In de, this message translates to:
  /// **'Vorrunde'**
  String get tournamentWizardVorrundeLabel;

  /// Group-phase preliminary option
  ///
  /// In de, this message translates to:
  /// **'Gruppenphase'**
  String get tournamentWizardVorrundeGroupPhase;

  /// Group-phase preliminary description
  ///
  /// In de, this message translates to:
  /// **'Jeder gegen jeden, Rangliste entscheidet.'**
  String get tournamentWizardVorrundeGroupPhaseHint;

  /// Schoch preliminary option
  ///
  /// In de, this message translates to:
  /// **'Schoch'**
  String get tournamentWizardVorrundeSchoch;

  /// Schoch preliminary description
  ///
  /// In de, this message translates to:
  /// **'Schoch-Paarung über mehrere Runden, dann Rangliste.'**
  String get tournamentWizardVorrundeSchochHint;

  /// KO stage selector label
  ///
  /// In de, this message translates to:
  /// **'K.-o.-System'**
  String get tournamentWizardKoSystemLabel;

  /// Single elimination KO option
  ///
  /// In de, this message translates to:
  /// **'Single-Out'**
  String get tournamentWizardKoSystemSingle;

  /// Single-out KO description
  ///
  /// In de, this message translates to:
  /// **'Eine Niederlage und du bist raus.'**
  String get tournamentWizardKoSystemSingleHint;

  /// Double elimination KO option
  ///
  /// In de, this message translates to:
  /// **'Double-Elimination'**
  String get tournamentWizardKoSystemDouble;

  /// Double-out KO description
  ///
  /// In de, this message translates to:
  /// **'Erst nach zwei Niederlagen ausgeschieden.'**
  String get tournamentWizardKoSystemDoubleHint;

  /// Consolation bracket KO option (Modell B)
  ///
  /// In de, this message translates to:
  /// **'Trostturnier'**
  String get tournamentWizardKoSystemConsolation;

  /// Consolation KO description
  ///
  /// In de, this message translates to:
  /// **'Single-Out plus separates Nebenturnier für die hinteren Plätze.'**
  String get tournamentWizardKoSystemConsolationHint;

  /// Accessibility/tooltip label for the info icon that opens the KO-model explainer sheet
  ///
  /// In de, this message translates to:
  /// **'K.-o.-Systeme erklärt'**
  String get tournamentKoModelExplainerOpen;

  /// Title of the KO-model explainer modal
  ///
  /// In de, this message translates to:
  /// **'Welcher zweite Baum?'**
  String get tournamentKoModelExplainerTitle;

  /// Section heading for the Single-Out KO model in the explainer modal
  ///
  /// In de, this message translates to:
  /// **'Single-Out'**
  String get tournamentKoModelExplainerSingleOutHeading;

  /// Explanation paragraph for the Single-Out KO model
  ///
  /// In de, this message translates to:
  /// **'Eine Niederlage und du bist draussen. Der Final entscheidet Platz 1 und 2, dazu gibt es ein Spiel um Platz 3. Schnell und einfach.'**
  String get tournamentKoModelExplainerSingleOutBody;

  /// Section heading for the Double-Elimination KO model in the explainer modal
  ///
  /// In de, this message translates to:
  /// **'Double-Elimination'**
  String get tournamentKoModelExplainerDoubleElimHeading;

  /// Explanation paragraph for the Double-Elimination KO model
  ///
  /// In de, this message translates to:
  /// **'Du musst zweimal verlieren, um auszuscheiden. Wer im Hauptbaum verliert, fällt in den Verliererbaum und kann sich von dort bis ins Finale zurückkämpfen — der Verliererbaum-Sieger kann am Ende noch Turniersieger werden. Sportlich am fairsten, aber mehr Spiele.'**
  String get tournamentKoModelExplainerDoubleElimBody;

  /// Section heading for the Trostturnier (consolation) KO model in the explainer modal
  ///
  /// In de, this message translates to:
  /// **'Trostturnier'**
  String get tournamentKoModelExplainerTrostturnierHeading;

  /// Explanation paragraph for the Trostturnier (consolation) KO model
  ///
  /// In de, this message translates to:
  /// **'Der Hauptbaum entscheidet Platz 1 und 2 endgültig. Wer im Hauptbaum ausscheidet (ausser den Halbfinal-Verlierern, die um Platz 3 spielen), kommt ins Trostturnier und spielt dort die hinteren Plätze aus. Optional starten zusätzlich einige Teams direkt aus der Vorrunde im Trostturnier. Es gibt keinen Weg zurück ins Finale — aber alle bekommen mehr Spiele und eine Platzierung.'**
  String get tournamentKoModelExplainerTrostturnierBody;

  /// Model-B main bracket size label (= KO size)
  ///
  /// In de, this message translates to:
  /// **'Hauptbaum-Grösse'**
  String get tournamentWizardConsolationMainBracketSizeLabel;

  /// Model-B direct-starter count label
  ///
  /// In de, this message translates to:
  /// **'Direkt ins Trostturnier'**
  String get tournamentWizardConsolationDirectCountLabel;

  /// Model-B direct-starter count helper
  ///
  /// In de, this message translates to:
  /// **'Wie viele Vorrunden-Teams starten direkt im Trostturnier (zusätzlich zu den Hauptbaum-Verlierern).'**
  String get tournamentWizardConsolationDirectCountHint;

  /// Model-B consolation display-name label
  ///
  /// In de, this message translates to:
  /// **'Name des Trostturniers'**
  String get tournamentWizardConsolationNameLabel;

  /// Model-B consolation display-name hint
  ///
  /// In de, this message translates to:
  /// **'z. B. Bâton Rouille'**
  String get tournamentWizardConsolationNameHint;

  /// Model-B consolation section heading shown in the KO step
  ///
  /// In de, this message translates to:
  /// **'Trostturnier (Nebenturnier)'**
  String get tournamentWizardConsolationSectionLabel;

  /// Label for the 0-direct-starters chip in the consolation config
  ///
  /// In de, this message translates to:
  /// **'Keine'**
  String get tournamentWizardConsolationDirectCountNone;

  /// Sets-to-win stepper label
  ///
  /// In de, this message translates to:
  /// **'Sätze zum Sieg'**
  String get tournamentWizardSetsToWinLabel;

  /// Max-sets stepper label
  ///
  /// In de, this message translates to:
  /// **'Max. Sätze'**
  String get tournamentWizardMaxSetsLabel;

  /// Round-time summary label
  ///
  /// In de, this message translates to:
  /// **'Rundenzeit (Minuten)'**
  String get tournamentWizardRoundTimeLabel;

  /// Wizard back button
  ///
  /// In de, this message translates to:
  /// **'Zurück'**
  String get tournamentWizardBackButton;

  /// Wizard next button
  ///
  /// In de, this message translates to:
  /// **'Weiter'**
  String get tournamentWizardNextButton;

  /// Wizard final submit button
  ///
  /// In de, this message translates to:
  /// **'Turnier anlegen'**
  String get tournamentWizardCreateButton;

  /// Wizard final submit button in EDIT mode (P7)
  ///
  /// In de, this message translates to:
  /// **'Änderungen speichern'**
  String get tournamentWizardSaveButton;

  /// Wizard app-bar title in EDIT mode (P7)
  ///
  /// In de, this message translates to:
  /// **'Turnier bearbeiten'**
  String get tournamentWizardEditTitle;

  /// Snackbar on submit failure
  ///
  /// In de, this message translates to:
  /// **'Turnier konnte nicht erstellt werden: {error}'**
  String tournamentWizardSubmitError(String error);

  /// Eyebrow above tournament-list title
  ///
  /// In de, this message translates to:
  /// **'Turniere'**
  String get tournamentListEyebrow;

  /// Tournament-list screen title
  ///
  /// In de, this message translates to:
  /// **'Übersicht'**
  String get tournamentListTitle;

  /// Tab label: tournaments created by caller
  ///
  /// In de, this message translates to:
  /// **'Meine Turniere'**
  String get tournamentListTabMine;

  /// Tab label: public discoverable tournaments
  ///
  /// In de, this message translates to:
  /// **'Aktuelle Turniere'**
  String get tournamentListTabPublic;

  /// FAB label opening the setup wizard
  ///
  /// In de, this message translates to:
  /// **'Neues Turnier'**
  String get tournamentListNewButton;

  /// Hub tile: tournaments the user is registered for
  ///
  /// In de, this message translates to:
  /// **'Angemeldete Turniere'**
  String get tournamentHubRegisteredTitle;

  /// Hub tile subtitle for registered tournaments
  ///
  /// In de, this message translates to:
  /// **'Deine Anmeldungen verwalten'**
  String get tournamentHubRegisteredSubtitle;

  /// Hub tile subtitle for the public tournament list
  ///
  /// In de, this message translates to:
  /// **'Ausgeschriebene Turniere stöbern'**
  String get tournamentHubBrowseSubtitle;

  /// Hub tile (organizer only): create/publish a tournament
  ///
  /// In de, this message translates to:
  /// **'Turnier erstellen'**
  String get tournamentHubCreateTitle;

  /// Hub tile subtitle for create tournament
  ///
  /// In de, this message translates to:
  /// **'Als Veranstalter publizieren'**
  String get tournamentHubCreateSubtitle;

  /// Hub tile: tournament statistics (placeholder)
  ///
  /// In de, this message translates to:
  /// **'Turnierstatistik'**
  String get tournamentHubStatsTitle;

  /// Hub tile subtitle for the not-yet-built stats screen
  ///
  /// In de, this message translates to:
  /// **'In Vorbereitung'**
  String get tournamentHubStatsSubtitle;

  /// Hub tile: past (finalized) tournaments
  ///
  /// In de, this message translates to:
  /// **'Vergangene Turniere'**
  String get tournamentHubPastTitle;

  /// Hub tile subtitle for past tournaments
  ///
  /// In de, this message translates to:
  /// **'Abgeschlossene Turniere ansehen'**
  String get tournamentHubPastSubtitle;

  /// Hub tile: mercenary market (coming soon)
  ///
  /// In de, this message translates to:
  /// **'Söldnermarkt'**
  String get tournamentHubMercenaryTitle;

  /// Hub tile subtitle for the mercenary market, includes the coming-soon hint
  ///
  /// In de, this message translates to:
  /// **'Bald verfügbar – Mitspieler für Turniere finden'**
  String get tournamentHubMercenarySubtitle;

  /// Coming-soon marker shown on not-yet-available hub tiles
  ///
  /// In de, this message translates to:
  /// **'Coming Soon'**
  String get tournamentHubComingSoonBadge;

  /// Hub tile title and app-bar title for the all-time tournament leaderboard
  ///
  /// In de, this message translates to:
  /// **'Rangliste'**
  String get tournamentHubRankingTitle;

  /// Hub tile subtitle for the all-time tournament leaderboard
  ///
  /// In de, this message translates to:
  /// **'Ewige Bestenliste der Turniere'**
  String get tournamentHubRankingSubtitle;

  /// Ranking screen tab label for league-A team leaderboard
  ///
  /// In de, this message translates to:
  /// **'Liga A'**
  String get tournamentRankingTabLigaA;

  /// Ranking screen tab label for league-B team leaderboard
  ///
  /// In de, this message translates to:
  /// **'Liga B'**
  String get tournamentRankingTabLigaB;

  /// Ranking screen tab label for league-C team leaderboard
  ///
  /// In de, this message translates to:
  /// **'Liga C'**
  String get tournamentRankingTabLigaC;

  /// Ranking screen tab label for the singles leaderboard
  ///
  /// In de, this message translates to:
  /// **'Einzel'**
  String get tournamentRankingTabEinzel;

  /// Ranking list column header for the participant name
  ///
  /// In de, this message translates to:
  /// **'Name'**
  String get tournamentRankingColName;

  /// Ranking list column header for total points
  ///
  /// In de, this message translates to:
  /// **'Punkte'**
  String get tournamentRankingColPoints;

  /// Ranking list column header for the tournament count
  ///
  /// In de, this message translates to:
  /// **'Turniere'**
  String get tournamentRankingColCount;

  /// Empty-state text on a ranking tab with no entries yet
  ///
  /// In de, this message translates to:
  /// **'Noch keine Wertungen'**
  String get tournamentRankingEmpty;

  /// Error text when the ranking leaderboard fails to load
  ///
  /// In de, this message translates to:
  /// **'Rangliste konnte nicht geladen werden'**
  String get tournamentRankingError;

  /// Eyebrow on the past tournaments screen
  ///
  /// In de, this message translates to:
  /// **'Turniere'**
  String get tournamentPastEyebrow;

  /// Screen title: past (finalized) tournaments
  ///
  /// In de, this message translates to:
  /// **'Vergangene Turniere'**
  String get tournamentPastTitle;

  /// Empty state title on the past tournaments screen
  ///
  /// In de, this message translates to:
  /// **'Noch keine vergangenen Turniere'**
  String get tournamentPastEmptyTitle;

  /// Empty state body on the past tournaments screen
  ///
  /// In de, this message translates to:
  /// **'Sobald ein Turnier abgeschlossen ist, erscheint es hier.'**
  String get tournamentPastEmptyBody;

  /// Eyebrow on the mercenary market screen
  ///
  /// In de, this message translates to:
  /// **'Turniere'**
  String get tournamentMercenaryEyebrow;

  /// Screen title: mercenary market
  ///
  /// In de, this message translates to:
  /// **'Söldnermarkt'**
  String get tournamentMercenaryTitle;

  /// Coming-soon placeholder title on the mercenary market screen
  ///
  /// In de, this message translates to:
  /// **'Bald verfügbar'**
  String get tournamentMercenaryComingSoonTitle;

  /// Coming-soon placeholder body on the mercenary market screen
  ///
  /// In de, this message translates to:
  /// **'Der Söldnermarkt ist noch in Arbeit. Bald kannst du hier Mitspieler für Turniere finden und dich selbst als Söldner anbieten.'**
  String get tournamentMercenaryComingSoonBody;

  /// Screen title: my tournament registrations
  ///
  /// In de, this message translates to:
  /// **'Angemeldet'**
  String get tournamentRegistrationsTitle;

  /// Empty state title on the registrations screen
  ///
  /// In de, this message translates to:
  /// **'Noch keine Anmeldung'**
  String get tournamentRegistrationsEmptyTitle;

  /// Empty state body on the registrations screen
  ///
  /// In de, this message translates to:
  /// **'Sobald du dich bei einem ausgeschriebenen Turnier anmeldest, erscheint es hier.'**
  String get tournamentRegistrationsEmptyBody;

  /// Empty state body on the public tournament list
  ///
  /// In de, this message translates to:
  /// **'Sobald Veranstalter Turniere ausschreiben, erscheinen sie hier.'**
  String get tournamentBrowseEmptyBody;

  /// Button: withdraw from a tournament
  ///
  /// In de, this message translates to:
  /// **'Abmelden'**
  String get tournamentRegistrationsWithdraw;

  /// Withdraw confirmation dialog title
  ///
  /// In de, this message translates to:
  /// **'Vom Turnier abmelden?'**
  String get tournamentWithdrawConfirmTitle;

  /// Withdraw confirmation dialog body
  ///
  /// In de, this message translates to:
  /// **'Deine Anmeldung wird zurückgezogen. Solange die Registrierung offen ist, kannst du dich erneut anmelden.'**
  String get tournamentWithdrawConfirmBody;

  /// Placeholder title on the tournament stats screen
  ///
  /// In de, this message translates to:
  /// **'Turnierstatistik kommt bald'**
  String get tournamentStatsComingSoonTitle;

  /// Placeholder body on the tournament stats screen
  ///
  /// In de, this message translates to:
  /// **'Hier siehst du künftig deine Turnier-Bilanz, Platzierungen und den Verlauf.'**
  String get tournamentStatsComingSoonBody;

  /// Empty state on Meine Turniere tab
  ///
  /// In de, this message translates to:
  /// **'Du hast noch keine Turniere erstellt.'**
  String get tournamentListEmptyMine;

  /// Empty state on Aktuelle Turniere tab
  ///
  /// In de, this message translates to:
  /// **'Keine offenen Turniere zurzeit.'**
  String get tournamentListEmptyPublic;

  /// Participant count chip on tournament cards
  ///
  /// In de, this message translates to:
  /// **'{count} Teilnehmer'**
  String tournamentListParticipantCount(int count);

  /// Pill: tournament status draft
  ///
  /// In de, this message translates to:
  /// **'Entwurf'**
  String get tournamentStatusDraft;

  /// Pill: tournament status published
  ///
  /// In de, this message translates to:
  /// **'Veröffentlicht'**
  String get tournamentStatusPublished;

  /// Pill: registration open
  ///
  /// In de, this message translates to:
  /// **'Anmeldung offen'**
  String get tournamentStatusRegistrationOpen;

  /// Pill: registration closed
  ///
  /// In de, this message translates to:
  /// **'Anmeldung geschlossen'**
  String get tournamentStatusRegistrationClosed;

  /// Pill: tournament live
  ///
  /// In de, this message translates to:
  /// **'Läuft'**
  String get tournamentStatusLive;

  /// Pill: tournament finalized
  ///
  /// In de, this message translates to:
  /// **'Abgeschlossen'**
  String get tournamentStatusFinalized;

  /// Pill: tournament aborted
  ///
  /// In de, this message translates to:
  /// **'Abgebrochen'**
  String get tournamentStatusAborted;

  /// Format chip: round-robin
  ///
  /// In de, this message translates to:
  /// **'Jeder gegen Jeden'**
  String get tournamentFormatRoundRobin;

  /// Format chip: single-elimination
  ///
  /// In de, this message translates to:
  /// **'K.-o.'**
  String get tournamentFormatSingleElimination;

  /// Format chip: Schoch system
  ///
  /// In de, this message translates to:
  /// **'Schoch'**
  String get tournamentFormatSchoch;

  /// Format chip: Swiss system
  ///
  /// In de, this message translates to:
  /// **'Schweizer System'**
  String get tournamentFormatSwiss;

  /// Format chip: round-robin then knockout
  ///
  /// In de, this message translates to:
  /// **'Gruppen + K.-o.'**
  String get tournamentFormatRoundRobinKo;

  /// Format chip: Schoch then knockout
  ///
  /// In de, this message translates to:
  /// **'Schoch + K.-o.'**
  String get tournamentFormatSchochKo;

  /// Format chip: Swiss then knockout
  ///
  /// In de, this message translates to:
  /// **'Schweiz + K.-o.'**
  String get tournamentFormatSwissKo;

  /// Detail-screen eyebrow
  ///
  /// In de, this message translates to:
  /// **'Turnier'**
  String get tournamentDetailEyebrow;

  /// Shown when detail returns null
  ///
  /// In de, this message translates to:
  /// **'Turnier nicht gefunden.'**
  String get tournamentDetailNotFound;

  /// Header subline with participant count vs capacity
  ///
  /// In de, this message translates to:
  /// **'{count} von {max} Teilnehmern'**
  String tournamentDetailParticipantSummary(int count, int max);

  /// Section heading: master data
  ///
  /// In de, this message translates to:
  /// **'Stammdaten'**
  String get tournamentDetailStammdaten;

  /// Row label: format
  ///
  /// In de, this message translates to:
  /// **'Format'**
  String get tournamentDetailFormat;

  /// Row label: team size
  ///
  /// In de, this message translates to:
  /// **'Team-Grösse'**
  String get tournamentDetailTeamSize;

  /// Row label: sets-to-win
  ///
  /// In de, this message translates to:
  /// **'Sätze zum Sieg'**
  String get tournamentDetailSetsToWin;

  /// Row label: maximum sets
  ///
  /// In de, this message translates to:
  /// **'Max Sätze'**
  String get tournamentDetailMaxSets;

  /// Row label: round time
  ///
  /// In de, this message translates to:
  /// **'Runden-Zeit'**
  String get tournamentDetailRoundTime;

  /// Section heading: participants
  ///
  /// In de, this message translates to:
  /// **'Teilnehmer'**
  String get tournamentDetailParticipants;

  /// Empty participants list
  ///
  /// In de, this message translates to:
  /// **'Noch keine Anmeldungen.'**
  String get tournamentDetailParticipantsEmpty;

  /// Section heading: caller's team roster
  ///
  /// In de, this message translates to:
  /// **'Mein Roster'**
  String get tournamentDetailRoster;

  /// Empty roster state
  ///
  /// In de, this message translates to:
  /// **'Noch keine Slots belegt.'**
  String get tournamentDetailRosterEmpty;

  /// Roster slot label with 1-based index
  ///
  /// In de, this message translates to:
  /// **'Slot {index}'**
  String tournamentDetailRosterSlot(int index);

  /// Marker for guest roster slot
  ///
  /// In de, this message translates to:
  /// **'Gast'**
  String get tournamentDetailRosterGuest;

  /// Team match header listing roster members
  ///
  /// In de, this message translates to:
  /// **'Hammer-Crew ({members})'**
  String tournamentMatchHammerCrew(String members);

  /// Inline marker for pending registration
  ///
  /// In de, this message translates to:
  /// **'ausstehend'**
  String get tournamentDetailPending;

  /// Inline marker / badge for a confirmed registration (auto-confirmed model)
  ///
  /// In de, this message translates to:
  /// **'Angemeldet'**
  String get tournamentDetailStatusConfirmed;

  /// Inline marker / badge for a waitlisted registration
  ///
  /// In de, this message translates to:
  /// **'Auf Warteliste'**
  String get tournamentDetailStatusWaitlist;

  /// Sub-heading for the waitlist section in the participants/registrations overview
  ///
  /// In de, this message translates to:
  /// **'Warteliste'**
  String get tournamentDetailWaitlistHeading;

  /// Optional organizer moderation action: remove a participant (not a required step)
  ///
  /// In de, this message translates to:
  /// **'Entfernen'**
  String get tournamentDetailActionRemove;

  /// Organizer button: approve registration
  ///
  /// In de, this message translates to:
  /// **'Bestätigen'**
  String get tournamentDetailApprove;

  /// Organizer button: reject registration
  ///
  /// In de, this message translates to:
  /// **'Ablehnen'**
  String get tournamentDetailReject;

  /// Action: publish draft tournament
  ///
  /// In de, this message translates to:
  /// **'Veröffentlichen'**
  String get tournamentDetailActionPublish;

  /// Action: open registration
  ///
  /// In de, this message translates to:
  /// **'Anmeldung öffnen'**
  String get tournamentDetailActionOpenReg;

  /// Action: close registration
  ///
  /// In de, this message translates to:
  /// **'Anmeldung schliessen'**
  String get tournamentDetailActionCloseReg;

  /// Action: register self
  ///
  /// In de, this message translates to:
  /// **'Anmelden'**
  String get tournamentDetailActionRegister;

  /// Action: withdraw own registration
  ///
  /// In de, this message translates to:
  /// **'Abmelden'**
  String get tournamentDetailActionWithdraw;

  /// Action: start tournament
  ///
  /// In de, this message translates to:
  /// **'Turnier starten'**
  String get tournamentDetailActionStart;

  /// Action: finalize tournament
  ///
  /// In de, this message translates to:
  /// **'Turnier abschliessen'**
  String get tournamentDetailActionFinalize;

  /// Action: abort tournament
  ///
  /// In de, this message translates to:
  /// **'Turnier abbrechen'**
  String get tournamentDetailActionAbort;

  /// Action: navigate to matches screen
  ///
  /// In de, this message translates to:
  /// **'Zu den Matches'**
  String get tournamentDetailActionGotoMatches;

  /// Action: navigate to final standings
  ///
  /// In de, this message translates to:
  /// **'Endrangliste'**
  String get tournamentDetailActionStandings;

  /// Action: navigate to KO bracket view
  ///
  /// In de, this message translates to:
  /// **'Bracket anzeigen'**
  String get tournamentDetailActionBracket;

  /// Action: organizer opens the live pitch dashboard
  ///
  /// In de, this message translates to:
  /// **'Live-Dashboard öffnen'**
  String get tournamentDetailActionLiveDashboard;

  /// Headline when status is aborted
  ///
  /// In de, this message translates to:
  /// **'Turnier abgebrochen.'**
  String get tournamentDetailAborted;

  /// Action: organizer edits the tournament details (pre-start)
  ///
  /// In de, this message translates to:
  /// **'Bearbeiten'**
  String get tournamentDetailActionEdit;

  /// Lifecycle hint shown to the organizer while the tournament is still a draft (publishing opens registration immediately)
  ///
  /// In de, this message translates to:
  /// **'Veröffentlichen — die Anmeldung ist danach sofort offen und Spieler können sich anmelden. Starten kannst du, sobald genug Teilnehmer dabei sind.'**
  String get tournamentDetailHintDraft;

  /// Lifecycle hint shown to the organizer while the tournament is published (legacy status; registration is open)
  ///
  /// In de, this message translates to:
  /// **'Die Anmeldung ist offen. Spieler können sich anmelden, bis du das Turnier startest.'**
  String get tournamentDetailHintPublished;

  /// Lifecycle hint shown to the organizer while registration is open (publishing already opened it)
  ///
  /// In de, this message translates to:
  /// **'Die Anmeldung ist offen. Starte das Turnier, sobald genug Teilnehmer dabei sind — der Start schliesst die Anmeldung automatisch.'**
  String get tournamentDetailHintRegistrationOpen;

  /// Lifecycle hint shown to the organizer after registration closed, before start
  ///
  /// In de, this message translates to:
  /// **'Anmeldung ist geschlossen. Jetzt kann das Turnier gestartet werden.'**
  String get tournamentDetailHintRegistrationClosed;

  /// Section heading for the pool-phase group standings on the detail screen
  ///
  /// In de, this message translates to:
  /// **'Gruppen'**
  String get tournamentDetailPools;

  /// Empty-state message when the pool phase has not produced standings yet
  ///
  /// In de, this message translates to:
  /// **'Noch keine Gruppendaten.'**
  String get tournamentDetailPoolsEmpty;

  /// Heading per pool group, e.g. 'Gruppe A'
  ///
  /// In de, this message translates to:
  /// **'Gruppe {label}'**
  String tournamentDetailPoolGroup(String label);

  /// Section heading: audit tail
  ///
  /// In de, this message translates to:
  /// **'Verlauf'**
  String get tournamentDetailAuditHeader;

  /// Empty audit-tail message
  ///
  /// In de, this message translates to:
  /// **'Keine Ereignisse.'**
  String get tournamentDetailAuditEmpty;

  /// Registration screen eyebrow
  ///
  /// In de, this message translates to:
  /// **'Turnier'**
  String get tournamentRegistrationEyebrow;

  /// Registration screen title
  ///
  /// In de, this message translates to:
  /// **'Anmelden'**
  String get tournamentRegistrationTitle;

  /// Hint banner explaining pending state
  ///
  /// In de, this message translates to:
  /// **'Du wirst zunächst auf \'ausstehend\' gesetzt, bis der Veranstalter bestätigt.'**
  String get tournamentRegistrationPendingHint;

  /// Submit button label
  ///
  /// In de, this message translates to:
  /// **'Anmeldung bestätigen'**
  String get tournamentRegistrationConfirm;

  /// Submit button label while submitting
  ///
  /// In de, this message translates to:
  /// **'Sende …'**
  String get tournamentRegistrationSubmitting;

  /// Cancel button label
  ///
  /// In de, this message translates to:
  /// **'Abbrechen'**
  String get tournamentRegistrationCancel;

  /// Success snackbar after registration
  ///
  /// In de, this message translates to:
  /// **'Anmeldung gesendet.'**
  String get tournamentRegistrationSuccess;

  /// Tile action: open the tournament detail screen
  ///
  /// In de, this message translates to:
  /// **'Details'**
  String get tournamentCardDetails;

  /// Roster hint for a fixed team size
  ///
  /// In de, this message translates to:
  /// **'Wähle {count} Spieler für dein Team aus.'**
  String tournamentTeamRosterRangeFixed(int count);

  /// Roster hint for a team size range
  ///
  /// In de, this message translates to:
  /// **'Wähle zwischen {min} und {max} Spielern für dein Team aus.'**
  String tournamentTeamRosterRange(int min, int max);

  /// Shows how many roster members are currently selected
  ///
  /// In de, this message translates to:
  /// **'{count} ausgewählt'**
  String tournamentTeamRosterSelected(int count);

  /// Success message after a team registration
  ///
  /// In de, this message translates to:
  /// **'Team angemeldet.'**
  String get tournamentTeamRegistered;

  /// Heading above the list of registered roster members after a team registration
  ///
  /// In de, this message translates to:
  /// **'Folgende Mitglieder sind angemeldet:'**
  String get tournamentTeamRegisteredMembers;

  /// Button that closes the team-registration confirmation
  ///
  /// In de, this message translates to:
  /// **'Fertig'**
  String get tournamentTeamRegisterDone;

  /// Per-member badge in the team-registration confirmation
  ///
  /// In de, this message translates to:
  /// **'angemeldet'**
  String get tournamentTeamMemberRegistered;

  /// Tournament match list screen title
  ///
  /// In de, this message translates to:
  /// **'Spiele'**
  String get tournamentMatchListTitle;

  /// Empty state for match list
  ///
  /// In de, this message translates to:
  /// **'Noch keine Spiele geplant.'**
  String get tournamentMatchListEmpty;

  /// Round group header in match list
  ///
  /// In de, this message translates to:
  /// **'Runde {round}'**
  String tournamentMatchListRound(int round);

  /// Error banner when match list / detail fails to load
  ///
  /// In de, this message translates to:
  /// **'Spiele konnten nicht geladen werden'**
  String get tournamentMatchLoadError;

  /// Label for a BYE participant slot
  ///
  /// In de, this message translates to:
  /// **'BYE'**
  String get tournamentMatchBye;

  /// Status pill for scheduled matches
  ///
  /// In de, this message translates to:
  /// **'Geplant'**
  String get tournamentMatchStatusScheduled;

  /// Status pill for awaiting-results matches
  ///
  /// In de, this message translates to:
  /// **'Warten'**
  String get tournamentMatchStatusAwaiting;

  /// Status pill for disputed matches
  ///
  /// In de, this message translates to:
  /// **'Strittig'**
  String get tournamentMatchStatusDisputed;

  /// Status pill for finalized matches
  ///
  /// In de, this message translates to:
  /// **'Abgeschlossen'**
  String get tournamentMatchStatusFinalized;

  /// Status pill for organizer-overridden matches
  ///
  /// In de, this message translates to:
  /// **'Korrigiert'**
  String get tournamentMatchStatusOverridden;

  /// Status pill for voided matches
  ///
  /// In de, this message translates to:
  /// **'Ungültig'**
  String get tournamentMatchStatusVoided;

  /// Tournament match detail screen title
  ///
  /// In de, this message translates to:
  /// **'Spiel-Eingabe'**
  String get tournamentMatchDetailTitle;

  /// Header eyebrow on match detail showing round and slot
  ///
  /// In de, this message translates to:
  /// **'Runde {round} — Spiel {match}'**
  String tournamentMatchHeaderRound(int round, int match);

  /// Header showing the two opponents
  ///
  /// In de, this message translates to:
  /// **'{a} gegen {b}'**
  String tournamentMatchVersusHeader(String a, String b);

  /// Header text when match is a BYE
  ///
  /// In de, this message translates to:
  /// **'Freilos'**
  String get tournamentMatchByeHeader;

  /// Fallback label for a tournament participant whose server-projected display_name is missing (W3-T4).
  ///
  /// In de, this message translates to:
  /// **'Unbekannt'**
  String get tournamentParticipantUnknown;

  /// Consensus banner — current retry round indicator
  ///
  /// In de, this message translates to:
  /// **'Versuch {attempt} von {max}'**
  String tournamentMatchConsensusAttempt(int attempt, int max);

  /// Per-set header in the score input form
  ///
  /// In de, this message translates to:
  /// **'Satz {n}'**
  String tournamentMatchSetLabel(int n);

  /// Stepper label for team A basekubbs
  ///
  /// In de, this message translates to:
  /// **'Basekubbs Team A'**
  String get tournamentMatchBasekubbsALabel;

  /// Stepper label for team B basekubbs
  ///
  /// In de, this message translates to:
  /// **'Basekubbs Team B'**
  String get tournamentMatchBasekubbsBLabel;

  /// Toggle label for who finished the King
  ///
  /// In de, this message translates to:
  /// **'Königsstoss durch'**
  String get tournamentMatchKingLabel;

  /// Option: King finished by team A
  ///
  /// In de, this message translates to:
  /// **'Team A'**
  String get tournamentMatchKingByA;

  /// Option: King finished by team B
  ///
  /// In de, this message translates to:
  /// **'Team B'**
  String get tournamentMatchKingByB;

  /// Option: time ran out, no King finisher
  ///
  /// In de, this message translates to:
  /// **'Zeitablauf'**
  String get tournamentMatchKingByNone;

  /// Button to add another set row
  ///
  /// In de, this message translates to:
  /// **'Satz +'**
  String get tournamentMatchAddSet;

  /// Button to remove the last set row
  ///
  /// In de, this message translates to:
  /// **'Satz −'**
  String get tournamentMatchRemoveSet;

  /// Live-Vorschau heading on match detail
  ///
  /// In de, this message translates to:
  /// **'Aktueller Stand'**
  String get tournamentMatchLivePreviewLabel;

  /// Live-Vorschau score display
  ///
  /// In de, this message translates to:
  /// **'{a}:{b}'**
  String tournamentMatchLivePreviewScore(int a, int b);

  /// Live-Vorschau hint when no winner yet
  ///
  /// In de, this message translates to:
  /// **'Match noch offen'**
  String get tournamentMatchLivePreviewUndecided;

  /// Submit-score button
  ///
  /// In de, this message translates to:
  /// **'Einreichen'**
  String get tournamentMatchSubmitButton;

  /// Snackbar prefix when the propose-scores RPC fails
  ///
  /// In de, this message translates to:
  /// **'Senden fehlgeschlagen'**
  String get tournamentMatchSubmitError;

  /// Hint shown when match status is terminal
  ///
  /// In de, this message translates to:
  /// **'Dieses Spiel ist bereits abgeschlossen.'**
  String get tournamentMatchReadOnlyNotice;

  /// Label above the live match countdown clock
  ///
  /// In de, this message translates to:
  /// **'Restzeit'**
  String get tournamentMatchTimerLabel;

  /// Call-to-action shown when the pool-play match timer runs out
  ///
  /// In de, this message translates to:
  /// **'Zeit abgelaufen — Resultat eintragen'**
  String get tournamentMatchTimerExpiredCta;

  /// Call-to-action shown when a KO match with tiebreak runs out
  ///
  /// In de, this message translates to:
  /// **'Zeit abgelaufen — Tiebreak / Mighty-Finisher melden'**
  String get tournamentMatchTimerTiebreakCta;

  /// Inline badge shown once the tiebreak window has opened
  ///
  /// In de, this message translates to:
  /// **'Tiebreak läuft'**
  String get tournamentMatchTimerTiebreakActive;

  /// Prominent call-to-play banner pointing the participant to their pitch
  ///
  /// In de, this message translates to:
  /// **'Dein Platz: Pitch {pitch} — leg los!'**
  String tournamentMatchPitchCallTitle(String pitch);

  /// Opponent line under the pitch-call banner
  ///
  /// In de, this message translates to:
  /// **'Gegen {opponent}'**
  String tournamentMatchPitchCallVersus(String opponent);

  /// Button on the pitch-call banner that opens the match detail
  ///
  /// In de, this message translates to:
  /// **'Spiel öffnen'**
  String get tournamentMatchPitchCallAction;

  /// Action button label that opens the forfeit declaration sheet (DSCORE-63)
  ///
  /// In de, this message translates to:
  /// **'Forfeit erklären'**
  String get tournamentForfeitAction;

  /// Bottom-sheet title for the forfeit-declaration surface
  ///
  /// In de, this message translates to:
  /// **'Forfeit erklären'**
  String get tournamentForfeitSheetTitle;

  /// Radio-group label for the absent-side selection
  ///
  /// In de, this message translates to:
  /// **'Welche Seite ist nicht erschienen?'**
  String get tournamentForfeitAbsentSideLabel;

  /// Radio label for the A side in the forfeit sheet
  ///
  /// In de, this message translates to:
  /// **'Team A'**
  String get tournamentForfeitSideA;

  /// Radio label for the B side in the forfeit sheet
  ///
  /// In de, this message translates to:
  /// **'Team B'**
  String get tournamentForfeitSideB;

  /// Reason text-field label for the forfeit sheet
  ///
  /// In de, this message translates to:
  /// **'Begründung'**
  String get tournamentForfeitReasonLabel;

  /// Reason text-field hint enforcing the DSCORE-65 minimum
  ///
  /// In de, this message translates to:
  /// **'Mindestens 10 Zeichen'**
  String get tournamentForfeitReasonHint;

  /// Validation error when the reason is shorter than 10 chars
  ///
  /// In de, this message translates to:
  /// **'Begründung muss mindestens 10 Zeichen enthalten.'**
  String get tournamentForfeitReasonTooShort;

  /// Validation error when no absent side has been picked
  ///
  /// In de, this message translates to:
  /// **'Bitte abwesende Seite auswählen.'**
  String get tournamentForfeitSideRequired;

  /// Submit button label inside the forfeit sheet
  ///
  /// In de, this message translates to:
  /// **'Forfeit speichern'**
  String get tournamentForfeitSubmitButton;

  /// Snackbar shown when the forfeit RPC fails
  ///
  /// In de, this message translates to:
  /// **'Forfeit konnte nicht gespeichert werden: {error}'**
  String tournamentForfeitSubmitError(String error);

  /// Confirmation snackbar after a successful forfeit declaration
  ///
  /// In de, this message translates to:
  /// **'Forfeit gespeichert — Match abgeschlossen.'**
  String get tournamentForfeitSuccessToast;

  /// Validation error when a set has neither score nor king
  ///
  /// In de, this message translates to:
  /// **'Satz {n}: Eingabe fehlt.'**
  String tournamentMatchValidationEmpty(int n);

  /// Validation error per DSCORE-15 — king requires max basekubbs on winning side
  ///
  /// In de, this message translates to:
  /// **'Satz {n}: Königsstoss verlangt volle Basekubbs.'**
  String tournamentMatchValidationKingNeedsMax(int n);

  /// Snackbar shown when submission finalises the match
  ///
  /// In de, this message translates to:
  /// **'Match abgeschlossen'**
  String get tournamentMatchFinalizedToast;

  /// Snackbar shown when submission triggers a consensus retry
  ///
  /// In de, this message translates to:
  /// **'Eingaben weichen ab — Versuch {attempt} von {max}'**
  String tournamentMatchDisagreementToast(int attempt, int max);

  /// Snackbar shown when submission moves match to disputed
  ///
  /// In de, this message translates to:
  /// **'Strittig — Veranstalter benachrichtigt'**
  String get tournamentMatchDisputedToast;

  /// Standings screen title
  ///
  /// In de, this message translates to:
  /// **'Endrangliste'**
  String get tournamentStandingsTitle;

  /// Empty state for standings
  ///
  /// In de, this message translates to:
  /// **'Noch keine Ergebnisse.'**
  String get tournamentStandingsEmpty;

  /// Standings load error banner
  ///
  /// In de, this message translates to:
  /// **'Rangliste konnte nicht geladen werden'**
  String get tournamentStandingsLoadError;

  /// Standings column: rank
  ///
  /// In de, this message translates to:
  /// **'Rang'**
  String get tournamentStandingsRank;

  /// Standings column: player
  ///
  /// In de, this message translates to:
  /// **'Spieler'**
  String get tournamentStandingsPlayer;

  /// Standings column: total points
  ///
  /// In de, this message translates to:
  /// **'Total'**
  String get tournamentStandingsTotal;

  /// Standings column: wins
  ///
  /// In de, this message translates to:
  /// **'Siege'**
  String get tournamentStandingsWins;

  /// Standings column: Buchholz score
  ///
  /// In de, this message translates to:
  /// **'Buchholz'**
  String get tournamentStandingsBuchholz;

  /// Standings column: kubb difference
  ///
  /// In de, this message translates to:
  /// **'Kubb-Diff'**
  String get tournamentStandingsKubbDiff;

  /// Conflict screen app-bar title
  ///
  /// In de, this message translates to:
  /// **'Eingaben weichen ab'**
  String get tournamentConflictTitle;

  /// Conflict banner with current consensus round
  ///
  /// In de, this message translates to:
  /// **'Versuch {attempt} von 3 — Eingaben weichen ab'**
  String tournamentConflictAttempt(int attempt);

  /// Warning banner at consensus round 3
  ///
  /// In de, this message translates to:
  /// **'Letzter Versuch — bei Abweichung übernimmt der Veranstalter'**
  String get tournamentConflictLastAttemptWarning;

  /// Conflict comparison column A header
  ///
  /// In de, this message translates to:
  /// **'Eingabe Team A'**
  String get tournamentConflictColumnA;

  /// Conflict comparison column B header
  ///
  /// In de, this message translates to:
  /// **'Eingabe Team B'**
  String get tournamentConflictColumnB;

  /// Per-set heading inside the conflict comparison row
  ///
  /// In de, this message translates to:
  /// **'Satz {n}'**
  String tournamentConflictSetLabel(int n);

  /// Row label: basekubbs knocked by team A
  ///
  /// In de, this message translates to:
  /// **'Basekubbs A'**
  String get tournamentConflictBasekubbsA;

  /// Row label: basekubbs knocked by team B
  ///
  /// In de, this message translates to:
  /// **'Basekubbs B'**
  String get tournamentConflictBasekubbsB;

  /// Row label: set winner
  ///
  /// In de, this message translates to:
  /// **'Sieger'**
  String get tournamentConflictSetWinner;

  /// Primary CTA: open match detail to re-submit
  ///
  /// In de, this message translates to:
  /// **'Erneut eintragen'**
  String get tournamentConflictRetryButton;

  /// Secondary CTA: ask organizer to override
  ///
  /// In de, this message translates to:
  /// **'Veranstalter hinzuziehen'**
  String get tournamentConflictEscalateButton;

  /// Snackbar shown after the escalate button is tapped
  ///
  /// In de, this message translates to:
  /// **'Verlangen an Veranstalter weitergeleitet'**
  String get tournamentConflictEscalateToast;

  /// Empty-state hint when no proposals are available
  ///
  /// In de, this message translates to:
  /// **'Noch keine abweichenden Eingaben.'**
  String get tournamentConflictEmpty;

  /// No description provided for @tournamentOverrideEyebrow.
  ///
  /// In de, this message translates to:
  /// **'Strittiges Match'**
  String get tournamentOverrideEyebrow;

  /// No description provided for @tournamentOverrideTitle.
  ///
  /// In de, this message translates to:
  /// **'Veranstalter-Override'**
  String get tournamentOverrideTitle;

  /// No description provided for @tournamentOverrideProposalsHeader.
  ///
  /// In de, this message translates to:
  /// **'Bisherige Eingaben'**
  String get tournamentOverrideProposalsHeader;

  /// No description provided for @tournamentOverrideProposalsEmpty.
  ///
  /// In de, this message translates to:
  /// **'Keine Eingaben vorhanden.'**
  String get tournamentOverrideProposalsEmpty;

  /// No description provided for @tournamentOverrideFinalHeader.
  ///
  /// In de, this message translates to:
  /// **'Finaler Score'**
  String get tournamentOverrideFinalHeader;

  /// No description provided for @tournamentOverrideReasonHeader.
  ///
  /// In de, this message translates to:
  /// **'Begründung'**
  String get tournamentOverrideReasonHeader;

  /// No description provided for @tournamentOverrideReasonHint.
  ///
  /// In de, this message translates to:
  /// **'Warum wurde dieser Score festgelegt?'**
  String get tournamentOverrideReasonHint;

  /// No description provided for @tournamentOverrideReasonCounter.
  ///
  /// In de, this message translates to:
  /// **'{current}/{max}'**
  String tournamentOverrideReasonCounter(Object current, Object max);

  /// No description provided for @tournamentOverrideSubmitButton.
  ///
  /// In de, this message translates to:
  /// **'Entscheidung speichern'**
  String get tournamentOverrideSubmitButton;

  /// No description provided for @tournamentOverrideSubmitError.
  ///
  /// In de, this message translates to:
  /// **'Speichern fehlgeschlagen: {error}'**
  String tournamentOverrideSubmitError(Object error);

  /// No description provided for @tournamentOverrideStatusGate.
  ///
  /// In de, this message translates to:
  /// **'Nur strittige Matches können übersteuert werden.'**
  String get tournamentOverrideStatusGate;

  /// No description provided for @tournamentOverrideValidationReasonEmpty.
  ///
  /// In de, this message translates to:
  /// **'Begründung ist erforderlich'**
  String get tournamentOverrideValidationReasonEmpty;

  /// No description provided for @tournamentOverrideValidationScoreNotDecisive.
  ///
  /// In de, this message translates to:
  /// **'Score muss eindeutig sein (ein Team erreicht die nötigen Sätze)'**
  String get tournamentOverrideValidationScoreNotDecisive;

  /// No description provided for @tournamentOverrideNotAuthorized.
  ///
  /// In de, this message translates to:
  /// **'Nicht autorisiert'**
  String get tournamentOverrideNotAuthorized;

  /// Bracket view header label for the knockout phase
  ///
  /// In de, this message translates to:
  /// **'KO-Phase'**
  String get tournamentBracketPhaseKo;

  /// Bracket view label for the final round
  ///
  /// In de, this message translates to:
  /// **'Finale'**
  String get tournamentBracketPhaseFinal;

  /// Bracket view label for the semifinal round
  ///
  /// In de, this message translates to:
  /// **'Halbfinale'**
  String get tournamentBracketPhaseSemifinal;

  /// Bracket view label for the quarterfinal round
  ///
  /// In de, this message translates to:
  /// **'Viertelfinale'**
  String get tournamentBracketPhaseQuarterfinal;

  /// Bracket view label for generic round (e.g. Round of 16)
  ///
  /// In de, this message translates to:
  /// **'Runde der {n}'**
  String tournamentBracketPhaseRoundOf(int n);

  /// Bracket view label for the third-place playoff (bronze match)
  ///
  /// In de, this message translates to:
  /// **'Spiel um Platz 3'**
  String get tournamentBracketPhaseThirdPlace;

  /// Short label for the third-place playoff used in compact UI
  ///
  /// In de, this message translates to:
  /// **'Bronze'**
  String get tournamentBracketBronzeMatchShort;

  /// Label shown on a BYE slot in the KO bracket (U5)
  ///
  /// In de, this message translates to:
  /// **'Freilos'**
  String get tournamentBracketByeLabel;

  /// Tooltip on a BYE slot paraphrasing FR-FMT-11 in plain language (U6)
  ///
  /// In de, this message translates to:
  /// **'Spielfreilos für Top-Seeds aus der Vorrunde — wer in der Gruppenphase vorne lag, startet eine Runde später.'**
  String get tournamentBracketByeTooltip;

  /// Seed badge prefix shown on bracket cards
  ///
  /// In de, this message translates to:
  /// **'Seed {n}'**
  String tournamentBracketSeedPrefix(int n);

  /// AppBar title of the tournament bracket screen
  ///
  /// In de, this message translates to:
  /// **'KO-Bracket'**
  String get tournamentBracketTitle;

  /// Empty-state copy shown on the bracket screen while the tournament is still in the group phase
  ///
  /// In de, this message translates to:
  /// **'KO noch nicht gestartet'**
  String get tournamentBracketEmpty;

  /// Error-state copy shown when the bracket fetch fails
  ///
  /// In de, this message translates to:
  /// **'Bracket konnte nicht geladen werden'**
  String get tournamentBracketLoadError;

  /// Segmented-button label for the main single-elim tree section of a consolation bracket (ADR-0028, Modell B)
  ///
  /// In de, this message translates to:
  /// **'Hauptbaum'**
  String get tournamentBracketSectionMain;

  /// Fallback display name / segmented-button label for the consolation (Trostturnier) tree when no consolation_name is available (ADR-0028 §UI, DoD-06)
  ///
  /// In de, this message translates to:
  /// **'Trostturnier'**
  String get tournamentBracketConsolationLabel;

  /// Hint shown in the Hauptbaum section of a consolation bracket when the single-elim main tree is not carried by the consolation domain object (ADR-0028 §1.1)
  ///
  /// In de, this message translates to:
  /// **'Der Hauptbaum ist hier nicht verfügbar. Endplatzierungen 1–4 siehe Turnier-Detail.'**
  String get tournamentBracketMainTreeUnavailable;

  /// Title of the seeding editor screen
  ///
  /// In de, this message translates to:
  /// **'Seeding'**
  String get tournamentSeedingTitle;

  /// Eyebrow above the seeding editor title
  ///
  /// In de, this message translates to:
  /// **'KO-Setup'**
  String get tournamentSeedingEyebrow;

  /// Seed position label in the seeding editor list
  ///
  /// In de, this message translates to:
  /// **'Position {n}'**
  String tournamentSeedingPositionLabel(int n);

  /// Hint above the drag-to-reorder seeding list
  ///
  /// In de, this message translates to:
  /// **'Lange tippen und ziehen zum Umsortieren.'**
  String get tournamentSeedingDragHint;

  /// Badge shown on a seed that was manually overridden by the organizer
  ///
  /// In de, this message translates to:
  /// **'Manuell gesetzt'**
  String get tournamentSeedingOverrideLabel;

  /// Button that resets manual seed overrides back to the round-robin standings
  ///
  /// In de, this message translates to:
  /// **'Auf Gruppen-Reihenfolge zurücksetzen'**
  String get tournamentSeedingResetButton;

  /// Primary action on the seeding editor
  ///
  /// In de, this message translates to:
  /// **'Seeding speichern'**
  String get tournamentSeedingSaveButton;

  /// Action that commits the seeding and triggers the start_ko_phase RPC
  ///
  /// In de, this message translates to:
  /// **'KO starten'**
  String get tournamentSeedingStartKoButton;

  /// Action that derives the seed order from each participant's ELO via the tournament_autoseed_from_elo RPC
  ///
  /// In de, this message translates to:
  /// **'Auto-Seed aus ELO'**
  String get tournamentSeedingAutoSeedButton;

  /// Inline banner title shown when the save or start RPC fails
  ///
  /// In de, this message translates to:
  /// **'Aktion fehlgeschlagen'**
  String get tournamentSeedingErrorTitle;

  /// Placeholder shown when the auto-seed list is empty (group phase not finished)
  ///
  /// In de, this message translates to:
  /// **'Noch keine qualifizierten Teilnehmer.'**
  String get tournamentSeedingEmpty;

  /// Title of wizard step 4.5 asking whether the tournament counts for the league
  ///
  /// In de, this message translates to:
  /// **'Liga-Wertung'**
  String get tournamentWizardStep45Title;

  /// Switch label for league_eligible toggle (wizard step 4.5)
  ///
  /// In de, this message translates to:
  /// **'Dieses Turnier wertet für die Liga'**
  String get tournamentWizardLeagueEligibleLabel;

  /// Helper text under the league-eligible switch explaining the bronze-match default
  ///
  /// In de, this message translates to:
  /// **'Liga-Turniere spielen standardmässig das Spiel um Platz 3 — Rang 3 und 4 geben unterschiedliche Punkte.'**
  String get tournamentWizardLeagueEligibleHelper;

  /// Title of wizard step 5 for KO phase configuration
  ///
  /// In de, this message translates to:
  /// **'KO-Konfiguration'**
  String get tournamentWizardStep5Title;

  /// Label for the qualifier-count integer input (U1)
  ///
  /// In de, this message translates to:
  /// **'Anzahl Qualifikanten'**
  String get tournamentWizardQualifierCountLabel;

  /// Helper text for the power-of-two KO size selector
  ///
  /// In de, this message translates to:
  /// **'Wie viele Teams ziehen aus der Vorrunde in die KO-Phase ein? Nur Zweierpotenzen (4/8/16/32) — keine Freilose im Hauptbaum.'**
  String get tournamentWizardQualifierCountHelper;

  /// Title of wizard step 6 for tiebreaker reordering
  ///
  /// In de, this message translates to:
  /// **'Tiebreaker-Reihenfolge'**
  String get tournamentWizardStep6Title;

  /// Hint above the drag-to-reorder tiebreaker list
  ///
  /// In de, this message translates to:
  /// **'Lange tippen und ziehen, um die Reihenfolge der Entscheidungskriterien zu ändern.'**
  String get tournamentWizardTiebreakerHint;

  /// Button that resets the tiebreaker order to the spec default
  ///
  /// In de, this message translates to:
  /// **'Standard wiederherstellen'**
  String get tournamentWizardTiebreakerResetButton;

  /// Title of the in-app help section explaining the KO phase (U8)
  ///
  /// In de, this message translates to:
  /// **'Wie funktioniert der KO-Cut?'**
  String get tournamentKoHelpTitle;

  /// Body of the KO help section paraphrasing FR-FMT-11 in plain language (U8/U9)
  ///
  /// In de, this message translates to:
  /// **'Die besten Teams aus der Gruppenphase ziehen ins KO-Bracket ein. Passt die Zahl nicht zu einer Zweierpotenz (2, 4, 8, 16…), bekommen die bestplatzierten Teams ein Freilos in Runde 1. So bleibt das Bracket fair und ausgeglichen — international Standard.'**
  String get tournamentKoHelpBody;

  /// Link label opening the KO help section from the wizard
  ///
  /// In de, this message translates to:
  /// **'Mehr zum KO-Modus'**
  String get tournamentKoHelpLinkLabel;

  /// Inbox badge label for the team_invitation kind (M3.1-T6)
  ///
  /// In de, this message translates to:
  /// **'Team-Einladung'**
  String get inboxTeamInvitation;

  /// Inbox badge label for the team_member_removed kind (M3.1-T6)
  ///
  /// In de, this message translates to:
  /// **'Team-Änderung'**
  String get inboxTeamMemberRemoved;

  /// Inbox badge label for the team_dissolved kind (M3.1-T6)
  ///
  /// In de, this message translates to:
  /// **'Team aufgelöst'**
  String get inboxTeamDissolved;

  /// Team list screen app bar title (M3.1-T11)
  ///
  /// In de, this message translates to:
  /// **'Teams'**
  String get teamListTitle;

  /// Team list tab — teams the user is a member of
  ///
  /// In de, this message translates to:
  /// **'Meine Teams'**
  String get teamListTabMine;

  /// Team list tab — search public teams
  ///
  /// In de, this message translates to:
  /// **'Suchen'**
  String get teamListTabSearch;

  /// Placeholder in the team search input
  ///
  /// In de, this message translates to:
  /// **'Team suchen …'**
  String get teamListSearchPlaceholder;

  /// Empty state on the 'My Teams' tab
  ///
  /// In de, this message translates to:
  /// **'Du bist noch in keinem Team. Erstelle eins oder lass dich einladen.'**
  String get teamListEmpty;

  /// FAB label on the team list to create a new team
  ///
  /// In de, this message translates to:
  /// **'Team erstellen'**
  String get teamListCreateFab;

  /// Team create screen title (M3.1-T12)
  ///
  /// In de, this message translates to:
  /// **'Neues Team'**
  String get teamCreateTitle;

  /// Team create form — team name field label
  ///
  /// In de, this message translates to:
  /// **'Teamname'**
  String get teamCreateNameLabel;

  /// Team create form — league field label
  ///
  /// In de, this message translates to:
  /// **'Liga (optional)'**
  String get teamCreateLeagueLabel;

  /// Team create form — helper text under the league selector explaining the Swiss A/B/C league classes (Mängel #2.3, R19-A-03)
  ///
  /// In de, this message translates to:
  /// **'A · Profi, B · Haupt-Tour, C · Neben-Tour'**
  String get teamCreateLeagueHelper;

  /// Team create form — logo URL field label
  ///
  /// In de, this message translates to:
  /// **'Logo-URL (optional)'**
  String get teamCreateLogoUrlLabel;

  /// Team create form — country selector label
  ///
  /// In de, this message translates to:
  /// **'Land'**
  String get teamCreateCountryLabel;

  /// Primary submit button on the team create screen
  ///
  /// In de, this message translates to:
  /// **'Team anlegen'**
  String get teamCreateSubmitButton;

  /// Snackbar shown when team creation fails
  ///
  /// In de, this message translates to:
  /// **'Team konnte nicht erstellt werden — bitte erneut versuchen.'**
  String get teamCreateErrorGeneric;

  /// Snackbar shown when team creation fails because the user has no valid session (permission/auth error)
  ///
  /// In de, this message translates to:
  /// **'Du bist nicht angemeldet — bitte melde dich erneut an und versuche es nochmal.'**
  String get teamCreateErrorAuth;

  /// League line in the team detail header (M3.1-T13)
  ///
  /// In de, this message translates to:
  /// **'Liga: {league}'**
  String teamDetailHeaderLeague(String league);

  /// Section header for the core/pool members on the team detail screen
  ///
  /// In de, this message translates to:
  /// **'Stammspieler'**
  String get teamDetailPoolSection;

  /// Section header for guest members on the team detail screen
  ///
  /// In de, this message translates to:
  /// **'Gäste'**
  String get teamDetailGuestsSection;

  /// Action button to invite a new player to the team
  ///
  /// In de, this message translates to:
  /// **'Spieler einladen'**
  String get teamDetailInviteAction;

  /// Action button to add a guest player to the team
  ///
  /// In de, this message translates to:
  /// **'Gast hinzufügen'**
  String get teamDetailAddGuestAction;

  /// Action for a regular member to leave the team
  ///
  /// In de, this message translates to:
  /// **'Team verlassen'**
  String get teamDetailLeaveAction;

  /// Owner-only action to dissolve the team
  ///
  /// In de, this message translates to:
  /// **'Team auflösen'**
  String get teamDetailDissolveAction;

  /// Owner-only action to remove a member from the team
  ///
  /// In de, this message translates to:
  /// **'Aus Team entfernen'**
  String get teamDetailRemoveMember;

  /// Badge label for regular pool members on the team detail screen
  ///
  /// In de, this message translates to:
  /// **'Mitglied'**
  String get teamDetailMemberBadge;

  /// Badge label for guest members on the team detail screen
  ///
  /// In de, this message translates to:
  /// **'Gast'**
  String get teamDetailGuestBadge;

  /// Confirm dialog body when removing a member
  ///
  /// In de, this message translates to:
  /// **'Mitglied wirklich aus dem Team entfernen?'**
  String get teamDetailConfirmRemove;

  /// Confirm dialog body when the user leaves the team
  ///
  /// In de, this message translates to:
  /// **'Möchtest du das Team wirklich verlassen?'**
  String get teamDetailConfirmLeave;

  /// Confirm dialog body when the owner dissolves the team
  ///
  /// In de, this message translates to:
  /// **'Team wirklich auflösen? Alle Mitglieder werden entfernt.'**
  String get teamDetailConfirmDissolve;

  /// Team invitation list screen title (M3.1-T14)
  ///
  /// In de, this message translates to:
  /// **'Einladungen'**
  String get teamInvitationListTitle;

  /// Accept button on a team invitation row
  ///
  /// In de, this message translates to:
  /// **'Annehmen'**
  String get teamInvitationAccept;

  /// Decline button on a team invitation row
  ///
  /// In de, this message translates to:
  /// **'Ablehnen'**
  String get teamInvitationDecline;

  /// Empty state on the team invitation list
  ///
  /// In de, this message translates to:
  /// **'Keine offenen Einladungen.'**
  String get teamInvitationEmpty;

  /// Sender line on a team invitation row
  ///
  /// In de, this message translates to:
  /// **'Von {name}'**
  String teamInvitationFrom(String name);

  /// Header above the roster composition widget (M3.2-T13)
  ///
  /// In de, this message translates to:
  /// **'Roster zusammenstellen'**
  String get rosterComposeTitle;

  /// Section label for the pool list in the roster composition widget
  ///
  /// In de, this message translates to:
  /// **'Pool'**
  String get rosterComposePoolSection;

  /// Section label for the roster slots in the roster composition widget
  ///
  /// In de, this message translates to:
  /// **'Slots'**
  String get rosterComposeSlotsSection;

  /// Label for an individual roster slot
  ///
  /// In de, this message translates to:
  /// **'Slot {index}'**
  String rosterComposeSlotLabel(int index);

  /// Placeholder text shown for an unassigned roster slot
  ///
  /// In de, this message translates to:
  /// **'Leer'**
  String get rosterComposeSlotEmpty;

  /// Prompt shown after tapping a pool entry, asking which slot to fill
  ///
  /// In de, this message translates to:
  /// **'Welcher Slot?'**
  String get rosterComposeSelectSlotPrompt;

  /// Prompt shown after tapping a slot, asking which pool member to assign
  ///
  /// In de, this message translates to:
  /// **'Welcher Pool-Eintrag?'**
  String get rosterComposeSelectMemberPrompt;

  /// Tooltip shown on a pool entry that is already assigned to another team roster
  ///
  /// In de, this message translates to:
  /// **'Bereits in anderem Roster'**
  String get rosterComposeConflictTooltip;

  /// Validation warning when a roster contains only guests (FR-REG-12)
  ///
  /// In de, this message translates to:
  /// **'Mindestens ein registriertes Mitglied'**
  String get rosterComposeMinOneRegisteredWarning;

  /// Title of the register-team screen (M3.2-T14)
  ///
  /// In de, this message translates to:
  /// **'Team anmelden'**
  String get registerTeamTitle;

  /// Dropdown label for choosing which team to register
  ///
  /// In de, this message translates to:
  /// **'Team auswählen'**
  String get registerTeamSelectTeamLabel;

  /// Primary submit button on the register-team screen
  ///
  /// In de, this message translates to:
  /// **'Anmelden'**
  String get registerTeamSubmitButton;

  /// Hint shown when the user has no teams to register
  ///
  /// In de, this message translates to:
  /// **'Du hast noch kein Team. Lege zuerst eines an.'**
  String get registerTeamNoTeamsHint;

  /// Action button that navigates to the team-create screen
  ///
  /// In de, this message translates to:
  /// **'Team erstellen'**
  String get registerTeamCreateTeamAction;

  /// Snackbar/dialog message for server error BR_5_VIOLATION
  ///
  /// In de, this message translates to:
  /// **'Ein Mitglied ist bereits in einem anderen Roster dieses Turniers.'**
  String get registerTeamErrorBr5Violation;

  /// Server-side error MIN_ONE_REGISTERED (FR-REG-12)
  ///
  /// In de, this message translates to:
  /// **'Roster benötigt mindestens ein registriertes Mitglied.'**
  String get registerTeamErrorMinOneRegistered;

  /// Generic fallback error for the register-team screen
  ///
  /// In de, this message translates to:
  /// **'Anmeldung fehlgeschlagen — bitte erneut versuchen.'**
  String get registerTeamErrorGeneric;

  /// Title of the roster editor screen (M3.2-T15)
  ///
  /// In de, this message translates to:
  /// **'Roster bearbeiten'**
  String get rosterEditorTitle;

  /// Section header for the current roster on the editor screen
  ///
  /// In de, this message translates to:
  /// **'Aktuelles Roster'**
  String get rosterEditorCurrentSection;

  /// Action button to replace a single roster slot
  ///
  /// In de, this message translates to:
  /// **'Ersetzen'**
  String get rosterEditorReplaceAction;

  /// Title of the replace-slot dialog
  ///
  /// In de, this message translates to:
  /// **'Slot {index} ersetzen'**
  String rosterEditorReplaceDialogTitle(int index);

  /// Label for the optional reason field in the replace-slot dialog
  ///
  /// In de, this message translates to:
  /// **'Grund (optional)'**
  String get rosterEditorReplaceReasonLabel;

  /// Submit button in the replace-slot dialog
  ///
  /// In de, this message translates to:
  /// **'Übernehmen'**
  String get rosterEditorReplaceSubmit;

  /// Collapsible section header for past roster substitutions
  ///
  /// In de, this message translates to:
  /// **'Verlauf'**
  String get rosterEditorAuditSection;

  /// Empty state for the audit-trail section
  ///
  /// In de, this message translates to:
  /// **'Keine bisherigen Wechsel.'**
  String get rosterEditorAuditEmpty;

  /// Error message for server error ROSTER_LOCKED_DURING_MATCH (OD-M3-07)
  ///
  /// In de, this message translates to:
  /// **'Substitution nur zwischen Matches möglich.'**
  String get rosterEditorErrorLockedDuringMatch;

  /// Hint shown when the tournament is finalized and roster edits are disabled
  ///
  /// In de, this message translates to:
  /// **'Turnier ist abgeschlossen — Roster nicht mehr änderbar.'**
  String get rosterEditorFinalizedHint;

  /// Tab label for the roster view on the tournament detail screen (M3.2-T17)
  ///
  /// In de, this message translates to:
  /// **'Roster'**
  String get tournamentDetailRosterTab;

  /// Match header for team matches, showing roster names (R-M3-G3-Mitigation)
  ///
  /// In de, this message translates to:
  /// **'{teamName} (Roster: {members})'**
  String tournamentDetailMatchTeamHeader(String teamName, String members);

  /// Title of the pool phase configuration step (M3.3-T9)
  ///
  /// In de, this message translates to:
  /// **'Pool-Phase konfigurieren'**
  String get poolConfigTitle;

  /// Toggle to enable or disable the pool phase for the tournament
  ///
  /// In de, this message translates to:
  /// **'Pool-Phase aktivieren'**
  String get poolConfigEnableToggle;

  /// Label for the group count stepper in the pool configuration
  ///
  /// In de, this message translates to:
  /// **'Anzahl Gruppen'**
  String get poolConfigGroupCountLabel;

  /// Label for the qualifiers-per-group stepper in the pool configuration
  ///
  /// In de, this message translates to:
  /// **'Qualifikanten pro Gruppe'**
  String get poolConfigQualifiersLabel;

  /// Label for the team distribution strategy selector
  ///
  /// In de, this message translates to:
  /// **'Verteilungsstrategie'**
  String get poolConfigStrategyLabel;

  /// Strategy option — snake distribution
  ///
  /// In de, this message translates to:
  /// **'Schlangenlinie'**
  String get poolConfigStrategySnake;

  /// Strategy option — random distribution
  ///
  /// In de, this message translates to:
  /// **'Zufällig'**
  String get poolConfigStrategyRandom;

  /// Strategy option — seeded distribution
  ///
  /// In de, this message translates to:
  /// **'Nach Setzliste'**
  String get poolConfigStrategySeeded;

  /// Label for the optional random seed input shown for the random strategy
  ///
  /// In de, this message translates to:
  /// **'Zufalls-Seed (optional)'**
  String get poolConfigRandomSeedLabel;

  /// Title of the pool standings screen (M3.3-T10)
  ///
  /// In de, this message translates to:
  /// **'Pool-Tabelle'**
  String get poolStandingsTitle;

  /// Title of the cross-pool standings section
  ///
  /// In de, this message translates to:
  /// **'Gesamttabelle'**
  String get poolStandingsCrossPoolTitle;

  /// Header row for a single pool/group
  ///
  /// In de, this message translates to:
  /// **'Gruppe {name}'**
  String poolStandingsGroupHeader(String name);

  /// Column header for rank in the pool standings table
  ///
  /// In de, this message translates to:
  /// **'Platz'**
  String get poolStandingsRank;

  /// Column header for set wins in the pool standings table
  ///
  /// In de, this message translates to:
  /// **'Sätze'**
  String get poolStandingsSets;

  /// Column header for points in the pool standings table
  ///
  /// In de, this message translates to:
  /// **'Punkte'**
  String get poolStandingsPoints;

  /// Column header for the Buchholz tiebreaker in the pool standings table
  ///
  /// In de, this message translates to:
  /// **'Buchholz'**
  String get poolStandingsBuchholz;

  /// Badge label for teams that qualified for the KO phase
  ///
  /// In de, this message translates to:
  /// **'Qualifiziert'**
  String get poolStandingsQualified;

  /// Title of the tie resolution dialog (M3.3-T11)
  ///
  /// In de, this message translates to:
  /// **'Gleichstand auflösen'**
  String get tieResolveTitle;

  /// Explanation shown above the tie resolution list
  ///
  /// In de, this message translates to:
  /// **'Mehrere Teams stehen punktgleich. Lege die Reihenfolge manuell fest.'**
  String get tieResolveExplanation;

  /// Submit button on the tie resolution dialog
  ///
  /// In de, this message translates to:
  /// **'Reihenfolge übernehmen'**
  String get tieResolveSubmitButton;

  /// Cancel button on the tie resolution dialog
  ///
  /// In de, this message translates to:
  /// **'Abbrechen'**
  String get tieResolveCancelButton;

  /// Snackbar shown after the tie resolution was applied
  ///
  /// In de, this message translates to:
  /// **'Reihenfolge gespeichert.'**
  String get tieResolveSuccess;

  /// Tab label for the pool/groups view on the tournament detail screen (M3.3-T12)
  ///
  /// In de, this message translates to:
  /// **'Gruppen'**
  String get tournamentDetailGroups;

  /// Realtime banner state — websocket connected and receiving updates
  ///
  /// In de, this message translates to:
  /// **'Live'**
  String get realtimeLive;

  /// Realtime banner state — websocket unavailable, fallback polling is active
  ///
  /// In de, this message translates to:
  /// **'Offline — Polling aktiv'**
  String get realtimePolling;

  /// Realtime banner state — websocket connection is being established
  ///
  /// In de, this message translates to:
  /// **'Verbinde…'**
  String get realtimeConnecting;

  /// Title of the live dashboard screen showing all pitches in real time (M4.2-T12)
  ///
  /// In de, this message translates to:
  /// **'Live-Dashboard'**
  String get liveDashboardTitle;

  /// Button label to navigate to the live dashboard screen
  ///
  /// In de, this message translates to:
  /// **'Live-Dashboard öffnen'**
  String get liveDashboardOpenButton;

  /// Pitch status label — match is scheduled but not yet started
  ///
  /// In de, this message translates to:
  /// **'Geplant'**
  String get pitchStatusScheduled;

  /// Pitch status label — match is currently in progress
  ///
  /// In de, this message translates to:
  /// **'Live'**
  String get pitchStatusLive;

  /// Pitch status label — match is stalled / waiting on input
  ///
  /// In de, this message translates to:
  /// **'Wartend'**
  String get pitchStatusStalled;

  /// Pitch status label — match has a dispute that requires resolution
  ///
  /// In de, this message translates to:
  /// **'Strittig'**
  String get pitchStatusDisputed;

  /// Public tournament view tab label — schedule
  ///
  /// In de, this message translates to:
  /// **'Spielplan'**
  String get publicTournamentSchedule;

  /// Public tournament view tab label — standings
  ///
  /// In de, this message translates to:
  /// **'Rangliste'**
  String get publicTournamentStandings;

  /// Public tournament view tab label — knockout bracket
  ///
  /// In de, this message translates to:
  /// **'Bracket'**
  String get publicTournamentBracket;

  /// Toggle label for switching the public view into live mode
  ///
  /// In de, this message translates to:
  /// **'Live-Modus'**
  String get liveModeToggle;

  /// Message shown when a tournament is not publicly accessible
  ///
  /// In de, this message translates to:
  /// **'Dieses Turnier ist nicht öffentlich'**
  String get publicNotAvailable;

  /// Status label shown next to a score submission while the device is offline and the submission is queued for sync
  ///
  /// In de, this message translates to:
  /// **'ausstehend, wird übertragen'**
  String get scorePending;

  /// Dialog title shown when a queued score submission was rejected by the server because the opponent already corrected the score
  ///
  /// In de, this message translates to:
  /// **'Sync-Konflikt'**
  String get scoreConflictTitle;

  /// Body text in the sync conflict dialog explaining why the submission was rejected
  ///
  /// In de, this message translates to:
  /// **'Dein Vorschlag konnte nicht übertragen werden, weil der Gegner schon korrigiert hat. Bitte erneut eingeben.'**
  String get scoreConflictExplanation;

  /// Primary action in the sync conflict dialog that lets the user re-enter the score
  ///
  /// In de, this message translates to:
  /// **'Erneut eingeben'**
  String get scoreConflictReenterButton;

  /// Short offline indicator label used when no queue size is shown
  ///
  /// In de, this message translates to:
  /// **'Offline'**
  String get offlineBannerLabel;

  /// Offline banner showing the number of queued submissions waiting to be synced
  ///
  /// In de, this message translates to:
  /// **'{count, plural, one{Offline — 1 Submission ausstehend} other{Offline — {count} Submissions ausstehend}}'**
  String offlineBannerQueueSize(int count);

  /// Generic season label used as screen title and section header
  ///
  /// In de, this message translates to:
  /// **'Saison'**
  String get seasonTitle;

  /// Title of the league-admin screen that lists and manages seasons
  ///
  /// In de, this message translates to:
  /// **'Saisonen verwalten'**
  String get seasonAdminTitle;

  /// Button label that opens the create-season form
  ///
  /// In de, this message translates to:
  /// **'Neue Saison'**
  String get seasonCreateNew;

  /// Season status chip — draft, not yet opened for registrations
  ///
  /// In de, this message translates to:
  /// **'Entwurf'**
  String get seasonStatusDraft;

  /// Season status chip — open, accepting tournaments and registrations
  ///
  /// In de, this message translates to:
  /// **'Offen'**
  String get seasonStatusOpen;

  /// Season status chip — closed, no further changes
  ///
  /// In de, this message translates to:
  /// **'Abgeschlossen'**
  String get seasonStatusClosed;

  /// Title above the season standings table
  ///
  /// In de, this message translates to:
  /// **'Saison-Tabelle'**
  String get seasonStandingsTitle;

  /// Empty state when the standings table has no rows yet
  ///
  /// In de, this message translates to:
  /// **'Noch keine Daten'**
  String get seasonStandingsEmpty;

  /// Filter pill label for selecting the league within a season
  ///
  /// In de, this message translates to:
  /// **'Liga'**
  String get seasonLeagueFilter;

  /// Dropdown item that clears the league filter and shows all leagues
  ///
  /// In de, this message translates to:
  /// **'Alle Ligen'**
  String get leagueFilterAll;

  /// Action that assigns an existing tournament to the current season
  ///
  /// In de, this message translates to:
  /// **'Turnier zuordnen'**
  String get seasonAssignTournament;

  /// Pairing mode label for the Swiss-system tournament format
  ///
  /// In de, this message translates to:
  /// **'Schweizer System'**
  String get tournamentSwissSystem;

  /// Field label for the number of Swiss rounds
  ///
  /// In de, this message translates to:
  /// **'Runden'**
  String get tournamentSwissRounds;

  /// Field label for the Swiss-system tiebreak rule selector
  ///
  /// In de, this message translates to:
  /// **'Tiebreak'**
  String get tournamentSwissTiebreak;

  /// Warning hint shown when participant count exceeds the recommended Swiss-system size
  ///
  /// In de, this message translates to:
  /// **'Schweizer System ist optimiert für ≤ 64 Teilnehmer'**
  String get tournamentSwissOversize;

  /// Section label for the points-formula selector
  ///
  /// In de, this message translates to:
  /// **'Punkte-Modus'**
  String get tournamentPointsMode;

  /// Points mode option — use the platform-wide global formula
  ///
  /// In de, this message translates to:
  /// **'Globale Formel'**
  String get tournamentPointsGlobal;

  /// Points mode option — define a custom per-tournament formula
  ///
  /// In de, this message translates to:
  /// **'Eigene Punkte'**
  String get tournamentPointsCustom;

  /// Helper text under the custom-points option explaining that platform-admin approval is required
  ///
  /// In de, this message translates to:
  /// **'Muss vom Plattform-Admin freigegeben werden'**
  String get tournamentPointsCustomHint;

  /// Tri-toggle option in the set-card: king fell, scored by Team A. Sprint A W3-T2 / R11-F-01.
  ///
  /// In de, this message translates to:
  /// **'Team A'**
  String get setKingOutcomeTeamA;

  /// Tri-toggle option in the set-card: king fell, scored by Team B. Sprint A W3-T2 / R11-F-01.
  ///
  /// In de, this message translates to:
  /// **'Team B'**
  String get setKingOutcomeTeamB;

  /// Tri-toggle option in the set-card: king was not hit, set timed out, contributes 0:0 to the EKC tally. Sprint A W3-T2 / R11-F-01.
  ///
  /// In de, this message translates to:
  /// **'Keiner'**
  String get setKingOutcomeNone;

  /// App-shell banner shown while the score-submission outbox is draining queued rows to the server
  ///
  /// In de, this message translates to:
  /// **'Synchronisiere ausstehende Spielstände …'**
  String get outboxStatusFlushing;

  /// App-shell banner shown when an outbox row terminated with a conflict (e.g. STALE_CONSENSUS_ROUND) and the user must intervene
  ///
  /// In de, this message translates to:
  /// **'Spielstand konnte nicht synchronisiert werden.'**
  String get outboxStatusError;

  /// Banner shown while the realtime channel is reconnecting after an error
  ///
  /// In de, this message translates to:
  /// **'Verbinde mit Live-Updates …'**
  String get realtimeStatusReconnecting;

  /// Banner shown when the realtime channel has flipped to the polling fallback
  ///
  /// In de, this message translates to:
  /// **'Live-Updates pausiert, lade automatisch nach.'**
  String get realtimeStatusPolling;

  /// AUDIT §4.4 — App-shell pill label shown when the device has no connectivity and no last-sync timestamp is known yet
  ///
  /// In de, this message translates to:
  /// **'Offline'**
  String get offlineBannerOffline;

  /// AUDIT §4.4 — App-shell pill label shown while the outbox flusher is actively draining queued submissions
  ///
  /// In de, this message translates to:
  /// **'Sync läuft …'**
  String get offlineBannerSyncing;

  /// AUDIT §4.4 — App-shell pill label shown when offline, with the elapsed minutes since the last successful sync
  ///
  /// In de, this message translates to:
  /// **'{minutes, plural, =0{Offline · gerade synchronisiert} one{Offline · letzte Sync vor 1 min} other{Offline · letzte Sync vor {minutes} min}}'**
  String offlineBannerSyncedAgo(int minutes);

  /// AUDIT §2.4 slide 1 title — 8m distance training
  ///
  /// In de, this message translates to:
  /// **'Sniper-Training'**
  String get onboardingSlide1Title;

  /// AUDIT §2.4 slide 1 body — sniper mode explainer
  ///
  /// In de, this message translates to:
  /// **'Wurf-Konstanz trainieren — 4 bis 8 m Distanz, eigene Sessions, eigene Stats.'**
  String get onboardingSlide1Body;

  /// AUDIT §2.4 slide 2 title — match endgame trainer
  ///
  /// In de, this message translates to:
  /// **'Finisseur'**
  String get onboardingSlide2Title;

  /// AUDIT §2.4 slide 2 body — finisseur mode explainer
  ///
  /// In de, this message translates to:
  /// **'Das Match-Endspiel üben. 6 Stöcke, Field-, Base- und Königs-Phase.'**
  String get onboardingSlide2Body;

  /// AUDIT §2.4 slide 3 title — tournament module
  ///
  /// In de, this message translates to:
  /// **'Turniere & Ligen'**
  String get onboardingSlide3Title;

  /// AUDIT §2.4 slide 3 body — tournament module explainer
  ///
  /// In de, this message translates to:
  /// **'Turniere veranstalten, Spielpläne live verfolgen, Saisontabellen lesen.'**
  String get onboardingSlide3Body;

  /// AUDIT §2.4 slide 4 title — social module
  ///
  /// In de, this message translates to:
  /// **'Mit Freunden trainieren'**
  String get onboardingSlide4Title;

  /// AUDIT §2.4 slide 4 body — social module explainer
  ///
  /// In de, this message translates to:
  /// **'Teams gründen, Freunde einladen, gemeinsam besser werden.'**
  String get onboardingSlide4Body;

  /// Top-right skip button on the onboarding tour
  ///
  /// In de, this message translates to:
  /// **'Überspringen'**
  String get onboardingSkip;

  /// Bottom CTA on the onboarding tour, slides 1–3
  ///
  /// In de, this message translates to:
  /// **'Weiter'**
  String get onboardingNext;

  /// Bottom CTA on the last onboarding slide
  ///
  /// In de, this message translates to:
  /// **'Los geht\'s'**
  String get onboardingDone;

  /// Status chip: match is actively being played (Sprint-B W3-T4)
  ///
  /// In de, this message translates to:
  /// **'Live'**
  String get statusMatchLive;

  /// Status chip: tournament match score is disputed
  ///
  /// In de, this message translates to:
  /// **'Disput'**
  String get statusMatchDisputed;

  /// Status chip: match is finalized / finished
  ///
  /// In de, this message translates to:
  /// **'Fertig'**
  String get statusMatchFinished;

  /// Status chip: match is awaiting input (scheduled, pending invites, awaiting results)
  ///
  /// In de, this message translates to:
  /// **'Wartet'**
  String get statusMatchWaiting;

  /// Status chip: tournament match result was overridden by an organizer
  ///
  /// In de, this message translates to:
  /// **'Korrigiert'**
  String get statusMatchOverridden;

  /// Status chip: match was voided / cancelled
  ///
  /// In de, this message translates to:
  /// **'Abgebrochen'**
  String get statusMatchVoided;

  /// Status chip: tournament is still a draft (not published)
  ///
  /// In de, this message translates to:
  /// **'Entwurf'**
  String get statusTournamentDraft;

  /// Status chip: tournament is published but registration not yet open
  ///
  /// In de, this message translates to:
  /// **'Veröffentlicht'**
  String get statusTournamentPublished;

  /// Status chip: tournament registration is open
  ///
  /// In de, this message translates to:
  /// **'Anmeldung offen'**
  String get statusTournamentRegistrationOpen;

  /// Status chip: tournament registration is closed, waiting for start
  ///
  /// In de, this message translates to:
  /// **'Anmeldung geschlossen'**
  String get statusTournamentRegistrationClosed;

  /// Status chip: tournament is live / running
  ///
  /// In de, this message translates to:
  /// **'Live'**
  String get statusTournamentRunning;

  /// Status chip: tournament has finished
  ///
  /// In de, this message translates to:
  /// **'Beendet'**
  String get statusTournamentFinished;

  /// Status chip: tournament was aborted / cancelled
  ///
  /// In de, this message translates to:
  /// **'Abgebrochen'**
  String get statusTournamentCancelled;

  /// KubbEmptyState title on Home (no recent training sessions)
  ///
  /// In de, this message translates to:
  /// **'Noch keine Sessions'**
  String get emptySessionsTitle;

  /// KubbEmptyState body on Home (encourages first session)
  ///
  /// In de, this message translates to:
  /// **'Spiel ein paar Trainings — danach siehst du sie hier.'**
  String get emptySessionsBody;

  /// KubbEmptyState CTA on Home — opens the training sheet
  ///
  /// In de, this message translates to:
  /// **'Erste Session starten'**
  String get emptySessionsCta;

  /// KubbEmptyState title on Friends screen
  ///
  /// In de, this message translates to:
  /// **'Noch keine Freunde'**
  String get emptyFriendsTitle;

  /// KubbEmptyState body on Friends screen
  ///
  /// In de, this message translates to:
  /// **'Such oben nach einem Spielernamen und schick eine Anfrage.'**
  String get emptyFriendsBody;

  /// KubbEmptyState CTA on Friends screen — focuses the search field
  ///
  /// In de, this message translates to:
  /// **'Freund suchen'**
  String get emptyFriendsCta;

  /// KubbEmptyState title on Tournament list
  ///
  /// In de, this message translates to:
  /// **'Noch keine Turniere'**
  String get emptyTournamentsTitle;

  /// KubbEmptyState body on Tournament list
  ///
  /// In de, this message translates to:
  /// **'Erstelle dein erstes Turnier — Setup ist in unter zwei Minuten erledigt.'**
  String get emptyTournamentsBody;

  /// KubbEmptyState CTA on Tournament list — opens setup wizard
  ///
  /// In de, this message translates to:
  /// **'Turnier erstellen'**
  String get emptyTournamentsCta;

  /// KubbEmptyState title on Inbox
  ///
  /// In de, this message translates to:
  /// **'Postfach ist leer'**
  String get emptyInboxTitle;

  /// KubbEmptyState body on Inbox
  ///
  /// In de, this message translates to:
  /// **'Match-Einladungen und Freundschaftsanfragen landen hier.'**
  String get emptyInboxBody;

  /// KubbEmptyState CTA on Inbox — jumps to friends search
  ///
  /// In de, this message translates to:
  /// **'Freunde finden'**
  String get emptyInboxCta;

  /// AppBar title of the achievements screen
  ///
  /// In de, this message translates to:
  /// **'Erfolge'**
  String get achievementsScreenTitle;

  /// AppBar eyebrow above the achievements title
  ///
  /// In de, this message translates to:
  /// **'Profil'**
  String get achievementsScreenEyebrow;

  /// Section header listing badges the player already unlocked
  ///
  /// In de, this message translates to:
  /// **'Erspielt'**
  String get achievementsSectionEarned;

  /// Section header listing badges that are not yet unlocked
  ///
  /// In de, this message translates to:
  /// **'Noch offen'**
  String get achievementsSectionOpen;

  /// KubbEmptyState title shown when no badges have been earned yet
  ///
  /// In de, this message translates to:
  /// **'Noch keine Erfolge'**
  String get achievementsEmptyTitle;

  /// KubbEmptyState body on the achievements screen
  ///
  /// In de, this message translates to:
  /// **'Spiel ein paar Sniper-Sessions und Matches — Erfolge schalten sich automatisch frei.'**
  String get achievementsEmptyBody;

  /// KubbEmptyState CTA on the achievements screen — opens the sniper config
  ///
  /// In de, this message translates to:
  /// **'Sniper starten'**
  String get achievementsEmptyCta;

  /// Placeholder badge — first successful hit
  ///
  /// In de, this message translates to:
  /// **'Erster Treffer'**
  String get achievementsBadgeFirstHitTitle;

  /// Description of the first-hit placeholder badge
  ///
  /// In de, this message translates to:
  /// **'Treffe deinen ersten Kubb in einer Session.'**
  String get achievementsBadgeFirstHitDesc;

  /// Placeholder badge — cumulative 100 hits
  ///
  /// In de, this message translates to:
  /// **'100 Treffer'**
  String get achievementsBadgeHundredHitsTitle;

  /// Description of the 100-hits placeholder badge
  ///
  /// In de, this message translates to:
  /// **'Sammle 100 Treffer ueber alle Sessions.'**
  String get achievementsBadgeHundredHitsDesc;

  /// Placeholder badge — 10x streak
  ///
  /// In de, this message translates to:
  /// **'Serien-Schuetze'**
  String get achievementsBadgeStreakTitle;

  /// Description of the streak placeholder badge
  ///
  /// In de, this message translates to:
  /// **'Triff 10 Kubbs in Folge ohne Fehlwurf.'**
  String get achievementsBadgeStreakDesc;

  /// Placeholder badge — helicopter throws
  ///
  /// In de, this message translates to:
  /// **'Heli-Meister'**
  String get achievementsBadgeHeliTitle;

  /// Description of the heli placeholder badge
  ///
  /// In de, this message translates to:
  /// **'Lande 5 Helikopter-Wuerfe in einer Session.'**
  String get achievementsBadgeHeliDesc;

  /// Placeholder badge — finishing king hit
  ///
  /// In de, this message translates to:
  /// **'Koenigsmacher'**
  String get achievementsBadgeKingTitle;

  /// Description of the king placeholder badge
  ///
  /// In de, this message translates to:
  /// **'Gewinne ein Match mit dem letzten Wurf auf den Koenig.'**
  String get achievementsBadgeKingDesc;

  /// Status chip on a locked badge — describes the unlock condition
  ///
  /// In de, this message translates to:
  /// **'Bei {trigger} freigeschaltet'**
  String achievementsLockedChip(String trigger);

  /// Eyebrow shown above legal-section screen titles
  ///
  /// In de, this message translates to:
  /// **'Recht'**
  String get legalEyebrow;

  /// Title of the privacy policy screen
  ///
  /// In de, this message translates to:
  /// **'Datenschutzerklärung'**
  String get legalPrivacyPolicyTitle;

  /// Loading state while the privacy policy markdown asset is read
  ///
  /// In de, this message translates to:
  /// **'Datenschutzerklärung wird geladen…'**
  String get legalPrivacyPolicyLoading;

  /// Fallback message when the privacy policy asset cannot be loaded
  ///
  /// In de, this message translates to:
  /// **'Datenschutzerklärung ist gerade nicht verfügbar. Bitte später erneut versuchen.'**
  String get legalPrivacyPolicyUnavailable;

  /// Title of the imprint screen
  ///
  /// In de, this message translates to:
  /// **'Impressum'**
  String get legalImprintTitle;

  /// Loading state while the imprint markdown asset is read
  ///
  /// In de, this message translates to:
  /// **'Impressum wird geladen…'**
  String get legalImprintLoading;

  /// Fallback message when the imprint asset cannot be loaded
  ///
  /// In de, this message translates to:
  /// **'Impressum ist gerade nicht verfügbar. Bitte später erneut versuchen.'**
  String get legalImprintUnavailable;

  /// Settings row label that opens the privacy policy screen
  ///
  /// In de, this message translates to:
  /// **'Datenschutz'**
  String get settingsRowPrivacyPolicy;

  /// Settings row label that opens the imprint screen
  ///
  /// In de, this message translates to:
  /// **'Impressum'**
  String get settingsRowImprint;

  /// P6 shoot-out report/confirm screen — app bar title
  ///
  /// In de, this message translates to:
  /// **'Shoot-Out'**
  String get shootoutTitle;

  /// P6 shoot-out screen — app bar eyebrow
  ///
  /// In de, this message translates to:
  /// **'Quali-Entscheidung'**
  String get shootoutEyebrow;

  /// P6 shoot-out screen — explanatory intro text
  ///
  /// In de, this message translates to:
  /// **'Gleichstand an der Qualifikations-Grenze. Legt gemeinsam fest, in welcher Reihenfolge die beteiligten Teams den Shoot-Out gewonnen haben — bestes Team zuerst.'**
  String get shootoutIntro;

  /// P6 shoot-out screen — section header above the ordered list of tied teams
  ///
  /// In de, this message translates to:
  /// **'Beteiligte Teams'**
  String get shootoutParticipantsHeader;

  /// P6 shoot-out screen — hint how to reorder the tied teams
  ///
  /// In de, this message translates to:
  /// **'Reihenfolge per Pfeile anpassen — oben = Sieger.'**
  String get shootoutOrderHint;

  /// P6 shoot-out screen — 1-based rank prefix for an ordered team row
  ///
  /// In de, this message translates to:
  /// **'{rank}.'**
  String shootoutRankLabel(int rank);

  /// P6 shoot-out screen — tooltip/label to move a team up in the order
  ///
  /// In de, this message translates to:
  /// **'Nach oben'**
  String get shootoutMoveUp;

  /// P6 shoot-out screen — tooltip/label to move a team down in the order
  ///
  /// In de, this message translates to:
  /// **'Nach unten'**
  String get shootoutMoveDown;

  /// P6 shoot-out screen — primary action that reports the chosen winner ordering
  ///
  /// In de, this message translates to:
  /// **'Sieger melden'**
  String get shootoutReportAction;

  /// P6 shoot-out screen — action that confirms the reported winner ordering
  ///
  /// In de, this message translates to:
  /// **'Bestätigen'**
  String get shootoutConfirmAction;

  /// P6 shoot-out screen — banner shown once an ordering was reported and is awaiting confirmation
  ///
  /// In de, this message translates to:
  /// **'Eine Reihenfolge wurde gemeldet. Die andere Seite muss sie bestätigen.'**
  String get shootoutReportedBanner;

  /// P6 shoot-out screen — snackbar after a successful report
  ///
  /// In de, this message translates to:
  /// **'Sieger-Reihenfolge gemeldet'**
  String get shootoutReportedSnack;

  /// P6 shoot-out screen — snackbar after a successful confirmation
  ///
  /// In de, this message translates to:
  /// **'Shoot-Out bestätigt'**
  String get shootoutConfirmedSnack;

  /// P6 shoot-out screen — error message when report/confirm fails
  ///
  /// In de, this message translates to:
  /// **'Shoot-Out konnte nicht aktualisiert werden: {error}'**
  String shootoutError(String error);

  /// P6 shoot-out screen — empty state title when no open shoot-out remains
  ///
  /// In de, this message translates to:
  /// **'Kein offener Shoot-Out'**
  String get shootoutEmptyTitle;

  /// P6 shoot-out screen — empty state body
  ///
  /// In de, this message translates to:
  /// **'Für dieses Turnier ist aktuell kein Shoot-Out für dich offen.'**
  String get shootoutEmptyBody;

  /// P6 shoot-out screen — load error message
  ///
  /// In de, this message translates to:
  /// **'Shoot-Out konnte nicht geladen werden:\n{error}'**
  String shootoutLoadError(String error);

  /// Inbox detail — button that opens the shoot-out report/confirm screen
  ///
  /// In de, this message translates to:
  /// **'Shoot-Out öffnen'**
  String get shootoutInboxOpenAction;

  /// P6 shoot-out screen — friendly message for server INVALID_ORDER
  ///
  /// In de, this message translates to:
  /// **'Die Reihenfolge muss alle beteiligten Teams genau einmal enthalten.'**
  String get shootoutErrorInvalidOrder;

  /// P6 shoot-out screen — friendly message for server ORDER_MISMATCH
  ///
  /// In de, this message translates to:
  /// **'Die Reihenfolge weicht von der gemeldeten ab. Bitte bestätige die gemeldete Reihenfolge unverändert.'**
  String get shootoutErrorOrderMismatch;

  /// P6 shoot-out screen — friendly message for server NOT_AUTHORISED
  ///
  /// In de, this message translates to:
  /// **'Du gehörst nicht zu diesem Shoot-Out und kannst ihn nicht bearbeiten.'**
  String get shootoutErrorNotAuthorised;

  /// P6 shoot-out screen — friendly message for server ALREADY_RESOLVED
  ///
  /// In de, this message translates to:
  /// **'Dieser Shoot-Out wurde bereits entschieden.'**
  String get shootoutErrorAlreadyResolved;

  /// P6 shoot-out screen — friendly message for server NOT_REPORTED
  ///
  /// In de, this message translates to:
  /// **'Es wurde noch keine Reihenfolge gemeldet, die du bestätigen könntest.'**
  String get shootoutErrorNotReported;

  /// P6 shoot-out screen — friendly message when the reporter tries to self-confirm
  ///
  /// In de, this message translates to:
  /// **'Die gemeldete Reihenfolge muss von der anderen Seite bestätigt werden.'**
  String get shootoutErrorSelfConfirm;

  /// P6 shoot-out screen — read-only hint shown to the confirming side (order is locked)
  ///
  /// In de, this message translates to:
  /// **'Die gemeldete Reihenfolge bestätigen — bestes Team zuerst.'**
  String get shootoutOrderHintReadonly;

  /// K26: placeholder shown for an empty/unset optional field in the summary review
  ///
  /// In de, this message translates to:
  /// **'—'**
  String get tournamentWizardSummaryPlaceholder;

  /// K26: summary section heading for the master-data step
  ///
  /// In de, this message translates to:
  /// **'Stammdaten'**
  String get tournamentWizardSummarySectionStammdaten;

  /// K26: summary section heading for the participants step
  ///
  /// In de, this message translates to:
  /// **'Teilnehmer'**
  String get tournamentWizardSummarySectionParticipants;

  /// K26: summary section heading for the prelim step
  ///
  /// In de, this message translates to:
  /// **'Vorrunde'**
  String get tournamentWizardSummarySectionVorrunde;

  /// K26: summary section heading for the KO step
  ///
  /// In de, this message translates to:
  /// **'K.-o.'**
  String get tournamentWizardSummarySectionKo;

  /// K26/ERR-1: heading of the validation-issue list shown when the draft is invalid
  ///
  /// In de, this message translates to:
  /// **'Turnier kann nicht angelegt werden'**
  String get tournamentWizardSummaryErrorTitle;

  /// K26: summary label for the team size (min/max players per team)
  ///
  /// In de, this message translates to:
  /// **'Teamgrösse'**
  String get tournamentWizardSummaryTeamSizeLabel;

  /// K26: summary value for a fixed team size
  ///
  /// In de, this message translates to:
  /// **'{size} (fix)'**
  String tournamentWizardSummaryTeamSizeFixed(int size);

  /// K26: summary value for a variable team size range
  ///
  /// In de, this message translates to:
  /// **'{min}–{max}'**
  String tournamentWizardSummaryTeamSizeRange(int min, int max);

  /// K26: summary value 'yes' (e.g. PDF present)
  ///
  /// In de, this message translates to:
  /// **'Ja'**
  String get tournamentWizardSummaryYes;

  /// K26: summary value 'no' (e.g. PDF not present)
  ///
  /// In de, this message translates to:
  /// **'Nein'**
  String get tournamentWizardSummaryNo;

  /// K26: summary value for the entry fee (amount + currency)
  ///
  /// In de, this message translates to:
  /// **'{amount} {currency}'**
  String tournamentWizardSummaryFee(String amount, String currency);

  /// K26: summary value when there is no entry fee
  ///
  /// In de, this message translates to:
  /// **'Gratis'**
  String get tournamentWizardSummaryFeeFree;

  /// K26: summary value for the EKC scoring system
  ///
  /// In de, this message translates to:
  /// **'EKC'**
  String get tournamentWizardSummaryScoringEkc;

  /// K26: summary value for the classic scoring system
  ///
  /// In de, this message translates to:
  /// **'Klassisch'**
  String get tournamentWizardSummaryScoringClassic;

  /// K26: summary label for the active rule variants
  ///
  /// In de, this message translates to:
  /// **'Regel-Varianten'**
  String get tournamentWizardSummaryRulesLabel;

  /// K26: summary value when no rule variant toggle is active
  ///
  /// In de, this message translates to:
  /// **'Keine Sonderregeln'**
  String get tournamentWizardSummaryRulesNone;

  /// K26: summary label for whether a rules PDF was uploaded
  ///
  /// In de, this message translates to:
  /// **'Regelwerk-PDF'**
  String get tournamentWizardSummaryPdfRulesLabel;

  /// K26: summary label for whether a site-map PDF was uploaded
  ///
  /// In de, this message translates to:
  /// **'Lageplan-PDF'**
  String get tournamentWizardSummaryPdfSiteMapLabel;

  /// K26: summary label for the organiser contact (name + phone)
  ///
  /// In de, this message translates to:
  /// **'Kontakt'**
  String get tournamentWizardSummaryContactLabel;

  /// K26: summary label for the participant info free-text blocks
  ///
  /// In de, this message translates to:
  /// **'Infotexte'**
  String get tournamentWizardSummaryInfoLabel;

  /// K26: summary value counting the filled participant info texts
  ///
  /// In de, this message translates to:
  /// **'{count} hinterlegt'**
  String tournamentWizardSummaryInfoCount(int count);

  /// K26: summary label for the prelim format (group phase vs Schoch)
  ///
  /// In de, this message translates to:
  /// **'Format'**
  String get tournamentWizardSummaryFormatLabel;

  /// K26: summary label for the prelim match time limit in minutes
  ///
  /// In de, this message translates to:
  /// **'Match-Zeit (Min.)'**
  String get tournamentWizardSummaryMatchTimeLabel;

  /// K26: summary label for the configured pitch count
  ///
  /// In de, this message translates to:
  /// **'Pitches'**
  String get tournamentWizardSummaryPitchesLabel;

  /// K26: summary label for the KO system (single-out / double / consolation)
  ///
  /// In de, this message translates to:
  /// **'KO-System'**
  String get tournamentWizardSummaryKoTypeLabel;

  /// K26: summary value for the single-out KO system
  ///
  /// In de, this message translates to:
  /// **'Single-Out'**
  String get tournamentWizardSummaryKoTypeSingle;

  /// K26: summary value for the double-elimination KO system
  ///
  /// In de, this message translates to:
  /// **'Double-Elimination'**
  String get tournamentWizardSummaryKoTypeDouble;

  /// K26: summary value for the consolation/Trostturnier KO system
  ///
  /// In de, this message translates to:
  /// **'Trostturnier'**
  String get tournamentWizardSummaryKoTypeConsolation;

  /// K26: summary label for the KO bracket size (qualifier count)
  ///
  /// In de, this message translates to:
  /// **'Bracket-Grösse'**
  String get tournamentWizardSummaryKoSizeLabel;

  /// K26: summary label for the per-round KO rules short form
  ///
  /// In de, this message translates to:
  /// **'Per-Runde-Regeln'**
  String get tournamentWizardSummaryKoRoundsLabel;

  /// K26: summary short form for one KO round (round number + best-of from its max sets), joined by '·'
  ///
  /// In de, this message translates to:
  /// **'R{round}: Bo{maxSets}'**
  String tournamentWizardSummaryKoRoundEntry(int round, int maxSets);

  /// K26: summary label for the KO seeding source
  ///
  /// In de, this message translates to:
  /// **'Seeding-Quelle'**
  String get tournamentWizardSummarySeedingLabel;

  /// K26: summary value for automatic seeding from the prelim
  ///
  /// In de, this message translates to:
  /// **'Automatisch aus Vorrunde'**
  String get tournamentWizardSummarySeedingAuto;

  /// K26: summary value for manual seeding
  ///
  /// In de, this message translates to:
  /// **'Manuell festlegen'**
  String get tournamentWizardSummarySeedingManual;

  /// K26: summary label for the consolation direct-starter count
  ///
  /// In de, this message translates to:
  /// **'Direkt ins Trostturnier'**
  String get tournamentWizardSummaryConsolationDirectLabel;
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
      <String>['de'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
