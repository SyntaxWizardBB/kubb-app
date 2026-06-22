# Tasks — Schoch/Buchholz, Vorrunde-Ranking, Stage-Seeding & Stage-Graph

**Status:** Sprint-Backlog (atomare Tasks fuer `/workflows/implement`).
**Bezug:** `docs/plans/schoch-stage-graph/architecture.md` (B1->B2->B4->B3),
ADR-0035..0038, Specs unter `docs/specs/`.
**Level:** senior (TDD-first fuer Domain/Engine, Conventional-Commit-Scopes,
Paritaets-Tests, explizite Refactoring-Tasks).
**Atomaritaet (senior):** <=100 LOC, <=3 Dateien, <=1h pro Task, ein Agent pro Task,
Dependencies azyklisch (DAG).

> **Legende Size:** S = 0.5-1h, M = 1-3h, L = 3-5h (mit senior-Faktor 0.8).
> **Legende Type:** domain | data (SQL/Migration) | tests | frontend (UI/Riverpod) | infra.
> **Agent-Mapping:** domain/data -> coder-backend bzw. coder-data; frontend -> coder-frontend;
> tests -> tester; SQL-Migration -> coder-data; reine Domain-Logik -> coder-backend.
> **Akzeptanzkriterien** sind aus den Spec-Quality-Gates abgeleitet (Referenz in Notes).

---

## Owner-Abnahme-Checkpoints (BLOCKING vor dem jeweiligen Milestone)

| Checkpoint | Entscheidung | Blockiert | Empfehlung |
|---|---|---|---|
| **CP-0** (vor M1) | Source-of-Truth Schoch/Buchholz: server-autoritativ + Dart Test-Truth? | M1, M2 | ADR-0036: ja |
| **CP-0** (vor M1) | Golden-Dataset SM Einzel 2026 ins Repo (Pseudonyme/Datenschutz)? | M1-Gates §7.1-7.5 | einchecken, pseudonymisiert |
| **CP-1** (vor M2) | Vorrunden-Rangfolge fix-pro-Typ vs. user-konfigurierbar? | M2 | ADR-0035: fix |
| **CP-2** (vor M3) | Seeding pro-Stufe vs. pro-Turnier (Root erbt Seedliste?)? | M3-Resolver | pro-Stufe via node.seeding, Root erbt turnier-weit |
| **CP-3** (vor M4) | Datenmodell Ebene 2: jsonb-Sub-Graph vs. eigene Tabellen? | M4 | ADR-0037: jsonb |
| **CP-3** (vor M4) | OFFEN-1 Vorrunde-Routing: Feld-Edges oder nur Runden + Paarungsregel? | M4 Vorrunde-Kategorie | **Feld-Edges** (Owner-Entscheid, ADR-0039) |

CP-0 und CP-1 sind echte BLOCKING-Eskalationen (sie bestimmen, wo der Code landet und
ob die Gates ueberhaupt ausfuehrbar sind). CP-2/CP-3 koennen als ADR-Bestaetigung
laufen, falls der Owner den Empfehlungen folgt.

---

# M1 — Schoch/Buchholz-Kern (B1, Domain pur)

Fundament. Reine Domain-Korrektur, keine Migration im Domain-Teil; der server-autoritative
Nachzug (ADR-0036) ist die letzten zwei Tasks. TDD: Golden-Fixture + Tests VOR den Fixes.

| Task | Type | Agent | Size | Files (anticipated) | Deps | Goal |
|---|---|---|---|---|---|---|
| M1-T01 | infra | coder-data | M | `packages/kubb_domain/test/tournament/golden/sm_einzel_2026_matches.dart`, `.../golden/sm_einzel_2026_expected.dart` | — | Golden-Dataset SM Einzel 2026 als pseudonymisiertes Test-Fixture einchecken |
| M1-T02 | tests | tester | M | `packages/kubb_domain/test/tournament/pairing/buchholz_golden_test.dart` | M1-T01 | Failing-Test: Buchholz 73/73 gegen Soll-Vektoren (Buschi=682 etc.) |
| M1-T03 | domain | coder-backend | S | `packages/kubb_domain/lib/src/tournament/pairing/buchholz.dart` | M1-T02 | Buchholz-Formel auf Gegenpunkt-Abzug umstellen (Formel §5) |
| M1-T04 | tests | tester | S | `.../test/tournament/properties/tiebreaker_properties_test.dart`, `.../tiebreaker_test.dart` | M1-T01 | Failing-Test: `ParticipantStats._buchholz` mit Gegenpunkt-Abzug |
| M1-T05 | domain | coder-backend | S | `packages/kubb_domain/lib/src/tournament/tiebreaker.dart` | M1-T04 | `_buchholz` in `ParticipantStats` auf Formel §5 angleichen (Parity zu Calculator) |
| M1-T06 | tests | tester | S | `.../test/tournament/standings_test.dart` | M1-T01 | Failing-Test: Schoch-Freilos = fest 16, Querwirkung Meff=411 |
| M1-T07 | domain | coder-backend | S | `packages/kubb_domain/lib/src/tournament/standings.dart` | M1-T06, M1-T03 | `byeScoreForUnopposedParticipant` Schoch-Default 16 verdrahten |
| M1-T08 | tests | tester | S | `.../test/tournament/pairing/swiss_system_test.dart` | M1-T01 | Failing-Test: Determinismus (zwei Laeufe identisch) + Freilos 8/8 |
| M1-T09 | domain | coder-backend | M | `packages/kubb_domain/lib/src/tournament/pairing/swiss_system.dart` | M1-T08, M1-T03 | RNG-jitter durch stabile Startnummer (3. Sort-Key) ersetzen |
| M1-T10 | tests | tester | M | `.../test/tournament/pairing/swiss_system_golden_test.dart` | M1-T09, M1-T01 | Regression-Gate: Monrad-Reproduktion R2-R8>=77%, R3-R8>=87%, R6=36/36, Fold-Negativtest |
| M1-T11 | data | coder-data | M | `supabase/migrations/2026….._stage_schoch_buchholz_fix.sql` | M1-T03 | SQL-Schoch-Rangfolge um korrigierten Buchholz ergaenzen (server-autoritativ, ADR-0036) |
| M1-T12 | tests | tester | M | `.../test/tournament/pairing/buchholz_parity_test.dart` (+ SQL-Fixture-Notiz) | M1-T11, M1-T02 | Paritaets-Test: SQL-Buchholz == Dart-Golden-Vektoren |

### M1-T01 — Golden-Fixture SM Einzel 2026 einchecken
- **ID:** M1-T01 · **Type:** infra · **Agent:** coder-data · **Size:** M
- **Bounded Context:** `kubb_domain/test` (Test-Fixture, Flutter-frei)
- **Deps:** — (Owner CP-0 muss Datenschutz/Pseudonyme freigegeben haben)
- **Goal:** Das SM-Einzel-2026-Dataset (8 Runden, 73 Spieler, alle Match-Punkte) als
  pseudonymisiertes pures-Dart-Fixture mit Soll-Werten (Punkte, Buchholz, Freilos je Runde) ablegen.
