# Tournament foundation — Meilensteine

> Status: Entwurf, wartet auf Abnahme
> Datum: 2026-05-25
> Bezug: `architecture.md`, `open-decisions.md`

## Überblick

Sechs Milestones. M0 ist reine pure-Dart-Arbeit ohne UI und ohne DB. M1 ist der erste demobare End-to-End-Slice. M2–M5 sind Headline-Schätzungen, mit Detail-Abnahme jeweils nach Abschluss der vorigen Milestone.

Schätzungen sind in Senior-Tempo-Tagen (per `scrum-master.md` Faktor 0.8) — eine Person, fokussiert, ohne Kontextwechsel.

| Milestone | Inhalt | Aufwand | Demobar? |
|---|---|---|---|
| M0 | Pure-Domain: Bracket, Pairing, EKC-Score | 4–6 Tage | Nein, nur Tests |
| M1 | MVP-Slice: 8-Spieler-Round-Robin Einzel, e2e | 9–12 Tage | Ja |
| M2 | KO-Bracket + Setup-Wizard ausbauen | 8–10 Tage | Ja |
| M3 | Teams + Team-Pool + Roster | 10–14 Tage | Ja |
| M4 | Realtime + Veranstalter Live-Dashboard | 8–10 Tage | Ja |
| M5 | Schweizer System + Liga-Punkte + Saisontabelle | 10–14 Tage | Ja |

Owner-Abnahme zwischen jeder Milestone. Spätere Milestones werden vor Beginn neu geschätzt.

## M0 — Domain-Kern (4–6 Tage)

Pure Dart in `packages/kubb_domain/lib/src/tournament/`. Keine UI, keine DB, keine Supabase-Aufrufe.

### Tasks

| ID | Task | Grösse |
|---|---|---|
| M0-T1 | `Bracket`-Wertobjekt + Single-Elimination-Generator | M |
| M0-T2 | `Pool`-Wertobjekt + Round-Robin-Generator | M |
| M0-T3 | `Pairing`-Strategien (Round-Robin, Top-vs-Bottom, 1-vs-2) | S |
| M0-T4 | `Tiebreaker`-Comparator-Chain | S |
| M0-T5 | `Standings`-Berechnung aus `List<MatchResult>` | M |
| M0-T6 | `score_system.dart` mit EKC-Berechnung (Basekubbs + König → Punkte) | S |
| M0-T7 | Property-Tests via `glados` für Bracket-Determinismus und Tiebreaker-Stabilität | M |

### Akzeptanz

- Given 8 Teilnehmer When `generateRoundRobin(8)` Then 7 Runden, kein BYE, kein Teilnehmer paart sich zweimal mit demselben Gegner.
- Given 7 Teilnehmer When `generateRoundRobin(7)` Then 7 Runden, jeder Teilnehmer hat genau einmal BYE.
- Given `MatchResult(setsWonA=2, setsWonB=1, basekubbs=[3-5,5-2,5-4])` When `applyEkcScoring()` Then Match-Score-A = 1+1+1 + 3 = 6 Sätze-Punkte (1 pro Basekubb des Set-Gewinners + 3 pro Set-Sieg ... — Detail in Score-Spec).
- Tiebreaker-Reihenfolge `[Wins, BuchholzMinusH2H, KubbDiff]` produziert auf identischen Eingabedaten immer dieselbe Sortierung.

### FR-Coverage

