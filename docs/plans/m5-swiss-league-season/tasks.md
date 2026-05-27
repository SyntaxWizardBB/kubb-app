# M5 — Task-Breakdown

> Status: Entwurf, wartet auf Abnahme
> Datum: 2026-05-27
> Level: senior — TDD, atomare Tasks (≤100 LOC, ≤3 Files, ≤1h)
> Bezug: `architecture.md`, `milestone-plan.md`, `open-decisions.md`, `risks-and-deferrals.md`

## Übersicht

16 atomare Tasks über 3 Sub-Milestones und 4 Wellen. Wave-Reihenfolge spiegelt die Dependency-Kette `Domain → Backend → UI+Demo` aus dem Milestone-Plan. Domain-Wave nutzt strikt TDD — jeder Implementierungs-Task hat einen vorausgehenden Test-Task (Red → Green).

| Wave | Sub-Milestone | Tasks | Fokus |
|------|---------------|-------|-------|
| 1 | M5.1 Domain | T1–T5 | SwissPairing, LeaguePointsEngine, Standings-Aggregator |
| 2 | M5.2 Backend | T6–T9 | Migration, RLS, RPC-Erweiterung, pgTAP |
| 3 | M5.3 UI | T10–T14 | Wizard, Saison-Screens, l10n |
| 4 | M5.3 Demo | T15–T16 | e2e-Test + Demo-Seeder |

---

## TASK-M5.1-T1: SwissPairing Property-Tests (TDD-red)

- **Type**: tests
- **Size**: M
- **Bounded Context**: tournament
- **Agent**: tester
- **Dependencies**: —
- **Wave**: 1
- **Files (anticipated)**:
  - `packages/kubb_domain/test/tournament/pairing/swiss_system_test.dart` (neu)
  - `packages/kubb_domain/test/tournament/pairing/buchholz_test.dart` (neu)
- **LOC-Budget**: ~90

### Goal
Test-First für Schweizer-System: Property-Tests definieren das Verhalten von `SwissSystemStrategy` und `BuchholzCalculator`, bevor irgendeine Implementierung existiert. Tests sind initial rot.

### Acceptance Criteria
- Given 8 Spieler nach 0 Runden When `SwissSystemStrategy.plan()` aufgerufen Then 4 Pairings, keine Wiederholung, Bye-Liste leer.
- Given 7 Spieler (ungerade) When erste Runde geplant Then genau 1 Bye-Slot, schwächster Spieler ohne Bye-Vorgeschichte gemäss FR-PAIR-5.
- Given 8 Spieler nach 3 Runden When Runde 4 geplant Then keine Pairing-Wiederholung über alle 4 Runden (Property: für jede Permutation der Input-Reihenfolge ist Pairing-Set bis auf Reihenfolge identisch).
- Given Tiebreak-Reihenfolge Buchholz → Direct-Encounter → Random(seed) (OD-M5-01 Empfehlung B) When zwei Spieler punktgleich Then Sortierung deterministisch.

### Notes
Tests müssen rot laufen — keine Implementierung in diesem Task. Buchholz-Test deckt Σ-Opponent-Scores ab. Random-Seed = `tournament_id + round_no` für Determinismus.

---

## TASK-M5.1-T2: SwissPairingStrategy Implementation

- **Type**: domain
- **Size**: L
- **Bounded Context**: tournament
- **Agent**: coder-frontend
- **Dependencies**: TASK-M5.1-T1
- **Wave**: 1
- **Files (anticipated)**:
  - `packages/kubb_domain/lib/src/tournament/pairing/swiss_system.dart` (neu)
  - `packages/kubb_domain/lib/src/tournament/pairing/buchholz.dart` (neu)
  - `packages/kubb_domain/lib/src/tournament/pairing.dart` (Export ergänzen)
- **LOC-Budget**: ~100

