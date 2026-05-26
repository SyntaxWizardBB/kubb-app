# Kubb Domain Note: Qualifier-Count im Hybrid `round_robin_then_ko`

- **Stand**: 2026-05-26
- **Slug**: qualifier-count
- **Quellen**:
  - Spec FR-FMT-11, FR-FMT-5, FR-FMT-10, FR-PAIR-4, FR-PAIR-5, FR-CFG-10, Sektion 5.12 — `docs/specs/tournament-mode-spec.md`
  - ADR-0017 §3 — `docs/adr/0017-ko-phase-semantics.md`
  - Bracket-Implementation — `packages/kubb_domain/lib/src/tournament/bracket.dart` (Zeilen 37–89)
  - Knowledge-Base + Synthesis — `/tmp/kubb_app/kubb-knowledge/qualifier-count-praxis/`
  - SM Team Format — <https://kubbtour.ch/turniere-detail.php?tid=16>
  - ÖUFI Cup (Top-8) — <https://kubbtour.ch/turniere-detail.php?tid=42>
  - DKB "Gedanken zum Turniermodus" — <https://www.dkubbb.de/gedanken-zum-turniermodus/>
  - US National (3-Bracket-Modell) — <https://www.usakubb.org/2026-u-s-championship>
  - Kubb VM Gotland (Nicht-Zweierpotenzen-Praxis) — <https://www.kubbvm.com/en/about-the-kubb-world-championship/>
  - Bracket-Theorie — <https://www.bracketsninja.com/types/single-elimination-bracket>, <https://kb.score7.io/blog/guides/single-elimination-tournament-how-it-works/>

## Frage

Welche Qualifier-Anzahlen lässt kubb_app für `round_robin_then_ko` zu? Nur Zweierpotenzen oder beliebige Top-N mit BYE-Auffüllung?

## Empfehlung (Synthesis + Owner-Bestätigung)

**Option B — Beliebige Top-N mit BYE-Auffüllung an die höchsten Seeds gemäss FR-FMT-11.**

Tally war 2:1 für B (Tournament-Organizer + Rule-Engine-Purist) gegen A (Spieler am Pitch). Owner hat 2026-05-26 bestätigt. Spieler-Sorgen werden nicht überstimmt, sondern als verbindliche UX-Anforderungen kodifiziert.

`KoPhaseConfig.qualifierCount` ist freier Integer-Input (`2 <= qualifierCount <= participantCount`), kein 2^n-Constraint. Bei nicht-2^n füllt `Bracket.singleElimination` auf die nächste Zweierpotenz `next_pow2(N)` auf; die `next_pow2(N) − N` BYEs gehen an die höchsten Seeds via Recursive-Standard-Order — bereits korrekt in `bracket.dart:48–61` implementiert.

## Begründung

- **FR-FMT-11 ist harte Spec-Regel** ("Byes in KO-Runde 1 werden höher gesetzten Teilnehmern zugeteilt") und beschreibt seed-basierte BYE-Allocation. Wenn die Spec BYE-Allocation regelt, sind Nicht-Zweierpotenzen mitgemeint.
- **`bracket.dart` produktiv und getestet**: `next_pow2(N)`-Padding plus BYE-Slots an Top-Seeds via Recursive-Order. Option A würde funktionierenden Code amputieren.
- **ADR-0017 §3 ist Accepted** für Option B.
- **CH-Liga-Praxis ist nicht einheitlich**: ÖUFI Cup fährt Top-8 (kein BYE nötig), SM publiziert nur "die bestplatzierten Teams" ohne fixe Zahl, Kubbtour-Veranstalter entscheiden pro Auflage. Kein verbindliches Schema.
- **Heterogene Veranstalter-Szenarien**: kleine Clubabende mit 9–14 Teams (BYE-Auffüllung normal), grosse Cups wie ÖUFI mit sauberer Top-8 (keine BYEs), Gotland-Style mit ~33 Qualifiern (Nicht-Zweierpotenzen). Option B deckt alle drei ab; Option A schliesst Szenario 1 und 3 aus.
- **Spec-Konsistenz**: Option A würde FR-FMT-11 zu totem Text machen (Regression).
- **Standard-Bracket-Theorie** (bracketsninja, score7) behandelt BYEs als legitimen Seed-Reward — branchenüblich.

## Edge Cases / offene Punkte

