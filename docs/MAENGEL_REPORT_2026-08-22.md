# Mängel-Report — 2026-08-22

Ein Befund, gefunden beim Aufsetzen der lokalen Demo-Turniere (`supabase/seed.sql`).
Reproduzierbar auf einer frischen lokalen DB, ohne Klickarbeit.

## 1. Schoch-Turniere ignorieren den Platz-Plan (P2)

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
