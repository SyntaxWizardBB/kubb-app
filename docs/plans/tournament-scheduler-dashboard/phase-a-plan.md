# Phase-A-Umsetzungsplan — Schedule-Engine + Sync-Uhr

**Milestone:** Veranstalter-Dashboard & zeitgesteuerter Turnier-Ablauf.
**Branch:** `feat/tournament-scheduler-dashboard` (von `main`).
**Bezug:** ADR-0031 (`docs/adr/0031-timed-tournament-runner-and-organizer-dashboard.md`),
Milestone-Spec `humanPlan/Milestone-Dashboard-Plan.md`, CLAUDE.md (Messaging-Framework
ADR-0029 „kein neues Polling", additive Migrationen NIE `db reset`, `CREATE OR REPLACE`
nur auf aktueller Definition, Design-System verbindlich, Solo-Training TABU).

> **Migrations-Nummerierung:** Auf diesem Branch ist die letzte Migration `20261249000000`.
> Der T1-Fix-Branch (`fix/t1-organizer-score-override`) belegt bereits `20261250000000`
> (organizer_override_scheduled) und wird nach `main` gemergt. Um Kollisionen zu vermeiden,
> startet Phase A bei **`20261251000000`**. Vor dem Bau prüfen, ob T1 schon gemergt ist,
> und ggf. fortlaufend anpassen.

> **RE-BASE-PFLICHT (höchstes Risiko):** Die 5 Materialisierungs-RPCs (`tournament_start`,
> `tournament_start_pool_phase`, `tournament_pair_round`, `tournament_start_ko_phase`)
> sind zuletzt in **`20261201000032_tournament_per_tournament_manage_gate.sql`** definiert,
> `tournament_generate_stage_matches` in **`20261247…`**. Jedes `CREATE OR REPLACE` MUSS
> auf dem echten letzten On-Disk-Body re-basen (Diff!), sonst wird das Per-Tournament-Gate
> `tournament_caller_can_manage` zurückgespielt. Nur die eingefügte
> `PERFORM _tournament_upsert_round_schedule(...)`-Zeile darf neu sein.

## Bau-Reihenfolge (Domain → Server → Client), je 1 Commit/Block

```
A3a  Domain: MatchTimer um Pause/Hold erweitern (pure Dart, isoliert testbar)
A1   Server: tournament_round_schedule (CDC) + Ableitung in den 5 RPCs   [251/252]
A2   Server: Trigger tournament_match_autostart (started_at-Anker)        [253]
A3b  Server: RPC app_server_now()                                         [254]
A3c  Client: serverClockOffsetProvider + schedule-CDC-Provider + MatchTimer-Wiring
A4   Client: Pausen-Countdown / Hold-Anzeige Widgets
```
A3a (Domain) vor A1 (Restzeit-Parität) und A3c/A4. A1 vor A2 (Trigger braucht die Tabelle).
A3b vor A3c (Provider ruft die RPC). A4 zuletzt (konsumiert alles).

---

## BLOCK A3a — Domain: `MatchTimer` um Pause/Hold

**Restzeit-Formel (verbindlich, ADR-0031):**
```
effective_elapsed = (now − startsAt) − pausedAccumSeconds
                    − (pausedAt != null ? (now − pausedAt) : 0)
remaining         = durationSeconds − effective_elapsed   // < 0 ⇒ abgelaufen
```

**Ändern:** `packages/kubb_domain/lib/src/tournament/match_timer.dart`
- Neue optionale Felder: `DateTime? pausedAt`, `int pausedAccumSeconds = 0`, `bool onHold = false`
  (Hold = `awaiting_results`/Tiebreak; friert wie Pause, semantisch getrennt für UI).
- `elapsed`/`remaining`/`isExpired`/`fractionElapsed` auf die Pause-korrigierte Formel.
- `==`/`hashCode` erweitern. Getter `bool get isFrozen => onHold || pausedAt != null;`.
- **Rückwärtskompatibel:** Defaults ⇒ exakt heutiges Verhalten (Anker `startedAt` bleibt).

**Tests:** `packages/kubb_domain/test/tournament/match_timer_test.dart` erweitern — Default-Pfad
unverändert grün; Pause friert `remaining`; Resume zieht akkumulierten Betrag ab; `onHold` friert
(`isExpired` bleibt true); Mehrfach-Pause summiert korrekt; `now < startsAt ⇒ remaining == duration`.