### Goal
Implementiert `SwissSystemStrategy implements PairingStrategy` plus `BuchholzCalculator`, sodass die Tests aus T1 grün werden. Backtracking-Tiefe ≤3 zur Wiederholungs-Vermeidung; bei Sackgasse Marker `repeated: true` (R-M5.1-2).

### Acceptance Criteria
- Given alle Tests aus T1 When `dart test` läuft Then alle grün.
- Given n=64 Eingabe When `plan()` läuft Then p99 Laufzeit <50 ms (Property-Budget aus `architecture.md` §6).
- Given Sackgasse erkannt (Backtracking erschöpft) When Pairing erzwungen Then Output enthält `repeated`-Marker, Algorithmus terminiert.

### Notes
Reine Dart-Logik. Keine Side-Effects, vollständig property-testbar. Bye-Punkt-Gutschrift wird im LeaguePointsEngine vergeben, nicht hier.

---

## TASK-M5.1-T3: LeaguePointsEngine Tests (TDD-red)

- **Type**: tests
- **Size**: M
- **Bounded Context**: tournament
- **Agent**: tester
- **Dependencies**: —
- **Wave**: 1
- **Files (anticipated)**:
  - `packages/kubb_domain/test/tournament/league_points_engine_test.dart` (neu)
- **LOC-Budget**: ~80

### Goal
Test-First für FR-POINTS-1: `Endpunkte = Basispunkte × Turnier-Faktor × Liga-Faktor`. Property-Tests decken Identity (Faktor=1), Linearität (Skalierung), und Permutations-Invarianz ab.

### Acceptance Criteria
- Given Standings + TF=1.0 + LF=1.0 When `compute()` Then `final_points == base_points` (Identity).
- Given Standings + TF=2.0 + LF=1.5 When `compute()` Then `final_points == base_points × 3.0` mit Toleranz <0.01.
- Given Stufungs-Bonus-Tabelle aus Spec FR-POINTS-1 When 1. Platz Then `base_points = N + Bonus_1`.
- Property: Für jede Permutation der Input-Standings ist `Σ awards` bis auf Reihenfolge identisch.
- Given Bye-Empfänger When `compute()` Then Bye-Punkt-Gutschrift gemäss OD-M5-01-Default (voller Match-Punkt = 3 bei 3-1-0-Schema).

### Notes
Tests rot. Match-Punkt-Schema Default 3-1-0 (OD-M5-02 Empfehlung A), konfigurierbar pro Turnier.

---

## TASK-M5.1-T4: LeaguePointsEngine Implementation

- **Type**: domain
- **Size**: M
- **Bounded Context**: tournament
- **Agent**: coder-frontend
- **Dependencies**: TASK-M5.1-T3
- **Wave**: 1
- **Files (anticipated)**:
  - `packages/kubb_domain/lib/src/tournament/league_points_engine.dart` (neu)
  - `packages/kubb_domain/lib/src/tournament/tournament_points_award.dart` (neu, Wert-Objekt)
- **LOC-Budget**: ~80

### Goal
Implementiert `LeaguePointsEngine.compute(finalStandings, config) → List<TournamentPointsAward>` nach FR-POINTS-1. Reine Funktion, kein State.

### Acceptance Criteria
- Given alle Tests aus T3 When `dart test` läuft Then alle grün.
- Given append-only-Output When `compute()` zweimal mit identischem Input Then identische Award-Liste (deterministisch).

### Notes
`TournamentPointsAward`: `participantId`, `leagueId`, `placement`, `basePoints`, `finalPoints`, `breakdown` (Audit-String). Engine ist Domain-Service, kein Aggregat.

---

## TASK-M5.1-T5: Standings-Aggregator (Cross-Tournament)

- **Type**: domain
- **Size**: S
- **Bounded Context**: season
- **Agent**: coder-frontend
- **Dependencies**: TASK-M5.1-T4
- **Wave**: 1
- **Files (anticipated)**:
  - `packages/kubb_domain/lib/src/season/season_standings.dart` (neu)
  - `packages/kubb_domain/test/season/season_standings_test.dart` (neu)
