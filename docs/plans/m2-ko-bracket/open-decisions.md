# M2 — KO-Bracket — Offene Entscheidungen

> Status: Entwurf, wartet auf Abnahme
> Datum: 2026-05-25

Folgende Punkte sind vor Implementierungsstart zu klären. Jeder Punkt blockiert wenigstens einen Task aus dem Milestone-Plan.

## OD-M2-01: Bracket-Visualisierung — CustomPainter oder Library? `[resolved]`

**Frage**: Mit welcher Technik bauen wir das Bracket-Visualisierungs-Widget?

**Warum blockierend**: Direkt blockiert M2.3-T2 (Implementation des `BracketView`-Widgets) und damit indirekt T3, T9. Ohne Entscheidung kann die UI-Phase nicht starten.

**Optionen**:
- **A) CustomPainter from scratch** — eigenes Widget mit `CustomPainter` für die Verbindungslinien und `Stack`/`Positioned` für die Match-Boxen. ~1.5–2 Tage für Mobile, +1 Tag für Tablet-/Desktop-Layout.
  - Pros: volle Kontrolle, perfekte Integration in `kubb_tokens`-Design-System, keine Abhängigkeit, exakte Steuerung der Touch-Targets (NFR-UX-1 verlangt 60×60 px).
  - Cons: höherer Initialaufwand, eigene Pflege bei Edge-Cases (sehr breite Brackets, Spiel-um-Platz-3 als Sonderspalte).
- **B) `flutter_bracket_view` o.ä. Pub.dev-Package** — fertige Library nutzen.
  - Pros: schneller fertig (geschätzt 0.5–1 Tag Integration).
  - Cons: Lifecycle vieler dieser Nischen-Libs ist fragwürdig (oft <200 Pub.dev-Likes, sporadische Maintenance), Theming-Anpassungen mit `kubb_tokens` oft umständlich, Spiel-um-Platz-3-Konzept selten supportet, Lock-In auf eine Drittpaket-Datenstruktur.
- **C) Hybrid — CustomPainter für Verbindungslinien, Library für Match-Boxen** — unrealistisch, weil die meisten Libs die Linien gleich mitliefern und nicht extern überschreibbar machen. Wird verworfen.

**Empfehlung (vorläufig, ersetzt sobald Committee zurück ist)**: A — CustomPainter. Begründung: Das Bracket-Widget wird einer der zentralen Touchpoints im Veranstalter-Flow. Ein nicht mehr gepflegtes Drittpaket im kritischen Pfad ist ein zukünftiges Liability. Die +1 Tag Initialaufwand zahlen sich über die Lebensdauer aus. Die spätere Streaming-Sicht (FR-PUB-10) wird ein verändertes Layout brauchen — mit Eigencode trivial nachrüstbar, mit Library evtl. nicht.

**Resolution**: Resolved 2026-05-25 via Committee Vote 3:0 für CustomPainter. Siehe ADR-0016 (Accepted).

## OD-M2-02: Server-Authority oder Client-Authority für Bracket-Generation? `[resolved]`

**Frage**: Wer berechnet das KO-Bracket — der Client (clientseitige `Bracket.singleElimination` in Dart) oder der Server (plpgsql-Spiegelung)?

**Warum blockierend**: Bestimmt den Inhalt von M2.2-T3. Server-Authority bedeutet eine plpgsql-Reimplementation der pure-Dart-Generator-Funktion (zusätzlicher Aufwand, doppelte Wahrheit) und SQL-Tests dafür.

**Optionen**:
- **A) Server-Authority via plpgsql** — `tournament_start_ko_phase` liest Standings serverseitig, generiert das Bracket in plpgsql, schreibt Match-Rows. Pure Dart bleibt für Tests und UI-Vorschau.
  - Pros: kein Race-Condition-Risiko bei zwei parallelen Veranstalter-Geräten, Single-Source-of-Truth ist die DB.
  - Cons: plpgsql-Implementation pflegt eine zweite Wahrheit (Drift zur Dart-Version möglich), pgTAP-Tests aufwendig, Logik ist in zwei Sprachen.
