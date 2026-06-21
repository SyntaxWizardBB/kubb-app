# Spec — Stage-Graph & Stufen-Typ-Modellierung (Canvas + Handy-Editor)

**Status:** Verbindliche Design- & Implementierungs-Spezifikation, Quality-Gate für
einen Implementer-Agent.
**Geltung:** Turnier-Stufen-Editor (Setup). Definiert **zwei Graph-Ebenen**, **zwei
Editoren** mit voller Parität, das **Modellieren neuer Stufen-Typen** und die
**Vorlagen-Bibliothek**.
**Verwandt:** [vorrunde-ranking-spec.md](./vorrunde-ranking-spec.md),
[schoch-swiss-pairing-buchholz-spec.md](./schoch-swiss-pairing-buchholz-spec.md),
ADR-0030 (Stage-Graph-Framework), ADR-0033 (Wizard-Redesign), ADR-0034 (KO-Matchup/
Tiebreak-Konsum).

> **Wording (verbindlich):** „**Stufe**" = ein Block im Turnier (Vorrunde oder KO).
> „**Runde**" = ein Spielabschnitt innerhalb einer Stufe. „**Feld** F1…Fn" = ein
> einzelnes Match-Slot innerhalb einer Runde. „**Vorrunde**" = Gruppenphase oder
> Schoch. „**KO**" = Ausscheidungs-Phase. „**Sieger-/Verlierer-Edge**" = Pfeil, der
> festlegt, wohin Sieger bzw. Verlierer eines Feldes gehen. „**Tiebreak**" = der
> physische KO-Match-Entscheider (Klassisch / Mighty-Finisher).
> **MUSS** = harte Anforderung, **SOLL** = wichtig, **OFFEN** = bewusst ungelöst.

---

## 1. Die zwei Ebenen (Kernidee)

| Ebene | Was | Status heute |
|---|---|---|
| **Ebene 1 — Stage-Graph** | Das ganze Turnier = **Stufen** (Vorrunde, KO) als Kacheln, mit **Edges** verdrahtet (wer kommt aus Stufe A in Stufe B). | **Existiert & solide** — nur erweitern/aufräumen. |
| **Ebene 2 — Typ-Graph** | **Eine einzelne Stufe** wird selbst als Graph modelliert: **Runde für Runde**, je Runde **Felder F1…Fn**, mit **Sieger-/Verlierer-Edges** zwischen den Runden. Das Ergebnis ist ein **Stufen-Typ**. | **Fehlt komplett** — das ist der Kern dieser Spec. |

**Beide Ebenen MÜSSEN auf beiden Geräten editierbar sein:**
- **Desktop → Canvas** (Drag-Platzierung, Port→Port-Edges).
- **Handy → Node/Edge-Editor** (geführte Listen + Dialoge).
- Beide Editoren arbeiten auf **demselben** Modell/Provider und teilen die
  Validierung (so wie heute schon `stageGraphBuilderProvider`).

---

## 2. Ist-Zustand (was bleibt, worauf wir aufbauen)

**Vorhanden und wiederzuverwenden (NICHT neu bauen):**
- **Stage-Graph-Modell** `StageNode` (id, type, config-Map, seeding) + `StageEdge`
  (from, to, **Selektor**, seedingIn) in `packages/kubb_domain/.../stage_graph/`.
- **Edge-Selektoren = die Sieger/Verlierer-Sprache:** `top_k`, `ranks(from..to)`,
  `losers_of_rounds({…})`, `winners`, `non_qualifiers`
  (`edge_selector.dart`). Damit werden heute schon Verlierer in Neben-Cups geroutet.
- **KO-Konfig pro Stufe (existiert!):** `ko_matchup`
  (`seed_high_vs_low` = **Beste vs Schlechteste**, `one_vs_two` = **1. vs 2.**),
  `ko_tiebreak_method` (`classic_kingtoss_removal` / `mighty_finisher_shootout`),
  `with_reset`, `ko_round_formats[]` (pro Runde: **Sätze zum Sieg**, max. Sätze,
  **Zeit pro Match**, **Pause danach**, **Tiebreak on/off** + After-Zeit) —
  `stage_node_config.dart`, Editor-Widget `ko_round_block.dart`.
