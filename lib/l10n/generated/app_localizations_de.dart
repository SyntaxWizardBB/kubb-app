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
}