- [FR-FMT-2 Round Robin](../../specs/tournament-mode-spec.md#38-turnierformate-fr-fmt)
- [FR-PAIR-1/-2/-3](../../specs/tournament-mode-spec.md#39-paarungsgenerierung-fr-pair)
- [FR-RANK-4 Tiebreaker](../../specs/tournament-mode-spec.md#313-turnier-rangliste-fr-rank)
- [FR-CFG-6 EKC-Score](../../specs/tournament-mode-spec.md#35-turnier-konfiguration-durch-veranstalter-fr-cfg)

## M1 — MVP-Slice: 8-Spieler-Einzelturnier (9–12 Tage)

Vertikaler Schnitt. Ein Veranstalter, acht Einzelspieler, Round-Robin, EKC-Score per-Satz, Endrangliste, alles e2e durch echtes Supabase.

### Vertical Slice (Happy Path)

1. Veranstalter (auf Mobile reicht) legt Turnier an: Name, Teamgrösse 1, max 8 Teilnehmer, Format Round-Robin, EKC-Score, Anmeldung sofort offen.
2. Veranstalter veröffentlicht.
3. Acht Spieler melden sich an. Veranstalter approved alle (oder Auto-Approve, siehe [OD-04](open-decisions.md#od-04-auto-approve)).
4. Veranstalter klickt "Turnier starten". App generiert die Round-Robin-Runden, schreibt Match-Plan in DB.
5. Jeder Spieler sieht in seiner App "Match 1 gegen X" (Polling alle 5 s).
6. Pro Match tragen beide Spieler Satz-Daten ein. Bei Übereinstimmung: Match finalisiert, Rangliste aktualisiert.
7. Bei Konflikt: zweiter Versuch automatisch. Bei Strittig nach Versuch 3: Veranstalter overrided manuell.
8. Nach allen Runden: "Turnier abschliessen". Endrangliste angezeigt.

Aussen vor: KO-Phase, Teams, Liga-Punkte, Realtime, Lageplan, Push-Notifications, Schweizer System. **Polling reicht im MVP**, alle Sichten refetchen jedes 5-Sekunden-Intervall.

### Tasks

| ID | Task | Grösse |
|---|---|---|
| M1-T1 | Supabase-Migration `tournament_schema.sql` (Tabellen, RLS, BASIS-Indices) | L |
| M1-T2 | Supabase-RPCs `tournament_create`, `tournament_publish`, `tournament_open_registration`, `tournament_close_registration` | M |
| M1-T3 | Supabase-RPC `tournament_register_single`, `tournament_list_for_caller`, `tournament_get` | M |
| M1-T4 | Supabase-RPC `tournament_start_round`, `tournament_finalize`, `tournament_compute_standings` (clientseitig genügt vorerst) | L |
| M1-T5 | Supabase-RPC `tournament_propose_set_score` mit 3-Versuche-Konsens (kopiert + erweitert aus `match_propose_result`) | L |
| M1-T6 | Supabase-RPC `tournament_organizer_override` mit Pflicht-Begründung | M |
| M1-T7 | `tournament_models.dart` + `tournament_repository.dart` (Wire-Types + Adapter) | L |
| M1-T8 | `TournamentRemote`-Port-Umschrift in `kubb_domain` (alten Match-Event-Pfad parken) | S |
| M1-T9 | Setup-Wizard-Screen (4 Schritte für MVP, ohne Wahl-Optionen für KO, Tiebreaker, Lageplan) | L |
| M1-T10 | Turnier-Liste + Turnier-Detail-Screen (öffentlich + eigene) | M |
| M1-T11 | Registrierungs-Screen Einzel | S |
| M1-T12 | Match-Detail-Screen mit Satz-Eingabe-UI (Stepper für Basekubbs, Switch für König) + Live-Vorschau | L |
| M1-T13 | Konflikt-Screen (Vergleichs-Tabelle, Diff-Highlight, Erneut-eintragen-Button) | M |
| M1-T14 | Veranstalter-Override-Screen (Strittig-Liste, finale Eingabe, Begründung-Pflichtfeld) | M |
| M1-T15 | Endrangliste-Screen mit Tiebreaker-Spalten | S |
| M1-T16 | Score-Draft-Cache (lokaler Entwurf via drift, DSCORE-19/20/21/22) | M |
| M1-T17 | Routing-Anbindung in `lib/app/router.dart` | S |
| M1-T18 | Integrations-Test: 4 Spieler, 6 Runden, ein Konflikt → Rangliste korrekt | M |

### Akzeptanz (Given/When/Then, Auswahl)

- Given Veranstalter im Setup-Wizard When alle Pflichtfelder ausgefüllt + "Erstellen" Then Turnier-Row in Status `draft` existiert, sichtbar in "Eigene Turniere".
- Given Spieler-Konto und Turnier in Status `registration_open` When "Anmelden" Then Eintrag in `tournament_participants` mit Status `pending`.
- Given Match in `awaiting_results` und beide Spieler tragen identische Sätze ein When zweiter Submit Then Match-Status wird `finalized`, Rangliste aktualisiert sich beim nächsten Refetch.
- Given Match in `awaiting_results` und Spieler tragen abweichende Sätze ein für drei Versuche When dritter Submit abweicht Then Match-Status wird `disputed`, Veranstalter sieht es im Dashboard.
- Given Match in `disputed` und Veranstalter trägt finalen Score + Begründung ein When Submit Then Match wird `overridden_finalized`, Audit-Event geschrieben mit Begründung im Payload.

### FR-Coverage

- [FR-AUTH-1](../../specs/tournament-mode-spec.md#31-authentifizierung-und-profile-fr-auth) (schon umgesetzt)
- [FR-CFG-1/2/3/4/5/6/7/20/21](../../specs/tournament-mode-spec.md#35-turnier-konfiguration-durch-veranstalter-fr-cfg) — Konfiguration im Wizard, eingefroren nach Veröffentlichung
- [FR-REG-1/3/6/7/10](../../specs/tournament-mode-spec.md#36-anmeldung-fr-reg) — Einzel-Anmeldung, Cutoff
- [FR-FMT-2](../../specs/tournament-mode-spec.md#38-turnierformate-fr-fmt) — Round Robin
- [FR-PAIR-1/3/8](../../specs/tournament-mode-spec.md#39-paarungsgenerierung-fr-pair) — Auto-Paarung, keine Wiederholungen
- [FR-MATCH-1/3/4](../../specs/tournament-mode-spec.md#310-match-durchführung-fr-match) — Pitch-Zuteilung (vereinfacht: alle auf Pitch 1, mehrere Matches sequentiell), Status-Übergänge
- [FR-SCORE-1/2/3/4](../../specs/tournament-mode-spec.md#311-score-eingabe-fr-score) — Eingabe pro Satz, Live-Vorschau, Plausibilität
- [FR-CONF-1/2/3/6/7](../../specs/tournament-mode-spec.md#312-konfliktauflösung-fr-conf) — Drei-Versuche-Flow, Differenz-Anzeige
- [FR-RANK-1/2/3/4/5](../../specs/tournament-mode-spec.md#313-turnier-rangliste-fr-rank) — Live-Rangliste mit Tiebreakern
- [FR-PUB-1/2/3](../../specs/tournament-mode-spec.md#317-öffentliche-sichten-fr-pub) — Öffentliche Turnier-Sicht
- Score-Spec DSCORE-1..-58, -68, -81, -83, -87, -88 (Score-Eingabe-Flow inkl. Override). Ausgenommen: -19..-22 partial (Draft-Cache, aber ohne Web-Pendant — M1 ist mobile only), Outbox -94..-104 (Offline wird in M4 fertig).

### Demo-Skript

Eine Live-Demo nach M1:

1. Owner und Architect loggen sich auf zwei Phones ein (plus ein Tablet für Veranstalter).
2. Owner legt 8-Spieler-Round-Robin-Turnier an, veröffentlicht, öffnet Anmeldung.
3. Architect + 6 Test-Accounts melden sich an.
4. Owner approved, startet Turnier.
5. Einige Matches spielen wir durch, einen mit Score-Konflikt, einen mit Override.
6. Endrangliste anschauen, Tiebreaker-Werte sind nachvollziehbar.

Wenn das in <30 Min lauffähig ist, ist der Slice abgenommen.

## M2 — KO-Bracket + Setup-Wizard-Polish (8–10 Tage, Headline)

Vorerst nur Outline, Details bei Abnahme von M1.

Inhalt:

- Bracket-Generation (Single-Elimination) als pure Funktion. Hinzu: Seeding aus Standings (FR-FMT-10), manuelle Override (FR-PAIR-7).
- KO-Phase nach Gruppenphase (FR-FMT-5: Gruppenphase + KO).
- Bracket-Visualisierungs-Widget (eigener CustomPainter oder Lib-Wahl als ADR).
- Setup-Wizard erweitert um KO-Konfiguration und Tiebreaker-Reihenfolge.
- Spiel-um-Platz-3 als Option (FR-FMT-1).

FR-Coverage: [FR-FMT-1, FR-FMT-5, FR-FMT-10, FR-FMT-11](../../specs/tournament-mode-spec.md#38-turnierformate-fr-fmt), [FR-PAIR-7](../../specs/tournament-mode-spec.md#39-paarungsgenerierung-fr-pair), [FR-PUB-6](../../specs/tournament-mode-spec.md#317-öffentliche-sichten-fr-pub).

## M3 — Teams + Pool + Roster (10–14 Tage, Headline)

Vorerst nur Outline.

Inhalt:

- Team-Tabellen `teams`, `team_members`.
- Team-gründen-Screen, Pool-Mitglieder-Verwaltung, Gast-Spieler.
- Captain-Rechte-Modell: jedes registrierte Mitglied kann das Team anmelden, Roster wählen, Score eintragen (BR-27).
- Roster-Auswahl beim Anmelden (FR-TEAM-12).
- Mid-Turnier-Roster-Swap (FR-TEAM-13).
- Team-Turniere (Teamgrösse 2, 3, 6).
- Audit-Log für Roster-Wechsel + Pool-Mitgliedschaft.

FR-Coverage: [FR-TEAM-1..20](../../specs/tournament-mode-spec.md#37-teams-und-team-mitgliedschaft-fr-team), [FR-REG-2, FR-REG-11, FR-REG-12](../../specs/tournament-mode-spec.md#36-anmeldung-fr-reg).

## M4 — Realtime + Live-Dashboard + Offline (8–10 Tage, Headline)

Vorerst nur Outline.

Inhalt:

- Supabase Realtime statt Polling. Channel pro geöffnetem Turnier.
- Veranstalter Live-Dashboard mit allen Pitches im Überblick, farbcodiert (FR-LIVE-1).
- Runden-Clock mit Pause/Verlängerung/vorzeitigem Ende (FR-LIVE-5..-8).
- Offline-Toleranz: ScoreOutbox-Implementierung Mobile (drift) + Web (sembast_web). DSCORE-93..-104.
- Push-Notifications (FCM Android, APNs iOS): Match-Start, Konflikt, Score-Erinnerung alle 5 Min.

FR-Coverage: [FR-LIVE-1..-10](../../specs/tournament-mode-spec.md#318-live-management-während-des-turniers-fr-live), [FR-NOT-1..-7](../../specs/tournament-mode-spec.md#316-benachrichtigungen-fr-not), [FR-PUB-11](../../specs/tournament-mode-spec.md#317-öffentliche-sichten-fr-pub).

## M5 — Schweizer System + Liga-Punkte + Saisontabelle (10–14 Tage, Headline)

Vorerst nur Outline.

Inhalt:

- Schochmodus + Schweizer System als zusätzliche Paarungsstrategien in `kubb_domain`.
- Liga-Punkte-Formel-Implementierung (FR-POINTS-1..-7).
- Saison-Tabellen pro Liga, eingefroren am Saisonende.
- Plattform-Admin-Surface (CLI reicht für MVP-Saison-Management).
- Mid-season-Liga-Wechsel durch Liga-Admin.

FR-Coverage: [FR-FMT-3, FR-FMT-4, FR-FMT-6, FR-FMT-7](../../specs/tournament-mode-spec.md#38-turnierformate-fr-fmt), [FR-POINTS-1..-18](../../specs/tournament-mode-spec.md#314-liga-punkte-system-fr-points), [FR-GLB-1..-22](../../specs/tournament-mode-spec.md#315-globales-ranking-und-liga-system-fr-glb), [FR-ADM-1..-17](../../specs/tournament-mode-spec.md#321-administration-fr-adm).

## Was nach M5 noch fehlt (für Vollabdeckung der Spec)

- Vereine + Vereins-Admin-Rolle (FR-CLUB)
- Veranstalter-Bewertung (FR-FEEDBACK)
- Lageplan (FR-MAP)
- Vollbild-Streaming-Sicht (FR-PUB-10, KANN)
- Shared Tournament mit Liga-Split (FR-FMT-8, FR-POINTS-14/15)
- Double Elimination (FR-FMT-9, KANN)
- Privatsphäre-Granularität FR-AUTH-5 + Datenexport FR-AUTH-6
- Self-Check-In via QR-Code (FR-REG-9, SOLL)
- Französisch + Englisch (NFR-I18N-2)

Diese werden in einer separaten Planungs-Runde nach M5 priorisiert. Die Vollspec ist auf 200+ Anforderungen ausgelegt — ohne Abnahme zwischen den Schritten wird das nichts.
