# M2 — Atomare Task-Liste

> Stand: 2026-05-26
> Bezug: `sprint-plan.md` (Waves, Sub-Milestones), `architecture.md`, `milestone-plan.md`, ADR-0016, ADR-0017
> Senior-Sizing: max 100 LOC, max 3 Files, max 1h netto pro Task

## Konvention

- IDs folgen `TASK-M2.<sub>-T<n>`. Sub ∈ {1, 2, 3}. Nummerierung ist nicht durchgehend — sie folgt der Wave-Reihenfolge aus `sprint-plan.md`.
- Wave-Nummer bezieht sich auf den Plan in `sprint-plan.md` §Wave-Plan.
- Agents: `coder-frontend` fuer Flutter-UI, `coder-data` fuer DB/Migrations/RPCs, `coder-domain` fuer `packages/kubb_domain/`, `tester` fuer Tests/Goldens/Property-Tests, `researcher` fuer Spike/Klaerung.
- TDD-Pflicht in Domain: ein Test-Task vor jedem Impl-Task. Test-Task hat tester als Agent, Impl-Task hat coder-domain.

---

# M2.1 — Pure Domain (Wave 1 bis 3)

## TASK-M2.1-T1: Property-Tests fuer `bracket.dart`

- **Type**: tests
- **Size**: M
- **Bounded Context**: tournament
- **Agent**: tester
- **Dependencies**: —
- **Wave**: 1
- **Files (anticipated)**: `packages/kubb_domain/test/tournament/bracket_test.dart`
- **LOC-Budget**: ~80

### Goal

glados-Property-Tests existieren fuer `Bracket.singleElimination`, decken Determinismus, BYE-Verteilung, Spiel-um-Platz-3-Position und `Bracket.fill`-Konsistenz ab.

### Acceptance Criteria

- Given participantIds-List mit n ∈ [2, 64] When `singleElimination(ids)` zweimal aufgerufen Then beide Brackets sind structural equal (Determinismus).
- Given n nicht Zweierpotenz When `singleElimination(ids)` Then `next_pow2(n) − n` BYE-Slots existieren, alle in Round-1 und ausschliesslich gegen Seeds 1..(size-n) (FR-FMT-11).
- Given `singleElimination(8 ids, withThirdPlace=true)` When Bracket erzeugt Then existiert eine zusaetzliche `BracketRound` (oder ein zusaetzliches Match) mit `phase = thirdPlace` und exakt einer Pairing.
- Given Halbfinale-1-Sieger A und Halbfinale-2-Sieger B When `Bracket.fill(round=2, position=1, A)` plus `Bracket.fill(round=2, position=2, B)` Then Final-Pairing enthaelt `[A, B]`, Third-Place-Pairing enthaelt beide Halbfinal-Verlierer.

### Notes

- Definiert Contract fuer TASK-M2.1-T5. Test-Task schreibt die erwartete API der `Bracket.fill`-Funktion, des `BracketPhase`-Enums und der `withThirdPlace`-Semantik vor.
- Property-Test-Generator: `any.listOfNonEmptyParticipantIds(2..64)` als glados `Any<List<String>>`.
- Bezug OD-M2-04 (Hybrid via `league_eligible`): Test deckt beide Varianten (`withThirdPlace = true` und `= false`) ab.
- Bezug OD-M2-05: Test ueber n ∈ [2, 64] inklusive Nicht-Zweierpotenzen.

---

## TASK-M2.1-T2: Property-Tests fuer `seeding.dart`

- **Type**: tests
- **Size**: S
- **Bounded Context**: tournament
- **Agent**: tester
- **Dependencies**: —
- **Wave**: 1
- **Files (anticipated)**: `packages/kubb_domain/test/tournament/seeding_test.dart`
- **LOC-Budget**: ~60

### Goal

glados-Property-Tests fuer `seedFromStandings` und `applyManualOverride`, die Stabilitaet, Idempotenz und Determinismus abdecken.

### Acceptance Criteria

- Given `List<ParticipantStats>` mit identischen `totalPoints` und unterschiedlichen `kubbDifference` When `seedFromStandings(stats, tiebreakerChain)` zweimal aufgerufen Then identische Reihenfolge.
- Given `seedFromStandings`-Output When `applyManualOverride(seeded, {})` Then identische Reihenfolge (Idempotenz-Edge-Case leer).
- Given Override-Map mit nicht-existierender `seed_position` When `applyManualOverride` Then `ArgumentError` oder dokumentierte Skip-Semantik (Test fixiert das Verhalten).

### Notes

- Definiert Contract fuer TASK-M2.1-T6.
- Bezug Architektur §3.1: Signaturen `List<String> seedFromStandings(List<ParticipantStats>, TiebreakerChain)` und `List<String> applyManualOverride(List<String> autoSeeded, Map<int, String> overrides)`.

---

## TASK-M2.1-T3: Property-Tests fuer `ko_phase.dart` `KoPhaseConfig`

- **Type**: tests
- **Size**: S
- **Bounded Context**: tournament
- **Agent**: tester
- **Dependencies**: —
- **Wave**: 1
- **Files (anticipated)**: `packages/kubb_domain/test/tournament/ko_phase_test.dart`
- **LOC-Budget**: ~50

### Goal

Property-Tests fuer Validierung von `KoPhaseConfig` — Qualifier-Range, Default-Werte, `withThirdPlacePlayoff`-Flag.

### Acceptance Criteria

- Given `qualifierCount = 1` When `KoPhaseConfig(qualifierCount: 1, ...)` Then `ArgumentError` (`qualifierCount >= 2`).
- Given `qualifierCount > participantCount` When Konstruktor Then `ArgumentError`.
- Given valid `qualifierCount ∈ [2, participantCount]` When Konstruktor Then `KoPhaseConfig`-Instanz mit Default `withThirdPlacePlayoff = false` und `seedingMode = SeedingMode.auto`.
- Given `KoPhaseConfig` zwei Instanzen mit denselben Werten Then `==` ist `true` und `hashCode` ist gleich.

### Notes

- Definiert Contract fuer TASK-M2.1-T7.
- Bezug OD-M2-05: kein 2^n-Constraint; freier Integer-Input. Bezug Domain-Notiz `qualifier-count.md` U10: kein zusaetzliches Flag noetig.

---

## TASK-M2.1-T4: Property-Tests fuer `bracket_layout.dart`

- **Type**: tests
- **Size**: M
- **Bounded Context**: tournament
- **Agent**: tester
- **Dependencies**: —
- **Wave**: 1
- **Files (anticipated)**: `packages/kubb_domain/test/tournament/bracket_layout_test.dart`
- **LOC-Budget**: ~90

### Goal

glados-Property-Tests fuer die Pure-Function `BracketLayout`, die spaeter vom CustomPainter konsumiert wird.

### Acceptance Criteria