**Verifikation:** `cd packages/kubb_domain && dart analyze && dart test test/tournament/match_timer_test.dart`

---

## BLOCK A1 — Server: `tournament_round_schedule` (CDC) + Ableitung

**Migration 1:** `20261251000000_tournament_round_schedule.sql`

DDL (additiv): Tabelle mit `tournament_id`, `stage_node_id` (NULL=klassisch), `round_number`,
`phase`, `status CHECK IN (published|call|running|awaiting_results|completed)`, `published_at`,
`starts_at` (= published_at + break_seconds), `ends_at` (= starts_at + match_seconds),
`break_seconds`, `match_seconds`, `tiebreak_after_seconds`, `paused_at`, `paused_accum_seconds`.
`UNIQUE (tournament_id, round_number, stage_node_id)` + partieller Unique-Index für
`stage_node_id IS NULL` + Index auf `tournament_id`.

RLS + CDC (Muster `20261234000000_cdc_tournament_matches.sql`):
- `ENABLE ROW LEVEL SECURITY`; SELECT-Policy `tournament_round_schedule_read` auf der
  **CDC-Filterspalte `tournament_id`** (nicht-draft ODER eigener Draft — spiegelt
  `tournament_matches_read`). Optional anon-Policy (siehe OE-3).
- Kein Client-Write: alle Schreibzugriffe via SECURITY-DEFINER-RPC.
- `ALTER PUBLICATION supabase_realtime ADD TABLE public.tournament_round_schedule;`
  (REPLICA IDENTITY DEFAULT; Konsument liest nur NEW).

Zentraler Helper `_tournament_upsert_round_schedule(p_tournament_id, p_stage_node_id,
p_round_number, p_phase, p_match_seconds, p_break_seconds, p_tiebreak_after, p_published_at)` —
INSERT mit `make_interval`, idempotent (`ON CONFLICT … DO NOTHING` für non-NULL;
expliziter Existenz-Guard für den NULL-Pfad, da Partial-Index nicht via ON CONFLICT matcht).

Config-Ableitung pro Phase (keine neuen Felder, E2 gelockt):
- Vorrunde/klassisch: `tournaments.match_format` → `round_time_seconds` (Match),
  `break_between_matches_seconds` (Pause). Key-Fallback `round_time_seconds`↔`time_limit_seconds`.
- KO/Final: `tournaments.ko_round_formats[]` (`time_limit_seconds`,
  `break_between_matches_seconds`, `tiebreak_after_seconds`, `final_no_tiebreak`) je Runde,
  Fallback `ko_match_format`.

**Migration 2:** `20261252000000_round_schedule_materialize.sql` — re-basiert die 5 RPCs auf
ihre `…032`/`…247`-Bodies und fügt je `PERFORM _tournament_upsert_round_schedule(...)` ein:
1. `tournament_start` (Runde 1; nur aktive Runde, auch bei round_robin — OE-2).
2. `tournament_start_pool_phase` (`phase='group'`, Runde 1).
3. `tournament_pair_round` (swiss, neue Runde).
4. `tournament_start_ko_phase` (pro KO-Runde im bestehenden Pitch-Loop; `phase='ko'`/`'final'`).
5. `tournament_generate_stage_matches` (`p_stage_node_id=p_node_id`) — wird vom Stage-Runner-
   Trigger (`20261228000000`) aufgerufen ⇒ Schedule-Materialisierung läuft result-getrieben
   automatisch (OE-6: Stage-Zeitquelle `tournament_stages.config` vs `match_format` verifizieren).

**Tests (pgTAP):** `supabase/tests/round_schedule_test.sql` — `has_table`, Spalten/Checks,
CDC-Publication-Mitgliedschaft (`pg_publication_tables`), RLS-Filterspalten-Parität
(`tournament_id`), Ableitungs-Fixture (`match_format` 1800/300 → 1 Zeile, starts/ends korrekt),
Idempotenz, KO-2-Runden → 2 Zeilen. Ergänzung in `realtime_cdc_rls_test.sql`.

**Verifikation:** `supabase migration up` (additiv); pgTAP in `BEGIN…ROLLBACK`; **RPC-Body-Diff**;
`git status` (kein Übergriff).

---

## BLOCK A2 — Server: Trigger `tournament_match_autostart`