- **Akzeptanzkriterien:**
  - Given das eingecheckte Fixture, When Tests es laden, Then liegen 288 Partien + 8 Freilose + Soll-Vektoren (Buschi=682, Beni=691, Sparringspartner=720, Meff=411, Die Nase=390) vor.
  - Given Datenschutz-Vorgabe, When Klarnamen vorkommen, Then sind sie durch stabile Pseudonyme ersetzt (keine echten Personendaten im Repo).
- **Notes:** schoch-spec §3, §7. BLOCKING-Owner-Entscheid CP-0 (Pseudonyme) ist Voraussetzung.

### M1-T02 — Failing-Test Buchholz 73/73
- **ID:** M1-T02 · **Type:** tests · **Agent:** tester · **Size:** M
- **Bounded Context:** `kubb_domain/test/pairing`
- **Deps:** M1-T01
- **Goal:** Test schreiben, der `BuchholzCalculator.scoreFor` gegen alle 73 Soll-Werte prueft (muss zunaechst rot sein).
- **Akzeptanzkriterien:**
  - Given das Golden-Fixture, When der Test laeuft, Then erwartet er 73/73 exakte Buchholz-Werte und scheitert am heutigen naiven Calculator (746 statt 682 fuer Buschi).
  - Given Freilos-Spieler, When geprueft, Then sind Meff=411 und Die Nase=390 explizit als Test-Vektoren enthalten.
- **Notes:** schoch-spec §7.2. TDD-first vor M1-T03.

### M1-T03 — Buchholz-Formel-Fix
- **ID:** M1-T03 · **Type:** domain · **Agent:** coder-backend · **Size:** S
- **Bounded Context:** `kubb_domain/pairing`
- **Deps:** M1-T02
- **Goal:** `scoreFor` pro Gegner um den H2H-Abzug `scoreOf(opp gegen P)` ergaenzen.
- **Akzeptanzkriterien:**
  - Given M1-T02, When der Fix angewandt ist, Then ist der Test gruen (73/73), Buschi=682.
  - Given ein Freilos-Match von P, When berechnet, Then traegt es 0 bei (uebersprungen); `oppTotal` enthaelt das Freilos des Gegners.
  - Given bestehende Tests, When erneut ausgefuehrt, Then bleiben sie gruen (keine Regression).
- **Notes:** schoch-spec §5.2/§5.3. `buchholzMinusH2H` bleibt unangetastet.

### M1-T04 — Failing-Test ParticipantStats-Buchholz
- **ID:** M1-T04 · **Type:** tests · **Agent:** tester · **Size:** S
- **Bounded Context:** `kubb_domain/test`
- **Deps:** M1-T01
- **Goal:** Property/Unit-Test, der `ParticipantStats._buchholz` (via Chain) gegen die Gegenpunkt-Abzug-Formel prueft.
- **Akzeptanzkriterien:**
  - Given dieselben Eingaben wie der Calculator, When `_buchholz` berechnet wird, Then muss der Wert identisch sein (Parity), und der Test scheitert am heutigen naiven `fold`.
- **Notes:** schoch-spec §5.5. Verhindert Divergenz Calculator vs. Chain.

### M1-T05 — ParticipantStats-Buchholz angleichen
- **ID:** M1-T05 · **Type:** domain · **Agent:** coder-backend · **Size:** S
- **Bounded Context:** `kubb_domain`
- **Deps:** M1-T04
- **Goal:** `_buchholz` in `tiebreaker.dart` auf die Gegenpunkt-Abzug-Formel umstellen (mit `headToHeadLookup`).
- **Akzeptanzkriterien:**
  - Given M1-T04, When der Fix sitzt, Then ist der Parity-Test gruen.
  - Given die Schoch-Chain, When sie Buchholz konsumiert, Then nutzt sie die korrigierte Formel, nicht `buchholzMinusH2H`.
- **Notes:** schoch-spec §5.5. `buchholzMinusH2H` und `medianBuchholz` bleiben unveraendert.

### M1-T06 — Failing-Test Freilos=16
- **ID:** M1-T06 · **Type:** tests · **Agent:** tester · **Size:** S · **Deps:** M1-T01
- **Goal:** Test fuer `byeScoreForUnopposedParticipant` = 16 im Schoch-Pfad inkl. Querwirkung auf Gegner-Buchholz.
- **Akzeptanzkriterien:**
  - Given ein Freilos-Spieler im Schoch-Standing, When Standings berechnet werden, Then erhaelt er +16 Punkte und seine 16 fliessen in `oppTotal` der Gegner (Meff=411 exakt).
- **Notes:** schoch-spec §4.2, §7.3.

### M1-T07 — Freilos-Default 16 (Schoch)
- **ID:** M1-T07 · **Type:** domain · **Agent:** coder-backend · **Size:** S · **Deps:** M1-T06, M1-T03
- **Goal:** Schoch-Standings rufen `computeStandings(..., byeScoreForUnopposedParticipant: 16)` auf.
- **Akzeptanzkriterien:**
  - Given Schoch, When ein Spieler ein Freilos hat, Then werden 16 statt 0/3 gutgeschrieben; M1-T06 gruen.
  - Given andere Formate (Gruppenphase), When unveraendert, Then bleibt deren bestehender Bye-Wert erhalten (kein globaler Default-Wechsel).
- **Notes:** schoch-spec §4. Owner-Klarstellung "16 nur Schoch" als Default umgesetzt.

### M1-T08 — Failing-Test Determinismus + Freilos 8/8
- **ID:** M1-T08 · **Type:** tests · **Agent:** tester · **Size:** S · **Deps:** M1-T01
- **Goal:** Test, dass zwei `planRound`-Laeufe identisch sind und die Freilos-Spieler je Runde dem Soll entsprechen (8/8).
- **Akzeptanzkriterien:**
  - Given gleiches (Roster, History), When zweimal gepaart, Then sind die Paarungen byte-identisch (kein per-Runde-Zufall).
  - Given das Golden-Fixture, When je Runde der Freilos bestimmt wird, Then trifft er 8/8 (R1 Die Nase … R8 LaMartina).
- **Notes:** schoch-spec §6.4, §7.3.

### M1-T09 — RNG-jitter durch stabile Startnummer ersetzen
- **ID:** M1-T09 · **Type:** domain · **Agent:** coder-backend · **Size:** M · **Deps:** M1-T08, M1-T03
- **Goal:** 3. Sort-Key von `math.Random(tournamentId.hashCode ^ round)` auf eine ueber das Turnier stabile Startnummer/Seed-Index umstellen.
- **Akzeptanzkriterien:**
  - Given Punkt- und Buchholz-Gleichstand, When sortiert wird, Then entscheidet die stabile Startnummer (aufsteigend), nicht Zufall.
  - Given zwei Prozesse, When derselbe Input, Then identische Reihenfolge (kein `String.hashCode`-Abhaengigkeit).
  - Given M1-T08, When ausgefuehrt, Then gruen.
- **Notes:** schoch-spec §6.1 Key 3, §6.4. Uebergangsquelle: `seedFromStandings`-Index bis B4 (M3) die `random`-Seedliste liefert.