- **LOC-Budget**: ~70

### Goal
Linearer additiver Aggregator: nimmt eine Liste `TournamentPointsAward` und produziert `SeasonStandingsRow` pro Participant (OD-M5-03 Empfehlung A). Sortierung: Σ Punkte desc, Tiebreak Anzahl Turniere desc, dann Anzeigename (OD-M5-06 Empfehlung A).

### Acceptance Criteria
- Given 3 Awards für Participant X (10+10+10) When aggregiert Then Σ = 30.
- Given Reversal-Row (negative Punkte) When aggregiert Then korrekt subtrahiert (OD-M5-07).
- Given zwei Participants mit gleichem Σ When sortiert Then derjenige mit mehr Turnier-Teilnahmen vorne.

### Notes
Tests inline im selben Task (Aggregator ist S-Sized). Read-Model, kein Persistenz-Bezug.

---

## TASK-M5.2-T6: Seasons-Schema Migration

- **Type**: data
- **Size**: L
- **Bounded Context**: season
- **Agent**: coder-data
- **Dependencies**: TASK-M5.1-T5
- **Wave**: 2
- **Files (anticipated)**:
  - `supabase/migrations/20260801000002_season_schema.sql` (neu)
- **LOC-Budget**: ~100

### Goal
Migration legt `seasons`, `season_tournaments`, `season_standings_awards` plus View `v_season_standings` an, inklusive Indices auf `(season_id, league_id, participant_id)` (siehe `architecture.md` §3.2).

### Acceptance Criteria
- Given leere DB When Migration läuft Then alle 3 Tabellen + 1 View existieren, FKs korrekt.
- Given Schema-Diff vs Architecture-ER-Diagramm When Review Then alle Felder vorhanden (inkl. `transfer_window_start/end` als nullable Reservierung gemäss OD-M5-05).
- Given Migration läuft auf bestehender M4-Datenbank When alte `tournaments`-Tabelle When Migration Then keine Mutation alter Tabellen (additiv, R-M5.2-1).

### Notes
Append-only-Charakter von `season_standings_awards` per Trigger (nur INSERT, kein UPDATE/DELETE). Reversal via neue Rows mit negativen `final_points`.

---

## TASK-M5.2-T7: RLS-Policies + season_get RPC

- **Type**: data
- **Size**: M
- **Bounded Context**: season
- **Agent**: coder-data
- **Dependencies**: TASK-M5.2-T6
- **Wave**: 2
- **Files (anticipated)**:
  - `supabase/migrations/20260801000003_season_rls.sql` (neu)
  - `supabase/migrations/20260801000004_season_rpc.sql` (neu)
- **LOC-Budget**: ~90

### Goal
RLS-Policies: `seasons` und `v_season_standings` public-readable für Status `open`/`closed`, `draft` nur für Liga-Admin. `season_tournaments` und `season_standings_awards` schreibbar nur durch Liga-Admin und Plattform-Admin (FR-POINTS-11). RPC `season_get(p_season_id)` als konsolidierter Read-Pfad fürs UI.

### Acceptance Criteria
- Given anon-Caller When `SELECT * FROM v_season_standings WHERE season_id = X` für `open`-Saison Then Daten sichtbar.
- Given anon-Caller When `INSERT INTO season_standings_awards` Then 42501 (permission denied).
- Given `season_get(p_season_id)` als RPC When Call Then JSON mit Saison-Meta + Standings + Turnier-Liste.

### Notes
Liga-Admin-Rolle ist M5 vereinfacht über `auth.jwt() ->> 'role' = 'league_admin'` — vollständige Rollen-Management ist out-of-scope (R-M5-G1).

---

## TASK-M5.2-T8: tournament_pair_round-Erweiterung (Swiss)

