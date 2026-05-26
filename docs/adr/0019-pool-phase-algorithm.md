# ADR-0019: Pool-Phase-Algorithmus (Group-Round-Robin, Cut, Cross-Pool-Tiebreaker)

- **Status**: Accepted
- **Date**: 2026-05-26
- **Depends on**: ADR-0001 (Tech-Stack), ADR-0002 (Bounded Contexts), ADR-0014 (Tournament-Match-Pfad-Trennung), ADR-0017 (KO-Phase-Semantik)
- **Bezug**: `docs/plans/m3-teams-pools-roster/architecture.md` §3.3–§3.4, `docs/specs/tournament-mode-spec.md` §3.8 FR-FMT-5, OD-M3-03, OD-M3-05

## Context

Spec FR-FMT-5 fordert "Gruppenphase plus KO" als Format-Variante. M1 hat `round_robin` als ein-Gruppen-RR umgesetzt; M2 hat `single_elimination` plus `round_robin_then_ko` (mit ein-Gruppen-RR-Vorrunde) aufgebaut. M3 öffnet jetzt den Mehrgruppen-Fall: zwei oder mehr parallele Round-Robins als Vorrunde, danach Top-N pro Gruppe ins KO.

Drei Aspekte sind zu entscheiden:

1. **Gruppen-Generation** — wie werden Teilnehmer in Gruppen verteilt? Snake-Pattern (seeded), zufällig, manuell?
2. **Cut-Algorithmus** — wenn Top-2 pro Gruppe ins KO rücken, wie wird das KO-Seeding aus den Top-2 ermittelt?
3. **Cross-Pool-Tiebreaker** — wenn zwei Top-Qualifier aus verschiedenen Gruppen identische Standings haben, wie ranken wir sie für das KO-Seeding?

Existierende Infrastruktur:

- `packages/kubb_domain/lib/src/tournament/pool.dart` hat einen Round-Robin-Generator für eine Gruppe (M0).
- `packages/kubb_domain/lib/src/tournament/tiebreaker.dart` hat eine konfigurierbare `TiebreakerChain` (M1).
- `packages/kubb_domain/lib/src/tournament/standings.dart` berechnet `ParticipantStats` (M1).
- ADR-0017 §7 hat Server-Authority für `tournament_start_ko_phase` als plpgsql-Spiegelung etabliert — Pool-Phase folgt diesem Pattern.

## Decision

Folgende M3-ODs werden mit dieser ADR aufgelöst (alle 2026-05-26 resolved):

- **OD-M3-03** (Cross-Pool-Tiebreaker): Option A mit Anpassung — bestehende `TiebreakerChain` Cross-Pool wiederverwenden, `direct_comparison` automatisch überspringen (Cross-Pool nicht definiert). Siehe §3.
- **OD-M3-05** (Pool-Cut bei vollständigem Tie): Option B — RPC `_tournament_compute_pool_cut` wirft `TIEBREAKER_NEEDS_RESOLUTION`, Frontend zeigt Veranstalter-Eskalations-Dialog. Kein Coin-Flip, kein Stichkampf. Siehe §4.

### 1. Gruppen-Verteilung

Drei Strategien werden unterstützt, wählbar im Wizard-Schritt "Pool-Konfiguration":

```dart
enum GroupingStrategy { snake, random, seeded }
```

- **Snake** (Default): Seeding 1, 2, 3, 4 ... wird verteilt nach Snake-Pattern. Bei 4 Gruppen: Seed 1 in A, Seed 2 in B, Seed 3 in C, Seed 4 in D, Seed 5 in D (back), Seed 6 in C, Seed 7 in B, Seed 8 in A, Seed 9 in A (forward), ... Gleichmässige Stärke-Verteilung.
- **Random**: deterministisch (`random_seed = tournament_id`), aber nicht-seeded. Für Casual-Turniere ohne Vor-Ranking.
- **Seeded**: alphabetisch oder nach manuellem Pre-Seeding (M5+ Erweiterung). In M3 als Stub akzeptiert, fällt zurück auf `random`.

Pure-Dart-Funktion in `packages/kubb_domain/lib/src/tournament/pool_phase_generator.dart`:

```dart
List<Pool> generatePools(
  List<String> participantIds,
  PoolPhaseConfig config,
);
```

Validierung im `PoolPhaseConfig`-Konstruktor:

- `groupCount >= 2 AND groupCount <= 16`
- `qualifiersPerGroup >= 1 AND qualifiersPerGroup * groupCount <= participantCount`
- Bei `participantCount % groupCount != 0`: Warnung im UI, aber kein Fehler. Gruppen bekommen ungleiche Grössen (Rounding).

### 2. Top-N-Cut pro Gruppe

`packages/kubb_domain/lib/src/tournament/pool_cut.dart` enthält die pure Funktion:

