# Mängel-Report — 2026-08-22

Ein Befund, gefunden beim Aufsetzen der lokalen Demo-Turniere (`supabase/seed.sql`).
Reproduzierbar auf einer frischen lokalen DB, ohne Klickarbeit.

## 1. Schoch-Turniere ignorieren den Platz-Plan (P2) — behoben

> Behoben mit `20261337000000_stage_graph_assign_pitches.sql`: verbatim
> Re-Base von `tournament_start_stage_graph` aus `20261299000000` mit einem
> zusätzlichen `_tournament_assign_pitches`-Aufruf vor dem Go-Live-Update.
> Festgehalten von `supabase/tests/stage_graph_pitch_assignment_test.sql`,
> der ohne den Fix drei seiner vier Prüfungen verliert.

**Beobachtung:** Ein Turnier mit `pitch_plan` im Range-Modus legt beim Start
sämtliche Matches auf Platz 1. Bei "Demo Schoch 33 · Plätze 16-32" liegen alle
17 Partien der ersten Runde auf Platz 1 statt verteilt auf 16..32. Dasselbe bei
"Demo Schoch 16" (Plan 1..8, alles auf Platz 1).

Die Gruppenphase macht es richtig: "Demo Gruppenphase 24" verteilt die 60
Vorrundenspiele sauber über die acht handgewählten Plätze (3, 4, 7, 8, 11, 12,
15, 16), je sieben bis acht Partien.

**Ursache:** `tournament_start` ruft `_tournament_assign_pitches` an zwei
Stellen — im `round_robin_then_ko`-Zweig und im Runner für Folgerunden. Der
Zweig für `schoch_then_ko` / `swiss_then_ko` delegiert an
`tournament_start_stage_graph` und kehrt danach mit `RETURN` zurück, bevor eine
der beiden Stellen erreicht wird. Weder `tournament_start_stage_graph` noch
`tournament_generate_stage_matches` weisen selbst Plätze zu.

Die Route stammt aus ADR-0039 §4 (Schoch läuft seit dem über den Stufen-Graph);
die Platzvergabe ist beim Umbau nicht mitgewandert.

**Was funktioniert:** Die Auflösung des Plans selbst ist in Ordnung.
`_tournament_pitch_available` liefert für den Range 16..32 korrekt
`{16,…,32}` und für den Manual-Plan die handgesetzte Reihenfolge. Es fehlt nur
der Aufruf.

**Konsequenz:** Auf einem geteilten Gelände landen alle Schoch-Partien auf
demselben Platz. Der Veranstalter kann Plätze konfigurieren, sieht aber keine
Wirkung — und die Pitch-Call-Benachrichtigungen
(`_tournament_notify_round_per_pitch`) melden für jede Partie denselben Platz.

**Empfehlung:** `_tournament_assign_pitches(p_tournament_id, 1)` im
Stufen-Graph-Zweig nachziehen, analog zu `20261302000000` Zeile 245, und für
Folgerunden im Stage-Runner prüfen. Ein pgTAP-Test, der nach dem Start eines
Schoch-Turniers mit Range-Plan `count(distinct pitch_number) > 1` erwartet,
hält es fest.

**Reproduktion:**

```bash
supabase db reset          # legt die drei Demo-Turniere an
# als veranstalter tournament_start auf "Demo Schoch 33" rufen, dann:
select pitch_number, count(*) from tournament_matches
 where round_number = 1 group by 1;
```

---

## 2. Ein Freilos belegte einen echten Platz (P3) — behoben

**Beobachtung:** Bei ungerader Teilnehmerzahl erzeugt jede Schoch-Runde eine
Freilos-Zeile. Die bekam einen Platz aus dem Plan zugeteilt — bei "Demo Schoch
33" lag sie auf Platz 32, während sich sechzehn echte Partien die restlichen
sechzehn Plätze teilten. Auf einem Gelände mit genau so vielen Plätzen wie
Partien hätte das zwei echte Partien auf einen Platz gedrängt.