- **B) Client-Authority mit Optimistic Concurrency** — Client berechnet das Bracket in Dart, schickt eine Liste vorbereiteter Match-Rows an `tournament_start_ko_phase`, Server validiert (Anzahl Slots, Konsistenz) und inserted. Bei zwei parallelen Versuchen gewinnt der erste, der zweite bekommt einen Conflict.
  - Pros: eine Wahrheit (`bracket.dart`), weniger Server-Code, einfache Tests.
  - Cons: Server-Validierung muss trotzdem da sein (sonst kann ein bösartiger Client Unsinn schreiben), Race-Condition zwischen zwei Veranstaltern braucht Optimistic-Lock-Mechanik.
- **C) Hybrid mit Lock-Token** — Veranstalter ruft `tournament_lock_phase_transition(id)` auf, bekommt ein Token, generiert Bracket clientseitig, ruft `tournament_start_ko_phase(id, token, matches)` auf. Server validiert Token + Matches.
  - Pros: löst die Race-Condition explizit, Server-Logik bleibt schlank.
  - Cons: zusätzlicher API-Roundtrip, neue Token-Lebenszyklus-Logik.

**Empfehlung (vorläufig)**: B mit serverseitiger Plausibilitätsprüfung. Vom Committee überstimmt — die Server-Plausibilitätsprüfungen reproduzieren faktisch die halbe Bracket-Logik, also lieber direkt vollständig serverseitig generieren und das `tournament_start`-Lifecycle-Pattern weiterführen.

**Resolution**: Resolved 2026-05-26 via Committee Vote 3:0 für **A — Server-Authority via plpgsql**. Confidence high (3× high). Begründung: `tournament_start_ko_phase` ist strukturell eine Lifecycle-Materialisierung wie `tournament_start` (Server schreibt Match-Rows als Folge einer Phasen-Transition). 13 von 18 bestehenden RPCs sind Server-Authority; `_tournament_compute_ekc` ist Präzedenzfall für plpgsql-Spiegelung der Dart-Domain. Konsens-Implementation: `FOR UPDATE` auf `tournaments`-Row, Idempotency-Guard via `ERRCODE 40001`, separater Seeding-Helper `_tournament_compute_ko_bracket(seeds jsonb, third_place bool)` für M5-Wiederverwendung, Dart-Client behandelt `ERRCODE 40001` als idempotente Success-Semantik. Property-Parität-Tests (pgTAP oder Dart-Integration über 8/16/32/64-Sweep) als Merge-Gate gegen Drift Dart ↔ plpgsql. Decision-Doc: `/tmp/kubb_app/committee/server-vs-client-bracket-authority/decision.md`. ADR-0017 §7 wird entsprechend aktualisiert.

## OD-M2-03: Tiebreaker-Reorder-UI — Drag-und-Drop oder Auswahl-Liste? `[committee]`

**Frage**: Wie wählt der Veranstalter die Tiebreaker-Reihenfolge im Wizard?

**Warum blockierend**: Bestimmt Aufwand für M2.3-T4 und beeinflusst l10n.

**Optionen**:
- **A) ReorderableListView** mit allen sieben Tiebreaker-Optionen sichtbar, drag-Reorder, Toggle pro Eintrag (aktiv/inaktiv).
  - Pros: alle Optionen sichtbar, Reihenfolge direkt klar, Standard-Flutter-Widget.
  - Cons: bei 7 Optionen auf Mobile braucht es einen scrollbaren Bereich, Touch-Targets müssen gross genug sein.
- **B) Multi-Select-Dropdown** — der Veranstalter wählt die Tiebreaker als Chip-Liste, neue Auswahl wird hinten angehängt, "X" entfernt einen Eintrag.
  - Pros: kompakter, leichter zu verstehen für Nicht-Turnier-Profis.
  - Cons: weniger flexibel für gezielte Reorder ohne komplette Neu-Auswahl.