- **Spieler-Wahrnehmung am Pitch**: "warum hat Seed 1 ein Freilos?" muss die App aktiv erklären, sonst entsteht am Turniertag Diskussion. UX-Mitigation ist Pflicht.
- **Tagesplanbarkeit**: R1 hat bei nicht-2^n weniger Matches als `next_pow2(N)/2` — Scheduler muss `N − (next_pow2(N) − N)` echte Matches korrekt ausweisen.
- **`KoPhaseConfig` braucht kein zusätzliches Flag** (`allowOddQualifierCount` o. ä.) — `qualifierCount: int` reicht, Verhalten ergibt sich aus bestehender Logik.
- **Knowledge-Gaps**: exakte SM-Qualifier-Zahl der letzten 3 Jahre nicht öffentlich publiziert; CH-Cantonal-Cup-Praxis zu Nicht-Zweierpotenzen nicht zentralisiert dokumentiert; Kubb-VM-Bracket-Mechanik für 33-Team-Finalspel nicht detailliert. Nicht blockierend.
- **Vokabular-Klarstellung FR-FMT-5 ↔ `round_robin_then_ko`**: Spec spricht von "Gruppenphase + KO", Implementation nennt es `round_robin_then_ko` (= FR-FMT-5 mit nur einer Gruppe). In nächster Spec-Iteration vereinheitlichen.

## UX-Anforderungen (verbindlich aus Synthesis)

Diese Anforderungen sind Teil der Resolution, nicht optional:

### Setup-Wizard

- **U1** Qualifier-Count-Feld bleibt freier Integer-Input, kein 2^n-Dropdown.
- **U2** Live-Validation `2 <= qualifierCount <= participantCount`, kein 2^n-Constraint.
- **U3** Preview-Panel unterhalb des Felds: "Bracket-Grösse: `next_pow2(N)`", "Davon `next_pow2(N) − N` BYEs an Seeds 1..K", "Runde 1 hat `N − (next_pow2(N) − N)` echte Matches", konkretes Beispiel.
- **U4** Smart-Default: bei 2^n-Participant-Count → `qualifierCount = participantCount / 2`; sonst nächstgelegene 2^n unter `participantCount`. Veranstalter kann abweichen.

### KO-Phase-Screen

- **U5** BYE-Slots visuell klar als "Freilos" markiert (Icon/Label, nicht nur leer).
- **U6** Tooltip am BYE-Slot: paraphrasierte FR-FMT-11-Erklärung ohne Spec-Jargon.
- **U7** Schedule-View-Hinweis zur tatsächlichen R1-Match-Anzahl.

### Hilfe / Dokumentation

- **U8** In-App-Hilfe-Sektion "Wie funktioniert der KO-Cut?" mit FR-FMT-11-Paraphrase.
- **U9** Begründung "BYEs sind Seed-Reward — international Standard (DKB, ÖUFI, bracketsninja)".

### Domain-Modell

- **U10** `KoPhaseConfig` kein zusätzliches Flag.
- **U11** Optional: `Set<int> recommendedQualifierCounts` für UI-Quick-Picks ({4, 8, 16}) — nicht blockierend.

## Folge-Aktionen

- **M2.1**: `KoPhaseConfig.qualifierCount` Validierung (`2 <= qualifierCount <= participantCount`).
- **M2.3**: Setup-Wizard mit Preview-Panel (U1–U4), KO-Phase-Screen mit BYE-Markierung (U5–U7), In-App-Hilfe (U8–U9). Akzeptanz-Kriterien direkt aus U1–U9 ableiten.
- **Tests**: Property-Test (`glados`) über n ∈ [2, 64] mit Invarianten (U12):
  - R1 hat genau `size/2` Slot-Paarungen (inkl. BYE-Paarungen).
  - BYE-Anzahl = `size − n`.
  - Alle BYEs gegen Seeds 1..(size − n).
  - Seed 1 trifft in R1 nie auf echten Teilnehmer, ausser `n == size`.
- **Tests**: pgTAP-Test (U13) — erwartete R1-Match-Anzahl = `n − (size − n)` bei `size > n`, gespiegelt mit Dart-Property-Test als Drift-Gate.
- **Spec-Folge (nicht M2)**: Vokabular FR-FMT-5 ↔ `round_robin_then_ko` in nächster Spec-Iteration vereinheitlichen.
- **Recherche-Folge (nicht blockierend)**: SM-Qualifier-Zahl der letzten 3 Jahre via direkter Kontakt zu Kubbtour-Veranstaltern klären, falls für spätere Iterationen relevant.