### M1-T10 — Regression-Gate Monrad-Reproduktion
- **ID:** M1-T10 · **Type:** tests · **Agent:** tester · **Size:** M · **Deps:** M1-T09, M1-T01
- **Goal:** Reproduktions-Test der echten Paarungen + Fold/Dutch-Negativtest.
- **Akzeptanzkriterien:**
  - Given Sortierung §6.1 + Monrad-Paarung, When R2-R8 reproduziert, Then >=77 % Treffer; R3-R8 >=87 %; R6 = 36/36.
  - Given dieselbe Sortierung mit Fold/Dutch, When gemessen, Then deutlich schlechter (Sanity-Negativtest).
  - Given alle Runden, When auf Rematches geprueft, Then 0/288.
- **Notes:** schoch-spec §7.4, §7.5.

### M1-T11 — SQL-Buchholz in Schoch-Rangfolge (server-autoritativ)
- **ID:** M1-T11 · **Type:** data · **Agent:** coder-data · **Size:** M · **Deps:** M1-T03
- **Bounded Context:** `supabase/migrations` (additiv)
- **Goal:** Neue additive Migration: die SQL-Schoch-Rangfolge (`tournament_stage_ranking` Schoch-Pfad) rechnet Buchholz nach Formel §5 und nutzt ihn als 2. Sortier-Kriterium.
- **Akzeptanzkriterien:**
  - Given eine Schoch-Stage, When der Live-Cut gebildet wird, Then verwendet die SQL-Rangfolge `points -> buchholz(Formel §5) -> …`.
  - Given die Migration, When eingespielt, Then ist sie additiv/abwaertskompatibel (alte App-Version schreibt weiter).
- **Notes:** ADR-0036. `db push`-Reihenfolge: gehoert zur B2-Migrationswelle (siehe §10 Architektur, Schritt 1 erweitert).

### M1-T12 — Paritaets-Test SQL vs. Dart-Buchholz
- **ID:** M1-T12 · **Type:** tests · **Agent:** tester · **Size:** M · **Deps:** M1-T11, M1-T02
- **Goal:** Test (oder reproduzierbares SQL-Fixture-Skript), das die SQL-Buchholz-Ausgabe gegen die Dart-Golden-Vektoren spiegelt.
- **Akzeptanzkriterien:**
  - Given dasselbe Match-Set, When SQL und Dart Buchholz rechnen, Then identische 73 Werte (Paritaet).
- **Notes:** Architektur §1 (doppelte Wahrheit), Risiko-Tabelle Zeile 1.

---

# M2 — Vorrunde-Ranking + Shoot-out (B2, Domain + SQL)

Trennt die Rangfolge pro Vorrunden-Typ und entfernt den pauschalen SQL-Buchholz-Fallback
fuer `group_phase`. Beide Pfade (Dart + SQL) in einem Milestone (ADR-0036). Braucht M1.

| Task | Type | Agent | Size | Files | Deps | Goal |
|---|---|---|---|---|---|---|
| M2-T01 | tests | tester | S | `.../test/tournament/tiebreaker_chain_for_type_test.dart` | M1-T05 | Failing-Test: `chainForStageType` liefert getrennte Chains |
| M2-T02 | domain | coder-backend | M | `packages/kubb_domain/lib/src/tournament/tiebreaker.dart` | M2-T01 | `chainForStageType(StageNodeType)` Builder |
| M2-T03 | tests | tester | S | `.../test/tournament/standings_test.dart` | M2-T02 | Failing-Test: Gruppenphase trennt nach Kubb-Diff, kein Buchholz |
| M2-T04 | domain | coder-backend | S | `.../standings.dart` bzw. Aufrufstelle der Chain | M2-T03, M2-T02 | Standings konsumieren `chainForStageType` statt globaler Order |
| M2-T05 | data | coder-data | L | `supabase/migrations/2026….._stage_ranking_per_type.sql` | M1-T11 | Ranking-`row_number` nach Stage-Typ verzweigen, pauschalen Buchholz-Fallback fuer group_phase entfernen |
| M2-T06 | tests | tester | M | `.../test/tournament/properties/standings_properties_test.dart` (+ SQL-Audit-Notiz) | M2-T05 | Audit-Test: `e.buchholz`-Grep zeigt keinen group_phase-Pfad |
| M2-T07 | tests | tester | S | `.../test/tournament/shootout_test.dart` | M1-T03 | Failing-Test: Schoch-tied-Key inkl. Buchholz |
| M2-T08 | data | coder-data | M | `supabase/migrations/2026….._detect_shootout_schoch_buchholz.sql` | M2-T05, M2-T07 | `_tournament_detect_shootout_groups` tied-Key fuer Schoch um Buchholz erweitern |
| M2-T09 | tests | tester | S | `.../test/tournament/shootout_test.dart` | M2-T08 | Gate: kosmetischer Gleichstand loest keinen Shoot-out aus |

### M2-T01 — Failing-Test chainForStageType
- **ID:** M2-T01 · **Type:** tests · **Agent:** tester · **Size:** S · **Deps:** M1-T05
- **Goal:** Test, dass ein Builder fuer `groupPhase` `[points, kubbDifference, shootout]` und fuer `schoch` `[points, buchholz, shootout]` liefert.
- **Akzeptanzkriterien:**
  - Given `StageNodeType.groupPhase`, When `chainForStageType`, Then Chain enthaelt `kubbDifference` und **kein** Buchholz.
  - Given `StageNodeType.schoch`, When `chainForStageType`, Then Chain enthaelt Buchholz an 2. Stelle.
- **Notes:** vorrunde-spec §2, §7.5; ADR-0035.

### M2-T02 — chainForStageType-Builder
- **ID:** M2-T02 · **Type:** domain · **Agent:** coder-backend · **Size:** M · **Deps:** M2-T01
- **Goal:** Reinen Builder `chainForStageType(StageNodeType)` ergaenzen, der die fixe Chain je Typ baut.
- **Akzeptanzkriterien:**
  - Given M2-T01, When implementiert, Then gruen; Chain ist nicht user-konfigurierbar (ADR-0035).
  - Given ein unbekannter Typ, When aufgerufen, Then klarer Fehler statt stillem Default.
- **Notes:** vorrunde-spec §6.1; ADR-0035. Chain wird nicht persistiert (keine Spalte).

### M2-T03 — Failing-Test Gruppenphase-Rangfolge
- **ID:** M2-T03 · **Type:** tests · **Agent:** tester · **Size:** S · **Deps:** M2-T02
- **Goal:** Test: zwei punktgleiche Gruppen-Teilnehmer mit unterschiedlicher Kubb-Diff und unterschiedlichem direktem Spiel.
- **Akzeptanzkriterien:**
  - Given Punktgleichstand, When sortiert, Then entscheidet hoehere Kubb-Diff; direktes Spiel und Buchholz haben keinen Einfluss.
- **Notes:** vorrunde-spec §7.1, §7.5.