- **C) Vordefinierte Presets** + "Custom"-Toggle, der A oder B aktiviert.
  - Pros: 90 % der Veranstalter wählen Standard ("Total Points, Buchholz-H2H, Direktvergleich, Anzahl Siege") und brauchen den Editor nie.
  - Cons: eine zusätzliche Konzept-Ebene (Preset vs. Custom).

**Empfehlung (vorläufig)**: C — Presets ("Standard", "Schweizer-konform", "Custom") als Hauptauswahl, "Custom" enthüllt einen kompakten Reorder-Editor im Stil A. Bringt schnellen Standard-Pfad für die meisten Veranstalter, Vollkontrolle bleibt für Experten.

**Marker**: `[committee]` — UX-Bewertung. Designer im Committee kann beurteilen, ob Presets auf der Schwelle "Junior-Veranstalter versteht das" landen.

## OD-M2-04: Spiel-um-Platz-3 — Optional pro Turnier oder Always-On? `[owner]`

**Frage**: Ist das Spiel-um-Platz-3 immer Teil des KO-Brackets, oder optional konfigurierbar?

**Warum blockierend**: Beeinflusst `KoPhaseConfig`-Datenmodell (mit/ohne Switch), Wizard-Schritt 5 (ein Feld mehr) und die Bracket-Generator-API.

**Optionen**:
- **A) Optional pro Turnier**, Default = aus. Veranstalter aktiviert im Wizard-Schritt 5 explizit.
  - Pros: Standard-Schweizer-Turniere kennen oft kein Spiel-um-Platz-3.
  - Cons: ein UI-Feld mehr.
- **B) Always-On** — jedes Single-Elimination-Bracket hat ein Spiel-um-Platz-3.
  - Pros: trivial, kein UI-Feld.
  - Cons: Spec FR-FMT-1 sagt explizit "mit oder ohne Spiel um Platz 3" — wäre Spec-Verletzung.
- **C) Optional pro Turnier**, Default = an.
  - Pros: häufig bei Liga-Turnieren erwünscht, da das Spiel-um-Platz-3 für Liga-Punkte zählt.
  - Cons: gleicher Aufwand wie A, nur anderer Default.

**Empfehlung (vorläufig)**: A — Default aus. Begründung: Liga-Punkte gibt es erst ab M5 — bis dahin ist das Spiel-um-Platz-3 nur ein zusätzliches Match ohne Auswirkung auf die "echte" Wertung. Wenn Owner für Schweizer-Liga-Praxis "Default an" möchte, ist es eine Zeile Änderung.

**Marker**: `[owner]` — direkt Owner-Entscheidung, weil es eine Default-Konvention für alle künftigen Turniere ist. Auch `[domain]` (Schweizer-Liga-Praxis).

## OD-M2-05: Hybrid `round_robin_then_ko` — Qualifier-Anzahl Constraints? `[resolved]`

**Frage**: Welche Qualifier-Anzahlen lassen wir für `round_robin_then_ko` zu?

**Warum blockierend**: Beeinflusst `KoPhaseConfig.qualifierCount`-Validierung und die Wizard-UI.

**Optionen**:
- **A) Nur Zweierpotenzen** (2, 4, 8, 16, 32) — perfekt befüllbares Bracket ohne BYEs.
  - Pros: einfachste KO-Logik, klares mentales Modell.
  - Cons: Veranstalter mit z.B. 6 Teilnehmern qualifiziert können nicht Top-6 nehmen, müssen Top-4 oder Top-8 wählen.
- **B) Beliebige Anzahl** mit BYE-Auffüllung auf nächste Zweierpotenz — bei Top-6 bekommen Top-2 ein Free-Lot in Runde 1.
  - Pros: Veranstalter-Freiheit, häufig in der Praxis (Top-6 bei 12 Vorrunden-Teilnehmern üblich).
  - Cons: BYE-Verteilung muss korrekt sein (Top-Seeds, FR-FMT-11). Komplizierter UI-Hinweis ("3 BYEs werden an Seeds 1–3 vergeben").
