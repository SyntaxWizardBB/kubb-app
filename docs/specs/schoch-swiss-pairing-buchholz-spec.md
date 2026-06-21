# Spec — Schoch/Swiss-System: Spielverlauf, Paarung & Buchholz (kubb.live-konform)

**Status:** Verbindliche Implementierungs-Spezifikation & Quality-Gate
**Quelle der Wahrheit:** Empirisch rückgerechnetes Verhalten von **live.kubb (kubb.live)**,
SM Einzel 2026 (73 Spieler, 8 Runden Schweizer System).
**Geltung:** Jede Turnier-Paarungs- und Buchholz-Implementierung in diesem Repo
(`packages/kubb_domain/.../pairing/`) MUSS die Akzeptanzkriterien in §7 erfüllen.

> Dieses Dokument ist als **Quality-Gate für einen Implementer-Agent** geschrieben.
> Es definiert *was* korrekt ist (mit nachprüfbaren Soll-Werten), nicht nur *wie*.
> Begriffe: „**MUSS**" = harte, bewiesene Anforderung. „**DEFINIERT**" = sinnvolle,
> deterministische Festlegung dort, wo die Originalquelle keinen eindeutigen Schluss
> zulässt. „**OFFEN**" = bewusst ungelöst.

---

## 1. Kontext & Begriffe

- **Schoch-System** = die schweizerische Ausprägung des **Schweizer Systems** (Swiss
  pairing). Die hier dokumentierte, an der SM Einzel **tatsächlich gespielte** Variante
  ist ein **Monrad-Swiss** (benachbarte Paarung), kein Dutch/FIDE-Fold. Das ist
  empirisch belegt (§7.4).
- **Punkte (Score):** Summe der erzielten Spielpunkte über alle Runden. Pro Match
  erzielt ein Spieler 0–16 Punkte (EKC-Scoring). Es gibt KEINE Sieg-/Remis-Punkte
  (2/1/0) — die Rangwertung ist die **Spielpunkte-Summe**.
- **Buchholz:** Feinwertung (Tiebreaker) = Stärke der Gegner. Exakte Formel in §5.
- **Freilos (BYE):** Bei ungerader Teilnehmerzahl bleibt pro Runde ein Spieler übrig.

---

## 2. Verifizierte Fakten & Konfidenz

| Eigenschaft | Befund (SM Einzel 2026) | Konfidenz |
|---|---|---|
| Buchholz = Σ(Gegner-Endpunkte − Gegner-Score-gegen-mich) | **73/73 Spieler exakt** | 🔒 bewiesen |
| Punkte = Summe der eigenen Spielpunkte | **73/73 exakt** | 🔒 bewiesen |
| Freilos an schwächsten Spieler ohne Vor-Freilos | **8/8 Runden exakt** | 🔒 bewiesen |
| Freilos zählt als voller Sieg = **16 Punkte** | **8/8 exakt** | 🔒 bewiesen |
| Keine Wiederholungspaarungen (Rematch-Vermeidung) | **0 von 288 Partien** | 🔒 bewiesen |
| Sortierung: Punkte → Buchholz → … | beste Reproduktion aller Sortier-Hypothesen | 🔒 sehr hoch |
| Paarung **benachbart (Monrad)**, NICHT Fold/Dutch | adjacent **77%** vs. fold **37%**; jede Runde adjacent klar vorn | 🔒 eindeutig |
| Exakter **3. Tiebreak** (bei Punkt- UND Buchholz-Gleichstand) | nicht isolierbar; verursacht alle Rest-Fehltreffer | ⚠️ OFFEN |

> Alle nicht reproduzierten Paarungen sind **Mini-Vertauschungen** zwischen
> *punktgleichen* Spielern (Δpunkte ≤ 1, Δposition ≤ 3) — Signatur eines feinen
> 3.-Tiebreaks, **kein** anderer Mechanismus. Ohne die strukturell mehrdeutige
> Runde 2 (nach R1 sind alle Sieger gleichauf) liegt die Reproduktion bei **87%**,
> Runde 6 sogar **36/36 perfekt**.

---

## 3. Datenmodell (Mindestanforderung)

Pro Match wird benötigt:

```
Match {
  round: int            // 1..N
  participantA: Id
  participantB: Id | BYE
  pointsA: int          // 0..16
  pointsB: int          // 0..16 ; bei BYE: pointsA = 16, kein Gegner
  isBye: bool
}
```