### M2-T04 — Standings konsumieren typ-spezifische Chain
- **ID:** M2-T04 · **Type:** domain · **Agent:** coder-backend · **Size:** S · **Deps:** M2-T03, M2-T02
- **Goal:** Standing-Berechnung pro Stage zieht ihre Chain aus `chainForStageType(node.type)`.
- **Akzeptanzkriterien:**
  - Given eine Gruppenphase-Stage, When Standings berechnet, Then Buchholz/direktes Spiel sind in keinem Pfad; M2-T03 gruen.
  - Given Schoch, When berechnet, Then Buchholz an 2. Stelle.
- **Notes:** vorrunde-spec §6. `computeStandings` nimmt Chain bereits als Parameter (REUSE).

### M2-T05 — SQL-Ranking per Stage-Typ verzweigen
- **ID:** M2-T05 · **Type:** data · **Agent:** coder-data · **Size:** L · **Deps:** M1-T11
- **Bounded Context:** `supabase/migrations` (additiv, eine Migration ueber alle Ranking-Funktionen)
- **Goal:** In jeder Ranking-`row_number`-Funktion nach Stage-Typ verzweigen; fuer `group_phase` Buchholz/H2H-Fallback entfernen, Kubb-Diff als 2. Key; Schoch behaelt Buchholz (aus M1-T11).
- **Akzeptanzkriterien:**
  - Given eine group_phase-Stage, When der Cut gebildet wird, Then enthaelt der SQL-Sortierschluessel in **keinem** Zweig `buchholz`.
  - Given eine schoch-Stage, When der Cut gebildet wird, Then `points -> buchholz -> …`.
  - Given die Migration, When eingespielt, Then additiv/abwaertskompatibel.
- **Notes:** vorrunde-spec §6; ADR-0035. Risiko: Fallback in >10 Migrationen kopiert -> Audit-Grep `e.buchholz` (siehe M2-T06). Task sprengt evtl. 100 LOC -> falls noetig nach Funktionsgruppe splitten (M2-T05a/b).

### M2-T06 — Audit-Test kein group_phase-Buchholz
- **ID:** M2-T06 · **Type:** tests · **Agent:** tester · **Size:** M · **Deps:** M2-T05
- **Goal:** Repository-Audit (Grep + Smoke-Standing) das sicherstellt, dass kein group_phase-Ranking-Pfad Buchholz enthaelt.
- **Akzeptanzkriterien:**
  - Given die finale Migration, When nach `e.buchholz` im group_phase-Zweig gegrept wird, Then 0 Treffer.
  - Given ein Smoke-Standing, When gruppenphasen-typisch berechnet, Then Reihenfolge stimmt mit Dart-Standings ueberein (Paritaet).
- **Notes:** Architektur Risiko-Tabelle Zeile 2.

### M2-T07 — Failing-Test Schoch-Shootout-tied-Key
- **ID:** M2-T07 · **Type:** tests · **Agent:** tester · **Size:** S · **Deps:** M1-T03
- **Goal:** Test, dass die Shoot-out-Erkennung im Schoch-Pfad zwei nur-punkt-gleiche Spieler erst nach Buchholz-Gleichstand als tied erkennt.
- **Akzeptanzkriterien:**
  - Given Schoch, zwei punktgleiche Spieler mit unterschiedlichem Buchholz, When Shoot-out-Gruppen erkannt, Then **kein** Shoot-out (Buchholz trennt bereits).
  - Given identischer Buchholz an der Cut-Linie, When erkannt, Then Shoot-out-Bedarf.
- **Notes:** vorrunde-spec §3, §7; Architektur §4.3.

### M2-T08 — detect_shootout_groups Schoch-Buchholz
- **ID:** M2-T08 · **Type:** data · **Agent:** coder-data · **Size:** M · **Deps:** M2-T05, M2-T07
- **Goal:** `_tournament_detect_shootout_groups` tied-Key fuer Schoch um den korrigierten Buchholz erweitern (Gruppenphase bleibt `points/wins/kubb_diff`).
- **Akzeptanzkriterien:**
  - Given Schoch, When der tied-Key gebildet wird, Then enthaelt er Buchholz; M2-T07 gruen.
  - Given Gruppenphase, When der tied-Key gebildet wird, Then unveraendert (kein Buchholz).
  - Given pending Shoot-out, When `tournament_start_ko_phase`, Then blockiert mit `P0001` (kein stiller ID-Fallback).
- **Notes:** Architektur §4.3.

### M2-T09 — Gate kosmetischer Gleichstand
- **ID:** M2-T09 · **Type:** tests · **Agent:** tester · **Size:** S · **Deps:** M2-T08
- **Goal:** Test, dass Gleichstaende ohne Auf-/Abstiegswirkung keinen Shoot-out ausloesen.
- **Akzeptanzkriterien:**
  - Given zwei sicher qualifizierte oder sicher ausgeschiedene Tied-Spieler, When erkannt, Then kein Shoot-out (straddle-cut greift nicht).
- **Notes:** vorrunde-spec §3, §7.3.

---

# M3 — Stage-Seeding (B4, Domain + UI + SQL)

Neue Quelle `random` mit persistiertem Seed, Optionslisten-Gating, Snake-only-Pool,
Engine-Seed-Resolver. Teils parallel zu M2; der `fromPrevRanking`-Resolver (M3-T11)
braucht M2. Braucht M1 (Seed -> stabile Schoch-Startnummer).

| Task | Type | Agent | Size | Files | Deps | Goal |
|---|---|---|---|---|---|---|
| M3-T01 | tests | tester | S | `.../test/tournament/seeding_test.dart` | M1-T01 | Failing-Test: `seedRandom(ids, seed)` deterministisch (Fisher-Yates) |
| M3-T02 | domain | coder-backend | S | `.../lib/src/tournament/seeding.dart` | M3-T01 | Pure `seedRandom(ids, seed)` aus `pool_phase._shuffle` heben |
| M3-T03 | tests | tester | S | `.../test/tournament/stage_graph/stage_node_test.dart` | — | Failing-Test: `StageSeedingSource.random` round-trips Wire `random` |
| M3-T04 | domain | coder-backend | S | `.../stage_graph/stage_node.dart` | M3-T03 | `random('random')` zu `StageSeedingSource` ergaenzen |
| M3-T05 | frontend | coder-frontend | S | `.../presentation/...` (stageSeedingSourceLabel-Stellen), `lib/l10n/app_de.arb` | M3-T04 | `random`-Case in exhaustiven Switches + ARB-Key ergaenzen |
| M3-T06 | tests | tester | S | `.../test/tournament/stage_graph/stage_validation_test.dart` | M3-T04 | Failing-Test: `seedingSourcesFor(type, isRoot)` Gating |
| M3-T07 | frontend | coder-frontend | M | `.../application/...` Gate-Helper, `stage_validation.dart`-Reuse (V5) | M3-T06 | `seedingSourcesFor(stageType, isRoot)` Helper |
| M3-T08 | frontend | coder-frontend | M | `stage_graph_builder_screen.dart`, `stage_graph_canvas.dart` | M3-T07 | Seeding-Dropdown in beiden Editoren auf Gate-Helper umstellen |
| M3-T09 | frontend | coder-frontend | M | `pool_phase.dart`, `tournament_config_draft.dart`, `stage_node_config.dart` | M3-T02 | Pool-Verteilung UI = nur Snake; `random/seeded` lesbar mit Fallback->snake; Draft-Default snake |
| M3-T10 | data | coder-data | S | `supabase/migrations/2026….._seeding_check_widen_random.sql` | M3-T04 | CHECK-Constraint `seeding` additiv um `random` weiten |
| M3-T11 | data | coder-data | L | `supabase/migrations/2026….._stage_seed_resolver.sql` | M3-T10, M2-T05 | Per-Stufe Seed-Resolver in Boot + Runner (`node.seeding` auswerten) |
| M3-T12 | tests | tester | M | `.../test/tournament/seeding_parity_test.dart` | M3-T11, M3-T02 | Paritaets-Test: plpgsql-random == Dart-`seedRandom` fuer denselben Seed |

