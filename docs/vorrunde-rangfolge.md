# Vorrunde: Rangfolge, Remis und Shoot-out

> Referenz-Doku zur Funktionsweise der Vorrunden-Auswertung. Ergänzt `glossar.md`.
> **Massgeblich für die Ranglisten-Kriterien ist `docs/specs/vorrunde-ranking-spec.md`** (Single Source of Truth). Dieses Dokument ist die erzählerische Ergänzung dazu und darf den dort definierten Kriterien nicht widersprechen.

## Grundsatz
In der Vorrunde gibt es **keinen** Match-Tiebreak. Partien dürfen unentschieden (remis) enden.
Ein Tiebreak am Satz-/Partie-Ende (wer gewinnt die Partie) ist erst im **KO** relevant — in der Vorrunde wird er **nicht konfiguriert und nicht ausgeführt**.

## Auflösungs-Reihenfolge bei Gleichstand
Nur für die qualifikations-/setz-relevanten Ränge, nach Abschluss der Vorrunde. Die Reihenfolge ist **typ-spezifisch** — der Unterschied liegt im zweiten Kriterium:

- **Schoch:** Gesamtpunkte → **Buchholz** → Shoot-out.
- **Gruppenphase:** Gesamtpunkte → **Kubb-Differenz** → Shoot-out.

Buchholz misst die Stärke der Gegner und ist nur bei Schoch aussagekräftig, weil dort jeder andere Gegner trifft. In der Gruppenphase spielt jeder gegen dieselben Gegner, darum ist Buchholz für punktgleiche Teilnehmer identisch und trennt sie nie — deshalb entscheidet dort die Kubb-Differenz (Begründung: `vorrunde-ranking-spec.md` §4). **Shoot-out** ist in beiden Fällen der letzte Entscheider zwischen genau den betroffenen Teams.

## Schoch
- **1 bis n Runden**, wählbar.
- Während der Runden: Remis erlaubt und ohne Folge. Gleiche Tabellenränge während der Vorrunde sind egal (z.B. 3x Rang 5, danach Rang 8).
- **Nach Abschluss der Vorrunde** wird die Rangfolge nur dort aufgelöst, wo sie über **KO-Qualifikation oder Setz-Reihenfolge** entscheidet — in der Reihenfolge **Gesamtpunkte → Buchholz → Shoot-out** (siehe oben).
  - Beispiel: KO = Top 16. Ist Rang 16 vierfach vergeben → Shoot-out unter diesen 4, bis klar ist, wer Rang 16 holt; die anderen sind raus.
  - Ist ein qualifizierter Rang (z.B. Rang 5) mehrfach vergeben → Shoot-out, um die Reihenfolge unter ihnen zu klären (für die Setzung).
  - Alle Ränge **hinter** dem Qualifikations-Cut sind irrelevant — kein Shoot-out nötig.
  - Der Cut hängt **dynamisch von der KO-Grösse** ab.

## Gruppenphase
- Beispiel: 4 Gruppen à 8 Teams. Pro Gruppe eine Runde **jeder gegen jeden**.
- Während der Runde: Remis erlaubt.
- **Nach der Runde**: die Reihenfolge bei Gleichstand wird **pro Gruppe** geklärt — in der Reihenfolge **Gesamtpunkte → Kubb-Differenz → Shoot-out** (kein Buchholz, siehe oben) — nur für die qualifikations-/setz-relevanten Ränge.
- Die **n Gruppenbesten** ziehen ins KO. Zuordnung je nach Begegnungs-Regel: **Beste vs. Schlechteste** oder **1. vs. 2.**

## Konsequenz für die Umsetzung
- **Jetzt (Welle C):** Den Vorrunden-Match-Tiebreak entfernen — weder Konfiguration noch Ausführung in der Vorrunde. Den einstellbaren Ranglisten-Kriterien-Selektor ("Schweizer-konform" / Standard / Custom) aus dem Setup nehmen. Bis das Shoot-out gebaut ist, läuft im Hintergrund eine feste Sortierung weiter (damit die Qualifikation bestimmbar bleibt) — bei Schoch **Gesamtpunkte → Buchholz**, bei der Gruppenphase **Gesamtpunkte → Kubb-Differenz**.
- **Später (eigene Aufgabe, Engine-Ebene):** Automatisches Shoot-out als letzter Schritt (nach dem typ-spezifischen zweiten Kriterium) zur Auflösung der qualifikations-/setz-relevanten Gleichstände nach der Vorrunde — Schoch global, Gruppenphase pro Gruppe, Cut dynamisch nach KO-Grösse. Hängt eng mit dem Stufen-Graph-Redesign zusammen.
