// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get organizerDashboardEyebrow => 'Veranstalter · Cockpit';

  @override
  String get organizerDashboardTitle => 'Turnier-Steuerung';

  @override
  String get organizerDashboardTabTournaments => 'Turniere';

  @override
  String get organizerDashboardTabTeams => 'Veranstalterteams';

  @override
  String get organizerDashboardEmptyTitle => 'Keine Turniere zu verwalten';

  @override
  String get organizerDashboardEmptyBody =>
      'Sobald du ein Turnier veröffentlichst oder als Veranstalterteam verwaltest, erscheint es hier im Cockpit.';

  @override
  String get organizerDashboardGateTitle => 'Kein Zugriff';

  @override
  String get organizerDashboardGateBody =>
      'Du bist nicht berechtigt, dieses Turnier zu steuern. Wende dich an den Veranstalter oder das Veranstalterteam.';

  @override
  String get organizerDashboardError => 'Cockpit konnte nicht geladen werden.';

  @override
  String get organizerDashboardDetailEyebrow => 'Veranstalter · Ablauf';

  @override
  String get organizerDashboardRoundsTitle => 'Runden & Begegnungen';

  @override
  String get organizerDashboardNoMatches =>
      'Für dieses Turnier liegen noch keine Begegnungen vor.';

  @override
  String organizerDashboardRoundLabel(int round) {
    return 'Runde $round';
  }

  @override
  String organizerDashboardCurrentRound(int round) {
    return 'Runde $round';
  }

  @override
  String get organizerDashboardNoRound => 'Noch keine aktive Runde';

  @override
  String organizerDashboardOpenMatches(int count) {
    return '$count offen';
  }

  @override
  String organizerDashboardDisputedMatches(int count) {
    return '$count strittig';
  }

  @override
  String organizerDashboardRemaining(String time) {
    return 'Restzeit $time';
  }

  @override
  String get organizerDashboardExpired => 'Zeit abgelaufen';

  @override
  String get organizerScheduleStatusPublished => 'Veröffentlicht';

  @override
  String get organizerScheduleStatusCall => 'Aufruf';

  @override
  String get organizerScheduleStatusRunning => 'Läuft';

  @override
  String get organizerScheduleStatusAwaiting => 'Wartet auf Ergebnis';

  @override
  String get organizerScheduleStatusCompleted => 'Abgeschlossen';

  @override
  String get organizerScheduleStatusNone => 'Kein Zeitplan';

  @override
  String get organizerScheduleStatusPaused => 'Pausiert';

  @override
  String get organizerActionStart => 'Starten';

  @override
  String get organizerActionPause => 'Pause';

  @override
  String get organizerActionResume => 'Fortsetzen';

  @override
  String get organizerActionSkipForward => 'Vorspulen';

  @override
  String get organizerActionSkipBack => 'Neu aufrufen';

  @override
  String get organizerActionSkipForwardHoldHint =>
      'Zum Vorspulen gedrückt halten';

  @override
  String get organizerOpenDetail => 'Ablauf öffnen';

  @override
  String get organizerControlSectionTitle => 'Steuerung';

  @override
  String get organizerEscalationSectionTitle => 'Eingriffe';

  @override
  String organizerEscalationDisputedBadge(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count strittig',
      one: '1 strittig',
    );
    return '$_temp0';
  }

  @override
  String organizerEscalationOpenBadge(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count offen',
      one: '1 offen',
    );
    return '$_temp0';
  }

  @override
  String get organizerEscalationNone => 'Keine offenen Eingriffe';

  @override
  String get organizerKoTransitionAction => 'KO-Phase starten';

  @override
  String get organizerMatchActionOverride => 'Korrigieren';

  @override
  String get organizerMatchActionForfeit => 'Forfait';

  @override
  String get organizerPairNextRound => 'Nächste Runde paaren';

  @override
  String get stageGraphEyebrow => 'Turnier-Baukasten';

  @override
  String get stageGraphTitle => 'Stufen-Graph';

  @override
  String get stageGraphFieldSizeSection => 'Feldgrösse';

  @override
  String get stageGraphFieldSizeLabel => 'Anzahl Felder';

  @override
  String get stageGraphFieldSizeHint =>
      'Die Feldgrösse treibt die Kapazitäts- und Planbarkeits-Warnungen.';

  @override
  String get stageGraphNodesSection => 'Stufen';

  @override
  String get stageGraphAddNode => 'Stufe hinzufügen';

  @override
  String get stageGraphEditNode => 'Stufe bearbeiten';

  @override
  String get stageGraphDeleteNode => 'Stufe löschen';

  @override
  String stageGraphDeleteNodeConfirm(String id) {
    return 'Stufe „$id“ und alle damit verbundenen Kanten löschen?';
  }

  @override
  String get stageGraphEdgesSection => 'Kanten';

  @override
  String get stageGraphAddEdge => 'Kante hinzufügen';

  @override
  String get stageGraphEditEdge => 'Kante bearbeiten';

  @override
  String get stageGraphDeleteEdge => 'Kante löschen';

  @override
  String get stageGraphEdgesEmpty =>
      'Noch keine Kanten. Verbinde zwei Stufen, um Teilnehmer weiterzuleiten.';

  @override
  String get stageGraphEdgesNeedNodes =>
      'Mindestens zwei Stufen nötig, um eine Kante zu ziehen.';

  @override
  String get stageGraphValidationSection => 'Validierung';

  @override
  String get stageGraphPlayable => 'Spielbar';

  @override
  String get stageGraphNotPlayable => 'Nicht spielbar';

  @override
  String get stageGraphNoFindings => 'Spielbar — keine Befunde.';

  @override
  String get stageGraphSeverityError => 'Fehler';

  @override
  String get stageGraphSeverityWarning => 'Warnung';

  @override
  String get stageGraphTemplatesSection => 'Vorlagen';

  @override
  String get stageGraphTemplateApply => 'Anwenden';

  @override
  String get stageGraphTemplateSave => 'Als Vorlage speichern';

  @override
  String get stageGraphTemplateSystemBadge => 'Vorlage';

  @override
  String get stageGraphTemplatesEmpty => 'Keine Vorlagen verfügbar.';

  @override
  String get stageGraphTemplatesError =>
      'Vorlagen konnten nicht geladen werden.';

  @override
  String get stageGraphRetry => 'Erneut versuchen';

  @override
  String get stageGraphTemplatePickerLabel => 'Vorlage wählen';

  @override
  String get stageGraphTemplateSaved => 'Vorlage gespeichert.';

  @override
  String get stageGraphTemplateSaveError =>
      'Vorlage konnte nicht gespeichert werden.';

  @override
  String get stageGraphTemplateApplied => 'Vorlage angewendet.';

  @override
  String get stageGraphEmptyTitle => 'Noch kein Stufen-Graph';

  @override
  String get stageGraphEmptyBody =>
      'Füge eine erste Stufe hinzu oder wende eine Vorlage an, um das Turnier zu komponieren.';

  @override
  String get stageGraphFieldId => 'Stufen-Name';

  @override
  String get stageGraphFieldIdLockedHint =>
      'Der Name kann nicht geändert werden, solange Kanten daran hängen.';

  @override
  String get stageGraphFieldType => 'Typ';

  @override
  String get stageGraphFieldSeeding => 'Seeding';

  @override
  String get stageGraphConfigGroupCount => 'Gruppen';

  @override
  String get stageGraphConfigQualifierCount => 'Qualifikanten';

  @override
  String get stageGraphConfigRounds => 'Runden';

  @override
  String get stageGraphConfigSlots => 'Plätze';

  @override
  String get stageGraphConfigRandomSeed => 'Zufalls-Seed';

  @override
  String get stageGraphConfigKoRoundCount => 'Anzahl K.-o.-Runden';

  @override
  String get stageGraphConfigKoRoundsRulesLabel => 'Rundenregeln';

  @override
  String stageGraphConfigKoRoundTitle(String n) {
    return 'Runde $n';
  }

  @override
  String get stageGraphConfigGroupCountHint =>
      'In wie viele Gruppen das Feld aufgeteilt wird.';

  @override
  String get stageGraphConfigQualifierHint =>
      'Qualifikanten zählen pro Gruppe, nicht über alle Gruppen zusammen: bei 2 ziehen die besten 2 jeder Gruppe weiter.';

  @override
  String stageGraphConfigGroupPitchSummary(int count) {
    return 'Pitches: $count Gruppen zugeteilt';
  }

  @override
  String get stageGraphConfigSwissHint =>
      'Anzahl der Schoch-Runden. Die Paarungen jeder Runde entstehen live nach Tabellenstand.';

  @override
  String get stageGraphConfigWithReset => 'Grand-Final-Reset';

  @override
  String get stageGraphConfigWithResetHint =>
      'Gewinnt das Team aus dem Verlierer-Bracket das erste Finale, gibt es ein zweites, entscheidendes Finale (beide haben dann genau eine Niederlage).';

  @override
  String get stageGraphConfigBracketAuto =>
      'Das Bracket wird automatisch aus der Setzliste gebaut — keine weitere Konfiguration nötig.';

  @override
  String get stageGraphErrorIdEmpty => 'Die ID darf nicht leer sein.';

  @override
  String get stageGraphErrorNameEmpty => 'Der Name darf nicht leer sein.';

  @override
  String get stageGraphErrorIdDuplicate => 'Diese ID existiert bereits.';

  @override
  String get stageGraphEdgeFrom => 'Von';

  @override
  String get stageGraphEdgeTo => 'Nach';

  @override
  String get stageGraphEdgeSelectorLabel => 'Selektor';

  @override
  String get stageGraphEdgeSeedingInLabel => 'Seeding-Modus';

  @override
  String get stageGraphErrorSameNode =>
      'Quelle und Ziel müssen verschieden sein.';

  @override
  String get stageGraphErrorRankOrder =>
      '„Von“ muss kleiner oder gleich „Nach“ sein.';

  @override
  String get stageGraphErrorRoundsEmpty =>
      'Bitte mindestens eine Runde angeben.';

  @override
  String get stageGraphSelectorRoundsLabel => 'Runden (kommagetrennt)';

  @override
  String get stageGraphSelectorRankFrom => 'Rang von';

  @override
  String get stageGraphSelectorRankTo => 'Rang bis';

  @override
  String get stageGraphSelectorK => 'Anzahl (Top K)';

  @override
  String stageGraphSelectorTopK(int k) {
    return 'Top $k';
  }

  @override
  String stageGraphSelectorRanks(int from, int to) {
    return 'Ränge $from–$to';
  }

  @override
  String stageGraphSelectorLosers(String rounds) {
    return 'Verlierer Runden $rounds';
  }

  @override
  String get stageGraphSelectorWinners => 'Sieger';

  @override
  String get stageGraphSelectorNonQualifiers => 'Übrige';

  @override
  String get stageGraphSelectorHintTopK =>
      'Die besten K jeder Quell-Stufe ziehen weiter — z. B. Top 2 jeder Gruppe.';

  @override
  String get stageGraphSelectorHintRanks =>
      'Ein zusammenhängender Rangbereich der Quell-Stufe zieht weiter — z. B. Ränge 3–4 für ein zweites Tableau.';

  @override
  String get stageGraphSelectorHintLosers =>
      'Verlierer bestimmter K.-o.-Runden werden weitergeleitet — so speist man Trost-/Neben-Cups.';

  @override
  String get stageGraphSelectorHintWinners =>
      'Alle Sieger der Quell-Stufe ziehen weiter.';

  @override
  String get stageGraphSelectorHintNonQualifiers =>
      'Alle, die sich NICHT qualifiziert haben, ziehen weiter — z. B. in einen Neben-Cup.';

  @override
  String get stageGraphEdgesMultiHint =>
      'Eine Stufe darf mehrere Kanten haben: z. B. Sieger ins Haupt-Bracket UND Verlierer früher Runden in einen Neben-Cup.';

  @override
  String get stageGraphNodeTypePool => 'Gruppenphase';

  @override
  String get stageGraphNodeTypeRoundRobin => 'Jeder gegen jeden';

  @override
  String get stageGraphNodeTypeSwiss => 'Schoch';

  @override
  String get stageGraphNodeTypeSingleElim => 'K.-o. (einfach)';

  @override
  String get stageGraphNodeTypeDoubleElim => 'K.-o. (doppelt)';

  @override
  String get stageGraphNodeTypeConsolation => 'Trosttournier';

  @override
  String get stageGraphNodeTypeShootoutQuali => 'Shoot-out-Quali';

  @override
  String get stageGraphNodeTypeInfoTitle => 'Stufentyp';

  @override
  String get stageGraphNodeTypeInfoPool =>
      'Jeder spielt in seiner Gruppe gegen jeden. Aus jeder Gruppe ziehen die Bestplatzierten weiter. Bei n Teilnehmern pro Gruppe sind das n-1 Runden.';

  @override
  String get stageGraphNodeTypeInfoSwiss =>
      'Schoch: die Paarungen werden nach jeder Runde neu nach Tabellenstand gebildet — Sieger gegen Sieger, Verlierer gegen Verlierer. Flexible Rundenzahl, ein gemeinsamer Pool. Ideal für grosse Felder, weil nicht jeder gegen jeden spielen muss.';

  @override
  String get stageGraphNodeTypeInfoSingleElim =>
      'Wer ein Spiel verliert, ist raus. Schnell und kurz, aber eine einzige Niederlage beendet das Turnier.';

  @override
  String get stageGraphNodeTypeInfoDoubleElim =>
      'Erst nach der zweiten Niederlage ist man raus (Verliererbracket). Fairer als einfaches K.-o., braucht aber mehr Spiele und Zeit.';

  @override
  String get stageGraphNodeTypeInfoConsolation =>
      'Nebenwettbewerb für früh ausgeschiedene Teams, damit sie weiterspielen. Beeinflusst die Hauptwertung nicht.';

  @override
  String get stageGraphNodeTypeInfoRoundRobin =>
      'Jeder spielt gegen jeden. Die Tabelle entscheidet, niemand scheidet vorzeitig aus.';

  @override
  String get stageGraphNodeTypeInfoShootoutQuali =>
      'Qualifikation per Shoot-out: die besten Würfe sichern die Startplätze für die nächste Stufe.';

  @override
  String get stageGraphSeedingFromElo => 'Aus ELO-Wertung';

  @override
  String get stageGraphSeedingFromPrevRanking => 'Aus Vorrangliste';

  @override
  String get stageGraphSeedingManual => 'Manuell';

  @override
  String get stageGraphSeedingRandom => 'Zufall';

  @override
  String get stageGraphSeedingAsRouted => 'Wie geroutet';

  @override
  String get stageGraphSeedingInOrderPreserving => 'Reihenfolge erhalten';

  @override
  String get stageGraphSeedingInReseedBySourceRank => 'Neu nach Quell-Rang';

  @override
  String get stageGraphSeedingInManual => 'Manuell';

  @override
  String get stageGraphSeedingInInfoTitle => 'Seeding-Modus';

  @override
  String get stageGraphSeedingInInfoOrderPreserving =>
      'Die weitergeleiteten Teams behalten die Reihenfolge aus der Quell-Stufe.';

  @override
  String get stageGraphSeedingInInfoReseedBySourceRank =>
      'Die Teams werden anhand ihres Rangs in der Quell-Stufe neu gesetzt, bevor sie in die nächste Stufe gehen.';

  @override
  String get stageGraphSeedingInInfoManual =>
      'Du legst die Setzung der weitergeleiteten Teams selbst fest. Achtung: das kann den Phasenstart blockieren, bis die Setzung gespeichert ist.';

  @override
  String get stageGraphInfoTemplateTitle => 'Vorlage wählen';

  @override
  String get stageGraphInfoTemplateBody =>
      'Statt alles neu zu bauen, kannst du eine gespeicherte Vorlage laden und als Ausgangspunkt nutzen. Anwenden übernimmt die komplette Konfiguration der Vorlage in deinen Aufbau.';

  @override
  String get stageGraphInfoNodeNameTitle => 'Name der Stufe';

  @override
  String get stageGraphInfoNodeNameBody =>
      'Frei wählbarer Name, um die Stufe im Graphen zu erkennen (z. B. \"Gruppenphase\", \"Hauptbaum\"). Der Name lässt sich nicht mehr ändern, solange Kanten daran hängen.';

  @override
  String get stageGraphInfoSeedingSourceTitle =>
      'Woher die Startreihenfolge kommt';

  @override
  String get stageGraphInfoSeedingSourceBody =>
      'Legt fest, woher die Setzliste für diese Stufe stammt: aus der ELO-Wertung, aus einer Vorrangliste, von dir manuell gesetzt, oder \"wie geroutet\" (in der Reihenfolge, in der die Teams aus der vorherigen Stufe ankommen).';

  @override
  String get stageGraphInfoGroupCountTitle => 'Anzahl Gruppen';

  @override
  String get stageGraphInfoGroupCountBody =>
      'In wie viele Gruppen das Feld dieser Stufe aufgeteilt wird.';

  @override
  String get stageGraphInfoQualifierTitle =>
      'Wie viele pro Gruppe weiterkommen';

  @override
  String get stageGraphInfoQualifierBody =>
      'Qualifikanten zählen pro Gruppe, nicht über alle Gruppen zusammen: bei 2 ziehen die besten 2 jeder Gruppe weiter.';

  @override
  String get stageGraphInfoKoMatchupTitle => 'Wer gegen wen';

  @override
  String get stageGraphInfoKoMatchupBody =>
      'Bestimmt die Paarungen im K.-o. \"Beste vs. Schlechteste\" lässt die stärksten gegen die schwächsten antreten, \"1. vs. 2.\" paart benachbarte Ränge.';

  @override
  String get stageGraphInfoKoTiebreakTitle => 'Entscheid bei Gleichstand';

  @override
  String get stageGraphInfoKoTiebreakBody =>
      'Wie ein unentschiedenes K.-o.-Spiel entschieden wird: \"Klassisch\" oder \"Mighty-Finisher\". Beim Mighty-Finisher wird ein zeitbegrenztes Spiel zu Ende gespielt, sobald die Zeit abgelaufen ist; steht es danach unentschieden, folgt ein Entscheidungssatz nach den festgelegten Finisher-Regeln. \"Klassisch\" ist der herkömmliche Entscheid ohne Zeit-Finisher. Der Mighty-Finisher ist nicht dasselbe wie das Shoot-out: das Shoot-out ist ein eigenes Konzept und löst beim Übergang Vorrunde→K.-o. ein platzierungsrelevantes Unentschieden auf, nicht ein einzelnes K.-o.-Spiel. Nur im K.-o. relevant, die Vorrunde hat keinen Tiebreak.';

  @override
  String get stageGraphInfoKoResetTitle => 'Zweites Finale möglich';

  @override
  String get stageGraphInfoKoResetBody =>
      'Nur beim doppelten K.-o.: gewinnt das Team aus dem Verliererbaum das erste Finale, gibt es ein zweites, entscheidendes Finale (beide haben dann genau eine Niederlage).';

  @override
  String get stageGraphInfoKoRoundCountTitle => 'Wie viele Runden';

  @override
  String get stageGraphInfoKoRoundCountBody =>
      'Legt fest, über wie viele Runden der K.-o.-Baum dieser Stufe gespielt wird.';

  @override
  String get stageGraphInfoKoRoundTitle => 'Regeln je Runde';

  @override
  String get stageGraphInfoKoRoundBody =>
      'Pro K.-o.-Runde einstellbar: wie viele Sätze zum Sieg nötig sind, das Zeitlimit pro Spiel, die Pause danach und ob ein Tiebreak greift. Spätere Runden dürfen länger angesetzt sein als frühe.';

  @override
  String get stageGraphEdgeConnectionLabel => 'Verbindung';

  @override
  String get stageGraphInfoEdgeFromToTitle => 'Verbindung zwischen Stufen';

  @override
  String get stageGraphInfoEdgeFromToBody =>
      'Eine Kante leitet Teilnehmer von einer Stufe (Von) in die nächste (Nach) weiter. So baust du den Ablauf zusammen. Eine Stufe darf mehrere Kanten haben — z. B. Sieger ins Hauptbaum UND Verlierer in einen Neben-Cup.';

  @override
  String get stageGraphInfoSelectorTitle => 'Selektor — wer weiterkommt';

  @override
  String get stageGraphInfoSelectorIntro =>
      'Bestimmt, welche Teams diese Kante in die nächste Stufe weiterleitet.';

  @override
  String get stageGraphSaveTemplateName => 'Name';

  @override
  String get stageGraphSaveTemplateVisibility => 'Sichtbarkeit';

  @override
  String get stageGraphVisibilityPrivate => 'Privat (nur ich)';

  @override
  String get stageGraphVisibilityClub => 'Verein/Organisation';

  @override
  String get stageGraphVisibilityPublic => 'Öffentlich';

  @override
  String get stageGraphSaveTemplateClubUnavailable =>
      'Für Verein/Organisation muss ein Veranstalter gewählt sein.';

  @override
  String get stageGraphConfirm => 'Bestätigen';

  @override
  String get stageGraphCancel => 'Abbrechen';

  @override
  String get stageGraphViewForm => 'Formular';

  @override
  String get stageGraphViewCanvas => 'Canvas';

  @override
  String get stageGraphCanvasEmpty =>
      'Noch keine Stufen. Füge eine Stufe hinzu, um den Graphen zu zeichnen.';

  @override
  String get stageGraphCanvasOutPort => 'Kante ziehen';

  @override
  String get stageGraphCanvasInPort => 'Eingang';

  @override
  String stageGraphCanvasDeleteEdge(String from, String to) {
    return 'Kante „$from → $to“ löschen?';
  }

  @override
  String stageGraphSeedingFieldHint(String label) {
    return 'Seeding: $label';
  }

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
  String get trainingHubMatchTitle => 'Match';

  @override
  String get trainingHubMatchSubtitle => 'Mehrspieler · Bo1/3/5';

  @override
  String get trainingHubStatsSubtitle => 'Verlauf & Bestwerte';

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
  String get homeAppTitle => 'Kubb Club';

  @override
  String get homeEyebrow => 'Kubb Club';

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
  String get statsHitsLabel => 'Treffer';

  @override
  String get statsMissesLabel => 'Fehlwürfe';

  @override
  String get statsHeliLabel => 'Helikopter';

  @override
  String get statsHeliQuotaLabel => 'Heli-Quote';

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
  String get settingsLegalSection => 'Rechtliches';

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
  String get settingsRowResetSessions => 'Trainings-Sessions zurücksetzen';

  @override
  String get settingsRowResetSessionsSub => 'lokal und auf dem Server löschen';

  @override
  String get settingsRowDeleteProfile => 'Profil löschen';

  @override
  String get settingsRowDeleteProfileSub =>
      'Profil und alle Sessions entfernen';

  @override
  String get settingsPrivacyHeader => 'Datenschutz';

  @override
  String get settingsPrivacyBody =>
      'Lokale Daten (Trainings-Sessions, lokale Drafts) bleiben auf deinem Gerät. Matches, Turniere, Freundschaften und Inbox-Nachrichten werden mit unserem Supabase-Backend in der EU synchronisiert, damit du Geräte wechseln kannst und Mitspieler dich sehen können.';

  @override
  String get settingsPrivacyLinkLabel => 'Datenschutzerklärung öffnen';

  @override
  String get settingsVisibilitySection => 'Profil';

  @override
  String get settingsRowVisibility => 'Profil-Sichtbarkeit';

  @override
  String get settingsRowVisibilitySub => 'Wer dein Profil sehen kann';

  @override
  String get settingsVisibilityPublic => 'Öffentlich';

  @override
  String get settingsVisibilityFriendsOnly => 'Nur Freunde';

  @override
  String get settingsVisibilityPrivate => 'Privat';

  @override
  String get settingsVisibilityPickerTitle => 'Profil-Sichtbarkeit';

  @override
  String get settingsVisibilitySavedSnack => 'Sichtbarkeit gespeichert';

  @override
  String get settingsVisibilityErrorSnack =>
      'Sichtbarkeit konnte nicht gespeichert werden';

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
      'Alle Trainings-Sessions werden unwiderruflich gelöscht — lokal und auf dem Server. Dein Profil bleibt bestehen.';

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
  String get authAppName => 'Kubb Club';

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
  String get authSignupNicknameAvatarHint => 'Dein Avatar-Buchstabe';

  @override
  String get authSignupNicknameRecoveryHint =>
      'Anonyme Sessions kannst du via Recovery-Phrase auf ein neues Gerät übertragen — die Wörter generieren wir gleich.';

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
      'Kubb Club hilft dir, deine Würfe systematisch zu verbessern — Sniper, Finisseur, und bald mehr.';

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
  String get tournamentWizardStep3Title => 'Vorrunde';

  @override
  String get tournamentWizardStepGroupPhaseTitle => 'Gruppenphase';

  @override
  String get tournamentWizardStep4Title => 'Übersicht';

  @override
  String tournamentWizardStepLabel(int step, int total) {
    return 'Schritt $step von $total';
  }

  @override
  String get tournamentWizardDisplayNameLabel => 'Turniername';

  @override
  String get tournamentWizardDisplayNameYearHint =>
      'Die Jahreszahl wird automatisch angehängt (z.B. 2026).';

  @override
  String get tournamentWizardClubLabel => 'Ausrichtendes Veranstalterteam';

  @override
  String get tournamentWizardClubHint =>
      'Veranstalterteams, die du verwalten kannst, können dieses Turnier ebenfalls verwalten. Ohne Veranstalterteam (Spasstournier) zählt das Turnier nicht für die Wertung.';

  @override
  String get tournamentWizardClubNone => 'Spasstournier – ohne Wertung';

  @override
  String get tournamentWizardClubChoosePrompt => 'Bitte wählen';

  @override
  String get tournamentWizardInviteOnlyLabel => 'Auf Einladung';

  @override
  String get tournamentWizardInviteOnlyHint =>
      'Nur eingeladene Spieler sehen dieses Turnier und können sich anmelden.';

  @override
  String get tournamentWizardInviteSearchHint => 'Spielername suchen…';

  @override
  String get tournamentWizardInvitedPlayersLabel => 'Eingeladene Spieler';

  @override
  String tournamentWizardInviteNoResults(String query) {
    return 'Niemand gefunden für „$query\".';
  }

  @override
  String tournamentWizardInviteSearchError(String error) {
    return 'Suche fehlgeschlagen: $error';
  }

  @override
  String get tournamentWizardInviteAddAction => 'Einladen';

  @override
  String get tournamentWizardInviteRemoveTooltip => 'Einladung entfernen';

  @override
  String tournamentWizardInvitePartialError(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Einladungen konnten nicht gesendet werden.',
      one: 'Eine Einladung konnte nicht gesendet werden.',
    );
    return '$_temp0';
  }

  @override
  String get tournamentWizardLocationLabel => 'Ort';

  @override
  String get tournamentWizardLocationHint => 'z.B. Sportplatz Esp, Fislisbach';

  @override
  String get tournamentWizardEventDateLabel => 'Datum & Startzeit';

  @override
  String get tournamentWizardRegistrationDeadlineLabel => 'Anmeldeschluss';

  @override
  String get tournamentWizardCheckinUntilLabel => 'Vor-Ort-Check-in bis';

  @override
  String get tournamentWizardDateNotSet => 'Nicht gesetzt';

  @override
  String get tournamentWizardOptional => 'optional';

  @override
  String get tournamentWizardHelpToggle => 'Erklärungen';

  @override
  String get tournamentWizardLeagueCategoriesLabel => 'Liga-Kategorien';

  @override
  String get tournamentWizardLeagueCategoriesHint =>
      'Für welche Liga zählt dieses Turnier? Mehrfachauswahl möglich.';

  @override
  String tournamentWizardLeagueCategory(String category) {
    return 'Liga $category';
  }

  @override
  String get tournamentWizardScoringLabel => 'Wertung';

  @override
  String get tournamentWizardScoringEkc => 'EKC';

  @override
  String get tournamentWizardScoringEkcHint =>
      '1 Punkt pro Basekubb + 3 für den Satz';

  @override
  String get tournamentWizardScoringClassic => 'Klassisch';

  @override
  String get tournamentWizardScoringClassicHint => 'Nur Satzsieg zählt';

  @override
  String get tournamentWizardSeedingSourceLabel => 'Seeding-Quelle';

  @override
  String get tournamentWizardSeedingSourceAuto => 'Automatisch aus Vorrunde';

  @override
  String get tournamentWizardSeedingSourceManual => 'Manuell festlegen';

  @override
  String get tournamentWizardSectionParticipation => 'Teilnahme';

  @override
  String get tournamentWizardSectionRules => 'Regeln & Dokumente';

  @override
  String get tournamentWizardSectionInfo => 'Infos für Teilnehmer';

  @override
  String get tournamentWizardSectionEckdaten => 'Eckdaten';

  @override
  String get tournamentWizardSectionPlay => 'Spielregeln';

  @override
  String get tournamentWizardSectionDocuments => 'Dokumente';

  @override
  String get tournamentWizardSectionPayment => 'Kosten & Zahlung';

  @override
  String get tournamentWizardSectionContact => 'Kontakt';

  @override
  String get tournamentWizardCheckinUntilHelper =>
      'Bis dahin müssen Angemeldete vor Ort bestätigen.';

  @override
  String get tournamentWizardVenueAddressLabel => 'Adresse';

  @override
  String get tournamentWizardVenueAddressHint => 'Strasse, PLZ Ort';

  @override
  String get tournamentWizardEntryFeeLabel => 'Teilnahmegebühr (CHF)';

  @override
  String get tournamentWizardEntryFeeHint => 'z.B. 10';

  @override
  String get tournamentWizardPaymentMethodsLabel => 'Zahlungsarten';

  @override
  String get tournamentWizardPaymentCash => 'Bar';

  @override
  String get tournamentWizardPaymentTwint => 'Twint';

  @override
  String get tournamentWizardPaymentCard => 'Karte';

  @override
  String get tournamentWizardContactNameLabel => 'Kontaktperson';

  @override
  String get tournamentWizardContactPhoneLabel => 'Kontakt-Telefon';

  @override
  String get tournamentWizardContactPhoneHint =>
      'Für kurzfristige Ab-/Ummeldungen';

  @override
  String get tournamentWizardInfoFoodLabel => 'Verpflegung';

  @override
  String get tournamentWizardInfoTravelLabel => 'Anfahrt';

  @override
  String get tournamentWizardInfoAccommodationLabel => 'Übernachtung';

  @override
  String get tournamentWizardWeatherLabel => 'Wetter-Hinweis';

  @override
  String get tournamentWizardOpeningRuleLabel => 'Anspielregel';

  @override
  String get tournamentWizardRuleSureshot => 'Sureshot';

  @override
  String get tournamentWizardRuleSureshotHint =>
      'König muss rückwärts zwischen den Beinen geworfen werden';

  @override
  String get tournamentWizardRuleDiggy => 'Diggy-Regel';

  @override
  String get tournamentWizardRuleDiggyHint =>
      'Doppel-Chriesi dürfen aufgestellt werden';

  @override
  String get tournamentWizardRuleOpeningLabel => 'Anspielregel';

  @override
  String get tournamentWizardRuleOpening246 => '2-4-6';

  @override
  String get tournamentWizardRuleOpeningFree => 'Frei';

  @override
  String get tournamentWizardRuleOpeningHint =>
      'Reihenfolge beim Anspiel (Standard: 2-4-6).';

  @override
  String get tournamentWizardRuleStrafkubb => 'Strafkubb mit Abstand';

  @override
  String get tournamentWizardRuleStrafkubbHint =>
      'Strafkubb mind. eine Stocklänge von der Grundlinie';

  @override
  String get tournamentWizardRulesPdfLabel => 'Regelwerk (PDF)';

  @override
  String get tournamentWizardSiteMapPdfLabel => 'Lageplan (PDF)';

  @override
  String get tournamentWizardPdfUpload => 'PDF hochladen';

  @override
  String get tournamentWizardPdfUploaded => 'Hochgeladen';

  @override
  String get tournamentWizardPdfUploading => 'Lädt hoch …';

  @override
  String get tournamentWizardPdfRemove => 'Entfernen';

  @override
  String get tournamentWizardPdfUploadError => 'Upload fehlgeschlagen';

  @override
  String get tournamentWizardMinTeamSizeLabel => 'Min. Spieler / Team';

  @override
  String get tournamentWizardMaxTeamSizeLabel => 'Max. Spieler / Team';

  @override
  String get tournamentWizardTeamSizeHint =>
      'Spieler pro Team — Min. = Max. = feste Grösse, 1 = Einzelturnier';

  @override
  String get tournamentWizardSectionPitches => 'Pitches / Spielfelder';

  @override
  String get tournamentWizardPitchHint =>
      'Auf welchen Feldern wird gespielt? Kann auch später gesetzt werden.';

  @override
  String get tournamentWizardPitchModeRange => 'Nummernbereich';

  @override
  String get tournamentWizardPitchModeManual => 'Manuelle Liste';

  @override
  String get tournamentWizardPitchRangeFrom => 'Von';

  @override
  String get tournamentWizardPitchRangeTo => 'Bis';

  @override
  String get tournamentWizardPitchNumbersLabel => 'Pitch-Nummern';

  @override
  String get tournamentWizardPitchNumbersHint => 'z.B. 1, 2, 5, 8';

  @override
  String get tournamentWizardPitchSortLabel => 'Sortierung';

  @override
  String get tournamentWizardPitchSortTopSeeds => 'Beste auf tiefsten Nummern';

  @override
  String get tournamentWizardPitchSortManual => 'Manuelle Reihenfolge';

  @override
  String get tournamentWizardPitchOrderLabel => 'Reihenfolge der Felder';

  @override
  String get tournamentWizardPitchOrderHint =>
      'Per Drag die gewünschte Reihenfolge der Feldnummern festlegen.';

  @override
  String tournamentWizardPitchOrderItem(int number) {
    return 'Feld $number';
  }

  @override
  String tournamentWizardPitchSummary(int count) {
    return '$count Pitches';
  }

  @override
  String get tournamentWizardPoolPitchAssignmentLabel =>
      'Pitch-Zuteilung pro Gruppe';

  @override
  String get tournamentWizardPoolPitchAssignmentHint =>
      'Wähle pro Gruppe die Pitch-Nummern. Die höchstgerankten Spieler werden auf die zuerst gelisteten Pitches gesetzt (Sortierung folgt der Pitch-Strategie).';

  @override
  String tournamentWizardPoolGroupLabel(String label) {
    return 'Gruppe $label';
  }

  @override
  String get tournamentWizardPoolGroupCountLabel => 'Anzahl Gruppen';

  @override
  String tournamentWizardPoolGroupCountRangeError(int min, int max) {
    return 'Wert zwischen $min und $max erforderlich.';
  }

  @override
  String tournamentWizardPoolDivisibilityError(int koSize) {
    return 'Gruppen müssen die KO-Grösse ($koSize) glatt teilen.';
  }

  @override
  String get tournamentWizardPoolQualifiersPerGroupLabel =>
      'Qualifier pro Gruppe';

  @override
  String get tournamentWizardPoolQualifiersPerGroupHint =>
      'Wird aus K.-o.-Grösse und Gruppenzahl berechnet. Steht erst nach dem K.-o.-Schritt.';

  @override
  String get tournamentWizardPoolStrategyLabel => 'Gruppierungsstrategie';

  @override
  String get tournamentWizardPoolStrategySnake => 'Snake / Reissverschluss';

  @override
  String get tournamentWizardPoolStrategySeeded => 'Seeded (Blockweise)';

  @override
  String get tournamentWizardPoolStrategyRandom => 'Random (deterministisch)';

  @override
  String get stageGraphGroupingInfoTitle => 'Gruppierungsstrategie';

  @override
  String get stageGraphGroupingInfoSnake =>
      'Reissverschluss: stärkste und schwächste Teams werden abwechselnd auf die Gruppen verteilt, damit die Gruppen etwa gleich stark sind.';

  @override
  String get stageGraphGroupingInfoSeeded =>
      'Blockweise nach Setzung: die Top-Teams werden der Reihe nach auf die Gruppen verteilt.';

  @override
  String get stageGraphGroupingInfoRandom =>
      'Zufällige Verteilung auf die Gruppen. Mit gesetztem Seed reproduzierbar.';

  @override
  String get tournamentWizardPoolRandomSeedLabel => 'Random-Seed (optional)';

  @override
  String get tournamentWizardPoolRandomSeedHint =>
      'Gleicher Seed erzeugt dieselbe Verteilung. Leer lassen mischt jedes Mal neu.';

  @override
  String get tournamentWizardMatchTimeLabel => 'Zeit pro Match (Min.)';

  @override
  String get tournamentWizardBreakBetweenLabel =>
      'Pause zwischen Matches (Min.)';

  @override
  String get tournamentWizardBracketTypeLabel => 'Bracket-Typ';

  @override
  String get tournamentWizardBracketSingle => 'Single-KO';

  @override
  String get tournamentWizardBracketDouble => 'Double-KO';

  @override
  String get tournamentWizardKoMatchupLabel => 'Begegnungen';

  @override
  String get tournamentWizardKoMatchupHighLow => 'Beste vs Schlechteste';

  @override
  String get tournamentWizardKoMatchupOneTwo => '1. vs 2.';

  @override
  String get tournamentWizardKoTiebreakMethodLabel => 'KO-Tiebreak-Methode';

  @override
  String get tournamentWizardKoTiebreakClassic => 'Klassisch';

  @override
  String get tournamentWizardKoTiebreakMighty => 'Mighty-Finisher';

  @override
  String get tournamentWizardKoRulesLabel => 'KO-Regelsatz';

  @override
  String get tournamentWizardKoRoundRulesLabel => 'Regeln pro KO-Runde';

  @override
  String get tournamentWizardKoRoundRulesHint =>
      'Sätze, Zeit und Pause können pro Runde gewählt werden.';

  @override
  String get tournamentWizardKoRoundFinal => 'Final';

  @override
  String get tournamentWizardKoRoundSemi => 'Halbfinale';

  @override
  String get tournamentWizardKoRoundQuarter => 'Viertelfinale';

  @override
  String get tournamentWizardKoRoundEighth => 'Achtelfinale';

  @override
  String tournamentWizardKoRoundOf(int size) {
    return '1/$size-Final';
  }

  @override
  String get tournamentWizardKoRoundPauseLabel => 'Pause danach (Min.)';

  @override
  String get tournamentWizardKoRoundTiebreakLabel => 'Tiebreak';

  @override
  String get tournamentWizardKoFinalNoTiebreak => 'Ab Halbfinale ohne Tiebreak';

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
  String get tournamentWizardFormatModeLabel => 'Turnierformat';

  @override
  String get tournamentWizardFormatModeClassic => 'Klassisch';

  @override
  String get tournamentWizardFormatModeClassicHint =>
      'Vorrunde (Gruppenphase oder Schoch) und ein K.-o.-Baum.';

  @override
  String get tournamentWizardFormatModeStageGraph => 'Stufen-Graph';

  @override
  String get tournamentWizardFormatModeStageGraphHint =>
      'Eigene Stufen frei verketten – Haupt- und Neben-Cups möglich.';

  @override
  String get tournamentWizardStageGraphSourceLabel => 'Stufen-Graph';

  @override
  String get tournamentWizardStageGraphSourceBuild => 'Neu erstellen';

  @override
  String get tournamentWizardStageGraphSourceBuildHint =>
      'Stufen und Routing von Hand komponieren.';

  @override
  String get tournamentWizardStageGraphSourceTemplate => 'Vorlage wählen';

  @override
  String get tournamentWizardStageGraphSourceTemplateHint =>
      'Mit einer gespeicherten oder System-Vorlage starten.';

  @override
  String get tournamentWizardStageGraphEmbedHint =>
      'Stufen, Routing und Validierung direkt hier komponieren.';

  @override
  String get tournamentWizardVorrundeLabel => 'Vorrunde';

  @override
  String get tournamentWizardVorrundeGroupPhase => 'Gruppenphase';

  @override
  String get tournamentWizardVorrundeGroupPhaseHint =>
      'Jeder gegen jeden, Rangliste entscheidet.';

  @override
  String get tournamentWizardVorrundeSchoch => 'Schoch';

  @override
  String get tournamentWizardVorrundeSchochHint =>
      'Schoch-Paarung über mehrere Runden, dann Rangliste.';

  @override
  String get tournamentWizardKoSystemLabel => 'K.-o.-System';

  @override
  String get tournamentWizardKoSystemSingle => 'Single-Out';

  @override
  String get tournamentWizardKoSystemSingleHint =>
      'Eine Niederlage und du bist raus.';

  @override
  String get tournamentWizardKoSystemDouble => 'Double-Elimination';

  @override
  String get tournamentWizardKoSystemDoubleHint =>
      'Erst nach zwei Niederlagen ausgeschieden.';

  @override
  String get tournamentWizardKoSystemConsolation => 'Trostturnier';

  @override
  String get tournamentWizardKoSystemConsolationHint =>
      'Single-Out plus separates Nebenturnier für die hinteren Plätze.';

  @override
  String get tournamentKoModelExplainerOpen => 'K.-o.-Systeme erklärt';

  @override
  String get tournamentKoModelExplainerLink => 'Modelle vergleichen';

  @override
  String get tournamentKoModelExplainerTitle => 'Welcher zweite Baum?';

  @override
  String get tournamentKoModelExplainerSingleOutHeading => 'Single-Out';

  @override
  String get tournamentKoModelExplainerSingleOutBody =>
      'Eine Niederlage und du bist draussen. Der Final entscheidet Platz 1 und 2, dazu gibt es ein Spiel um Platz 3. Schnell und einfach.';

  @override
  String get tournamentKoModelExplainerDoubleElimHeading =>
      'Double-Elimination';

  @override
  String get tournamentKoModelExplainerDoubleElimBody =>
      'Du musst zweimal verlieren, um auszuscheiden. Wer im Hauptbaum verliert, fällt in den Verliererbaum und kann sich von dort bis ins Finale zurückkämpfen — der Verliererbaum-Sieger kann am Ende noch Turniersieger werden. Sportlich am fairsten, aber mehr Spiele.';

  @override
  String get tournamentKoModelExplainerTrostturnierHeading => 'Trostturnier';

  @override
  String get tournamentKoModelExplainerTrostturnierBody =>
      'Der Hauptbaum entscheidet Platz 1 und 2 endgültig. Wer im Hauptbaum ausscheidet (ausser den Halbfinal-Verlierern, die um Platz 3 spielen), kommt ins Trostturnier und spielt dort die hinteren Plätze aus. Optional starten zusätzlich einige Teams direkt aus der Vorrunde im Trostturnier. Es gibt keinen Weg zurück ins Finale — aber alle bekommen mehr Spiele und eine Platzierung.';

  @override
  String get tournamentWizardConsolationMainBracketSizeLabel =>
      'Hauptbaum-Grösse';

  @override
  String get tournamentWizardConsolationDirectCountLabel =>
      'Direkt ins Trostturnier';

  @override
  String get tournamentWizardConsolationDirectCountHint =>
      'Wie viele Vorrunden-Teams starten direkt im Trostturnier (zusätzlich zu den Hauptbaum-Verlierern).';

  @override
  String get tournamentWizardConsolationNameLabel => 'Name des Trostturniers';

  @override
  String get tournamentWizardConsolationNameHint => 'z. B. Bâton Rouille';

  @override
  String get tournamentWizardConsolationSectionLabel =>
      'Trostturnier (Nebenturnier)';

  @override
  String get tournamentWizardConsolationDirectCountNone => 'Keine';

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
  String get tournamentWizardSaveButton => 'Änderungen speichern';

  @override
  String get tournamentWizardEditTitle => 'Turnier bearbeiten';

  @override
  String tournamentWizardSubmitError(String error) {
    return 'Turnier konnte nicht erstellt werden: $error';
  }

  @override
  String get tournamentEditStructureLocked =>
      'Strukturänderung nicht möglich – die Phase läuft bereits. Metadaten und künftige Runden-Einstellungen bleiben änderbar.';

  @override
  String get tournamentEditTournamentLocked =>
      'Turnier ist abgeschlossen oder abgebrochen – eine Bearbeitung ist nicht mehr möglich.';

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
  String get tournamentHubLiveTitle => 'Live Turniere';

  @override
  String get tournamentHubLiveSubtitle => 'Deine laufenden Turniere';

  @override
  String get tournamentHubLivePickerTitle => 'Live Turnier wählen';

  @override
  String get tournamentHubLiveEmptyTitle => 'Kein laufendes Turnier';

  @override
  String get tournamentHubLiveEmptyBody =>
      'Sobald eines deiner Turniere startet, erscheint es hier.';

  @override
  String get tournamentHubUpcomingTitle => 'Künftige Turniere';

  @override
  String get tournamentHubUpcomingSubtitle => 'Anstehende Turniere entdecken';

  @override
  String get tournamentHubCreateTitle => 'Turnier erstellen';

  @override
  String get tournamentHubCreateSubtitle => 'Als Veranstalter publizieren';

  @override
  String get tournamentHubStatsTitle => 'Turnierstatistik';

  @override
  String get tournamentHubStatsSubtitle => 'In Vorbereitung';

  @override
  String get tournamentHubPastTitle => 'Vergangene Turniere';

  @override
  String get tournamentHubPastSubtitle => 'Abgeschlossene Turniere ansehen';

  @override
  String get tournamentHubRankingTitle => 'Rangliste';

  @override
  String get tournamentHubRankingSubtitle => 'Ewige Bestenliste der Turniere';

  @override
  String get tournamentRankingTabLigaA => 'Liga A';

  @override
  String get tournamentRankingTabLigaB => 'Liga B';

  @override
  String get tournamentRankingTabLigaC => 'Liga C';

  @override
  String get tournamentRankingTabEinzel => 'Einzel';

  @override
  String get tournamentRankingColName => 'Name';

  @override
  String get tournamentRankingColPoints => 'Punkte';

  @override
  String get tournamentRankingColCount => 'Turniere';

  @override
  String get tournamentRankingEmpty => 'Noch keine Wertungen';

  @override
  String get tournamentRankingError => 'Rangliste konnte nicht geladen werden';

  @override
  String get eloLeaderboardTitle => 'ELO-Bestenliste';

  @override
  String get eloLeaderboardEyebrow => 'Turniere';

  @override
  String get eloLeaderboardHubTitle => 'ELO-Bestenliste';

  @override
  String get eloLeaderboardHubSubtitle => 'Globale Turnier-ELO der Spieler';

  @override
  String get eloLeaderboardColName => 'Name';

  @override
  String get eloLeaderboardColElo => 'ELO';

  @override
  String get eloLeaderboardColGames => 'Spiele';

  @override
  String get eloLeaderboardProvisionalBadge => 'provisorisch';

  @override
  String get eloLeaderboardEmptyTitle => 'Noch keine Wertungen';

  @override
  String get eloLeaderboardEmptyBody =>
      'Sobald die ersten Turnierspiele gewertet sind, erscheinen hier die Spieler mit ihrer ELO.';

  @override
  String get eloLeaderboardError => 'Bestenliste konnte nicht geladen werden';

  @override
  String get tournamentPastEyebrow => 'Turniere';

  @override
  String get tournamentPastTitle => 'Vergangene Turniere';

  @override
  String get tournamentPastEmptyTitle => 'Noch keine vergangenen Turniere';

  @override
  String get tournamentPastEmptyBody =>
      'Sobald ein Turnier abgeschlossen ist, erscheint es hier.';

  @override
  String get tournamentRegistrationsTitle => 'Angemeldet';

  @override
  String get tournamentRegistrationsEmptyTitle => 'Noch keine Anmeldung';

  @override
  String get tournamentRegistrationsEmptyBody =>
      'Sobald du dich bei einem ausgeschriebenen Turnier anmeldest, erscheint es hier.';

  @override
  String get tournamentBrowseEmptyBody =>
      'Sobald Veranstalter Turniere ausschreiben, erscheinen sie hier.';

  @override
  String get tournamentRegistrationsWithdraw => 'Abmelden';

  @override
  String get tournamentWithdrawConfirmTitle => 'Vom Turnier abmelden?';

  @override
  String get tournamentWithdrawConfirmBody =>
      'Deine Anmeldung wird zurückgezogen. Solange die Registrierung offen ist, kannst du dich erneut anmelden.';

  @override
  String get tournamentStatsComingSoonTitle => 'Turnierstatistik kommt bald';

  @override
  String get tournamentStatsComingSoonBody =>
      'Hier siehst du künftig deine Turnier-Bilanz, Platzierungen und den Verlauf.';

  @override
  String get tournamentStatsTabSeries => 'Serien';

  @override
  String get tournamentStatsTabDuel => 'Duell';

  @override
  String get tournamentStatsSeriesError =>
      'Serien konnten nicht geladen werden.';

  @override
  String get tournamentStatsSeriesEmptyTitle => 'Noch keine Serien';

  @override
  String get tournamentStatsSeriesEmptyBody =>
      'Sobald Turniere abgeschlossen sind, erscheinen hier ihre Serien mit Verlauf und Platzierungen.';

  @override
  String tournamentStatsEditionsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Austragungen',
      one: '1 Austragung',
    );
    return '$_temp0';
  }

  @override
  String get tournamentStatsSeriesDetailEyebrow => 'Serie';

  @override
  String get tournamentStatsSectionEditions => 'Austragungen';

  @override
  String get tournamentStatsSectionPlacements => 'Platzierungs-Verteilung';

  @override
  String get tournamentStatsSectionMine => 'Meine Bilanz';

  @override
  String tournamentStatsFieldSize(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Teilnehmer',
      one: '1 Teilnehmer',
    );
    return '$_temp0';
  }

  @override
  String tournamentStatsPlacementShort(int rank) {
    return '$rank.';
  }

  @override
  String get tournamentStatsWinnerLabel => 'Sieger';

  @override
  String get tournamentStatsBestPlacement => 'Beste Platzierung';

  @override
  String get tournamentStatsAvgPlacement => 'Ø Platzierung';

  @override
  String get tournamentStatsEditionsPlayed => 'Teilnahmen';

  @override
  String get tournamentStatsMineEmpty =>
      'Du hast in dieser Serie noch nicht gespielt.';

  @override
  String get tournamentStatsDuelPickA => 'Erste Seite wählen';

  @override
  String get tournamentStatsDuelPickB => 'Zweite Seite wählen';

  @override
  String get tournamentStatsDuelHint =>
      'Wähle zwei Teilnehmer, um ihre direkten Duelle aus allen abgeschlossenen Turnieren zu vergleichen.';

  @override
  String get tournamentStatsDuelError =>
      'Die Bilanz konnte nicht geladen werden.';

  @override
  String get tournamentStatsDuelEmpty =>
      'Diese beiden hatten in abgeschlossenen Turnieren noch keine direkten Duelle.';

  @override
  String get tournamentStatsDuelTotal => 'Duelle';

  @override
  String get tournamentStatsDuelKo => 'davon K.o.';

  @override
  String get tournamentStatsDuelWinRate => 'Siegquote';

  @override
  String get tournamentStatsDuelDraws => 'Offen';

  @override
  String get tournamentStatsPickerTitle => 'Teilnehmer wählen';

  @override
  String get tournamentStatsPickerSearchHint => 'Name suchen …';

  @override
  String get tournamentStatsPickerEmpty =>
      'Keine passenden Teilnehmer gefunden.';

  @override
  String get tournamentStatsPickerTeamBadge => 'Team';

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
  String get tournamentFormatSwiss => 'Schoch';

  @override
  String get tournamentFormatRoundRobinKo => 'Gruppen + K.-o.';

  @override
  String get tournamentFormatSchochKo => 'Schoch + K.-o.';

  @override
  String get tournamentFormatSwissKo => 'Schoch + K.-o.';

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
  String tournamentDetailTeamSizeRange(int min, int max) {
    return '$min–$max Spieler';
  }

  @override
  String tournamentDetailTeamSizeFixed(int size) {
    return '$size Spieler';
  }

  @override
  String get tournamentDetailBasekubbs => 'Basiskubbs/Seite';

  @override
  String get tournamentDetailTiebreak => 'Tiebreak-Satz';

  @override
  String tournamentDetailTiebreakAfter(int minutes) {
    return 'Tiebreak nach $minutes min';
  }

  @override
  String get tournamentDetailBreakBetween => 'Pause zwischen Matches';

  @override
  String tournamentDetailMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String get tournamentDetailKoPhaseHeading => 'KO-Phase';

  @override
  String get tournamentDetailBracketType => 'KO-Modell';

  @override
  String get tournamentDetailBracketSingle => 'Single-Elimination';

  @override
  String get tournamentDetailBracketDouble => 'Double-Elimination';

  @override
  String get tournamentDetailKoTiebreakMethod => 'KO-Tiebreak';

  @override
  String get tournamentDetailKoTiebreakClassic =>
      'Classic (Kingtoss-Entfernung)';

  @override
  String get tournamentDetailKoTiebreakMighty => 'Mighty Finisher';

  @override
  String get tournamentDetailMightyFinisher => 'Mighty Finisher';

  @override
  String tournamentDetailMightyFinisherSlots(int slots) {
    return '$slots Plätze';
  }

  @override
  String get tournamentDetailFinalNoTiebreak => 'Finale ohne Tiebreak';

  @override
  String get tournamentDetailMightyFinisherMethod => 'Mighty-Finisher Methode';

  @override
  String get tournamentDetailMightyFinisherMethodShootout => 'Shootout';

  @override
  String get tournamentDetailMightyFinisherPool => 'Mighty-Finisher Pool';

  @override
  String get tournamentDetailMightyFinisherPoolRunnersUp => 'Gruppenzweite';

  @override
  String get tournamentDetailMightyFinisherPoolRankBand =>
      'Rangband aus Vorrunde';

  @override
  String get tournamentDetailMightyFinisherTiebreak =>
      'Mighty-Finisher Tiebreak';

  @override
  String get tournamentDetailMightyFinisherTiebreakSudden => '8m Sudden Death';

  @override
  String get tournamentDetailThirdPlacePlayoff => 'Spiel um Platz 3';

  @override
  String get tournamentDetailSeedingMode => 'Seeding';

  @override
  String get tournamentDetailSeedingAuto => 'Automatisch aus Vorrunde';

  @override
  String get tournamentDetailSeedingManual => 'Manuell';

  @override
  String get tournamentDetailKoMatchup => 'KO-Paarung';

  @override
  String get tournamentDetailKoMatchupSeed => '1 gegen n (Setzliste)';

  @override
  String get tournamentDetailKoMatchupOneVsTwo => '1 gegen 2 (benachbart)';

  @override
  String get tournamentDetailPoolStrategy => 'Gruppen-Verteilung';

  @override
  String get tournamentDetailPoolStrategySnake => 'Schlange (Snake)';

  @override
  String get tournamentDetailPoolStrategyRandom => 'Zufällig';

  @override
  String get tournamentDetailPoolStrategySeeded => 'Gesetzt (Block)';

  @override
  String get tournamentDetailPoolConfig => 'Gruppen-Aufteilung';

  @override
  String tournamentDetailPoolConfigValue(int groups, int qualifiers) {
    return '$groups Gruppen, $qualifiers qualifizieren';
  }

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
  String get tournamentDetailStatusConfirmed => 'Angemeldet';

  @override
  String get tournamentDetailStatusWaitlist => 'Auf Warteliste';

  @override
  String get tournamentDetailWaitlistHeading => 'Warteliste';

  @override
  String get tournamentDetailActionRemove => 'Entfernen';

  @override
  String get tournamentDetailCheckinAction => 'Einchecken';

  @override
  String get tournamentDetailCheckedInState => 'Anwesend';

  @override
  String tournamentDetailCheckedInAt(String time) {
    return 'Eingecheckt $time';
  }

  @override
  String tournamentDetailCheckedInCount(int checkedIn, int total) {
    return '$checkedIn/$total eingecheckt';
  }

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
  String get tournamentDetailActionSetSeeding => 'Seeding festlegen';

  @override
  String get tournamentSeedingRequiredError =>
      'Seeding erforderlich: Lege die Setzliste fest, bevor die KO-Phase startet.';

  @override
  String get tournamentDetailActionStandings => 'Endrangliste';

  @override
  String get tournamentDetailActionBracket => 'Bracket anzeigen';

  @override
  String get tournamentDetailAborted => 'Turnier abgebrochen.';

  @override
  String get tournamentDetailActionEdit => 'Bearbeiten';

  @override
  String get tournamentDetailActionResume => 'Fortsetzen';

  @override
  String get tournamentDetailHintDraft =>
      'Veröffentlichen — die Anmeldung ist danach sofort offen und Spieler können sich anmelden. Starten kannst du, sobald genug Teilnehmer dabei sind.';

  @override
  String get tournamentDetailHintPublished =>
      'Die Anmeldung ist offen. Spieler können sich anmelden, bis du das Turnier startest.';

  @override
  String get tournamentDetailHintRegistrationOpen =>
      'Die Anmeldung ist offen. Starte das Turnier, sobald genug Teilnehmer dabei sind — der Start schliesst die Anmeldung automatisch.';

  @override
  String get tournamentDetailHintRegistrationClosed =>
      'Anmeldung ist geschlossen. Jetzt kann das Turnier gestartet werden.';

  @override
  String get tournamentDetailPools => 'Gruppen';

  @override
  String get tournamentDetailPoolsEmpty => 'Noch keine Gruppendaten.';

  @override
  String tournamentDetailPoolGroup(String label) {
    return 'Gruppe $label';
  }

  @override
  String get tournamentDetailInfoHeading => 'Veranstaltung';

  @override
  String get tournamentDetailLocation => 'Ort';

  @override
  String get tournamentDetailVenueAddress => 'Adresse';

  @override
  String get tournamentDetailDatesHeading => 'Termine';

  @override
  String get tournamentDetailEventStart => 'Turnierstart';

  @override
  String get tournamentDetailRegistrationCloses => 'Anmeldeschluss';

  @override
  String get tournamentDetailCheckinUntil => 'Check-in bis';

  @override
  String get tournamentDetailFeeHeading => 'Gebühr & Zahlung';

  @override
  String get tournamentDetailEntryFee => 'Startgebühr';

  @override
  String get tournamentDetailPaymentMethods => 'Zahlarten';

  @override
  String get tournamentDetailContactHeading => 'Kontakt';

  @override
  String get tournamentDetailContactName => 'Ansprechperson';

  @override
  String get tournamentDetailContactPhone => 'Telefon';

  @override
  String get tournamentDetailInfoTextsHeading => 'Infos für Teilnehmer';

  @override
  String get tournamentDetailInfoFood => 'Verpflegung';

  @override
  String get tournamentDetailInfoTravel => 'Anreise';

  @override
  String get tournamentDetailInfoAccommodation => 'Unterkunft';

  @override
  String get tournamentDetailWeatherNote => 'Wetter';

  @override
  String get tournamentDetailRulesHeading => 'Regel-Varianten';

  @override
  String get tournamentDetailRuleDiggy => 'Diggy';

  @override
  String get tournamentDetailRuleSureshot => 'Sureshot';

  @override
  String get tournamentDetailRuleStrafkubb =>
      'Strafkubb Stocklänge Abstand zu König und Grundlinie';

  @override
  String get tournamentDetailRuleOpening => 'Anspielregel';

  @override
  String get tournamentDetailRuleOn => 'An';

  @override
  String get tournamentDetailRuleOff => 'Aus';

  @override
  String get tournamentDetailScoring => 'Wertung';

  @override
  String get tournamentDetailInviteOnly => 'Auf Einladung';

  @override
  String get tournamentDetailScoringEkc => 'EKC';

  @override
  String get tournamentDetailScoringClassic => 'Classic';

  @override
  String get tournamentDetailOrganizationHeading => 'Veranstalter & Liga';

  @override
  String get tournamentDetailClubLabel => 'Veranstalterteam';

  @override
  String get tournamentDetailFunTournament => 'Spasstournier – ohne Wertung';

  @override
  String get tournamentDetailLeagueCategories => 'Liga-Kategorien';

  @override
  String get tournamentDetailKoSetup => 'KO-Setup';

  @override
  String tournamentDetailKoQualifiers(int count) {
    return '$count Qualifikanten';
  }

  @override
  String get tournamentDetailConsolationLabel => 'Trostturnier';

  @override
  String get tournamentDetailConsolationSource => 'Trostturnier-Quelle';

  @override
  String get tournamentDetailConsolationSourceKoLosers =>
      'Verlierer früher KO-Runden';

  @override
  String get tournamentDetailConsolationSourceRankBand =>
      'Rangband aus Vorrunde';

  @override
  String get tournamentDetailConsolationSourceRounds =>
      'Trostturnier Quell-Runden';

  @override
  String get tournamentDetailConsolationRankBand => 'Trostturnier Rangband';

  @override
  String tournamentDetailConsolationRankBandValue(int from, int to) {
    return 'Rang $from–$to';
  }

  @override
  String get tournamentDetailConsolationDirectCount =>
      'Direkt-Starter Trostturnier';

  @override
  String get tournamentDetailConsolationMainBracketSize => 'Hauptfeld-Grösse';

  @override
  String get tournamentDetailDocumentsHeading => 'Dokumente';

  @override
  String get tournamentDetailRulesPdf => 'Regelwerk (PDF)';

  @override
  String get tournamentDetailSiteMapPdf => 'Geländeplan (PDF)';

  @override
  String get tournamentDetailPdfOpenError =>
      'PDF konnte nicht geöffnet werden.';

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
  String get tournamentCardDetails => 'Details';

  @override
  String tournamentTeamRosterRangeFixed(int count) {
    return 'Wähle $count Spieler für dein Team aus.';
  }

  @override
  String tournamentTeamRosterRange(int min, int max) {
    return 'Wähle zwischen $min und $max Spielern für dein Team aus.';
  }

  @override
  String tournamentTeamRosterSelected(int count) {
    return '$count ausgewählt';
  }

  @override
  String get tournamentTeamRegistered => 'Team angemeldet.';

  @override
  String get tournamentTeamRegisteredMembers =>
      'Folgende Mitglieder sind angemeldet:';

  @override
  String get tournamentTeamRegisterDone => 'Fertig';

  @override
  String get tournamentTeamMemberRegistered => 'angemeldet';

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
  String get publicMatchShareAction => 'Spiel-Link teilen';

  @override
  String get publicMatchShareSubject => 'Kubb-Spiel verfolgen';

  @override
  String get publicMatchLinkCopied => 'Link kopiert';

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
  String tournamentMatchLivePreviewLeader(String name) {
    return '$name führt';
  }

  @override
  String get tournamentMatchSubmitButton => 'Einreichen';

  @override
  String get tournamentMatchSubmitError => 'Senden fehlgeschlagen';

  @override
  String get tournamentMatchReadOnlyNotice =>
      'Dieses Spiel ist bereits abgeschlossen.';

  @override
  String get tournamentMatchFinisherPrompt => 'Wer hat den Finisher gewonnen?';

  @override
  String tournamentMatchFinisherSetLabel(int set) {
    return 'Satz $set';
  }

  @override
  String tournamentMatchFinisherNeeded(int set) {
    return 'Satz $set: KO ohne König — Finisher auflösen';
  }

  @override
  String get tournamentMatchFinisherShootoutPending =>
      'Mighty-Finisher Shoot-out offen — im Shoot-out auflösen.';

  @override
  String get tournamentMatchFinisherShootoutOpenAction => 'Shoot-out öffnen';

  @override
  String get tournamentMatchTimerLabel => 'Restzeit';

  @override
  String get tournamentMatchTimerExpiredCta =>
      'Zeit abgelaufen — Resultat eintragen';

  @override
  String get tournamentMatchTimerTiebreakCta =>
      'Zeit abgelaufen — Tiebreak / Mighty-Finisher melden';

  @override
  String get tournamentMatchTimerTiebreakActive => 'Tiebreak läuft';

  @override
  String tournamentRoundCallCountdown(String time) {
    return 'Nächste Runde in $time';
  }

  @override
  String get tournamentRoundHold => 'Zeit angehalten — Resultat eintragen';

  @override
  String get tournamentRoundTiebreakHold => 'Tiebreak';

  @override
  String tournamentMatchPitchCallTitle(String pitch) {
    return 'Dein Platz: Pitch $pitch — leg los!';
  }

  @override
  String tournamentMatchPitchCallVersus(String opponent) {
    return 'Gegen $opponent';
  }

  @override
  String get tournamentMatchPitchCallAction => 'Spiel öffnen';

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
  String get tournamentEscalationTitle => 'Eskalationen';

  @override
  String get tournamentEscalationEmptyTitle => 'Alles im grünen Bereich';

  @override
  String get tournamentEscalationEmptyBody =>
      'Keine strittigen oder überfälligen Matches und keine fehlenden Check-ins.';

  @override
  String get tournamentEscalationDisputedHeading => 'Strittig';

  @override
  String get tournamentEscalationOverdueHeading => 'Überfällig';

  @override
  String get tournamentEscalationNotCheckedInHeading => 'Nicht eingecheckt';

  @override
  String tournamentEscalationMatchLabel(int round, int match) {
    return 'Runde $round · Match $match';
  }

  @override
  String get tournamentEscalationOverrideAction => 'Korrigieren';

  @override
  String get tournamentEscalationForfeitAction => 'No-Show → Forfait';

  @override
  String get tournamentEscalationNoShowReason => 'No-Show - nicht eingecheckt';

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
      'Dieses Match kann nicht mehr übersteuert werden.';

  @override
  String get tournamentOverrideEntryAction => 'Als Veranstalter eintragen';

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
  String get tournamentBracketSectionMain => 'Hauptbaum';

  @override
  String get tournamentBracketConsolationLabel => 'Trostturnier';

  @override
  String get tournamentBracketMainTreeUnavailable =>
      'Der Hauptbaum ist hier nicht verfügbar. Endplatzierungen 1–4 siehe Turnier-Detail.';

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
  String get tournamentSeedingAutoSeedButton => 'Aus ELO-Wertung';

  @override
  String get tournamentSeedingErrorTitle => 'Aktion fehlgeschlagen';

  @override
  String get tournamentSeedingInfoTitle => 'Setzliste';

  @override
  String get tournamentSeedingInfoBody =>
      'Lege die Reihenfolge fest, in der die Teams in den KO-Baum gesetzt werden. Position 1 ist der höchste Setzplatz. Ziehe Einträge zum Umsortieren oder übernimm die ELO-Wertung. Erst nach dem Speichern lässt sich die KO-Phase starten.';

  @override
  String get tournamentSeedingDirtyHint => 'Ungespeicherte Änderungen.';

  @override
  String get tournamentSeedingStartKoConfirmTitle => 'KO jetzt starten?';

  @override
  String get tournamentSeedingStartKoConfirmBody =>
      'Die Setzung wird fixiert und die KO-Phase gestartet. Das lässt sich nicht rückgängig machen.';

  @override
  String get tournamentSeedingStartKoConfirmAction => 'KO starten';

  @override
  String get tournamentSeedingEmpty => 'Noch keine qualifizierten Teilnehmer.';

  @override
  String get tournamentSetupInfoSeedingSortTitle => 'Reihenfolge per Ziehen';

  @override
  String get tournamentSetupInfoSeedingSortBody =>
      'Lange auf einen Eintrag tippen und ziehen, um die Setzreihenfolge zu ändern. Position 1 ist der höchste Setzplatz.';

  @override
  String get tournamentSetupInfoSeedingSaveTitle => 'Setzung sichern';

  @override
  String get tournamentSetupInfoSeedingSaveBody =>
      'Speichert die aktuelle Reihenfolge. Erst nach dem Speichern lässt sich das K.-o. starten.';

  @override
  String get tournamentSetupInfoSeedingRestoreTitle =>
      'Auf Gruppen-Reihenfolge zurücksetzen';

  @override
  String get tournamentSetupInfoSeedingRestoreBody =>
      'Setzt deine manuellen Änderungen zurück auf die automatische Reihenfolge aus der Vorrunde.';

  @override
  String get tournamentSetupInfoSeedingEloTitle =>
      'Setzliste aus ELO übernehmen';

  @override
  String get tournamentSetupInfoSeedingEloBody =>
      'Füllt die Setzliste mit der Reihenfolge aus den ELO-Wertungen der Teams. Du kannst danach trotzdem von Hand nachsortieren.';

  @override
  String get tournamentSetupInfoSeedingStartKoTitle => 'K.-o. starten';

  @override
  String get tournamentSetupInfoSeedingStartKoBody =>
      'Startet die K.-o.-Phase mit der gespeicherten Setzliste. Geht erst, wenn die Setzung gespeichert ist.';

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
      'Wie viele Teams ziehen aus der Vorrunde in die KO-Phase ein? Nur Zweierpotenzen (4/8/16/32) — keine Freilose im Hauptbaum.';

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
  String get teamCreateLeagueHelper =>
      'A · Profi, B · Haupt-Tour, C · Neben-Tour';

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
  String get teamCreateErrorAuth =>
      'Du bist nicht angemeldet — bitte melde dich erneut an und versuche es nochmal.';

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
  String get leagueFilterAll => 'Alle Ligen';

  @override
  String get seasonAssignTournament => 'Turnier zuordnen';

  @override
  String get tournamentSwissSystem => 'Schoch';

  @override
  String get tournamentSwissRounds => 'Runden';

  @override
  String get tournamentSwissTiebreak => 'Tiebreak';

  @override
  String get tournamentSwissOversize =>
      'Bei sehr vielen Teilnehmern werden die Runden länger';

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

  @override
  String get offlineBannerOffline => 'Offline';

  @override
  String get offlineBannerSyncing => 'Sync läuft …';

  @override
  String offlineBannerSyncedAgo(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: 'Offline · letzte Sync vor $minutes min',
      one: 'Offline · letzte Sync vor 1 min',
      zero: 'Offline · gerade synchronisiert',
    );
    return '$_temp0';
  }

  @override
  String get onboardingSlide1Title => 'Sniper-Training';

  @override
  String get onboardingSlide1Body =>
      'Wurf-Konstanz trainieren — 4 bis 8 m Distanz, eigene Sessions, eigene Stats.';

  @override
  String get onboardingSlide2Title => 'Finisseur';

  @override
  String get onboardingSlide2Body =>
      'Das Match-Endspiel üben. 6 Stöcke, Field-, Base- und Königs-Phase.';

  @override
  String get onboardingSlide3Title => 'Turniere & Ligen';

  @override
  String get onboardingSlide3Body =>
      'Turniere veranstalten, Spielpläne live verfolgen, Saisontabellen lesen.';

  @override
  String get onboardingSlide4Title => 'Mit Freunden trainieren';

  @override
  String get onboardingSlide4Body =>
      'Teams gründen, Freunde einladen, gemeinsam besser werden.';

  @override
  String get onboardingSkip => 'Überspringen';

  @override
  String get onboardingNext => 'Weiter';

  @override
  String get onboardingDone => 'Los geht\'s';

  @override
  String get statusMatchLive => 'Live';

  @override
  String get statusMatchDisputed => 'Disput';

  @override
  String get statusMatchFinished => 'Fertig';

  @override
  String get statusMatchWaiting => 'Wartet';

  @override
  String get statusMatchOverridden => 'Korrigiert';

  @override
  String get statusMatchVoided => 'Abgebrochen';

  @override
  String get statusTournamentDraft => 'Entwurf';

  @override
  String get statusTournamentPublished => 'Veröffentlicht';

  @override
  String get statusTournamentRegistrationOpen => 'Anmeldung offen';

  @override
  String get statusTournamentRegistrationClosed => 'Anmeldung geschlossen';

  @override
  String get statusTournamentRunning => 'Live';

  @override
  String get statusTournamentFinished => 'Beendet';

  @override
  String get statusTournamentCancelled => 'Abgebrochen';

  @override
  String get emptySessionsTitle => 'Noch keine Sessions';

  @override
  String get emptySessionsBody =>
      'Spiel ein paar Trainings — danach siehst du sie hier.';

  @override
  String get emptySessionsCta => 'Erste Session starten';

  @override
  String get emptyFriendsTitle => 'Noch keine Freunde';

  @override
  String get emptyFriendsBody =>
      'Such oben nach einem Spielernamen und schick eine Anfrage.';

  @override
  String get emptyFriendsCta => 'Freund suchen';

  @override
  String get emptyTournamentsTitle => 'Noch keine Turniere';

  @override
  String get emptyTournamentsBody =>
      'Erstelle dein erstes Turnier — Setup ist in unter zwei Minuten erledigt.';

  @override
  String get emptyTournamentsCta => 'Turnier erstellen';

  @override
  String get emptyInboxTitle => 'Postfach ist leer';

  @override
  String get emptyInboxBody =>
      'Match-Einladungen und Freundschaftsanfragen landen hier.';

  @override
  String get emptyInboxCta => 'Freunde finden';

  @override
  String get achievementsScreenTitle => 'Erfolge';

  @override
  String get achievementsScreenEyebrow => 'Profil';

  @override
  String get achievementsSectionEarned => 'Erspielt';

  @override
  String get achievementsSectionOpen => 'Noch offen';

  @override
  String get achievementsEmptyTitle => 'Noch keine Erfolge';

  @override
  String get achievementsEmptyBody =>
      'Spiel ein paar Sniper-Sessions und Matches — Erfolge schalten sich automatisch frei.';

  @override
  String get achievementsEmptyCta => 'Sniper starten';

  @override
  String get achievementsBadgeFirstHitTitle => 'Erster Treffer';

  @override
  String get achievementsBadgeFirstHitDesc =>
      'Treffe deinen ersten Kubb in einer Session.';

  @override
  String get achievementsBadgeHundredHitsTitle => '100 Treffer';

  @override
  String get achievementsBadgeHundredHitsDesc =>
      'Sammle 100 Treffer über alle Sessions.';

  @override
  String get achievementsBadgeStreakTitle => 'Serien-Schütze';

  @override
  String get achievementsBadgeStreakDesc =>
      'Triff 10 Kubbs in Folge ohne Fehlwurf.';

  @override
  String get achievementsBadgeHeliTitle => 'Heli-Meister';

  @override
  String get achievementsBadgeHeliDesc =>
      'Lande 5 Helikopter-Würfe in einer Session.';

  @override
  String get achievementsBadgeKingTitle => 'Königsmacher';

  @override
  String get achievementsBadgeKingDesc =>
      'Gewinne ein Match mit dem letzten Wurf auf den König.';

  @override
  String achievementsLockedChip(String trigger) {
    return 'Bei $trigger freigeschaltet';
  }

  @override
  String get legalEyebrow => 'Recht';

  @override
  String get legalPrivacyPolicyTitle => 'Datenschutzerklärung';

  @override
  String get legalPrivacyPolicyLoading => 'Datenschutzerklärung wird geladen…';

  @override
  String get legalPrivacyPolicyUnavailable =>
      'Datenschutzerklärung ist gerade nicht verfügbar. Bitte später erneut versuchen.';

  @override
  String get legalImprintTitle => 'Impressum';

  @override
  String get legalImprintLoading => 'Impressum wird geladen…';

  @override
  String get legalImprintUnavailable =>
      'Impressum ist gerade nicht verfügbar. Bitte später erneut versuchen.';

  @override
  String get settingsRowPrivacyPolicy => 'Datenschutz';

  @override
  String get settingsRowImprint => 'Impressum';

  @override
  String get shootoutTitle => 'Shoot-Out';

  @override
  String get shootoutEyebrow => 'Quali-Entscheidung';

  @override
  String get shootoutIntro =>
      'Gleichstand an der Qualifikations-Grenze. Legt gemeinsam fest, in welcher Reihenfolge die beteiligten Teams den Shoot-Out gewonnen haben — bestes Team zuerst.';

  @override
  String get shootoutParticipantsHeader => 'Beteiligte Teams';

  @override
  String get shootoutOrderHint =>
      'Reihenfolge per Pfeile anpassen — oben = Sieger.';

  @override
  String shootoutRankLabel(int rank) {
    return '$rank.';
  }

  @override
  String get shootoutMoveUp => 'Nach oben';

  @override
  String get shootoutMoveDown => 'Nach unten';

  @override
  String get shootoutReportAction => 'Sieger melden';

  @override
  String get shootoutConfirmAction => 'Bestätigen';

  @override
  String get shootoutReportedBanner =>
      'Eine Reihenfolge wurde gemeldet. Die andere Seite muss sie bestätigen.';

  @override
  String get shootoutReportedSnack => 'Sieger-Reihenfolge gemeldet';

  @override
  String get shootoutConfirmedSnack => 'Shoot-Out bestätigt';

  @override
  String shootoutError(String error) {
    return 'Shoot-Out konnte nicht aktualisiert werden: $error';
  }

  @override
  String get shootoutEmptyTitle => 'Kein offener Shoot-Out';

  @override
  String get shootoutEmptyBody =>
      'Für dieses Turnier ist aktuell kein Shoot-Out für dich offen.';

  @override
  String shootoutLoadError(String error) {
    return 'Shoot-Out konnte nicht geladen werden:\n$error';
  }

  @override
  String get shootoutInboxOpenAction => 'Shoot-Out öffnen';

  @override
  String get shootoutErrorInvalidOrder =>
      'Die Reihenfolge muss alle beteiligten Teams genau einmal enthalten.';

  @override
  String get shootoutErrorOrderMismatch =>
      'Die Reihenfolge weicht von der gemeldeten ab. Bitte bestätige die gemeldete Reihenfolge unverändert.';

  @override
  String get shootoutErrorNotAuthorised =>
      'Du gehörst nicht zu diesem Shoot-Out und kannst ihn nicht bearbeiten.';

  @override
  String get shootoutErrorAlreadyResolved =>
      'Dieser Shoot-Out wurde bereits entschieden.';

  @override
  String get shootoutErrorNotReported =>
      'Es wurde noch keine Reihenfolge gemeldet, die du bestätigen könntest.';

  @override
  String get shootoutErrorSelfConfirm =>
      'Die gemeldete Reihenfolge muss von der anderen Seite bestätigt werden.';

  @override
  String get shootoutOrderHintReadonly =>
      'Die gemeldete Reihenfolge bestätigen — bestes Team zuerst.';

  @override
  String get inboxScheduleLabelRoundPublished => 'Neue Runde';

  @override
  String get inboxScheduleLabelMatchRunning => 'Match läuft';

  @override
  String get inboxScheduleLabelPaused => 'Turnier pausiert';

  @override
  String get inboxScheduleLabelResumed => 'Turnier läuft weiter';

  @override
  String get inboxScheduleLabelAwaitingResults => 'Resultat fehlt';

  @override
  String get inboxScheduleLabelTiebreakHold => 'Tiebreak';

  @override
  String get inboxScheduleLabelGeneric => 'Turnier-Ablauf';

  @override
  String get inboxScheduleOpenMatchAction => 'Zum Match';

  @override
  String get tournamentWizardSummaryPlaceholder => '—';

  @override
  String get tournamentWizardSummarySectionStammdaten => 'Stammdaten';

  @override
  String get tournamentWizardSummarySectionParticipants => 'Teilnehmer';

  @override
  String get tournamentWizardSummarySectionVorrunde => 'Vorrunde';

  @override
  String get tournamentWizardSummarySectionKo => 'K.-o.';

  @override
  String get tournamentWizardSummaryErrorTitle =>
      'Turnier kann nicht angelegt werden';

  @override
  String get tournamentWizardSummaryTeamSizeLabel => 'Teamgrösse';

  @override
  String tournamentWizardSummaryTeamSizeFixed(int size) {
    return '$size (fix)';
  }

  @override
  String tournamentWizardSummaryTeamSizeRange(int min, int max) {
    return '$min–$max';
  }

  @override
  String get tournamentWizardSummaryYes => 'Ja';

  @override
  String get tournamentWizardSummaryNo => 'Nein';

  @override
  String tournamentWizardSummaryFee(String amount, String currency) {
    return '$amount $currency';
  }

  @override
  String get tournamentWizardSummaryFeeFree => 'Gratis';

  @override
  String get tournamentWizardSummaryScoringEkc => 'EKC';

  @override
  String get tournamentWizardSummaryScoringClassic => 'Klassisch';

  @override
  String get tournamentWizardSummaryRulesLabel => 'Regel-Varianten';

  @override
  String get tournamentWizardSummaryRulesNone => 'Keine Sonderregeln';

  @override
  String get tournamentWizardSummaryPdfRulesLabel => 'Regelwerk-PDF';

  @override
  String get tournamentWizardSummaryPdfSiteMapLabel => 'Lageplan-PDF';

  @override
  String get tournamentWizardSummaryContactLabel => 'Kontakt';

  @override
  String get tournamentWizardSummaryInfoLabel => 'Infotexte';

  @override
  String tournamentWizardSummaryInfoCount(int count) {
    return '$count hinterlegt';
  }

  @override
  String get tournamentWizardSummaryFormatLabel => 'Format';

  @override
  String get tournamentWizardSummaryMatchTimeLabel => 'Match-Zeit (Min.)';

  @override
  String get tournamentWizardSummaryPitchesLabel => 'Pitches';

  @override
  String get tournamentWizardSummaryKoTypeLabel => 'KO-System';

  @override
  String get tournamentWizardSummaryKoTypeSingle => 'Single-Out';

  @override
  String get tournamentWizardSummaryKoTypeDouble => 'Double-Elimination';

  @override
  String get tournamentWizardSummaryKoTypeConsolation => 'Trostturnier';

  @override
  String get tournamentWizardSummaryKoSizeLabel => 'Bracket-Grösse';

  @override
  String get tournamentWizardSummaryKoRoundsLabel => 'Per-Runde-Regeln';

  @override
  String tournamentWizardSummaryKoRoundEntry(int round, int maxSets) {
    return 'R$round: Bo$maxSets';
  }

  @override
  String get tournamentWizardSummarySeedingLabel => 'Seeding-Quelle';

  @override
  String get tournamentWizardSummarySeedingAuto => 'Automatisch aus Vorrunde';

  @override
  String get tournamentWizardSummarySeedingManual => 'Manuell festlegen';

  @override
  String get tournamentWizardSummaryConsolationDirectLabel =>
      'Direkt ins Trostturnier';

  @override
  String get eloSectionLabel => 'ELO-WERTUNG';

  @override
  String get eloTournamentLabel => 'Turnier-ELO';

  @override
  String get eloPersonalLabel => 'Persönlich';

  @override
  String get eloProvisionalBadge => 'provisorisch';

  @override
  String get eloNoRating => 'noch keine Wertung';

  @override
  String eloGamesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Spiele',
      one: '1 Spiel',
    );
    return '$_temp0';
  }

  @override
  String get nicknameTakenError =>
      'Dieser Name ist bereits vergeben — bitte wähle einen anderen.';

  @override
  String get nicknameCheckingHint => 'Name wird geprüft …';

  @override
  String get teamNameTakenError =>
      'Dieser Teamname ist bereits vergeben — bitte wähle einen anderen.';

  @override
  String get clubNameTakenError =>
      'Dieser Veranstalterteam-Name ist bereits vergeben — bitte wähle einen anderen.';

  @override
  String get nameCheckingHint => 'Name wird geprüft …';

  @override
  String get organizerTileTitle => 'Veranstalter';

  @override
  String get organizerTileSubtitle => 'Dashboard & Veranstalterteams';

  @override
  String get organizerDashboardTeamsTitle => 'Meine Veranstalterteams';

  @override
  String get organizerDashboardFoundTeam => 'Veranstalterteam gründen';

  @override
  String get organizerDashboardNoTeams => 'Noch kein Veranstalterteam';

  @override
  String get homeOngoingMatchTitle => 'Laufendes Match';

  @override
  String homeOngoingMatchSubtitle(String tournament, String opponent) {
    return '$tournament · gegen $opponent';
  }

  @override
  String get tournamentSetupInfoDisplayNameTitle => 'Name des Turniers';

  @override
  String get tournamentSetupInfoDisplayNameBody =>
      'Der Name, unter dem dein Turnier in der Liste und für alle Teilnehmer erscheint. Die App hängt automatisch die Jahreszahl an (z. B. \"Frühlingscup 2026\").';

  @override
  String get tournamentSetupInfoClubTitle => 'Wer richtet aus?';

  @override
  String get tournamentSetupInfoClubBody =>
      'Wählst du einen Club, zählt das Turnier als offizielles, für die Liga wertbares Vereinsturnier. Wählst du \"Spasstournier – ohne Wertung\", ist es ein privates Turnier ohne Liga-Bezug, und du kannst es auf Einladung beschränken.';

  @override
  String get tournamentSetupInfoLeagueCategoriesTitle =>
      'Für welche Liga zählt es?';

  @override
  String get tournamentSetupInfoLeagueCategoriesBody =>
      'Legt fest, in welche Liga-Wertung die Ergebnisse einfliessen. Nur bei einem Vereinsturnier sicht- und auswählbar; ein Spasstournier hat keine Liga-Kategorie.';

  @override
  String get tournamentSetupInfoInviteOnlyTitle => 'Nur eingeladene Spieler';

  @override
  String get tournamentSetupInfoInviteOnlyBody =>
      'Wenn aktiv, können sich nicht alle frei anmelden — nur die Spieler, die du unten gezielt einlädst, dürfen mitspielen. Die Einladungen werden nach dem Anlegen des Turniers verschickt. Nur für Spassturniere ohne Club.';

  @override
  String get tournamentSetupInfoInvitedPlayersTitle => 'Wen einladen?';

  @override
  String get tournamentSetupInfoInvitedPlayersBody =>
      'Such die Spieler über den Namen und tippe \"Einladen\". Nur diese erhalten Zugang zum Turnier. Du kannst Einträge jederzeit wieder entfernen, bevor du das Turnier anlegst.';

  @override
  String get tournamentSetupInfoLocationTitle => 'Wo wird gespielt?';

  @override
  String get tournamentSetupInfoLocationBody =>
      'Der Veranstaltungsort, kurz benannt (z. B. \"Sportplatz Brügg\"). Erscheint in der Turnierübersicht.';

  @override
  String get tournamentSetupInfoAddressTitle => 'Genaue Anschrift';

  @override
  String get tournamentSetupInfoAddressBody =>
      'Die vollständige Adresse zum Anfahren. Hilft den Teilnehmern, den Spielort zu finden.';

  @override
  String get tournamentSetupInfoEventDateTitle => 'Wann geht es los?';

  @override
  String get tournamentSetupInfoEventDateBody =>
      'Datum und Uhrzeit, an denen das Turnier beginnt.';

  @override
  String get tournamentSetupInfoRegistrationDeadlineTitle => 'Anmeldeschluss';

  @override
  String get tournamentSetupInfoRegistrationDeadlineBody =>
      'Bis zu diesem Zeitpunkt können sich Teilnehmer anmelden. Danach ist keine neue Anmeldung mehr möglich.';

  @override
  String get tournamentSetupInfoCheckinUntilTitle => 'Einchecken bis';

  @override
  String get tournamentSetupInfoCheckinUntilBody =>
      'Bis dahin müssen angemeldete Teilnehmer vor Ort bestätigen, dass sie da sind. Wer bis dahin nicht eingecheckt hat, kann aus der Spielplanung fallen.';

  @override
  String get tournamentSetupInfoScoringTitle => 'Zählweise der Sätze';

  @override
  String get tournamentSetupInfoScoringBody =>
      'Bestimmt, wie ein einzelner Satz gewertet wird. Bei EKC zählt jeder Feldkubb einen Punkt. Bei Classic zählt nur der Satzsieger — Sätze, die nicht zu Ende gespielt werden, fliessen nicht in die Wertung ein. Diese Wahl gilt für alle Spiele des Turniers.';

  @override
  String get tournamentSetupInfoSureshotTitle => 'Sonderregel Sureshot';

  @override
  String get tournamentSetupInfoSureshotBody =>
      'Schaltet die Sureshot-Variante für alle Spiele ein. Mit Sureshot muss die Königsfigur am Ende eines Satzes durch die Beine hindurch abgeworfen werden statt aus dem normalen Stand. Lässt sich ein- und ausschalten.';

  @override
  String get tournamentSetupInfoDiggyTitle => 'Sonderregel Diggy';

  @override
  String get tournamentSetupInfoDiggyBody =>
      'Schaltet die Diggy-Variante für alle Spiele ein. Liegt beim Einwerfen ein Kubb auf einem anderen und dabei im Spielfeld (also ein gültiger Einwurf), darf das einwerfende Team den oben liegenden Kubb platzieren.';

  @override
  String get tournamentSetupInfoStrafkubbTitle => 'Strafkubb-Platzierung';

  @override
  String get tournamentSetupInfoStrafkubbBody =>
      'Ein Strafkubb entsteht, wenn ein eingeworfener Kubb nach dem zweiten Versuch nicht gültig steht; der Gegner darf ihn frei aufstellen. Ist diese Option aktiv, muss der Strafkubb 30 cm (eine Stocklänge) Abstand zum König und zur Baseline haben.';

  @override
  String get tournamentSetupInfoOpeningTitle => 'Eröffnung';

  @override
  String get tournamentSetupInfoOpeningBody =>
      '\"2-4-6\" heisst: in der ersten Runde werden 2 Wurfstöcke geworfen, in der zweiten 4, ab der dritten 6 — ein sanfter Einstieg. \"Frei\" lässt die Eröffnung offen. Gilt für alle Spiele.';

  @override
  String get tournamentSetupInfoRulesPdfTitle => 'Regeln als PDF';

  @override
  String get tournamentSetupInfoRulesPdfBody =>
      'Optionales Dokument mit den Turnierregeln, das Teilnehmer einsehen können.';

  @override
  String get tournamentSetupInfoSiteMapPdfTitle => 'Lageplan als PDF';

  @override
  String get tournamentSetupInfoSiteMapPdfBody =>
      'Optionaler Plan des Spielgeländes (Felder, Anfahrt, Infrastruktur) zum Herunterladen.';

  @override
  String get tournamentSetupInfoEntryFeeTitle => 'Startgeld';

  @override
  String get tournamentSetupInfoEntryFeeBody =>
      'Betrag, den Teilnehmer zahlen. Leer oder 0 bedeutet kostenlos (\"Gratis\").';

  @override
  String get tournamentSetupInfoPaymentMethodsTitle => 'Wie bezahlt wird';

  @override
  String get tournamentSetupInfoPaymentMethodsBody =>
      'Wähle, welche Zahlungsarten du vor Ort akzeptierst (Bar, TWINT, Karte). Mehrfachauswahl möglich.';

  @override
  String get tournamentSetupInfoContactTitle => 'Kontakt für Rückfragen';

  @override
  String get tournamentSetupInfoContactBody =>
      'Name und Telefonnummer der Person, die Teilnehmer bei Fragen erreichen. Optional.';

  @override
  String get tournamentSetupInfoParticipantInfoTitle =>
      'Hinweise für Teilnehmer';

  @override
  String get tournamentSetupInfoParticipantInfoBody =>
      'Freitextfelder für praktische Infos rund ums Turnier. Erscheinen in der Turnierbeschreibung; alle optional.';

  @override
  String get tournamentSetupInfoTeamSizeMinTitle => 'Kleinste Teamgrösse';

  @override
  String get tournamentSetupInfoTeamSizeMinBody =>
      'Wie viele Spieler ein Team mindestens haben muss. Bei 1 spielen Einzelpersonen.';

  @override
  String get tournamentSetupInfoMaxTeamSizeTitle => 'Grösste Teamgrösse';

  @override
  String get tournamentSetupInfoMaxTeamSizeBody =>
      'Wie viele Spieler ein Team höchstens haben darf. Liegt dieser Wert über dem Minimum, sind Teams unterschiedlicher Grösse erlaubt.';

  @override
  String get tournamentSetupInfoMaxParticipantsTitle => 'Teilnehmer-Obergrenze';

  @override
  String get tournamentSetupInfoMaxParticipantsBody =>
      'Wie viele Teams höchstens mitspielen. Ist das Limit erreicht, kommen weitere Teams auf die Warteliste. Sie rücken Stück für Stück nach, sobald sich ein Team abmeldet oder von einer Person mit Setup-Berechtigung entfernt wird.';

  @override
  String get tournamentSetupInfoFormatModeTitle =>
      'Wie das Turnier aufgebaut ist';

  @override
  String get tournamentSetupInfoFormatModeBody =>
      '\"Klassisch\" führt durch den gewohnten Ablauf: eine Vorrunde und danach ein K.-o. \"Stufen-Graph\" ist für Fortgeschrittene: du baust den Turnierablauf aus einzelnen Stufen selbst zusammen und verbindest sie. Im Stufen-Graph-Modus entfällt der separate K.-o.-Schritt — die K.-o.-Stufen baust du direkt im Graphen.';

  @override
  String get tournamentSetupInfoVorrundeTitle => 'Wie die Vorrunde läuft';

  @override
  String get tournamentSetupInfoVorrundeBody =>
      'Bestimmt, wie gespielt wird, bevor das K.-o. beginnt. \"Gruppenphase\": jeder spielt in seiner Gruppe gegen jeden, die Bestplatzierten ziehen weiter. \"Schoch\": ein gemeinsamer Pool, die Paarungen werden nach jeder Runde neu nach Tabellenstand gebildet — gut für grosse Felder.';

  @override
  String get tournamentSetupInfoKoTypeTitle => 'Welcher K.-o.-Baum';

  @override
  String get tournamentSetupInfoKoTypeBody =>
      'Steuert, wie das Ausscheiden funktioniert: bei \"einfach\" ist man nach einer Niederlage raus, bei \"doppelt\" erst nach der zweiten, und das \"Trostturnier\" gibt früh Ausgeschiedenen einen Nebenwettbewerb. Ausführliche Erklärung im \"K.-o.-Systeme erklärt\"-Sheet.';

  @override
  String get tournamentSetupInfoKoBracketSizeTitle =>
      'Wie viele Teams im K.-o.';

  @override
  String get tournamentSetupInfoKoBracketSizeBody =>
      'Wie viele Teams in den K.-o.-Baum kommen (eine Zweierpotenz: 2, 4, 8, 16, …). Bei Gruppenphase muss diese Zahl durch die Anzahl Gruppen teilbar sein, weil pro Gruppe gleich viele weiterkommen.';

  @override
  String get tournamentSetupInfoKoSeedingSourceTitle =>
      'Woher die Setzliste kommt';

  @override
  String get tournamentSetupInfoKoSeedingSourceBody =>
      'Automatisch aus Vorrunde: Die Setzliste für den K.-o.-Baum wird automatisch aus der Vorrunden-Rangliste gebildet. Du musst nichts von Hand sortieren.\n\nManuell: Du legst die Setzliste selbst fest. Das passiert nach der Vorrunde auf einem eigenen Setzlisten-Screen, wo du die Qualifikanten per Ziehen sortierst. Erst wenn die Setzliste gespeichert ist, lässt sich das K.-o. starten.';

  @override
  String get tournamentSetupInfoKoMatchupTitle => 'Wer gegen wen';

  @override
  String get tournamentSetupInfoKoMatchupBody =>
      'Bestimmt die Paarungen im K.-o.-Baum. \"Beste vs. Schlechteste\" lässt die stärksten gegen die schwächsten antreten, \"1. vs. 2.\" paart benachbarte Ränge.';

  @override
  String get tournamentSetupInfoKoTiebreakTitle => 'Entscheid bei Gleichstand';

  @override
  String get tournamentSetupInfoKoTiebreakBody =>
      'Wie ein unentschiedenes K.-o.-Spiel entschieden wird. \"Mighty-Finisher\" und \"Shoot-out\" sind dabei nicht dasselbe. Der Mighty-Finisher wird gespielt, wenn eine zeitbegrenzte Partie abläuft: der Finisher startet, sobald die Zeit abgelaufen ist, und der laufende Satz wird zu Ende gespielt. Steht es danach unentschieden, folgt ein Entscheidungssatz nach den festgelegten Finisher-Regeln. \"Klassisch\" ist der herkömmliche Entscheid ohne Zeit-Finisher. Das Shoot-out ist ein anderes Konzept (Übergang Vorrunde→K.-o. bei platzierungsrelevantem Unentschieden).';

  @override
  String get tournamentSetupInfoKoConsolationDirectTitle =>
      'Wer direkt im Trostturnier startet';

  @override
  String get tournamentSetupInfoKoConsolationDirectBody =>
      'Wie viele Teams direkt aus der Vorrunde ins Trostturnier einsteigen, zusätzlich zu den im Hauptbaum ausgeschiedenen. \"Keine\" heisst: nur Ausgeschiedene aus dem Hauptbaum.';

  @override
  String get tournamentSetupInfoKoConsolationNameTitle =>
      'Name des Trostturniers';

  @override
  String get tournamentSetupInfoKoConsolationNameBody =>
      'Pflichtfeld beim Trostturnier: unter diesem Namen erscheint der Nebenwettbewerb. Ohne Namen kannst du nicht weiter.';

  @override
  String get tournamentSetupInfoKoRoundRulesTitle => 'Regeln je Runde';

  @override
  String get tournamentSetupInfoKoRoundRulesBody =>
      'Pro K.-o.-Runde einstellbar: wie viele Sätze zum Sieg nötig sind, das Zeitlimit pro Spiel, die Pause danach und ob ein Tiebreak greift. Spätere Runden dürfen länger angesetzt sein als frühe.';

  @override
  String get tournamentSetupInfoMaxSetsTitle => 'Sätze pro Spiel (Vorrunde)';

  @override
  String get tournamentSetupInfoMaxSetsBody =>
      'Die höchstmögliche Anzahl Sätze, die ein Vorrunden-Spiel dauern darf. In der Vorrunde dürfen Spiele unentschieden enden; die Rangliste entscheidet über das Weiterkommen.';

  @override
  String get tournamentSetupInfoGroupCountTitle => 'In wie viele Gruppen';

  @override
  String get tournamentSetupInfoGroupCountBody =>
      'Wie viele Gruppen in der Gruppenphase gebildet werden. Aus jeder Gruppe ziehen gleich viele Teams ins K.-o. — diese Zahl muss zur K.-o.-Grösse passen (sie wird im nächsten Schritt geprüft).';

  @override
  String get tournamentSetupInfoGroupingStrategyTitle =>
      'Wie Teams auf Gruppen verteilt werden';

  @override
  String get tournamentSetupInfoGroupingStrategyBody =>
      'Legt fest, nach welchem Prinzip die Teams den Gruppen zugeordnet werden. Reissverschluss: stärkste und schwächste Teams werden abwechselnd verteilt, damit die Gruppen etwa gleich stark sind. Blockweise: die Top-Teams werden der Reihe nach auf die Gruppen verteilt. Zufall: zufällige Verteilung, mit gesetztem Seed reproduzierbar.';

  @override
  String get tournamentSetupInfoRandomSeedTitle =>
      'Startwert für die Zufallsverteilung';

  @override
  String get tournamentSetupInfoRandomSeedBody =>
      'Eine Zahl, die die zufällige Gruppierung steuerbar macht: derselbe Seed erzeugt immer dieselbe Verteilung. Lässt du das Feld leer, wird jedes Mal neu gemischt.';

  @override
  String get tournamentSetupInfoPitchAssignmentTitle =>
      'Welche Felder für welche Gruppe';

  @override
  String get tournamentSetupInfoPitchAssignmentBody =>
      'Ordnet jeder Gruppe (A, B, C, …) die Felder zu, auf denen ihre Spiele laufen. Ein Feld darf mehreren Gruppen dienen. Nur in der Gruppenphase und nur, wenn du Felder angelegt hast.';

  @override
  String get tournamentSetupInfoSchochRoundsTitle => 'Anzahl Schoch-Runden';

  @override
  String get tournamentSetupInfoSchochRoundsBody =>
      'Wie viele Runden im Schoch-Modus gespielt werden. Mehr Runden trennen die Tabelle sauberer — bei grossen Feldern zu empfehlen. Die Paarungen jeder Runde entstehen live nach Tabellenstand.';

  @override
  String get tournamentWizardSchochRoundsLabel => 'Runden';

  @override
  String get tournamentWizardSchochLargeFieldHint =>
      'Grosses Feld: mehr Runden trennen die Tabelle sauberer.';

  @override
  String get tournamentWizardSchochTiebreak =>
      'Tiebreak: Buchholz → Direct-Encounter → Random';

  @override
  String get tournamentSetupInfoMatchTimeTitle => 'Zeit pro Spiel';

  @override
  String get tournamentSetupInfoMatchTimeBody =>
      'Zeitlimit für eine einzelne Begegnung, in Minuten.';

  @override
  String get tournamentSetupInfoBreakBetweenTitle => 'Pause nach einem Spiel';

  @override
  String get tournamentSetupInfoBreakBetweenBody =>
      'Wie lange nach einem Spiel pausiert wird, bevor das nächste auf demselben Feld startet, in Minuten. 0 heisst keine Pause.';

  @override
  String get stageTypeGraphEyebrow => 'Stufen-Typ · Editor';

  @override
  String get stageTypeGraphTitle => 'Stufen-Typ modellieren';

  @override
  String get stageTypeGraphCategorySection => 'Kategorie';

  @override
  String get stageTypeGraphCategoryKo => 'K.-o.';

  @override
  String get stageTypeGraphCategoryVorrunde => 'Vorrunde';

  @override
  String get stageTypeGraphCategoryHint =>
      'K.-o.: Felder halbieren sich Richtung Final. Vorrunde: Felderzahl bleibt konstant, alle spielen weiter.';

  @override
  String get stageTypeGraphParticipantsLabel => 'Teilnehmer';

  @override
  String get stageTypeGraphParticipantsHint =>
      'Erzeugt Runde 1 mit Feldern F1 … Fn.';

  @override
  String get stageTypeGraphRebuildRound1 => 'Runde 1 neu erzeugen';

  @override
  String get stageTypeGraphRoundsSection => 'Runden';

  @override
  String get stageTypeGraphAddRound => 'Runde hinzufügen';

  @override
  String get stageTypeGraphDeleteRound => 'Runde löschen';

  @override
  String stageTypeGraphRoundTitle(String round) {
    return 'Runde $round';
  }

  @override
  String stageTypeGraphRoundFieldCount(int count) {
    return '$count Felder';
  }

  @override
  String get stageTypeGraphFieldCountLabel => 'Felderzahl';

  @override
  String get stageTypeGraphPlatesHint =>
      'Platten dieser Runde. In der Vorrunde bleibt die Zahl über alle Runden konstant.';

  @override
  String get stageTypeGraphAdvanceAllNote =>
      'Alle weiter → nächste Runde. Die Neupaarung folgt der Vorrunden-Regel; einzelne Sieger-/Verlierer-Wege gibt es hier nicht.';

  @override
  String get stageTypeGraphPairingRuleLabel => 'Neupaarung';

  @override
  String get stageTypeGraphPairingGroup => 'Gruppe (jeder gegen jeden)';

  @override
  String get stageTypeGraphPairingSchoch => 'Schoch (Auslosung nach Stand)';

  @override
  String get stageTypeGraphEdgesSection => 'Feld-Verdrahtung';

  @override
  String get stageTypeGraphAddEdge => 'Kante hinzufügen';

  @override
  String get stageTypeGraphDeleteEdge => 'Kante löschen';

  @override
  String get stageTypeGraphEdgesVorrundeHint =>
      'In der Vorrunde laufen alle weiter — es gibt keine einzelnen Sieger-/Verlierer-Kanten zum Anwählen.';

  @override
  String get stageTypeGraphEdgesEmpty => 'Noch keine Kanten verdrahtet.';

  @override
  String get stageTypeGraphEdgeKindLabel => 'Art';

  @override
  String get stageTypeGraphEdgeWinner => 'Sieger';

  @override
  String get stageTypeGraphEdgeLoser => 'Verlierer';

  @override
  String get stageTypeGraphEdgeOpen => 'Offen lassen';

  @override
  String get stageTypeGraphEdgeOpenWarning =>
      'Ein offener Weg ist erlaubt, wird aber als Warnung markiert.';

  @override
  String get stageTypeGraphEdgeFromField => 'Von Feld';

  @override
  String get stageTypeGraphEdgeToField => 'Zu Feld';

  @override
  String get stageTypeGraphEdgeSlotLabel => 'Seite';

  @override
  String get stageTypeGraphValidationSection => 'Prüfung';

  @override
  String get stageTypeGraphSavable => 'Speicherbar';

  @override
  String get stageTypeGraphNotSavable => 'Nicht speicherbar';

  @override
  String get stageTypeGraphNoFindings => 'Keine Befunde.';

  @override
  String get stageTypeGraphSeverityError => 'Fehler';

  @override
  String get stageTypeGraphSeverityWarning => 'Warnung';

  @override
  String get stageTypeGraphSave => 'Speichern';

  @override
  String get stageTypeGraphCancel => 'Abbrechen';

  @override
  String get stageTypeGraphConfirm => 'Übernehmen';

  @override
  String get stageTypeTemplatesSection => 'Typ-Vorlagen';

  @override
  String get stageTypeTemplatePickerLabel => 'Vorlage wählen';

  @override
  String get stageTypeTemplateApply => 'Anwenden';

  @override
  String get stageTypeTemplateSave => 'Als Vorlage speichern';

  @override
  String get stageTypeTemplateSystemBadge => 'Vorlage';

  @override
  String get stageTypeTemplatesEmpty => 'Keine Typ-Vorlagen verfügbar.';

  @override
  String get stageTypeTemplatesError =>
      'Typ-Vorlagen konnten nicht geladen werden.';

  @override
  String get stageTypeTemplateApplied => 'Vorlage angewendet.';

  @override
  String get stageTypeTemplateSaved => 'Als Vorlage gespeichert.';

  @override
  String get stageTypeTemplateSaveError =>
      'Vorlage konnte nicht gespeichert werden.';

  @override
  String get stageTypeTemplateRetry => 'Erneut versuchen';

  @override
  String get stageTypeGraphKoConfigLabel => 'K.-o.-Konfiguration';

  @override
  String get stageTypeGraphRoundFormatLabel => 'Match-Format dieser Runde';

  @override
  String get stageTypeGraphCanvasEmpty =>
      'Noch keine Runden. Lege im Formular eine Runde an, dann erscheinen hier die Felder.';

  @override
  String stageTypeGraphCanvasFieldRound(String round) {
    return 'Runde $round';
  }

  @override
  String get stageTypeGraphCanvasInPort => 'Eingang';

  @override
  String get stageTypeGraphCanvasWinnerPort =>
      'Sieger-Ausgang — auf Zielfeld ziehen';

  @override
  String get stageTypeGraphCanvasLoserPort =>
      'Verlierer-Ausgang — auf Zielfeld ziehen';

  @override
  String get stageTypeGraphCanvasAdvanceAll => 'Alle weiter';

  @override
  String get stageTypeGraphCanvasVorrundeTerminal => 'Letzte Runde';

  @override
  String stageTypeGraphCanvasDeleteEdge(String edge) {
    return 'Kante $edge entfernen?';
  }

  @override
  String stageTypeGraphCanvasErrors(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Fehler — nicht speicherbar',
      one: '1 Fehler — nicht speicherbar',
    );
    return '$_temp0';
  }

  @override
  String stageTypeGraphCanvasWarnings(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Speicherbar · $count Warnungen',
      one: 'Speicherbar · 1 Warnung',
    );
    return '$_temp0';
  }

  @override
  String tournamentWizardSummaryTypeRoundLabel(int round, int fields) {
    return 'Runde $round ($fields Felder)';
  }

  @override
  String tournamentWizardSummaryTypeFields(String ids) {
    return 'Felder: $ids';
  }

  @override
  String tournamentWizardSummaryTypeFormat(int maxSets, int minutes) {
    return 'Bo$maxSets · $minutes Min.';
  }

  @override
  String get tournamentWizardSummaryTypePairingRoundRobin =>
      'Jeder gegen jeden';

  @override
  String get tournamentWizardSummaryTypePairingSchoch => 'Schoch / Monrad';

  @override
  String get tournamentWizardSummaryTypeRoutingAdvanceAll => 'Alle weiter';

  @override
  String tournamentWizardSummaryTypeRouting(int winners, int losers, int open) {
    return 'Sieger $winners · Verlierer $losers · Offen $open';
  }
}