```dart
List<String> selectQualifiers(
  List<List<ParticipantStats>> standingsPerGroup,
  PoolPhaseConfig config,
  TiebreakerChain chain,
);
```

Vorgehen:

1. Sortiere jede Gruppen-Standings mit der vom Veranstalter gewählten `TiebreakerChain` (aus `tournaments.tiebreaker_order`).
2. Nimm die ersten `qualifiersPerGroup` aus jeder Gruppe.
3. Merge alle Qualifier zu einer Liste.
4. Sortiere die Merged-Liste mit der Cross-Pool-Variante der Chain (siehe 3.).
5. Resultierende Reihenfolge ist das KO-Seeding (Seed 1 = bester Qualifier insgesamt).

### 3. Cross-Pool-Tiebreaker (OD-M3-03)

Die `TiebreakerChain` wird Cross-Pool unverändert verwendet **mit einer Ausnahme**: das Kriterium `direct_comparison` ist Cross-Pool nicht definiert (zwei Qualifier aus verschiedenen Gruppen haben sich nie direkt getroffen). Es wird übersprungen — der Algorithmus geht zum nächsten Kriterium über.

Konkret in `pool_cut.dart`:

```dart
TiebreakerChain crossPoolChain(TiebreakerChain original) {
  return original.where((c) => c != TiebreakerCriterion.directComparison);
}
```

Begründung: bestehende Tiebreaker-Logik wird wiederverwendet, kein neuer Algorithmus. Schwächere Differenzierung bei Tie ist akzeptiert — Edge-Case wird via OD-M3-05 (Veranstalter-Override) aufgelöst.

### 4. Vollständiger Tie nach Cross-Pool-Chain (OD-M3-05)

Wenn nach dem Cross-Pool-Sort zwei Qualifier identische Werte über alle Kriterien haben (sehr selten mit EKC-Score, aber möglich), wirft die Server-RPC `_tournament_compute_pool_cut`:

```
RAISE EXCEPTION 'TIEBREAKER_NEEDS_RESOLUTION'
  USING ERRCODE = '40001',
        DETAIL = '{"tied_participants":[...]}';
```

Frontend zeigt Veranstalter einen Eskalations-Dialog ("Diese N Qualifier sind nach allen Tiebreakern identisch — entscheide manuell"). Die manuelle Entscheidung schreibt einen `tournament_seeding_overrides`-Eintrag (existiert seit M2) und ruft `tournament_start_ko_phase` erneut auf.

Kein Coin-Flip, kein automatischer Stichkampf — Mensch entscheidet.

### 5. Server-Authority

Wie ADR-0017 §7: Pool-Generation und Pool-Cut laufen serverseitig in plpgsql:

- `_tournament_compute_pools(seed_list jsonb, group_count int, strategy text)` → JSON-Mapping `{participant_id → group_label}`.
- `_tournament_compute_pool_cut(group_label text, top_n int, tiebreaker_chain text[])` → Top-N-Liste pro Gruppe.

Beide spiegeln 1:1 die pure-Dart-Funktionen. Property-Parität-Tests in M3.3-T7 sind Merge-Gate gegen Drift.

Idempotency-Pattern aus M2 wird übernommen: `tournament_start_pool_phase` macht `FOR UPDATE` auf `tournaments`-Row, gibt `ERRCODE 40001` bei doppelter Phase-Transition (Dart-Client behandelt als idempotenten Success).

### 6. Datenmodell-Auswirkungen

Migration `20260615000005_tournament_pool_phase.sql`:

- `ALTER TABLE tournament_participants ADD COLUMN group_label text NULL` — wird beim Pool-Phase-Start gesetzt.
- `ALTER TABLE tournament_matches ADD COLUMN group_label text NULL` — markiert Pool-Matches, NULL bei KO.
- `tournament_matches.phase` (aus M2) bekommt zusätzlichen Wert `group` — Default für M3 Pool-Matches.

Der M2 `tournament_start_ko_phase`-RPC wird erweitert: wenn `group_label IS NOT NULL` in den Vorrunden-Matches, ruft er den `_tournament_compute_pool_cut`-Helper vor `_tournament_compute_ko_bracket`. Backward-Compatibility: bei reinem `round_robin_then_ko` ohne Pool-Phase bleibt das alte Verhalten (alles in einer Gruppe).

### 7. Pure-Dart-Interface

