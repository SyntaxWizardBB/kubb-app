# P6 — K.-o.-Modelle: Double-Elimination vs. Trostturnier

> **Status:** verbindliche Konzept-Entscheidung (User, Juni 2026).
> **Zweck:** Einzige Quelle der Wahrheit für die beiden wählbaren „zweiter
> Baum"-Modelle im Turnier-Setup. Der kurze **Modal-Text** am Ende ist 1:1 die
> Vorlage für das In-App-Erklär-Modal (Info-Icon neben der K.-o.-System-Auswahl
> in Screen „Vorrunde"/„K.-o."). Ergänzt [P6_RULES_DECISIONS.md](P6_RULES_DECISIONS.md)
> und [ADR-0027](adr/0027-double-elimination.md).

## Überblick

Jedes Turnier hat zwingend ein K.-o. (kein „Kein K.-o."). Beim K.-o.-System
wählt der Veranstalter zwischen drei Optionen:

| Option | Zweiter Baum? | Verlierer | Endergebnis |
|---|---|---|---|
| **Single-Out** | nein | eine Niederlage = raus | Final = Platz 1/2, Spiel um Platz 3 |
| **Double-Elimination** (Modell A) | ja, gekoppelt | raus erst nach **2** Niederlagen | ein Champion, Verliererbaum-Sieger kann noch gewinnen |
| **Trostturnier** (Modell B) | ja, separat | eine Niederlage im Hauptbaum = raus aus dem Titelrennen | Final entscheidet Platz 1/2 **endgültig**, Nebenturnier spielt hintere Plätze aus |

**Beide Modelle (A und B) sind wählbar.** Sie sehen oberflächlich ähnlich aus
(„es gibt einen zweiten Baum"), unterscheiden sich aber fundamental darin, ob
der zweite Baum noch zum Turniersieg führen kann.

---

## Modell A — Echtes Double-Elimination

Winner-Bracket (WB) + Loser-Bracket (LB) + Grand Final. Wer im WB verliert,
fällt an einer **deterministisch festgelegten Position** in den LB. Der
LB-Sieger spielt im Grand Final gegen den WB-Sieger und **kann das Turnier noch
gewinnen** (bei Bedarf mit Bracket-Reset-Entscheidungsspiel). Endgültig raus ist
man erst nach der **zweiten** Niederlage.

Beispiel mit 8 Teams (A–H), A ist Topseed und gewinnt jeweils:

```
WINNER-BRACKET (WB)
  Viertelfinale   Halbfinale   WB-Final
   A ┐
     ├ A ┐
   H ┘   ├ A ┐
   D ┐   │   │
     ├ D ┘   │
   E ┘       ├ A ──► ins GRAND FINAL
   C ┐       │
     ├ C ┐   │
   F ┘   ├ B ┘
   B ┐   │
     ├ B ┘
   G ┘
  WB-Verlierer:  R1 = H,E,F,G   HF = D,C   Final = B
        │  ALLE fallen in den Loser-Bracket ↓

LOSER-BRACKET (LB) — zweite Niederlage = endgültig raus
  LB-R1 :  H–E → H ,  F–G → F            (E,G raus)
  LB-R2 :  H–D → D ,  F–C → C            (H,F raus)   ← D,C aus HF dazu
  LB-R3 :  D–C → D                       (C raus)
  LB-Fin:  D–B → B                       (D raus)     ← B aus WB-Final dazu
           ⇒ LB-Sieger = B ──► ins GRAND FINAL

GRAND FINAL :  A (0 Niederlagen)  vs  B (1 Niederlage)
   • A gewinnt → 🏆 A , B = 2.
   • B gewinnt → 1 Entscheidungsspiel (Bracket-Reset) → 🏆
   ⇒ Selbst der WB-Final-Verlierer kann am Ende noch Turniersieger werden.
```

**Eignung:** sportlich „fairste" Form (ein Pech-Spiel wirft niemanden raus),
aber mehr Spiele und komplexerer Ablauf. Technisch bereits umgesetzt (ADR-0027).
Beim reinen Double-Elimination ist die zweite-Baum-Struktur **geschlossen** —
es kommen keine zusätzlichen Teams direkt aus der Vorrunde dazu.

---

## Modell B — Trostturnier / „Nebenturnier"

Der Hauptbaum ist ein normales Single-Elimination und entscheidet **endgültig**
Platz 1/2 (plus Spiel um Platz 3). Parallel läuft ein **separater zweiter Baum**
(„Trostturnier"), der die ausgeschiedenen Teams sammelt und die **hinteren
Plätze** ausspielt. Es gibt **keinen Weg zurück** in den Hauptbaum.

Beispiel mit 8 Teams im Hauptbaum (A–H):

```
HAUPTBAUM (Single-Elim)
  Viertelfinale   Halbfinale   Final
   A ┐
     ├ A ┐
   H ┘   ├ A ┐
   D ┐   │   │
     ├ D ┘   │
   E ┘       ├ A     🏆 Platz 1 = A , Platz 2 = B
   C ┐       │
     ├ C ┐   │
   F ┘   ├ B ┘
   B ┐   │
     ├ B ┘
   G ┘
  Halbfinal-Verlierer D,C  → SPIEL UM PLATZ 3  (Platz 3/4)
  Viertelfinal-Verlierer H,E,F,G  → ins Trostturnier ↓

TROSTTURNIER ("Nebenturnier", eigene K.-o.-Regeln)
  Trost-HF :  H–E → H ,  F–G → F
  Trost-Fin:  H–F          → Platz 5 / 6
  Trost-P3 :  E–G          → Platz 7 / 8
  ⇒ KEIN Weg zurück in den Hauptbaum / ins Final.

Endrang:  1 A · 2 B · 3/4 (D,C) · 5/6 (H,F) · 7/8 (E,G)
```

### Gestaffelter Einstieg (grössere Felder)

Verlierer steigen je nach Hauptbaum-Runde **in unterschiedlichen Runden** des
Trostturniers ein — frühe Verlierer früh, spätere später. Die
**Halbfinal-Verlierer** gehen NICHT ins Trostturnier, sondern ins Spiel um
Platz 3.

```
Hauptbaum startet im "Achtelfinale" (16 Teams im Hauptbaum):
  Achtelfinale  : 8 Verlierer  → Trostturnier, Runde 1
  Viertelfinale : 4 Verlierer  → Trostturnier, steigen in Runde 2 dazu
  Halbfinale    : 2 Verlierer  → Spiel um Platz 3 (NICHT Trostturnier)
  Final         : Platz 1 / 2
```

### Konfiguration Modell B (Veranstalter-Eingaben)

1. **Hauptbaum-Grösse** — wie viele aus der Vorrunde in den Hauptbaum kommen.
   Zweierpotenz (4/8/16/32 …), keine Freilose im Hauptbaum.
2. **Direkt ins Trostturnier (Anzahl)** — eine **frei wählbare Zahl** weiterer
   Vorrunden-Teams, die NICHT in den Hauptbaum kommen, sondern direkt im
   Trostturnier starten. Beispiel: 16 weiter in den Hauptbaum, 8 direkt ins
   Trostturnier.
   - Teilnehmer des Trostturniers = **diese Direkt-Starter PLUS die
     Hauptbaum-Verlierer** (gestaffelt, siehe oben).
   - Die Direkt-Starter seeden die frühen Runden des Trostturniers; die
     Hauptbaum-Verlierer steigen gemäss ihrer Ausscheide-Runde dazu.
3. **Name des Trostturniers** — frei wählbar (z. B. „Trostturnier", „Plate",
   „Consolation Cup", „B-Cup").
4. **K.-o.-Regeln des Trostturniers** — eigene Sätze-zum-Sieg / Match-Zeit /
   Pause / Tiebreak je Runde, analog zum Hauptbaum-K.-o.

**Eignung:** alle Teams bekommen mehr Spiele und eine Platzierung, der Titel
bleibt aber rein dem Hauptbaum vorbehalten. Beliebt bei grossen Feldern und
Tagesturnieren.

---

## Offene Implementierungs-Details (nicht User-Entscheidungen)

- **Freilose im Trostturnier:** Wenn Direkt-Starter + gestaffelte Verlierer pro
  Einstiegsrunde keine glatte Zweierpotenz ergeben, braucht das Trostturnier
  intern Freilose (im Gegensatz zum Hauptbaum). Regel beim Bauen festlegen.
- **Exakte Einstiegsrunden-Zuordnung** der gestaffelten Verlierer → eigener ADR
  (analog `lbDropTarget` aus ADR-0027), wenn Modell B umgesetzt wird.

---

## Modal-Text (Vorlage für die UI)

> Diese kurzen Texte werden im Erklär-Modal angezeigt (Info-Icon neben der
> K.-o.-System-Auswahl). In `app_de.arb` als `tournamentKoModelExplainer*`
> hinterlegen.

**Titel:** Welcher zweite Baum?

**Single-Out**
Eine Niederlage und du bist draussen. Der Final entscheidet Platz 1 und 2, dazu
gibt es ein Spiel um Platz 3. Schnell und einfach.

**Double-Elimination**
Du musst zweimal verlieren, um auszuscheiden. Wer im Hauptbaum verliert, fällt in
den Verliererbaum und kann sich von dort bis ins Finale zurückkämpfen — der
Verliererbaum-Sieger kann am Ende noch Turniersieger werden. Sportlich am
fairsten, aber mehr Spiele.

**Trostturnier**
Der Hauptbaum entscheidet Platz 1 und 2 endgültig. Wer im Hauptbaum ausscheidet
(ausser den Halbfinal-Verlierern, die um Platz 3 spielen), kommt ins
Trostturnier und spielt dort die hinteren Plätze aus. Optional starten zusätzlich
einige Teams direkt aus der Vorrunde im Trostturnier. Es gibt keinen Weg zurück
ins Finale — aber alle bekommen mehr Spiele und eine Platzierung.