### M3-T01 — Failing-Test seedRandom
- **ID:** M3-T01 · **Type:** tests · **Agent:** tester · **Size:** S · **Deps:** M1-T01
- **Goal:** Test fuer pure `seedRandom(ids, seed)` (deterministisches Fisher-Yates).
- **Akzeptanzkriterien:**
  - Given gleiche `(ids, seed)`, When zweimal aufgerufen, Then identische Reihenfolge.
  - Given verschiedene Seeds, When aufgerufen, Then i.d.R. verschiedene Reihenfolge.
- **Notes:** seeding-spec §2 Determinismus, §7.3.

### M3-T02 — seedRandom heben
- **ID:** M3-T02 · **Type:** domain · **Agent:** coder-backend · **Size:** S · **Deps:** M3-T01
- **Goal:** Fisher-Yates aus `pool_phase._shuffle` als pure `seedRandom(ids, seed)` nach `seeding.dart` extrahieren; `pool_phase` ruft die gehobene Funktion.
- **Akzeptanzkriterien:**
  - Given M3-T01, When extrahiert, Then gruen; `pool_phase` nutzt dieselbe Funktion (kein Duplikat).
  - Given bestehende `pool_phase`-Tests, When ausgefuehrt, Then weiterhin gruen.
- **Notes:** seeding-spec §2; Architektur §5.2. plpgsql-portabel halten (Parity M3-T12).

### M3-T03 — Failing-Test StageSeedingSource.random
- **ID:** M3-T03 · **Type:** tests · **Agent:** tester · **Size:** S · **Deps:** —
- **Goal:** Test, dass `StageSeedingSource.random` von/zu Wire `'random'` round-trippt.
- **Akzeptanzkriterien:**
  - Given Wire `'random'`, When `fromWire`, Then `StageSeedingSource.random`; `toWire()` == `'random'`.
- **Notes:** seeding-spec §6.1.

### M3-T04 — StageSeedingSource.random ergaenzen
- **ID:** M3-T04 · **Type:** domain · **Agent:** coder-backend · **Size:** S · **Deps:** M3-T03
- **Goal:** Enum-Wert `random('random')` ergaenzen.
- **Akzeptanzkriterien:**
  - Given M3-T03, When ergaenzt, Then gruen.
  - Given exhaustive Switches, When kompiliert, Then erzwingt der Linter den `random`-Case (gewollt).
- **Notes:** seeding-spec §2, §6; ADR-0038.

### M3-T05 — random-Case in Switches + ARB
- **ID:** M3-T05 · **Type:** frontend · **Agent:** coder-frontend · **Size:** S · **Deps:** M3-T04
- **Goal:** `stageSeedingSourceLabel` und weitere exhaustive Switches um `random` ergaenzen + deutschen ARB-Key "Zufall".
- **Akzeptanzkriterien:**
  - Given die UI, When eine Seeding-Quelle gerendert wird, Then zeigt `random` das Label "Zufall".
  - Given `flutter analyze`, When ausgefuehrt, Then keine non-exhaustive-switch-Fehler mehr.
- **Notes:** seeding-spec §2; Architektur §5.2.

### M3-T06 — Failing-Test seedingSourcesFor
- **ID:** M3-T06 · **Type:** tests · **Agent:** tester · **Size:** S · **Deps:** M3-T04
- **Goal:** Test des Gate-Helpers.
- **Akzeptanzkriterien:**
  - Given Vorrunde/Root (keine eingehende Kante), When `seedingSourcesFor`, Then {ELO, Zufall, Manuell} — **kein** `from_prev_ranking`.
  - Given KO/Folge-Stufe (eingehende Kante), When aufgerufen, Then {aus Vorrunde, ELO, Zufall, Manuell}.
- **Notes:** seeding-spec §1, §7.1, §7.2.

### M3-T07 — seedingSourcesFor-Helper
- **ID:** M3-T07 · **Type:** frontend · **Agent:** coder-frontend · **Size:** M · **Deps:** M3-T06
- **Goal:** Gate-Helper `seedingSourcesFor(stageType, isRoot)`, Root/Folge-Erkennung via `stage_validation.dart` (V5) wiederverwenden.
- **Akzeptanzkriterien:**
  - Given M3-T06, When implementiert, Then gruen.
  - Given die Validierung, When eine ungueltige Quelle dennoch gesetzt wird, Then bleibt V5 als Sicherheitsnetz aktiv.
- **Notes:** seeding-spec §1, §6.3; Architektur §5.3. Muster `selectableStageNodeTypes`.

### M3-T08 — Dropdown-Gating in beiden Editoren
- **ID:** M3-T08 · **Type:** frontend · **Agent:** coder-frontend · **Size:** M · **Deps:** M3-T07
- **Goal:** Seeding-Dropdown in Form-Editor und Canvas auf den Gate-Helper umstellen.
- **Akzeptanzkriterien:**
  - Given eine Vorrunde-Stufe in beiden Editoren, When das Dropdown geoeffnet wird, Then exakt {ELO, Zufall, Manuell}.
  - Given eine KO-Stufe, When geoeffnet, Then {aus Vorrunde, ELO, Zufall, Manuell}.
  - Given Manuell, When bei Gruppenphase/Schoch/KO gewaehlt, Then editier- und speicherbar.
- **Notes:** seeding-spec §1, §7.1, §7.2, §7.4.

### M3-T09 — Pool-Verteilung auf Snake reduzieren
- **ID:** M3-T09 · **Type:** frontend · **Agent:** coder-frontend · **Size:** M · **Deps:** M3-T02
- **Goal:** UI bietet nur Snake; `random/seeded` bleiben als gespeicherte Werte lesbar (Reader-Fallback -> snake); Draft-Default auf snake.
- **Akzeptanzkriterien:**
  - Given die Gruppenphase-Config, When der Verteilungs-Schalter gerendert wird, Then nur noch Snake auswaehlbar (kein zweiter Random-Schalter).
  - Given ein alter Draft mit `seeded/random`, When gelesen, Then Fallback -> snake (kein Crash).
  - Given Zufall-Quelle + Snake, When Gruppen gebildet, Then nachvollziehbar durchmischt.
- **Notes:** seeding-spec §3, §7.5, §7.6; ADR-0038. Enum-Wert NICHT hart loeschen (Blast-Radius).

