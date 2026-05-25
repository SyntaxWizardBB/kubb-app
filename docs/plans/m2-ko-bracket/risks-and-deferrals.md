# M2 — KO-Bracket — Risiken und Deferrals

> Status: Entwurf
> Datum: 2026-05-25

## Risiken pro Sub-Milestone

### M2.1 — Pure Domain

**R-M2.1-1: Spiel-um-Platz-3 verändert die Bracket-Datenstruktur invasiver als gedacht**

Das vorhandene `Bracket`-Wertobjekt rechnet aktuell mit einer linearen Folge `BracketRound[0..N]` — Halbfinale → Finale. Das Spiel-um-Platz-3 sitzt strukturell parallel zum Finale, nicht davor oder danach. Das saubere Modellieren über das geplante `BracketPhase`-Enum (`winners`, `thirdPlace`, `final_`) ist die richtige Lösung, aber alle existierenden Tests in `bracket_test.dart` müssen aktualisiert werden — die Tests rechnen heute mit der `rounds[i]`-Linearität.

**Mitigation**: M2.1-T1 (Tests first) zwingt zu früher Auseinandersetzung. Bestehende Tests aktualisieren, nicht neu schreiben.

**R-M2.1-2: BYE-Verteilung bei ungeradem Qualifier-Count**

Wenn OD-M2-05 zugunsten "beliebige Anzahl Qualifier" entscheidet, hat der Generator Edge-Cases wie 5, 6, 9, 10, 11 Qualifier. Die existierende `singleElimination`-Implementation füllt zwar auf Zweierpotenz auf, aber die Property-Tests müssen explizit pathologische Fälle abdecken (z.B. 9 Qualifier → 7 BYEs an Top-7 → 2 Matches in Runde 1).

**Mitigation**: `glados`-Property-Tests mit Eingabegrössen 2..32, kontinuierlich verifizieren dass die Top-Seeds tatsächlich BYEs bekommen (FR-FMT-11).

### M2.2 — Server + RPCs

**R-M2.2-1: plpgsql-Spiegelung der Bracket-Generation driftet ab**

Wenn OD-M2-02 zugunsten Server-Authority entscheidet, muss `tournament_start_ko_phase` die `Bracket.singleElimination`-Logik in plpgsql nachbauen. Zwei Implementationen derselben Funktion in zwei Sprachen sind eine klassische Drift-Quelle.

**Mitigation**: Beidseitige Tests gegen denselben Erwartungs-Output (z.B. JSON-Vergleich des generierten Brackets bei festen Inputs). Bei OD-M2-02 → B (Client-Authority) entfällt das Risiko komplett.

**R-M2.2-2: AFTER-UPDATE-Trigger erzeugt Race mit dem Konsens-Protokoll**

Der bestehende M1-Konsens-Pfad `tournament_propose_set_score` macht ein UPDATE auf `tournament_matches.status` (von `awaiting_results` auf `finalized` bei Konsens). Der geplante `tournament_advance_ko_winner`-Trigger reagiert auf genau dieses UPDATE und schreibt das nächste Match. Wenn beide Spieler nahezu zeitgleich proposeSetScores rufen, wird der Trigger womöglich vor dem letzten Versuch ausgeführt.

**Mitigation**: Trigger-Bedingung muss `OLD.status != 'finalized' AND NEW.status = 'finalized'` prüfen (nur State-Transition zu finalized triggert). pgTAP-Test für genau diesen Edge-Case.

**R-M2.2-3: Forfeit / No-Show im KO bricht die Sieger-Fortschreibung**

FR-MATCH-7 und FR-MATCH-8: bei No-Show wird das Match mit Forfeit-Score automatisch entschieden. Im Round-Robin egal, im KO bricht das die Sieger-Fortschreibung nicht — aber der Trigger muss `winner_participant` korrekt aus einem Forfeit-Match lesen können.

**Mitigation**: In M2.2-T4 explizit Forfeit-Pfad mittesten. Forfeit-Logik selbst bleibt M3+ (nicht im M2-Scope), aber die Datenmodell-Kompatibilität wird im Trigger sichergestellt.

### M2.3 — UI

**R-M2.3-1: Bracket-View auf Mobile bei 16+ Teilnehmern unübersichtlich**

16 Teilnehmer = 4 Runden = bis zu 8 Match-Boxen in Runde 1. Auf 360px-Display bedeutet das horizontal scrollen über 800–1000 logische Pixel. Vertikal kann es eng werden.

**Mitigation**: Mobile-First-Layout, Minimum-Touch-Target 60×60 (NFR-UX-1), horizontal Scroll mit visuellem Hinweis. 32+ Teilnehmer-Brackets sind ein Tablet-Use-Case und werden auf Mobile als "lange Vertikal-Liste" gerendert (eine Fallback-View, kein Bracket-Diagramm). Spec-konform per FR-PUB-6 ("Bracket-Visualisierung in KO-Phase" — kein verpflichtendes Diagramm-Layout für jeden Screen).

**R-M2.3-2: Setup-Wizard wächst zu sechs Schritten — Abbruch-Quote steigt**

Vier Schritte in M1 waren ein guter Kompromiss. Sechs Schritte bei jedem `round_robin_then_ko`-Setup sind viel.

**Mitigation**: Dynamic-Steps-Logik — wer Round-Robin-only wählt, sieht weiterhin nur vier Schritte. Wer Hybrid wählt, akzeptiert die zwei zusätzlichen Schritte. Schritt 6 (Tiebreaker) mit Preset-Empfehlung (OD-M2-03 → C) macht den Schritt einen Klick lang für 90 % der Veranstalter.

