# Phase D — Vor-Ort-Check-in + Eskalations-Tools

**Bezug:** ADR-0031, README.md (K4 Rollenmenge, K6 Forfait-Gate). ProjectPlan BUG3 (Vor-Ort-Checkin).
**Migrationsband ab `20261265000000`.** **D setzt B NICHT voraus** — koppelt an `tournament_detail_screen.dart`
(existiert) und exponiert Widgets so, dass eine spätere B-Dashboard-Shell sie 1:1 einhängt.

## Faktenlage
`tournament_participants` (`20260525000001`): eine Zeile pro Spieleinheit (Single `user_id` / Team
`team_id`), CDC aktiv (`20261236000000`, Filter `tournament_id`). Check-in ≠ confirm (confirm = Pool-
Zugehörigkeit; Check-in = physische Anwesenheit). Forfait `tournament_match_forfeit` gated **creator-only**
(K6). Gate-Helper `tournament_caller_can_manage` (`…031`; referee kommt via B). Realtime-Provider hat
matches+bracket, **keinen** participant-CDC-Provider.

## Bau-Reihenfolge (Server → Client)
```
D1  Server: Spalte checked_in_at + RPCs checkin/undo_checkin        [20261265000000]
D2  Server: tournament_get projiziert checked_in_at (Stale-Body-Diff!) [20261266000000]
D3  Client: Domain+Parser+Port+Repo+participant-CDC-Provider (end-to-end)
D4  Client: Check-in-UI (Anwesenheits-Toggle in Teilnehmerliste)
D5  Client: Eskalations-Panel (überfällig/strittig/nicht-eingecheckt) + No-Show→Forfait-Shortcut
```

## D1 — `checked_in_at` + Check-in-RPCs
**Migration `20261265000000_tournament_participant_checkin.sql`** (additiv): `ALTER TABLE
tournament_participants ADD COLUMN IF NOT EXISTS checked_in_at timestamptz NULL`. RPCs
`tournament_checkin_participant(p_participant_id uuid)` + `tournament_undo_checkin(...)`: SECURITY
DEFINER, Gate `tournament_caller_can_manage(v_tournament_id)`, Status-Gate Turnier `IN
(registration_open, registration_closed, live)` (OE-D1), `registration_status='confirmed'`, idempotent
(NULL/NOT-NULL no-op), Audit-Event, GRANT authenticated. **Kein `CREATE OR REPLACE` → kein Stale-Risiko.**
**Tests (pgTAP) `participant_checkin_test.sql`:** has_column, Publication-Mitgliedschaft, Grants,
happy/idempotent/undo, Gate-Negativ (42501), Status-Gate (draft→22023, live ok), waitlist→22023.

## D2 — `tournament_get` projiziert `checked_in_at`
**Migration `20261266000000`:** `CREATE OR REPLACE tournament_get(uuid)` — **RE-BASE auf echten letzten
Body** (heute `…032 §2`; falls A/B `tournament_get` ersetzen → deren Body). Einzige Änderung: im
`v_participants`-jsonb_build_object `'checked_in_at', p.checked_in_at` ergänzen, alles andere byte-genau.
**Tests:** Projektion non-NULL nach Check-in; Smoke `club_id`/`display_name` erhalten. **Verif:**
**RPC-Body-Diff** protokollieren.

## D3 — Client end-to-end
`TournamentParticipant` um `checkedInAt`/`isCheckedIn`; Port `checkinParticipant/undoCheckin/
watchTournamentParticipants`. Parser `tournamentParticipantFromRow` += `checked_in_at`. Repo: RPC-Calls
+ `watchTournamentParticipants` (`_realtime.subscribe(table:'tournament_participants',
filterColumn:'tournament_id')`). `tournamentParticipantListRealtimeProvider` (StreamProvider.autoDispose,
**invalidiert `tournamentDetailProvider`** — kein neues Polling, CDC existiert). `TournamentActions`
checkin/undo (invalidiert Detail). **Tests:** Port-Contract, Parser, Realtime-Provider (invalidate, kein
Timer.periodic).

