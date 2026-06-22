# ADR-0038: Seeding-Quelle `random` mit persistiertem Seed; Pool-Verteilung auf Snake

- **Status**: Proposed
- **Date**: 2026-06-22
- **Bezug**: `docs/plans/schoch-stage-graph/architecture.md` §8; `docs/specs/stage-seeding-spec.md`; ADR-0019 (Pool-Phase), ADR-0030 (Stage-Graph-Framework), `docs/specs/schoch-swiss-pairing-buchholz-spec.md`

## Kontext

`StageSeedingSource` kennt kein `random`; Zufall existiert heute nur als
Pool-Verteilungsstrategie (snake/seeded/random). Die Seeding-Spec verlangt eine
Seeding-Quelle `random` (deterministisch via Seed) für Vorrunde und KO und reduziert
die Pool-Verteilung auf Snake — Zufalls-Gruppen entstehen aus Quelle = Zufall +
Snake, nicht aus zwei Zufalls-Schaltern.

## Entscheidung

`random('random')` wird zu `StageSeedingSource` ergänzt. Der Seed wird **einmal bei
Stufenstart** gezogen und persistiert; gleicher Seed -> gleiche Setzliste
(Fisher-Yates, geteilt zwischen Dart-Vorschau und plpgsql-Materialisierung,
Parity-Test). Die SQL-CHECK-Constraint wird additiv geweitet. Die Pool-Verteilung
bietet im UI nur noch Snake; `random/seeded` bleiben als gespeicherte Werte
abwärtskompatibel lesbar (Fallback -> Snake), werden aber nicht mehr angeboten und
der Draft-Default wird Snake.

## Alternativen

- **Seed bei jedem Aufruf neu würfeln.** Verworfen: bricht die Reproduzierbarkeit
  und die stabile Schoch-Startnummer.
- **Enum-Wert `random/seeded` hart aus `PoolGroupingStrategy` löschen.** Verworfen:
  breiter Blast-Radius über Draft/Controller/Wizard/ARB/plpgsql/Tests, alte Templates
  brechen.
- **`random` nur für den Stage-Graph-Pfad, nicht klassisch.** Offen, Owner-Entscheid
  §9.

## Konsequenzen

Eine einzige Zufallsquelle, sauberes mentales Modell. Der Seed wird zur stabilen
Startnummer für Schoch (B1). Alte Drafts mit `seeded`-Verteilung verhalten sich nach
dem Fallback wie Snake — das Verhalten ist gegen Bestandsdaten zu testen.