### M3-T10 — CHECK-Constraint additiv weiten
- **ID:** M3-T10 · **Type:** data · **Agent:** coder-data · **Size:** S · **Deps:** M3-T04
- **Goal:** Migration, die die `seeding`-CHECK-Constraint additiv um `'random'` erweitert (Muster `20261293000000`).
- **Akzeptanzkriterien:**
  - Given die neue Constraint, When eine Stage mit `seeding='random'` geschrieben wird, Then akzeptiert; alte Werte weiterhin gueltig.
  - Given alte App-Version, When sie schreibt, Then keine Ablehnung (deploy-safe).
- **Notes:** seeding-spec §6; ADR-0038; `db push`-Reihenfolge Schritt 2.

### M3-T11 — Per-Stufe Seed-Resolver (Boot + Runner)
- **ID:** M3-T11 · **Type:** data · **Agent:** coder-data · **Size:** L · **Deps:** M3-T10, M2-T05
- **Goal:** In `tournament_start_stage_graph` und `tournament_stage_runner` eine Seed-Resolution einziehen, die `node.seeding` auswertet: `from_elo`->autoseed (REUSE), `random`->Fisher-Yates(persist. Seed), `manual`->Liste, `from_prev_ranking`->Vorrunden-Schlussrangliste (M2 `chainForStageType`).
- **Akzeptanzkriterien:**
  - Given eine Stufe mit `seeding='random'`, When sie startet, Then wird der Seed einmal gezogen und persistiert; Vorschau == gespielte Liste.
  - Given `from_prev_ranking`, When aufgeloest, Then nutzt es die per-Typ-Rangliste aus M2.
  - Given Boot heute (`node.seeding` ignoriert), When der Resolver greift, Then richtet sich die Setzliste nach `node.seeding` statt nur nach turnier-weiter `seed`-Spalte.
- **Notes:** seeding-spec §6.5; Architektur §5.5; Owner CP-2 (pro-Stufe). Sprengt evtl. 100 LOC -> splitten je Quelle (M3-T11a..d) falls noetig.

### M3-T12 — Paritaets-Test random Dart vs. plpgsql
- **ID:** M3-T12 · **Type:** tests · **Agent:** tester · **Size:** M · **Deps:** M3-T11, M3-T02
- **Goal:** Test/Fixture, das plpgsql-Random gegen `seedRandom` fuer denselben Seed spiegelt.
- **Akzeptanzkriterien:**
  - Given gleicher Seed + ids, When plpgsql und Dart shufflen, Then identische Reihenfolge.
- **Notes:** seeding-spec §7.3; Architektur Risiko-Tabelle "Dart-Random != plpgsql-Random".

---

# M4 — Stage-Graph / Typ-Graph Ebene 2 (B3, Domain + Server + UI)

Der grosse Brocken. Braucht M1 (Schoch-Paarung), M2 (per-Typ-Rangfolge), M3 (Seeding-Quellen).
Etappenfolge der Spec: Datenmodell -> Editor -> Templates -> Engine -> Summary.
Materializer fein gesplittet (Runden / Sieger-Advance / Verlierer-Route / R2+-Scheduling).

| Task | Type | Agent | Size | Files | Deps | Goal |
|---|---|---|---|---|---|---|

| M4-T01 | tests | tester | M | `.../test/tournament/stage_graph/stage_type_graph_test.dart` | M3-T04 | Failing-Test: `TypeRound/TypeField/FieldEdge` toJson/fromJson round-trip |
| M4-T02 | domain | coder-backend | L | `.../stage_graph/stage_type_graph.dart` | M4-T01 | Pure Domain-Struktur Runde/Feld/Edge (Vorbild stage_graph), jsonb-serialisierbar |
| M4-T03 | tests | tester | S | `.../test/tournament/stage_graph/stage_type_graph_gen_test.dart` | M4-T02 | Failing-Test: `generateRound1(category, count)` -> F1..F(n/2) |
| M4-T04 | domain | coder-backend | S | `.../stage_graph/stage_type_graph.dart` | M4-T03 | `generateRound1(category, count)` |
| M4-T05 | tests | tester | M | `.../test/tournament/stage_graph/stage_type_validation_test.dart` | M4-T02 | Failing-Test: KO fallend/letzte=1, Vorrunde konstant, offen=Warnung, Kapazitaet x2 |
| M4-T06 | domain | coder-backend | L | `.../stage_graph/stage_type_validation.dart` | M4-T05 | Typ-Graph-Validierung (Vorbild validateStageGraph V1-V7) |
| M4-T07 | frontend | coder-frontend | M | `.../application/type_graph_builder_controller.dart` | M4-T02, M4-T06 | Ein Provider/Controller (Vorbild stage_graph_builder_controller), Live-Revalidierung |
| M4-T08 | frontend | coder-frontend | L | `.../presentation/type_graph_builder_screen.dart` | M4-T07 | Handy-Form-Editor Runden/Felder/Edges (Vorbild builder_screen) |
| M4-T09 | frontend | coder-frontend | L | `.../presentation/type_graph_canvas.dart` | M4-T07 | Desktop-Canvas Port->Port fuer Felder (Vorbild stage_graph_canvas) |
| M4-T10 | tests | tester | M | `.../test/.../type_graph_parity_test.dart` | M4-T08, M4-T09 | Paritaets-Test: Handy- und Canvas-Modell identisch serialisiert |
| M4-T11 | data | coder-data | L | `supabase/migrations/2026….._stage_type_templates.sql` | M4-T02 | Stufen-Typ-Template-Tabelle + save/apply RPC + RLS (Vorbild 20261230) |
| M4-T12 | frontend | coder-frontend | M | `.../data/stage_type_templates_repository.dart`, Setup-Auswahl | M4-T11 | Repo + Template-Auswahl im Setup (privat/oeffentlich) |
| M4-T13 | tests | tester | M | `.../test/.../stage_type_materialize_round_test.dart` | M4-T02 | Failing-Test: Felder als Matches aus Runde |
| M4-T14 | data | coder-data | L | `supabase/migrations/2026….._stage_type_materialize_round.sql` | M4-T13, M3-T11 | Generischer Materializer: Felder einer Runde -> Matches (Vorbild generate_stage_matches) |
| M4-T15 | data | coder-data | M | `supabase/migrations/2026….._stage_type_advance_winner.sql` | M4-T14 | Sieger-Advance entlang Sieger-Feld-Edges (REUSE advance_ko_winner) |
| M4-T16 | data | coder-data | M | `supabase/migrations/2026….._stage_type_route_loser.sql` | M4-T14 | Verlierer-Route entlang Verlierer-Feld-Edges / offen (REUSE route_completed_stage) |
| M4-T17 | data | coder-data | M | `supabase/migrations/2026….._stage_ko_round2plus_schedule.sql` | M4-T15 | Stage-KO-Runden 2+ Scheduling (`ko_round_formats[r]`) |
| M4-T18 | data | coder-data | M | `supabase/migrations/2026….._ko_tiebreak_server_authoritative.sql` | M4-T15 | `ko_tiebreak_method` server-autoritativ pro Feld durchsetzen |
| M4-T19 | tests | tester | M | `.../test/integration/stage_type_engine_test.dart` (Fake/Integration) | M4-T15, M4-T16, M4-T17, M4-T18 | Gate 9.7: custom Typ erzeugt Matches, Sieger/Verlierer laufen entlang Edges |
| M4-T20 | frontend | coder-frontend | M | `.../presentation/...summary...` | M4-T02 | Summary um Runden/Felder-Detail + Config erweitern (H2) |
| M4-T21 | tests | tester | S | `.../test/.../summary_completeness_test.dart` | M4-T20 | Gate 9.8: Summary zeigt alle Stufen/Runden/Felder/Config |