- Given `Bracket` mit n ∈ [2, 64] When `BracketLayout.compute(bracket)` Then jede Match-Box hat einen `BoxRect` mit `width > 0`, `height >= touchMin (48)`.
- Given zwei verschiedene Match-Boxen When Layout berechnet Then ihre `BoxRect` ueberlappen nicht (no collision).
- Given Bracket mit `withThirdPlace = true` When Layout berechnet Then Third-Place-Box hat eigene Side-Branch-Spalte rechts vom Finale (x > final.x).
- Given Bracket mit BYE-Slots When Layout berechnet Then jeder BYE-Slot hat `BracketEntry.isBye == true` und ist im Layout-Output markiert.

### Notes

- Definiert Contract fuer TASK-M2.1-T8.
- Bezug ADR-0016: eigene Records `BoxRect`/`Point`, kein Flutter-Import.
- Property: Layout muss deterministisch sein (zweimal aufgerufen → identische `Map<MatchId, BoxRect>`).

---

## TASK-M2.1-T5: `bracket.dart` ausbauen — `withThirdPlace`, `BracketPhase`, `Bracket.fill`

- **Type**: domain
- **Size**: M
- **Bounded Context**: tournament
- **Agent**: coder-domain
- **Dependencies**: TASK-M2.1-T1
- **Wave**: 2
- **Files (anticipated)**: `packages/kubb_domain/lib/src/tournament/bracket.dart`
- **LOC-Budget**: ~90

### Goal

Das `// ignore: avoid_unused_constructor_parameters` aus `bracket.dart:41` ist weg, `withThirdPlace` ist aktiv verdrahtet, `BracketPhase`-Enum existiert, `Bracket.fill(round, position, participantId)` ist pure und deterministisch.

### Acceptance Criteria

- Given `singleElimination(ids, withThirdPlace: true)` When Bracket erzeugt Then Bracket enthaelt ein Third-Place-Match (separate Round oder per `BracketPhase.thirdPlace` markiert).
- Given `Bracket.fill(round, position, participantId)` auf einem Bracket mit leerem Slot Then Bracket-Returnwert hat den Slot belegt, alle anderen Slots unveraendert.
- Given `BracketPhase`-Enum mit Werten `{winners, thirdPlace, final_}` Then `BracketRound` traegt das Feld `phase`.
- Tests aus TASK-M2.1-T1 gruen.

### Notes

- Bezug ADR-0017 §4: Third-Place ist nicht "Runde N+1", sondern eigene Phase parallel zum Finale.
- Existierende M0-Tests in `bracket_test.dart` muessen ggf. angepasst werden (siehe R-M2.1-1 in `risks-and-deferrals.md`).
- Contract fuer TASK-M2.1-T9 (bracketFromMatches): die `BracketPhase` muss konsumierbar sein.

---

## TASK-M2.1-T6: `seeding.dart` — `seedFromStandings` + `applyManualOverride`

- **Type**: domain
- **Size**: S
- **Bounded Context**: tournament
- **Agent**: coder-domain
- **Dependencies**: TASK-M2.1-T2
- **Wave**: 2
- **Files (anticipated)**: `packages/kubb_domain/lib/src/tournament/seeding.dart`, `packages/kubb_domain/lib/kubb_domain.dart` (Export)
- **LOC-Budget**: ~70

### Goal

Neue Pure-Function-Datei `seeding.dart` mit den zwei Funktionen. Library-Export erweitert.

### Acceptance Criteria

- Given `List<ParticipantStats>` und `TiebreakerChain` When `seedFromStandings(stats, chain)` Then `List<String>` mit `participantIds` in absteigender Reihenfolge (best zuerst).
- Given seeded `List<String>` und `Map<int, String>` mit gueltigen `seed_position → participantId` When `applyManualOverride` Then neue Liste mit Tausch-Operation angewendet.
- Tests aus TASK-M2.1-T2 gruen.

### Notes

- Bezug Architektur §3.1.
- Funktionen sind pure: kein Side-Effect, kein Throw bei Default-Pfad. Override mit ungueltigem Seed wirft `ArgumentError`.

---

## TASK-M2.1-T7: `ko_phase.dart` — `KoPhaseConfig`-Wertobjekt

- **Type**: domain
- **Size**: S
- **Bounded Context**: tournament
- **Agent**: coder-domain
- **Dependencies**: TASK-M2.1-T3
- **Wave**: 2
- **Files (anticipated)**: `packages/kubb_domain/lib/src/tournament/ko_phase.dart`, `packages/kubb_domain/lib/kubb_domain.dart` (Export)
- **LOC-Budget**: ~60

### Goal

Neue Wertobjekt-Datei `ko_phase.dart` mit `KoPhaseConfig` (Felder: `qualifierCount`, `withThirdPlacePlayoff`, `seedingMode`) plus `SeedingMode`-Enum.

### Acceptance Criteria

- Given `KoPhaseConfig.validate(qualifierCount: 4, participantCount: 8)` Then kein Throw.
- Given `qualifierCount = 1` Then `ArgumentError` mit Message-Hint auf U2.
- Given `KoPhaseConfig` zweimal Then `==`/`hashCode` korrekt (immutable + freezed-aequivalent via `@immutable`).
- Tests aus TASK-M2.1-T3 gruen.

### Notes

- Bezug OD-M2-05 Resolution: freier Integer-Input, kein 2^n-Constraint.
- Bezug Domain-Notiz `qualifier-count.md`: U10 (kein zusaetzliches Flag).
- Bezug OD-M2-04: `withThirdPlacePlayoff` Default `false` (Code-Default per Architektur §3.1 / ADR-0017 §4).

---

## TASK-M2.1-T8: `bracket_layout.dart` — Pure-Function Layout

- **Type**: domain
- **Size**: M
- **Bounded Context**: tournament
- **Agent**: coder-domain
- **Dependencies**: TASK-M2.1-T4
- **Wave**: 2
- **Files (anticipated)**: `packages/kubb_domain/lib/src/tournament/bracket_layout.dart`, `packages/kubb_domain/lib/kubb_domain.dart` (Export)
- **LOC-Budget**: ~100

### Goal

Pure-Function `BracketLayout.compute(Bracket bracket, {LayoutParams params})` produziert `Map<MatchKey, BoxRect>` plus Connector-Liste. Eigene Records `BoxRect`/`Point` ohne Flutter-Dep.

### Acceptance Criteria

- Given `Bracket` mit 8 Teilnehmern Then Layout liefert 7 Match-Boxen (3 Runden) plus optionalem Third-Place-Box.
- Given Layout-Params mit `minBoxHeight=48` Then alle Boxen haben `height >= 48`.
- Given zwei verschiedene Boxen Then keine Ueberlappung (no collision).
- Tests aus TASK-M2.1-T4 gruen.

### Notes

- Bezug ADR-0016 Implementation Notes: eigene Records `BoxRect`/`Point` statt `Rect`/`Offset`.
- Contract fuer TASK-M2.3-T7 (BracketConnectorPainter): Connector-Liste hat `from: Point, to: Point`, Painter konsumiert das 1:1.
- Wird via `golden_toolkit` in TASK-M2.3-T9 visuell verifiziert.

