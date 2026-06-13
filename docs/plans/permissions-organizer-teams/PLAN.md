# Umsetzungsplan: Berechtigungskonzept — Veranstalterteams & Rollen

**Bezug:** ADR-0032. Branch `feat/permissions-organizer-teams` (von main). CLAUDE.md +
docs/AGENT_PIPELINE_PLAYBOOK.md gelten. **Auto-Commit/Push pro grünem Block.**

> **Stale-Body-Pflicht (verbindlich):** Für JEDES `CREATE OR REPLACE` zuerst
> `grep -rln "FUNCTION public.<fn>(" supabase/migrations/ | sort | tail -1` → den ECHTEN
> letzten On-Disk-Body als Basis; Body-Diff darf NUR die beabsichtigte Zeile ändern.

## 0. Verifizierte Befunde (korrigieren ADR-Annahmen)
1. **`tournament_update` ist NICHT creator-only** — letzter Body `20261273000000` nutzt schon
   `tournament_caller_can_manage`. Der Gate-Split ist daher eine **Verengung** auf owner/admin
   (referee raus), kein Öffnen. Netto = gewolltes Verhalten.
2. **clubs / club_memberships / tournaments sind NICHT in `supabase_realtime`** → Rename braucht
   **kein** `ALTER PUBLICATION`; `ALTER TABLE … RENAME` erhält Policies/Indizes/Constraints/Trigger.
3. **Gate-Body letzter Stand = `20261255000000`** (`['owner','admin','organizer','referee']`).
4. **Invite-mit-Rolle braucht Schema:** `club_invitations` hat keine `role`-Spalte;
   `club_invitation_respond` hardcodet `ARRAY['member']` beim Accept.

## 1. Phasen-Reihenfolge (Rename ANS ENDE)
**P1 Rollen → P2 Gate-Split → P3 Invite-mit-Rolle → P4 Veranstalter-Kachel → P5 Ongoing-Match → P6 RENAME → P7 Feinschliff.**
Begründung: Verhaltensänderungen zuerst auf heutigen `club_*`-Namen; der **verhalten-neutrale
Rename** (höchster Blast-Radius) kommt als isolierte mechanische Phase, deren Gate die **volle,
bereits grüne Suite** ist (jeder rote Test danach = mechanischer Fehler, nie Logik). Rollen vor
Gate (Gate-Array referenziert das konsolidierte Set), Invite nach Rollen.

## 2. Phasen im Detail

### P1 — Rollen-Konsolidierung {owner, admin, referee}
**P1-S** Migration `20261280000000_role_consolidation.sql`: (a) **Audit-Insert vor Remap** (alte
roles festhalten, kind `roles_consolidated`); (b) **Bestand-Remap UPDATE vor CHECK** — jede
gestrippte Rolle entfernen, organizer→admin, leere→`['admin']`, nur Zeilen mit
`NOT (roles <@ {owner,admin,referee})`; (c) CHECK verengen (Constraint-Name vorab via
`pg_constraint` ermitteln, NICHT raten); (d) `roles`-DEFAULT entfernen. **Stale-Body** auf je
letztem Body: `club_set_member_roles` (Array→{owner,admin,referee}), `club_invitation_respond` +
`club_respond_join_request` (`['member']`→`['admin']`). `club_caller_can_publish` /
`tournament_caller_can_manage` in P1 NICHT anfassen (organizer-Bestand ist schon zu admin gemappt).
**P1-C** `club_models.dart` `clubRoles=['owner','admin','referee']`; `club_detail_screen` `_roleLabel`
auf 3 Fälle (Owner/Admin/Schiedsrichter).
**Tests** pgTAP `role_consolidation_test.sql` (set_member_roles lehnt member/organizer ab, akzeptiert
referee; Remap organizer/scorekeeper→admin; CHECK weist ['member'] ab; Accept→['admin']).

