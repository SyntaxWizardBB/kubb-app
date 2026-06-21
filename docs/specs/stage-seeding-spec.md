# Spec — Seeding pro Stufe (ELO / Zufall / Manuell / aus Vorrunde)

**Status:** Verbindliche Implementierungs-Spezifikation & Quality-Gate.
**Geltung:** Wie die **Setzliste (Seeding)** einer Stufe bestimmt wird — für
**Vorrunde** (Gruppenphase, Schoch, Jeder-gegen-jeden) und **KO**.
**Verwandt:** [vorrunde-ranking-spec.md](./vorrunde-ranking-spec.md),
[stage-graph-and-stage-type-modeling-spec.md](./stage-graph-and-stage-type-modeling-spec.md),
[schoch-swiss-pairing-buchholz-spec.md](./schoch-swiss-pairing-buchholz-spec.md).

> **Wording:** „**Seeding/Setzliste**" = die Start-Reihenfolge der Teilnehmer, die
> eine Stufe als Eingang bekommt (für die erste Paarung bzw. Gruppen-Verteilung).
> „**Vorrunde**" = Gruppenphase, Schoch oder Jeder-gegen-jeden. „**aus Vorrunde**" =
> Setzliste aus der Schlussrangliste der vorherigen Stufe.
> **MUSS** = harte Anforderung, **OFFEN** = ungelöst.

---

## 1. Verfügbare Seeding-Quellen je Stufenart (MUSS)

| Stufenart | Wählbare Seeding-Quellen |
|---|---|
| **Vorrunde** (Gruppenphase, Schoch, Jeder-gegen-jeden) | **ELO · Zufall · Manuell** |
| **KO** (und jede Folgestufe mit Eingang) | **aus Vorrunde · ELO · Zufall · Manuell** |

**Regeln:**
- „**aus Vorrunde**" ist **nur** für Stufen mit eingehender Kante verfügbar (KO,
  Folge-Stufen). Eine Vorrunde ist die **erste** Stufe → kein vorheriger Stand →
  „aus Vorrunde" entfällt.
- **Manuell** MUSS bei **allen** Stufenarten möglich sein (auch Gruppenphase und
  Schoch), nicht nur im KO.
- Die Auswahl der Seeding-Quelle ist pro Stufe **genauso** zu bedienen wie heute im
  KO — nur die Optionsliste unterscheidet sich (Vorrunde ohne „aus Vorrunde").

---

## 2. Die Lücke: „Zufall" als Seeding-Quelle ergänzen (MUSS)

Heute existiert **„Zufall" NICHT als Seeding-Quelle**:
- `StageSeedingSource` (`packages/kubb_domain/.../stage_graph/stage_node.dart`) kennt
  nur `from_elo`, `from_prev_ranking`, `manual`, `as_routed`.
- Das klassische `SeedingMode` (`tournament_models.dart`) kennt nur `auto`, `manual`.
- „Zufall" gibt es bisher **nur** als Pool-**Verteilungs**-Strategie (snake/seeded/
  **random**), nicht als Setzlisten-Quelle.

**MUSS:** Eine Seeding-Quelle **`random` (Zufall)** ergänzen (für Vorrunde *und* KO
auswählbar).

**Determinismus (MUSS):** „Zufall" MUSS **reproduzierbar** sein — über einen
gespeicherten Seed (wie der bestehende `random_seed` der Pool-Verteilung). Gleicher
Seed → gleiche Setzliste. Kein neues Würfeln bei jedem Aufruf (konsistent mit der
Determinismus-Regel der Schoch-Spec).

---

## 3. Gruppenphase: Setzliste vs. Verteilung sauber trennen (MUSS)

Bei der Gruppenphase gibt es **zwei** Schritte, die sich bei „Zufall" sonst beißen:

1. **Seeding-Quelle** = in welcher **Reihenfolge** stehen die Teilnehmer
   (ELO / Zufall / Manuell).
2. **Verteilung** = wie diese Reihenfolge auf die Gruppen **verteilt** wird.

**Entscheid (MUSS):**
- Die **Verteilung ist Snake** (faire Verteilung der Setzliste über die Gruppen).
- Die bisherige **„Random"-Verteilungsstrategie entfällt** — Zufalls-Gruppen entstehen
  sauber durch **Seeding-Quelle = Zufall** + **Snake-Verteilung**. So gibt es nur
  **einen** „Zufall"-Schalter, nicht zwei.
