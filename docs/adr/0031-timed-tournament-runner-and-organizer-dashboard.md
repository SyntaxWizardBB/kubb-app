# ADR-0031: Zeitgesteuerter Turnier-Ablauf (Schedule-Runner) + Veranstalter-Dashboard

- **Status**: Proposed
- **Date**: 2026-06-09
- **Bezug**: `humanPlan/Milestone-Dashboard-Plan.md` (Milestone-Spec + geklärte
  User-Entscheide), ADR-0029 (Unified Messaging & Battery-Lifecycle — CDC/Broadcast/
  Inbox, „kein neues Polling"), ADR-0021 (Realtime-Subscription-Architektur),
  ADR-0017 (KO-Phase-Semantik, Server-Authority-Trigger), ADR-0030 (Stage-Graph-
  Framework — liefert die Runden, die hier **zeitlich orchestriert** werden).
- **Code-Quelle**: Config `packages/kubb_domain/.../tournament_setup.dart`
  (`MatchFormatSpec.timeLimitSeconds`, `.breakBetweenMatchesSeconds`,
  `.tiebreakAfterSeconds`, `.finalNoTiebreak`), Vorrunde `round_time_seconds` /
  `break_between_matches_seconds`. Server: `tournament_matches`-CDC (`20261234000000`),
  Materialisierungs-RPCs (`tournament_start`, `tournament_pair_round`,
  `tournament_start_ko_phase`, `tournament_generate_stage_matches`), Stage-Runner-
  Trigger (`20261228000000`), KO-Advance-Trigger (`20260601000016`), Notify-Spine
  `_tournament_notify_participants` (`20261201000010`), Org-Gate
  `canManageTournamentClubProvider` / Server `tournament_caller_can_manage`.

> **Reines DESIGN-/Entscheid-Dokument.** Legt Modell, Runner-Semantik und Invarianten
> fest; keine fertige Implementierung/Test-Suite (die materialisiert der Phase-Plan).

## Kontext & Motivation

Veranstalter managen real **mehrere parallele Turniere** (z.B. Liga C + Liga A/B). Der
Ablauf — Runden, Pausen, Uhren — soll **automatisch nach einem aus der Config
abgeleiteten Zeitplan** laufen; der Veranstalter **überwacht** und greift nur bei
**Fehlern/Eskalationen** ein (Start/Pause/Skip).

Das frühere read-only Dashboard wurde in O1 (`a46f962`) bewusst entfernt — es hatte
**keine eigene Aktion**. Gebraucht wird das Gegenteil: ein **aktionsreiches** Cockpit.

Heutige Lücken: `started_at` wird erst beim **ersten Score** gesetzt (nicht bei
Spielbereitschaft); **keine Server-Zeit** (Client-Clock-Skew driftet); **kein Pause-
Konzept**; Runden-Progression ist nur **result-getrieben**, nicht **zeit-getrieben**.

## Entscheidung

Ein laufendes Turnier wird von einem **zeitgesteuerten Runner** getragen, dessen Wahrheit
**server-autoritative Zeitstempel pro Runde** sind. Das Dashboard ist die Überwachungs-/
Eingriffs-Lage darüber.

1. **Zeitplan = Zeitstempel pro Runde**, abgeleitet aus der bestehenden Config (Match-
   und Pausen-Dauer **pro Phase/Runde** — keine neuen Config-Felder nötig). Persistenz in
   eigener CDC-Tabelle `tournament_round_schedule` (`published_at`, `starts_at`,
   `ends_at`, `break_seconds`, `match_seconds`, `status`, `paused_at`,
   `paused_accum_seconds`), RLS-Filter `tournament_id`.
2. **Uhr = zeitstempel-verankert + skew-korrigiert.** RPC `app_server_now()` liefert
   Server-`now()`; der Client hält einen `offset = server_now − local_now` und rechnet
   `now = DateTime.now() + offset`. Der lokale 1-s-Ticker ist **reines Rendering** — ein
   Per-Sekunde-Push wäre ein ADR-0029-Anti-Pattern.
3. **Fortschritt = zwei Treiber.** (a) **Result-Trigger** (bestehender Stage-Runner /
   KO-Advance) materialisiert die nächste Runde, sobald alle Matches einer Runde terminal
   sind. (b) **pg_cron 1-Min-Tick** (`tournament_schedule_tick()`) treibt die **reinen
   Zeit-Übergänge** (`call`→`running`, fällige Zeit-Notifies) — idempotent, server-
   autoritativ. pg_cron 1.6 ist verfügbar.
4. **Realtime via bestehende CDC** (`tournament_matches` + neue Schedule-Tabelle) →
   automatischer Push, **kein neues Polling** (ADR-0029).
5. **Pause = Turnier-weit (Default).** `tournaments.paused_at` friert alle laufenden
   Uhren über die Restzeit-Formel; Einzel-Match-Pause als Sonderfall über die Match-Felder.
6. **Tiebreak/Hold ist emergent**, kein globaler Schalter: eine Runde wird erst
   `completed`, wenn **alle** Matches terminal sind → fehlt eines (Tiebreak), wartet der
   Ablauf automatisch, die Match-Uhr hält (Pause-Semantik) bis eingetragen.
7. **Dashboard = Überwachungs-Cockpit über mehrere Turniere** des Veranstalters;
   konsolidiert bestehende Eingriffs-RPCs (Override, Forfait, Pairing-Override,
   pair_round, start_ko_phase) + Start/Pause/Skip. **Zugang** `canAdministerTournament` =
   Creator **ODER** Club-Rolle {owner, admin, referee} — baut auf dem bestehenden
   `canManageTournamentClubProvider` / `tournament_caller_can_manage` auf (nur `referee`
   ergänzen). Minimal-Gate jetzt; Rollen-Konsolidierung zieht nach.
8. **Notifies: durable Inbox bei Publish** („Runde N, Pitch X, Start HH:MM") +
   cron-getriebene Zeit-Notifies; **echte Out-of-App-Pushes** bleiben am Push-Milestone.

## Modell

### Restzeit-Formel (Server = Client identisch)
```
effective_elapsed = (now − starts_at) − paused_accum_seconds
                    − (paused_at IS NOT NULL ? (now − paused_at) : 0)
remaining         = match_seconds − effective_elapsed     // < 0 ⇒ Zeit abgelaufen
```
`now` = serverkorrigierte Zeit (Skew-Offset). Pause friert, weil `paused_at` den
laufenden Abzug stoppt; Resume akkumuliert die Differenz in `paused_accum_seconds`.

### Zustandsautomat pro Runde
```
[Runde N berechnet] → published (Notify: Runde N, Pitch, Start HH:MM)
   → call (Aufruf-/Pausen-Fenster break_seconds; Countdown auf allen Geräten)
   → running (starts_at erreicht — durch cron/Zeitstempel; Notify "Match läuft")
   → ends_at erreicht:
        alle Resultate terminal? → completed → (Result-Trigger) Runde N+1 → published …
        sonst / Tiebreak        → awaiting_results (Uhr hält, Dashboard flaggt;
                                   Eintrag durch Spieler/Veranstalter) → completed → weiter
[letzte Runde completed] → tournament finalize
```

## Runner-Semantik (server-autoritativ)

- **Materialisierung** der nächsten Runde bleibt result-getrieben (ADR-0017/0030-Trigger),
  ergänzt um das Setzen der Schedule-Zeitstempel beim Erzeugen.
- Der **cron-Tick** ist eine **idempotente** Funktion: er darf doppelt/verspätet laufen,
  ohne Schaden (Übergänge sind durch Status-/Zeit-Guards geschützt). Er erzeugt **keine**
  Pairings (das bleibt Trigger-Sache), sondern schaltet nur Zeit-Zustände und feuert
  fällige Notifies.
- **Skew**: `app_server_now()` ist ein seltener Offset-Sync (App-Start/Reconnect), kein
  Sekunden-Poll.

## Abgrenzung

- **Nicht** die Stage-Graph-/Pairing-Engine selbst (ADR-0030) — der Runner **konsumiert**
  die Runden, er erzeugt keine Paarungen.
- **Nicht** echte Out-of-App-Pushes (Push-Provider/FCM) — deferred auf den Push-Milestone
  (LastMilestonePublishApp); bis dahin Inbox + lokale Notifications.
- **Nicht** die Rollen-Konsolidierung (Berechtigungskonzept-Milestone) — hier nur das
  Minimal-Gate + `referee`-Ergänzung.
- **Nicht** das app-weite `AdminDashBoard` (globaler Support / User-Rechte) — eigener
  Milestone.

## Offene Punkte

1. **Pause-Granularität**: Turnier-weit als Default bestätigt; Einzel-Match-Pause als
   Sonderfall — Felder auf `tournament_matches` jetzt mitführen oder später?
2. **Cron-Idempotenz/Locking**: Advisory-Lock pro Turnier im Tick, damit parallele Ticks/
   Trigger nicht kollidieren; genaues Guard-Design beim Bau.
3. **„Zeit um, aber Resultat fehlt"**: `awaiting_results` + Eskalations-Flag im Dashboard
   (Default, kein Auto-Forfait) vs. optionaler cron-Auto-Forfait nach Karenz — Owner-Entscheid.
4. **Skew-Resync-Intervall** + Verhalten bei Reconnect/Hintergrund (Kopplung an ADR-0029-
   Lifecycle).
5. **Pitch-Zuweisung bei parallelen Stufen/Turnieren** (`tournament_assign_pitches`) und die
   Mehr-Turnier-Overview-Last.

> Fundament für den „Veranstalter-Dashboard"-Milestone; baut auf ADR-0029 (Transport),
> ADR-0030 (Runden) und dem bestehenden Org-Gate auf. Phasen A–E im Phase-Plan.
