# Mängel-Report — 2026-06-22

> **Status 2026-08-22: alle sechs Befunde abgearbeitet.** Nachgeprüft gegen den
> heutigen Stand. 1 ist der Stufen-Graph-Route in `tournament_start` zu
> verdanken (ADR-0039 §4) und über den lokalen Seed end-to-end verifiziert:
> sechzehn Teilnehmer ergeben acht Matches in Runde 1, nicht 120. 2 löst
> `20261312000000_tournament_remove_participant.sql` samt Dialog im
> Organizer-Dashboard. 3 und 4 hängen an `schoch_rounds` und der verdrahteten
> `pairRound`-Aktion, 5 an `20261314000000_override_writes_proposal_rows.sql`.
> 6 ist vermutlich mit `20261307000000_fix_public_read_grants.sql` erledigt —
> als einziger nicht sicher belegt.
>
> Der Report bleibt als Protokoll der Session stehen. Neue Befunde gehören in
> einen neuen Report, nicht hier hinein.

Befunde aus einer Testsession auf der lokalen Supabase-DB (Branch
`feature/setup-wizard-verbesserungen`). Aufgesetzt wurde ein 64-Team-Schoch-Turnier
(`schoch_then_ko`, 3er-Teams, KO über alle 64), dann der Schoch-Verlauf simuliert
und das Teilnehmer-Management des Veranstalters getestet.

## Schweregrad-Skala

- **P0** — Blockiert die Funktion komplett, App unbrauchbar in dem Flow.
- **P1** — Funktioniert teilweise, aber wesentliche Lücke; UX kaputt.
- **P2** — Feature fehlt oder ist nicht spec-konform; Workaround möglich.
- **P3** — Polish, Konsistenz, Datenqualität.

---

## 1. Schoch startet als Round-Robin statt Schweizer System (P1)

**Beobachtung:** Ein als `schoch_then_ko` angelegtes Turnier läuft beim Start
nicht als 7-Runden-Schoch (Monrad-Swiss), sondern als eine einzige
Round-Robin-Gruppe über alle Teilnehmer. Bei 64 Teams sind das **2016 Matches**
in "Runde 1" statt 32.

