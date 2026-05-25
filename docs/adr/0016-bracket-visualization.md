# ADR-0016: Bracket-Visualisierungs-Widget

- **Status**: Accepted
- **Date**: 2026-05-25
- **Depends on**: ADR-0001, ADR-0002, ADR-0008, ADR-0015
- **Bezug**: `docs/plans/m2-ko-bracket/architecture.md` §3.3, §6, OD-M2-01

## Context

Milestone M2 verlangt eine Bracket-Visualisierung für die Single-Elimination-KO-Phase (FR-PUB-6) und für das Hybridformat `round_robin_then_ko`. Das Widget rendert:

- Spalten pro KO-Runde (Halbfinale, Finale, ggf. Spiel-um-Platz-3).
- Match-Boxen pro Paarung mit Teilnehmer-Namen, Seed und Match-Status.
- Verbindungslinien zwischen Match-Boxen (Sieger fliesst ins Folge-Match).
- Optionale separate Spalte für das Spiel-um-Platz-3 rechts vom Finale.
- Tap-Handler auf jede Match-Box, die zum bestehenden `tournament_match_detail_screen.dart` führt.
- Editier-Modus für Pairing-Override vor Match-Start (FR-PAIR-7) — als Tap-Dialog.

Das Widget wird sowohl im Veranstalter-Flow (`/<id>/bracket`) als auch in der öffentlichen Zuschauer-Sicht (Anon-Key) gezeigt.

Anforderungen:
- Responsiv (Mobile, Tablet, Desktop, Web).
- Konsistent mit `kubb_tokens`-Design-System (ADR-0008).
- Touch-Targets ≥ 48 px (NFR-UX-1 / `KubbTokens.touchMin`).
- Performant bei bis zu 64-Teilnehmer-Brackets (63 Match-Boxen + Connectoren).
- Wartbar — die Streaming-Sicht (FR-PUB-10, KANN nach M5) wird ein Variant brauchen.
- BYE-Slots (FR-FMT-11) und Spiel-um-Platz-3 (FR-FMT-1) müssen first-class darstellbar sein.

## Decision

CustomPainter from scratch.

Layout-Math wandert als Pure-Function nach `packages/kubb_domain/lib/src/tournament/bracket_layout.dart` und verwendet eigene `BoxRect`/`Point`-Records statt Flutter-Typen (`Rect`/`Offset`), damit das Flutter-Import-Verbot im Domain-Package erhalten bleibt (ADR-0002). Die Presentation lebt in `lib/features/tournament/presentation/bracket/`:

- `BracketCanvas` (ConsumerWidget) als Root: `InteractiveViewer` für Pan/Zoom, darunter ein `Stack` mit `Positioned`-`KubbMatchCard`-Widgets, dazu ein `CustomPaint`-Layer ausschliesslich für die Connector-Linien.
- Tap-Hit-Test, Tap-Navigation (`context.go`) und Live-Highlight (`currentMatchProvider`) laufen über echte Widgets — keine Painter-Hit-Test-Workarounds.
- `KubbMatchCard` konsumiert `KubbTokens` direkt (`meadow500`, `touchMin=48`, `radiusLg`), `InkWell` für Tap, `Semantics` first-class.
- `BracketConnectorPainter` mit `shouldRepaint`-Optimierung: Layout-Hash plus separater Repaint-Listenable für Highlight, damit Live-Highlight nicht das ganze Connector-Layer neu malt.

Dieser Schnitt erfüllt drei Constraints, die keine der evaluierten Libraries gleichzeitig erfüllt: Tactical-DDD-Konformität (ADR-0001/0002, Layout-Math testbar via glados ohne Flutter-Dep), Design-System-Disziplin (ADR-0008, Tokens werden direkt konsumiert statt gegen Library-Defaults gewrappt) und Web/WASM-Null-Risiko (ADR-0015, nur Standard-Flutter-Primitiven).

## Alternatives considered

### A — `flutter_tournament_bracket` (Pub.dev)

Pub-Score 160/160, 22 Likes, 18 Monate kein Release. Verworfen: BYE-Support ist offenes Issue #4 (seit Dez 2024), Side-Bracket für Spiel-um-Platz-3 ist offenes Issue #5 (seit Okt 2025). Genau unsere zwei Pflicht-Features fehlen.

### B — `tournament_bracket` (Pub.dev)

0.0.4, 3 Likes, 3 Jahre kein Commit, Null-Safety-Status unklar. Verworfen: faktisch abandoned, `touchable`-Transitive-Dep mit eigenem Maintenance-Risk.

### C — `graphview` als Bracket-Renderer

508 Likes, verified Publisher, generischer Tree-Renderer. Verworfen: README sagt explizit "works excellent with small graphs" — kein Beleg für 64-Team-Brackets. Bracket-typische rechtwinklige Connectors sind kein Default, brauchen Custom-Edge-Renderer — der LOC-Vorteil schmilzt auf ~200–350 LOC Mapper + Edge-Code zusammen.

### D — `graphite`

186 Likes, letzter Release März 2025, generischer Direct-Graph-Renderer. Verworfen: gleiche `touchable`-Transitive-Dep wie B, Bracket-Semantik (Round, Seed, Bye, Third-Place) bleibt komplett Eigen-Mapping, Web-Support in README nicht belegt.

### E — Serverseitig generiertes SVG via `flutter_svg`

Verworfen: Tap-Interaktivität pro `<g>` umständlich, Layout-Anpassungen ohne Server-Roundtrip unmöglich, Overengineering für M2.

## Consequences

- M2.3-T2 wird ein L-Task statt M-Task (~3 Tage Mobile + Tablet/Desktop).
- Keine neue Pub.dev-Abhängigkeit in `pubspec.yaml`. Stack-Decision-Trigger aus ADR-0001 entfällt.
- Widget-Pflege bleibt im Haus, Risiko von externer Drift entfällt.
- Streaming-Sicht in M5+ kann das Widget mit anderem Layout-Parameter wiederverwenden.

Implementation Notes (gehen 1:1 in die M2.3-Tasks):

- **Domain-Layer** (`packages/kubb_domain/lib/src/tournament/bracket_layout.dart`): Pure-Function `BracketLayout` mit eigenen Records `BoxRect`/`Point`. `BracketEntry.isBye` first-class. Spiel-um-Platz-3 als optionaler Side-Branch im Layout-Output (separates Box-Set mit eigenen Connectoren zu beiden SF-Verlierern).
- **Property-Tests** via glados über Team-Counts 1..64 im Domain-Package.
- **Goldens** via `golden_toolkit` für 4/8/16/32/64-Team-Brackets inkl. BYE- und Side-Branch-Varianten.
- **Viewport-Culling** im Painter ab 32-Team-Brackets (Connectoren in `canvas.clipRect`).
- **Semantics** pro `KubbMatchCard` plus `semanticsBuilder` am Painter — nicht nachträglich draufgeschraubt.
- **Live-Highlight**-Animation via `AnimatedBuilder` über `currentMatchProvider`-Listenable, separater Layer im Painter.

Scale-Impact-Notiz (Tier 1 per `tech-lead.md`): Bracket > 32 Teams, Performance-Budget **p95 < 16 ms first-paint** als Tester-Task vor Implementation-Start.

## Reference: Committee Decision Doc

`/tmp/kubb_app/committee/bracket-visualization-flutter/decision.md`