### M4-T01 — Failing-Test Typ-Graph-Serialisierung
- **ID:** M4-T01 · **Type:** tests · **Agent:** tester · **Size:** M · **Deps:** M3-T04
- **Goal:** Round-trip-Test fuer `TypeRound/TypeField/FieldEdge` (immutable, wire-stabil).
- **Akzeptanzkriterien:**
  - Given ein Typ-Graph, When `toJson` dann `fromJson`, Then strukturell identisch.
  - Given ein `FieldEdge` mit `kind`-Diskriminator (sieger/verlierer/offen), When serialisiert, Then stabiler Wire-String.
- **Notes:** stage-spec §3; ADR-0037. Vorbild `stage_edge.dart`/`edge_selector.dart`.

### M4-T02 — Typ-Graph-Domain-Struktur
- **ID:** M4-T02 · **Type:** domain · **Agent:** coder-backend · **Size:** L · **Deps:** M4-T01
- **Goal:** `stage_type_graph.dart` mit `TypeRound`, `TypeField`, `FieldEdge` (sealed, `kind`), als jsonb-Sub-Graph in `StageNode.config`.
- **Akzeptanzkriterien:**
  - Given M4-T01, When implementiert, Then gruen; Struktur immutable.
  - Given `StageNode.config`, When der Sub-Graph serialisiert wird, Then teilnehmer-agnostisch (keine konkreten Spieler).
- **Notes:** ADR-0037; stage-spec §3, §10.1. Vorbild stage_graph 1:1.

### M4-T03 — Failing-Test generateRound1
- **ID:** M4-T03 · **Type:** tests · **Agent:** tester · **Size:** S · **Deps:** M4-T02
- **Akzeptanzkriterien:**
  - Given Kategorie KO + 16, When `generateRound1`, Then F1..F8.
  - Given Kategorie Vorrunde + n, When generiert, Then passende Felderzahl konstant fuer Folgerunden.
- **Notes:** stage-spec §3.3, §9.1.

### M4-T04 — generateRound1
- **ID:** M4-T04 · **Type:** domain · **Agent:** coder-backend · **Size:** S · **Deps:** M4-T03
- **Akzeptanzkriterien:** Given M4-T03, When implementiert, Then gruen; Felder beschriftet F1..F(n/2).
- **Notes:** stage-spec §3.3.

### M4-T05 — Failing-Test Typ-Graph-Validierung
- **ID:** M4-T05 · **Type:** tests · **Agent:** tester · **Size:** M · **Deps:** M4-T02
- **Akzeptanzkriterien:**
  - Given KO mit Runde2 >= Runde1 Felder, When validiert, Then Error (§9.3).
  - Given Vorrunde mit abnehmender Zahl, When validiert, Then Error (§9.4).
  - Given offene Sieger-Edge, When validiert, Then Warnung, kein Error (§9.2); letzte KO-Runde = 1 Feld.
  - Given KO-Runde, When Kapazitaet geprueft, Then eingehend = Felder x 2.
- **Notes:** stage-spec §7, §9.2-9.4.

### M4-T06 — Typ-Graph-Validierung
- **ID:** M4-T06 · **Type:** domain · **Agent:** coder-backend · **Size:** L · **Deps:** M4-T05
- **Goal:** `stage_type_validation.dart`: fallend/konstant/offen/Kapazitaet, azyklisch (Kahn REUSE), `hasErrors` blockiert Speichern; `ValidationSeverity` REUSE.
- **Akzeptanzkriterien:** Given M4-T05, When implementiert, Then gruen; bei Errors blockiert Speichern/Veroeffentlichen.
- **Notes:** stage-spec §7; Vorbild validateStageGraph V1-V7. Owner CP-3 OFFEN-1: Vorrunde ALS Feld-Edges (ADR-0039) — AdvanceAllEdge je Runde, granulare Sieger/Verlierer-Edges in der Vorrunde unzulaessig.

### M4-T07 — Typ-Graph-Controller (ein Provider)
- **ID:** M4-T07 · **Type:** frontend · **Agent:** coder-frontend · **Size:** M · **Deps:** M4-T02, M4-T06
- **Goal:** Riverpod-Controller (Vorbild `stage_graph_builder_controller`), jede Mutation re-validiert live, eine Serialisierung.
- **Akzeptanzkriterien:**
  - Given eine Feld/Edge-Mutation, When ausgefuehrt, Then State re-validiert sofort (Live).
  - Given beide spaeteren Views, When sie mutieren, Then ueber genau diesen Provider (kein divergenter State).
- **Notes:** stage-spec §5, §6.5; Editor-Paritaet.

### M4-T08 — Handy-Form-Editor
- **ID:** M4-T08 · **Type:** frontend · **Agent:** coder-frontend · **Size:** L · **Deps:** M4-T07
- **Goal:** Gefuehrter Listen-Editor fuer Runden/Felder/Edges (Vorbild builder_screen), `ko_round_block.dart` REUSE.
- **Akzeptanzkriterien:**
  - Given Owner gibt 16 ein, When generiert, Then F1-F8; er verdrahtet Sieger->Runde2 etc., setzt Saetze/Zeit/Pause/Tiebreak, speichert -> gueltiger Typ, keine Errors (§9.1).
  - Given offene Edge, When gespeichert, Then Warnung, kein Error (§9.2).
- **Notes:** stage-spec §3, §5, §9.1, §9.2.

### M4-T09 — Desktop-Canvas
- **ID:** M4-T09 · **Type:** frontend · **Agent:** coder-frontend · **Size:** L · **Deps:** M4-T07
- **Goal:** Port->Port-Canvas fuer Felder (Vorbild `stage_graph_canvas`), ab 720 dp gegated.
- **Akzeptanzkriterien:**
  - Given dieselbe Mutation wie im Handy-Editor, When per Canvas ausgefuehrt, Then identisches Modell ueber denselben Provider.
- **Notes:** stage-spec §5, §9.5.

### M4-T10 — Editor-Paritaets-Test
- **ID:** M4-T10 · **Type:** tests · **Agent:** tester · **Size:** M · **Deps:** M4-T08, M4-T09
- **Akzeptanzkriterien:**
  - Given derselbe Typ-Graph am Handy und am Desktop gebaut, When serialisiert, Then identische Form, identische Validierung (§9.5).
- **Notes:** stage-spec §9.5; Architektur Risiko "Paritaet zweiter Editor".