- **Beide Editoren** (`stage_graph_builder_screen.dart` = Form/Handy,
  `stage_graph_canvas.dart` = Desktop-Canvas), Canvas gegated ab 720 dp.
- **Validierung** `validateStageGraph()` (V1–V7: azyklisch, Erreichbarkeit,
  Seeding auflösbar, Selektor-Überlappung, Kapazitäts-Propagation, Min-Input).
- **Vorlagen** mit Sichtbarkeit `private/club/public` (save/apply stage-graph
  template).
- **Engine** materialisiert KO-Runde 1 (matchup-bewusst), schiebt Sieger per Trigger
  `tournament_advance_ko_winner()` weiter, routet Verlierer/Qualifizierte per
  Edge-Selektoren in die nächste Stufe (`tournament_route_completed_stage()`).

**Der „Mist" / die Lücken (= Arbeitsauftrag):**
1. **Keine neuen Stufen-Typen modellierbar** — nur die 7 fixen Enum-Typen.
2. **Kein Feld-Modell (F1…Fn):** Runden/Felder sind unsichtbar und werden von der
   Typ-Implementierung fix erzeugt; man kann die innere Bracket-Struktur nicht
   modellieren.
3. **Vorlagen nur für den Stage-Graph**, nicht für Stufen-Typen.
4. `ko_tiebreak_method` wird **gespeichert, aber nicht konsumiert** (ADR-0034 §2).
5. **Stage-KO-Runden 2+** haben noch kein Scheduling (nur Runde 1).
6. **Summary** zeigt im Graph-Modus nur Knoten-/Kanten-Zahlen, nicht die Config
   (verstößt gegen H2 — keine stille Auslassung).

---

## 3. Ebene 2 — Stufen-Typ modellieren (NEU, MUSS)

Ein **Stufen-Typ** ist ein **Typ-Graph**: Runden, Felder, Sieger-/Verlierer-Edges.
Der Modellier-Ablauf:

1. **Kategorie wählen: Vorrunde oder KO.** (Bestimmt die Regeln in §4.)
2. **Teilnehmerzahl** angeben (Zahl Spieler/Teams, z. B. 16 = Achtelfinale-Einstieg).
3. **Runde 1 wird generiert:** Felder **F1 … F(n/2)** als Kacheln, beschriftet.
4. **Weitere Runde definieren:** Für jedes Feld der bestehenden Runde werden
   **Edges** gesetzt:
   - **Sieger-Edge:** in welches Feld der nächsten Runde geht der Sieger.
   - **Verlierer-Edge:** wohin geht der Verlierer.
   - Eine Edge **darf bewusst offen bleiben** (= Teilnehmer **überspringt eine
     Stufe** / wird später geroutet). Offen ist ein **gültiger** Zustand, kein Fehler
     — aber sichtbar markiert (Warnung, nicht Error).
5. **Runde für Runde** wiederholen, bis der Owner **Speichern** drückt.
6. **Speichern** als Stufen-Typ (optional als Vorlage, §6).

**KO-Feld-Konfiguration (pro Runde, MUSS — existiert als `ko_round_formats`):**
- **Begegnungen:** Beste vs Schlechteste (`seed_high_vs_low`) **oder** 1. vs 2.
  (`one_vs_two`).
- **Sätze zum Sieg.**
- **Zeit pro Match.**
- **Pause danach.**
- **Tiebreak: on/off.** Wenn **on** → **Methode: Klassisch / Mighty-Finisher.**

---

## 4. Regeln je Kategorie (MUSS)

