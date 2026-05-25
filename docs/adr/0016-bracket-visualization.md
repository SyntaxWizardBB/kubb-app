# ADR-0016: Bracket-Visualisierungs-Widget

- **Status**: Proposed
- **Date**: 2026-05-25
- **Bezug**: `docs/plans/m2-ko-bracket/architecture.md` §3.3, §6, OD-M2-01

## Entscheidung

**TBD** — wartet auf Output von `/committee bracket-visualization-flutter` plus Owner-Abnahme.

Vorläufige Empfehlung der Architekten-Vorprüfung: **Option A — eigener CustomPainter**.

## Kontext

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
- Konsistent mit `kubb_tokens`-Design-System.
- Touch-Targets ≥ 60×60 px (NFR-UX-1).
- Performant bei bis zu 32-Teilnehmer-Brackets (5 Runden, 31 Boxen).
- Wartbar — die Streaming-Sicht (FR-PUB-10, KANN nach M5) wird ein Variant brauchen.

## Alternativen

### Option A — Eigener CustomPainter from scratch

`StatelessWidget`, der intern einen `CustomPainter` für Verbindungslinien verwendet und Match-Boxen via `Stack`/`Positioned` platziert. Layout-Berechnung in einer pure-Dart-Helper-Funktion.

- **Pros**:
  - Volle Kontrolle über Layout, Theming, Animationen.
  - Keine externe Abhängigkeit, keine Lib-Lock-In.
  - Direkte Integration in `kubb_tokens` (Primary-Color für Sieger-Pfad, Border-Radius aus Tokens).
  - Spiel-um-Platz-3 als separate Spalte einfach modellierbar.
  - Wiederverwendbar für die spätere Streaming-Sicht ohne Refactor.
- **Cons**:
  - Initialer Aufwand: 1.5–2 Tage Mobile + 1 Tag Tablet/Desktop = ~3 Tage.
  - Edge-Cases bei sehr breiten Brackets (32+) sind eigener Pflege-Aufwand.

### Option B — Pub.dev-Library (z.B. `flutter_bracket_view`, `bracket_widget`)

Eine fertige Library einbinden und konfigurieren.

- **Pros**:
  - Schnellere Initial-Integration (geschätzt 0.5–1 Tag).
  - Weniger eigener Code.
- **Cons**:
  - Nischen-Libs auf Pub.dev haben oft sporadische Maintenance (typisch < 200 Likes, letzter Commit > 12 Monate alt).
  - Theming-Anpassungen mit `kubb_tokens` häufig umständlich (Theme-API limitiert).
  - Spiel-um-Platz-3-Spalte selten supportet — würde Custom-Layout erfordern.
  - Tap-Dialog-Override für FR-PAIR-7 muss durch die Lib-API möglich sein, sonst Fork.
  - Lock-In auf Drittpaket-Datenstruktur, eventuell Mapper-Layer nötig.
  - Maintenance-Risiko: Lib unmaintained → eigener Fork oder Wechsel.

### Option C — SVG-Renderer (`flutter_svg`) mit serverseitig generierten SVG

Server (oder Edge-Function) erzeugt das Bracket als SVG, App rendert mit `flutter_svg`.

- **Pros**:
  - Eine Wahrheit für Bracket-Layout (serverseitig).
  - Wiederverwendbar für Streaming-Sicht und PDF-Export.
- **Cons**:
  - Overengineering für M2.
  - Tap-Interaktivität in SVG umständlich (jeder Tap-Bereich braucht eigene `<g>`-Group).
  - Server-Code-Aufwand (oder Edge-Function-Deployment) für eine Funktion, die clientseitig trivial ist.
  - Layout-Anpassungen ohne Server-Roundtrip nicht möglich.

## Konsequenzen

### Bei Option A (empfohlen):

- M2.3-T2 wird ein L-Task statt M-Task (3 Tage statt 1.5).
- Keine neue Pub.dev-Abhängigkeit in `pubspec.yaml`.
- Widget-Pflege bleibt im Haus, Risiko von externer Drift entfällt.
- Streaming-Sicht in M5+ kann das Widget mit anderem Layout-Parameter wiederverwenden.

### Bei Option B:

- M2.3-T2 wird ein M-Task (1.5 Tage).
- Neue Abhängigkeit in `pubspec.yaml`, Owner-Abnahme der Lib-Wahl nötig (Stack-Decision per ADR-0001).
- Theming-Test in M2.3-T1 muss Konsistenz mit `kubb_tokens` verifizieren.
- Lock-In, Fallback-Plan (eigene Lib) muss dokumentiert sein.

### Bei Option C:

- Server-Aufwand kommt zu M2.2 hinzu (zusätzliche RPC oder Edge-Function).
- M2.3-T2 wird trivial (nur `SvgPicture`), aber Interaktivität separat zu lösen.
- Realistisch nicht für M2-Zeitfenster.

## Tracking

- `/committee bracket-visualization-flutter` läuft parallel — der Output liefert eine technische Bewertung der konkreten Pub.dev-Optionen.
- Nach Committee-Output: Owner-Abnahme dieser ADR.
- Nach Acceptance: M2.3-T1/T2 starten.
