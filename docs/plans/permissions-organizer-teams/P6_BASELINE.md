# P6 Baseline-Snapshot (vor P6a-Rename-Migration)

Erstellt: **2026-06-13, ca. 02:29–02:34 Uhr** — VOR Anwendung von
`20261283000000_rename_organizer_teams.sql` (Apply: 02:43:08 Uhr, mtime der
Migrationsdatei). Zeitliche Einordnung belegt durch mtimes der Lauf-Artefakte:
Baseline-Runner `/tmp/p6a/run_baseline.sh` (führt `flutter test --no-pub` +
`flutter analyze --no-pub` aus) geschrieben 02:29:06; Beginn der
Migrations-Erstellung (`/tmp/p6a/mig_header.sql`) 02:34:29 — beide Läufe lagen
dazwischen und damit eindeutig vor der Migration.
Referenz für P6b/P6c: Nach Abschluss von P6 muss die Suite wieder exakt diesen
Stand erreichen (identisch grün, keine neuen analyze-Issues). Dieser Snapshot
ist ausdrücklich **kein Gate für P6a** (siehe „Gate-Abgrenzung" unten).

## flutter test --no-pub (2026-06-13, ca. 02:29–02:31 Uhr, vor Migration 02:43)

- Ergebnis: **1441 passed, 6 skipped, 0 failed** — Suite grün.
- Schlusszeile: `00:57 +1441 ~6: All other tests passed!`

## flutter analyze --no-pub (2026-06-13, ca. 02:31–02:34 Uhr, vor Migration 02:43)

- Ergebnis: **12 Issues** (alle vorbestehend, 2 warning / 10 info):

```text
   info • 'bool' parameters should be named parameters • lib/features/tournament/application/tournament_config_controller.dart:91:22 • avoid_positional_boolean_parameters
   info • 'bool' parameters should be named parameters • lib/features/tournament/application/tournament_config_controller.dart:375:26 • avoid_positional_boolean_parameters
   info • Don't cast a nullable value to a non-nullable type • lib/features/tournament/data/tournament_models.dart:214:42 • cast_nullable_to_non_nullable
   info • The referenced name isn't visible in scope • lib/features/tournament/data/tournament_repository.dart:753:50 • comment_references
warning • The value of the field '_highlightSlot' isn't used • lib/features/tournament/presentation/register_team_screen.dart:35:8 • unused_field
warning • Unused import: 'package:kubb_domain/src/ports/realtime_channel.dart' • packages/kubb_domain/test/test_support/fake_realtime_channel_test.dart:1:8 • unused_import
   info • The import of 'package:kubb_domain/src/tournament/pairing/buchholz.dart' is unnecessary because all of the used elements are also provided by the import of 'package:kubb_domain/src/tournament/pairing.dart' • packages/kubb_domain/test/tournament/pairing/swiss_system_test.dart:2:8 • unnecessary_import
   info • The import of 'package:kubb_domain/src/tournament/pairing/swiss_system.dart' is unnecessary because all of the used elements are also provided by the import of 'package:kubb_domain/src/tournament/pairing.dart' • packages/kubb_domain/test/tournament/pairing/swiss_system_test.dart:3:8 • unnecessary_import
   info • Closure should be a tearoff • test/features/legal/imprint_screen_test.dart:61:12 • unnecessary_lambdas
   info • Closure should be a tearoff • test/features/legal/privacy_policy_screen_test.dart:81:12 • unnecessary_lambdas
   info • Sort directive sections alphabetically • test/features/settings/legal_links_test.dart:11:1 • directives_ordering
   info • The value of the argument is redundant because it matches the default value • test/features/tournament/presentation/register_team_screen_test.dart:133:19 • avoid_redundant_argument_values

12 issues found.
```

## DB-Vorher-Proben (read-only psql, 2026-06-13, ca. 02:26–02:40 Uhr, Stand 20261282500000)

- `pg_policies`: `clubs` = **1**, `club_memberships` = **1**.
- Zeilen-Counts: `clubs` = **1**, `club_memberships` = **1**.
- `pg_publication_tables` für `clubs`/`club_memberships`/`tournaments` = **0**
  (kein `ALTER PUBLICATION` nötig, PLAN §0.2).
- Keine bestehende public-Funktion `organizer_*`, `is_active_organizer_team_member`
  oder `is_organizer_team_manager` → Rename-Zielnamen waren frei.
- 1vs1-Team-Funktionen vorher (je genau 1 Definition, dürfen nach P6a unverändert
  sein): `_team_assert_active_member`, `is_active_team_member`, `team_add_guest`,
  `team_add_guest_member`, `team_create`, `team_dissolve`, `team_get`,
  `team_invitation_respond`, `team_invite`, `team_invite_by_nickname`,
  `team_league_window_open`, `team_leave`, `team_list_for_caller`,
  `team_name_available`, `team_pool_with_tournament_conflicts`,
  `team_remove_guest`, `team_remove_member`, `team_set_league`,
  `team_set_member_role`, `team_update`.

## Gate-Abgrenzung P6a (verbindlich)

P6a gated **ausschließlich** auf DB-Verifikation (`supabase migration up` clean,
to_regclass-/pg_proc-/pg_policies-/pg_publication_tables-Proben) und pgTAP
(`rename_organizer_teams_test.sql` + mechanisch nachgezogene Bestands-pgTAPs).
**`flutter test` / `flutter analyze` sind nach der P6a-Migration KEIN
Pass/Fail-Kriterium:** Die Dart-Seite ist bis P6b erwartbar rot — erwartete
Fehlerklasse: **unbekannte RPC-Namen** (`club_*` → `organizer_team_*`) und
**Wire-Keys** (`club_id` → `organizer_team_id`). Die vollständige
Mapping-Tabelle (Funktionen, Spalten, JSON-Keys) steht im Header von
`supabase/migrations/20261283000000_rename_organizer_teams.sql` und ist die
verbindliche Vorlage für P6b.

## Stale-Body-Anker (grep-tail-1, verifiziert)

Basis jedes `CREATE OR REPLACE` in der P6a-Migration ist der **letzte
angewendete Body** (`pg_get_functiondef` des voll migrierten lokalen Stacks;
`supabase migration list --local` war vor P6a clean bei `20261282500000` →
DB-Body == letzter On-Disk-Body). Jeder neue Body wurde **maschinell
reverse-gemappt** (neue→alte Bezeichner) und musste byte-identisch zum
Original sein — Diff = ausschließlich Token-Ersetzungen (Skript
`/tmp/p6a/emit_migration.sql`, DO-Block bricht bei Abweichung ab; Lauf war
fehlerfrei für alle 38 Bodies). `club_founding_code` wurde NUR umbenannt
(Body referenziert keine umbenannten Bezeichner → kein Replace, P6A-10).

Letzte On-Disk-Definitionsdatei je Funktion
(`grep -rln "FUNCTION public.<fn>(" supabase/migrations/ | sort | tail -1`,
ohne die neue 20261283000000):

| Funktion | Anker (letzte On-Disk-Definition) |
|---|---|
| club_caller_can_publish | 20260901000016_club_membership_ops.sql |
| club_caller_is_organizer | 20261282500000_club_caller_is_organizer.sql |
| club_create | 20261244000000_name_uniqueness_checks.sql |
| club_founding_code (rename-only) | 20260901000013_club_rpcs.sql |
| club_get | 20260901000013_club_rpcs.sql |
| club_invitation_respond | 20261282000000_invite_with_role.sql |
| club_invite | 20261282000000_invite_with_role.sql |
| club_invite_by_nickname | 20261282000000_invite_with_role.sql |
| club_leave | 20260901000016_club_membership_ops.sql |
| club_list_for_caller | 20260901000013_club_rpcs.sql |
| club_list_join_requests | 20260901000016_club_membership_ops.sql |
| club_name_available | 20261244000000_name_uniqueness_checks.sql |
| club_remove_member | 20260901000016_club_membership_ops.sql |
| club_request_join | 20260901000016_club_membership_ops.sql |
| club_respond_join_request | 20261280000000_role_consolidation.sql |
| club_set_member_roles | 20261280000000_role_consolidation.sql |
| is_active_club_member | 20260901000012_club_schema.sql |
| is_club_manager | 20260901000016_club_membership_ops.sql |
| tournament_caller_can_setup | 20261281000000_gate_split.sql |
| tournament_caller_can_administer | 20261281000000_gate_split.sql |
| tournament_caller_is_organizer | 20261201000030_tournament_lifecycle_organizer_role.sql |
| tournament_create | 20261201000032_tournament_per_tournament_manage_gate.sql |
| tournament_update (inkl. Live-Recompute) | 20261281000000_gate_split.sql |
| tournament_get | 20261266000000_tournament_get_checked_in_at.sql |
| tournament_is_rated | 20261206000000_cf1_unrated_tournaments_excluded.sql |
| tournament_write_skv_awards (Trigger) | 20261217000000_tournament_finalize_awards_trigger.sql |
| tournament_skv_compute_awards | 20261216000000_tournament_skv_compute_awards.sql |
| apply_stage_graph_template | 20261281000000_gate_split.sql |
| save_stage_graph_template | 20261230000000_tournament_stage_graph_templates.sql |
| tournament_abort / close_registration / detect_shootouts / finalize / open_registration / pair_round / publish / start / start_pool_phase | 20261281000000_gate_split.sql (Kommentar-only-Token) |
| tournament_ranking_get | 20261206000000_cf1_unrated_tournaments_excluded.sql (Kommentar-only) |

Hinweis: Die im Block-Brief genannten Anker `tournament_update=20261273000000`
und `tournament_start=20261261000000` sind ÜBERHOLT — P2 (20261281000000,
Gate-Split) hat beide Funktionen zuletzt neu definiert (Live-Recompute- bzw.
Notify-Logik dort enthalten; im verwendeten Basis-Body verifiziert vorhanden).

## P6a-Ergebnisse (2026-06-13, nach Migration)

- `supabase migration up`: clean (Exit 0, „Applying migration
  20261283000000_rename_organizer_teams.sql … Local database is up to date").
  `supabase migration list --local`: 20261283000000 lokal + applied.
- Post-Proben (read-only psql): to_regclass organizer_teams/team_members
  NOT NULL, clubs/club_memberships NULL; club_invitations/club_join_requests/
  club_audit_events/teams/team_memberships unverändert vorhanden;
  tournaments.organizer_team_id vorhanden, club_id abwesend;
  pg_policies organizer_teams = **1**, team_members = **1**, alte Namen = **0**;
  pg_publication_tables (3 Tabellen) = **0**; Rows organizer_teams = **1**,
  team_members = **1** (identisch zu vorher); club_*-Funktionen = **0**,
  18 umbenannte Pendants vorhanden; 1vs1-`team_*` = 20 Namen, je genau 1
  Definition (keine neuen Überladungen); Alias `tournament_caller_can_manage`
  unverändert vorhanden (OE-4).
- Zusätzliche Spalten-Renames (nötig für P6A-09, dokumentiert im
  Migrations-Header): `team_members.club_id → organizer_team_id` und
  `tournament_stage_graph_templates.club_id → organizer_team_id`.
  Constraint-/Index-NAMEN bewusst unverändert (z.B.
  `club_memberships_roles_check` auf team_members,
  `clubs_display_name_unique_idx` auf organizer_teams).

### Befundliste: verbleibende `club_id`-Vorkommen in Funktions-Bodies (P6A-09)

`SELECT proname FROM pg_proc WHERE prosrc ~* '\mclub_id\M'` → genau diese 9
Funktionen; jedes Vorkommen ist eine Spaltenreferenz der NICHT umbenannten
Tabellen (einzeln geprüft):

| Funktion | Vorkommen (alle = Spalten der Legacy-Tabellen) |
|---|---|
| organizer_team_create | `club_audit_events(club_id, …)` |
| organizer_team_invitation_respond | `v_inv.club_id` (club_invitations-Rowtype), `club_audit_events(club_id, …)` |
| organizer_team_invite | `i.club_id`, `club_invitations(club_id, …)`, `club_audit_events(club_id, …)` |
| organizer_team_leave | `club_audit_events(club_id, …)` |
| organizer_team_list_join_requests | `r.club_id` (club_join_requests) |
| organizer_team_remove_member | `club_audit_events(club_id, …)` |
| organizer_team_request_join | `club_join_requests(club_id, …)`, `WHERE club_id … AND state='pending'` (club_join_requests), `club_audit_events(club_id, …)` |
| organizer_team_respond_join_request | `v_req.club_id` (club_join_requests-Rowtype), `club_audit_events(club_id, …)` |
| organizer_team_set_member_roles | `club_audit_events(club_id, …)` |

`prosrc ~* '\mclubs\M|\mclub_memberships\M'` → **0 Zeilen**.
`prosrc LIKE '%''club_id''%'` (JSON-Key-Emission) → **0 Zeilen** (P6A-11).

### pgTAP-Inventar + Ergebnisse (P6A-13/14)

Neu: `rename_organizer_teams_test.sql` → **32/32 ok**.

`grep -rln 'club' supabase/tests/` → 11 Dateien, alle erklärt und einzeln
grün (via `docker exec … psql < datei`):

| Datei | Status | Behandlung |
|---|---|---|
| rename_organizer_teams_test.sql | 32 ok | NEU (P6a-Smoke) |
| gate_split_test.sql | 17 ok | bezeichner-only aktualisiert |
| tournament_administrable_test.sql | 14 ok | bezeichner-only aktualisiert |
| tournament_schedule_control_test.sql | 26 ok | bezeichner-only aktualisiert |
| tournament_get_checkin_projection_test.sql | 7 ok | bezeichner-only aktualisiert (inkl. Wire-Key organizer_team_id) |
| name_uniqueness_test.sql | 14 ok | bezeichner-only aktualisiert (Index-Name clubs_display_name_unique_idx bleibt) |
| club_caller_is_organizer_test.sql | 3 ok | bezeichner-only aktualisiert (Dateiname bewusst belassen) |
| role_consolidation_test.sql | 20 ok | bezeichner-only aktualisiert (club_invitations/club_join_requests/club_audit_events-Refs bleiben club_id) |
| invite_with_role_test.sql | 15 ok | bezeichner-only aktualisiert (Inbox-Kind 'club_invitation' bleibt, P7) |
| tournament_update_live_edit_test.sql | 24 ok | UNVERÄNDERT — 'club' nur in Kommentaren |
| schedule_notify_per_pitch_test.sql | 29 ok | UNVERÄNDERT — 'club' nur in Inbox-Kind-Strings (Kinds bleiben, P7) |

**Hinweis für den Orchestrator (Commit-Sichtung, Reviewer-Befund P6A-14):**
Da git in diesem Lauf gesperrt war, ist „Diff = nur Bezeichner" für die 8
aktualisierten Bestands-pgTAPs nur per Einzelnachweis (alle einzeln grün +
Inhalts-Stichprobe `gate_split_test.sql`) belegt. Beim finalen Commit bitte den
`git diff` der 8 Testdateien einmal sichten — erwartet: **ausschließlich**
Ersetzungen `clubs → organizer_teams`, `club_memberships → team_members`,
`club_id → organizer_team_id` (Wire-Key/Spalte) und `club_* → organizer_team_*`
RPC-Namen; keine Logik-/Assert-Änderungen.

### Scope-Hygiene (P6A-15)

In diesem Block erstellt/geändert (mtimes 2026-06-13): Migration
`20261283000000_rename_organizer_teams.sql`, 9 pgTAP-Dateien unter
`supabase/tests/` (1 neu + 8 aktualisiert), diese Datei. Die von
`find -newer 20261282500000…` zusätzlich gelisteten Dateien unter `lib/`,
`test/`, `lib/l10n/` haben mtimes vom **2026-06-12 19:24–19:53** (vorherige
Blöcke P4/P5 auf diesem Branch, vor P6a-Beginn) und wurden in diesem Block
NICHT berührt. Tabu-Zonen (lib/features/training/, lib/features/match/,
docs/plans/realtime-messaging/, docs/adr/0029*) unberührt.