| | **KO** | **Vorrunde** |
|---|---|---|
| Teilnehmerzahl je Runde | **nimmt ab** (Felder halbieren sich Richtung Final) | **bleibt konstant** |
| Sieger-/Verlierer-Wege | Sieger steigt auf, Verlierer scheidet aus (oder Neben-Cup-Edge) | **alle** spielen weiter; Neupaarung nach Gruppen-/Schoch-Regel |
| Pro-Runde-Config | volle KO-Feld-Config (§3) | Match-Format pro Runde; Rangfolge gemäß [vorrunde-ranking-spec](./vorrunde-ranking-spec.md) |

> **Vorrunde im Feld/Edge-Editor (Owner-Entscheid):** Auch die Vorrunde wird mit
> Feldern und Runden modelliert. Weil niemand ausscheidet, tragen die Edges hier
> **„alle weiter"**-Semantik (keine Sieger/Verlierer-Trennung); die konkrete
> Neupaarung der nächsten Runde folgt dem Vorrunden-Typ (Gruppenphase = jeder gegen
> jeden seiner Gruppe; Schoch = Auslosung gemäß Schoch-Spec). Siehe **OFFEN-1**.

---

## 5. Editoren (MUSS — volle Parität)

- **Desktop = Canvas:** Felder/Stufen als Kacheln, Edges per Port→Port-Drag, frei
  platzierbar, Auto-Layout. (Basis vorhanden: `stage_graph_canvas.dart`.)
- **Handy = Node/Edge-Editor:** geführte Listen für Felder/Runden/Stufen + Dialoge
  für Edges. (Basis vorhanden: `stage_graph_builder_screen.dart` Form-View.)
- **Parität (MUSS):** Beide Editoren können **dasselbe** — Felder/Stufen + Edges
  anlegen, bearbeiten, löschen, konfigurieren — auf **beiden** Graph-Ebenen.
- Beide arbeiten auf **einem** gemeinsamen Provider + **einer** Validierung (kein
  divergenter State).

---

## 6. Vorlagen-Bibliothek (MUSS)

- Vorlagen gibt es für **beide** Ebenen: **Stufen-Typen** (Ebene 2) **und** ganze
  **Stage-Graphen** (Ebene 1). Beide sind beim Setup **auswählbar**.
- **Sichtbarkeit:**
  - **privat** = nutzbar von Mitgliedern **desselben Veranstalter-Teams**
    (`organizer_teams`), die das **Turnier-Setup-Recht** haben (siehe
    Berechtigungskonzept-Milestone).
  - **öffentlich** = für alle nutzbar.
- Eine Vorlage ist **teilnehmer-agnostisch** (Struktur, nicht konkrete Spieler) —
  wie das bestehende Template-System.
- Bestehende Template-Sichtbarkeit `private/club/public` ist auf dieses Modell zu
  mappen (`private` → Veranstalter-Team + Setup-Recht).

---

## 7. Validierung (MUSS — bestehende Regeln erweitern)

Zusätzlich zu V1–V7 (`validateStageGraph`) gelten für den **Typ-Graph**:
- **KO:** Teilnehmerzahl pro Runde **strikt fallend**; letzte Runde = 1 Feld (Final).
- **Vorrunde:** Teilnehmerzahl pro Runde **konstant**.
- **Jedes Feld** braucht für Sieger **und** Verlierer entweder ein Ziel **oder** den
  expliziten Zustand **„offen"** (offen = Warnung, kein Error).
- **Keine Sackgassen** außer am Terminal; **jede Runde/Stufe erreichbar**; azyklisch.
- **Kapazität konsistent:** eingehende Teilnehmerzahl = Summe der Felder × 2 (KO-Runde)
  bzw. passend zum Vorrunden-Typ.
- Editor blockiert **Speichern/Veröffentlichen** bei Errors (wie heute `hasErrors`).

---

## 8. Engine-Konsequenzen (MUSS)

1. **Materialisierung aus dem Typ-Graph:** Die Engine MUSS Matches aus dem modellierten
   Typ-Graph erzeugen (Felder + Sieger/Verlierer-Edges), nicht nur aus den 7 fixen
   Typen. Bestehende Pfade (`tournament_generate_stage_matches`, Winner-Advance-Trigger,
   Edge-Routing) sind die Basis und werden auf custom Typ-Graphen erweitert.
