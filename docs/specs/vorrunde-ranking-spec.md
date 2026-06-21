# Spec — Vorrunde-Rangfolge & Shoot-out (Gruppenphase / Schoch → KO)

**Status:** Verbindliche Implementierungs-Spezifikation & Quality-Gate
**Geltung:** Klassisches Turnier (ohne Stufen-Graph). Legt fest, **wie die Rangfolge
am Ende der Vorrunde gebildet wird** und damit, **wer in die KO-Phase aufsteigt.**
**Verwandt:** [schoch-swiss-pairing-buchholz-spec.md](./schoch-swiss-pairing-buchholz-spec.md)
(Buchholz-Formel + Schoch-Auslosung).

---

## 1. Begriffe (verbindliches Wording)

- **Klassisches Turnier** = genau **zwei Phasen**: **Vorrunde → KO-Phase**.
- **Vorrunde** = genau **einer von zwei Typen**:
  - **Gruppenphase** — jeder spielt gegen **alle anderen seiner Gruppe**.
  - **Schoch** — jeder bekommt pro Runde **andere** Gegner zugelost (Schweizer
    Variante, siehe verwandte Spec).
- **Punkte** = Summe der eigenen Spielpunkte (EKC).
- **Kubb-Differenz** = erzielte minus erhaltene Basekubbs.
- **Buchholz** = Stärke der Gegner (Formel in der verwandten Spec).
- **Shoot-out** = physischer Entscheid (Mighty-Finisher), wenn ein Gleichstand
  übersteht. **„Tiebreak"** im engeren Sinn (KO-Match-Entscheider) ist **kein**
  Thema dieser Spec — die Vorrunde hat eine **Rangfolge-Regel**, keinen „Tiebreak".

---

## 2. Die Regel (MUSS)

### 2.1 Gruppenphase → KO

Rangfolge innerhalb einer Gruppe, von oben nach unten:

```
1. Punkte            (mehr = besser)
2. Kubb-Differenz    (höher = besser)
3. Shoot-out         (physischer Entscheid, nur wenn nötig — siehe §3)
```

