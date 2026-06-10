# Phase B — Veranstalter-Dashboard (Cockpit, Multi-Turnier)

**Bezug:** ADR-0031, README.md (phasenübergreifende Korrekturen K1–K8 — v.a. **K1** Gate-Body in
`…031`, **K4** Rollenmenge inkl. organizer, **K5** Pause schreibt Schedule-Zeile). **Harte
Vorbedingung: Phase A gebaut/gemergt** (B liest `tournament_round_schedule`, `RoundStatus`,
`paused_at`, `RoundPhaseCountdown`, `serverClockOffsetProvider`, `watchRoundSchedule`).
**Migrationsband ab `20261255000000`.**

## Bau-Reihenfolge (Domain → Server → Client, 1 Commit/Block)
```
B0   Domain:  TournamentAdminCardRef DTO + Port-Methoden                     [Dart]
B1s  Server:  Gate referee (caller_can_manage CREATE OR REPLACE re-based …031)
              + RPC tournament_list_administrable                            [20261255000000]
B1c  Client:  Repo/Port list, Overview-Provider, canAdministerTournament-Provider
B2s  Server:  RPCs tournament_pause / resume / skip_forward / skip_back      [20261256000000]
B2c  Client:  Repo/Port/Actions-Facade pause/resume/skip
B4   Client:  Routen /tournament/dashboard + /:id/dashboard, Overview+Detail-Screen, l10n
B3   Client:  Eingriffs-Aktionen (override/forfeit/pairing/pair_round/start_ko_phase) konsolidiert
```

## BLOCK B0 — Domain: Dashboard-Read-DTO + Status-Wire-Parität
Reiner Dart. `packages/kubb_domain/lib/src/ports/tournament_remote.dart`: neues `@immutable`
`TournamentAdminCardRef` (`tournamentId, displayName, format, status, currentRound int?,
scheduleStatus RoundStatus?, remainingSeconds int?, openMatchCount, disputedMatchCount, pausedAt`)
mit vollem `==`/`hashCode`; Port-Signaturen `listAdministrableTournaments()` +
`pauseTournament/resumeTournament/skipScheduleForward/skipScheduleBackward(TournamentId)`. Export
in `kubb_domain.dart`. **Test:** `tournament_admin_card_ref_test.dart` (Konstruktion/Gleichheit/Defaults).
**Verif:** `dart analyze && dart test` (kubb_domain).

## BLOCK B1s — Server: Gate-`referee` + RPC `tournament_list_administrable`
**Migration `20261255000000_tournament_administrable_gate_and_list.sql`:**
- **Teil A (RE-BASE auf `…031` Z.60–88, K1):** `CREATE OR REPLACE tournament_caller_can_manage(uuid)`,
  einzige Änderung `ARRAY['owner','admin','organizer'] → ARRAY['owner','admin','organizer','referee']`
  (Array-Overlap `cm.roles && ARRAY[...]`). SECURITY DEFINER/STABLE/`search_path` unverändert, REVOKE/GRANT mit.
- **Teil B:** `tournament_list_administrable(p_limit int DEFAULT 50) RETURNS SETOF jsonb`, SECURITY
  DEFINER, Auth-Guard wie `tournament_list_for_caller`, `WHERE t.status IN ('published','live') AND
  public.tournament_caller_can_manage(t.id)`. **LEFT JOIN** `tournament_round_schedule` (Bestand ohne
  Schedule nicht verlieren). Projektion: `current_round`, `schedule_status`, `remaining_seconds`
  (server-Restzeitformel mit `app_server_now()`), `open_match_count` (scheduled|awaiting_results),
  `disputed_match_count`, `paused_at`.
**Tests (pgTAP) `tournament_administrable_test.sql`:** Gate-referee-Regression, Status-Filter
(draft/finalized raus), Counts, LEFT-JOIN-Fallback, EXECUTE-Grant. **Verif:** `migration up`;
BEGIN/ROLLBACK; **Gate-Body-Diff vs `…031`**.