- „Seeded"-Verteilung (Reihenfolge blockweise) entfällt analog, sofern nicht
  ausdrücklich gebraucht (siehe OFFEN-1).

So gilt einheitlich: **Quelle bestimmt die Reihenfolge, Snake verteilt sie.**

---

## 4. McMahon ist nicht nötig (Kontext)

Ein **gesetztes Schweizer System (McMahon)** ist durch **ELO-Seeding bei Schoch**
praktisch abgedeckt: Starke treffen früh nicht auf Schwache. Der McMahon-Zusatz
(Rangpunkte als Startguthaben, um das Feld zu stauchen) wird für Kubb **nicht**
gebraucht. → **Kein eigener McMahon-Modus.**

---

## 5. Ist-Zustand im Code (Mapping)

- `StageSeedingSource`: `from_elo`, `from_prev_ranking`, `manual`, `as_routed`
  (`stage_node.dart:53-64`) — **`random` fehlt**.
- `SeedingMode` (klassisch): `auto`, `manual` (`tournament_models.dart:120-122`).
- Pool-Verteilung: `snake` / `seeded` / `random` (+`random_seed`) via
  `writePoolNodeConfig()` — hier lebt heute der einzige „Zufall".
- Stufen ohne eingehende Kante (Root/Vorrunde) vs. mit Kante (KO/Folge) sind im
  Graph-Modell bereits unterscheidbar (Validierung kennt Roots).

---

## 6. Was geändert werden muss (MUSS)

1. **`random` zu `StageSeedingSource` hinzufügen** (+ Wire-String `random`,
   + reproduzierbarer Seed).
2. **Seeding-Quelle pro Stufe wählbar machen** — auch für Gruppenphase, Schoch,
   Jeder-gegen-jeden (nicht nur KO).
3. **Optionsliste je Stufe gaten:** Root/Vorrunde → ohne „aus Vorrunde"; Folge-Stufe
   → mit „aus Vorrunde".
4. **Pool-Verteilung auf Snake reduzieren** (Random/Seeded-Verteilung entfernen;
   Zufall kommt aus der Seeding-Quelle).
5. **Engine:** Setzliste gemäß gewählter Quelle erzeugen (ELO-Sortierung / Zufall mit
   Seed / manuelle Liste / aus Vorrunde) und der Stufe als Eingang übergeben.

---

## 7. Akzeptanzkriterien / Quality-Gates (nachprüfbar)

**7.1 Vorrunde-Optionen:** Eine Schoch- bzw. Gruppenphase- bzw. Jeder-gegen-jeden-
Stufe bietet **genau** {ELO, Zufall, Manuell} an — **nicht** „aus Vorrunde".

**7.2 KO-Optionen:** Eine KO-Stufe mit Eingang bietet {aus Vorrunde, ELO, Zufall,
Manuell} an.

**7.3 Zufall reproduzierbar:** Gleicher Seed → identische Setzliste über mehrere Läufe.

**7.4 Manuell überall:** Manuelle Setzliste ist bei Gruppenphase, Schoch und KO
editier- und speicherbar.

**7.5 Gruppenphase eindeutig:** Es gibt **eine** Seeding-Quelle (Reihenfolge) und die
Verteilung ist **Snake**; **kein** zweiter „Random"-Verteilungsschalter mehr.

**7.6 Zufalls-Gruppen:** Seeding-Quelle = Zufall + Snake erzeugt nachvollziehbar
durchmischte Gruppen (ersetzt die alte Random-Verteilung).

---

## 8. Offene Punkte

- **OFFEN-1 („Seeded"-Verteilung):** Ob neben Snake noch eine blockweise
  („Seeded")-Verteilung gebraucht wird (z. B. um bewusst Top-Spieler in dieselbe
  Gruppe zu legen) — Default ist **nein** (nur Snake).
- **OFFEN-2 (ELO-Quelle):** Wo die ELO/Rating-Werte herkommen und was passiert, wenn
  ein Teilnehmer keinen ELO-Wert hat (Fallback-Reihenfolge), ist zu definieren.
