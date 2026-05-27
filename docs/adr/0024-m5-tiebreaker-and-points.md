# ADR-0024: M5 — Tiebreaker-Reihenfolge und Match-Punkte-Schema im Schweizer System

- **Status**: Accepted
- **Date**: 2026-05-27
- **Depends on**: ADR-0014 (Tournament-Match-Coexistence), ADR-0019 (Pool-Phase-Algorithm)
- **Bezug**: `docs/plans/m5-swiss-league-season/architecture.md` §3 (`SwissSystemStrategy`, `BuchholzCalculator`, `LeaguePointsEngine`), `open-decisions.md` OD-M5-01 + OD-M5-02, `docs/specs/tournament-mode-spec.md` §3.6 (FR-FMT-4), §3.7 (FR-PAIR-1..-8), §3.14 (FR-POINTS-1)

## Kontext

Der Schweizer-System-Strategy braucht eine deterministische Sortierung bei Score-Gleichstand — sowohl im Pairing pro Runde als auch in der Schluss-Rangliste. Ohne klare Reihenfolge produziert das Pairing für gleiche Eingaben unterschiedliche Outputs, was Tests instabil macht und Veranstalter verunsichert.

Zusätzlich braucht der `LeaguePointsEngine` ein Default-Schema für Match-Punkte (Sieg / Unentschieden / Niederlage), das in die Buchholz-Berechnung einfliesst. Match-Punkte sind nicht identisch mit Liga-Punkten (FR-POINTS-1 berechnet Liga-Punkte aus Platzierung × Faktor) — sie steuern nur die Sortier-Reihenfolge innerhalb des Turniers.

OD-M5-01 und OD-M5-02 haben drei bzw. vier Optionen diskutiert. Dieser ADR fixiert die Wahl.

## Entscheidung

### 1. Tiebreaker-Reihenfolge: Buchholz → Direct-Encounter → Random (Seed)

Bei Score-Gleichstand sortiert `SwissSystemStrategy` in dieser Reihenfolge:

1. **Buchholz-Summe** absteigend — Σ Scores aller bisherigen Gegner.
2. **Direct-Encounter** — wer hat im direkten Aufeinandertreffen gewonnen.
3. **Random** mit Seed `hash(tournament_id || round_number || participant_id)` — deterministisch reproduzierbar.

**Begründung**:

- Kubb-WM-Konvention nutzt keine Sonneborn-Berger-Wertung; Schach-Idiom ist in Kubb nicht etabliert.
- Direct-Encounter ist intuitiv für Spieler ("ihr habt gegeneinander gespielt, der Sieger steht vor") und algorithmisch trivial.
- Seed-basiertes Random hält Tests deterministisch und erlaubt einem Veranstalter, ein Pairing reproduzierbar nachzuvollziehen.

Sonneborn-Berger als optionaler Sekundär-Tiebreak bleibt als Konfig-Flag im `BuchholzCalculator` reserviert (Architektur §3, Zeile 22) — Default-AUS, kein UI-Toggle in M5.

### 2. Match-Punkte-Default: 3-1-0, pro Turnier konfigurierbar

`LeaguePointsEngine` und `SwissSystemStrategy` lesen das Match-Punkte-Schema aus der Turnier-Konfiguration. Default-Tabelle:

| Ergebnis      | Punkte |
| ------------- | ------ |
| Sieg          | 3      |
| Unentschieden | 1      |
| Niederlage    | 0      |

Konfigurierbar pro Turnier im Wizard-Schritt "Liga & Saison" als Drei-Felder-Eingabe `match_points_win`, `match_points_draw`, `match_points_loss` (NOT NULL, Default-Werte oben).

**Begründung**:

- 3-1-0 ist international etabliert (Fussball, Schach in vielen Verbänden) und passt zur Spreizung, die Buchholz braucht, um wirksam zu trennen.
- Konfigurierbarkeit erlaubt EKC-Style (1-1-1, Anwesenheitspunkt) und Vereins-Reglemente ohne Schema-Bruch.
- Match-Punkte sind orthogonal zu FR-POINTS-1 Liga-Punkten — kein Konflikt mit der Saison-Aggregation.

## Alternativen

### A — FIDE-Klassik mit Sonneborn-Berger (OD-M5-01 Option A)

Verworfen: in Kubb nicht etabliert, erhöht Test-Aufwand ohne realen Mehrwert.

### B — Nur Buchholz + Random ohne Direct-Encounter (OD-M5-01 Option C)

Verworfen: Direct-Encounter ist günstig (eine zusätzliche Sortier-Stufe) und wesentlich besser kommunizierbar als ein Random-Wurf.

### C — 1-1-1 Anwesenheitspunkt-Schema (OD-M5-02 Option C)

Verworfen als Default: macht Buchholz wirkungslos (alle haben fast gleiche Scores). Bleibt als Konfig-Option erreichbar.

### D — 2-1-0 Klassik-Schach (OD-M5-02 Option B)

Verworfen als Default: 3-1-0 ist dominanter in modernen Sport-Reglementen.

## Konsequenzen

### Positiv

- Tests sind deterministisch — `SwissSystemStrategy`-Goldfile-Tests bleiben stabil.
- Veranstalter können EKC-/Vereins-Schemata abbilden, ohne dass M5 ein zweites Code-Pfad-System nötig macht.
- Sonneborn-Berger bleibt als Konfig-Flag-Erweiterung greifbar, falls eine Liga das später fordert.

### Negativ

- Drei zusätzliche Spalten `match_points_*` in `tournaments` (oder als JSON in `format_config`); Wizard-Step braucht Validierung (Win ≥ Draw ≥ Loss).
- Spieler-Edukation nötig: "Match-Punkte sind nicht eure Liga-Punkte" — UI-Tooltip im Wizard und im Schluss-Standings-Screen.

### Neutral

- Wenn später eine Liga Sonneborn-Berger fordert, ist das Konfig-Flag plus ein zusätzlicher Sortier-Schritt — keine neue Migration.

## Test-Strategie

- **Unit-Tests** (`packages/kubb_domain/test/tournament/pairing/swiss_system_test.dart`): Golden-File-Tests mit Seed-fixierten Pairings über 5–9 Runden, 8/16/32 Teilnehmer.
- **Property-Tests** (`BuchholzCalculator`): Buchholz ist monoton bzgl. Gegner-Score; Reversal-Edge-Cases.
- **Wizard-Validierung**: Win > Draw und Draw ≥ Loss erzwungen; pgTAP-Test auf CHECK-Constraint.