**Migration:** `20261253000000_tournament_match_autostart.sql`

`BEFORE INSERT OR UPDATE OF status ON tournament_matches`: wenn `NEW.started_at IS NULL`,
zugehörige `tournament_round_schedule.starts_at` der Runde lesen und
`NEW.started_at := greatest(v_starts_at, now())` setzen. Idempotent
(`IF NEW.started_at IS NOT NULL THEN RETURN`). Match ohne Schedule-Zeile ⇒ no-op
(Bestand bricht nicht; Score-RPC-`COALESCE` bleibt Backstop). `tournament_matches` ist CDC ⇒
`started_at` pusht automatisch.

**Tests (pgTAP):** `supabase/tests/match_autostart_test.sql` — Schedule in Vergangenheit ⇒
`started_at=starts_at`; Zukunft erlaubt; ohne Schedule NULL; bereits gesetzt nicht überschrieben.

**Verifikation:** `supabase migration up`; pgTAP; Score-RPC-Diff unverändert.

---

## BLOCK A3b — Server: `app_server_now()`

**Migration:** `20261254000000_app_server_now.sql`
```sql
CREATE OR REPLACE FUNCTION public.app_server_now()
RETURNS timestamptz LANGUAGE sql STABLE AS $$ SELECT now(); $$;
GRANT EXECUTE ON FUNCTION public.app_server_now() TO authenticated, anon;
```
Rückgabe UTC; Client vergleicht mit `DateTime.now().toUtc()`.

**Tests (pgTAP):** existiert, EXECUTE-Grants, Rückgabe nahe `now()` (<1s).

---

## BLOCK A3c — Client: Offset + Schedule-CDC + MatchTimer-Wiring

1. **Repository** `lib/features/tournament/data/tournament_repository.dart`:
   `fetchServerNow()` (`rpc('app_server_now')`), `watchRoundSchedule(TournamentId)`
   (`_realtime.subscribe(table:'tournament_round_schedule', filterColumn:'tournament_id', …)`
   analog `watchTournamentMatches`). Port erweitern:
   `packages/kubb_domain/lib/src/ports/tournament_remote.dart`.
2. **Domain-Modell** `packages/kubb_domain/lib/src/tournament/round_schedule.dart`:
   `TournamentRoundScheduleRef` + `RoundStatus`-Enum; Export in `kubb_domain.dart`.
3. **CDC-Parser** `lib/features/tournament/data/tournament_models.dart`:
   `tournamentRoundScheduleRefFromCdcRow` (nutzt vorhandene `_asInt`/`_asDateOrNull`).
4. **serverClockOffsetProvider** `lib/features/tournament/application/server_clock_provider.dart`:
   `FutureProvider<Duration>` (einmaliger Sync, KEIN Polling); `serverCorrectedNow(offset)`
   für den 1s-UI-Ticker (bleibt reines Rendering, CLAUDE.md-Ausnahme).
5. **Realtime-Provider** in `tournament_realtime_provider.dart`:
   `tournamentRoundScheduleRealtimeProvider` (StreamProvider.autoDispose.family) invalidiert
   `tournamentRoundScheduleProvider` — Muster der 3 bestehenden Provider.
6. **Wiring** `match_countdown.dart` + `tournament_match_detail_screen.dart`:
   `MatchCountdown` um `serverOffset`, `pausedAt`, `pausedAccumSeconds`, `onHold`;
   `_nowValue() = DateTime.now().toUtc().add(serverOffset)`; Detail-Screen speist aus
   `serverClockOffsetProvider` + passender Schedule-Zeile.

**Tests:** Port-Contract (Fake-Remote), `server_clock_provider_test.dart` (Offset, kein
Timer.periodic), `match_countdown_test.dart` (Offset + Pause friert), CDC-Parser-Test.

**Verifikation:** `flutter analyze` + `dart analyze`; `flutter test test/features/tournament/...`;
`dart test` (kubb_domain).

---

## BLOCK A4 — Client: Pausen-Countdown / Hold-Anzeige

`lib/features/tournament/presentation/widgets/round_phase_countdown.dart` (Design-System
verbindlich): drei Zustände aus `RoundStatus` + `isFrozen` —
1. **Pausen-/Call-Countdown** (`published`/`call`, `now < startsAt`): „Nächste Runde in mm:ss".
2. **Match-Countdown** (`running`): bestehendes `MatchCountdown` (server-/pause-korrigiert).
3. **Hold** (`awaiting_results`/Tiebreak): „Zeit angehalten — Resultat eintragen" / „Tiebreak",
   eingefrorene Uhr (`onHold`), amber (`wood400`)/`miss`.
