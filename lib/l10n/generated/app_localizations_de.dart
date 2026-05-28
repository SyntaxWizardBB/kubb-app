// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'Kubb';

  @override
  String get welcomeMessage => 'Willkommen — Projekt-Setup läuft.';

  @override
  String get onboardingGreeting => 'Willkommen';

  @override
  String get onboardingTitle => 'Wie heisst du?';

  @override
  String get onboardingHint => 'z.B. Lukas';

  @override
  String get onboardingConfirm => 'Weiter';

  @override
  String get onboardingCreateError =>
      'Profil konnte nicht erstellt werden — bitte erneut versuchen.';

  @override
  String get profileTitle => 'Profil';

  @override
  String get profileNotLoaded => 'Kein Profil';

  @override
  String get profileDeviceLabel => 'Geräte-ID';

  @override
  String get profileSinceLabel => 'Mitglied seit';

  @override
  String get profileEditButton => 'Bearbeiten';

  @override
  String get profileSaveButton => 'Speichern';

  @override
  String get profileCancelButton => 'Abbrechen';

  @override
  String get profileNameLabel => 'Anzeigename';

  @override
  String get profileColorLabel => 'Avatar-Farbe';

  @override
  String get profileUpdateError =>
      'Profil konnte nicht gespeichert werden — bitte erneut versuchen.';

  @override
  String get settingsTitle => 'Einstellungen';

  @override
  String get settingsLanguage => 'Sprache';

  @override
  String get settingsLanguageValue => 'Deutsch';

  @override
  String get settingsTheme => 'Erscheinungsbild';

  @override
  String get settingsHeli => 'Helikopter zählen';

  @override
  String get settingsVibration => 'Vibration';

  @override
  String get settingsLongDubbie => 'Long Dubbie zählen';

  @override
  String get settingsPenaltyKubb => 'Strafkubb zählen';

  @override
  String get settingsKingThrow => 'Königswurf zählen';

  @override
  String get settingsAllowContinue => 'Über Stock 6 hinaus weiterspielen';

  @override
  String get settingsAllowContinueSub =>
      'Nach Stock 6 weiterspielen bis fertig';

  @override
  String get settingsFinisseurSection => 'Finisseur';

  @override
  String get themeLight => 'Hell';

  @override
  String get themeDark => 'Dunkel';

  @override
  String get themeHighContrast => 'Sonnenlicht';

  @override
  String settingsVersion(String version, String build) {
    return 'Version $version ($build)';
  }

  @override
  String get trainingSheetEyebrow => 'Neue Session';

  @override
  String get trainingSheetTitle => 'Welcher Modus?';

  @override
  String get trainingSheetStatsLink => 'Statistik anzeigen';

  @override
  String get modeSniperTitle => 'Sniper-Training';

  @override
  String get modeSniperSubtitle => 'Trefferquote · Konstanz';

  @override
  String get modeFinisseurTitle => 'Finisseur';

  @override
  String get modeFinisseurSubtitle => 'Match-Endspiel · 6 Stöcke';

  @override
  String get modeFinisseurComingSoon => 'In Vorbereitung';

  @override
  String get homeModeTournamentTitle => 'Turnier';

  @override
  String get homeModeTournamentSubtitle => 'Mehrere Teams · Tabelle';

  @override
  String get finisseurConfigEyebrow => 'Finisseur';

  @override
  String get finisseurConfigTitle => 'Konfiguration';

  @override
  String get finisseurConfigFieldLabel => 'Feldkubbs (eingeworfen)';

  @override
  String finisseurConfigBaseLabel(int max) {
    return 'Basiskubbs · max $max';
  }

  @override
  String finisseurConfigConstraint(int current) {
    return 'Total maximal 10 Kubbs · Basis maximal 5. Aktuell $current / 10.';
  }

  @override
  String get finisseurConfigPresets => 'Presets';

  @override
  String get finisseurConfigPresetStandard => 'Standard';

  @override
  String get finisseurConfigPresetEven => '5/5';

  @override
  String get finisseurConfigPresetAllField => '10/0';

  @override
  String get finisseurConfigPresetLate => 'Spät';

  @override
  String finisseurConfigPreviewSubtitle(int field, int base) {
    return '$field / $base · 6 Stöcke';
  }

  @override
  String get finisseurConfigStartButton => 'Finisseur starten';

  @override
  String finisseurStickTitle(int n) {
    return 'Stock $n / 6';
  }

  @override
  String finisseurStickEyebrow(int field, int base) {
    return 'Finisseur · $field/$base';
  }

  @override
  String get finisseurStickRemainingField => 'Feldkubbs übrig';

  @override
  String get finisseurStickRemainingBase => 'Basiskubbs übrig';

  @override
  String get finisseurStickFieldHeader => 'Feldkubbs umgeworfen';

  @override
  String finisseurStickFieldRange(int max) {
    return '0–$max';
  }

  @override
  String get finisseurStickFieldEmpty =>
      'keine Feldkubbs mehr — direkt 8m oder König';

  @override
  String get finisseurStick8mLabel => '8m-Treffer';

  @override
  String get finisseurStick8mSub => 'Wurf auf Basiskubb';

  @override
  String get finisseurStickLongDubbieLabel => 'Long Dubbie';

  @override
  String get finisseurStickLongDubbieSub => 'Feldkubb + Basiskubb in einem';

  @override
  String get finisseurStickHeliLabel => 'Helikopter';

  @override
  String get finisseurStickHeliSub => 'ungültig, Stock weg';

  @override
  String get finisseurStickKingLabel => 'Königswurf';

  @override
  String get finisseurStickKingSubDefault => 'am Ende';

  @override
  String get finisseurStickKingPosition => 'Position';

  @override
  String get finisseurStickKingOutcome => 'Outcome';

  @override
  String get finisseurStickKingOben => 'oben';

  @override
  String get finisseurStickKingUnten => 'unten';

  @override
  String get finisseurStickKingHit => 'Treffer';

  @override
  String get finisseurStickKingMiss => 'verfehlt';

  @override
  String get finisseurStickPenaltyHeader => 'Strafkubbs (vom letzten Halbsatz)';

  @override
  String finisseurStickPenaltyMeta(int sum, int base) {
    return '$sum / $base umgeworfen';
  }

  @override
  String get finisseurStickPenaltyFirst => '1× geworfen';

  @override
  String get finisseurStickPenaltyFirstSub => 'erster Strafkubb-Wurf';

  @override
  String get finisseurStickPenaltySecond => '2× geworfen';

  @override
  String get finisseurStickPenaltySecondSub => 'zweiter Strafkubb-Wurf';

  @override
  String finisseurStickNextStock(int n) {
    return 'Stock $n';
  }

  @override
  String get finisseurStickFinish => 'Session abschliessen';

  @override
  String get finisseurStickFinishStick => 'Stock abschliessen';

  @override
  String get continueDecisionTitle => '6 Stöcke verbraucht';

  @override
  String get continueDecisionBody => 'Möchtest du bis zum Ende weiterspielen?';

  @override
  String get continueDecisionContinue => 'Weiterspielen';

  @override
  String get continueDecisionGiveUp => 'Aufgeben';

  @override
  String get finisseurStickBasePadHeader => 'Wurf auf Basiskubb';

  @override
  String get finisseurStickBasePadHit => 'Treffer';

  @override
  String get finisseurStickBasePadMiss => 'Verfehlt';

  @override
  String get finisseurStickPenaltyLabel => 'Strafkubb';

  @override
  String get finisseurStickPenaltySub => 'Strafwurf umgeworfen';

  @override
  String get finisseurAbortConfirmTitle => 'Session verwerfen?';

  @override
  String get finisseurAbortConfirmBody =>
      'Die bisherigen Stöcke werden gelöscht. Trotzdem zurück?';

  @override
  String get finisseurAbortConfirmStay => 'Weitertrainieren';

  @override
  String get finisseurAbortConfirmDiscard => 'Verwerfen';

  @override
  String get finisseurSummarySuccess => 'Sauber finished';

  @override
  String get finisseurSummaryFail => 'Nicht geschafft';

  @override
  String finisseurSummarySticksUsed(int n) {
    return '$n / 6';
  }

  @override
  String finisseurSummarySticksUsedSubtitle(String duration) {
    return 'Stöcke benötigt · $duration';
  }

  @override
  String finisseurSummaryOverstickSubtitle(String duration) {
    return 'Stöcke benötigt (Verlängerung) · $duration';
  }

  @override
  String get finisseurSummaryKingRow => 'Königswurf';

  @override
  String finisseurSummaryKingHit(String position) {
    return '$position durch · Treffer';
  }

  @override
  String get finisseurSummaryKingMiss => 'verfehlt';

  @override
  String get finisseurSummaryKingNone => 'kein Wurf';

  @override
  String get finisseurSummaryPenalties => 'Strafkubbs';

  @override
  String get finisseurSummaryHeli => 'Heli';

  @override
  String get finisseurSummaryModeLabel => 'Modus';

  @override
  String finisseurSummaryConfig(int field, int base) {
    return 'Finisseur · $field/$base';
  }

  @override
  String finisseurRecentSubtitle(int field, int base, int sticks, String when) {
    return '$field/$base · $sticks Stöcke · $when';
  }

  @override
  String get homeAppTitle => 'Brosi\'s Kubb';

  @override
  String get homeEyebrow => 'Brosi\'s Kubb';

  @override
  String homeGreeting(String name) {
    return 'Hallo, $name.';
  }

  @override
  String get homeGreetingFallback => 'Hallo.';

  @override
  String get homeTournierEyebrow => 'Tournier';

  @override
  String get homeTournierTitle => 'Match-Modus';

  @override
  String get homeTournierComingSoon => 'In Vorbereitung';

  @override
  String get homeTournierTapToast => 'In Vorbereitung';

  @override
  String get homeNewsEyebrow => 'News · Kubbtour.ch';

  @override
  String get homeNewsTitle => 'Saison 2026 — Termine sind raus';

  @override
  String get homeNewsSubtitle => 'tippen für alle Turniere & Anmeldung';

  @override
  String get homeRecentTitle => 'Zuletzt';

  @override
  String get homeFabLabel => 'Training';

  @override
  String get sniperConfigEyebrow => 'Sniper-Training';

  @override
  String get sniperConfigTitle => 'Einstellungen';

  @override
  String get sniperConfigDistanceLabel => 'Distanz';

  @override
  String get sniperConfigTargetLabel => 'Ziel-Wurfzahl';

  @override
  String get sniperConfigTargetNone => 'kein Ziel';

  @override
  String get sniperConfigTargetCustomHint => 'Eigener Wert';

  @override
  String get sniperConfigStartButton => 'Sniper starten';

  @override
  String get sniperCounterHit => 'Treffer';

  @override
  String get sniperCounterMiss => 'Miss';

  @override
  String get sniperCounterHeli => 'Heli';

  @override
  String sniperRemaining(int count) {
    return 'noch $count Würfe';
  }

  @override
  String get sniperBlindHint => 'Trefferzahl verdeckt — du wirfst blind.';

  @override
  String get sniperEndButton => 'Session beenden';

  @override
  String get sniperAbortButton => 'Abbrechen';

  @override
  String get abortDialogTitle => 'Session abbrechen?';

  @override
  String get abortDialogContent =>
      'Möchtest du die bisherige Session speichern oder verwerfen?';

  @override
  String get abortDialogCancel => 'Zurück';

  @override
  String get abortDialogDiscard => 'Verwerfen';

  @override
  String get abortDialogSave => 'Speichern';

  @override
  String get summaryEyebrow => 'Sniper-Training';

  @override
  String get summaryTitle => 'Zusammenfassung';

  @override
  String get summaryHitRateLabel => 'Trefferquote';

  @override
  String get summaryHits => 'Treffer';

  @override
  String get summaryMisses => 'Miss';

  @override
  String get summaryHelis => 'Heli';

  @override
  String get summaryDistance => 'Distanz';

  @override
  String get summaryDuration => 'Dauer';

  @override
  String get summarySave => 'Speichern';

  @override
  String get summaryDiscard => 'Verwerfen';

  @override
  String get summaryRestart => 'Neu starten';

  @override
  String get crashRecoveryTitle => 'Letzte Session unterbrochen';

  @override
  String crashRecoveryContent(String date) {
    return 'Eine Session vom $date ist noch offen. Was möchtest du tun?';
  }

  @override
  String get crashRecoveryResume => 'Fortsetzen';

  @override
  String get crashRecoverySave => 'Als beendet speichern';

  @override
  String get crashRecoveryDiscard => 'Verwerfen';

  @override
  String get bootstrapErrorTitle => 'App konnte nicht starten';

  @override
  String get bootstrapErrorBody =>
      'Bitte App neu starten. Wenn das Problem bleibt, melde dich beim Support.';

  @override
  String get statsTitle => 'Statistik';

  @override
  String get statsEyebrow => 'Profil';

  @override
  String get statsFilterDistance => 'Distanz';

  @override
  String get statsFilterAllDistances => 'Alle';

  @override
  String get statsFilterDateRange => 'Zeitraum';

  @override
  String get statsFilterTitle => 'Filter';

  @override
  String get statsFilterApply => 'Anwenden';

  @override
  String get statsFilterReset => 'Zurücksetzen';

  @override
  String statsFilterDistanceRange(String lo, String hi) {
    return 'Distanz $lo–$hi m';
  }

  @override
  String statsFilterFieldRange(int lo, int hi) {
    return 'Feldkubbs $lo–$hi';
  }

  @override
  String statsFilterBaseRange(int lo, int hi) {
    return 'Basiskubbs $lo–$hi';
  }

  @override
  String get statsFilterFinisseurField => 'Feldkubbs';

  @override
  String get statsFilterFinisseurBase => 'Basiskubbs';

  @override
  String get statsRangeAll => 'Gesamt';

  @override
  String get statsRangeLast7Days => '7 Tage';

  @override
  String get statsRangeLast30Days => '30 Tage';

  @override
  String get statsHitRateLabel => 'Trefferrate';

  @override
  String get statsTotalThrowsLabel => 'Würfe';

  @override
  String get statsTotalSessionsLabel => 'Sessions';

  @override
  String get statsLongestStreakLabel => 'Längste Serie';

  @override
  String get statsTrendTitle => 'Verlauf';

  @override
  String get statsBestsTitle => 'Bestmarken';

  @override
  String get statsBestRate => 'Beste Trefferrate';

  @override
  String get statsBestStreak => 'Längste Serie';

  @override
  String get statsBestDay => 'Meiste Würfe an einem Tag';

  @override
  String get statsSessionsTitle => 'Letzte Sessions';

  @override
  String get statsTabSniper => 'Sniper';

  @override
  String get statsTabFinisseur => 'Finisseur';

  @override
  String get statsTabMatch => 'Match';

  @override
  String get statsMatchEmptyTitle => 'Noch keine Matches';

  @override
  String get statsMatchEmptyBody =>
      'Spiele dein erstes Match — die Statistik füllt sich automatisch.';

  @override
  String get statsMatchWins => 'Siege';

  @override
  String get statsMatchLosses => 'Niederlagen';

  @override
  String get statsMatchTies => 'Unentschieden';

  @override
  String get statsMatchWinRate => 'Siegquote';

  @override
  String get statsMatchRecentTitle => 'Letzte Matches';

  @override
  String get statsMatchOutcomeWon => 'Gewonnen';

  @override
  String get statsMatchOutcomeLost => 'Verloren';

  @override
  String get statsMatchOutcomeTie => 'Unentschieden';

  @override
  String statsMatchOpponent(int n) {
    return 'vs $n Spieler';
  }

  @override
  String get statsFinisseurSuccessRate => 'Erfolgsrate';

  @override
  String get statsFinisseurTotalSticks => 'Stöcke total';

  @override
  String get statsFinisseurAvgSticks => 'Stöcke pro Session';

  @override
  String get statsFinisseurLongDubbies => 'Long Dubbies pro Session';

  @override
  String get statsFinisseurHeli => 'Helikopter';

  @override
  String get statsFinisseurPenalty => 'Strafkubb';

  @override
  String get statsFinisseurKingRate => 'Königswurf-Quote';

  @override
  String get statsFinisseurMisses => 'Misses (0-Treffer-Stöcke)';

  @override
  String get statsFinisseurStickRate => 'Stock-Trefferquote';

  @override
  String get statsFinisseurSessionsTitle => 'Letzte Finisseurs';

  @override
  String statsFinisseurRowConfig(int field, int base) {
    return '$field/$base';
  }

  @override
  String statsFinisseurRowSticks(int n) {
    return '$n Stöcke';
  }

  @override
  String get statsEmptyTitle => 'Noch keine Sessions';

  @override
  String get statsEmptyBody =>
      'Starte dein erstes Training — die Statistik füllt sich automatisch.';

  @override
  String get statsTrendEmpty =>
      'Noch zu wenig Daten — mindestens 2 Sessions für den Verlauf.';

  @override
  String statsRowThrows(int n) {
    return '$n Würfe';
  }

  @override
  String get csvExportTitle => 'CSV-Export';

  @override
  String get csvExportRangeLabel => 'Zeitraum';

  @override
  String get csvExportRangeAll => 'Alle';

  @override
  String get csvExportRange30 => '30 Tage';

  @override
  String get csvExportRange90 => '90 Tage';

  @override
  String get csvExportRangeYear => 'Jahr';

  @override
  String get csvExportModesLabel => 'Modi';

  @override
  String get csvExportModeSniper => 'Sniper-Training';

  @override
  String get csvExportModeFinisseur => 'Finisseur';

  @override
  String csvExportCount(int n) {
    return '$n Sessions im Filter';
  }

  @override
  String get csvExportDownload => 'Herunterladen';

  @override
  String get csvExportEmpty => 'Keine Sessions zum Exportieren';

  @override
  String csvExportSavedTo(String path) {
    return 'Export gespeichert: $path';
  }

  @override
  String get settingsScreenEyebrow => 'Menü';

  @override
  String get settingsAccountSection => 'Account';

  @override
  String get settingsDataSection => 'Daten';

  @override
  String get settingsAppSection => 'App';

  @override
  String get settingsRowProfile => 'Profil';

  @override
  String get settingsRowProfileSub => 'Name, Avatar-Farbe';

  @override
  String get settingsRowDeviceLabel => 'Geräte-ID';

  @override
  String get settingsRowStats => 'Statistik';

  @override
  String get settingsRowStatsSub => 'Trefferquote, Streaks, Verlauf';

  @override
  String get settingsRowExport => 'CSV-Export';

  @override
  String get settingsRowExportSub => 'Sessions als .csv-Datei';

  @override
  String get settingsRowResetSessions => 'Sessions zurücksetzen';

  @override
  String get settingsRowResetSessionsSub => 'alle Trainings-Sessions löschen';

  @override
  String get settingsRowDeleteProfile => 'Profil löschen';

  @override
  String get settingsRowDeleteProfileSub =>
      'Profil und alle Sessions entfernen';

  @override
  String get settingsPrivacyHeader => 'Datenschutz';

  @override
  String get settingsPrivacyBody =>
      'Alle Daten bleiben lokal auf deinem Gerät. Die App sendet nichts an externe Server.';

  @override
  String get settingsFooterTagline => 'Für die Wiese gebaut.';

  @override
  String get confirmCancel => 'Abbrechen';

  @override
  String get confirmDelete => 'Löschen';

  @override
  String get confirmResetSessionsTitle => 'Sessions löschen?';

  @override
  String get confirmResetSessionsBody =>
      'Alle Trainings-Sessions werden unwiderruflich gelöscht. Dein Profil bleibt bestehen.';

  @override
  String get confirmDeleteProfileTitle => 'Profil löschen?';

  @override
  String get confirmDeleteProfileBody =>
      'Profil und alle Trainings-Sessions werden unwiderruflich gelöscht. Du landest danach im Onboarding.';

  @override
  String get settingsResetDoneSnack => 'Sessions zurückgesetzt.';

  @override
  String get authSigninTagline => 'Trainings-Tracker für die Wiese';

  @override
  String get authSigninGoogle => 'Mit Google anmelden';

  @override
  String get authSigninApple => 'Mit Apple anmelden';

  @override
  String get authSigninAnonymous => 'Ohne Konto starten (anonym)';

  @override
  String get authSigninAnonymousLoading => 'Konto wird angelegt …';

  @override
  String get authSigninRestore => 'Konto auf neuem Gerät wiederherstellen';

  @override
  String get authSigninOffline =>
      'Du bist offline. Provider-Anmeldung wird nicht funktionieren — Anonym-Account legt offline an, lädt später hoch.';

  @override
  String get authSigninOr => 'oder';

  @override
  String get authSigninOauthError =>
      'Anmeldung fehlgeschlagen. Versuch es nochmals.';

  @override
  String get authAppName => 'Brosi\'s Kubb';

  @override
  String get authCommonContinue => 'Weiter';

  @override
  String get authCommonBack => 'Zurück';

  @override
  String get authCommonClose => 'Abbrechen';

  @override
  String get authSignupEyebrow => 'Anonym anlegen';

  @override
  String get authSignupNicknameTitle => 'Wähle einen Spielnamen';

  @override
  String get authSignupNicknameLabel => 'Spielname';

  @override
  String get authSignupNicknamePlaceholder => 'z. B. wiese-marc';

  @override
  String get authSignupNicknameHelper =>
      'Andere Spielerinnen sehen diesen Namen';

  @override
  String get authSignupNicknameTooShort => 'Mindestens 3 Zeichen.';

  @override
  String get authSignupNicknameTooLong => 'Maximal 30 Zeichen.';

  @override
  String get authSignupNicknameInvalidChars =>
      'Nur Buchstaben, Zahlen, \'-\' und \'_\'.';

  @override
  String get authSignupDisclaimerTitle => 'Sichere deine Passphrase';

  @override
  String get authDisclaimerHeading => 'Wichtig — bitte lesen';

  @override
  String get authDisclaimerNoReset =>
      'Diese Passphrase kann nicht zurückgesetzt werden.';

  @override
  String get authDisclaimerPasswordManager =>
      'Wir empfehlen dringend einen Passwort-Manager.';

  @override
  String get authDisclaimerNoLiability => 'Die App-Betreiber haften nicht.';

  @override
  String get authDisclaimerAcknowledge =>
      'Ich habe verstanden, dass diese Passphrase nicht zurückgesetzt werden kann.';

  @override
  String get authPassphraseLabel => 'Passphrase';

  @override
  String get authPassphrasePlaceholder => 'mindestens 12 Zeichen';

  @override
  String get authPassphraseHelper =>
      'Mindestens 12 Zeichen. Wir empfehlen, sie direkt im Passwort-Manager zu speichern.';

  @override
  String get authPassphraseMinError => 'Mindestens 12 Zeichen.';

  @override
  String get authPassphraseShow => 'Passphrase anzeigen';

  @override
  String get authPassphraseHide => 'Passphrase verbergen';

  @override
  String get authPassphraseStrengthWeak => 'Schwach';

  @override
  String get authPassphraseStrengthMedium => 'Mittel';

  @override
  String get authPassphraseStrengthStrong => 'Stark';

  @override
  String get authSignupSubmit => 'Account erstellen';

  @override
  String get authSignupSubmitting => 'Account wird angelegt …';

  @override
  String get authSignupSubmittingHint =>
      'Verschlüsselungsschlüssel werden erzeugt — bis zu 4 s.';

  @override
  String get authSignupErrorBanner =>
      'Konto konnte nicht angelegt werden. Prüfe deine Verbindung und versuch es nochmals.';

  @override
  String get authSignupSuccessTitle => 'Account angelegt';

  @override
  String get authSignupSuccessReminder =>
      'Speichere deine Passphrase im Passwort-Manager. Ohne sie kommst du nicht mehr an dein Konto.';

  @override
  String get authSignupSuccessContinue => 'Weiter zur Tour';

  @override
  String authWizardStepCount(int step, int total) {
    return 'Schritt $step / $total';
  }

  @override
  String get authRestoreEyebrow => 'Konto wiederherstellen';

  @override
  String get authRestoreNicknameTitle => 'Spielname';

  @override
  String get authRestorePassphraseTitle => 'Passphrase';

  @override
  String get authRestoreNicknamePlaceholder => 'dein Spielname';

  @override
  String get authRestoreNicknameHelper => 'Genau wie beim Anlegen des Kontos.';

  @override
  String get authRestorePassphraseHelper =>
      'Genau wie beim Anlegen — Gross-/Kleinschreibung beachten.';

  @override
  String get authRestoreSubmit => 'Konto entsperren';

  @override
  String get authRestoreSubmitting => 'Konto wird entsperrt …';

  @override
  String get authRestoreError => 'Wiederherstellung fehlgeschlagen.';

  @override
  String get authRestoreCooldownTitle => 'Zu viele Versuche';

  @override
  String authRestoreCooldownMessage(int seconds) {
    return 'Bitte warte $seconds Sekunden, dann versuch es erneut.';
  }

  @override
  String get authLinkEyebrow => 'Account';

  @override
  String get authLinkTitle => 'Konto verknüpfen';

  @override
  String get authLinkHeading => 'Verknüpfe dein Konto\nfür sichereres Backup';

  @override
  String get authLinkExplanation =>
      'Du bist aktuell anonym mit deiner Passphrase angemeldet. Wenn du Google oder Apple verknüpfst, kannst du dein Konto auch ohne Passphrase wiederherstellen.';

  @override
  String get authLinkGoogleLabel => 'Google verknüpfen';

  @override
  String get authLinkAppleLabel => 'Apple verknüpfen';

  @override
  String get authLinkErrorBanner =>
      'Verknüpfen fehlgeschlagen. Versuch es nochmals.';

  @override
  String get authLinkSuccessBanner => 'Konto erfolgreich verknüpft.';

  @override
  String get authLinkFallbackKept =>
      'Dein bisheriger Zugang per Passphrase bleibt als Backup erhalten.';

  @override
  String get authPassphraseChangeEyebrow => 'Sicherheit';

  @override
  String get authPassphraseChangeTitle => 'Passphrase ändern';

  @override
  String get authPassphraseChangeOldLabel => 'Alte Passphrase';

  @override
  String get authPassphraseChangeOldHelper =>
      'Wir prüfen erst, dann setzen wir die neue.';

  @override
  String get authPassphraseChangeError => 'Konnte nicht ändern.';

  @override
  String get authPassphraseChangeNewLabel => 'Neue Passphrase';

  @override
  String get authPassphraseChangeNewHelper =>
      'Mindestens 12 Zeichen. Sie sollte sich von der bisherigen unterscheiden.';

  @override
  String get authPassphraseChangeConfirmLabel => 'Neue Passphrase bestätigen';

  @override
  String get authPassphraseChangeConfirmHelper =>
      'Erneut eingeben — exakt gleich.';

  @override
  String get authPassphraseChangeConfirmMismatch => 'Stimmt nicht überein.';

  @override
  String get authPassphraseChangeSuccess => 'Passphrase aktualisiert.';

  @override
  String get authPassphraseChangeSubmit => 'Speichern';

  @override
  String get authPassphraseChangeSubmitting => 'Speichere …';

  @override
  String get authPassphraseChangeCancel => 'Abbrechen';

  @override
  String get authDeleteEyebrow => 'Konto löschen';

  @override
  String get authDeleteWarningTitle => 'Konto löschen?';

  @override
  String get authDeleteConfirmTitle => 'Endgültig bestätigen';

  @override
  String get authDeleteWarningHeadline => 'Diese Aktion ist endgültig';

  @override
  String get authDeleteWarningSub =>
      'Wenn du fortfährst, geht Folgendes verloren:';

  @override
  String get authDeleteConsequenceSessions =>
      'Alle gespeicherten Trainings-Sessions';

  @override
  String get authDeleteConsequenceStats => 'Statistiken, Streaks, Erfolge';

  @override
  String get authDeleteConsequenceProfile => 'Dein Spielername und Profil';

  @override
  String get authDeleteConsequenceLinkedAccounts =>
      'Verknüpfte Konten (Google / Apple)';

  @override
  String get authDeleteConsequenceKeypair =>
      'Anonymer Keypair-Zugang — nicht wiederherstellbar';

  @override
  String get authDeleteContinueToConfirm => 'Weiter zur Bestätigung';

  @override
  String get authDeleteAcknowledge =>
      'Ich verstehe, dass alle Daten dauerhaft gelöscht werden.';

  @override
  String get authDeleteErrorBanner =>
      'Löschen fehlgeschlagen. Bitte später erneut versuchen.';

  @override
  String get authDeleteSubmit => 'Konto endgültig löschen';

  @override
  String get authDeleteSubmitting => 'Konto wird gelöscht …';

  @override
  String get authDeleteCancel => 'Abbrechen';

  @override
  String get authOnboardingNext => 'Weiter';

  @override
  String get authOnboardingDone => 'Fertig';

  @override
  String get authOnboardingSkip => 'Überspringen';

  @override
  String get authOnboardingWelcomeTitle => 'Willkommen.';

  @override
  String get authOnboardingWelcomeBody =>
      'Brosi\'s Kubb hilft dir, deine Würfe systematisch zu verbessern — Sniper, Finisseur, und bald mehr.';

  @override
  String get authOnboardingBadgeAnon => 'Anonymes Konto';

  @override
  String get authOnboardingBadgeGoogle => 'Mit Google verknüpft';

  @override
  String get authOnboardingBadgeApple => 'Mit Apple verknüpft';

  @override
  String get authBadgeAnonShort => 'Anonym';

  @override
  String get authBadgeGoogleShort => 'Google';

  @override
  String get authBadgeAppleShort => 'Apple';

  @override
  String authBadgeStatusSemantic(String label) {
    return 'Konto-Status: $label';
  }

  @override
  String get authOnboardingModesTitle => 'Trainingsmodi';

  @override
  String get authOnboardingModeSniperName => 'Sniper';

  @override
  String get authOnboardingModeSniperSub => '8 m gerade Treffer trainieren';

  @override
  String get authOnboardingModeFinisseurName => 'Finisseur';

  @override
  String get authOnboardingModeFinisseurSub => 'Königswurf-Sequenzen üben';

  @override
  String get authOnboardingMode4mName => '4 m-Linie';

  @override
  String get authOnboardingMode4mSub => 'Strafkubb-Distanz präzisieren';

  @override
  String get authOnboardingSoonPill => 'künftig';

  @override
  String get authOnboardingSoonTitle => 'Bald verfügbar';

  @override
  String get authOnboardingSoonTournaments => 'Tournaments';

  @override
  String get authOnboardingSoonFriendMatch => 'Friend-Match';

  @override
  String get authOnboardingSoonBody =>
      'Mit Freundinnen und Klubs spielen, Resultate teilen, Ranglisten verfolgen — kommt bald.';

  @override
  String get authOnboardingReminderTitle => 'Eine letzte Sache.';

  @override
  String get authOnboardingReminderQuestion =>
      'Hast du deine Passphrase im Passwort-Manager gespeichert?';

  @override
  String get authOnboardingReminderBody =>
      'Ohne sie kommst du nicht mehr an dein anonymes Konto.';

  @override
  String get authAccountSectionLabel => 'Konto';

  @override
  String get authAccountProviderAnonymous => 'Anonym (Passphrase)';

  @override
  String get authAccountProviderGoogle => 'Google';

  @override
  String get authAccountProviderApple => 'Apple';

  @override
  String get authAccountLinkLabel => 'Konto verknüpfen';

  @override
  String get authAccountLinkSub =>
      'Mit Google oder Apple für sichereres Backup';

  @override
  String get authAccountPassphraseLabel => 'Passphrase ändern';

  @override
  String get authAccountPassphraseSub => 'Neue Passphrase für dein Keypair';

  @override
  String get authAccountSignOutLabel => 'Abmelden';

  @override
  String authAccountSignOutSub(String provider) {
    return 'Beendet die Session — $provider';
  }

  @override
  String get authAccountDeleteLabel => 'Konto löschen';

  @override
  String get authAccountDeleteSub => 'Alle Daten dauerhaft entfernen';

  @override
  String get authBackupWarningTitle => 'Backup empfohlen';

  @override
  String get authBackupWarningMissing =>
      'Dein anonymes Konto hat noch kein Backup auf dem Server.';

  @override
  String authBackupWarningStale(int days) {
    return 'Letztes Backup vor $days Tagen — bitte aktualisieren.';
  }

  @override
  String get authEditProfileEyebrow => 'Account';

  @override
  String get authEditProfileTitle => 'Profil bearbeiten';

  @override
  String get authEditProfileNicknameLabel => 'Spielname';

  @override
  String get authEditProfileNicknameHelper =>
      '3–30 Zeichen, Buchstaben, Zahlen, \'-\', \'_\'.';

  @override
  String get authEditProfileError => 'Konnte nicht speichern.';

  @override
  String get authEditProfileSuccess => 'Profil aktualisiert.';

  @override
  String get authEditProfileSubmit => 'Speichern';

  @override
  String get authEditProfileSubmitting => 'Speichere …';

  @override
  String get tournamentWizardTitle => 'Neues Turnier';

  @override
  String get tournamentWizardStep1Title => 'Stammdaten';

  @override
  String get tournamentWizardStep2Title => 'Teilnehmer';

  @override
  String get tournamentWizardStep3Title => 'Format';

  @override
  String get tournamentWizardStep4Title => 'Übersicht';

  @override
  String tournamentWizardStepLabel(int step, int total) {
    return 'Schritt $step von $total';
  }

  @override
  String get tournamentWizardDisplayNameLabel => 'Turniername';

  @override
  String get tournamentWizardMinParticipantsLabel => 'Min. Teilnehmer';

  @override
  String get tournamentWizardMaxParticipantsLabel => 'Max. Teilnehmer';

  @override
  String get tournamentWizardFormatLabel => 'Turnierformat';

  @override
  String get tournamentWizardFormatRoundRobin => 'Round Robin';

  @override
  String get tournamentWizardFormatComingSoon => 'Folgt in M2+';

  @override
  String get tournamentWizardSetsToWinLabel => 'Sätze zum Sieg';

  @override
  String get tournamentWizardMaxSetsLabel => 'Max. Sätze';

  @override
  String get tournamentWizardRoundTimeLabel => 'Rundenzeit (Minuten)';

  @override
  String get tournamentWizardBackButton => 'Zurück';

  @override
  String get tournamentWizardNextButton => 'Weiter';

  @override
  String get tournamentWizardCreateButton => 'Turnier anlegen';

  @override
  String tournamentWizardSubmitError(String error) {
    return 'Turnier konnte nicht erstellt werden: $error';
  }

  @override
  String get tournamentListEyebrow => 'Turniere';

  @override
  String get tournamentListTitle => 'Übersicht';

  @override
  String get tournamentListTabMine => 'Meine Turniere';

  @override
  String get tournamentListTabPublic => 'Aktuelle Turniere';

  @override
  String get tournamentListNewButton => 'Neues Turnier';

  @override
  String get tournamentListEmptyMine => 'Du hast noch keine Turniere erstellt.';

  @override
  String get tournamentListEmptyPublic => 'Keine offenen Turniere zurzeit.';

  @override
  String tournamentListParticipantCount(int count) {
    return '$count Teilnehmer';
  }

  @override
  String get tournamentStatusDraft => 'Entwurf';

  @override
  String get tournamentStatusPublished => 'Veröffentlicht';

  @override
  String get tournamentStatusRegistrationOpen => 'Anmeldung offen';

  @override
  String get tournamentStatusRegistrationClosed => 'Anmeldung geschlossen';

  @override
  String get tournamentStatusLive => 'Läuft';

  @override
  String get tournamentStatusFinalized => 'Abgeschlossen';

  @override
  String get tournamentStatusAborted => 'Abgebrochen';

  @override
  String get tournamentFormatRoundRobin => 'Jeder gegen Jeden';

  @override
  String get tournamentFormatSingleElimination => 'K.-o.';

  @override
  String get tournamentFormatSchoch => 'Schoch';

  @override
  String get tournamentFormatSwiss => 'Schweizer System';

  @override
  String get tournamentFormatRoundRobinKo => 'Gruppen + K.-o.';

  @override
  String get tournamentFormatSchochKo => 'Schoch + K.-o.';

  @override
  String get tournamentFormatSwissKo => 'Schweiz + K.-o.';

  @override
  String get tournamentDetailEyebrow => 'Turnier';

  @override
  String get tournamentDetailNotFound => 'Turnier nicht gefunden.';

  @override
  String tournamentDetailParticipantSummary(int count, int max) {
    return '$count von $max Teilnehmern';
  }

  @override
  String get tournamentDetailStammdaten => 'Stammdaten';

  @override
  String get tournamentDetailFormat => 'Format';

  @override
  String get tournamentDetailTeamSize => 'Team-Grösse';

  @override
  String get tournamentDetailSetsToWin => 'Sätze zum Sieg';

  @override
  String get tournamentDetailMaxSets => 'Max Sätze';

  @override
  String get tournamentDetailRoundTime => 'Runden-Zeit';

  @override
  String get tournamentDetailParticipants => 'Teilnehmer';

  @override
  String get tournamentDetailParticipantsEmpty => 'Noch keine Anmeldungen.';

  @override
  String get tournamentDetailRoster => 'Mein Roster';

  @override
  String get tournamentDetailRosterEmpty => 'Noch keine Slots belegt.';

  @override
  String tournamentDetailRosterSlot(int index) {
    return 'Slot $index';
  }

  @override
  String get tournamentDetailRosterGuest => 'Gast';

  @override
  String tournamentMatchHammerCrew(String members) {
    return 'Hammer-Crew ($members)';
  }

  @override
  String get tournamentDetailPending => 'ausstehend';

  @override
  String get tournamentDetailApprove => 'Bestätigen';

  @override
  String get tournamentDetailReject => 'Ablehnen';

  @override
  String get tournamentDetailActionPublish => 'Veröffentlichen';

  @override
  String get tournamentDetailActionOpenReg => 'Anmeldung öffnen';

  @override
  String get tournamentDetailActionCloseReg => 'Anmeldung schliessen';

  @override
  String get tournamentDetailActionRegister => 'Anmelden';

  @override
  String get tournamentDetailActionWithdraw => 'Abmelden';

  @override
  String get tournamentDetailActionStart => 'Turnier starten';

  @override
  String get tournamentDetailActionFinalize => 'Turnier abschliessen';

  @override
  String get tournamentDetailActionAbort => 'Turnier abbrechen';

  @override
  String get tournamentDetailActionGotoMatches => 'Zu den Matches';

  @override
  String get tournamentDetailActionStandings => 'Endrangliste';

  @override
  String get tournamentDetailActionBracket => 'Bracket anzeigen';

  @override
  String get tournamentDetailActionLiveDashboard => 'Live-Dashboard öffnen';

  @override
  String get tournamentDetailAborted => 'Turnier abgebrochen.';

  @override
  String get tournamentDetailPools => 'Gruppen';

  @override
  String get tournamentDetailPoolsEmpty => 'Noch keine Gruppendaten.';

  @override
  String tournamentDetailPoolGroup(String label) {
    return 'Gruppe $label';
  }

  @override
  String get tournamentDetailAuditHeader => 'Verlauf';

  @override
  String get tournamentDetailAuditEmpty => 'Keine Ereignisse.';

  @override
  String get tournamentRegistrationEyebrow => 'Turnier';

  @override
  String get tournamentRegistrationTitle => 'Anmelden';

  @override
  String get tournamentRegistrationPendingHint =>
      'Du wirst zunächst auf \'ausstehend\' gesetzt, bis der Veranstalter bestätigt.';

  @override
  String get tournamentRegistrationConfirm => 'Anmeldung bestätigen';

  @override
  String get tournamentRegistrationSubmitting => 'Sende …';

  @override
  String get tournamentRegistrationCancel => 'Abbrechen';

  @override
  String get tournamentRegistrationSuccess => 'Anmeldung gesendet.';

  @override
  String get tournamentMatchListTitle => 'Spiele';

  @override
  String get tournamentMatchListEmpty => 'Noch keine Spiele geplant.';

  @override
  String tournamentMatchListRound(int round) {
    return 'Runde $round';
  }

  @override
  String get tournamentMatchLoadError => 'Spiele konnten nicht geladen werden';

  @override
  String get tournamentMatchBye => 'BYE';

  @override
  String get tournamentMatchStatusScheduled => 'Geplant';

  @override
  String get tournamentMatchStatusAwaiting => 'Warten';

  @override
  String get tournamentMatchStatusDisputed => 'Strittig';

  @override
  String get tournamentMatchStatusFinalized => 'Abgeschlossen';

  @override
  String get tournamentMatchStatusOverridden => 'Korrigiert';

  @override
  String get tournamentMatchStatusVoided => 'Ungültig';

  @override
  String get tournamentMatchDetailTitle => 'Spiel-Eingabe';

  @override
  String tournamentMatchHeaderRound(int round, int match) {
    return 'Runde $round — Spiel $match';
  }

  @override
  String tournamentMatchVersusHeader(String a, String b) {
    return '$a gegen $b';
  }

  @override
  String get tournamentMatchByeHeader => 'Freilos';

  @override
  String get tournamentParticipantUnknown => 'Unbekannt';

  @override
  String tournamentMatchConsensusAttempt(int attempt, int max) {
    return 'Versuch $attempt von $max';
  }

  @override
  String tournamentMatchSetLabel(int n) {
    return 'Satz $n';
  }

  @override
  String get tournamentMatchBasekubbsALabel => 'Basekubbs Team A';

  @override
  String get tournamentMatchBasekubbsBLabel => 'Basekubbs Team B';

  @override
  String get tournamentMatchKingLabel => 'Königsstoss durch';

  @override
  String get tournamentMatchKingByA => 'Team A';

  @override
  String get tournamentMatchKingByB => 'Team B';

  @override
  String get tournamentMatchKingByNone => 'Zeitablauf';

  @override
  String get tournamentMatchAddSet => 'Satz +';

  @override
  String get tournamentMatchRemoveSet => 'Satz −';

  @override
  String get tournamentMatchLivePreviewLabel => 'Aktueller Stand';

  @override
  String tournamentMatchLivePreviewScore(int a, int b) {
    return '$a:$b';
  }

  @override
  String get tournamentMatchLivePreviewUndecided => 'Match noch offen';

  @override
  String get tournamentMatchSubmitButton => 'Einreichen';

  @override
  String get tournamentMatchSubmitError => 'Senden fehlgeschlagen';

  @override
  String get tournamentMatchReadOnlyNotice =>
      'Dieses Spiel ist bereits abgeschlossen.';

  @override
  String get tournamentForfeitAction => 'Forfeit erklären';

  @override
  String get tournamentForfeitSheetTitle => 'Forfeit erklären';

  @override
  String get tournamentForfeitAbsentSideLabel =>
      'Welche Seite ist nicht erschienen?';

  @override
  String get tournamentForfeitSideA => 'Team A';

  @override
  String get tournamentForfeitSideB => 'Team B';

  @override
  String get tournamentForfeitReasonLabel => 'Begründung';

  @override
  String get tournamentForfeitReasonHint => 'Mindestens 10 Zeichen';

  @override
  String get tournamentForfeitReasonTooShort =>
      'Begründung muss mindestens 10 Zeichen enthalten.';

  @override
  String get tournamentForfeitSideRequired =>
      'Bitte abwesende Seite auswählen.';

  @override
  String get tournamentForfeitSubmitButton => 'Forfeit speichern';

  @override
  String tournamentForfeitSubmitError(String error) {
    return 'Forfeit konnte nicht gespeichert werden: $error';
  }

  @override
  String get tournamentForfeitSuccessToast =>
      'Forfeit gespeichert — Match abgeschlossen.';

  @override
  String tournamentMatchValidationEmpty(int n) {
    return 'Satz $n: Eingabe fehlt.';
  }

  @override
  String tournamentMatchValidationKingNeedsMax(int n) {
    return 'Satz $n: Königsstoss verlangt volle Basekubbs.';
  }

  @override
  String get tournamentMatchFinalizedToast => 'Match abgeschlossen';

  @override
  String tournamentMatchDisagreementToast(int attempt, int max) {
    return 'Eingaben weichen ab — Versuch $attempt von $max';
  }

  @override
  String get tournamentMatchDisputedToast =>
      'Strittig — Veranstalter benachrichtigt';

  @override
  String get tournamentStandingsTitle => 'Endrangliste';

  @override
  String get tournamentStandingsEmpty => 'Noch keine Ergebnisse.';

  @override
  String get tournamentStandingsLoadError =>
      'Rangliste konnte nicht geladen werden';

  @override
  String get tournamentStandingsRank => 'Rang';

  @override
  String get tournamentStandingsPlayer => 'Spieler';

  @override
  String get tournamentStandingsTotal => 'Total';

  @override
  String get tournamentStandingsWins => 'Siege';

  @override
  String get tournamentStandingsBuchholz => 'Buchholz';

  @override
  String get tournamentStandingsKubbDiff => 'Kubb-Diff';

  @override
  String get tournamentConflictTitle => 'Eingaben weichen ab';

  @override
  String tournamentConflictAttempt(int attempt) {
    return 'Versuch $attempt von 3 — Eingaben weichen ab';
  }

  @override
  String get tournamentConflictLastAttemptWarning =>
      'Letzter Versuch — bei Abweichung übernimmt der Veranstalter';

  @override
  String get tournamentConflictColumnA => 'Eingabe Team A';

  @override
  String get tournamentConflictColumnB => 'Eingabe Team B';

  @override
  String tournamentConflictSetLabel(int n) {
    return 'Satz $n';
  }

  @override
  String get tournamentConflictBasekubbsA => 'Basekubbs A';

  @override
  String get tournamentConflictBasekubbsB => 'Basekubbs B';

  @override
  String get tournamentConflictSetWinner => 'Sieger';

  @override
  String get tournamentConflictRetryButton => 'Erneut eintragen';

  @override
  String get tournamentConflictEscalateButton => 'Veranstalter hinzuziehen';

  @override
  String get tournamentConflictEscalateToast =>
      'Verlangen an Veranstalter weitergeleitet';

  @override
  String get tournamentConflictEmpty => 'Noch keine abweichenden Eingaben.';

  @override
  String get tournamentOverrideEyebrow => 'Strittiges Match';

  @override
  String get tournamentOverrideTitle => 'Veranstalter-Override';

  @override
  String get tournamentOverrideProposalsHeader => 'Bisherige Eingaben';

  @override
  String get tournamentOverrideProposalsEmpty => 'Keine Eingaben vorhanden.';

  @override
  String get tournamentOverrideFinalHeader => 'Finaler Score';

  @override
  String get tournamentOverrideReasonHeader => 'Begründung';

  @override
  String get tournamentOverrideReasonHint =>
      'Warum wurde dieser Score festgelegt?';

  @override
  String tournamentOverrideReasonCounter(Object current, Object max) {
    return '$current/$max';
  }

  @override
  String get tournamentOverrideSubmitButton => 'Entscheidung speichern';

  @override
  String tournamentOverrideSubmitError(Object error) {
    return 'Speichern fehlgeschlagen: $error';
  }

  @override
  String get tournamentOverrideStatusGate =>
      'Nur strittige Matches können übersteuert werden.';

  @override
  String get tournamentOverrideValidationReasonEmpty =>
      'Begründung ist erforderlich';

  @override
  String get tournamentOverrideValidationScoreNotDecisive =>
      'Score muss eindeutig sein (ein Team erreicht die nötigen Sätze)';

  @override
  String get tournamentOverrideNotAuthorized => 'Nicht autorisiert';

  @override
  String get tournamentBracketPhaseKo => 'KO-Phase';

  @override
  String get tournamentBracketPhaseFinal => 'Finale';

  @override
  String get tournamentBracketPhaseSemifinal => 'Halbfinale';

  @override
  String get tournamentBracketPhaseQuarterfinal => 'Viertelfinale';

  @override
  String tournamentBracketPhaseRoundOf(int n) {
    return 'Runde der $n';
  }

  @override
  String get tournamentBracketPhaseThirdPlace => 'Spiel um Platz 3';

  @override
  String get tournamentBracketBronzeMatchShort => 'Bronze';

  @override
  String get tournamentBracketByeLabel => 'Freilos';

  @override
  String get tournamentBracketByeTooltip =>
      'Spielfreilos für Top-Seeds aus der Vorrunde — wer in der Gruppenphase vorne lag, startet eine Runde später.';

  @override
  String tournamentBracketSeedPrefix(int n) {
    return 'Seed $n';
  }

  @override
  String get tournamentBracketTitle => 'KO-Bracket';

  @override
  String get tournamentBracketEmpty => 'KO noch nicht gestartet';

  @override
  String get tournamentBracketLoadError =>
      'Bracket konnte nicht geladen werden';

  @override
  String get tournamentSeedingTitle => 'Seeding';

  @override
  String get tournamentSeedingEyebrow => 'KO-Setup';

  @override
  String tournamentSeedingPositionLabel(int n) {
    return 'Position $n';
  }

  @override
  String get tournamentSeedingDragHint =>
      'Lange tippen und ziehen zum Umsortieren.';

  @override
  String get tournamentSeedingOverrideLabel => 'Manuell gesetzt';

  @override
  String get tournamentSeedingResetButton =>
      'Auf Gruppen-Reihenfolge zurücksetzen';

  @override
  String get tournamentSeedingSaveButton => 'Seeding speichern';

  @override
  String get tournamentSeedingStartKoButton => 'KO starten';

  @override
  String get tournamentSeedingErrorTitle => 'Aktion fehlgeschlagen';

  @override
  String get tournamentSeedingEmpty => 'Noch keine qualifizierten Teilnehmer.';

  @override
  String get tournamentWizardStep45Title => 'Liga-Wertung';

  @override
  String get tournamentWizardLeagueEligibleLabel =>
      'Dieses Turnier wertet für die Liga';

  @override
  String get tournamentWizardLeagueEligibleHelper =>
      'Liga-Turniere spielen standardmässig das Spiel um Platz 3 — Rang 3 und 4 geben unterschiedliche Punkte.';

  @override
  String get tournamentWizardStep5Title => 'KO-Konfiguration';

  @override
  String get tournamentWizardQualifierCountLabel => 'Anzahl Qualifikanten';

  @override
  String get tournamentWizardQualifierCountHelper =>
      'Wie viele Teams ziehen aus der Gruppenphase in die KO-Phase ein? Beliebige Zahl möglich — die App füllt fehlende Plätze mit Freilosen auf.';

  @override
  String tournamentWizardQualifierPreviewBracketSize(int size) {
    return 'Bracket-Grösse: $size';
  }

  @override
  String tournamentWizardQualifierPreviewByes(int byes) {
    return 'Davon $byes Freilos(e) an die Top-Seeds';
  }

  @override
  String tournamentWizardQualifierPreviewRealMatches(int matches) {
    return 'Runde 1: $matches echte Spiele';
  }

  @override
  String get tournamentWizardBronzeMatchLabel => 'Spiel um Platz 3 austragen';

  @override
  String get tournamentWizardBronzeMatchHelper =>
      'Empfohlen bei Liga-Turnieren — entscheidet zwischen Rang 3 und 4.';

  @override
  String get tournamentWizardStep6Title => 'Tiebreaker-Reihenfolge';

  @override
  String get tournamentWizardTiebreakerHint =>
      'Lange tippen und ziehen, um die Reihenfolge der Entscheidungskriterien zu ändern.';

  @override
  String get tournamentWizardTiebreakerResetButton =>
      'Standard wiederherstellen';

  @override
  String get tournamentKoHelpTitle => 'Wie funktioniert der KO-Cut?';

  @override
  String get tournamentKoHelpBody =>
      'Die besten Teams aus der Gruppenphase ziehen ins KO-Bracket ein. Passt die Zahl nicht zu einer Zweierpotenz (2, 4, 8, 16…), bekommen die bestplatzierten Teams ein Freilos in Runde 1. So bleibt das Bracket fair und ausgeglichen — international Standard.';

  @override
  String get tournamentKoHelpLinkLabel => 'Mehr zum KO-Modus';

  @override
  String get inboxTeamInvitation => 'Team-Einladung';

  @override
  String get inboxTeamMemberRemoved => 'Team-Änderung';

  @override
  String get inboxTeamDissolved => 'Team aufgelöst';

  @override
  String get teamListTitle => 'Teams';

  @override
  String get teamListTabMine => 'Meine Teams';

  @override
  String get teamListTabSearch => 'Suchen';

  @override
  String get teamListSearchPlaceholder => 'Team suchen …';

  @override
  String get teamListEmpty =>
      'Du bist noch in keinem Team. Erstelle eins oder lass dich einladen.';

  @override
  String get teamListCreateFab => 'Team erstellen';

  @override
  String get teamCreateTitle => 'Neues Team';

  @override
  String get teamCreateNameLabel => 'Teamname';

  @override
  String get teamCreateLeagueLabel => 'Liga (optional)';

  @override
  String get teamCreateLogoUrlLabel => 'Logo-URL (optional)';

  @override
  String get teamCreateCountryLabel => 'Land';

  @override
  String get teamCreateSubmitButton => 'Team anlegen';

  @override
  String get teamCreateErrorGeneric =>
      'Team konnte nicht erstellt werden — bitte erneut versuchen.';

  @override
  String teamDetailHeaderLeague(String league) {
    return 'Liga: $league';
  }

  @override
  String get teamDetailPoolSection => 'Stammspieler';

  @override
  String get teamDetailGuestsSection => 'Gäste';

  @override
  String get teamDetailInviteAction => 'Spieler einladen';

  @override
  String get teamDetailAddGuestAction => 'Gast hinzufügen';

  @override
  String get teamDetailLeaveAction => 'Team verlassen';

  @override
  String get teamDetailDissolveAction => 'Team auflösen';

  @override
  String get teamDetailRemoveMember => 'Aus Team entfernen';

  @override
  String get teamDetailMemberBadge => 'Mitglied';

  @override
  String get teamDetailGuestBadge => 'Gast';

  @override
  String get teamDetailConfirmRemove =>
      'Mitglied wirklich aus dem Team entfernen?';

  @override
  String get teamDetailConfirmLeave =>
      'Möchtest du das Team wirklich verlassen?';

  @override
  String get teamDetailConfirmDissolve =>
      'Team wirklich auflösen? Alle Mitglieder werden entfernt.';

  @override
  String get teamInvitationListTitle => 'Einladungen';

  @override
  String get teamInvitationAccept => 'Annehmen';

  @override
  String get teamInvitationDecline => 'Ablehnen';

  @override
  String get teamInvitationEmpty => 'Keine offenen Einladungen.';

  @override
  String teamInvitationFrom(String name) {
    return 'Von $name';
  }

  @override
  String get rosterComposeTitle => 'Roster zusammenstellen';

  @override
  String get rosterComposePoolSection => 'Pool';

  @override
  String get rosterComposeSlotsSection => 'Slots';

  @override
  String rosterComposeSlotLabel(int index) {
    return 'Slot $index';
  }

  @override
  String get rosterComposeSlotEmpty => 'Leer';

  @override
  String get rosterComposeSelectSlotPrompt => 'Welcher Slot?';

  @override
  String get rosterComposeSelectMemberPrompt => 'Welcher Pool-Eintrag?';

  @override
  String get rosterComposeConflictTooltip => 'Bereits in anderem Roster';

  @override
  String get rosterComposeMinOneRegisteredWarning =>
      'Mindestens ein registriertes Mitglied';

  @override
  String get registerTeamTitle => 'Team anmelden';

  @override
  String get registerTeamSelectTeamLabel => 'Team auswählen';

  @override
  String get registerTeamSubmitButton => 'Anmelden';

  @override
  String get registerTeamNoTeamsHint =>
      'Du hast noch kein Team. Lege zuerst eines an.';

  @override
  String get registerTeamCreateTeamAction => 'Team erstellen';

  @override
  String get registerTeamErrorBr5Violation =>
      'Ein Mitglied ist bereits in einem anderen Roster dieses Turniers.';

  @override
  String get registerTeamErrorMinOneRegistered =>
      'Roster benötigt mindestens ein registriertes Mitglied.';

  @override
  String get registerTeamErrorGeneric =>
      'Anmeldung fehlgeschlagen — bitte erneut versuchen.';

  @override
  String get rosterEditorTitle => 'Roster bearbeiten';

  @override
  String get rosterEditorCurrentSection => 'Aktuelles Roster';

  @override
  String get rosterEditorReplaceAction => 'Ersetzen';

  @override
  String rosterEditorReplaceDialogTitle(int index) {
    return 'Slot $index ersetzen';
  }

  @override
  String get rosterEditorReplaceReasonLabel => 'Grund (optional)';

  @override
  String get rosterEditorReplaceSubmit => 'Übernehmen';

  @override
  String get rosterEditorAuditSection => 'Verlauf';

  @override
  String get rosterEditorAuditEmpty => 'Keine bisherigen Wechsel.';

  @override
  String get rosterEditorErrorLockedDuringMatch =>
      'Substitution nur zwischen Matches möglich.';

  @override
  String get rosterEditorFinalizedHint =>
      'Turnier ist abgeschlossen — Roster nicht mehr änderbar.';

  @override
  String get tournamentDetailRosterTab => 'Roster';

  @override
  String tournamentDetailMatchTeamHeader(String teamName, String members) {
    return '$teamName (Roster: $members)';
  }

  @override
  String get poolConfigTitle => 'Pool-Phase konfigurieren';

  @override
  String get poolConfigEnableToggle => 'Pool-Phase aktivieren';

  @override
  String get poolConfigGroupCountLabel => 'Anzahl Gruppen';

  @override
  String get poolConfigQualifiersLabel => 'Qualifikanten pro Gruppe';

  @override
  String get poolConfigStrategyLabel => 'Verteilungsstrategie';

  @override
  String get poolConfigStrategySnake => 'Schlangenlinie';

  @override
  String get poolConfigStrategyRandom => 'Zufällig';

  @override
  String get poolConfigStrategySeeded => 'Nach Setzliste';

  @override
  String get poolConfigRandomSeedLabel => 'Zufalls-Seed (optional)';

  @override
  String get poolStandingsTitle => 'Pool-Tabelle';

  @override
  String get poolStandingsCrossPoolTitle => 'Gesamttabelle';

  @override
  String poolStandingsGroupHeader(String name) {
    return 'Gruppe $name';
  }

  @override
  String get poolStandingsRank => 'Platz';

  @override
  String get poolStandingsSets => 'Sätze';

  @override
  String get poolStandingsPoints => 'Punkte';

  @override
  String get poolStandingsBuchholz => 'Buchholz';

  @override
  String get poolStandingsQualified => 'Qualifiziert';

  @override
  String get tieResolveTitle => 'Gleichstand auflösen';

  @override
  String get tieResolveExplanation =>
      'Mehrere Teams stehen punktgleich. Lege die Reihenfolge manuell fest.';

  @override
  String get tieResolveSubmitButton => 'Reihenfolge übernehmen';

  @override
  String get tieResolveCancelButton => 'Abbrechen';

  @override
  String get tieResolveSuccess => 'Reihenfolge gespeichert.';

  @override
  String get tournamentDetailGroups => 'Gruppen';

  @override
  String get realtimeLive => 'Live';

  @override
  String get realtimePolling => 'Offline — Polling aktiv';

  @override
  String get realtimeConnecting => 'Verbinde…';

  @override
  String get liveDashboardTitle => 'Live-Dashboard';

  @override
  String get liveDashboardOpenButton => 'Live-Dashboard öffnen';

  @override
  String get pitchStatusScheduled => 'Geplant';

  @override
  String get pitchStatusLive => 'Live';

  @override
  String get pitchStatusStalled => 'Wartend';

  @override
  String get pitchStatusDisputed => 'Strittig';

  @override
  String get publicTournamentSchedule => 'Spielplan';

  @override
  String get publicTournamentStandings => 'Rangliste';

  @override
  String get publicTournamentBracket => 'Bracket';

  @override
  String get liveModeToggle => 'Live-Modus';

  @override
  String get publicNotAvailable => 'Dieses Turnier ist nicht öffentlich';

  @override
  String get scorePending => 'ausstehend, wird übertragen';

  @override
  String get scoreConflictTitle => 'Sync-Konflikt';

  @override
  String get scoreConflictExplanation =>
      'Dein Vorschlag konnte nicht übertragen werden, weil der Gegner schon korrigiert hat. Bitte erneut eingeben.';

  @override
  String get scoreConflictReenterButton => 'Erneut eingeben';

  @override
  String get offlineBannerLabel => 'Offline';

  @override
  String offlineBannerQueueSize(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Offline — $count Submissions ausstehend',
      one: 'Offline — 1 Submission ausstehend',
    );
    return '$_temp0';
  }

  @override
  String get seasonTitle => 'Saison';

  @override
  String get seasonAdminTitle => 'Saisonen verwalten';

  @override
  String get seasonCreateNew => 'Neue Saison';

  @override
  String get seasonStatusDraft => 'Entwurf';

  @override
  String get seasonStatusOpen => 'Offen';

  @override
  String get seasonStatusClosed => 'Abgeschlossen';

  @override
  String get seasonStandingsTitle => 'Saison-Tabelle';

  @override
  String get seasonStandingsEmpty => 'Noch keine Daten';

  @override
  String get seasonLeagueFilter => 'Liga';

  @override
  String get seasonAssignTournament => 'Turnier zuordnen';

  @override
  String get tournamentSwissSystem => 'Schweizer System';

  @override
  String get tournamentSwissRounds => 'Runden';

  @override
  String get tournamentSwissTiebreak => 'Tiebreak';

  @override
  String get tournamentSwissOversize =>
      'Schweizer System ist optimiert für ≤ 64 Teilnehmer';

  @override
  String get tournamentPointsMode => 'Punkte-Modus';

  @override
  String get tournamentPointsGlobal => 'Globale Formel';

  @override
  String get tournamentPointsCustom => 'Eigene Punkte';

  @override
  String get tournamentPointsCustomHint =>
      'Muss vom Plattform-Admin freigegeben werden';

  @override
  String get setKingOutcomeTeamA => 'Team A';

  @override
  String get setKingOutcomeTeamB => 'Team B';

  @override
  String get setKingOutcomeNone => 'Keiner';

  @override
  String get outboxStatusFlushing => 'Synchronisiere ausstehende Spielstände …';

  @override
  String get outboxStatusError =>
      'Spielstand konnte nicht synchronisiert werden.';

  @override
  String get realtimeStatusReconnecting => 'Verbinde mit Live-Updates …';

  @override
  String get realtimeStatusPolling =>
      'Live-Updates pausiert, lade automatisch nach.';
}
