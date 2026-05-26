# Kubb Domain Note: Spiel um Platz 3

- **Stand**: 2026-05-26
- **Slug**: spiel-um-platz-3
- **Quellen**:
  - CH-Regelwerk v1.11 (S. 6 "Turniermodus", S. 12 "Punkteverteilung") — `docs/rules/kubb_ch_regelwerk.pdf`
  - Spec FR-FMT-1 — `docs/specs/tournament-mode-spec.md:244`
  - Domain-Stub — `packages/kubb_domain/lib/src/tournament/bracket.dart:42`
  - Knowledge-Base + Synthesis — `/tmp/kubb_app/kubb-knowledge/spiel-um-platz-3-schweiz/`
  - SM Team 2024/2025 — <https://kubbtour.ch/turniere-detail.php?tid=16>, <https://kubb.live/sm-team-2024/>
  - Kubbtour Masters — <https://kubbtour.ch/turniere-detail.php?tid=13>
  - EKC 2019 Bronze-Match-Bericht — <https://kubbtour.ch/index.php?articleId=134&op=ViewArt>
  - DM Deutschland (DDM/DEM) — <https://www.dkubbb.de/event/deutsche-meisterschaft/>, <https://www.kubb-sh.de/ablauf-regeln-ddm-und-dem/>
  - US National (kontrastierendes Triple-Bracket-Modell) — <https://www.usakubb.org/2026-u-s-championship>

## Frage

Wird das Spiel um Platz 3 bei Schweizer Kubb-Turnieren standardmässig gespielt? Wie soll kubb_app den Default behandeln?

## Empfehlung (Synthesis + Owner-Entscheidung)

**Hybrid-Default** via neuer Spalte `tournaments.league_eligible bool NOT NULL DEFAULT false`:
- Veranstalter markiert im Wizard früh "Dieses Turnier wertet für die Liga".
- Bei `league_eligible = true` setzt der Wizard `with_third_place_playoff = true` als vorgeschlagenen Default (entspricht SM/Masters/EKC-Empirie).
- Bei `league_eligible = false` bleibt der Default `false` (defensiv, Regelwerk schweigt, freie Turniere brauchen Bronze nicht zwingend).
- Veranstalter kann den Default in beiden Fällen explizit overriden.

Code-Default in `bracket.dart:42` bleibt `false` als technischer Fallback. Synthesis-Tally war 2:1 für Default = an (C); Owner hat den Hybrid gewählt, um die App-Positionierung nicht festzulegen.

## Begründung

- **Empirie**: SM Team 2024/2025, Kubbtour Masters (analoge Regelung S. 14 Regelwerk), EKC, DM Deutschland (DDM + DEM) spielen Bronze als Standard. Nur US-Format (Triple-Bracket Championship/Silver/Bronze) weicht ab.
- **Liga-Punkte-Differenz**: Rangfaktoren 0.65 (Rang 3) vs. 0.5 (Rang 4) → bei 20-Team-Hauptturnier ca. 22.5 Kubbtour-Punkte Differenz zwischen Halbfinal-Verlierern. Bei SM entsprechend mehr.
- **CH-Regelwerk v1.11 schweigt** zum Spiel um Platz 3 in der Modus-Sektion (S. 6) und in der Punkteverteilung (S. 12). Es ist reine Organisations-/App-Konfiguration.
- **FR-FMT-1**: Optionalität ist Spec-Pflicht ("mit oder ohne Spiel um Platz 3") — Always-On wäre Spec-Verletzung.
- **Asymmetrische Fehlerkosten**: Liga-relevantes Turnier ohne Bronze → systematischer Liga-Punkt-Fehler und Verbandsdispute. Freies Turnier mit unnötigem Bronze → ein zusätzliches Match, harmlos.

## Edge Cases / offene Punkte

- **Forfeit-Pfad** bei kurzfristiger Absage (Müdigkeit, Verletzung): Walkover-Behandlung im `tournament_advance_ko_winner`-Trigger — nicht-antretender Halbfinal-Verlierer verliert mit Standard-Set, Gegner gewinnt Bronze. Im CH-Regelwerk nicht explizit geregelt, übliche DACH-Praxis abgeleitet aus Tournament-Berichten.
- **Nachträgliche Deaktivierung bei Zeitnot**: Override-Aktion auf Tournament-Detail-Screen mit mandatory reason für Audit-Trail.
- **Best-of-Länge für Bronze**: oft kürzer als Halbfinale (Stamina-Realität nach frischer Niederlage), separat konfigurierbar — nicht an Halbfinale-Bo gekoppelt.
- **Tiebreaker-Chain für Rang 3 vs. 4** bei `withThirdPlace = false`: muss deterministisch sein, sonst willkürliche Liga-Punkt-Vergabe. Reihenfolge in `TiebreakerChain` (siehe `packages/kubb_domain/lib/src/tournament/tiebreaker.dart`) fixieren.
- **Bronze parallel zum Finale**: eigene Pitch-Zuteilung. Sieger des Bronze-Matches verpasst potenziell die Siegerehrung — UI-Hinweis im Scheduler.
- **Knowledge-Gap**: Forfeit-Handhabung im Bronze nicht regelwerk-belegt; VM i Kubb dokumentiert Bronze-Match nicht explizit im Reglement; Cantonal-Cup-Praxis ist nicht zentralisiert dokumentiert.

## Folge-Aktionen

- **M2.1**: `KoPhaseConfig.withThirdPlacePlayoff` aktiv verdrahten (heute `// ignore: avoid_unused_constructor_parameters` in `bracket.dart:41`).
- **M2.1**: Tiebreaker-Chain-Determinismus für Rang 3 vs. 4 bei `withThirdPlace = false` als Sub-Task (Kriterien-Reihenfolge fixieren).
- **M2.2**: Neue Spalte `tournaments.league_eligible bool NOT NULL DEFAULT false` in Migration `20260601000010_tournament_ko_phase.sql`.
- **M2.2**: `tournament_advance_ko_winner`-Trigger mit Walkover-Behandlung für Halbfinal-Forfeits und Bronze-Befüllung bei `with_third_place_playoff = true`.
- **M2.3**: Setup-Wizard "Liga-relevant"-Frage früh (vor KO-Konfiguration) plus dynamisch abgeleiteter Bronze-Default.
- **M2.3**: Override-Aktion "Bronze nachträglich aktivieren/deaktivieren" mit mandatory reason.
- **M2.3**: Bracket-Vis-Doppel-Layout (mit/ohne Bronze-Slot rechts neben dem Finale).
- **Tests**: Property-Tests via `glados` für beide Pfade (`withThirdPlace = true` und `= false`); pgTAP-Tests für `tournament_advance_ko_winner` in beiden Varianten plus Walkover-Pfad.
- **M5 (out of M2 scope)**: Liga-Punkte-Anbindung von Rang 3/4 — bestätigt das Rang-3-vs-4-Determinismus-Requirement aus M2.1.