---

## TASK-M2.1-T9: `bracketFromMatches`-Helper in `bracket.dart`

- **Type**: domain
- **Size**: S
- **Bounded Context**: tournament
- **Agent**: coder-domain
- **Dependencies**: TASK-M2.1-T5
- **Wave**: 3
- **Files (anticipated)**: `packages/kubb_domain/lib/src/tournament/bracket.dart`, `packages/kubb_domain/test/tournament/bracket_from_matches_test.dart`
- **LOC-Budget**: ~80

### Goal

Pure Mapper-Function `Bracket bracketFromMatches(List<TournamentMatchRef> matches)` plus Tests. Maps DB-Match-Rows (mit `phase`, `bracketPosition`, `winnerParticipantId`) auf eine `Bracket`-Struktur.

### Acceptance Criteria

- Given Liste von 7 KO-Match-Refs (2 Halbfinale + 1 Finale + 2 ... wait, fuer 4 Teams: 2 Halbfinale + 1 Finale = 3; fuer 8 Teams = 7) Then resultierender `Bracket` hat korrekte Round-Anzahl und gefuellte/leere Slots gemaess Match-Status.
- Given Match mit `winner_participant != null` und Folge-Match-Slot leer When `bracketFromMatches` Then Folge-Slot bleibt leer (Mapper ist passiv, kein Auto-Fill — der Trigger macht das serverseitig).
- Given Liste mit `phase = thirdPlace` Then Bracket hat Third-Place-Match korrekt zugeordnet.

### Notes

- Bezug Architektur §3.3: `tournament_bracket_provider` ruft `bracketFromMatches` nach `listMatchesForTournament`.
- Contract fuer TASK-M2.3-T4 (bracket_provider): Funktion ist sync, pure, kein I/O.
- Modifiziert `bracket.dart` — Datei wird im selben Sub-Milestone von T5 und T9 geaendert; Wave-Ordnung erzwingt Sequenz.

---

## TASK-M2.1-T10: Tiebreaker-Determinismus Rang 3 vs. 4

- **Type**: domain
- **Size**: S
- **Bounded Context**: tournament
- **Agent**: coder-domain
- **Dependencies**: —
- **Wave**: 3
- **Files (anticipated)**: `packages/kubb_domain/lib/src/tournament/tiebreaker.dart`, `packages/kubb_domain/test/tournament/tiebreaker_rank34_test.dart`
- **LOC-Budget**: ~50

### Goal

Wenn `withThirdPlace = false`, ist die Tiebreaker-Chain fuer Rang 3 vs. 4 deterministisch fixiert. glados-Test verifiziert das.

### Acceptance Criteria

- Given zwei Halbfinal-Verlierer mit identischen Vorrunden-Standings ausser `kubbDifference` When Tiebreaker Then Reihenfolge ist deterministisch und stabil ueber 100 glados-Runs.
- Given identische Standings inklusive Tiebreaker-Werte When Tiebreaker Then sekundaere stabile Ordnung (z.B. `participantId.compareTo`) garantiert Determinismus statt random.

### Notes

- Bezug ADR-0017 §4 letzter Absatz, Domain-Notiz `spiel-um-platz-3.md` Edge Cases.
- Wenn der bestehende `tiebreaker.dart`-Code bereits deterministisch ist, reicht ein zusaetzlicher Test + Doc-Kommentar — dann Task ist nur tester-Arbeit; sonst Modifikation.

---

## TASK-M2.1-T11: M2.1-Acceptance-Smoke (Domain-E2E im Test)

- **Type**: tests
- **Size**: M
- **Bounded Context**: tournament
- **Agent**: tester
- **Dependencies**: TASK-M2.1-T5, TASK-M2.1-T6, TASK-M2.1-T7
- **Wave**: 3
- **Files (anticipated)**: `packages/kubb_domain/test/tournament/m21_domain_smoke_test.dart`
- **LOC-Budget**: ~80

### Goal

Ein einzelner Smoke-Test: 8-Teilnehmer, Standings → Seeding → Bracket (mit Third-Place) → Halbfinale-Fill → Finale + Third-Place gefuellt. Alles pure Domain.

### Acceptance Criteria

- Given 8 `ParticipantStats` mit unterschiedlichen `totalPoints` When kompletter Domain-Flow durchlaufen Then Endrangliste hat Plaetze 1–4 in korrekter Reihenfolge (Final-Sieger=1, Final-Verlierer=2, Bronze-Sieger=3, Bronze-Verlierer=4).

### Notes

- Demobarkeit von M2.1 = dieser Test laeuft gruen.

---

# M2.2 — Server + RPCs (Wave 4 bis 7)

## TASK-M2.2-T0: Pre-Task — pgTAP-Verfuegbarkeit klaeren

- **Type**: research
- **Size**: S
- **Bounded Context**: core
- **Agent**: researcher
- **Dependencies**: —
- **Wave**: 4
- **Files (anticipated)**: `docs/plans/m2-ko-bracket/pgtap-feasibility.md` (Output-Notiz)
- **LOC-Budget**: 0 (research-Output ist Markdown)

### Goal

Klaeren: ist pgTAP in der lokalen Supabase-Pipeline und in CI verfuegbar? Wenn nein: Dart-Integration-Tests gegen lokale Supabase-Instanz als Fallback.

### Acceptance Criteria

- Given Supabase-Local-Setup When `pg_prove`-Aufruf versucht Then klare Antwort "ja, mit Setup X" oder "nein, Fallback Y".
- Output: kurze Doc-Notiz mit Empfehlung fuer TASK-M2.2-T6.

### Notes

- Bezug Auftrags-Constraint und ADR-0017 §7 letzter Absatz.
- Blockiert nur TASK-M2.2-T6 (Test-Strategie), nicht den Rest von M2.2.

---

## TASK-M2.2-T1a: Migration — Schema-Erweiterung (`phase`, `bracket_position`, `ko_config`, `league_eligible`)

- **Type**: data
- **Size**: M
- **Bounded Context**: tournament
- **Agent**: coder-data
- **Dependencies**: TASK-M2.1-T11 (Sub-Milestone-Gate)
- **Wave**: 4
- **Files (anticipated)**: `supabase/migrations/20260601000010_tournament_ko_phase.sql`
- **LOC-Budget**: ~70

### Goal

Migration-Datei fuegt `tournament_matches.phase`, `tournament_matches.bracket_position`, `tournaments.ko_config`, `tournaments.league_eligible` hinzu.

### Acceptance Criteria

- Given Migration angewandt When neue `tournament_matches`-Row mit Default-Werten erzeugt Then `phase = 'group'`, `bracket_position = NULL`.
- Given Migration angewandt When neue `tournaments`-Row erzeugt Then `ko_config = NULL`, `league_eligible = false`.
- Given Migration angewandt Then `CHECK (phase IN ('group','ko','third_place','final'))` aktiv.
- Bestehende M1-Rows: nach Migration `phase = 'group'` fuer alle (Default greift).

