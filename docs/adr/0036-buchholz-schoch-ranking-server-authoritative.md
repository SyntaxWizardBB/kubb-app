# ADR-0036: Buchholz und Schoch-Ranking server-autoritativ; Dart bleibt Heuristik + Test-Truth

- **Status**: Proposed
- **Date**: 2026-06-22
- **Bezug**: `docs/plans/schoch-stage-graph/architecture.md` §8; `docs/specs/schoch-swiss-pairing-buchholz-spec.md`; ADR-0030 (Stage-Graph-Framework), OD-M5-04

## Kontext

Buchholz/Swiss liegt doppelt vor: testbar in `kubb_domain` (heute nicht in `lib/`
verdrahtet) und live in SQL (`tournament_stage_ranking`, das Buchholz bewusst
weglässt). Ein Dart-only-Fix ändert das gespielte Verhalten nicht; ein
SQL-only-Fix trifft die Golden-Tests nicht.

## Entscheidung

Der Server bleibt autoritativ für Live-Standings, Cut und Routing — die
SQL-Schoch-Rangfolge wird um den korrigierten Buchholz (Formel §5) ergänzt. Die
Dart-Domain bleibt die getestete Source-of-Truth der Formel (Golden-Dataset) und die
Heuristik-Quelle für die Paarung; der Client schlägt Paarungen vor, der Server
validiert (analog OD-M5-04). Jede Ranking-Änderung trifft beide Pfade in einem
Milestone, mit Paritäts-Test gegen dieselben Soll-Werte.

## Alternativen

- **Nur Dart, Server ruft Dart nicht.** Verworfen: der Live-Cut bliebe spec-widrig.
- **Nur SQL, Golden-Tests gegen SQL.** Verworfen: keine pure-Dart Property-Tests,
  Bounded-Context-Bruch.
- **Buchholz komplett in eine Edge-Function auslagern.** Verworfen: neue
  Infrastruktur, kein Mehrwert gegen plpgsql.

## Konsequenzen

Doppelte Pflege der Formel (Dart + plpgsql) mit Paritäts-Test als Sicherung. Der
Live-Schoch-Cut wird spec-konform. `tournament_stage_ranking` ändert sich für
Schoch-Stages rückwirkend — bestehende Daten sind zu prüfen.
