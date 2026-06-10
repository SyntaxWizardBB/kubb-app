# Phase E — pg_cron-Autonomie-Tick

**Bezug:** ADR-0031 §3b/§Runner, README.md (K5 Pause-Quelle = Schedule-Zeile, K7 `p_now`-Param, K8 E
erzeugt keine Pairings). **HART abhängig von Phase A** (`tournament_round_schedule`, Status-Enum,
`paused_at`). **Migrationsband ab `20261270000000`.**

## Ausgangslage (verifiziert)
pg_cron `default=1.6`, **in `shared_preload_libraries`**, `cron.database_name=postgres` = App-DB →
in-DB-Job, kein pg_net/HTTP. Terminal-Status `('finalized','overridden','voided')`. Stage-Runner
`tournament_run_stage_graph` (DEFINER, `search_path=''`) + KO-Advance `advance_ko_winner` materialisieren
Folgerunden. **pgTAP-`now()` ist in der TX eingefroren** → Tick braucht `p_now`-Param (K7). Postgres 15.

## Bau-Reihenfolge (4 Blöcke)
```
E0  20261270000000_enable_pg_cron.sql            create extension pg_cron
E1  20261271000000_tournament_round_anchor.sql   _tournament_round_anchor() (mit A2 geteilt)
E2  20261272000000_tournament_schedule_tick.sql  tournament_schedule_tick(p_now)
E3  20261273000000_schedule_tick_cron_job.sql    cron.schedule (1-Min, idempotent)
```

## E0 — Extension
`CREATE EXTENSION IF NOT EXISTS pg_cron;` (additiv/idempotent; eigenes `cron`-Schema). **Tests:**
`has_extension('pg_cron')`, `has_schema('cron')`, `has_table('cron','job')`. **Verif:** `migration up`;
`installed_version=1.6`.

## E1 — Anker-Helper (geteilt mit A2)
```sql
CREATE OR REPLACE FUNCTION public._tournament_round_anchor(p_starts_at timestamptz, p_now timestamptz)
RETURNS timestamptz LANGUAGE sql IMMUTABLE SET search_path = ''
AS $$ SELECT greatest(p_starts_at, p_now); $$;
REVOKE ALL ON FUNCTION public._tournament_round_anchor(timestamptz, timestamptz) FROM public;
```
A2-Trigger auf diesen Helper umstellen (Stale-Body-Diff, falls A2 schon on-disk). **Tests:**
`round_anchor_test.sql` (Vergangenheit→p_now, Zukunft→p_starts_at).

## E2 — `tournament_schedule_tick(p_now timestamptz DEFAULT now()) RETURNS int`
SECURITY DEFINER, `search_path=''`. FOR-Loop über Schedule-Zeilen mit Status
`('published','call','running','awaiting_results')` **und `s.paused_at IS NULL`** (K5: Turnier-weite
Pause = `paused_at` auf der aktiven Schedule-Zeile; **kein** `t.paused_at` mehr) und
`(s.starts_at<=p_now OR s.ends_at<=p_now)`. Pro Turnier: Subtransaktion (`BEGIN…EXCEPTION WHEN OTHERS →
RAISE WARNING`, R3 Fehlerisolation) + `pg_try_advisory_xact_lock(hashtextextended(tournament_id::text,0))`
(non-blocking, R2). Übergänge (je idempotent via `WHERE status=<Quellstatus>`):
- `published/call` & `starts_at<=p_now` → `running` (+ E2b: `_tournament_notify_match_running`).
- `running/awaiting_results` & `ends_at<=p_now`: `bool_and(m.status IN
  ('finalized','overridden','voided'))` über Matches der Runde (`stage_node_id IS NOT DISTINCT FROM`) →
  alle terminal → `completed` (Folgerunde hat der Result-Trigger schon materialisiert, K8); sonst
  `running→awaiting_results` (Uhr hält, **kein** Auto-Forfait, OE-2; + E2b: `_tournament_notify_awaiting`).
`RETURNS int` = Anzahl Transitionen (Observability + Idempotenz-Test). `REVOKE ALL FROM public` (cron
läuft als `postgres`). **Tests (pgTAP) `schedule_tick_test.sql` (11 Fälle, `p_now`-injiziert):**
published→running, call→running, alle-terminal→completed, fehlt→awaiting_results (kein Forfait),
awaiting→completed, **Idempotenz (Re-Tick=0)**, verspäteter Tick, Pause-Guard (Schedule-Zeile),
Fehlertoleranz (kaputtes Turnier blockiert nicht), NULL- und Stage-Pfad.

## E3 — cron.schedule (idempotent, fester Name)
```sql
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname='tournament_schedule_tick')
    THEN PERFORM cron.unschedule('tournament_schedule_tick'); END IF;
  PERFORM cron.schedule('tournament_schedule_tick','* * * * *',
    'SELECT public.tournament_schedule_tick();');
END $$;
```
Fester `jobname` = Idempotenz-Schlüssel; Command ohne Arg → `DEFAULT now()` in Prod. **Tests:** genau 1
Job, Schedule `* * * * *`, Doppel-Apply→count=1. **Verif:** `migration up`; **Dev-Smoke:** Schedule-Zeile
mit `starts_at` knapp in Vergangenheit seeden, ≤60s warten → Status springt `running` **ohne** Client
(beweist Geräteunabhängigkeit), dann zurückrollen.

## Risiken
**R0 Phase A nicht gebaut** (E referenziert A-Objekte → E erst nach A). R1 Idempotenz (Status-Guard +
RETURNS int). R2 Race Result-Trigger (try-advisory-lock). R3 Fehlerisolation (Subtx + WARNING). R4 Pause
(Schedule-Zeile-Guard, K5). R5 Zeit-Test (`p_now`-Param). R6 Dev=Prod (gleiche DB postgres). R7
Job-Duplikat (fester Name + unschedule). R8 Notify-Kind (Zeit-Notify erst E2b mit C, kind-CHECK additiv).
R9 search_path-Leck (`''` + schema-qualifiziert).

## Offene Entscheidungen
- **OE-1/K8:** E nur Status+Notify, **keine** Pairings (Empf.; Result-Trigger materialisiert). Vor Bau in
  A1 verifizieren, dass jede Phase result-getriebene Folgerunden hat; sonst ist `completed` das
  Dashboard-Endsignal und der Veranstalter paart manuell (B).
- **OE-2:** **Kein** Auto-Forfait (Default `awaiting_results`+Flag; Karenz-Forfait später additiv).
- **OE-3:** `pg_try_advisory_xact_lock` (non-blocking). · **OE-4:** `RETURNS int`.

## Verifikation je Block
E0 `migration up`/extension-Test · E1 `migration up`/anchor-Test (+ A2-Diff falls angefasst) · E2
`migration up`/11 pgTAP-Fälle/**kein Touch an Stage-Runner/KO-Advance** · E3 `migration up`/cron-Test/
**Dev-Smoke geräteunabhängig**. Nach jedem Block `git status`, ein Commit/Block.

### Critical Files
`20261228000000_tournament_stage_runner.sql` (DEFINER/`search_path=''`/terminal-`bool_and`-Muster) ·
`20261201000010_tournament_golive_inbox.sql` (`_tournament_notify_participants` + kind-CHECK für E2b) ·
`20260601000016_trigger_advance_ko_winner.sql` (2. Result-Treiber; E materialisiert nicht) ·
`supabase/tests/pair_round_swiss.test.sql` (pgTAP-Muster) · `phase-a-plan.md` (R0-Voraussetzung).