### Notes

- Bezug Architektur §3.2 Schema-Tabelle, ADR-0017 §4 (`league_eligible`).
- Contract fuer TASK-M2.3-T12 (Wizard liest `league_eligible`).
- Contract fuer TASK-M2.2-T3a/T3b/T4 (RPC und Trigger lesen `ko_config`).

---

## TASK-M2.2-T1b: Migration — Tabelle `tournament_seeding_overrides`

- **Type**: data
- **Size**: S
- **Bounded Context**: tournament
- **Agent**: coder-data
- **Dependencies**: TASK-M2.1-T11
- **Wave**: 4
- **Files (anticipated)**: `supabase/migrations/20260601000011_tournament_seeding_overrides.sql`
- **LOC-Budget**: ~50

### Goal

Neue Tabelle `tournament_seeding_overrides` mit `tournament_id`, `participant_id`, `seed_override int NOT NULL`, `set_by uuid`, `set_at timestamptz`, plus RLS-Policy.

### Acceptance Criteria

- Given Veranstalter ruft Insert Then RLS erlaubt es nur fuer `tournaments.created_by = auth.uid()`.
- Given Insert mit Foreign-Key-Verletzung Then DB lehnt ab.
- Given Doppel-Insert (gleicher participant_id im selben Turnier) Then `UNIQUE(tournament_id, participant_id)` greift.

### Notes

- Bezug Architektur §3.2 Tabelle.
- Contract fuer TASK-M2.2-T2 (`tournament_set_seeding` upsertet hier).

---

## TASK-M2.2-T2: RPC `tournament_set_seeding`

- **Type**: data
- **Size**: S
- **Bounded Context**: tournament
- **Agent**: coder-data
- **Dependencies**: TASK-M2.2-T1a, TASK-M2.2-T1b
- **Wave**: 5
- **Files (anticipated)**: `supabase/migrations/20260601000012_rpc_tournament_set_seeding.sql`
- **LOC-Budget**: ~80

### Goal

RPC `tournament_set_seeding(p_tournament_id uuid, p_seeds jsonb)` mit `SECURITY DEFINER`. Upsertet pro Teilnehmer einen Override. Schreibt Audit-Event `kind='seeding_set'`.

### Acceptance Criteria

- Given Veranstalter ruft RPC mit gueltigem `{participantId: seedNumber}`-Map When RPC Then `tournament_seeding_overrides` enthaelt alle Eintraege, Audit-Event geschrieben.
- Given Nicht-Veranstalter ruft RPC Then `403` (RLS auf `tournaments.created_by`).
- Given `p_seeds` enthaelt Teilnehmer-IDs die nicht im Turnier sind Then `422 INVALID_PARTICIPANT`.

### Notes

- Bezug Architektur §3.2, OD-M2-02 nicht direkt betroffen.
- Folgt M1-RPC-Pattern (`tournament_propose_set_score` als Vorbild).

---

## TASK-M2.2-T2b: RPC `tournament_organizer_override_pairing`

- **Type**: data
- **Size**: M
- **Bounded Context**: tournament
- **Agent**: coder-data
- **Dependencies**: TASK-M2.2-T1a
- **Wave**: 5
- **Files (anticipated)**: `supabase/migrations/20260601000013_rpc_tournament_organizer_override_pairing.sql`
- **LOC-Budget**: ~90

### Goal

RPC `tournament_organizer_override_pairing(match_id, participant_a, participant_b, reason)` mit Pflicht-Begruendung, Validierung und Audit-Event.

### Acceptance Criteria

- Given Veranstalter ruft RPC mit gueltigen Teilnehmern und nicht-leerer `reason` und Match-Status `scheduled` Then `participant_a/b` aktualisiert, Audit-Event `kind='pairing_overridden'` mit alten und neuen IDs plus Reason.
- Given `reason = ''` oder `NULL` Then `400 MISSING_REASON`.
- Given Match-Status nicht `scheduled` Then `422 MATCH_ALREADY_STARTED`.
- Given Teilnehmer bereits in anderem Match derselben Runde Then `422 PARTICIPANT_CONFLICT`.

### Notes

- Bezug ADR-0017 §6, FR-PAIR-7.

---

## TASK-M2.2-T3a: Helper `_tournament_compute_ko_bracket(seeds jsonb, third_place bool)`

- **Type**: data
- **Size**: L
- **Bounded Context**: tournament
- **Agent**: coder-data
- **Dependencies**: TASK-M2.2-T1a
- **Wave**: 5
- **Files (anticipated)**: `supabase/migrations/20260601000014_fn_compute_ko_bracket.sql`
- **LOC-Budget**: ~100

### Goal

Plpgsql-Function spiegelt den Recursive-Standard-Seeding-Algorithmus aus `bracket.dart:48–61` 1:1. Eingabe: Seeds als JSONB-Array. Ausgabe: Match-Row-Set mit `round_number`, `bracket_position`, `participant_a`, `participant_b`, `phase`, `is_bye_pairing`.

### Acceptance Criteria

- Given `seeds = ['p1','p2','p3','p4']`, `third_place = true` Then Output: 2 Halbfinale + 1 Finale + 1 Third-Place-Match, alle korrekt belegt.
- Given `seeds = ['p1','p2','p3','p4','p5']`, `third_place = false` Then 8-Slot-Bracket mit BYEs an Seeds 1+2+3, R1 hat 1 Match (Seeds 4 vs. 5), R2/R3 Placeholder.
- Function ist deterministisch — zweimal aufgerufen produziert dieselbe Row-Reihenfolge.

### Notes

- Bezug ADR-0017 §7, Architektur §3.2.
- Contract fuer TASK-M2.2-T3b (start_ko_phase nutzt diesen Helper).
- Contract fuer TASK-M2.2-T5 (Property-Paritaet-Test).
- Wiederverwendbar fuer M5 (Schweizer-Hybride).

---

## TASK-M2.2-T3b: RPC `tournament_start_ko_phase`

- **Type**: data
- **Size**: M
- **Bounded Context**: tournament
- **Agent**: coder-data
- **Dependencies**: TASK-M2.2-T3a, TASK-M2.2-T1a
- **Wave**: 6
- **Files (anticipated)**: `supabase/migrations/20260601000015_rpc_tournament_start_ko_phase.sql`
- **LOC-Budget**: ~100

### Goal

RPC startet die KO-Phase server-authoritativ. Validierung, `FOR UPDATE`-Lock, Idempotency-Guard mit `ERRCODE 40001`, Bracket-Insert via Helper, Audit-Event.

### Acceptance Criteria

