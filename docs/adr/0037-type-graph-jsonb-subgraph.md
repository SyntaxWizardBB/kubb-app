# ADR-0037: Typ-Graph (Ebene 2) als jsonb-Sub-Graph in StageNode.config

- **Status**: Proposed
- **Date**: 2026-06-22
- **Bezug**: `docs/plans/schoch-stage-graph/architecture.md` §8; `docs/specs/stage-graph-and-stage-type-modeling-spec.md`; ADR-0030 (Stage-Graph-Framework)

## Kontext

Das Feld/Runde/Sieger-Verlierer-Modell einer Stufe (Ebene 2) fehlt. Die Spec lässt
offen, ob es als jsonb-Sub-Graph in `StageNode.config` oder als eigenes
Tabellen-/Domain-Set lebt. Die Wahl prägt Serialisierung, Validierung, Engine und
Template-Format.

## Entscheidung

Das Modell wird als eigene, pure Domain-Struktur (`stage_type_graph.dart`) gebaut und
als **jsonb-Sub-Graph in `StageNode.config`** serialisiert. Es folgt 1:1 dem
Stage-Graph-Vorbild (immutable, wire-stabile `toJson/fromJson`, sealed Edge mit
`kind`-Diskriminator). Templates speichern den Sub-Graphen als Teil der Node-Config —
teilnehmer-agnostisch, ohne zweite Tabellen-/RLS-Schicht.

## Alternativen

- **Eigene Tabellen `stage_type_round` / `stage_type_field` / `stage_type_field_edge`.**
  Verworfen für Phase 1: doppelte RLS, Join-Komplexität, das Template-Format wird
  schwerer; vertretbar erst wenn Felder serverseitig quergeprüft werden müssen.
- **Felder implizit aus der Teilnehmerzahl generieren ohne persistiertes Modell.**
  Verworfen: bricht Editor-Parität und Summary-Vollständigkeit.

## Konsequenzen

Ein konsistentes Serialisierungs-Muster über beide Ebenen. Die Validierung und der
Materializer lesen aus der Node-Config. Wachstumsgrenze: sehr grosse Typ-Graphen
blähen die jsonb-Config; bei Bedarf später auf Tabellen migrierbar, da die
Domain-Struktur die Persistenz kapselt.