- **Type**: data
- **Size**: M
- **Bounded Context**: tournament
- **Agent**: coder-data
- **Dependencies**: TASK-M5.1-T2, TASK-M5.2-T6
- **Wave**: 2
- **Files (anticipated)**:
  - `supabase/migrations/20260801000001_pair_round_swiss.sql` (neu)
- **LOC-Budget**: ~80

### Goal
Bestehende RPC `tournament_pair_round` um `swiss_system`-Dispatch erweitern. Per OD-M5-04 Empfehlung A (Client-Side-Pairing): RPC nimmt Pairing als JSON, validiert via `validate_swiss_pairing(p_tournament_id, p_pairings jsonb)` und inserted Matches.

### Acceptance Criteria
- Given gültiges Pairing-JSON (alle Teilnehmer enthalten, keine Doppel, kein Repeat) When RPC-Call Then Matches inserted, neue Runde erzeugt.
- Given ungültiges Pairing (fehlender Spieler / Doppel-Zuordnung) When RPC-Call Then Exception `invalid_pairing`, kein Insert.
- Given Round-Robin- oder Top-vs-Bottom-Pfad When RPC-Call mit altem Strategy-Arg Then unverändertes Verhalten (Backward-Compat).

### Notes
Validierungs-Funktion ist Trust-Boundary (R-M5.2-2) und wird in T9 separat getestet.

---

## TASK-M5.2-T9: pgTAP Tests für Seasons-Schema + Pairing-Validation

- **Type**: tests
- **Size**: M
- **Bounded Context**: season | tournament
- **Agent**: tester
- **Dependencies**: TASK-M5.2-T6, TASK-M5.2-T7, TASK-M5.2-T8
- **Wave**: 2
- **Files (anticipated)**:
  - `supabase/tests/season_rls.test.sql` (neu)
  - `supabase/tests/pair_round_swiss.test.sql` (neu)
- **LOC-Budget**: ~100

### Goal
pgTAP-Test-Suite über Seasons-RLS und Pairing-Validation. Deckt R-M5.2-2 (Trust-Boundary) mit mindestens 4 negativen Test-Cases (fehlender Teilnehmer / Doppel / Repeat / Bye-Konflikt).

### Acceptance Criteria
- Given pgTAP-Suite läuft When CI Then alle Tests grün.
- Given Idempotenz-Test When Punkte-Sink zweimal feuert für gleiches Turnier Then keine doppelten Awards (Constraint oder Reversal-Logik).
- Given Re-Open-Workflow When Turnier von `finalized` zurück zu `in_progress` Then alle bestehenden Awards bekommen Reversal-Row (R-M5-G3, OD-M5-07).

### Notes
Datei-Pfad `supabase/tests/` konsistent mit M4-pgTAP-Convention.

---

## TASK-M5.3-T10: SwissSystem-Option im Setup-Wizard

- **Type**: frontend
- **Size**: M
- **Bounded Context**: tournament
- **Agent**: coder-frontend
- **Dependencies**: TASK-M5.2-T8
- **Wave**: 3
- **Files (anticipated)**:
  - `lib/features/tournament/presentation/setup_wizard/format_step.dart` (Edit)
  - `lib/features/tournament/presentation/setup_wizard/swiss_config_section.dart` (neu)
- **LOC-Budget**: ~90

### Goal
Format-Step des Setup-Wizards bekommt "Schweizer System" als Option (FR-FMT-4). Bei Auswahl: Konfig-Section mit Runden-Anzahl (Default `ceil(log2(n))`, Min 3, Max 9 — OD-M5-04), Tiebreak-Reihenfolge-Anzeige (read-only Buchholz → Direct-Encounter → Random).

### Acceptance Criteria
- Given Veranstalter wählt "Schweizer System" When Teilnehmer=8 Then Runden-Default=3 (ceil(log2(8))), editierbar.
- Given Teilnehmer=65 When Format=Schweizer System Then Warn-Banner "optimiert auf ≤64" (R-M5-G2).
- Given existierender Round-Robin- oder KO-Pfad When ohne SwissSystem-Auswahl Then unverändert.