## BLOCK B1c — Client: administrable-Provider + Gate-Provider
`tournament_repository.dart`: `listAdministrableTournaments()` → `rpc('tournament_list_administrable')`.
`tournament_models.dart`: `tournamentAdminCardRefFromRow` (NULL-Schedule-Pfad). `tournament_providers.dart`:
`canAdministerTournamentProvider` (Creator OR Club {owner,admin,organizer,referee} — **K4**;
spiegelt `canManageTournamentClubProvider` + Creator-OR), `administrableTournamentsProvider`
(FutureProvider). **Realtime-Refresh:** Overview hat keinen Single-Column-Scope → Invalidierung über
Inbox-CDC (CLAUDE.md Regel #4), KEIN Polling (OE-B3). **Tests:** Port-Contract, Parser, Gate-Provider
(Creator/referee true, member false). **Verif:** `flutter analyze` + `dart analyze`; Tests.

## BLOCK B2s — Server: pause/resume/skip_forward/skip_back
**Migration `20261256000000_tournament_schedule_control_rpcs.sql`:** vier RPCs, SECURITY DEFINER,
Gate `tournament_caller_can_manage`, GRANT authenticated. Schreiben **nur** `tournament_round_schedule`
der aktiven Runde (Status `call/running/awaiting_results`, `<> completed`):

| RPC | Semantik |
|---|---|
| `tournament_pause(uuid)` | `paused_at = now()` wenn NULL (idempotent) — **K5: das IST die Turnier-weite Pause** |
| `tournament_resume(uuid)` | `paused_accum_seconds += EXTRACT(EPOCH FROM now()-paused_at)::int; paused_at = NULL` (idempotent) |
| `tournament_skip_forward(uuid)` | `starts_at=now(), ends_at=now()+match_seconds, status='running'` (Aufruf-Frist überspringen) |
| `tournament_skip_back(uuid)` | `starts_at=now()+break_seconds, ends_at=…, status='call'` (Fenster neu aufrufen) |

Guards: nur nicht-terminale Zeilen; **schreibt NIE `tournament_matches`** (laufende/finalisierte
Matches immun); `pg_advisory_xact_lock(hashtext(tournament_id))` gegen E-Tick-Race; `skip_*` clear't
`paused_at=NULL, paused_accum_seconds=0`. Realtime gratis (Schedule ist CDC). **Tests (pgTAP):** Gate
(referee erlaubt, Fremder 42501), pause/resume-Akkumulation, skip-Übergänge, terminal-Guard,
finalisierte Matches unverändert. **Verif:** `migration up`; BEGIN/ROLLBACK.

## BLOCK B2c — Client: Actions-Facade
`tournament_repository.dart` vier `rpc(...)`-Impls + (reuse A's `watchRoundSchedule`).
`TournamentActions` um `pause/resume/skipForward/skipBack(TournamentId)` (invalidiert
`administrableTournamentsProvider` + Detail-Schedule-Provider). **Tests:** Port-Contract, Facade-Test.

## BLOCK B4 — Routen + Screens
Routes `tournament_routes.dart`: `dashboard = '/tournament/dashboard'` (**vor** `/tournament/:id`
registrieren!), `dashboardDetail(id)`. `router.dart` Tournaments-Branch. **Gate:** In-Screen
`KubbEmptyState` (Empf. OE-B5; Server ist Sicherheitsgrenze). Screens (Design-System verbindlich,
Prototyp `docs/design/ui_kits/app/TournamentScreen.jsx`): NEU
`organizer_dashboard_screen.dart` (Overview-Karten je mit Phase/Runde/scheduleStatus/Restzeit/
open+disputed-Badges + Start/Pause/Resume-Schnellaktion — **NICHT read-only** wie das in `a46f962`
entfernte), `organizer_dashboard_detail_screen.dart` (Runden-/Match-Liste + Steuerleiste
Start/Pause/Resume/Skip; Hold via A4-Widget). Widgets `organizer_tournament_card.dart`,
`schedule_control_bar.dart`. l10n + `flutter gen-l10n`. **Tests:** Overview/Detail-Widget-Tests,
Router-Test (`/tournament/dashboard` matcht nicht `:id`), Design-Abgleich.

## BLOCK B3 — Eingriffs-Aktionen konsolidiert (keine neue Server-Arbeit)
Detail-Screen verlinkt kontextuell: disputed→Override-Route; offen/No-Show→Forfeit-Dialog
(`declareForfeit`); KO-Übergang→`startKoPhase`; Swiss→`pairRound`. Eskalations-Badges aus Counts.
**Tests:** Detail-Screen-Verlinkungen.

## Risiken (Auszug)
Stale-Gate-Body (Diff vs `…031`); Pause/Skip nur Schedule, nie Match (finalisierte immun);
skip-auf-completed verboten; Advisory-Lock gegen E; Pause+Skip-Wechselwirkung (skip clear't pause);
Realtime-Push gratis (Schedule CDC); Gate Server=Wahrheit (K4); Bestand ohne Schedule (LEFT-JOIN +
Fallback); Route-Kollision (static vor `:id`); Overview-Last (eine RPC, kein N+1).

## Offene Entscheidungen (mit Empfehlung)
- **OE-B0:** A zuerst (harte Vorbedingung). · **OE-B1/K4:** Rollenmenge = Creator+{owner,admin,organizer,referee}.
- **OE-B2/K5:** Pause schreibt aktive Schedule-Zeile (eine Quelle für die Uhr-Formel). · **OE-B3:**
  Overview-Realtime via Inbox-CDC-Invalidierung statt Polling. · **OE-B4:** skip_back = Fenster neu
  aufrufen (kein echtes Rückspringen). · **OE-B5:** In-Screen-Gate statt Router-Redirect.

## Verifikation je Block
B0 `dart analyze`+Test · B1s `migration up`/pgTAP/**Gate-Diff** · B1c analyze+Tests · B2s `migration up`/pgTAP
(finalisierte Matches unverändert) · B2c analyze+Tests · B4 analyze/Widget/Router/Design · B3 analyze/Widget.
Nach jedem Block `git status`, ein Commit/Block, `flutter gen-l10n` nach ARB.

### Critical Files
`20261201000031_tournament_club_link.sql` (Gate-Body, RE-BASE-Quelle) ·
`20260525000005_tournament_list_creator.sql` (RPC-Vorlage) · `tournament_providers.dart`
(`canManageTournamentClubProvider`, `TournamentActions`) · `tournament_repository.dart` · `router.dart`
(static `dashboard` vor `:id`).