2. **`ko_tiebreak_method` konsumieren** (heute nur gespeichert): bei tied KO-Match →
   Klassisch bzw. Mighty-Finisher anwenden.
3. **Stage-KO-Runden 2+ schedulen** (heute nur Runde 1): `ko_round_formats[r]` pro
   Runde anwenden.
4. **Summary** zeigt den vollständigen Typ-/Stage-Graph inkl. Config (H2-Regel).

---

## 9. Akzeptanzkriterien / Quality-Gates (nachprüfbar)

**9.1 Neuen KO-Typ modellieren:** Owner gibt 16 ein → es erscheinen Felder **F1–F8**
(Runde 1). Er verdrahtet Sieger → Runde 2 (F1–F4) → … → Final, setzt pro Runde Sätze/
Zeit/Pause/Tiebreak, speichert. **Ergebnis:** gültiger Stufen-Typ, keine Errors.

**9.2 Offene Edge erlaubt:** Ein Sieger-Weg bleibt bewusst offen → **Warnung**, **kein**
Error, Speichern möglich.

**9.3 KO-Schrumpfung erzwungen:** Ein KO-Typ, dessen Runde 2 gleich viele oder mehr
Felder hätte als Runde 1 → **Error** (KO muss abnehmen).

**9.4 Vorrunde konstant:** Ein Vorrunde-Typ mit abnehmender Teilnehmerzahl → **Error**.

**9.5 Beide Editoren, gleiches Ergebnis:** Derselbe Typ-Graph, am Handy und am Desktop
gebaut, ergibt **identisches** Modell (gleiche Validierung, gleiche serialisierte Form).

**9.6 Vorlage privat:** Als privat gespeicherter Typ ist **nur** für Veranstalter-Team-
Mitglieder mit Setup-Recht auswählbar; öffentliche für alle.

**9.7 Engine spielt custom Typ:** Ein selbst modellierter Typ erzeugt beim Turnierstart
echte Matches, Sieger/Verlierer laufen entlang der modellierten Edges, KO-Tiebreak-
Methode greift.

**9.8 Summary vollständig:** Die Turnier-Zusammenfassung zeigt alle Stufen, Runden,
Felder und deren Config (kein stilles Weglassen).

---

## 10. Vorgehen (empfohlene Etappen)

1. **Datenmodell Ebene 2:** Feld/Runde/Edge innerhalb einer Stufe (auf `StageNode`-
   Config oder eigenem Sub-Graph). Validierung erweitern.
2. **Editor:** Feld/Edge-Editor (Handy-Listen + Desktop-Canvas) auf Basis der
   bestehenden Builder; ein Provider, eine Validierung.
3. **Vorlagen** für Stufen-Typen (privat/öffentlich, Veranstalter-Team-Scope).
4. **Engine:** Materialisierung aus Typ-Graph; `ko_tiebreak_method` konsumieren;
   Stage-KO-Runden 2+ schedulen.
5. **Summary** vervollständigen.

---

## 11. Offene Punkte

- **OFFEN-1 (Vorrunde-Routing):** Konkrete Semantik der Edges in einer Vorrunde-Stufe
  („alle weiter" + Neupaarung nach Gruppen-/Schoch-Regel) muss beim Bau festgezurrt
  werden — insbesondere, ob die Vorrunde überhaupt explizite Feld-Edges braucht oder
  nur Runden + Paarungsregel.
- **OFFEN-2 (BYE/ungerade Zahlen):** Verhalten bei nicht-2er-Potenzen und ungeraden
  Teilnehmerzahlen im Typ-Graph (Freilos-Felder) ist zu spezifizieren.
- **OFFEN-3 (Custom-Typ vs. fixe Typen):** Ob die 7 bestehenden Typen als
  vorgefertigte Vorlagen in das neue Modell überführt werden (empfohlen) oder parallel
  bestehen bleiben.
