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
  /// **'Brosi\'s Kubb'**
  String get homeAppTitle;

  /// Eyebrow above greeting on home
  ///
  /// In de, this message translates to:
  /// **'Brosi\'s Kubb'**
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

  /// Reset sessions row label
  ///
  /// In de, this message translates to:
  /// **'Sessions zurücksetzen'**
  String get settingsRowResetSessions;

  /// Reset sessions row subtitle
  ///
  /// In de, this message translates to:
  /// **'alle Trainings-Sessions löschen'**
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
  /// **'Alle Daten bleiben lokal auf deinem Gerät. Die App sendet nichts an externe Server.'**
  String get settingsPrivacyBody;

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
  /// **'Alle Trainings-Sessions werden unwiderruflich gelöscht. Dein Profil bleibt bestehen.'**
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

  /// App brand name on SignInScreen
  ///
  /// In de, this message translates to:
  /// **'Brosi\'s Kubb'**
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