**Ausdrücklich NICHT in der Gruppenphase:**
- **kein Buchholz**,
- **kein direktes Spiel** (bewusste Entscheidung des Owners — ein Implementer darf
  es NICHT „hilfreich" wieder einfügen).

### 2.2 Schoch → KO

Rangfolge, von oben nach unten:

```
1. Punkte            (mehr = besser)
2. Buchholz          (höher = besser)
3. Shoot-out         (physischer Entscheid, nur wenn nötig — siehe §3)
```

---

## 3. Shoot-out (MUSS)

- Der Shoot-out greift **nur**, wenn ein Gleichstand nach den vorgelagerten
  Kriterien **bestehen bleibt UND über das Weiterkommen in die KO entscheidet**
  (d. h. der Gleichstand liegt auf der Auf-/Abstiegsgrenze der Gruppe bzw. der
  Qualifikation).
- Gleichstände, die **nichts entscheiden** (rein kosmetisch, z. B. zwei sicher
  qualifizierte oder zwei sicher ausgeschiedene Teilnehmer), lösen **keinen**
  Shoot-out aus.
- Der Shoot-out ist ein **physischer** Vorgang vor Ort; sein Ergebnis wird erfasst
  und legt die Reihenfolge der betroffenen Teilnehmer fest.

---

## 4. Begründung (warum Buchholz nur bei Schoch)

- **Gruppenphase:** Jeder spielt gegen **dieselben** Gegner (alle anderen seiner
  Gruppe). Buchholz misst „wie stark waren meine Gegner" — bei gleichen Gegnern für
  alle sagt der Wert **nichts** aus. Bei vollständiger Gruppe haben zwei
  punktgleiche Teilnehmer sogar **identischen** Buchholz → er trennt sie nie.
  Deshalb entscheidet die **Kubb-Differenz**.
- **Schoch:** Jeder bekommt **verschiedene** Gegner. Erst dadurch wird „Gegnerstärke"
  unterscheidbar → Buchholz ist hier aussagekräftig (so wie an der SM Einzel 2026).

---

## 5. Ist-Zustand im Code (was heute abweicht)

Die heutige Standard-Reihenfolge (Default in
`lib/features/tournament/data/tournament_config_draft.dart`, Feld `tiebreakerOrder`)
ist:

```
total_points → buchholz_minus_h2h → direct_comparison → mighty_finisher_shootout
```

Diese **eine** Reihenfolge gilt aktuell für **beide** Vorrunden-Typen. Abweichungen
zu dieser Spec:

| | Soll Gruppenphase | Ist (heute) |
|---|---|---|
| nach Punkten | **Kubb-Differenz** | Buchholz |
| danach | Shoot-out | direktes Spiel → Shoot-out |
| Kubb-Differenz | ja, an 2. Stelle | **fehlt ganz** |
| Buchholz | **nein** | ja (an 2. Stelle) |

Zusätzlich: Der App-`buchholz_minus_h2h` entspricht **nicht** der bewiesenen
kubb.live-Buchholz-Formel (er rechnet die naive Summe minus eines ±1-Indikators);
für Schoch ist er gemäß verwandter Spec zu korrigieren.

---

## 6. Was geändert werden muss (MUSS)

1. **Rangfolge pro Vorrunden-Typ trennen** (nicht eine globale Reihenfolge für beide):
   - Gruppenphase: `total_points → kubb_difference → mighty_finisher_shootout`.
   - Schoch: `total_points → buchholz → mighty_finisher_shootout`.
2. In der **Gruppenphase** dürfen `buchholz_minus_h2h`, `median_buchholz` und
   `direct_comparison` **nicht** Teil der Rangfolge sein.
3. Für **Schoch** muss der Buchholz-Wert der kubb.live-Formel entsprechen
   (verwandte Spec §5).

---

## 7. Akzeptanzkriterien / Quality-Gates (nachprüfbar)

**7.1 Gruppenphase-Rangfolge:** Bei punktgleichen Teilnehmern derselben Gruppe
entscheidet die **Kubb-Differenz**; Buchholz und direktes Spiel haben **keinen**
Einfluss. (Test: zwei Teilnehmer gleich auf Punkte, unterschiedliche Kubb-Differenz
→ höhere Kubb-Differenz steht vorne, unabhängig vom direkten Spiel.)

**7.2 Gruppenphase, voller Gleichstand:** Bleiben zwei Teilnehmer auch nach
Kubb-Differenz gleich UND entscheidet das übers Weiterkommen → es entsteht ein
**Shoot-out-Bedarf** (kein Münzwurf, keine ID-Sortierung als stiller Entscheid).

**7.3 Kein Shoot-out bei kosmetischem Gleichstand:** Gleichstand, der nicht übers
Weiterkommen entscheidet → **kein** Shoot-out.

**7.4 Schoch-Rangfolge:** Bei punktgleichen Teilnehmern entscheidet **Buchholz**
(kubb.live-Formel); danach ggf. Shoot-out.

**7.5 Trennung der Typen:** Gruppenphase enthält in keinem Pfad Buchholz; Schoch
enthält Buchholz an 2. Stelle.

---

## 8. Offene Punkte

- **Ungleich große Gruppen:** Wird die Kubb-Differenz **über Gruppen hinweg**
  verglichen (z. B. „bester Gruppen-Zweiter"), sind unterschiedliche Gruppengrößen
  unfair (mehr Spiele = mehr mögliche Differenz). Für den **gruppen-internen**
  Aufstieg (jeder gegen jeden) ist die Kubb-Differenz fair; für den
  **gruppenübergreifenden** Vergleich ist zu klären, ob normalisiert wird.
- **3. Stufe bei Schoch:** An der SM Einzel gab es nach Buchholz noch einen feinen
  Entscheider; diese Spec verwendet bewusst direkt den **Shoot-out** als Entscheid.
