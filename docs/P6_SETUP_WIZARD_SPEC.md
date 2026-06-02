# P6 — Turnier-Setup-Wizard: Gesamt-Spezifikation

> **Status:** verbindlich (User-Entscheide, Juni 2026). **Einzige Quelle der
> Wahrheit** für den Umbau des Turnier-Setup-Wizards.
> **Detail-Dokumente:** [P6_KO_MODELS.md](P6_KO_MODELS.md) (KO-Modelle + Modal-Text),
> [P6_SHOOTOUT_TIEBREAK.md](P6_SHOOTOUT_TIEBREAK.md) (Shoot-Out).
> **Bezug:** [P6_RULES_DECISIONS.md](P6_RULES_DECISIONS.md), [ADR-0017](adr/0017-single-elimination-bracket.md),
> [ADR-0027](adr/0027-double-elimination.md). Code: `lib/features/tournament/presentation/tournament_setup_wizard.dart`
> + `widgets/_wizard_*.dart`.

## Leitprinzipien

- Jedes Turnier hat **zwingend ein K.-o.** („Kein KO" gibt es nicht).
- Die Vorrunde braucht **keinen eindeutigen Sieger pro Spiel** (Unentschieden
  erlaubt); der K.-o. schon.
- Die Vorrunden-**Rangliste muss immer eindeutig** sein, soweit sie die
  Qualifikation betrifft → Shoot-Out.
- **Keine Freilose im K.-o.** (Hauptbaum = Zweierpotenz); Freilose nur in der
  Vorrunde.

## Globale UI-Änderung (alle Setup-Screens)

- **Titel-Hierarchie drehen:** der **Schritt-Name** (z. B. „Vorrunde") gross +
  fett, **„Neues Turnier"** klein und nicht fett darüber. Umsetzung: in
  `KubbAppBar` den Schritt-Titel als `title`, „Neues Turnier" als `eyebrow`.

---

## Screen 1 — Stammdaten

- **Liga ist global** (über Vereine hinweg), nicht pro Verein.
- Wird in Screen 1 ein **Verein** als Ausrichter gewählt, erscheinen die
  **Liga-Chips**: der Veranstalter **wählt die Liga aktiv** → Turnier ist
  liga-relevant.
- Wird **persönlich** veranstaltet (kein Verein), fallen **Liga-Wertung und
  Liga-Chips weg** → nicht liga-relevant.
- Punkte gehören zur globalen Liga ⇒ **keine per-Turnier-Punkte-Konfig**
  (frühere League-Points-Eingabe entfällt).

## Screen 2 — Teilnehmer

- **Min und Max** Teilnehmer (numerische Eingaben). (Bereits umgesetzt.)

## Screen 3 — „Vorrunde" (umbenannt von „Format")

- **Vorrunde-Achse:** Gruppenphase | Schoch.
- **K.-o.-Achse:** Single-Out | Double-Elimination | Trostturnier — **kein
  „Kein KO"** mehr.
- **Vorrunden-Scoring:** nur **Max. Sätze** (gerade Werte erlaubt, z. B. 2 →
  Unentschieden möglich). **Kein** „Sätze zum Sieg", **kein** Tiebreak in der
  Vorrunde.
- **Match-Zeit** und **Pause zwischen Matches** bleiben (Zeitmanagement).
- **Pitch-Sortierung:** „Top-Seeds auf tiefe Feldnummern" oder **„Manuell"** —
  bei „Manuell" einen echten **Reihenfolge-Editor** bauen (sortierbare Liste,
  schreibt `PitchPlan.order`). Heute ist „Manuell" eine tote Option.

## Screen 4 — Liga: **entfällt komplett**

Logik wandert in Screen 1 (siehe oben).

## Screen 5 — Gruppenphase

- **Nur sichtbar**, wenn in Screen 3 **Gruppenphase** gewählt ist
  (`vorrundeType == groupPhase`).
- **„Qualifier pro Gruppe" entfällt** als Eingabe → wird **berechnet** aus
  KO-Bracket-Grösse ÷ Anzahl Gruppen und read-only angezeigt. Anzahl Gruppen muss
  die Bracket-Grösse glatt teilen (Validierung). ⇒ KO-Grösse muss vor der
  Gruppen-Aufteilung feststehen (Schritt-Reihenfolge entsprechend anordnen).
- **Grouping-Strategie** (bleibt): Snake (serpentinenförmig nach Stärke) ·
  Seeded (blockweise) · Random (deterministisch mit Seed).

## Screen 6 — K.-o.

- **Keine Freilose:** KO-Grösse auf **Zweierpotenz** (4/8/16/32 …) beschränken,
  Byes-Vorschau entfällt.
- **Spiel um Platz 3:** **immer** (Toggle entfernen).
- **Seeding-Quelle:** Label **„Automatisch aus Vorrunde"** (nicht „Gruppenphase",
  da auch Schoch möglich) | „Manuell festlegen".