Abgeleitet (über alle Matches eines Spielers P):
- `totalPoints(P)` = Σ aller `pointsForP` (inkl. der 16 aus einem evtl. Freilos).
- `opponents(P)` = Liste aller Gegner aus Nicht-Freilos-Matches.
- `scoreOf(opp, vs P)` = die Punkte, die `opp` im direkten Match gegen `P` erzielt hat.

---

## 4. Punkte-/Scoring-Modell (MUSS)

1. `totalPoints(P)` = Summe der eigenen Spielpunkte über **alle** Runden.
2. **Freilos** ⇒ dem Freilos-Spieler werden **16 Punkte** gutgeschrieben (voller Sieg);
   es entsteht **kein** Gegner-Eintrag (zählt für niemandes Buchholz).
3. Rang in der Live-Tabelle = Sortierung nach §6.1.

**Quality-Gate 4-A:** `totalPoints` jedes Spielers MUSS der Spielpunkte-Summe seiner
Matches entsprechen (Golden-Dataset: 73/73).

---

## 5. Buchholz-Formel (MUSS — exakt)

### 5.1 In einem Satz
> Buchholz = die Stärke aller Gegner zusammengezählt — **aber die Punkte, die ein
> Gegner ausgerechnet gegen dich gemacht hat, zählen nicht mit.**

### 5.2 Zwei gleichwertige Schreibweisen

**Pro Gegner:**
```
Buchholz(P) = Σ über Gegner G von [ totalPoints(G) − scoreOf(G gegen P) ]
```

**Aggregiert (äquivalent, am einfachsten):**
```
Buchholz(P) = ( Σ totalPoints(aller Gegner) ) − ( Gegenpunkte von P )

  Gegenpunkte(P) = Σ Punkte, die alle Gegner in ihren Direktduellen gegen P erzielt haben
```

Beide Formen sind mathematisch identisch und treffen **73/73** exakt.

### 5.3 Referenz-Implementierung (Pseudocode)

```
int buchholz(P, allMatches):
    sum = 0
    for m in matchesOf(P, allMatches):
        if m.isBye: continue                    # Freilos: kein Gegner -> kein Beitrag
        opp        = opponentIn(m, P)
        oppTotal   = totalPoints(opp, allMatches)   # ALLE Spiele des Gegners (inkl. dessen Freilos-16)
        oppVsP     = pointsScoredBy(opp, in: m)     # was der Gegner in DIESEM Match gegen P machte
        sum += (oppTotal − oppVsP)              # Gegnerstärke OHNE den H2H-Anteil gegen P
    return sum
```

**Wichtige Edge-Cases:**
- Ein **Freilos**-Match von P trägt **0** bei (übersprungen).
- `oppTotal` enthält die 16 Punkte eines evtl. Freiloses des Gegners (korrekt — es wird
  nur der reale H2H-Score gegen P abgezogen, nicht das Freilos des Gegners).
- Hat P selbst ein Freilos gehabt, hat P nur 7 reale Gegner ⇒ Summe über 7 Terme.
  (Verifiziert an den Freilos-Spielern, z. B. Meff: 411 exakt.)

### 5.4 Worked Example — Buschi (Endrang 1)

| Runde | Gegner | Buschi : Gegner | Gegner-Endpunkte | Score gegen Buschi | Beitrag |
|---|---|---|---|---|---|
| 1 | Pitsch Loco | 16:3 | 64 | 3 | 61 |
| 2 | Driiibiii | 16:4 | 86 | 4 | 82 |
| 3 | Sparringspartner | 8:16 | 102 | 16 | 86 |
| 4 | Rolli | 16:4 | 93 | 4 | 89 |
| 5 | Hafenkneipenleiter | 11:10 | 95 | 10 | 85 |
| 6 | Croci-Torti | 16:8 | 97 | 8 | 89 |
| 7 | Clint Eastwood | 11:10 | 100 | 10 | 90 |
| 8 | Beni the Gun | 16:9 | 109 | 9 | 100 |
| | | | **Σ 746** | **Σ 64** | **= 682** |

`Buchholz(Buschi) = 746 − 64 = 682` ✓ (live.kubb: **682**)

### 5.5 Abgrenzung zur bestehenden App-Implementierung (WICHTIG)

- `packages/kubb_domain/lib/src/tournament/pairing/buchholz.dart` (`BuchholzCalculator.scoreFor`)
  summiert aktuell **nur** die Gegner-Endpunkte (**naive** Form, OHNE Abzug). Das ergibt
  z. B. für Buschi **746/721** statt **682** und ist gegenüber live.kubb **falsch**.
  → MUSS auf die Formel aus §5.2/§5.3 umgestellt werden (Gegenpunkt-Abzug ergänzen).