```dart
@immutable
class PoolPhaseConfig {
  const PoolPhaseConfig({
    required this.groupCount,
    required this.qualifiersPerGroup,
    required this.groupingStrategy,
  });

  final int groupCount;
  final int qualifiersPerGroup;
  final GroupingStrategy groupingStrategy;

  void validate(int participantCount) {
    if (groupCount < 2 || groupCount > 16) {
      throw ArgumentError('groupCount must be in [2, 16]');
    }
    if (qualifiersPerGroup < 1) {
      throw ArgumentError('qualifiersPerGroup must be at least 1');
    }
    final smallestGroupSize = participantCount ~/ groupCount;
    if (qualifiersPerGroup > smallestGroupSize) {
      throw ArgumentError(
        'qualifiersPerGroup ($qualifiersPerGroup) exceeds smallest '
        'group size ($smallestGroupSize) for $participantCount '
        'participants in $groupCount groups',
      );
    }
  }
}
```

## Alternatives considered

### A) Cross-Pool ohne Tiebreaker-Wiederverwendung (eigener Algorithmus)

Verworfen. Eigene Cross-Pool-Logik bedeutet zwei Tiebreaker-Implementierungen (Within-Group plus Cross-Pool), die divergieren können. Die Wiederverwendung mit `directComparison`-Skip ist einfacher zu testen und vermeidet das Drift-Risiko.

### B) Pool-Stärke-Normalisierung (Buchholz-bereinigt um Pool-Schnitt)

Verworfen. Mathematisch interessant, in der Praxis kaum erklärbar gegenüber Veranstaltern und Spielern. Schweizer Liga-Praxis (per Kubb-Knowledge-Skill, OD-M3-03) nutzt es nicht. Komplexitätskosten überschritten den Wert.

### C) Coin-Flip bei vollständigem Tie (statt Veranstalter-Override)

Verworfen. Random-Entscheidung über Qualifikation ist sportlich nicht akzeptiert. Schweizer Liga-Reglemente verlangen eine bewusste Entscheidung. Ein Eskalations-Dialog ist nervig, aber ehrlich.

### D) Stichkampf als generiertes Tie-Break-Match

Verworfen für M3. Zusätzlicher Match-Generation-Pfad mit eigener Pitch-Logistik und Spieler-Benachrichtigung — Aufwand für einen extrem seltenen Edge-Case. Kann M5+ kommen, wenn die Liga-Reglemente das explizit fordern.

### E) Client-Authority statt plpgsql-Spiegelung

Verworfen aus denselben Gründen wie ADR-0017 §7 für die KO-Phase: Race-Condition zwischen parallelen Veranstalter-Geräten ist real, Server-Authority eliminiert sie ohne Optimistic-Lock-Komplexität. Die plpgsql-Spiegelung ist mit Property-Parität-Tests beherrschbar.

### F) Snake-Pattern weglassen und nur "Random" anbieten

Verworfen. Snake ist Schweizer Standard für gleichmässige Stärke-Verteilung. Ohne Snake wären schwache Teams womöglich gegen lauter Top-Teams in einer Gruppe. Auf Vorrunden-Niveau eine echte Fairness-Frage.

## Consequences

### Was einfacher wird

- Pool-Cut nutzt die bestehende `TiebreakerChain` — keine Duplizierung der Tiebreaker-Logik.
- Server-Authority-Pattern aus M2 wird wiederverwendet, kein neues Lifecycle-Konzept.
- KO-Übergang nach Pool-Phase ist nur eine Erweiterung von `tournament_start_ko_phase` — kein neuer Aufruf-Pfad für den Client.
- Pure-Dart-Funktion plus plpgsql-Spiegelung plus Property-Parität-Tests folgen dem etablierten M2-Workflow.

### Was teurer wird

- Zwei Implementationen von `generatePools` und `selectQualifiers` (Dart plus plpgsql) müssen synchron gehalten werden — Drift-Risiko ist mit Property-Parität-Tests beherrschbar, aber jede Änderung am Algorithmus erfordert beidseitige Anpassung.
- Vollständiger Tie als Veranstalter-Eskalation ist UX-Reibung — selten, aber unangenehm wenn er auftritt. Die Eskalations-UI muss klar und schnell sein.
- Snake-Pattern bei ungleicher Gruppen-Grösse (z.B. 14 Teams in 4 Gruppen) erzeugt Gruppen-Grössen (4, 4, 3, 3) — Standings müssen relativ statt absolut verglichen werden (Sieg-Quote statt Sieg-Anzahl). Bestehende `standings.dart` braucht Anpassung.

### Nicht-Konsequenzen

- Schweizer-System bleibt M5. Pool-Phase ist nicht Schweizer-System — Schweizer-System hat dynamische Paarungen pro Runde basierend auf Standings, Pool-Phase hat statische Paarungen ab Gruppen-Start.
- Schoch-Mode bleibt M5. Schoch hat Cut-Mechanik basierend auf Loss-Count, nicht auf Rangierung pro Gruppe.
- Liga-Punkte-Berechnung aus Pool-Phasen-Standings ist M5-Block (FR-POINTS).