- Given Vorrunde alle `finalized`/`overridden` When RPC Then KO-Match-Rows mit `phase IN ('ko','third_place','final')` werden inserted, Audit-Event `kind='ko_phase_started'`.
- Given ein Vorrunden-Match `disputed` Then `422 PHASE_NOT_COMPLETE` mit Match-IDs im Detail.
- Given parallele Aufrufe Then erster gewinnt, zweiter bekommt `ERRCODE 40001` ("serialization_failure") — Dart-Client behandelt das als idempoten Erfolg.
- Given `tournaments.ko_config->>'with_third_place_playoff' = 'true'` Then zusaetzlich Third-Place-Match-Row mit `phase = 'third_place'`.

### Notes

- Bezug ADR-0017 §7, Architektur §3.2/§5.2.
- Folgt strikt `tournament_start`-Pattern (M1).
- Contract fuer TASK-M2.2-T7b (`SupabaseTournamentRemote.startKoPhase` behandelt 40001 idempotent).

---

## TASK-M2.2-T4: Trigger `tournament_advance_ko_winner` (mit Walkover)

- **Type**: data
- **Size**: M
- **Bounded Context**: tournament
- **Agent**: coder-data
- **Dependencies**: TASK-M2.2-T1a
- **Wave**: 6
- **Files (anticipated)**: `supabase/migrations/20260601000016_trigger_advance_ko_winner.sql`
- **LOC-Budget**: ~100

### Goal

`AFTER UPDATE`-Trigger auf `tournament_matches`. Bedingung: `OLD.status NOT IN ('finalized','overridden') AND NEW.status IN ('finalized','overridden') AND NEW.phase IN ('ko','third_place','final')`. Schreibt Sieger ins Folge-Match, Verlierer ins Third-Place falls aktiv. Walkover-Pfad fuer Forfeit.

### Acceptance Criteria

- Given KO-Match `phase='ko'`, status wechselt auf `finalized` Then Folge-Match (`round_number+1`, `ceil(bracket_position/2)`) hat Sieger in `participant_a` (bracket_position ungerade) oder `participant_b` (gerade).
- Given Halbfinale finalisiert und `ko_config->>'with_third_place_playoff' = 'true'` Then Verlierer in `third_place`-Match-Row geschrieben.
- Given Match per Forfeit beendet (`winner_participant != NULL`, kein regulaerer Score) Then Walkover-Pfad: Trigger setzt nicht-antretenden Teilnehmer als Verlierer, Sieger rueckt vor.
- Given beide Slots eines Folge-Matches gefuellt Then Status wechselt von `scheduled` auf `awaiting_results`.

### Notes

- Bezug ADR-0017 §5, R-M2.2-2 (Race mit Konsens-Pfad), R-M2.2-3 (Forfeit).
- Forfeit-Logik selbst bleibt M3+; der Trigger muss nur Datenmodell-kompatibel mit Forfeit sein.

---

## TASK-M2.2-T5: Property-Paritaet-Test Dart ↔ plpgsql

- **Type**: tests
- **Size**: M
- **Bounded Context**: tournament
- **Agent**: tester
- **Dependencies**: TASK-M2.2-T3a, TASK-M2.1-T5
- **Wave**: 6
- **Files (anticipated)**: `packages/kubb_domain/test/tournament/bracket_parity_test.dart` ODER `supabase/tests/bracket_parity.sql`
- **LOC-Budget**: ~100

### Goal

Sweep ueber n ∈ {8, 16, 32, 64} und `third_place ∈ {true, false}`. Generiert Bracket via Dart-Referenz und via `_tournament_compute_ko_bracket`, vergleicht JSON-Serialisierung.

### Acceptance Criteria

- Given n=8, third_place=true When beide Implementationen ausgefuehrt Then identische Round-Anzahl, identische Pairings pro Runde, identische Third-Place-Slot-Belegung.
- Given n=64, third_place=false Then identisches Ergebnis.
- Test ist als Merge-Gate konfiguriert — bei Drift wird CI rot.

### Notes

- Bezug ADR-0017 §7 letzter Absatz: "Property-Paritaet als Merge-Gate".
- Wenn pgTAP verfuegbar (TASK-M2.2-T0) → SQL-Variante. Sonst Dart-Integration-Test gegen lokale Supabase-Instanz mit `supabase_flutter`.

---

## TASK-M2.2-T6: RPC-Tests (pgTAP oder Dart-Integration)

- **Type**: tests
- **Size**: M
- **Bounded Context**: tournament
- **Agent**: tester
- **Dependencies**: TASK-M2.2-T0, TASK-M2.2-T2, TASK-M2.2-T2b, TASK-M2.2-T3b, TASK-M2.2-T4
- **Wave**: 7
- **Files (anticipated)**: `supabase/tests/tournament_ko_rpcs.sql` ODER `integration_test/tournament_ko_rpcs_test.dart`
- **LOC-Budget**: ~100

### Goal

Test-Suite deckt fuer alle vier RPCs: Happy-Path, Authorization-Fail, Phase-Validierung, Walkover-Pfad.

### Acceptance Criteria

- 12+ Test-Cases gruen (jede RPC mind. 3 Cases).
- Idempotency-Test fuer `tournament_start_ko_phase`: zweiter Aufruf liefert `ERRCODE 40001`.
- Forfeit-Walkover-Pfad in `tournament_advance_ko_winner` verifiziert.

### Notes

- Strategie nach TASK-M2.2-T0-Ergebnis.

---

## TASK-M2.2-T7a: `TournamentRemote`-Port-Erweiterung

- **Type**: domain
- **Size**: S
- **Bounded Context**: tournament
- **Agent**: coder-domain
- **Dependencies**: TASK-M2.2-T3b, TASK-M2.2-T4
- **Wave**: 7
- **Files (anticipated)**: `packages/kubb_domain/lib/src/ports/tournament_remote.dart`
- **LOC-Budget**: ~50

### Goal

Interface `TournamentRemote` bekommt vier neue abstrakte Methoden (`setSeeding`, `startKoPhase`, `overrideKoPairing`, `getBracket`) gemaess Architektur §4 Code-Block.

### Acceptance Criteria

- Existierende Implementations (Supabase, Fake) kompilieren noch (UnimplementedError oder Stub).
- Vier Methoden-Signaturen exakt wie in Architektur §4.

### Notes

- Bezug Architektur §4.
- Contract fuer TASK-M2.2-T7b und TASK-M2.2-T7c.

---

## TASK-M2.2-T7b: `SupabaseTournamentRemote`-Implementation

- **Type**: data
- **Size**: M
- **Bounded Context**: tournament
- **Agent**: coder-data
- **Dependencies**: TASK-M2.2-T7a, TASK-M2.2-T3b, TASK-M2.2-T4
- **Wave**: 7
- **Files (anticipated)**: `lib/features/tournament/data/tournament_repository.dart`, `lib/features/tournament/data/tournament_models.dart`
- **LOC-Budget**: ~100

### Goal

Vier RPC-Calls implementiert. `startKoPhase` behandelt `ERRCODE 40001` idempotent (kein Error-Toast, `ref.invalidate`).

### Acceptance Criteria