- **C) Zweierpotenzen oder "Alle ins KO"** — entweder klassisch 2/4/8/16 oder das gesamte Teilnehmerfeld qualifiziert sich (also Vorrunde war Rangierung, KO ist die richtige Wertung).
  - Pros: zwei Standard-Pfade, kein BYE-Chaos.
  - Cons: weniger Flexibilität als B.

**Empfehlung (vorläufig)**: B — beliebige Anzahl mit BYE-Auffüllung. Begründung: FR-FMT-11 ist explizit ("BYEs werden höher gesetzten Teilnehmern zugeteilt") — der Spec-Verfasser hat genau diesen Fall im Sinn. Die existierende `singleElimination`-Implementation in `bracket.dart` macht BYE-Auffüllung bereits korrekt.

**Resolution**: Resolved 2026-05-26 via Owner-Bestätigung auf Domain-Tally **2:1 für B** (mit UX-Mitigation). Begründung: ADR-0017 §3 ist bereits Accepted für B, `bracket.dart:48–61` implementiert die BYE-Auffüllung korrekt, FR-FMT-11 bleibt aktiv (Option A würde Spec zu totem Text machen). CH-Praxis ist nicht einheitlich (ÖUFI Cup Top-8 = 2^n; SM publiziert nur "die bestplatzierten Teams"); für gemischte Teilnehmerfelder (9–14 Teams) ist Flexibilität essenziell. Minderheit (Spieler-Vote) wird nicht überstimmt — UX-Sorgen gehen als verbindliche Anforderungen ein: (U1–U4) freier Integer-Input statt 2^n-Dropdown plus Preview-Panel ("Bracket-Grösse: next_pow2(N)", "K BYEs an Seeds 1..K", "R1 hat M echte Matches") plus Smart-Default-Vorschlag; (U5–U7) BYE-Slots visuell als Freilos markiert mit Tooltip-Erklärung und Schedule-View-Hinweis zu R1-Match-Anzahl; (U8–U9) In-App-Hilfe paraphrasiert FR-FMT-11; (U10) `KoPhaseConfig` braucht kein zusätzliches Flag; (U12–U13) Property-Tests glados + pgTAP über n ∈ [2, 64] mit Invarianten zu BYE-Anzahl und Top-Seed-Allocation. Synthesis-Doc: `/tmp/kubb_app/kubb-knowledge/qualifier-count-praxis/synthesis.md`. Domain-Notiz: `docs/domain-knowledge/qualifier-count.md`.

## OD-M2-06: Phase-Wechsel-Validierung — strikt oder mit Force-Override? `[committee]`

**Frage**: Wenn der Veranstalter `tournament_start_ko_phase` aufruft, während noch ein Vorrunden-Match `disputed` ist (kein finaler Score) — was passiert?

**Warum blockierend**: Beeinflusst Server-Validierung in M2.2-T3 und Wizard/Seeding-Editor-UX in M2.3-T6.

**Optionen**:
- **A) Strikt — Block** — RPC wirft 422 `PHASE_NOT_COMPLETE` mit Liste der offenen Matches. Veranstalter muss zuerst alle disputed Matches per Override schliessen.
  - Pros: Datenintegrität garantiert, klare Reihenfolge.
  - Cons: kann den Veranstalter aufhalten ("Aha, ich muss erst diesen einen Override machen, sorry Spieler").
- **B) Force-Override-Pfad** — Veranstalter kann mit Force-Flag und Begründung trotzdem starten. Offene Matches werden auf `voided` gesetzt und nicht in die Standings einberechnet.
  - Pros: Veranstalter behält Kontrolle in Notfall-Situationen.
  - Cons: kann Standings verzerren, schwer rückgängig zu machen.
- **C) Strikt + UX-Helfer** — Strikt wie A, aber die Seeding-Screen zeigt vor "KO starten" die offenen Matches und einen Schnell-Override-Knopf direkt.
  - Pros: zwingt zur Datenintegrität, aber führt den Veranstalter durch den fehlenden Schritt.
  - Cons: ein bisschen mehr UI-Arbeit (Liste offener Matches im Seeding-Screen).