- Das Kriterium `TiebreakerCriterion.buchholzMinusH2H` in `tiebreaker.dart` ist **NICHT**
  diese Formel: es zieht nur den H2H gegen den *einen* aktuell verglichenen Gegner ab.
  Die hier geforderte Formel zieht für **jeden** Gegner dessen Score gegen P ab.
  → Nicht verwechseln; die Korrektur gehört in den Buchholz-Kern, nicht in den
  paarweisen Vergleich.

---

## 6. Paarungs-/Auslosungs-Algorithmus (Monrad-Swiss)

### 6.1 Standings-Sortierung (vor jeder Paarung)

```
sortKey(P) = ( −points(P),          // 1. mehr Punkte zuerst
               −buchholz(P),         // 2. höherer Buchholz zuerst (Formel §5)
               startNumber(P) )      // 3. DEFINIERT: feste Startnummer/Seed aufsteigend
```

- Schlüssel 1+2 sind **bewiesen**.
- Schlüssel 3 ist **DEFINIERT** (deterministischer Seed/Startnummer). Es MUSS
  deterministisch und über das ganze Turnier **stabil** sein — **kein Zufall pro Runde**.
  Die Originalquelle liess den exakten 3.-Tiebreak nicht eindeutig isolieren (§7.5).

### 6.2 Der Algorithmus (MUSS)

```
function pairRound(round, players, history):
    if round == 1:
        order = startOrder(players)              // Seed-/Auslosungsreihenfolge
    else:
        order = sortBy(players, sortKey)         // §6.1 ; best -> worst

    pairs = []

    // 1) FREILOS bei ungerader Anzahl — VOR dem Paaren
    if isOdd(len(order)):
        bye = firstFromBottom(order, p -> not hadBye(p))   // schwächster ohne Vor-Freilos
        if bye == null: bye = order.last                   // Fallback: schwächster erneut
        award(bye, 16 points, fullWin); mark hadBye(bye)
        order.remove(bye)

    // 2) PAARUNG — benachbart (Monrad), mit Rematch-Skip
    pool = order                                  // bereits sortiert best->worst
    while pool not empty:
        a = pool.removeFirst()
        partner = first p in pool with key(a,p) NOT in history     // nächster un-gespielter darunter
        if partner == null:
            partner = pool.first                  // erzwungener Rematch (trat 2026 NIE auf)
        pool.remove(partner)
        pairs.add( (a, partner) )

    return pairs, byeOf(round)
```

### 6.3 Regeln im Detail (MUSS)

1. **Sortierung** strikt nach §6.1.
2. **Freilos** wird **vor** dem Paaren bestimmt und aus `order` entfernt:
   schwächster Spieler (= letzter der Sortierung), **der noch kein Freilos hatte**;
   falls alle bereits eines hatten, der schwächste erneut. Freilos = **16 Punkte**.
3. **Benachbarte Paarung (Monrad):** Liste von oben nach unten; jeder Spieler wird mit
   dem **nächsten Spieler darunter** gepaart, gegen den er **noch nicht gespielt** hat.
4. **Rematch-Vermeidung (MUSS):** Eine bereits gespielte Paarung wird übersprungen
   (nächster zulässiger Gegner weiter unten). Fold/Dutch (obere vs. untere Hälfte) ist
   **explizit verboten** — es widerspricht den Daten (37% vs. 77%).
5. **Runde 1:** nach fester Start-/Auslosungsreihenfolge, ebenfalls benachbart gepaart;
   Freilos an den letzten der Startliste.
6. **Pitch-/Tisch-Nummerierung** folgt der Standings-Reihenfolge (Tisch 1 = Spitzenpaar).

### 6.4 Was NICHT passieren darf (Anti-Pattern)

- ❌ Fold/Dutch-Paarung (S1[i] vs S2[i]).
- ❌ Zufalls-Tiebreak, der pro Runde neu würfelt (nicht reproduzierbar).
- ❌ Wiederholungspaarung, solange ein rematch-freier Gegner existiert.
- ❌ Freilos an einen Spieler, der schon eines hatte, solange ein anderer ohne existiert.
- ❌ Freilos NACH dem Paaren bestimmen.

---

## 7. Akzeptanzkriterien / Quality-Gates (nachprüfbar)

> Golden-Dataset = SM Einzel 2026 (kubb.live: `rangliste/` + `alle-runden/`).
> Implementierung MUSS gegen dieses Dataset getestet werden.

**7.1 Punkte:** `totalPoints` aller 73 Spieler == Spielpunkte-Summe ⇒ **73/73**.