## D4 — Check-in-UI
`tournament_detail_screen.dart` `_participantRow`: Toggle nur wenn `canManage` && Status
`IN {registration_open, registration_closed, live}`. Zustände „Einchecken"/„Anwesend (grün)";
`checked_in_at`-Label (serverzeit via A's Offset falls da, sonst lokal). Screen watcht
`tournamentParticipantListRealtimeProvider`. Optional Header-Zähler „X/Y eingecheckt". l10n + `gen-l10n`.
**Tests:** `tournament_detail_checkin_test.dart` (Sichtbarkeit/Status/Tap/Undo), Design-Abgleich.

## D5 — Eskalations-Panel + No-Show→Forfait
NEU `tournament_escalation_panel.dart` (aus `tournamentDetailProvider`, kein neuer Read): drei Listen —
**Strittig** (`disputed`→Override), **Überfällig** (`awaiting_results`; A-Schedule-Hold falls da, sonst
Match-Status-Fallback), **Nicht eingecheckt** (confirmed + `checkedInAt==null`). No-Show→Forfait-Shortcut:
nur wenn Teilnehmer in forfeitbarem Match (`scheduled|awaiting_results|disputed`) && Turnier `live` →
öffnet bestehendes `tournament_forfeit_sheet.dart` vorbelegt (`absentSide` aus Match-Seite), Reason
„No-Show — nicht eingecheckt". Panel als eigenständiges Widget (B-Dashboard übernimmt es später).
**Tests:** `tournament_escalation_panel_test.dart`.

## Risiken
Stale-Body `tournament_get` (Diff!); CDC `checked_in_at` (Publication-Erbe, Provider-Invalidierung);
Status-Gate; No-Show↔Forfait↔Schedule-Hold (Forfait treibt denselben Result-Trigger; nur EINE Seite
anbieten); **Gate-Asymmetrie K6** (Forfait creator-only vs Check-in manage-gated) → OE-D2; Bestand
additiv NULL (kein Backfill).

## Offene Entscheidungen
- **OE-D1:** Check-in-Fenster `registration_open|registration_closed|live` (Empf.; `checkin_until` nur
  Anzeige, nicht hartes Gate). · **OE-D2/K6:** `tournament_match_forfeit` auf `caller_can_manage`
  re-gaten (separate Migration `20261267000000`, Stale-Body-Diff vs `20260601000001`) damit
  referee/organizer den Shortcut nutzen — sonst Shortcut auf Creator beschränken. · **OE-D3:** Team-
  Check-in über die EINE Participant-Zeile („Team ist da"); per-Member out of scope. · **OE-D4:** Punkte-
  Feinschliff kein eigener D-Scope (Override/Forfait nur schneller erreichbar). · **OE-D5:** D an
  Detail-Screen ankern (B existiert noch nicht), Widgets wiederverwendbar.

## Verifikation je Block
D1 `migration up`/pgTAP/Publication-Check · D2 `migration up`/**`tournament_get`-Body-Diff** · D3 `dart
analyze`+`flutter analyze`/Tests · D4 `flutter analyze`/Widget/Design · D5 `flutter analyze`/Widget
(+ bei OE-D2 `migration up`/Forfait-Diff). Nach jedem Block `git status`, ein Commit/Block.

### Critical Files
`20260525000001_tournament_schema.sql` (Teilnehmer-Tabelle) · `20261201000032…` (`tournament_get`-Body,
D2-RE-BASE) · `20260601000001_tournament_match_forfeit.sql` (OE-D2-Re-Gate) · `tournament_repository.dart`
(Check-in-RPCs + participant-CDC) · `tournament_detail_screen.dart` (`_participantRow` + Panel-Anhang).