### Notes
Pairing-Engine wird Client-Side aufgerufen (per OD-M5-04 A), Result via RPC gepostet.

---

## TASK-M5.3-T11: Saison-CRUD-Screen (Liga-Admin)

- **Type**: frontend
- **Size**: L
- **Bounded Context**: season
- **Agent**: coder-frontend
- **Dependencies**: TASK-M5.2-T7
- **Wave**: 3
- **Files (anticipated)**:
  - `lib/features/season/presentation/season_admin_screen.dart` (neu)
  - `lib/features/season/data/season_repository.dart` (neu)
  - `lib/features/season/application/season_admin_controller.dart` (neu)
- **LOC-Budget**: ~100

### Goal
CRUD-Screen für Liga-Admin: Saison-Liste, Detail-View, Edit-Form (Name, Start, Ende, Liga, Status). Turniere zuordnen / entfernen.

### Acceptance Criteria
- Given Liga-Admin öffnet Screen When neue Saison erstellt mit Pflichtfeldern Then Saison persistent, Liste aktualisiert.
- Given Saison mit Status `draft` When Liga-Admin Status auf `open` setzt Then Saison wird public-readable (T7 RLS).
- Given Turnier wird zugeordnet When Save Then Eintrag in `season_tournaments` mit Snapshot der Faktoren.

### Notes
Riverpod-Provider. Kein Routing-Setup hier (geht in T14). Trennung Repository / Controller / Screen.

---

## TASK-M5.3-T12: Saison-Tabelle-Screen (Standings)

- **Type**: frontend
- **Size**: L
- **Bounded Context**: season
- **Agent**: coder-frontend
- **Dependencies**: TASK-M5.2-T7
- **Wave**: 3
- **Files (anticipated)**:
  - `lib/features/season/presentation/season_standings_screen.dart` (neu)
  - `lib/features/season/presentation/widgets/standings_row.dart` (neu)
  - `lib/features/season/application/season_standings_provider.dart` (neu)
- **LOC-Budget**: ~100

### Goal
Saison-Tabellen-Screen: ListView.builder (Lazy-Render, R-M5.3-1) mit Spalten Rang, Avatar+Name, Σ Punkte, Anzahl Turniere. Liga-Filter im Header. Sortier-Default per OD-M5-06 A.

### Acceptance Criteria
- Given Saison mit 3 finalisierten Turnieren When Screen öffnet Then Tabelle zeigt alle Spieler, Σ Punkte korrekt aggregiert.
- Given 200 Rows (Smoke-Test) When Scroll Then keine sichtbaren Frame-Drops (Lazy-Render).
- Given Liga-Filter ändert sich When Auswahl Then Tabelle neu geladen für gewählte Liga.

### Notes
Datenquelle: RPC `season_get` aus T7. Detail-Tap navigiert zu Spieler-Profil (out-of-scope für M5).

---

## TASK-M5.3-T13: LeaguePointsConfig im Wizard

- **Type**: frontend
- **Size**: M
- **Bounded Context**: tournament
- **Agent**: coder-frontend
- **Dependencies**: TASK-M5.2-T6, TASK-M5.3-T10
- **Wave**: 3
- **Files (anticipated)**:
  - `lib/features/tournament/presentation/setup_wizard/league_points_step.dart` (neu)
  - `lib/features/tournament/presentation/setup_wizard/wizard_flow.dart` (Edit)
- **LOC-Budget**: ~90

### Goal
Kombinierter Wizard-Step "Liga & Punkte" (R-M5.3-2: kein extra Step): Punkte-Modus (Globale Formel / Eigene Punkte, FR-POINTS-8), Saison-Dropdown (FR-CFG-16), Match-Punkt-Schema (Default 3-1-0 per OD-M5-02).