- **Shoot-Out:** **immer an**, kein Toggle/keine Konfig (siehe
  [P6_SHOOTOUT_TIEBREAK.md](P6_SHOOTOUT_TIEBREAK.md)).
- **Mighty-Finisher-Quali (Wildcard-Modell): entfernt.**
- **Per-KO-Runde-Regeln** (bleiben): Sätze zum Sieg / Match-Zeit / Pause /
  Tiebreak je Runde, numerische Eingaben.

---

## K.-o.-Modelle (beide wählbar, Erklärung per Modal)

Details + ASCII-Verläufe + Modal-Text: [P6_KO_MODELS.md](P6_KO_MODELS.md).

| Option | Zweiter Baum | Endergebnis |
|---|---|---|
| **Single-Out** | nein | Final = Platz 1/2 + Spiel um Platz 3 |
| **Double-Elimination (A)** | ja, gekoppelt (WB+LB+Grand Final) | Verliererbaum-Sieger kann noch Turniersieger werden; raus erst nach 2 Niederlagen |
| **Trostturnier (B)** | ja, separat | Final entscheidet Platz 1/2 endgültig; Nebenturnier spielt hintere Plätze; kein Weg zurück |

**In-App-Modal** (Info-Icon neben der KO-Auswahl) erklärt die drei Optionen —
Text steht in P6_KO_MODELS.md.

**Modell-B-Konfiguration:**
1. **Hauptbaum-Grösse** — Zweierpotenz, wie viele aus der Vorrunde in den Hauptbaum.
2. **Direkt ins Trostturnier (Anzahl)** — frei wählbare Zahl weiterer Vorrunden-
   Teams, die direkt im Trostturnier starten (zusätzlich zu den gestaffelt
   einsteigenden Hauptbaum-Verlierern).
3. **Name** des Trostturniers — frei wählbar.
4. **Eigene K.-o.-Regeln** je Trostturnier-Runde.
5. Halbfinal-Verlierer → **Spiel um Platz 3** (nie Trostturnier).

---

## Shoot-Out (Vorrunden-Tiebreak) — Kurzfassung

Voll: [P6_SHOOTOUT_TIEBREAK.md](P6_SHOOTOUT_TIEBREAK.md).

- **Immer an**, keine Konfiguration.
- Greift **nur bei quali-relevanten Gleichständen** (an der Cut-Linie / wer kann
  noch in die Quali rutschen), nicht bei kosmetischen Rängen.
- **Ergebnis = nur welche Seite gewonnen hat** (Sieger-Bestätigung), **Team-
  Konsens** wie beim Match. Keine Zeit, kein Score.
- Macht die Qualifikation **immer eindeutig** (ersetzt den ID-Fallback).

---

## Umsetzung — Arbeitsblöcke

**Reine Umbauten/Entfernungen (kein neues Domänen-Modell):**
- Screen-Umbenennung + Titel-Hierarchie (alle Screens).
- „Kein KO" entfernen; Vorrunde-Scoring reduzieren; Bronze-Toggle raus; Seeding-
  Label; Mighty-Finisher-Quali raus.
- Liga-Logik nach Screen 1 (Chips), Screen 4 löschen.
- Screen 5 nur bei Gruppenphase; Qualifier-pro-Gruppe berechnen.
- Pitch-„Manuell"-Reihenfolge-Editor.

**Drei echte Neubauten:**
1. **Trostturnier (Modell B)** — neuer Bracket-Typ inkl. gestaffeltem Einstieg +
   Direkt-aus-Vorrunde-Einspeisung → **eigener ADR** (analog ADR-0027), Server-
   Migrationen, Domänen-Logik, Read-Path, Tests.
2. **Shoot-Out-Tiebreak** — Gleichstand-Erkennung an der Cut-Linie, Konsens-
   Erfassung (Sieger), Ranking-Integration, UI, Tests.
3. **KO-Modell-Erklär-Modal** — UI + l10n.

**Vorgehen:** erst Detail-Umsetzungsplan (Block-Reihenfolge + Trostturnier-ADR)
zur Freigabe, dann Umsetzung in Blöcken mit Review-Agent gegen diese Spec + die
Regeln.

---

## Offene Detail-Regeln (klein, keine User-Entscheidungen)

- **Freilose im Trostturnier:** wenn Direkt-Starter + gestaffelte Verlierer keine
  glatte Zweierpotenz ergeben, braucht der Trostturnier-Baum intern Freilose
  (anders als der Hauptbaum). Regel beim Bauen festlegen.
- **Exakte Einstiegsrunden-Zuordnung** der Trostturnier-Verlierer → im ADR (analog
  `lbDropTarget`).
- **Gleicher Shoot-Out-Ausgang nicht eindeutig** (theoretisch): Wiederholung,
  sonst ID-Fallback als letzte Reserve.