### P2 — Gate-Split (Setup vs Admin)
**P2-S** Migration `20261281000000_gate_split.sql`: zwei Funktionen —
`tournament_caller_can_setup` = Ersteller OR {owner,admin}; `tournament_caller_can_administer` =
Ersteller OR {owner,admin,referee} (Basis = letzter Gate-Body `20261255000000`, organizer raus).
**Call-Sites umhängen** (jeder auf seinem letzten Body): **Setup** = update/publish/start/
open_close_registration/seeding/stage-graph-start/finalize/abort/invite-RPCs/round-publish;
**Admin** = organizer_override/_pairing, forfait, pause/resume, skip_forward/back, checkin/undo,
list_administrable. Default-Regel: **strukturverändernd/Pre-Live = Setup; Live-Eingriff
(Score/Zeit/Checkin) = Admin.** `tournament_caller_can_manage` **als Alias auf `_administer`
re-definieren** (fail-safe für übersehene Call-Sites), Kommentar „deprecated".
**P2-C** `tournament_providers.dart`: `canManageTournamentClubProvider`→Setup-Spiegel {owner,admin};
`canAdministerTournamentProvider`→{owner,admin,referee}; `manageableClubsProvider` (Wizard-Picker)→
{owner,admin}, **referee ausgeschlossen**; `canPublishTournamentProvider`→{owner,admin}.
**Tests** pgTAP `gate_split_test.sql` (referee↛Setup/update, referee↦Admin/override; Wahrheitstabelle);
Dart Setup-Provider referee→false, Picker ohne referee-only-Team.
> **OE-2 `tournament_start` = Setup** (Default). Vor P2 bestätigen.

### P3 — Invite-mit-Rolle
**P3-S** `20261282000000_invite_with_role.sql`: `ALTER TABLE club_invitations ADD COLUMN role text
NOT NULL DEFAULT 'admin' CHECK (role IN ('owner','admin','referee'))`. `club_invite(...,p_role
DEFAULT 'admin')` schreibt role + Inbox-Payload; `club_invitation_respond` Accept liest `v_inv.role`
statt `'member'` (Stale-Body 000013). **P3-C** `club_repository.invite/inviteByNickname` +Param;
`club_add_member_screen` Rollen-Picker (SegmentedButton über teamRoles, Default admin).
**Tests** pgTAP (invite role=referee → Membership ['referee']; invalid→22023); Dart Widget (Picker).