**Ursache:** `schochSinglePoolConfig` ([tournament_config_draft.dart:873](lib/features/tournament/data/tournament_config_draft.dart#L873))
setzt bewusst `group_count == 1`. `tournament_start` delegiert für die Hybrid-Formate
an `tournament_start_pool_phase` ([20261001000010_tournament_start_formats.sql:129](supabase/migrations/20261001000010_tournament_start_formats.sql#L129)),
und dieser Pfad materialisiert die Single-Pool als vollen Round-Robin. Der echte
Schoch-Paarungspfad (`SwissSystemStrategy` + `tournament_pair_round`) wird vom
App-Flow nie aufgerufen — explizit so vermerkt in
[organizer_dashboard_detail_screen.dart:512](lib/features/tournament/presentation/organizer_dashboard_detail_screen.dart#L512)
("Swiss/pairRound is intentionally NOT linked here", DOD-06).

**Konsequenz:** Ein Schoch-Turnier ist faktisch kein Schoch. Die Spec
(`docs/specs/schoch-swiss-pairing-buchholz-spec.md`) verlangt 7 Monrad-Runden mit
inkrementeller Paarung aus den Resultaten.

**Was funktioniert:** Die Domain-Logik ist da und korrekt. Die Simulation mit der
echten `SwissSystemStrategy` über `tournament_pair_round` lief sauber durch — 7 Runden,
0 Wiederholungspaarungen, jeder Spieler genau 7 verschiedene Gegner,
`tournament_pool_standings.total_points` deckungsgleich mit den Domain-Summen (64/64).
Es fehlt nur die Verdrahtung.

**Empfehlung:** Start-Pfad für `schoch`/`schoch_then_ko` von "RR-Pool materialisieren"
auf "Schoch-Runde 1 paaren" umstellen und die Client-Brücke aus #4 bauen.

---

## 2. Veranstalter kann Teilnehmer nicht entfernen (P1)

**Beobachtung:** Der Veranstalter kann ein registriertes Team nicht aus der
Teilnehmerliste entfernen.

**Ursache:** Es gibt keinen passenden RPC.

- `tournament_withdraw` lässt nur den Teilnehmer selbst raus
  (`only the participant can withdraw`, Vergleich `user_id <> auth.uid()`). Der
  Veranstalter ist ausgeschlossen.
- `tournament_reject_registration` ist Creator-only, greift aber nur bei Status
  `pending` oder `waitlist`. Bestätigte Teilnehmer (`confirmed`) sind damit nicht
  entfernbar.
- Einen `remove`/`kick`/`disqualify`-RPC gibt es nicht.

Dazu eine UI-Lücke: Selbst für `pending`/`waitlist`, wo `reject_registration`
funktioniert, ist die Aktion im Organizer-Dashboard nicht verdrahtet (Owner-Beobachtung,
UI noch zu verifizieren).

**Konsequenz:** No-Shows, Doppelregistrierungen und Fehlanmeldungen bleiben in der
Liste hängen; der Veranstalter hat keine Handhabe.

**Workaround in dieser Session:** Ein hängengebliebenes Warteliste-Team wurde per
`reject_registration` (als Veranstalter) entfernt — der RPC kann das für `waitlist`,
er ist nur nicht über das UI erreichbar.

**Empfehlung:**
- Neuer RPC `tournament_remove_participant(participant_id, reason)` für den
  Veranstalter, der auch `confirmed` entfernt (mit Audit-Event und Waitlist-Nachrückung
  analog `withdraw`).
- Remove-Button in der Teilnehmerliste des Organizer-Dashboards.
- Verhalten bei laufendem Turnier klären: Matches der entfernten Einheit als Forfeit
  werten, nicht hart löschen.

---

## 3. Schoch-Rundenzahl wird nicht gespeichert (P2)

**Beobachtung:** Im Setup-Wizard lässt sich die Schoch-Rundenzahl (5–9) einstellen,
der Wert landet aber nicht in der DB.

**Ursache:** `_schochRounds` ist reiner UI-State
([tournament_setup_wizard.dart:101](lib/features/tournament/presentation/tournament_setup_wizard.dart#L101)),
wird in der `SchochConfigSection` nur angezeigt (Zeile 2164) und nicht in den Draft
geschrieben, der an `createTournament(draft)` geht (Zeile 247). Ein passender
Setup-Key oder eine Spalte existiert auch nicht.

**Konsequenz:** Die Wahl des Veranstalters ist nach dem Speichern verloren; die
Rundenzahl ist undefiniert und müsste zur Laufzeit getrieben werden.

**Empfehlung:** `schoch_rounds` in den Setup-JSON aufnehmen (z.B. in
`pool_phase_config`) und beim Phasenende auslesen, um nach Runde N automatisch ins
KO zu wechseln.

---

## 4. Schoch-Auto-Pairing ab Runde 2 nicht verdrahtet (P2)

**Beobachtung:** Nach Runde 1 gibt es im App-UI keinen Weg, die nächste Runde zu
erzeugen — weder automatisch noch von Hand.

**Ursache:** `SwissSystemStrategy.planRound`
([swiss_system.dart](packages/kubb_domain/lib/src/tournament/pairing/swiss_system.dart))
berechnet die nächste Runde korrekt und ist getestet (inkl. Golden gegen SM Einzel
2026). Der Server-RPC `tournament_pair_round`
([20260801000001_pair_round_swiss.sql](supabase/migrations/20260801000001_pair_round_swiss.sql))
validiert und inserted vom Client gelieferte Paarungen — er rechnet selbst nichts.
Es fehlt der Client-Teil: kein Code ruft die Strategy auf und schickt das Ergebnis
an den RPC. Keinen RPC, der Runde N>1 selbst paart, gibt es ebenfalls.

**Konsequenz:** Schoch bleibt nach Runde 1 stehen (hängt mit #1 zusammen).

**Empfehlung:** `TournamentActions.pairRound` plus Port/Repository-Methode bauen; im
Organizer-Dashboard nach Rundenabschluss "Nächste Runde paaren" anbieten (Strategy
rechnet → `tournament_pair_round`). Im Design als OD-M5-04 (Client-Side-Pairing)
vorgesehen, aber es existiert kein Umsetzungs-Task.

---

## 5. organizer_override schreibt keine Set-Score-Proposals (P3)

**Beobachtung:** Nach `tournament_organizer_override` stehen in
`tournament_pool_standings` `kubbs_scored = 0` und `kubbs_conceded = 0`.

**Ursache:** Der Override setzt nur `final_score_a/b` + `winner`, legt aber keine
`tournament_set_score_proposals` an. Die Kubb-Differenz in den Standings speist sich
aus den Proposals.

**Konsequenz:** `total_points` (EKC) stimmt, aber der Kubb-Differenz-Tiebreaker ist 0.
Bei Punktgleichstand kann die Rangfolge dadurch falsch sein.

**Empfehlung:** Override optional die Set-Scores mitschreiben lassen, oder die
Kubb-Differenz in den Standings aus `final_score_*` ableiten.

---

## 6. Lokaler Keypair-Login ohne service_role-Grants kaputt (Setup/Infra)

**Beobachtung:** Auf einer frischen lokalen Supabase-DB schlägt der Keypair-Login für
jeden User fehl (HTTP 500 `challenge_lookup_failed` bzw. `credential_lookup_failed`).

**Ursache:** Die `keypair-verify` Edge-Function läuft als `service_role`, dem lokal
`SELECT, DELETE` auf `keypair_challenges` und `SELECT` auf `user_credentials` /
`user_profiles` fehlen. Die committeten Migrationen vergeben diese Grants nirgends.

**Konsequenz:** Lokales Login-Testing ist ohne manuellen Fix unmöglich. Offene Frage:
Hat die Prod-DB diese Grants über eine andere Quelle? Sonst wäre der Login auch dort
betroffen.

**Fix (lokal angewandt, verifiziert):**

```sql
GRANT SELECT, DELETE ON public.keypair_challenges TO service_role;
GRANT SELECT ON public.user_credentials TO service_role;
GRANT SELECT ON public.user_profiles TO service_role;
NOTIFY pgrst, 'reload schema';
```

Danach läuft der Restore-Login end-to-end (HTTP 200 + JWT).

**Empfehlung:** Grants in eine Migration aufnehmen (Prod-Parität), oder bestätigen,
dass Prod sie anderweitig hat.

---

## Session-Kontext

Test-Turnier `Schoch-Cup 64 (Test)` (`fecc932e-53c9-4acd-b078-cf5d13333d5d`) auf der
lokalen DB. Veranstalter: Club `testclub` (Owner `orger`). Team `Sopiast` enthält den
Test-Login-User für das Spieler-Testing. Die Befunde #1, #3, #4, #5 betreffen den
ausgelieferten Code, nicht das Seeding; #2 ist die in dieser Session gemeldete
Veranstalter-Lücke; #6 ist eine lokale Setup-Hürde mit möglicher Prod-Relevanz.
