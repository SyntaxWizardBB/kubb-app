# P6 — Shoot-Out (Vorrunden-Tiebreak)

> **Status:** verbindliche Konzept-Entscheidung (User, Juni 2026).
> **Zweck:** Eindeutige Qualifikation bei exaktem Gleichstand nach der Vorrunde.
> Ersetzt das frühere „Mighty-Finisher-Quali"-Wildcard-Modell (slots/pool
> **entfallen**). Ergänzt die Tiebreak-Kette in
> [P6_RULES_DECISIONS.md](P6_RULES_DECISIONS.md) §H. Teil der Gesamt-Spec
> [P6_SETUP_WIZARD_SPEC.md](P6_SETUP_WIZARD_SPEC.md).

## Was es ist

Der **Shoot-Out** ist die **letzte Tiebreak-Stufe** der Vorrunde. Er stellt
sicher, dass **immer eindeutig** ist, wer sich für den K.-o. qualifiziert — dort,
wo nach allen regulären Kriterien (Punkte, Buchholz, direkter Vergleich,
Kubb-Differenz …) Teams exakt gleichauf wären und die Rangliste sonst auf den
willkürlichen Teilnehmer-ID-Fallback fiele.

- **Immer an.** Kein Toggle, keine Konfiguration im Wizard. (Die alten Felder
  `slots`/`pool` entfallen; das frühere „Wasserschloss"-Wildcard-Modell ist
  verworfen.)
- **Ergebnis = nur welche Seite gewonnen hat** — eine einfache Sieger-Bestätigung,
  keine Zeitmessung, kein Score. (Ersetzt die zwischenzeitlich diskutierte
  Zeit-Variante.)

## Geltungsbereich — nur quali-relevante Ränge

Der Shoot-Out wird **nur** für Gleichstände ausgelöst, die die **Qualifikation
beeinflussen**:

- Teams an der **Cut-Linie** des K.-o. (z. B. Gleichstand um die letzten
  Qualifikationsplätze), und
- Teams, die durch den Shoot-Out **potenziell noch in die Quali** kommen können.

Gleichstände auf Rängen, die **weder rein- noch rausfallen** können (rein
kosmetische Platzierungen unterhalb/oberhalb der relevanten Zone), lösen
**keinen** Shoot-Out aus — sie sind für die Qualifikation irrelevant.

## Ablauf

1. **Rangliste berechnen** — nach der Vorrunde mit allen normalen Kriterien.
2. **Quali-relevanten Gleichstand erkennen** — verbleiben an/um die Cut-Linie
   Teams exakt gleichauf, sodass nicht eindeutig ist, wer sich qualifiziert,
   bildet die App eine **Shoot-Out-Gruppe**.
3. **Shoot-Out delegieren** — die betroffenen Teams bekommen einen Shoot-Out-
   Auftrag (Benachrichtigung/Task).
4. **Ergebnis erfassen — Team-Konsens** — analog Match-Flow: die beteiligten
   Teams melden, **welche Seite gewonnen hat**, und bestätigen sich gegenseitig.
5. **Qualifikation finalisieren** — der/die Sieger des Shoot-Outs rücken auf die
   Qualifikationsplätze; das Ergebnis ersetzt den ID-Fallback. Bei mehr als zwei
   gleichauf-Teams werden so viele Sieger-Vergleiche durchgeführt, bis eindeutig
   ist, wer die offenen Quali-Plätze belegt.
6. **KO-Seeding** — die Seeding-Quelle „aus Vorrunde" nutzt die so finalisierte
   Rangliste.

## Aktueller Code-Stand (vor Umsetzung)

- `TiebreakerCriterion.mightyFinisherShootout` existiert, ist im Ranking aber ein
  **No-Op** ([pool_cut.dart:118-121](packages/kubb_domain/lib/src/tournament/pool_cut.dart#L118):
  „physical decider; not resolvable from stats" → gibt `0` zurück).
- `MightyFinisherQuali {enabled, slots, pool}` existiert als Setup-Feld und wird
  von Create/Update/Get persistiert — die Stage selbst ist nie gebaut.

## Noch zu bauen

- **Quali-relevante Gleichstand-Erkennung** an der Cut-Linie (nicht alle Ränge).
- **Shoot-Out-Datensatz** (pro Gruppe: beteiligte Teams + Sieger + Konsens-Status),
  wiederverwendet wo möglich den bestehenden Match-Konsens-Flow.
- **UI**: Shoot-Out-Auftrag + Sieger-Meldung + gegenseitige Bestätigung.
- **Ranking-Integration**: bei quali-relevantem Gleichstand die Gruppe per
  Shoot-Out-Sieger auflösen statt per ID.
- **Setup-Vereinfachung**: „Shoot-Out"-Toggle und `slots`/`pool` ganz aus dem
  Wizard entfernen (immer an); Datenmodell-Altfelder dürfen bleiben.