- Given `startKoPhase(id)` mit `40001`-Response Then keine Exception nach oben, stattdessen `ref.invalidate` und Success-Semantik.
- Given `setSeeding`, `overrideKoPairing`, `getBracket` Then HTTP-RPC-Call wie M1-Pattern.
- Wire-Shapes (`KoPhaseConfigWire`, `BracketPositionWire`, `SeedingOverrideWire`) sind JSON-serialisierbar.

### Notes

- Bezug Architektur §3.3 Data, ADR-0017 §7.

---

## TASK-M2.2-T7c: `FakeTournamentRemote`-Implementation

- **Type**: tests
- **Size**: M
- **Bounded Context**: tournament
- **Agent**: tester
- **Dependencies**: TASK-M2.2-T7a
- **Wave**: 7
- **Files (anticipated)**: `lib/features/tournament/data/fake_tournament_remote.dart` (oder bestehender Pfad im Repo)
- **LOC-Budget**: ~100

### Goal

Fake-Adapter implementiert die vier Methoden plus simuliert den `tournament_advance_ko_winner`-Trigger (wenn Match finalisiert wird, schiebt der Fake automatisch in die naechste Runde).

### Acceptance Criteria

- Given Fake `proposeSetScores` finalisiert ein KO-Match Then Folge-Match-Slot wird automatisch gefuellt (Trigger-Simulation).
- Given Fake `startKoPhase` Then KO-Match-Rows werden im In-Memory-Store erzeugt.

### Notes

- Bezug Architektur §4 letzter Absatz: Fake muss Trigger simulieren.
- Contract fuer TASK-M2.3-T11 (SeedingScreen) und TASK-M2.3-T16 (e2e-Test).

---

# M2.3 — UI (Wave 8 bis 11)

## TASK-M2.3-T1: Widget-Tests `BracketCanvas`

- **Type**: tests
- **Size**: M
- **Bounded Context**: tournament
- **Agent**: tester
- **Dependencies**: TASK-M2.1-T8
- **Wave**: 8
- **Files (anticipated)**: `test/features/tournament/presentation/bracket/bracket_canvas_test.dart`
- **LOC-Budget**: ~80

### Goal

Widget-Tests fuer `BracketCanvas`: Layout-Rendering, Tap-Navigation, Read-only-Modus.

### Acceptance Criteria

- Given `BracketCanvas` mit Bracket-Stub und 8 Teilnehmern Then 7 `KubbMatchCard`-Widgets sichtbar.
- Given Tap auf Match-Card Then `context.go('/<id>/match/<matchId>')` wird gerufen (Mock-Router).
- Given Read-only-Modus (`editable: false`) Then Tap loest kein Override-Dialog aus.

### Notes

- Bezug ADR-0016 Implementation Notes.
- Contract fuer TASK-M2.3-T6, T7, T8.

---

## TASK-M2.3-T2: Golden-Test-Setup

- **Type**: tests
- **Size**: S
- **Bounded Context**: tournament
- **Agent**: tester
- **Dependencies**: TASK-M2.1-T8
- **Wave**: 8
- **Files (anticipated)**: `test/features/tournament/presentation/bracket/bracket_canvas_golden_test.dart`
- **LOC-Budget**: ~60

### Goal

`golden_toolkit`-Setup mit Test-Cases fuer 4/8/16/32/64-Team-Brackets plus BYE- und Third-Place-Varianten. Tests sind initial rot (Goldens existieren noch nicht).

### Acceptance Criteria

- Given Test-Cases laufen Then 5+ Golden-Test-Slots existieren, alle initial fehlend.
- Goldens werden in TASK-M2.3-T9 generiert.

### Notes

- Bezug ADR-0016 Implementation Notes.

---

## TASK-M2.3-T3: `TournamentConfigDraft` Erweiterung

- **Type**: frontend
- **Size**: M
- **Bounded Context**: tournament
- **Agent**: coder-frontend
- **Dependencies**: TASK-M2.1-T7
- **Wave**: 8
- **Files (anticipated)**: `lib/features/tournament/data/tournament_config_draft.dart`, `test/features/tournament/data/tournament_config_draft_test.dart`
- **LOC-Budget**: ~80

### Goal

`TournamentConfigDraft` bekommt drei neue Felder: `koConfig: KoPhaseConfig?`, `bracketSeedingMode: SeedingMode?`, `leagueEligible: bool` (Default `false`). Validierungs-Pfade erweitert.

### Acceptance Criteria

- Given Format `single_elimination` oder `round_robin_then_ko` When `validate()` Then `koConfig` muss non-null sein.
- Given `leagueEligible = true` Then Wizard schlaegt `withThirdPlacePlayoff = true` als Default-Value vor (Test verifiziert den Vorschlag, nicht den finalen Wert).
- Tests fuer copyWith, ==, validate gruen.

### Notes

- Bezug ADR-0017 §4, Architektur §3.3 Application.

---

## TASK-M2.3-T4: `tournament_bracket_provider`

- **Type**: frontend
- **Size**: S
- **Bounded Context**: tournament
- **Agent**: coder-frontend
- **Dependencies**: TASK-M2.2-T7b, TASK-M2.2-T7c, TASK-M2.1-T9
- **Wave**: 8
- **Files (anticipated)**: `lib/features/tournament/application/tournament_bracket_provider.dart`, `test/features/tournament/application/tournament_bracket_provider_test.dart`
- **LOC-Budget**: ~70

### Goal

Riverpod `FutureProvider.family<Bracket, TournamentId>` ruft `TournamentRemote.getBracket(id)` (oder komponiert intern via `listMatchesForTournament` + `bracketFromMatches`). Polling 5s.

### Acceptance Criteria

- Given Provider in Test-Container Then `Bracket`-Wertobjekt nach Fetch verfuegbar.
- Given `tournamentId` aendert sich Then Provider feuert neu (family).

### Notes

- Bezug Architektur §3.3 Application, §5.4.

---

## TASK-M2.3-T5: l10n DE-Strings

- **Type**: frontend
- **Size**: S
- **Bounded Context**: tournament
- **Agent**: coder-frontend
- **Dependencies**: —
- **Wave**: 8
- **Files (anticipated)**: `lib/l10n/app_de.arb` (oder Pfad im Repo)
- **LOC-Budget**: ~50

### Goal

DE-Strings fuer alle neuen Screens und Wizard-Schritte: Bracket-View-Labels, Seeding-Editor, Wizard-Schritte 4.5/5/6, BYE-Tooltip (U6), Hilfe-Text (U8).

### Acceptance Criteria

- 25+ neue ARB-Keys existieren.
- Keys folgen bestehender Namenskonvention.
- Tooltip-Text fuer BYE-Slot paraphrasiert FR-FMT-11 ohne Spec-Jargon (U6).

### Notes

- Bezug Domain-Notiz `qualifier-count.md` U6/U8/U9.

---

## TASK-M2.3-T6: `KubbMatchCard`-Widget

- **Type**: frontend
- **Size**: M
- **Bounded Context**: tournament
- **Agent**: coder-frontend
- **Dependencies**: TASK-M2.3-T1
- **Wave**: 9
- **Files (anticipated)**: `lib/features/tournament/presentation/bracket/kubb_match_card.dart`
- **LOC-Budget**: ~100