### P4 — Veranstalter-Kachel
**P4-S** Funktion `club_caller_is_organizer()` = `user_profiles.can_found_clubs` OR EXISTS
membership {owner,admin,referee}. **P4-C** `home_screen.dart` Kachel „Meine Vereine"→„Veranstalter"
(Subtitle „Dashboard & Veranstalterteams"), Sichtbarkeit via `organizerTileVisibleProvider`,
Tap→`organizer_dashboard_screen` (ADR-0031) **mit Team-Liste-Sektion** (kein neuer Screen).
**Tests** pgTAP (can_found_clubs/referee-only→true, Fremd→false); Dart (Kachel sichtbar/ausgeblendet).

### P5 — Ongoing-Match-Kachel (cross-Turnier)
**P5-C** neuer `myActiveTournamentMatchProvider` (foldet per-Turnier-`myActiveMatchProvider` über
`myTournamentRegistrationsProvider`, dringendstes Match, **nur Turnier-Matches**); `home_screen`
neue Kachel, **ausgeblendet wenn null**, Tap→Match. **1vs1-„Match Modus"-Kachel im Training-Hub +
`lib/features/match/` UNANGETASTET.** Kein neues Polling (CDC existiert). **Tests** Dart Provider
(dringendstes cross-Turnier, null wenn nichts); Widget; `git diff --stat` zeigt match/training nicht.

### P6 — RENAME (verhalten-neutral, 3 Sub-Blöcke, Gate = volle Suite grün)
**P6a DB** `20261283000000_rename_organizer_teams.sql`: `ALTER TABLE clubs RENAME TO
organizer_teams`; `club_memberships RENAME TO team_members`; `tournaments RENAME COLUMN club_id TO
organizer_team_id`. RPC-Rename `club_*`→`team_*` via `ALTER FUNCTION … RENAME` (exakte Signaturen);
Helper `is_active_club_member`/`is_club_manager`/`club_caller_*`. Alle Bodies, die
`club_memberships/clubs/club_id` lesen (inkl. P2-Gates, tournament_create, list_administrable):
`CREATE OR REPLACE` auf neuem Bezeichner — **auf echtem letztem Body, Body-Diff = nur Bezeichner.**
**P6b Dart** `lib/features/club/`→`organizer_team/`; `Club*`→`OrganizerTeam*`, `clubRoles`→
`teamRoles`, `ClubId`→`OrganizerTeamId`; RPC-Literale `'club_*'`→`'team_*'`; Wire-Keys
`club_id`→`organizer_team_id` **konsistent mit RPC-Projektion**. Router-Pfade `/clubs` **belassen**
(OE-3). **P6c l10n** „Verein"→„Veranstalterteam".
**Verhaltens-Neutralität:** Baseline-Snapshot (Testanzahl + analyze-Issues) vor P6; nach P6 identisch
grün; je `CREATE OR REPLACE` Body-Diff nur Bezeichner. pgTAP-Smoke: `to_regclass('organizer_teams')`
notnull, `('clubs')` null; `pg_policies` tablename='team_members' Count erhalten;
`pg_publication_tables` für die 3 Tabellen = 0.

### P7 — Events / i18n / Audit
l10n alle „Verein"-Strings; Rollennamen aus `_roleLabel` nach `app_de.arb`; Inbox-Kinds `club_*`→
`team_*` **additiv** (neue Kinds hinzufügen, alte für Bestand belassen); Rollenänderung→Inbox-Event.

## 3. Bestand-Remap (SQL) + Edge
Remap-UPDATE vor CHECK; Audit vor UPDATE. **Über-Vergabe-Edge:** member-only→admin gibt Management.
Vor Migration read-only Probe `SELECT count(*) … WHERE removed_at IS NULL AND NOT (roles &&
{owner,admin,referee})`; ist >0 bei realem Bestand → dem User berichten (manuell auf referee/entfernen).

## 4. Risiken + offene Entscheidungen
- **R1** übersehener Gate-Call-Site → Alias `tournament_caller_can_manage`→`_administer` (fail-safe) +
  `grep` nach P2 = keine Call-Sites mehr. **R2** Stale-Body (v.a. update 000273 mit Live-Recompute,
  start 000261 mit Notify) → grep-tail-1 + Body-Diff. **R3** Über-Vergabe → Probe §3. **R4** Rename
  Wire-Key-Mismatch → Suite-Gate + Key-Konsistenz. **R5** pending invitations ohne role → DEFAULT
  'admin'. **R6** 1vs1/Training nicht anfassen.
- **OE-2** start=Setup (bestätigen). **OE-3** `/clubs`-Pfade belassen. **OE-4** Alias statt Drop.
  **OE-5** Veranstalter-Kachel→bestehendes Dashboard+Team-Sektion. **OE-6** Ongoing-Match client-seitig.

## 5. Verifikation je Block
git status nur Scope; analyze keine neuen Issues vs Baseline; `flutter test --no-pub` grün; additive
Migration via `supabase migration up`; Proben BEGIN/ROLLBACK; je `CREATE OR REPLACE` grep-tail-1 +
Body-Diff; ein Commit/Block. P6: Baseline-Snapshot identisch nach Rename; `to_regclass`/`pg_policies`/
`pg_publication_tables`-Smoke.

### Critical Files
`20260901000012_club_schema.sql` (CHECK P1, Constraint-Name ermitteln) ·
`20261255000000_tournament_administrable_gate_and_list.sql` (Gate-Body-Anker P2) ·
`tournament_providers.dart` (Provider P2) · `club_models.dart` (clubRoles P1 / Rename P6b) ·
`20260901000013_club_rpcs.sql` (invitation_respond/set_member_roles P1+P3).
