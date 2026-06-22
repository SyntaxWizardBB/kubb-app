# ADR-0035: Vorrunden-Rangfolge aus dem Stage-Typ ableiten (nicht frei konfigurierbar)

- **Status**: Proposed
- **Date**: 2026-06-22
- **Bezug**: `docs/plans/schoch-stage-graph/architecture.md` §8; `docs/specs/vorrunde-ranking-spec.md`; ADR-0024 (Tiebreaker/Punkte), ADR-0030 (Stage-Graph-Framework)

## Kontext

Heute gibt es eine globale `tiebreaker_order` pro Turnier, und der SQL-Cut hängt
überall pauschal Buchholz/H2H/kubb_diff an. Die Vorrunde-Spec verlangt zwei feste,
getrennte Rangfolgen je Vorrunden-Typ und verbietet Buchholz in der Gruppenphase in
**jedem** Pfad — auch als stillen Fallback.

## Entscheidung

Die Vorrunden-Rangfolge wird **strikt aus dem Stage-Typ abgeleitet**: Gruppenphase =
`points -> kubb_difference -> shootout`, Schoch = `points -> buchholz -> shootout`.
Kein User-Override pro Stufe. Dart liefert die Chain über `chainForStageType(type)`;
jede SQL-Ranking-Funktion verzweigt nach Stage-Typ und der pauschale
Buchholz-Fallback entfällt für `group_phase`.

## Alternativen

- **Frei konfigurierbare Chain pro Stufe.** Verworfen: lädt genau die
  Spec-Verletzung wieder ein, die der Owner bewusst ausschliesst, und braucht
  zusätzliche UI.
- **Globale Chain beibehalten und nur den Default ändern.** Verworfen: trennt die
  Typen nicht, die Gruppenphase behielte Buchholz im Fallback.

## Konsequenzen

Der Setup-Wizard exponiert die Vorrunden-Rangfolge nicht mehr als freie Wahl —
weniger UI, weniger Fehlbedienung. Bestehende Turniere mit abweichender
`tiebreaker_order` ändern ihr Cut-Verhalten; der Migrationspfad für laufende
Turniere ist zu prüfen. Die Chain wird pro `StageNode` aus dem Typ bestimmt, nicht
persistiert — keine zusätzliche Spalte.