**Empfehlung (vorläufig)**: C — strikt mit UX-Hilfe. Der Sonderfall (Force-Override) ist nicht häufig genug, um die Komplexität von B zu rechtfertigen.

**Marker**: `[committee]` — technisch + UX-Bewertung.

## OD-M2-07: Bracket-View-Theming — Eigenes Token-Set oder bestehende `kubb_tokens`? `[committee]`

**Frage**: Bekommt der Bracket-View ein eigenes Token-Set (eigene Farben für Sieger-Hervorhebung, Verbindungslinien, BYE-Slots) oder leiten wir alles aus `kubb_tokens` ab?

**Warum blockierend**: Beeinflusst Aufwand für M2.3-T2 und die Konsistenz mit der späteren Streaming-Sicht.

**Optionen**:
- **A) `kubb_tokens` weiterverwenden** — Standard-Primary, Standard-Border, Standard-Text. Keine neuen Tokens.
  - Pros: Konsistenz, weniger Designer-Aufwand.
  - Cons: keine besondere Hervorhebung von Sieger-Pfaden möglich.
- **B) Bracket-spezifisches Token-Subset** — 3–5 zusätzliche Tokens (`bracketWinnerHighlight`, `bracketByeBg`, `bracketConnectorColor`).
  - Pros: erlaubt visuelle Hervorhebung des Champion-Pfades, BYEs klar als solche erkennbar.
  - Cons: erweitert die Token-Liste, muss in Dark-Mode-Variant gespiegelt werden.

**Empfehlung (vorläufig)**: A für M2, B als Refinement für M3+. Begründung: M2 ist Funktionalität, M3+ ist Polish.

**Marker**: `[committee]` — Designer im Committee bewerten.

---

## Übersicht der ODs nach Marker

| ID | `[committee]` | `[owner]` | `[domain]` | `[resolved]` | Blockt |
|---|---|---|---|---|---|
| OD-M2-01 | — | — | — | ja | M2.3-T2 |
| OD-M2-02 | ja | — | — | — | M2.2-T3 |
| OD-M2-03 | ja | — | — | — | M2.3-T4 |
| OD-M2-04 | — | ja | ja | — | M2.1-T3, M2.3-T4 |
| OD-M2-05 | — | — | ja | — | M2.1-T3 |
| OD-M2-06 | ja | — | — | — | M2.2-T3, M2.3-T6 |
| OD-M2-07 | ja | — | — | — | M2.3-T2 |

Zählung: 7 ODs gesamt — 4x `[committee]`, 1x `[owner]`, 2x `[domain]`, 1x `[resolved]`. Manche tragen mehrere Marker.

## Empfohlene Entscheidungs-Reihenfolge

Damit M2-Implementierung starten kann, in dieser Sequenz:

1. **OD-M2-04** und **OD-M2-05** — beide blocken M2.1 (Pure Domain), das ist der erste Sub-Milestone. Schnell entscheiden, beide sind low-stakes Domain-Fragen.
2. **OD-M2-02** — blocked M2.2 (Server). Vor dem Committee-Output kann hier vorläufig die Empfehlung B verfolgt werden, eine spätere Anpassung ist additiv.
3. ~~**OD-M2-01**~~ — resolved 2026-05-25 (Committee 3:0 für CustomPainter, ADR-0016 Accepted). M2.3-T2 entblockt.
4. **OD-M2-06**, **OD-M2-03**, **OD-M2-07** — UX/Polish-Entscheidungen, können parallel zur Implementation laufen, müssen aber vor M2.3 abgeschlossen sein.

## Was die ODs explizit **nicht** entscheiden

- **Realtime-Strategie** — vererbt aus OD-01 (Tournament-Foundation), bleibt Polling bis M4.
- **Web-Build** — vererbt aus OD-02. Wenn Web vor M3 produktiv sein muss, Spike vorziehen (steht in `risks-and-deferrals.md`).
- **Solo-Match-Stats-Trennung** — OD-03 läuft unabhängig, kein M2-Touchpoint.