### M4-T11 — Stufen-Typ-Template-Tabelle + RPC + RLS
- **ID:** M4-T11 · **Type:** data · **Agent:** coder-data · **Size:** L · **Deps:** M4-T02
- **Goal:** Tabelle + save/apply RPC + RLS (Vorbild `20261230000000`), Sichtbarkeit privat (organizer_team + Setup-Recht) / oeffentlich.
- **Akzeptanzkriterien:**
  - Given ein privat gespeicherter Typ, When abgefragt, Then nur fuer Veranstalter-Team-Mitglieder mit Setup-Recht sichtbar (§9.6).
  - Given ein oeffentlicher Typ, When abgefragt, Then fuer alle sichtbar; Vorlage teilnehmer-agnostisch.
- **Notes:** stage-spec §6, §9.6. Template-Scope `organizer_teams` Mapping `private`->Team+Setup-Recht.

### M4-T12 — Template-Repo + Setup-Auswahl
- **ID:** M4-T12 · **Type:** frontend · **Agent:** coder-frontend · **Size:** M · **Deps:** M4-T11
- **Akzeptanzkriterien:**
  - Given das Setup, When der Owner eine Stufen-Typ-Vorlage waehlt, Then wird der Typ-Graph in die Stage uebernommen.
- **Notes:** stage-spec §6.

### M4-T13 — Failing-Test Runden-Materialisierung
- **ID:** M4-T13 · **Type:** tests · **Agent:** tester · **Size:** M · **Deps:** M4-T02
- **Akzeptanzkriterien:**
  - Given ein Typ-Graph mit Runde 1 Feldern, When materialisiert, Then je Feld ein Match (matchup-bewusst).
- **Notes:** stage-spec §8.1, §9.7.

### M4-T14 — Generischer Runden-Materializer
- **ID:** M4-T14 · **Type:** data · **Agent:** coder-data · **Size:** L · **Deps:** M4-T13, M3-T11
- **Goal:** `tournament_generate_stage_matches` von typ-fix (CASE ueber 7 Typen) auf einen aus dem Typ-Graphen lesenden Materializer erweitern; Felder -> Matches.
- **Akzeptanzkriterien:**
  - Given ein custom Typ-Graph, When eine Stufe startet, Then erzeugt die Engine echte Matches aus den Feldern (M4-T13 gruen).
  - Given Seeding aus M3-T11, When materialisiert, Then in der per-Quelle aufgeloesten Reihenfolge.
- **Notes:** stage-spec §8.1; Architektur §6.6 (fein gesplittet). Sprengt 100 LOC -> ggf. M4-T14a/b.

### M4-T15 — Sieger-Advance entlang Edges
- **ID:** M4-T15 · **Type:** data · **Agent:** coder-data · **Size:** M · **Deps:** M4-T14
- **Akzeptanzkriterien:**
  - Given ein abgeschlossenes Feld, When der Sieger feststeht, Then wird er entlang der Sieger-Feld-Edge ins Zielfeld geschoben (REUSE `tournament_advance_ko_winner`).
- **Notes:** stage-spec §8.1; Architektur §6.6.

### M4-T16 — Verlierer-Route entlang Edges / offen
- **ID:** M4-T16 · **Type:** data · **Agent:** coder-data · **Size:** M · **Deps:** M4-T14
- **Akzeptanzkriterien:**
  - Given ein abgeschlossenes Feld mit Verlierer-Edge, When ausgewertet, Then Verlierer entlang der Edge geroutet (REUSE `tournament_route_completed_stage`).
  - Given eine offene Verlierer-Edge, When ausgewertet, Then Verlierer scheidet/wird spaeter geroutet (kein Fehler).
- **Notes:** stage-spec §3.4, §8.1.

### M4-T17 — Stage-KO-Runden 2+ Scheduling
- **ID:** M4-T17 · **Type:** data · **Agent:** coder-data · **Size:** M · **Deps:** M4-T15
- **Akzeptanzkriterien:**
  - Given eine KO-Stage jenseits Runde 1, When Runde r gescheduled wird, Then greift `ko_round_formats[r]` (Saetze/Zeit/Pause).
- **Notes:** stage-spec §2 Luecke 5, §8.3.

### M4-T18 — ko_tiebreak_method server-autoritativ
- **ID:** M4-T18 · **Type:** data · **Agent:** coder-data · **Size:** M · **Deps:** M4-T15
- **Goal:** `ko_tiebreak_method` pro Feld serverseitig durchsetzen (heute nur am Match-Detail konsumiert).
- **Akzeptanzkriterien:**
  - Given ein tied KO-Feld, When entschieden, Then wendet der Server Klassisch bzw. Mighty-Finisher gemaess Feld-Config an (nicht nur Anzeige).
- **Notes:** stage-spec §8.2; Architektur §6.6 (gegen Ist-Code, nicht Spec-Status).

### M4-T19 — Engine-Integrationstest custom Typ
- **ID:** M4-T19 · **Type:** tests · **Agent:** tester · **Size:** M · **Deps:** M4-T15, M4-T16, M4-T17, M4-T18
- **Akzeptanzkriterien:**
  - Given ein selbst modellierter Typ, When das Turnier startet, Then echte Matches; Sieger/Verlierer laufen entlang der modellierten Edges; KO-Tiebreak-Methode greift (§9.7).
  - Given die Materialisierung 73 Teilnehmer, When gemessen, Then < 200 ms serverseitig (Scale-Budget §11).
- **Notes:** stage-spec §9.7; Architektur §11.

### M4-T20 — Summary um Runden/Felder erweitern
- **ID:** M4-T20 · **Type:** frontend · **Agent:** coder-frontend · **Size:** M · **Deps:** M4-T02
- **Akzeptanzkriterien:**
  - Given ein Typ-Graph, When die Summary rendert, Then zeigt sie Stufen, Runden, Felder und deren Config (kein stilles Weglassen, H2).
- **Notes:** stage-spec §2 Luecke 6, §8.4, §9.8. Summary rendert Stage-Config bereits H2-konform -> nur Runden/Felder-Ebene ergaenzen.

### M4-T21 — Summary-Vollstaendigkeits-Test
- **ID:** M4-T21 · **Type:** tests · **Agent:** tester · **Size:** S · **Deps:** M4-T20
- **Akzeptanzkriterien:**
  - Given ein vollstaendiger Typ-Graph, When die Summary geprueft wird, Then erscheinen alle Stufen/Runden/Felder/Config (§9.8).
- **Notes:** stage-spec §9.8.

---

## Hinweise zur Ausfuehrung

- **TDD-Disziplin:** Jeder Domain-/Engine-Fix hat seinen Test-Task als Dependency davor
  (rot -> gruen). Reine UI-Gating-Tasks haben einen Helper-Test als Dependency.
- **`db push`-Reihenfolge (additiv):** M1-T11 + M2 (T05/T08) zuerst, dann M3 (T10/T11),
  dann M4 (T11/T14-T18). Owner spielt jede Migration per `supabase db push` ein.
- **LOC-Sprenger:** M2-T05, M3-T11, M4-T14 sind als L markiert und koennen das
  100-LOC-Limit reissen; sie werden bei Bedarf nach Funktionsgruppe/Quelle/Phase
  in `<id>a/b`-Unter-Tasks gesplittet (Hinweis in den jeweiligen Notes).
- **Conventional-Commit-Scopes:** `tournament`, `pairing`, `match`, `stage` — Task-ID
  in der Commit-Message (senior).
