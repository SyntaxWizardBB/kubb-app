# Milestone-Plan: Veranstalter-Dashboard & zeitgesteuerter Turnier-Ablauf

Index + **phasenübergreifende Abstimmung** der Detailpläne. Architektur: ADR-0031
(`docs/adr/0031-timed-tournament-runner-and-organizer-dashboard.md`). Spec:
`humanPlan/Milestone-Dashboard-Plan.md`. Branch `feat/tournament-scheduler-dashboard`.

## Phasen & Dokumente
- **A** — Schedule-Engine + Sync-Uhr → [phase-a-plan.md](phase-a-plan.md) *(Fundament)*
- **B** — Veranstalter-Dashboard (Multi-Turnier, Start/Pause/Skip) → [phase-b-plan.md](phase-b-plan.md)
- **C** — Notifications bei Schedule-Events → [phase-c-plan.md](phase-c-plan.md)
- **D** — Vor-Ort-Check-in + Eskalations-Tools → [phase-d-plan.md](phase-d-plan.md)
- **E** — pg_cron-Autonomie-Tick → [phase-e-plan.md](phase-e-plan.md)

## Abhängigkeiten / Bau-Reihenfolge
```
A  (Fundament: tournament_round_schedule, paused_at, app_server_now, MatchTimer, RoundPhaseCountdown)
├─ B  (liest Schedule, schreibt Pause/Skip — HART abhängig von A)
├─ C  (Publish-Notify durable ohne A lauffähig; starts_at-Suffix + getaktete Notifies brauchen A/E)
├─ D  (an tournament_detail_screen; NICHT von B abhängig; Eskalations-„überfällig" nutzt A wenn da)
└─ E  (cron-Tick — HART abhängig von A; treibt Cs getaktete Notifies)
```
**Empfehlung:** A zuerst vollständig bauen/mergen. Danach B/C/D/E (B & E hart auf A; C/D degradieren sauber ohne A). E nach A; Cs getaktete Notifies (E2/E4/E7/E8) werden vom E-Tick gefeuert.

## Migrations-Nummernbänder (kollisionsfrei, on-disk-Maximum = 20261249000000)
- A: `20261251000000`–`20261254000000` · B: `20261255000000`+ · C: `20261260000000`+ · D: `20261265000000`+ · E: `20261270000000`+
- T1-Fix belegt `20261250000000` (Branch `fix/t1-organizer-score-override`, noch nicht in main).

## Phasenübergreifende Korrekturen (von den Architekten gefunden — VERBINDLICH)

- **K1 — Gate-Body liegt in `…031`, nicht `…032`.** `tournament_caller_can_manage(uuid)` ist zuletzt
  in `20261201000031_tournament_club_link.sql` (Z. 60–88) definiert; `…032` *ruft* es nur. Die
  `referee`-Ergänzung (Phase B) re-bast auf **`…031`** (`ARRAY['owner','admin','organizer','referee']`).
- **K2 — Notify-Helper-Body in `…242`.** `_tournament_notify_participants` + der kind-CHECK sind
  zuletzt in `20261242000000` definiert (16 kinds). Jedes Re-Base in Phase C darauf.
- **K3 — Materialisierungs-RPC-Bodies: pro Funktion den ECHTEN letzten On-Disk-Body re-basen
  (NICHT pauschal `…032`!).** Verifizierte letzte Definitionen (höchster Timestamp, committet):
  `tournament_start` → **`20261201000040`** (Open-Registration-Modell: Start aus
  `registration_open|registration_closed`); `tournament_start_ko_phase` → **`20261210000000`**
  (CF6 Shootout-Gate/Resolve + `seeding_required`-Gate); `tournament_start_pool_phase` →
  `20261201000032`; `tournament_pair_round` → `20261201000032`; `tournament_generate_stage_matches`
  → `20261247000000`. **Vor jedem `CREATE OR REPLACE` per `grep -rl 'FUNCTION public.<fn>(' …` den
  höchsten Timestamp ermitteln** — `…032` ist für `tournament_start`/`tournament_start_ko_phase`
  VERALTET (es gibt spätere Redefinitionen). Body-Diff: nur die `PERFORM _tournament_upsert_round_
  schedule(...)`-Zeile darf neu sein. Reihenfolge: wer nach A kommt (z.B. C1), re-bast auf die
  A-Version (mit Schedule-Zeile).
- **K4 — Rollenmenge (organizer-Divergenz).** ADR/Spec nennen `{owner,admin,referee}`; das Server-Gate
  hat zusätzlich `organizer`. **Entscheid: Zugang = Creator + {owner,admin,organizer,referee}** (Server-
  Gate ist Wahrheit; Client spiegelt exakt). Gilt für B (Dashboard), D (Check-in), und implizit alle
  Schedule-Control-RPCs.
- **K5 — Wo lebt die „Turnier-weite Pause"?** A legt `paused_at`/`paused_accum_seconds` nur auf
  `tournament_round_schedule`; `tournaments.paused_at` existiert NICHT. Der E-Tick referenziert aber
  `t.paused_at`. **Entscheid (Single-Source für die Uhr-Formel): Turnier-weite Pause schreibt
  `paused_at` auf die AKTIVE(N) `tournament_round_schedule`-Zeile(n)** (B2-RPCs). Damit liest die
  Restzeit-Formel EINE Quelle (Schedule-Zeile), und der E-Tick prüft **nur `s.paused_at`** (die
  `t.paused_at`-Guard-Zeile im E-Plan entfällt / wird zu schedule-row). Einzel-Match-Pause = späterer
  Sonderfall. *(A-Plan + E-Plan an diesem Punkt entsprechend bauen.)*
- **K6 — Forfait-Gate ist creator-only.** `tournament_match_forfeit` (`20260601000001`) gated auf
  `created_by`. Für den No-Show-Shortcut (D) und Dashboard-Konsistenz auf `tournament_caller_can_manage`
  re-gaten (separate Migration, Stale-Body-Diff) — siehe D OE-D2.
- **K7 — pgTAP `now()` ist in der TX eingefroren.** Zeitabhängige Funktionen (E-Tick) bekommen einen
  `p_now timestamptz DEFAULT now()`-Parameter, damit Tests Zeit injizieren können; cron ruft ohne Arg.
- **K8 — E erzeugt KEINE Pairings.** Folgerunden materialisiert der bestehende Result-Trigger
  (`tournament_run_stage_graph` / `advance_ko_winner`); E flippt nur Schedule-Status + feuert
  Zeit-Notifies. (ADR-0031 §Runner.)

## Globale Guardrails (alle Phasen)
Additive Migrationen, NIE `db reset`; `CREATE OR REPLACE` nur auf aktuellem On-Disk-Body (Diff);
kein neues Client-Polling (Server-cron ist erlaubt); CDC-Tabellen → `ALTER PUBLICATION` + RLS auf der
Filterspalte; Design-System `docs/design/` verbindlich; Solo-Training TABU; ein Commit/Block;
Push nur auf Ansage; PII-frei in Notify-Payloads.