**Ursache:** `_tournament_assign_pitches` verteilte über alle Zeilen der Runde,
ohne Freilose auszunehmen. Eine Freilos-Zeile ist aber schon beim Anlegen
`finalized` mit gesetztem Sieger — sie wird nie gespielt.

**Behoben** mit `20261338000000_bye_matches_have_no_pitch.sql`: verbatim
Re-Base von `20261201000003` mit zwei Ergänzungen — Freilose werden vorab auf
`pitch_number = NULL` gesetzt (vor den Plan-Prüfungen, gilt also auch ohne
Plan) und aus der Verteilung ausgenommen. Die Änderung sitzt in der geteilten
Zuweisungsfunktion, gilt damit für Vorrunde, Gruppenphase, KO und Folgerunden
gleichermassen.

Kein Client-Code nötig: die UI zeigt einen Platz ohnehin nur, wenn einer
gesetzt ist. Ein Freilos zeigt jetzt schlicht keinen.

Festgehalten von drei weiteren Prüfungen in
`supabase/tests/stage_graph_pitch_assignment_test.sql` (neun Spieler auf genau
vier Plätzen); ohne den Fix fällt "the bye holds no pitch" um.

---

## 3. KO-Satzzahl war nicht auf ungerade festgelegt (P3) — behoben

**Beobachtung:** Ein KO-Match ist Best-of-N, und N muss ungerade sein, damit es
einen Sieger geben kann. Der Solo-Match erzwingt das seit `20260507000007` per
CHECK auf `matches.format` (`^bo([13579]|[1-9][13579])$`). Der Turnier-Pfad
hatte keine entsprechende Regel.

**Ursache:** `MatchFormatSpec.issues()` prüfte nur `max_sets >= 2*sets_to_win-1`,
also eine Untergrenze, keine Parität. Der KO-Block im Wizard hat gar kein
`max_sets`-Feld und leitet den Wert als `2*sets_to_win-1` ab — dadurch ist er
in der Praxis ungerade, aber das ist eine UI-Eigenschaft, keine Regel. Ein
importiertes oder von Hand geschriebenes Setup konnte einen geraden Wert
tragen, serverseitig prüfte nichts. Die per-KO-Runden-Overrides
(`ko_round_formats`) wurden überhaupt nicht validiert.

**Bewusst nicht abgedeckt: die Vorrunde.** Dort ist ein Unentschieden ein
gültiges Ergebnis (K14), und ADR-0024 §2 zahlt dafür einen Punkt
(`MatchOutcome.draw: 1`). Eine Ungerade-Pflicht in der Vorrunde würde diese
Regel zu totem Code machen. Owner-Entscheid 2026-08-24: die Regel gilt für KO
und Solo-Match, nicht für die Vorrunde.

**Behoben** an drei Stellen:

- `20261339000000_ko_sets_must_be_odd.sql` — `_tournament_ko_sets_all_odd` plus
  CHECK-Constraint auf `tournaments`. Als Tabellen-Constraint statt in
  `tournament_create`, damit sie greift, welches RPC auch schreibt. `NOT VALID`:
  neue und geänderte Zeilen werden geprüft, Bestandszeilen bleiben unangetastet
  — die Constraint kann separat validiert werden, sobald die gehosteten Daten
  als sauber bekannt sind.
- `MatchFormatSpec.issues({bool oddMaxSets = false})` in der Domain.
- Der Draft reicht `oddMaxSets: true` für `koMatchFormat` **und** für jeden
  Eintrag in `koRoundFormats` durch — letztere wurden vorher gar nicht geprüft.

Festgehalten von `supabase/tests/ko_sets_odd_test.sql` (8 Prüfungen, inklusive
einer, die den Constraint-Text exakt vergleicht, damit eine spätere Ausweitung
auf die Vorrunde auffällt) und zwei Domain-Tests.