Detail-Screen ersetzt das direkte `MatchCountdown` (Zeile 561–577) durch `RoundPhaseCountdown`.
Neue l10n-Keys (`tournamentRoundCallCountdown`, `tournamentRoundHold`,
`tournamentRoundTiebreakHold`). **Fallback `schedule == null`** (laufende Bestands-Turniere) auf
die heutige reine `started_at`-Uhr.

**Tests:** `round_phase_countdown_test.dart` — alle drei Zustände + Übergänge + Hold friert.

**Verifikation:** `flutter analyze`; Widget-Tests; Design-Abgleich gegen `docs/design/ui_kits/app/`.

---

## Schnittstelle zu Phase E (pg_cron) — nur Skizze

`tournament_schedule_tick()` schaltet idempotent `published/call→running` (`now>=starts_at`),
`running→awaiting_results/completed` (`now>=ends_at`; completed nur wenn alle Runden-Matches
terminal). A liefert die Wahrheit (Zeitstempel + Status + Formel), E den Zeit-Treiber.
Gemeinsame `greatest(starts_at, now())`-Anker-Logik mit A2. Advisory-Lock pro `tournament_id`
im Tick. `paused_at`/`paused_accum_seconds` werden in A nur gelesen/gerendert; geschrieben erst
durch B2 (Pause/Resume-RPCs) und E.

## Risiken & Absicherung
1. **Stale-RPC-Body** → Diff gegen `…032`/`…247` vor jedem Replace.
2. **Skew-Resync** → kein Sekunden-Poll; Offset nur App-Start/Reconnect (Lifecycle `lib/app/app.dart`).
3. **Pause-Akkumulation** → A3a-Mehrfach-Pause-Tests; Schreiben erst B2.
4. **Idempotenz Upsert** → Existenz-Guard NULL-Pfad; pgTAP-Idempotenz.
5. **RLS-Filterspalten-Parität** → Assertion in `realtime_cdc_rls_test.sql`.
6. **Bestandsdaten** → A2-Trigger no-op ohne Schedule; A4-Fallback auf heutige Uhr.
7. **`started_at` in Zukunft** → `MatchTimer.elapsed` clamped Negativ auf 0 (A3a-Test).
8. **`db reset` verboten** → nur `migration up`; Proben in `BEGIN…ROLLBACK`.

## Offene Entscheidungen (vor jeweiligem Block)
- **OE-1 (A3a):** `MatchTimer.startedAt` als Anker behalten (Empf.) vs. `startsAt` umbenennen.
- **OE-2 (A1):** round_robin — nur aktive Runde materialisieren (Empf.) vs. alle.
- **OE-3 (A1):** Anon-Lesezugriff auf Schedule gleich mitnehmen (Empf.) für öffentliche Live-Sicht.
- **OE-4 (A2):** Autostart-Trigger-Backstop jetzt (Empf.) vs. erst durch E-Tick.
- **OE-5 (A1):** kein Backfill laufender Turniere in A (Empf.); A4-Fallback deckt Bestand.
- **OE-6 (A1):** Stage-Config-Zeitquelle (`tournament_stages.config` vs `match_format`) vor A1 per grep verifizieren.

## Verifikations-Checkliste je Block
| Block | analyze | Tests | DB |
|---|---|---|---|
| A3a | `dart analyze` (kubb_domain) | `match_timer_test.dart` | — |
| A1  | — | `round_schedule_test.sql` + `realtime_cdc_rls_test.sql` | `migration up`; BEGIN/ROLLBACK; CDC-Check; **RPC-Diff** |
| A2  | — | `match_autostart_test.sql` | `migration up`; Score-RPC-Diff |
| A3b | — | `public_rpc_test.sql` | `migration up`; `SELECT app_server_now()` |
| A3c | `flutter analyze` + `dart analyze` | port/provider/parser/widget | — |
| A4  | `flutter analyze` | `round_phase_countdown_test.dart` + Design-Abgleich | — |

Nach jedem Block: `git status` (kein Übergriff), ein Commit/Block, Push nur auf Ansage.