**7.2 Buchholz:** Berechnete Buchholz-Werte == kubb.live-Werte ⇒ **73/73 exakt**.
Test-Vektoren:

| Spieler | Punkte | Buchholz (Soll) |
|---|---|---|
| Buschi | 110 | **682** |
| Beni the Gun | 109 | **691** |
| Voegi18 | 106 | **650** |
| Sparringspartner | 102 | **720** |
| RougeOMat | 89 | **577** |
| Meff (Freilos-Spieler) | 71 | **411** |
| Die Nase (Freilos-Spieler) | 44 | **390** |

**7.3 Freilos:** Vorhergesagte Freilos-Spieler je Runde == Ist ⇒ **8/8**:

| Runde | Freilos | (Stand: schwächster ohne Vor-Freilos) |
|---|---|---|
| 1 | Die Nase | letzter der Startliste |
| 2 | Börny | |
| 3 | Laura | |
| 4 | Schibu | |
| 5 | Meff | |
| 6 | Tom Kreuzfahrt | Platz 72 (Platz 73 hatte schon Freilos) |
| 7 | Kubbacca | |
| 8 | LaMartina | Platz 71 (72 & 73 hatten schon Freilos) |

**7.4 Rematch:** Über alle Runden ⇒ **0 Wiederholungspaarungen**.

**7.5 Paarungs-Reproduktion (Regression-Gate):** Mit Sortierung §6.1 und Monrad-Paarung
MUSS die Implementierung mindestens reproduzieren:
- **Gesamt R2–R8 ≥ 77%** der echten Paare,
- **R3–R8 ≥ 87%**,
- **mindestens eine Runde 36/36** (R6),
- und Fold/Dutch MUSS **deutlich schlechter** abschneiden (Sanity-Check gegen falsche Regel).
> 100% sind NICHT erreichbar, solange der exakte 3.-Tiebreak (§2, OFFEN) unbekannt ist.
> Wird er später bestimmt, ist dieses Gate auf 100% (außer R2) zu verschärfen.

---

## 8. Spielverlauf-Charakteristik (Referenz für Plausibilität)

Führung nach jeder Runde (Punkte): R1 Buschi(16) → R2 Buschi(32) →
R3 Sparringspartner(48) → R4 Sparringspartner(60) → R5 **Beni the Gun**(73) →
R6 Beni(84) → R7 Beni(100) → **R8 Buschi(110) 🏆**.

Typisch fürs Schweizer System: die Führung wechselt mehrfach, Spitzenspieler treffen
erst spät aufeinander, und die Entscheidung fällt im **direkten Spitzenduell der
Schlussrunde** (Buschi schlägt den führenden Beni 16:9 und übernimmt die Spitze).
Buchholz dient nur als Feinwertung bei Punktgleichheit.

---

## 9. Offene Punkte

- **3.-Tiebreak** bei Punkt- UND Buchholz-Gleichstand ist nicht aus den Daten isoliert.
  Bis zur Klärung gilt §6.1 Schlüssel 3 als **DEFINIERT** (stabile Startnummer).
  Kandidaten zur weiteren Untersuchung: Startnummer/Seed, Feinbuchholz
  (Σ Gegner-Buchholz), Gegenpunkte. Keiner schlug in Tests die Startnummer-Variante
  signifikant.
- **Startliste/Seed** für Runde 1 ist nur als Auslosungsreihenfolge rekonstruierbar
  (erste Paarungen: Beni the Gun, N'Ivo, Ikarus, Jim Panse, Hafenkneipenleiter,
  Kubbernikus, Buschi, Pitsch Loco, …), nicht als externe Setzung verifizierbar.

---

## 10. Implementierungs-Checkliste für den Implementer-Agent

- [ ] `BuchholzCalculator` auf Formel §5 umstellen (Gegenpunkt-Abzug pro Gegner).
- [ ] Unit-Test: 73/73 Buchholz gegen Golden-Dataset (§7.2), inkl. Freilos-Spieler.
- [ ] Standings-Sort §6.1 (Punkte → Buchholz → stabile Startnummer).
- [ ] Freilos-Auswahl §6.3.2 + 16-Punkte-Gutschrift; Test 8/8 (§7.3).
- [ ] Monrad-Paarung mit Rematch-Skip (§6.2); Test 0 Rematches (§7.4).
- [ ] Regression-Test Paarungs-Reproduktion (§7.5).
- [ ] Sanity: Fold/Dutch-Variante schneidet schlechter ab (Negativ-Test).
- [ ] Keine Zufalls-Tiebreaks pro Runde (Determinismus-Test: zwei Läufe identisch).
