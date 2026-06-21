# Vorrunde: Rangfolge, Remis und Shoot-out

> Referenz-Doku zur Funktionsweise der Vorrunden-Auswertung. Ergaenzt `glossar.md`.

## Grundsatz
In der Vorrunde gibt es **keinen** Match-Tiebreak. Partien duerfen unentschieden (remis) enden.
Ein Tiebreak am Satz-/Partie-Ende (wer gewinnt die Partie) ist erst im **KO** relevant — in der Vorrunde wird er **nicht konfiguriert und nicht ausgefuehrt**.

## Aufloesungs-Reihenfolge bei Gleichstand (Schoch und Gruppenphase identisch)
Nur fuer die qualifikations-/setz-relevanten Raenge, nach Abschluss der Vorrunde:
1. **Gesamtpunkte** — bei Gleichstand weiter zu
2. **Buchholz** — bei weiterhin Gleichstand weiter zu
3. **Shoot-out** — der letzte Entscheider zwischen genau den betroffenen Teams.

## Schoch
- **1 bis n Runden**, waehlbar.
- Waehrend der Runden: Remis erlaubt und ohne Folge. Gleiche Tabellenraenge waehrend der Vorrunde sind egal (z.B. 3x Rang 5, danach Rang 8).
- **Nach Abschluss der Vorrunde** wird die Rangfolge nur dort aufgeloest, wo sie ueber **KO-Qualifikation oder Setz-Reihenfolge** entscheidet — in der Reihenfolge **Gesamtpunkte → Buchholz → Shoot-out** (siehe oben).
  - Beispiel: KO = Top 16. Ist Rang 16 vierfach vergeben → Shoot-out unter diesen 4, bis klar ist, wer Rang 16 holt; die anderen sind raus.
  - Ist ein qualifizierter Rang (z.B. Rang 5) mehrfach vergeben → Shoot-out, um die Reihenfolge unter ihnen zu klaeren (fuer die Setzung).
  - Alle Raenge **hinter** dem Qualifikations-Cut sind irrelevant — kein Shoot-out noetig.
  - Der Cut haengt **dynamisch von der KO-Groesse** ab.

## Gruppenphase
- Beispiel: 4 Gruppen a 8 Teams. Pro Gruppe eine Runde **jeder gegen jeden**.
- Waehrend der Runde: Remis erlaubt.
- **Nach der Runde**: die Reihenfolge bei Gleichstand wird **pro Gruppe** geklaert — in derselben Reihenfolge **Gesamtpunkte → Buchholz → Shoot-out** — nur fuer die qualifikations-/setz-relevanten Raenge.
- Die **n Gruppenbesten** ziehen ins KO. Zuordnung je nach Begegnungs-Regel: **Beste vs. Schlechteste** oder **1. vs. 2.**

## Konsequenz fuer die Umsetzung
- **Jetzt (Welle C):** Den Vorrunden-Match-Tiebreak entfernen — weder Konfiguration noch Ausfuehrung in der Vorrunde. Den einstellbaren Ranglisten-Kriterien-Selektor ("Schweizer-konform" / Standard / Custom) aus dem Setup nehmen. Bis das Shoot-out gebaut ist, laeuft im Hintergrund eine feste Sortierung **Gesamtpunkte → Buchholz** weiter (damit die Qualifikation bestimmbar bleibt).
- **Spaeter (eigene Aufgabe, Engine-Ebene):** Automatisches Shoot-out als letzter Schritt (nach Gesamtpunkte → Buchholz) zur Aufloesung der qualifikations-/setz-relevanten Gleichstaende nach der Vorrunde — Schoch global, Gruppenphase pro Gruppe, Cut dynamisch nach KO-Groesse. Haengt eng mit dem Stufen-Graph-Redesign zusammen.