### Goal

`KubbMatchCard`-Widget: Match-Box mit Teilnehmer, Seed, Score, Status. Tap via `InkWell`, Semantics first-class, `KubbTokens` direkt konsumiert.

### Acceptance Criteria

- Given Match mit `participantA`, `participantB`, `winnerId` Then Card zeigt beide Namen, Sieger optisch hervorgehoben.
- Given BYE-Slot Then Card zeigt "Freilos"-Label plus Icon (U5).
- Card-Hoehe ≥ 48 px (`KubbTokens.touchMin`).
- Semantics-Label vorhanden.

### Notes

- Bezug ADR-0016 Implementation Notes.

---

## TASK-M2.3-T7: `BracketConnectorPainter`

- **Type**: frontend
- **Size**: M
- **Bounded Context**: tournament
- **Agent**: coder-frontend
- **Dependencies**: TASK-M2.3-T1, TASK-M2.1-T8
- **Wave**: 9
- **Files (anticipated)**: `lib/features/tournament/presentation/bracket/bracket_connector_painter.dart`
- **LOC-Budget**: ~100

### Goal

CustomPainter zeichnet rechtwinklige Connector-Linien zwischen Match-Boxen. `shouldRepaint` ist optimiert (Layout-Hash). Separater Repaint-Listener fuer Highlight-Layer.

### Acceptance Criteria

- Given Layout-Output aus `BracketLayout.compute` Then Painter zeichnet exakt N-1 Connectoren fuer einen N-Match-Bracket.
- Given Highlight-Match aendert sich Then nur Highlight-Layer wird neu gemalt, nicht der ganze Painter.
- Viewport-Culling ab 32-Team-Brackets aktiv (`canvas.clipRect`).

### Notes

- Bezug ADR-0016 Implementation Notes, Scale-Impact-Notiz "p95 < 16ms first-paint".

---

## TASK-M2.3-T8: `BracketCanvas`-ConsumerWidget

- **Type**: frontend
- **Size**: M
- **Bounded Context**: tournament
- **Agent**: coder-frontend
- **Dependencies**: TASK-M2.3-T6, TASK-M2.3-T7
- **Wave**: 9
- **Files (anticipated)**: `lib/features/tournament/presentation/bracket/bracket_canvas.dart`
- **LOC-Budget**: ~100

### Goal

Root-Widget `BracketCanvas`: `InteractiveViewer` mit `Stack` aus `Positioned`-`KubbMatchCard`-Widgets plus `CustomPaint`-Layer fuer Connectoren. Konsumiert `BracketLayout` und `currentMatchProvider`.

### Acceptance Criteria

- Given Bracket-Provider liefert Bracket Then `BracketCanvas` rendert ohne Overflow auf 360px-Display.
- Given 16-Team-Bracket Then horizontal scrollbar.
- Tests aus TASK-M2.3-T1 gruen.

### Notes

- Bezug ADR-0016 Implementation Notes.

---

## TASK-M2.3-T9: Bracket-View-Goldens generieren

- **Type**: tests
- **Size**: S
- **Bounded Context**: tournament
- **Agent**: tester
- **Dependencies**: TASK-M2.3-T8, TASK-M2.3-T2
- **Wave**: 9
- **Files (anticipated)**: `test/features/tournament/presentation/bracket/goldens/*.png`
- **LOC-Budget**: 0 (Bilder)

### Goal

Goldens fuer 4/8/16/32/64-Team-Brackets plus BYE- und Third-Place-Varianten generieren und einchecken.

### Acceptance Criteria

- 5+ Golden-PNG-Dateien existieren.
- `flutter test --update-goldens` einmal manuell ausgefuehrt, danach Tests aus T2 gruen.

### Notes

- Bezug ADR-0016 Implementation Notes ("Goldens via golden_toolkit").

---

## TASK-M2.3-T10: `TournamentBracketScreen` + Route

- **Type**: frontend
- **Size**: M
- **Bounded Context**: tournament
- **Agent**: coder-frontend
- **Dependencies**: TASK-M2.3-T8
- **Wave**: 10
- **Files (anticipated)**: `lib/features/tournament/presentation/tournament_bracket_screen.dart`, `lib/features/tournament/presentation/tournament_routes.dart`
- **LOC-Budget**: ~80

### Goal

Neue Route `/<id>/bracket` plus Screen. Konsumiert `tournament_bracket_provider`, rendert `BracketCanvas`.

### Acceptance Criteria

- Given Route `/<id>/bracket` Then Screen sichtbar (auch fuer Anon-User bei `published/live/finalized`-Turnieren).
- Given Phase = `group` Then Screen zeigt "KO noch nicht gestartet"-Empty-State.

### Notes

- Bezug Architektur §3.3 Presentation.

---

## TASK-M2.3-T11: `TournamentSeedingScreen` + Controller

- **Type**: frontend
- **Size**: L
- **Bounded Context**: tournament
- **Agent**: coder-frontend
- **Dependencies**: TASK-M2.2-T7c, TASK-M2.1-T6
- **Wave**: 10
- **Files (anticipated)**: `lib/features/tournament/presentation/tournament_seeding_screen.dart`, `lib/features/tournament/application/tournament_seeding_controller.dart`, `test/features/tournament/presentation/tournament_seeding_screen_test.dart`
- **LOC-Budget**: ~100

### Goal

Seeding-Editor mit `ReorderableListView` plus "Auto wiederherstellen" und "KO starten"-Button. Controller haelt State, ruft `setSeeding` und `startKoPhase`.

### Acceptance Criteria

- Given Vorrunde fertig When Veranstalter oeffnet Screen Then Top-N-Liste in Auto-Seed-Reihenfolge sichtbar.
- Given Drag-Reorder Then Liste aktualisiert, "Speichern" ruft `setSeeding`.
- Given "Auto wiederherstellen" Then Auto-Order ist wiederhergestellt.
- Given "KO starten" Then `startKoPhase` aufgerufen, bei 40001 idempotent, sonst Navigation zu Bracket-Screen.

### Notes

- Bezug Architektur §3.3, §5.2.
- LOC-Budget liegt am Senior-Limit; bei Verstoss split in `_screen` + `_controller` als separate Tasks moeglich.

---

## TASK-M2.3-T12: Wizard-Schritt 4.5 — Liga-Flag-Frage

- **Type**: frontend
- **Size**: S
- **Bounded Context**: tournament
- **Agent**: coder-frontend
- **Dependencies**: TASK-M2.3-T3
- **Wave**: 10
- **Files (anticipated)**: `lib/features/tournament/presentation/widgets/_wizard_league_step.dart`
- **LOC-Budget**: ~60

### Goal

Neuer Wizard-Sub-Schritt als ausgelagertes Helper-Widget. Switch "Dieses Turnier wertet fuer die Liga", Default aus. Bei `true` schlaegt der naechste Schritt `withThirdPlacePlayoff = true` als Default vor.