**R-M2.3-3: Seeding-Editor und Bracket-View teilen kein Drag-and-Drop-Modell**

Im Seeding-Editor (Vor-KO) wird drag-reordered. Im Bracket-View (nach KO-Start) gibt es Pairing-Override (FR-PAIR-7), das aber als Dialog "Tap → Tausche zwei Slots" implementiert wird, nicht als Drag. Inkonsistenz für den Veranstalter.

**Mitigation**: Bewusste Entscheidung — Reorder im Seeding ist linear (Liste), Tausch im Bracket ist paarweise (zwei Slots). Zwei verschiedene Operationen, zwei verschiedene Interaktionsmuster ist okay. In der DE-l10n explizit "Reihenfolge ändern" vs. "Paarung tauschen" trennen.

### Übergreifend

**R-M2-G1: M2 hängt an Owner-Reviews zwischen Sub-Milestones**

Drei Sub-Milestones, drei potenzielle Pause-Punkte für Owner-Abnahme. Wenn der Owner zwischen M2.1 und M2.2 zwei Wochen Pause macht, läuft die Cadence aus.

**Mitigation**: Sub-Milestones sind klein (jeweils 2–4 Tage), Demobarkeit ist nach M2.3 gegeben. Owner-Abnahme ideal nur einmal am Ende von M2 (mit Zwischen-Checkpoints für M2.1 und M2.2 als "approve to proceed").

**R-M2-G2: Tournament-Spec hat noch nicht-finalisierte Detail-Fragen**

FR-CFG-12 (Forfeit-Buchholz-Verhalten) ist Spec-konform, aber praktisch nirgendwo durchgespielt. Bei einem `round_robin_then_ko` mit einem Forfeit in der Vorrunde ist die Buchholz-Berechnung der Standings nicht trivial.

**Mitigation**: M2 implementiert die Wizard-Felder und schreibt die Config in die DB. Die echte Forfeit-Buchholz-Logik im Tiebreaker bleibt in M5 (Schweizer-System-Block), wo Forfeit-Edge-Cases ohnehin neu durchdacht werden müssen.

## Was bewusst auf M3+ verschoben wird

| Bereich | FR | Verschoben auf | Grund |
|---|---|---|---|
| Schweizer System + Schoch + Hybride mit Schweizer/Schoch | FR-FMT-3, FR-FMT-4, FR-FMT-6, FR-FMT-7 | M5 | Komplexe Paarungs-Logik, eigener Spike |
| Double Elimination | FR-FMT-9 | nach M5 (KANN) | Spec sagt KANN |
| Shared Tournaments mit Liga-Split | FR-FMT-8 | nach M5 | Hängt an Liga-System |
| Drag-and-Drop-Pairing direkt im Bracket-View | FR-PAIR-7 ext. | M3+ | M2 hat Tap-Dialog-Lösung, voller DnD ist Polish |
| Realtime-Push für Bracket-Updates | FR-PUB-11 | M4 | Polling reicht für M2 |
| Streaming-Sicht (Vollbild-Bracket auf TV-Display) | FR-PUB-10 | nach M5 (KANN) | Spec sagt KANN |
| Liga-Punkte aus KO-Platzierungen | FR-POINTS-1..-18 | M5 | Hängt an Saison-Modell |
| Team-Brackets (statt Einzel) | FR-TEAM-1..-20 | M3 | Bracket-Logik ist agnostisch, Teams kommen vorher |
| Veranstalter-Bewertung post-Turnier | FR-FEEDBACK-1..-7 | nach M5 | Optional |
| Bracket-Edit nach Start (Match neu paaren wenn Spieler ausfällt) | FR-MATCH-8 Variation | M4 | Eng verknüpft mit Live-Management |

## Bekannte Einschränkungen — bleiben aus M1 erhalten

Diese sind nicht M2-spezifisch, sondern Übernahmen:

- **iOS, Web, Linux, Windows-Build**: M2 ist Android-only wie M1 (OD-02 in Tournament-Foundation). Web-Spike sollte vor M2.3-T2 abgeschlossen sein, falls die Bracket-View auch im Browser-Veranstalter-Dashboard funktionieren soll.
- **Push-Notifications**: nicht in M2, kommt M4. KO-Phasen-Start ohne Push-Erinnerung an alle Teilnehmer ist im MVP-Demo-Setting (alle vor Ort) akzeptabel.
- **Realtime**: weiter Polling alle 5 Sekunden. Eine KO-Bracket-Aktualisierung kommt mit ~5 Sekunden Latenz beim Zuschauer an — okay für MVP.
- **Solo-Match-Stats-Privacy**: OD-03 läuft eigenständig, kein M2-Touchpoint.

## Nicht-Risiken (zur Klärung)

- **`tournament_advance_ko_winner` als Trigger statt RPC**: Manche Architekten ziehen RPC-Aufrufe vom Client vor. In diesem Fall ist Trigger besser, weil der Sieger-Fortschritt eine reine Server-Datenmodell-Invariante ist (jeder finalisierte KO-Sieger gehört ins Folge-Match — keine Client-Entscheidung dabei). Diskussion abgeschlossen.
- **plpgsql-Bracket-Generator als "Dual-Source-of-Truth"**: bei OD-M2-02 → B (Client-Authority) entfällt der Punkt komplett. Bei OD-M2-02 → A bleibt das Risiko, ist aber mit pgTAP-Tests gegen Dart-Referenzwerte beherrschbar.
- **Mobile-First-Bracket-View für 32-Teilnehmer-Turniere**: oben als R-M2.3-1 adressiert, Fallback auf Liste klärt das.