### Acceptance Criteria
- Given Veranstalter wählt "Globale Formel" When Weiter Then `tournament_config.points_mode = global_formula`.
- Given Veranstalter wählt "Eigene Punkte" When Weiter Then Hint "muss vom Plattform-Admin freigegeben werden" (FR-POINTS-10, dataset-only in M5).
- Given Saison-Dropdown leer When Liga ohne offene Saison Then Option "(keine Zuordnung)".

### Notes
Custom-Punkte-Freigabe-Workflow ist out-of-scope, nur Datenfeld setzen.

---

## TASK-M5.3-T14: l10n DE-Strings

- **Type**: frontend
- **Size**: S
- **Bounded Context**: core
- **Agent**: coder-frontend
- **Dependencies**: TASK-M5.3-T10, TASK-M5.3-T11, TASK-M5.3-T12, TASK-M5.3-T13
- **Wave**: 3
- **Files (anticipated)**:
  - `lib/l10n/app_de.arb` (Edit)
  - `lib/l10n/app_en.arb` (Edit, falls vorhanden)
- **LOC-Budget**: ~60

### Goal
Alle neuen UI-Strings als l10n-Keys in DE. Englische Stubs werden nur ergänzt wenn `app_en.arb` existiert.

### Acceptance Criteria
- Given alle neuen Screens When DE-Locale aktiv Then keine hardcoded Strings sichtbar.
- Given `flutter gen-l10n` läuft When Build Then keine Warnings über fehlende Keys.

### Notes
Key-Struktur: `season.*`, `tournament.swiss.*`, `tournament.points.*`. Konsistent mit M4-Conventions.

---

## TASK-M5.3-T15: e2e-Test 3-Turnier-Saison

- **Type**: tests
- **Size**: L
- **Bounded Context**: season
- **Agent**: tester
- **Dependencies**: TASK-M5.3-T11, TASK-M5.3-T12, TASK-M5.3-T13
- **Wave**: 4
- **Files (anticipated)**:
  - `integration_test/season_three_tournament_flow_test.dart` (neu)
- **LOC-Budget**: ~100

### Goal
Integration-Test mit Patrol / `integration_test`: Liga-Admin erstellt Saison → Veranstalter legt 3 Turniere im Schweizer System an → simulierte Ergebnisse → Saison-Tabelle zeigt korrekte Σ Punkte aller Spieler.

### Acceptance Criteria
- Given frische Test-DB When Test läuft Then alle 6 Demobarkeits-Schritte aus `milestone-plan.md` durchlaufen.
- Given Test beendet Then Saison-Tabelle zeigt 8 Spieler mit Σ Punkten >0, mindestens 1 Spieler mit Bye-Eintrag.

### Notes
Test-DB via Supabase-CLI-Setup, parallel-isolierbar via Schema-Prefix.

---

## TASK-M5.3-T16: Demo-Seeder Script

- **Type**: tests
- **Size**: M
- **Bounded Context**: season
- **Agent**: coder-data
- **Dependencies**: TASK-M5.3-T15
- **Wave**: 4
- **Files (anticipated)**:
  - `scripts/demo_swiss_league.dart` (neu)
- **LOC-Budget**: ~80

### Goal
Demo-Seeder generiert 8-Spieler-Liga, 3 Turniere in einer Saison "Frühling 2026 — Liga B", komplette Match-Ergebnisse, fertig finalisiert. Ermöglicht 20-Min-Demo statt 60-Min-Manuell.

### Acceptance Criteria
- Given leere DB + Seeder-Run When Demo-Skript läuft Then `season_standings_awards` enthält 24 Rows (3 Turniere × 8 Spieler).
- Given Demo-Run When `season_standings_screen` öffnet Then sofort befüllte Tabelle ohne weitere Eingaben.

### Notes
Skript ist idempotent — re-run löscht Demo-Daten via Tag/Marker und neu seeded.