### Acceptance Criteria

- Given User aktiviert Switch Then `TournamentConfigDraft.leagueEligible = true`.
- Given User aktiviert Then Schritt 5 (KO-Konfig) hat `withThirdPlacePlayoff` initial `true`.
- Given Switch deaktiviert Then Default bleibt `false`.

### Notes

- Bezug ADR-0017 §4, Domain-Notiz `spiel-um-platz-3.md`.
- Wird in `tournament_setup_wizard.dart` als `_LeagueStep`-Widget eingehaengt — Wizard-Datei selbst kriegt nur eine Zeile mehr im `_buildStep`-Switch (siehe T13 fuer den Switch-Anker).

---

## TASK-M2.3-T13: Wizard-Schritt 5 — KO-Konfiguration

- **Type**: frontend
- **Size**: L
- **Bounded Context**: tournament
- **Agent**: coder-frontend
- **Dependencies**: TASK-M2.3-T3, TASK-M2.3-T12
- **Wave**: 10
- **Files (anticipated)**: `lib/features/tournament/presentation/widgets/_wizard_ko_config_step.dart`, `lib/features/tournament/presentation/tournament_setup_wizard.dart` (Anker-Aenderung)
- **LOC-Budget**: ~100

### Goal

Wizard-Schritt 5 als Helper-Widget mit: Qualifier-Anzahl (freier Integer-Input plus Live-Validierung U1/U2), Preview-Panel (U3), Smart-Default (U4), Bronze-Switch, Seeding-Mode-Radio. `_totalSteps`-Logik in `tournament_setup_wizard.dart` dynamisch.

### Acceptance Criteria

- Given Format `round_robin_then_ko` Then `_totalSteps = 6` (Format + Liga + KO + Tiebreaker + …).
- Given User tippt `qualifierCount = 6` bei 12 Teilnehmern Then Preview zeigt: "Bracket-Groesse: 8", "2 BYEs an Seeds 1+2", "R1 hat 4 echte Matches".
- Given participantCount ist 2^n Then Smart-Default = `participantCount / 2`. Sonst naechstgelegene 2^n unter `participantCount`.
- Live-Validierung: 2 <= qualifierCount <= participantCount.

### Notes

- Bezug Domain-Notiz `qualifier-count.md` U1–U4.
- ADR-0017 §3.

---

## TASK-M2.3-T14: Wizard-Schritt 6 — Tiebreaker-Reorder

- **Type**: frontend
- **Size**: M
- **Bounded Context**: tournament
- **Agent**: coder-frontend
- **Dependencies**: TASK-M2.3-T3
- **Wave**: 10
- **Files (anticipated)**: `lib/features/tournament/presentation/widgets/_wizard_tiebreaker_step.dart`
- **LOC-Budget**: ~90

### Goal

Wizard-Schritt 6 als Helper-Widget mit Preset-Auswahl ("Standard", "Schweizer-konform", "Custom") plus `ReorderableListView` im Custom-Mode (OD-M2-03 Empfehlung C).

### Acceptance Criteria

- Given Preset "Standard" gewaehlt Then Default-Tiebreaker-Order ist gesetzt.
- Given Preset "Custom" Then Reorder-Liste sichtbar.
- Given Reorder durchgefuehrt Then `TournamentConfigDraft.tiebreakerOrder` aktualisiert.

### Notes

- Bezug OD-M2-03 (committee-marker, vorlaeufige Empfehlung C wird umgesetzt; Anpassbar wenn Owner anders entscheidet).

---

## TASK-M2.3-T15: Bracket-Tab in `tournament_detail_screen`

- **Type**: frontend
- **Size**: S
- **Bounded Context**: tournament
- **Agent**: coder-frontend
- **Dependencies**: TASK-M2.3-T10
- **Wave**: 10
- **Files (anticipated)**: `lib/features/tournament/presentation/tournament_detail_screen.dart`
- **LOC-Budget**: ~50

### Goal

Bestehender `TournamentDetailScreen` bekommt eine "Bracket"-Karte oder einen Tab, der auf `/<id>/bracket` weiterleitet. Sichtbar wenn Phase ≥ `ko`.

### Acceptance Criteria

- Given Turnier-Phase ist `group` Then Bracket-Card nicht sichtbar.
- Given irgendein Match `phase IN ('ko','third_place','final')` Then Bracket-Card sichtbar.

### Notes

- Bezug Architektur §3.3 Presentation.

---

## TASK-M2.3-T16: Integrations-Test `round_robin_then_ko_e2e`

- **Type**: tests
- **Size**: L
- **Bounded Context**: tournament
- **Agent**: tester
- **Dependencies**: TASK-M2.3-T10, TASK-M2.3-T11, TASK-M2.3-T13
- **Wave**: 11
- **Files (anticipated)**: `integration_test/tournament/round_robin_then_ko_e2e_test.dart`
- **LOC-Budget**: ~100

### Goal

End-to-End: 8 Teilnehmer, Setup-Wizard, Round-Robin spielen, KO starten, Halbfinale spielen, Final + Bronze spielen, Endrangliste verifizieren.

### Acceptance Criteria

- Given 8-Spieler-Turnier `round_robin_then_ko`, Qualifier=4, Bronze=ja When voller Flow Then Endrangliste hat Plaetze 1–4 in korrekter Reihenfolge, Plaetze 5–8 nach Vorrunden-Standings.
- Bracket-View zeigt am Ende alle Matches finalisiert.

### Notes

- Bezug Architektur §5 (alle vier Datenfluss-Diagramme), Demo-Akzeptanz M2.3.

---

## TASK-M2.3-T17: Demo-Script dokumentieren

- **Type**: docs
- **Size**: S
- **Bounded Context**: core
- **Agent**: coder-domain (oder researcher)
- **Dependencies**: TASK-M2.3-T16
- **Wave**: 11
- **Files (anticipated)**: `docs/plans/m2-ko-bracket/demo-script.md`
- **LOC-Budget**: ~80 (Markdown)

### Goal

Manuelle Demo-Anleitung fuer Owner-Abnahme. 20-Minuten-Skript am Tablet, vier gleichzeitige Player-Phones.

### Acceptance Criteria

- Script enthaelt Schritte 1–9 aus `milestone-plan.md` "Was nach M2 demobar ist".
- Erwartungen pro Schritt explizit (was sieht der Owner).

### Notes

- Demobarkeit-Gate fuer M2.

---

# Zusammenfassung

- Sub-Milestone M2.1: 11 Tasks (T1–T11), 3 Waves.
- Sub-Milestone M2.2: 11 Tasks (T0, T1a, T1b, T2, T2b, T3a, T3b, T4, T5, T6, T7a, T7b, T7c — 13 Tasks), 4 Waves.
- Sub-Milestone M2.3: 17 Tasks (T1–T17), 4 Waves.
- Gesamt: 41 Tasks ueber 11 Waves.
