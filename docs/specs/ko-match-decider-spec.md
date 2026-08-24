# KO-Match-Entscheidung bei Gleichstand nach Spielzeit

- **Status**: Draft, Owner-Spezifikation 2026-08-24
- **Bezug**: ADR-0024 (Match-Punkte), ADR-0031 (Rundentimer), K14 (Remis in der Vorrunde)
- **Abgrenzung**: NICHT das bestehende Shoot-Out aus `packages/kubb_domain/lib/src/tournament/shootout.dart`. Jenes löst Gleichstände in der **Vorrunden-Tabelle** auf, um die Qualifikation zu bestimmen. Hier geht es um die Entscheidung **innerhalb eines einzelnen KO-Matches**.

## Regel (Owner-Wortlaut, strukturiert)

Der Rundentimer läuft über das Match. Was beim Ablauf der Spielzeit passiert, hängt an der Phase.

**Vorrunde.** Zeit abgelaufen, Satzstand zum Beispiel 1:1 → das Match wird so
abgeschlossen. Das Remis ist ein gültiges Ergebnis und zahlt einen Punkt
(ADR-0024 §2). Kein Stechen.

**KO-Phase.** Zeit abgelaufen und die Best-of-Serie ist noch nicht entschieden —
bei Best-of-5 also 2:2, 1:1 oder 0:0 — dann:

1. Der Timer wird **angehalten**.
2. Die beiden Kontrahenten spielen die vom Veranstalter konfigurierte
   Entscheidungsvariante (`ko_tiebreak_method`: Königsstoss-Entfernen oder
   Mighty-Finisher-Shootout).
3. Das läuft weiter, **bis die Best-of-Serie durch ist** — bei Best-of-5 wird
   also ein 3:2 oder 2:3 eingetragen.

Das muss für **jede** Best-of-Variante funktionieren, nicht nur für Best-of-5.

## Was heute existiert

Verifiziert am Stand 2026-08-24:

- Der **Zeitpunkt** ist modelliert: `MatchFormatSpec.tiebreakAfterSeconds`
  liefert `timeLimitSeconds`, wenn `tiebreakEnabled` gesetzt ist — der Tiebreak
  öffnet also genau beim Ablauf der Spielzeit. Der Wert wandert über
  `tournament_round_schedule.tiebreak_after_seconds` bis in
  `tournament_match_detail_screen.dart`.
- Die **Variante** ist konfigurierbar und wird persistiert:
  `ko_tiebreak_method` mit `classic_kingtoss_removal` und
  `mighty_finisher_shootout`.
- `MatchFormatSpec.finalNoTiebreak` deckt "ab Halbfinale ohne Tiebreak" ab.
- Der Rundentimer kennt Pausen: `tournament_round_schedule.paused_at` und
  `paused_accum_seconds`, gesteuert über die Pause/Resume-RPCs aus ADR-0031.

## Was fehlt

- **Nichts verbindet einen Tiebreak mit dem Anhalten der Uhr.** Eine Suche nach
  `paused_at` in Verbindung mit `tiebreak` oder `shootout` über alle Migrations
  bleibt leer. Der Timer läuft heute durch.
- Es gibt **keine Logik, die eine unentschiedene KO-Serie erkennt** und die
  Entscheidungsvariante erzwingt. `sets_to_win` / `max_sets` beschreiben die
  Serie, aber niemand prüft beim Zeitablauf, ob sie entschieden ist.
- Der eingetragene Endstand nach einem Stechen ist nicht definiert: das Stechen
  liefert einen Sieger, aber wie daraus ein 3:2 statt eines 2:2 wird, steht
  nirgends.

## Offene Fragen für die Umsetzung

1. **Wer hält an?** Pausiert der Server automatisch beim Erreichen von
   `tiebreak_after_seconds` mit unentschiedener Serie, oder tut das der
   Veranstalter über die bestehende Pause-Aktion und das System zeigt es nur an?
2. **Betrifft es die ganze Runde oder nur das Match?** `paused_at` sitzt auf
   `tournament_round_schedule`, also auf der Runde. Ein einzelnes Match im
   Stechen darf vermutlich nicht die Uhr aller anderen Courts anhalten.
3. **Wie viele Stechen?** Bei 0:0 in einem Best-of-5 fehlen drei Sätze. Wird
   dreimal gestochen, oder entscheidet ein Stechen die ganze Serie und der
   Endstand wird auf 3:2 normalisiert?
4. **Vorrunde mit ungerader Satzzahl.** Dort ist ein Remis unmöglich; greift die
   KO-Regel dann auch in der Vorrunde, oder wird schlicht weitergespielt?
