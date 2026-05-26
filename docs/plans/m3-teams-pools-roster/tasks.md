# M3 — Atomare Task-Liste

> Stand: 2026-05-26
> Bezug: `sprint-plan.md` (Waves, Sub-Milestones), `architecture.md`, `milestone-plan.md`, `open-decisions.md` (alle 7 ODs resolved), ADR-0018, ADR-0019, ADR-0020
> Senior-Sizing: max 100 LOC, max 3 Files, max 1h netto pro Task

## Konvention

- IDs folgen `TASK-M3.<sub>-T<n>`. Sub ∈ {1, 2, 3}. Nummerierung folgt der Wave-Reihenfolge aus `sprint-plan.md`.
- Wave-Nummer bezieht sich auf `sprint-plan.md` §Wave-Plan.
- Agents: `coder-frontend` für Flutter-UI, `coder-data` für DB/Migrations/RPCs, `coder-domain` für `packages/kubb_domain/`, `tester` für Tests/Goldens/Property-Tests, `coder-docs` für Demo-Script.
- TDD-Pflicht im Domain-Package: ein Test-Task vor jedem Impl-Task. Test-Task hat `tester` als Agent, Impl-Task hat `coder-domain`.

---

# M3.1 — Teams (Wave 1 bis 4)

## TASK-M3.1-T1: Schema-Migration `team_schema.sql`

- **Type**: data
- **Size**: L
- **Bounded Context**: team
- **Agent**: coder-data
- **Dependencies**: —
- **Wave**: 1
- **Files (anticipated)**: `supabase/migrations/20260615000001_team_schema.sql`
- **LOC-Budget**: ~100

### Goal

Migration legt die fünf Team-Tabellen samt Indices und RLS-SELECT-Policies an: `teams`, `team_memberships`, `team_guest_players`, `team_invitations`, `team_audit_events`.

### Acceptance Criteria

- Given Migration läuft auf leerer DB When `\dt team_*` Then alle fünf Tabellen existieren mit den Spalten aus `architecture.md` §3.2.
- Given Migration läuft When `\d team_memberships` Then UNIQUE-Partial-Index `(team_id, user_id) WHERE removed_at IS NULL` existiert.
- Given Migration läuft When `\d teams` Then RLS aktiviert, SELECT-Policy öffentlich (für Team-Suche FR-PUB-9).
- Given Migration läuft When `\d team_invitations` Then CHECK-Constraint auf `state IN ('pending','accepted','declined','revoked')`.

### Notes

- Spalten exakt aus `architecture.md` §3.2-Tabelle übernehmen.
- Indices zusätzlich anlegen: `team_memberships(user_id) WHERE removed_at IS NULL`, `team_invitations(invitee_user_id, state)` (siehe §7).
- `teams.home_club_id` als nullable FK-Stub ohne Referenz-Tabelle — `clubs` kommt erst in M5+.
- Migration kollidiert nicht mit M2-Migrationen (eigenes Datum 20260615).
- **Contract für M3.1-T4/T5**: Spaltennamen und Typen sind verbindlich, RPCs schreiben gegen genau dieses Schema.

---

## TASK-M3.1-T2: Value Objects für Team-IDs

- **Type**: domain
- **Size**: S
- **Bounded Context**: core
- **Agent**: coder-domain
- **Dependencies**: —
- **Wave**: 1
- **Files (anticipated)**: `packages/kubb_domain/lib/src/values/ids.dart`, `packages/kubb_domain/test/values/team_ids_test.dart`
- **LOC-Budget**: ~50

### Goal

`TeamGuestPlayerId`, `TeamMembershipId`, `TeamInvitationId` als Wrapped-UUID-Value-Objects analog zu bestehendem `TeamId` und `UserId`.

### Acceptance Criteria

- Given UUID-String `"a1b2…"` When `TeamGuestPlayerId(uuid)` Then Instanz mit `value == uuid`.
- Given zwei Instanzen mit gleicher UUID Then `==` ist `true`, `hashCode` ist gleich.
- Given Konstruktor mit leerem String When `TeamGuestPlayerId("")` Then `ArgumentError`.
- Given Tests mit den drei neuen IDs Then alle grün.

### Notes

- Muster aus bestehendem `TeamId`/`UserId` 1:1 übernehmen.
- **Contract**: `TeamGuestPlayerId.value` und `TeamMembershipId.value` werden in `RosterSlotInput` (M3.2-T4) verwendet.

---

## TASK-M3.1-T3: Schema-Smoke-Tests Team-Migration

- **Type**: tests
- **Size**: S
- **Bounded Context**: team
- **Agent**: tester
- **Dependencies**: TASK-M3.1-T1
- **Wave**: 1
- **Files (anticipated)**: `supabase/tests/team_schema_test.sql` (pgTAP) **oder** `test/integration/team_schema_test.dart`
- **LOC-Budget**: ~70

### Goal

Tests verifizieren dass alle Tabellen, Indices, Constraints, RLS-Policies existieren und greifen. Test-First für die folgenden RPCs.

### Acceptance Criteria

- Given Migration applied When Tests laufen Then `has_table('teams')`, `has_table('team_memberships')`, etc. sind grün.
- Given Insert von zwei Memberships mit gleichem `(team_id, user_id)` und `removed_at IS NULL` Then UNIQUE-Violation.
- Given anonymer SELECT auf `teams` Then liefert Rows (öffentlich).
- Given anonymer INSERT auf `teams` Then 42501 (RLS).

### Notes

- Wenn pgTAP in Supabase-Pipeline nicht verfügbar: Dart-Integration-Test gegen lokale Supabase. Vorbild M2-T0-Spike.
- **Contract**: Test-Setup-Hilfsfunktionen (z.B. `_seedTeam(...)`) werden in T7 wiederverwendet — Helper-Modul in der Test-Datei vorsehen.

---

## TASK-M3.1-T4: Team-RPCs Teil A (Create/List/Get/Invite/Respond)

- **Type**: data
- **Size**: L
- **Bounded Context**: team
- **Agent**: coder-data
- **Dependencies**: TASK-M3.1-T1
- **Wave**: 2
- **Files (anticipated)**: `supabase/migrations/20260615000002_team_rpcs_a.sql`
- **LOC-Budget**: ~100

### Goal

Migration legt fünf RPCs an: `team_create`, `team_list_for_caller`, `team_get`, `team_invite`, `team_invitation_respond`. Alle `SECURITY DEFINER`.

### Acceptance Criteria

- Given Auth-Nutzer When `team_create('Hammer-Crew', 'B', NULL, 'CH')` Then `teams`-Row plus `team_memberships`-Row für Caller plus Audit-Event `team_created`.
- Given Caller-Pool-Mitglied When `team_invite(team_id, invitee_user_id)` Then `team_invitations`-Row (state=`pending`) plus Inbox-Eintrag mit Type `team_invitation`.
- Given Doppel-Invite an dieselbe Person Then Error `INVITATION_ALREADY_PENDING`.
- Given Invitee When `team_invitation_respond(invitation_id, true)` Then `team_memberships`-Insert plus state=`accepted`.
- Given Non-Invitee When `team_invitation_respond(invitation_id, ...)` Then 42501.

### Notes

- RPC-Signaturen aus `architecture.md` §3.2-Tabelle.
- **Contract für M3.1-T9 (Repository)**: Return-Shape von `team_create` ist `uuid`, von `team_list_for_caller` ist `setof teams`, von `team_get` ist `jsonb` (Header + Pool). Im Repository als Wire-Type erwartet.
- Inbox-Item-Type `team_invitation` wird in M3.1-T6 definiert — Hardcoded String hier (`'team_invitation'`) ist Contract-Punkt.

---

## TASK-M3.1-T5: Team-RPCs Teil B (Guest/Remove/Leave/Dissolve)

- **Type**: data
- **Size**: L
- **Bounded Context**: team
- **Agent**: coder-data
- **Dependencies**: TASK-M3.1-T1
- **Wave**: 2
- **Files (anticipated)**: `supabase/migrations/20260615000002_team_rpcs_b.sql`
- **LOC-Budget**: ~100

### Goal

Migration legt fünf RPCs an: `team_add_guest`, `team_remove_member`, `team_remove_guest`, `team_leave`, `team_dissolve`. OD-M3-01-Empfehlung B umgesetzt: kritische Aktionen erzeugen Audit-Event plus Inbox-Notification an alle anderen Pool-Mitglieder.

### Acceptance Criteria

- Given Pool-Mitglied When `team_add_guest(team_id, 'Toni Tester')` Then `team_guest_players`-Row plus Audit-Event `guest_added`.
- Given Pool-Mitglied A entfernt Pool-Mitglied B per `team_remove_member` Then `team_memberships.removed_at` gesetzt, Audit-Event `member_removed` mit `actor=A`, plus Inbox-Item `team_member_removed` für jedes andere Pool-Mitglied (OD-M3-01).
- Given Letztes registriertes Mitglied verlässt Team When `team_leave` Then Team automatisch `dissolved_at` (FR-TEAM-19) plus Audit-Event `team_dissolved`.
- Given `team_dissolve` aufgerufen ohne Consent aller Mitglieder Then Error `DISSOLVE_NEEDS_CONSENT`.
- Given Non-Member When `team_remove_member` Then 42501.

### Notes

- Audit + Inbox-Notification: pro entferntem Mitglied wird `inbox_items` für jedes andere Pool-Mitglied geschrieben (FR-NOT konform).
- `team_dissolve` braucht Consent-Tracking — pragmatisch via `team_audit_events` mit `kind='dissolve_consent'` plus check ob alle Mitglieder consentet haben. Wenn Consent-Tracking zu gross für 100 LOC: T5b als separater Task abspalten. Default: in T5 enthalten mit minimalem Consent-Model (jedes Mitglied muss vorher `team_consent_dissolve` aufgerufen haben).
- **Contract**: Inbox-Item-Type-Strings `'team_member_removed'` werden in M3.1-T6 definiert.

---

## TASK-M3.1-T6: Inbox-Item-Type-Erweiterung

- **Type**: data
- **Size**: S
- **Bounded Context**: core
- **Agent**: coder-data
- **Dependencies**: —
- **Wave**: 2
- **Files (anticipated)**: `supabase/migrations/20260615000002_team_inbox_types.sql`, `lib/features/inbox/data/inbox_item_types.dart`
- **LOC-Budget**: ~50

### Goal

Inbox-Item-Types `team_invitation`, `team_member_removed`, `team_dissolved` werden serverseitig zugelassen (CHECK-Constraint erweitert oder Enum-Wert hinzugefügt) und clientseitig im Mapping bekannt gemacht.

### Acceptance Criteria

- Given Migration läuft When Insert in `inbox_items` mit `kind='team_invitation'` Then akzeptiert.
- Given Client liest Inbox-Item mit Type `team_invitation` Then in `InboxItemType.teamInvitation` (oder analog) gemappt.
- Given DE-Strings `inboxTeamInvitation`, `inboxTeamMemberRemoved`, `inboxTeamDissolved` existieren in ARB Then `flutter pub run intl_utils:generate` läuft fehlerfrei.

### Notes

- Aktuelle Inbox-Struktur prüfen: wenn `inbox_items.kind` text+CHECK, dann CHECK erweitern; wenn Enum, dann ALTER TYPE.
- **Contract** für M3.1-T9, T14: Mapping-Konstanten werden im Repository und Invitation-Screen genutzt.

---

## TASK-M3.1-T7: pgTAP/Integration-Tests Team-RPCs

- **Type**: tests
- **Size**: M
- **Bounded Context**: team
- **Agent**: tester
- **Dependencies**: TASK-M3.1-T4, TASK-M3.1-T5, TASK-M3.1-T6
- **Wave**: 3
- **Files (anticipated)**: `supabase/tests/team_rpcs_test.sql` (pgTAP) **oder** `test/integration/team_rpcs_test.dart`
- **LOC-Budget**: ~100

### Goal

Tests decken Happy-Path, Auth-Fail, BR-Edge-Cases der zehn Team-RPCs ab. Schwerpunkt: FR-TEAM-19 (Last-Member-Auto-Dissolve), FR-TEAM-8 (Invitation-Lifecycle), OD-M3-01 (Audit+Notification).

### Acceptance Criteria

- Given Auth-Nutzer A When `team_create` Then `team_get` zeigt A als einziges Mitglied.
- Given A invitet B, B akzeptiert When `team_get(team_id)` Then beide Mitglieder.
- Given Team mit nur Mitglied A (registriert) plus Gast G When `team_leave(A)` Then Team `dissolved_at` (Gast zählt nicht).
- Given A entfernt B When Inbox-Liste für C abgefragt Then `team_member_removed` Item vorhanden.
- Given Anonymer Caller When `team_create` Then 42501.

### Notes

- Test-Helper `_seedTeam` aus M3.1-T3 wiederverwenden.
- Wenn pgTAP nicht verfügbar: Dart-Integration-Test gegen lokale Supabase.

---

## TASK-M3.1-T8: Wire-Models Team

- **Type**: data
- **Size**: M
- **Bounded Context**: team
- **Agent**: coder-frontend
- **Dependencies**: TASK-M3.1-T2
- **Wave**: 3
- **Files (anticipated)**: `lib/features/team/data/team_models.dart`
- **LOC-Budget**: ~90

### Goal

Vier freezed-Klassen: `TeamWire`, `TeamMembershipWire`, `TeamInvitationWire`, `GuestPlayerWire`. JSON-Serialisierung gegen die RPC-Return-Shapes aus T4/T5.

### Acceptance Criteria

- Given Json-Payload aus `team_get` When `TeamWire.fromJson(...)` Then Felder gemappt (id, displayName, leagueMembership, …).
- Given freezed-generated `==` und `copyWith` Then verfügbar.
- Given Wire-Model When zu DTO (z.B. `TeamRef`) konvertierbar Then sauberer Mapper.
- Given `flutter pub run build_runner build` Then keine Fehler.

### Notes

- Zwei Files erlaubt wenn Code-Generator-Output mitgezählt wird; LOC-Budget bezieht sich auf hand-geschriebenen Code.
- **Contract** für T9: Wire-Property-Namen sind verbindlich für die Repository-Methoden-Returns.

---

## TASK-M3.1-T9: Team-Repository

- **Type**: data
- **Size**: M
- **Bounded Context**: team
- **Agent**: coder-frontend
- **Dependencies**: TASK-M3.1-T4, TASK-M3.1-T5, TASK-M3.1-T8
- **Wave**: 3
- **Files (anticipated)**: `lib/features/team/data/team_repository.dart`
- **LOC-Budget**: ~100

### Goal

Riverpod-`Provider` über `Ref`. Eine Methode pro RPC (`createTeam`, `listMyTeams`, `getTeam`, `invite`, `respondInvitation`, `addGuest`, `removeMember`, `removeGuest`, `leave`, `dissolve`).

### Acceptance Criteria

- Given `teamRepositoryProvider` When `.read(...)` Then Repository-Instanz.
- Given `createTeam('Crew', LeagueMembership.b, …)` When ausgeführt Then RPC `team_create` aufgerufen, `TeamId` zurück.
- Given RPC-Error `42501` Then Repository wirft `TeamPermissionException`.
- Given RPC-Error `INVITATION_ALREADY_PENDING` Then `TeamInvitationDuplicateException`.

### Notes

- RPC-Signaturen aus T4/T5 (Contract).
- Pragmatic CRUD per ADR-0002: kein Domain-Port (`TeamRemote`) — Repository ruft Supabase direkt. Begründung siehe `architecture.md` §3.5.

---

## TASK-M3.1-T10: Team-Riverpod-Provider

- **Type**: frontend
- **Size**: M
- **Bounded Context**: team
- **Agent**: coder-frontend
- **Dependencies**: TASK-M3.1-T9
- **Wave**: 4
- **Files (anticipated)**: `lib/features/team/application/team_list_provider.dart`, `lib/features/team/application/team_detail_provider.dart`, `lib/features/team/application/team_membership_controller.dart`
- **LOC-Budget**: ~100

### Goal

`team_list_provider` (FutureProvider: meine Teams + Search), `team_detail_provider` (FutureProvider.family<TeamId>), `team_membership_controller` (Notifier mit invite/accept/decline/remove/dissolve).

### Acceptance Criteria

- Given Logged-in User When `teamListProvider` gelesen Then Liste der `TeamWire` aus `team_list_for_caller`.
- Given `teamDetailProvider(teamId)` Then Header + Pool.
- Given Controller-`invite(...)` läuft When OK Then State invalidiert und `teamDetailProvider` refreshet.
- Given Controller-Action wirft Exception Then State `AsyncError`.

### Notes

- Controller-Patterns aus bestehenden M1/M2-Controllern übernehmen.
- **Contract** für T11–T14: Controller-API.

---

## TASK-M3.1-T11: `team_list_screen.dart`

- **Type**: frontend
- **Size**: M
- **Bounded Context**: team
- **Agent**: coder-frontend
- **Dependencies**: TASK-M3.1-T10
- **Wave**: 4
- **Files (anticipated)**: `lib/features/team/presentation/team_list_screen.dart`
- **LOC-Budget**: ~90

### Goal

Zwei Tabs ("Meine Teams", "Suchen"), Karten-Layout (Name, Liga, Pool-Grösse), Tap → Detail, FAB → Create.

### Acceptance Criteria

- Given `teamListProvider` returns 3 Teams When Screen rendert Then drei Karten im "Meine Teams"-Tab.
- Given Tab "Suchen" plus Query "Hammer" When Submit Then RPC-Search (filtert serverseitig) plus Resultate sichtbar.
- Given Tap auf Karte Then Navigation `/teams/<id>`.
- Given FAB-Tap Then Navigation `/teams/new`.

### Notes

- Search-RPC nutzt aktuell `team_list_for_caller` plus clientseitiges Filter — Server-Side-Search ist out-of-scope für M3 (kommt im FR-PUB-9-Block M5).

---

## TASK-M3.1-T12: `team_create_screen.dart`

- **Type**: frontend
- **Size**: S
- **Bounded Context**: team
- **Agent**: coder-frontend
- **Dependencies**: TASK-M3.1-T10
- **Wave**: 4
- **Files (anticipated)**: `lib/features/team/presentation/team_create_screen.dart`
- **LOC-Budget**: ~80

### Goal

Wizard-leichtes Form: Name, Liga-Vorwahl (Dropdown {A,B,C,D}, Default B), optional Logo-URL, optional Country-Code. Submit ruft `team_membership_controller.create(...)`.

### Acceptance Criteria

- Given Eingabe "Hammer-Crew" + Liga B When Submit Then Navigation zu `/teams/<new-id>`.
- Given Fehler bei Submit Then Snackbar mit Fehlertext.
- Given leerer Name Then Submit-Button disabled.

### Notes

- Logo-URL ist plain text-Feld, kein File-Picker (siehe `architecture.md` §5).

---

## TASK-M3.1-T13: `team_detail_screen.dart` + Member-Card

- **Type**: frontend
- **Size**: L
- **Bounded Context**: team
- **Agent**: coder-frontend
- **Dependencies**: TASK-M3.1-T10
- **Wave**: 4
- **Files (anticipated)**: `lib/features/team/presentation/team_detail_screen.dart`, `lib/features/team/presentation/widgets/team_member_card.dart`
- **LOC-Budget**: ~100

### Goal

Team-Detail-Screen mit Header (Name, Liga, Logo), Pool-Liste mit `TeamMemberCard` (Avatar/Initialen, Name, Rollen-Badge "Mitglied"/"Gast"), Aktionen "Mitglied einladen", "Gast hinzufügen", "Verlassen", "Auflösen". Member-Card wiederverwendbar.

### Acceptance Criteria

- Given Team mit 3 Members + 1 Guest When Screen rendert Then vier Karten im Pool-Bereich.
- Given Tap auf Mitglied X + "Entfernen" Then Bestätigungs-Dialog plus RPC-Call.
- Given Mitglied entfernt Then Snackbar plus Pool-Refresh plus (OD-M3-01) Inbox-Notification dokumentiert.
- Given Aktion "Verlassen" Then Confirmation plus Navigation zur Liste.

### Notes

- Drei Files erlaubt (Screen + Member-Card + ggf. Action-Sheet) — bei LOC-Druck Member-Card minimal halten.
- **Contract**: `TeamMemberCard` wird in M3.2-T13 für Pool-Conflict-Anzeige wiederverwendet (mit zusätzlichem `isConflicted: bool`-Property erweiterbar).

---

## TASK-M3.1-T14: `team_invitation_screen.dart` + Inbox-Hook

- **Type**: frontend
- **Size**: M
- **Bounded Context**: team
- **Agent**: coder-frontend
- **Dependencies**: TASK-M3.1-T10, TASK-M3.1-T6
- **Wave**: 4
- **Files (anticipated)**: `lib/features/team/presentation/team_invitation_screen.dart`, `lib/features/inbox/presentation/inbox_item_renderer.dart` (Patch)
- **LOC-Budget**: ~80

### Goal

Screen für ausstehende Einladungen (Liste plus Detail), Akzeptieren/Ablehnen. Inbox-Item-Renderer um Type `team_invitation` erweitert (Tap navigiert zu Invitation-Screen).

### Acceptance Criteria

- Given User hat 2 Pending-Invitations When Screen rendert Then beide Karten sichtbar.
- Given Tap "Akzeptieren" Then `team_invitation_respond(id, true)` plus Navigation `/teams/<id>`.
- Given Tap "Ablehnen" Then `respond(id, false)` plus Item aus Liste verschwindet.
- Given Inbox-Item mit Type `team_invitation` Then Tap navigiert zu Invitation-Screen.

### Notes

- Inbox-Renderer-Patch ist minimal: Switch-Case-Branch für `team_invitation`.

---

## TASK-M3.1-T15: l10n DE für Team-Screens

- **Type**: frontend
- **Size**: S
- **Bounded Context**: team
- **Agent**: coder-frontend
- **Dependencies**: TASK-M3.1-T11, TASK-M3.1-T12, TASK-M3.1-T13, TASK-M3.1-T14
- **Wave**: 4
- **Files (anticipated)**: `lib/l10n/app_de.arb`
- **LOC-Budget**: ~80

### Goal

Alle DE-Strings für die vier Team-Screens plus Inbox-Item-Renderer in `app_de.arb`. Generator läuft fehlerfrei.

### Acceptance Criteria

- Given alle Strings aus T11–T14 referenzieren ARB-Keys When `flutter pub run intl_utils:generate` Then keine Missing-Key-Warnings.
- Given Screens werden gebaut Then keine Hardcoded-deutschen-Strings (Lint via Plugin).
- Given neue Keys `teamList*`, `teamCreate*`, `teamDetail*`, `teamInvitation*`, `inboxTeam*` vorhanden.

### Notes

- Nur DE — EN ist out-of-scope (App ist Android/Schweiz, ADR-0011).

---

## TASK-M3.1-T16: Routing-Anbindung + Home-Eintrag

- **Type**: frontend
- **Size**: S
- **Bounded Context**: core
- **Agent**: coder-frontend
- **Dependencies**: TASK-M3.1-T11, TASK-M3.1-T13
- **Wave**: 4
- **Files (anticipated)**: `lib/app/router.dart`, `lib/features/home/presentation/home_screen.dart`
- **LOC-Budget**: ~50

### Goal

Routen `/teams`, `/teams/new`, `/teams/:id`, `/teams/invitations` werden in go_router registriert. Home-Screen bekommt Tile "Teams".

### Acceptance Criteria

- Given URL `/teams` When App startet Then `TeamListScreen` rendert.
- Given Tile-Tap auf Home Then Navigation `/teams`.
- Given URL `/teams/<uuid>` mit nicht existierender ID Then Error-Page.

### Notes

- go_router-Stil aus bestehenden Routen übernehmen.

---

## TASK-M3.1-T17: Widget-Tests Team-Controller + Card

- **Type**: tests
- **Size**: M
- **Bounded Context**: team
- **Agent**: tester
- **Dependencies**: TASK-M3.1-T10, TASK-M3.1-T13
- **Wave**: 4
- **Files (anticipated)**: `test/features/team/team_membership_controller_test.dart`, `test/features/team/widgets/team_member_card_test.dart`
- **LOC-Budget**: ~90

### Goal

Controller-Tests (Mock-Repository) plus Snapshot/Widget-Test für `TeamMemberCard`-Layout.

### Acceptance Criteria

- Given Mock-Repository liefert `TeamWire`-Liste When Controller-`load()` Then State `AsyncData`.
- Given Controller-`invite(...)` Then Repository-Method aufgerufen.
- Given `TeamMemberCard(member: ..., role: 'guest')` Then Badge "Gast" sichtbar.
- Given Card-Tap Then Callback ausgelöst.

### Notes

- Mock-Repository minimal halten (nur die zwei genutzten Methoden).

---

# M3.2 — Tournament-Roster (Wave 5 bis 7)

## TASK-M3.2-T1: Roster-Schema-Migration + BR-5-Trigger

- **Type**: data
- **Size**: L
- **Bounded Context**: tournament
- **Agent**: coder-data
- **Dependencies**: TASK-M3.1-T1
- **Wave**: 5
- **Files (anticipated)**: `supabase/migrations/20260615000003_tournament_team_roster.sql`
- **LOC-Budget**: ~100

### Goal

Migration: `tournament_participants` bekommt `team_id`, `roster_locked_at`, `user_id` nullable; CHECK-Constraint `(team_id IS NULL AND user_id IS NOT NULL) OR (team_id IS NOT NULL)`. Neue Tabelle `tournament_roster_slots` plus BR-5-Trigger.

### Acceptance Criteria

- Given Migration läuft When `\d tournament_participants` Then neue Spalten und CHECK-Constraint existieren, M1-Rows valide.
- Given Migration läuft When `\d tournament_roster_slots` Then Spalten `participant_id, slot_index, member_user_id, guest_player_id, assigned_at, assigned_by, replaced_at, replaced_by, reason` existieren plus CHECK (genau eines von member/guest) plus UNIQUE `(participant_id, slot_index) WHERE replaced_at IS NULL`.
- Given Trigger When Insert mit `member_user_id=U` und U ist bereits in einem offenen Slot eines anderen Participants desselben Turniers Then ERRCODE `23P01` mit Hint `BR_5_VIOLATION`.
- Given Insert für anderes Turnier Then keine Verletzung (Cross-Tournament-OK).

### Notes

- Spec exakt aus `architecture.md` §3.3.
- Index `tournament_participants(team_id) WHERE team_id IS NOT NULL` zusätzlich anlegen (§7).
- **Contract** für M3.2-T6, T7, T13: Spaltennamen + Trigger-ERRCODE sind verbindlich.

---

## TASK-M3.2-T2: pgTAP/Integration-Tests BR-5-Trigger

- **Type**: tests
- **Size**: M
- **Bounded Context**: tournament
- **Agent**: tester
- **Dependencies**: TASK-M3.2-T1
- **Wave**: 5
- **Files (anticipated)**: `supabase/tests/br5_trigger_test.sql` **oder** `test/integration/br5_trigger_test.dart`
- **LOC-Budget**: ~80

### Goal

Tests verifizieren BR-5-Trigger-Verhalten (Doppel-Roster blockiert, Cross-Tournament erlaubt, Replace-Pfad geht ohne Verletzung).

### Acceptance Criteria

- Given U in Team A Slot 1 Turnier T1 When Insert U in Team B Slot 1 Turnier T1 Then `23P01`.
- Given U in Team A Slot 1 Turnier T1 When Insert U in Team B Slot 1 Turnier T2 Then OK.
- Given U in Team A Slot 1 mit `replaced_at`=now() When Insert U in Team B Slot 1 Turnier T1 Then OK (Slot geschlossen, U wieder verfügbar).
- Given parallele Inserts (Concurrency-Sim) Then Trigger bleibt konsistent (kein Race-Window).

### Notes

- Concurrency-Test optional, wenn pgTAP-Setup das nicht erlaubt: dokumentieren und Test serial halten.

---

## TASK-M3.2-T3: Property-Tests `RosterSlot{Input}`

- **Type**: tests
- **Size**: S
- **Bounded Context**: tournament
- **Agent**: tester
- **Dependencies**: —
- **Wave**: 5
- **Files (anticipated)**: `packages/kubb_domain/test/tournament/roster_slot_test.dart`
- **LOC-Budget**: ~70

### Goal

glados-Property-Tests für `RosterSlotInput` und `RosterSlot` — Invarianten "genau eines von memberUserId/guestPlayerId", `slotIndex ∈ [1, 6]`, FR-REG-12 (Liste muss min. 1 `member`-Entry haben).

### Acceptance Criteria

- Given `RosterSlotInput.member(1, userId)` Then `memberUserId != null && guestPlayerId == null`.
- Given Konstruktor mit beiden null oder beiden gesetzt Then `ArgumentError`.
- Given `slotIndex` out of range (0, 7) Then `ArgumentError`.
- Given Liste mit nur `guest`-Entries When Validator `requireAtLeastOneMember(list)` Then false.
- Given Liste mit mind. 1 `member` Then true.

### Notes

- glados-`Any<RosterSlotInput>` als Generator.
- **Contract** für M3.2-T4: Konstruktor-Form `.member(idx, user)`, `.guest(idx, guest)` aus `architecture.md` §3.5-Code-Block.

---

## TASK-M3.2-T4: Roster + Pool-Standings Value Objects

- **Type**: domain
- **Size**: S
- **Bounded Context**: tournament
- **Agent**: coder-domain
- **Dependencies**: TASK-M3.2-T3, TASK-M3.1-T2
- **Wave**: 6
- **Files (anticipated)**: `packages/kubb_domain/lib/src/tournament/roster_slot.dart`, `packages/kubb_domain/lib/src/tournament/pool_group_standings.dart`
- **LOC-Budget**: ~90

### Goal

Value Objects `RosterSlotInput` (Konstruktoren `.member(...)`, `.guest(...)`), `RosterSlot` (gelesene Form mit Audit-Feldern), `PoolGroupStandings` (Gruppe-Label + List<ParticipantStats>).

### Acceptance Criteria

- Given Konstruktor-Calls aus `architecture.md` §3.5 Then keine Test-Fails.
- Given `RosterSlot.fromJson(...)` Then korrekte Deserialisierung.
- Given `==` und `hashCode` Then sauber.
- Given `PoolGroupStandings('A', [stats])` Then immutable und List ist unmodifiable.

### Notes

- **Contract** für T5: alle drei Klassen sind im Port-Interface referenziert.

---

## TASK-M3.2-T5: `TournamentRemote`-Port-Erweiterung

- **Type**: domain
- **Size**: S
- **Bounded Context**: tournament
- **Agent**: coder-domain
- **Dependencies**: TASK-M3.2-T4
- **Wave**: 6
- **Files (anticipated)**: `packages/kubb_domain/lib/src/ports/tournament_remote.dart`
- **LOC-Budget**: ~60

### Goal

Drei neue Methoden in `TournamentRemote`: `registerTeam`, `replaceRosterSlot`, `getRoster` (Signaturen exakt aus `architecture.md` §3.5).

### Acceptance Criteria

- Given Interface erweitert When `flutter analyze` Then keine Errors.
- Given bestehende Fakes implementieren das Interface Then Compile-Fail bis Default-Impls oder Stub-Impls bereitgestellt.
- Given Signaturen When mit Code-Block aus §3.5 verglichen Then identisch.

### Notes

- Method-Stubs in Fakes mit `throw UnimplementedError()` befüllen, T10 vervollständigt sie.
- **Contract** für T9 (Supabase-Impl), T10 (Fake-Impl), und alle UI-Tasks.

---

## TASK-M3.2-T6: Tournament-Team-RPCs

- **Type**: data
- **Size**: L
- **Bounded Context**: tournament
- **Agent**: coder-data
- **Dependencies**: TASK-M3.2-T1
- **Wave**: 6
- **Files (anticipated)**: `supabase/migrations/20260615000004_tournament_team_rpcs.sql`
- **LOC-Budget**: ~100

### Goal

Drei RPCs: `tournament_register_team`, `tournament_roster_replace`, `tournament_roster_list`. OD-M3-07: Roster-Replace prüft `NOT EXISTS (... matches WHERE participant_id IN (...) AND status='awaiting_results')`.

### Acceptance Criteria

- Given `tournament_register_team(t_id, team_id, roster_json)` mit 3-Slot-Roster (1 member + 2 guests) When Caller ist Pool-Mitglied von team_id Then participant + 3 slots eingefügt.
- Given Roster ohne registriertes Mitglied Then Error `MIN_ONE_REGISTERED` (FR-REG-12).
- Given `tournament_roster_replace` vor `tournaments.status='finalized'` Then alte Slot-Row `replaced_at`, neue Slot-Row, Audit-Event.
- Given Replace bei offenem Match (Status `awaiting_results`) Then Error `ROSTER_LOCKED_DURING_MATCH` (OD-M3-07).
- Given Replace nach `finalized` Then `ROSTER_LOCKED` (FR-TEAM-15).

### Notes

- BR-5-Validierung läuft via Trigger aus T1.
- Audit-Event in `tournament_audit_events` (existiert aus M1).
- **Contract** für T8 (Tests), T9 (Adapter), T13 (Composition-Widget): RPC-Parameter-Reihenfolge und Fehler-Codes.

---

## TASK-M3.2-T7: Score-RPC-Anpassung für Team-Pfad

- **Type**: data
- **Size**: M
- **Bounded Context**: tournament
- **Agent**: coder-data
- **Dependencies**: TASK-M3.2-T1
- **Wave**: 6
- **Files (anticipated)**: `supabase/migrations/20260615000004_score_rpc_team_patch.sql`
- **LOC-Budget**: ~80

### Goal

`tournament_propose_set_score` und verwandte Score-RPCs lernen den Team-Pfad: Submitter-Validation via `EXISTS (... team_memberships WHERE team_id = participant.team_id AND user_id = caller AND removed_at IS NULL)` zusätzlich zu `participant.user_id = caller`. BR-9.

### Acceptance Criteria

- Given Team-Match Participant A (team_id=T1) When Pool-Mitglied U von T1 ruft `tournament_propose_set_score` Then OK.
- Given Non-Member ruft Score-RPC Then 42501.
- Given Einzel-Match (team_id IS NULL) Then Verhalten aus M1 unverändert (user_id-Check).
- Given Pool-Mitglied U war Mitglied, ist `removed_at` gesetzt Then 42501.

### Notes

- Existierende M1-RPCs CREATE OR REPLACE — keine breaking change auf Einzel-Pfad.
- **Contract**: Validierungs-CTE wird auch für `tournament_confirm_set_score` und `tournament_void_match` (falls in M1 vorhanden) angewandt.

---

## TASK-M3.2-T8: pgTAP/Integration-Tests Tournament-Team-RPCs

- **Type**: tests
- **Size**: M
- **Bounded Context**: tournament
- **Agent**: tester
- **Dependencies**: TASK-M3.2-T6, TASK-M3.2-T7
- **Wave**: 6
- **Files (anticipated)**: `supabase/tests/tournament_team_rpcs_test.sql` **oder** `test/integration/tournament_team_rpcs_test.dart`
- **LOC-Budget**: ~100

### Goal

Happy-Path Team-Registrierung, BR-5-Violation (Cross-Team), Roster-Replace vor/nach finalized, OD-M3-07-Block bei offenem Match, Score-RPC durch Pool-Mitglied.

### Acceptance Criteria

- Given Turnier `team_size=3` When Team-Captain ruft `tournament_register_team` mit gültigem Roster Then participant + 3 slots.
- Given derselbe Spieler in zwei Teams desselben Turniers Then `23P01`.
- Given Replace nach `finalized` Then `ROSTER_LOCKED`.
- Given Replace während Match `awaiting_results` Then `ROSTER_LOCKED_DURING_MATCH`.
- Given Pool-Mitglied B (nicht Captain) ruft Score-RPC für Team-A-Match Then OK.

### Notes

- Wenn Score-RPC-Setup zu komplex: minimaler Happy-Path-Test reicht.

---

## TASK-M3.2-T9: SupabaseTournamentRemote-Impl (Roster)

- **Type**: data
- **Size**: M
- **Bounded Context**: tournament
- **Agent**: coder-frontend
- **Dependencies**: TASK-M3.2-T5, TASK-M3.2-T6
- **Wave**: 7
- **Files (anticipated)**: `lib/features/tournament/data/supabase_tournament_remote.dart`
- **LOC-Budget**: ~80

### Goal

Drei Methoden implementieren: `registerTeam`, `replaceRosterSlot`, `getRoster` als RPC-Calls.

### Acceptance Criteria

- Given `registerTeam(t_id, team_id, [slot1, slot2, slot3])` When ausgeführt Then RPC `tournament_register_team` aufgerufen, Wire-Payload korrekt (JSON-Array).
- Given Error `MIN_ONE_REGISTERED` Then `MinOneRegisteredException`.
- Given Error `23P01` Then `RosterBR5Exception`.
- Given Error `ROSTER_LOCKED_DURING_MATCH` Then `RosterLockedException` mit Cause "match-open".

### Notes

- Bestehende Adapter-Datei wird patched — additiv.

---

## TASK-M3.2-T10: FakeTournamentRemote-Impl (Roster)

- **Type**: tests
- **Size**: M
- **Bounded Context**: tournament
- **Agent**: tester
- **Dependencies**: TASK-M3.2-T5
- **Wave**: 7
- **Files (anticipated)**: `packages/kubb_domain/test/fakes/fake_tournament_remote.dart`
- **LOC-Budget**: ~80

### Goal

In-Memory-Impl der drei neuen Methoden für Widget-Tests. Simuliert BR-5-Lookup, Roster-Locked-Logik.

### Acceptance Criteria

- Given Fake hat 4 Teams seeded When `registerTeam(...)` Then In-Memory-Participant + Slots.
- Given Doppel-Roster Then `RosterBR5Exception`.
- Given Replace bei `finalized` Then `RosterLockedException`.

### Notes

- Reicht für Widget-Tests; produktiver Pfad ist T9.

---

## TASK-M3.2-T11: Property-Tests Domain für `RosterSlot{Input}` + FR-REG-12

- **Type**: tests
- **Size**: S
- **Bounded Context**: tournament
- **Agent**: tester
- **Dependencies**: TASK-M3.2-T3, TASK-M3.2-T4
- **Wave**: 7
- **Files (anticipated)**: `packages/kubb_domain/test/tournament/roster_validation_test.dart`
- **LOC-Budget**: ~60

### Goal

Ergänzt T3 um Invarianten-Tests, die die Value-Object-Impl aus T4 verifizieren (T3 war Test-First gegen Stubs).

### Acceptance Criteria

- Given Property-Test für FR-REG-12-Validator Then auf 100 Generierungen kein Fail.
- Given Slot-Index-Range-Test über n ∈ [2, 6] Then alle gültig, alle ausserhalb fail.
- Given Mixed-Liste mit duplicate slot_index Then Validator wirft `DuplicateSlotIndex`.

### Notes

- Kein Drift zu T3: T11 ist ergänzend, nicht Ersatz.

---

## TASK-M3.2-T12: Pool-Conflict-Helper-RPC

- **Type**: data
- **Size**: S
- **Bounded Context**: tournament
- **Agent**: coder-data
- **Dependencies**: TASK-M3.2-T1
- **Wave**: 7
- **Files (anticipated)**: `supabase/migrations/20260615000004_team_pool_conflict_helper.sql`
- **LOC-Budget**: ~50

### Goal

RPC `team_pool_with_tournament_conflicts(p_team_id, p_tournament_id)` retourniert Pool-Liste mit `conflicted` Flag (true wenn Mitglied bereits in einem anderen Roster desselben Turniers). R-M3-G2-Mitigation.

### Acceptance Criteria

- Given Team T1 mit Pool [A,B,C], Spieler A in Roster Turnier X When `team_pool_with_tournament_conflicts(T1, X)` Then [A:conflicted=true, B:false, C:false].
- Given Tournament Y (nicht X) Then [A:false, B:false, C:false].
- Given anonymer Caller Then 42501.

### Notes

- `SECURITY DEFINER`.
- **Contract** für T13: Return-Shape `[{user_id, display_name, conflicted}]`.

---

## TASK-M3.2-T13: `RosterCompositionWidget`

- **Type**: frontend
- **Size**: L
- **Bounded Context**: tournament
- **Agent**: coder-frontend
- **Dependencies**: TASK-M3.2-T4, TASK-M3.2-T12
- **Wave**: 7
- **Files (anticipated)**: `lib/features/tournament/presentation/widgets/roster_composition_widget.dart`
- **LOC-Budget**: ~100

### Goal

Tap-Select-Pattern (siehe R-M3.2-3): Pool-Liste links, N Slots rechts. Tap auf Pool-Eintrag fragt "Welcher Slot?", Tap auf Slot fragt "Welcher Pool-Eintrag?". Conflicted Pool-Entries (aus T12) sind ausgegraut. Client-side Validierung: min. 1 `member`-Slot (FR-REG-12).

### Acceptance Criteria

- Given Pool [A,B,C,D] + 3 Slots When 3 Members zugewiesen Then `onChanged([slot1, slot2, slot3])` ruft Parent.
- Given nur Gäste zugewiesen Then "Mind. 1 registriertes Mitglied"-Warnung sichtbar.
- Given Pool-Entry mit `conflicted=true` Then ausgegraut + disabled + Tooltip "Bereits in anderem Roster".
- Given responsive bei 360 px Breite Then Slots 1..6 vertikal scrollbar.

### Notes

- Widget bekommt `availableSlots: int` (2..6) als Parameter, kein Hardcoded.
- Tap-Select statt Drag spart Aufwand (R-M3.2-3).

---

## TASK-M3.2-T14: `RegisterTeamScreen`

- **Type**: frontend
- **Size**: L
- **Bounded Context**: tournament
- **Agent**: coder-frontend
- **Dependencies**: TASK-M3.2-T9, TASK-M3.2-T13
- **Wave**: 7
- **Files (anticipated)**: `lib/features/tournament/presentation/register_team_screen.dart`
- **LOC-Budget**: ~100

### Goal

Screen: Team-Auswahl (Dropdown aus `teamListProvider`), `RosterCompositionWidget`, Submit. Bei Submit-Error wird die Server-Validierung (BR-5, MIN_ONE_REGISTERED) als Snackbar/Dialog angezeigt.

### Acceptance Criteria

- Given User hat 2 Teams When Screen lädt für Turnier T mit `team_size=3` Then Dropdown mit 2 Optionen, 3 Slots.
- Given Submit mit gültigem Roster Then `registerTeam` aufgerufen, Navigation zu Turnier-Detail.
- Given Server-Error `BR_5_VIOLATION` Then Snackbar mit verständlichem DE-Text plus Highlight des konfliktären Slots.

### Notes

- l10n in T18.

---

## TASK-M3.2-T15: `RosterEditorScreen`

- **Type**: frontend
- **Size**: L
- **Bounded Context**: tournament
- **Agent**: coder-frontend
- **Dependencies**: TASK-M3.2-T9, TASK-M3.2-T4
- **Wave**: 7
- **Files (anticipated)**: `lib/features/tournament/presentation/roster_editor_screen.dart`
- **LOC-Budget**: ~100

### Goal

Mid-Tournament-Ansicht: aktuelle Slots, Replace-Dialog (Pool-Liste plus optionales Grund-Feld). Audit-Trail-Anzeige (vergangene Replacements) als kollabierbare ExpansionTile.

### Acceptance Criteria

- Given Roster mit 3 Slots When Screen lädt Then aktuelle Occupants sichtbar.
- Given Tap "Replace Slot 2" Then Dialog mit Pool + Grund-Feld.
- Given Submit Replace Then `replaceRosterSlot(...)` plus Refetch.
- Given Server-Error `ROSTER_LOCKED_DURING_MATCH` Then Dialog "Substitution nur zwischen Matches möglich" (OD-M3-07).
- Given Tournament `finalized` Then alle Replace-Buttons disabled.

### Notes

- Audit-Trail-Ansicht ist kompakt — voll-Audit-Screen ist M5+.

---

## TASK-M3.2-T16: Register-Screen Weiche Einzel vs. Team

- **Type**: frontend
- **Size**: M
- **Bounded Context**: tournament
- **Agent**: coder-frontend
- **Dependencies**: TASK-M3.2-T14
- **Wave**: 7
- **Files (anticipated)**: `lib/features/tournament/presentation/tournament_register_screen.dart`
- **LOC-Budget**: ~60

### Goal

`tournament_register_screen.dart` (M1) routet bei `tournaments.team_size > 1` direkt zu `RegisterTeamScreen` statt Einzel-Flow.

### Acceptance Criteria

- Given Turnier `team_size=1` Then Einzel-Flow (M1, unverändert).
- Given Turnier `team_size=3` Then Team-Flow.
- Given User hat keine Teams Then CTA "Erstelle ein Team" + Navigation `/teams/new`.

### Notes

- Bestehende M1-Logik nicht brechen.

---

## TASK-M3.2-T17: Detail-Screen Roster-Tab + Team-Match-Header

- **Type**: frontend
- **Size**: M
- **Bounded Context**: tournament
- **Agent**: coder-frontend
- **Dependencies**: TASK-M3.2-T9
- **Wave**: 7
- **Files (anticipated)**: `lib/features/tournament/presentation/tournament_detail_screen.dart`
- **LOC-Budget**: ~80

### Goal

Roster-Tab sichtbar wenn Turnier-Participant ein `team_id` hat. Match-Detail-Header zeigt "Team A (Roster: X, Y, Z)" statt "Participant A". R-M3-G3-Mitigation.

### Acceptance Criteria

- Given Turnier `team_size=3`, User ist Pool-Mitglied Then Roster-Tab sichtbar.
- Given User ist nicht Pool-Mitglied Then Roster-Tab nicht sichtbar oder read-only.
- Given Match-Header in Team-Match Then "Hammer-Crew (X, Y, Z)" sichtbar.
- Given Match in Einzel-Turnier Then alter Header unverändert.

### Notes

- Tab-Anzeige hängt an `tournament_roster_list`-Call (Repo-Method aus T9).

---

## TASK-M3.2-T18: l10n DE für M3.2-Screens

- **Type**: frontend
- **Size**: S
- **Bounded Context**: tournament
- **Agent**: coder-frontend
- **Dependencies**: TASK-M3.2-T13, TASK-M3.2-T14, TASK-M3.2-T15, TASK-M3.2-T17
- **Wave**: 7
- **Files (anticipated)**: `lib/l10n/app_de.arb`
- **LOC-Budget**: ~60

### Goal

DE-Strings für Register-Team, Roster-Editor, Roster-Composition, Match-Header. Generator-Run grün.

### Acceptance Criteria

- Given Screens referenzieren ARB-Keys When Generator läuft Then ohne Missing-Keys.
- Given DE-Texte gut formuliert ("Mindestens ein registriertes Mitglied", "Substitution nur zwischen Matches") Then keine Marketing-Wörter.

### Notes

- Konsistente Keys `rosterCompose*`, `rosterEditor*`, `registerTeam*`.

---

## TASK-M3.2-T19: Integrations-Test 4-Team-Round-Robin + Substitution

- **Type**: tests
- **Size**: L
- **Bounded Context**: tournament
- **Agent**: tester
- **Dependencies**: TASK-M3.2-T14, TASK-M3.2-T15, TASK-M3.2-T16, TASK-M3.2-T17
- **Wave**: 7
- **Files (anticipated)**: `test/integration/team_round_robin_e2e_test.dart`
- **LOC-Budget**: ~100

### Goal

E2E-Integrations-Test: Veranstalter legt 4-Team-Round-Robin (`team_size=3`) an, jedes Team meldet sich mit Roster an, eine Substitution mid-Tournament, Score-Eingabe durch Nicht-Captain, Audit-Trail-Verifikation.

### Acceptance Criteria

- Given Test-Setup mit lokaler Supabase When Test läuft Then alle Steps grün.
- Given Mid-Tournament-Substitution Then alte Slot-Row mit `replaced_at`, neue Slot-Row, Audit-Event in `tournament_audit_events`.
- Given Score-Eingabe durch Nicht-Captain (aber Pool-Mitglied) Then OK.

### Notes

- Falls Test-Setup-Komplexität LOC sprengt: in Test-Helper-Datei auslagern (separater Helper-Task wäre dann aber out-of-scope, T19 nutzt nur bestehende Helper plus 2-3 neue Convenience-Funktionen).

---

# M3.3 — Pool-Phase (Wave 8 bis 11)

## TASK-M3.3-T1: Property-Tests `pool_phase_test.dart`

- **Type**: tests
- **Size**: M
- **Bounded Context**: tournament
- **Agent**: tester
- **Dependencies**: —
- **Wave**: 8
- **Files (anticipated)**: `packages/kubb_domain/test/tournament/pool_phase_test.dart`
- **LOC-Budget**: ~90

### Goal

glados-Property-Tests für `PoolPhaseConfig`-Validierung und `generatePools`-Determinismus über alle drei Grouping-Strategies (snake, random mit Seed, seeded). BYE-Verhalten pro Gruppe.

### Acceptance Criteria

- Given `PoolPhaseConfig(groupCount=4, qualifiersPerGroup=2, snake)` plus 16 Participants Then `generatePools` retourniert 4 Pools à 4 Participants.
- Given `groupCount=0` Then `ArgumentError`.
- Given `qualifiersPerGroup > participantsPerGroup` Then `ArgumentError`.
- Given snake-Strategy, zweimaliger Aufruf mit gleicher Input Then strukturell gleiche Pools (Determinismus).
- Given 14 Participants in 4 Gruppen Then Gruppen-Sizes [4,4,3,3], BYE-Slots in den kürzeren Gruppen (R-M3.3-2).
- Given random-Strategy mit gleichem Seed Then strukturell gleiche Pools.

### Notes

- glados-Generator `Any<PoolPhaseConfig>` einbauen.
- **Contract** für T3: `PoolPhaseConfig`-Felder, `generatePools(List<String>, PoolPhaseConfig) -> List<Pool>`.
- TDD-First: Tests laufen rot bis T3 fertig ist.

---

## TASK-M3.3-T2: Property-Tests `pool_cut_test.dart`

- **Type**: tests
- **Size**: M
- **Bounded Context**: tournament
- **Agent**: tester
- **Dependencies**: —
- **Wave**: 8
- **Files (anticipated)**: `packages/kubb_domain/test/tournament/pool_cut_test.dart`
- **LOC-Budget**: ~90

### Goal

glados-Property-Tests für `selectQualifiers` — Top-N-Determinismus, Cross-Pool-Tiebreaker mit `direct_comparison`-Skip (OD-M3-03), Tie-Resolution-Marker bei vollständigem Tie (OD-M3-05).

### Acceptance Criteria

- Given 4 Standings-Listen à 4 Participants, `top=2` When `selectQualifiers(...)` Then 8 Participants in der Liste.
- Given zwei Cross-Pool-Top-Qualifier mit identischer `totalPoints` plus identischer Buchholz plus identischer Wins Then Result enthält Tie-Marker (`TieResolutionNeeded(participantIds, criterion)`).
- Given `TiebreakerChain` enthält `directComparison`-Stufe When Cross-Pool-Vergleich Then Stufe wird übersprungen, nächste Stufe greift (OD-M3-03).
- Given Determinismus: zweimaliger Aufruf mit gleicher Input Then gleiche Result-Reihenfolge.

### Notes

- **Contract** für T4: `selectQualifiers(List<List<ParticipantStats>>, PoolPhaseConfig, TiebreakerChain) -> CutResult` mit `CutResult.qualifiers` plus `CutResult.tieResolutionNeeded`.

---

## TASK-M3.3-T3: `pool_phase.dart` + `pool_phase_generator.dart`

- **Type**: domain
- **Size**: M
- **Bounded Context**: tournament
- **Agent**: coder-domain
- **Dependencies**: TASK-M3.3-T1
- **Wave**: 9
- **Files (anticipated)**: `packages/kubb_domain/lib/src/tournament/pool_phase.dart`, `packages/kubb_domain/lib/src/tournament/pool_phase_generator.dart`
- **LOC-Budget**: ~100

### Goal

`PoolPhaseConfig`-Value-Object mit Validierung, `generatePools` pure Funktion. Nutzt bestehende `pool.dart` (Round-Robin-Generator) pro Gruppe.

### Acceptance Criteria

- Given Tests aus T1 Then alle grün.
- Given `generatePools(participantIds, config)` Then deterministisches Resultat, BYE-Slots pro Gruppe befüllt.
- Given snake-Grouping Then Standard-Schlangenmuster (S1-G1, S2-G2, ..., Sn-Gn, Sn+1-Gn, ...).
- Given seeded-Grouping Then Pre-existing Seed-Order respektiert.

### Notes

- **Contract** für M3.3-T5 (plpgsql-Spiegelung): Algorithmus muss in plpgsql nachbildbar sein. Recursive-Funktionen vermeiden — iterative Form bevorzugen.

---

## TASK-M3.3-T4: `pool_cut.dart`

- **Type**: domain
- **Size**: S
- **Bounded Context**: tournament
- **Agent**: coder-domain
- **Dependencies**: TASK-M3.3-T2
- **Wave**: 9
- **Files (anticipated)**: `packages/kubb_domain/lib/src/tournament/pool_cut.dart`
- **LOC-Budget**: ~80

### Goal

`selectQualifiers` mit existierender `TiebreakerChain`. `direct_comparison`-Stufe wird Cross-Pool übersprungen (OD-M3-03). Bei vollständigem Tie nach allen Stufen wird `CutResult.tieResolutionNeeded` befüllt (OD-M3-05).

### Acceptance Criteria

- Given Tests aus T2 Then alle grün.
- Given Top-N pro Gruppe ausgewählt, Cross-Pool-Sortierung läuft Then `direct_comparison` wird übersprungen.
- Given vollständiger Tie nach allen Tiebreakern Then `tieResolutionNeeded` enthält die betroffenen `participantId`s.
- Given `CutResult.qualifiers` ist immer korrekt sortiert (Seeding-Reihenfolge).

### Notes

- `TiebreakerChain.skip(TiebreakerStage.directComparison)` als API-Hilfe (kann auch inline-Filter sein).

---

## TASK-M3.3-T5: Migration Pool-Phase Schema + Helper

- **Type**: data
- **Size**: L
- **Bounded Context**: tournament
- **Agent**: coder-data
- **Dependencies**: TASK-M3.3-T3
- **Wave**: 10
- **Files (anticipated)**: `supabase/migrations/20260615000005_tournament_pool_phase.sql`
- **LOC-Budget**: ~100

### Goal

`group_label`-Spalten an `tournament_matches` und `tournament_participants` (nullable text). Helper `_tournament_compute_pools(participants jsonb, config jsonb)` (plpgsql-Spiegelung von `generatePools`). RPC `tournament_start_pool_phase`. Helper `_tournament_compute_pool_cut(p_tournament_id, p_group_label, p_top_n)` retourniert ranking + Marker `TIEBREAKER_NEEDS_RESOLUTION` wenn nötig.

### Acceptance Criteria

- Given Migration When `\d tournament_matches` Then `group_label text` existiert.
- Given Caller-Veranstalter When `tournament_start_pool_phase(id, config)` Then participant-`group_label` gesetzt, `phase='group'` Matches angelegt, `tournaments.status='live'`.
- Given alle Pool-Matches finalized When `_tournament_compute_pool_cut(id, 'A', 2)` Then Top-2 mit `directComparison`-Skip-Logik (OD-M3-03).
- Given vollständiger Tie in einer Gruppe Then Helper-Return enthält Marker (z.B. jsonb `{tie_resolution_needed: true, ...}`).

### Notes

- **Contract**: Helper-Signaturen
  - `_tournament_compute_pools(p_participants jsonb, p_config jsonb) returns jsonb` (Array von `{participant_id, group_label, group_position}`)
  - `_tournament_compute_pool_cut(p_tournament_id uuid, p_group_label text, p_top_n int) returns jsonb` (`{qualifiers: [...], tie_resolution_needed: bool, ...}`)
- Idempotenz-Pattern wie `tournament_start_ko_phase` (M2): `FOR UPDATE` + `ERRCODE 40001` bei Doppelaufruf.

---

## TASK-M3.3-T6: Erweiterung `tournament_start_ko_phase` für Pool-Cut

- **Type**: data
- **Size**: M
- **Bounded Context**: tournament
- **Agent**: coder-data
- **Dependencies**: TASK-M3.3-T5, TASK-M3.3-T4
- **Wave**: 10
- **Files (anticipated)**: `supabase/migrations/20260615000005_start_ko_phase_pool_extend.sql`
- **LOC-Budget**: ~80

### Goal

Wenn Turnier Pool-Matches hat (`EXISTS phase='group'`), ruft `tournament_start_ko_phase` pro Gruppe `_tournament_compute_pool_cut`, mergt zu seeded Bracket-Eingabe via Cross-Pool-Sortierung. Bei `tie_resolution_needed=true` wirft RPC `ERRCODE 'P0001'` mit Message `TIEBREAKER_NEEDS_RESOLUTION` (OD-M3-05) plus jsonb-Payload mit den betroffenen Participants.

### Acceptance Criteria

- Given Turnier ohne Pool-Phase Then RPC verhält sich wie M2 (unverändert).
- Given Turnier mit 4 Gruppen + alle Matches `finalized` Then Top-2 pro Gruppe → 8 Bracket-Seeds, KO-Matches inserted.
- Given Tie in Cross-Pool-Sortierung Then RPC wirft `TIEBREAKER_NEEDS_RESOLUTION` plus JSON `{conflicting_participants: [...]}`.
- Given vorgängige `tournament_resolve_cross_pool_tie(...)`-RPC liefert manuelle Sortierung Then nächster `tournament_start_ko_phase`-Aufruf nutzt die Sortierung.

### Notes

- Resolution-RPC `tournament_resolve_cross_pool_tie(p_tournament_id, p_ordered_participant_ids jsonb)` schreibt in `tournament_seeding_overrides` (M2-Tabelle). Sub-Task-Logik in derselben Migration, da nur ~20 LOC.
- **Contract** für T8 (Port-Method): `resolveCrossPoolTie(...)`.

---

## TASK-M3.3-T7: Property-Parität Dart ↔ plpgsql

- **Type**: tests
- **Size**: M
- **Bounded Context**: tournament
- **Agent**: tester
- **Dependencies**: TASK-M3.3-T5, TASK-M3.3-T3
- **Wave**: 10
- **Files (anticipated)**: `test/integration/pool_parity_test.dart` **oder** `supabase/tests/pool_parity_test.sql`
- **LOC-Budget**: ~100

### Goal

Test-Sweep n ∈ {8, 12, 16, 24, 32} × g ∈ {2, 3, 4, 6, 8} = 25 Kombinationen. Dart `generatePools` und plpgsql `_tournament_compute_pools` liefern strukturell gleiche Pools.

### Acceptance Criteria

- Given alle 25 Kombinationen When Test läuft Then JSON-Vergleich pro Kombi grün.
- Given snake- und seeded-Strategy Then Parität.
- Given random-Strategy mit identischem Seed Then Parität.

### Notes

- Vorbild M2-T5 (Property-Parität für `_tournament_compute_ko_bracket`).
- Bei Drift: T3 oder T5 nachziehen.

---

## TASK-M3.3-T8: Pool-Pfad-Adapter und Port-Methods

- **Type**: data
- **Size**: S
- **Bounded Context**: tournament
- **Agent**: coder-frontend
- **Dependencies**: TASK-M3.3-T5, TASK-M3.3-T6
- **Wave**: 10
- **Files (anticipated)**: `packages/kubb_domain/lib/src/ports/tournament_remote.dart`, `lib/features/tournament/data/supabase_tournament_remote.dart`, `packages/kubb_domain/test/fakes/fake_tournament_remote.dart`
- **LOC-Budget**: ~80

### Goal

Port-Erweiterung um `startPoolPhase`, `getPoolStandings`, `resolveCrossPoolTie`. Supabase- und Fake-Implementationen.

### Acceptance Criteria

- Given Interface-Methode-Signaturen aus `architecture.md` §3.5 Then im Port präsent.
- Given Supabase-Adapter When `startPoolPhase(...)` Then RPC-Aufruf korrekt mit JSON-Config.
- Given `TIEBREAKER_NEEDS_RESOLUTION` Error Then `TieResolutionRequiredException` mit `conflictingParticipants`.
- Given Fake-Adapter simuliert Pool-Generierung deterministisch.

### Notes

- Drei Files erlaubt (Port + Supabase + Fake).
- **Contract** für T10, T11: Method-Signaturen.

---

## TASK-M3.3-T9: Wizard-Erweiterung Pool-Konfig-Step

- **Type**: frontend
- **Size**: M
- **Bounded Context**: tournament
- **Agent**: coder-frontend
- **Dependencies**: TASK-M3.3-T3
- **Wave**: 11
- **Files (anticipated)**: `lib/features/tournament/presentation/widgets/pool_config_step.dart`, `lib/features/tournament/presentation/tournament_setup_wizard.dart` (Patch)
- **LOC-Budget**: ~90

### Goal

Neuer Helper-Widget `_PoolConfigStep` (analog M2-Pattern für `_LeagueStep`/`_KoConfigStep`). Felder: Anzahl Gruppen, Qualifier pro Gruppe, Grouping-Strategie (Dropdown). Sichtbar wenn Format hybrid + `match_format.pool_phase=true` Toggle.

### Acceptance Criteria

- Given Format `round_robin_then_ko` + Toggle `Pool-Phase aktivieren` ON Then Step sichtbar.
- Given Submit-Werte (groups=4, top=2, snake) Then `TournamentConfigDraft.poolPhaseConfig` aktualisiert.
- Given Toggle OFF Then Step versteckt, draft.poolPhaseConfig = null.
- Given invalide Werte (groups=0) Then Validation-Error inline.

### Notes

- Wizard-File-Konflikt-Risiko (siehe Sprint-Plan §Kritische Pfade): Helper-Widget-Auslagerung macht das konfliktfrei.

---

## TASK-M3.3-T10: `tournament_pool_standings_screen.dart`

- **Type**: frontend
- **Size**: M
- **Bounded Context**: tournament
- **Agent**: coder-frontend
- **Dependencies**: TASK-M3.3-T8
- **Wave**: 11
- **Files (anticipated)**: `lib/features/tournament/presentation/tournament_pool_standings_screen.dart`
- **LOC-Budget**: ~100

### Goal

Pool-Standings-View: oben Cross-Pool-Übersicht (Top-N pro Gruppe), darunter ExpansionTile pro Gruppe (kollabierbar, R-M3.3-4-Mitigation), je Tile Standings-Liste mit Rangierung, Sets, Punkte, Buchholz.

### Acceptance Criteria

- Given Pool-Phase aktiv mit 4 Gruppen Then 4 ExpansionTiles, default kollabiert.
- Given Top-N-Cut sichtbar Then Cross-Pool-Übersicht oben mit Highlighting der Qualifier.
- Given Tap auf Gruppe Then expand mit voller Standings-Liste.
- Given Realtime-Updates (Polling) Then refresh alle 5s.

### Notes

- Polling-Pattern aus bestehenden M1/M2-Screens.

---

## TASK-M3.3-T11: Cross-Pool-Tiebreaker-Resolution-Dialog

- **Type**: frontend
- **Size**: M
- **Bounded Context**: tournament
- **Agent**: coder-frontend
- **Dependencies**: TASK-M3.3-T8, TASK-M3.3-T6
- **Wave**: 11
- **Files (anticipated)**: `lib/features/tournament/presentation/widgets/cross_pool_tie_dialog.dart`
- **LOC-Budget**: ~90

### Goal

Wenn `startKoPhase` `TIEBREAKER_NEEDS_RESOLUTION` retourniert (OD-M3-05): Dialog mit den betroffenen Participants als reorderable Liste. Veranstalter sortiert manuell, Submit ruft `resolveCrossPoolTie(...)` und triggert dann `startKoPhase` neu.

### Acceptance Criteria

- Given `TieResolutionRequiredException` von `startKoPhase` Then Dialog öffnet automatisch.
- Given Conflicting-Participants [A,B,C] When Veranstalter sortiert [B,C,A] und Submit Then `resolveCrossPoolTie(...)` mit dieser Reihenfolge.
- Given Resolve OK Then `startKoPhase` automatisch neu, Dialog schliesst, Bracket-View öffnet.
- Given Dialog-Abbruch Then keine RPC-Aufrufe, KO bleibt nicht gestartet.

### Notes

- Reorderable-List via `ReorderableListView` (Flutter Built-in, kein neues Paket).

---

## TASK-M3.3-T12: Detail-Screen Gruppen-Tab + Provider-Patch

- **Type**: frontend
- **Size**: S
- **Bounded Context**: tournament
- **Agent**: coder-frontend
- **Dependencies**: TASK-M3.3-T10
- **Wave**: 11
- **Files (anticipated)**: `lib/features/tournament/presentation/tournament_detail_screen.dart` (Patch), `lib/features/tournament/application/tournament_bracket_provider.dart` (Patch)
- **LOC-Budget**: ~60

### Goal

Tab "Gruppen" sichtbar wenn `tournaments.match_format.pool_phase=true`. Tab rendert `PoolStandingsScreen` inline (oder Sub-Route). `tournament_bracket_provider` lernt zusätzlich Pool-Daten zu laden.

### Acceptance Criteria

- Given Pool-Phase aktiv Then "Gruppen"-Tab sichtbar.
- Given Pool-Phase nicht aktiv Then Tab versteckt.
- Given Provider lädt Pool-Standings Then Daten im State.

### Notes

- M2-Tabs bleiben unangetastet (Bracket, Stats, …).

---

## TASK-M3.3-T13: l10n DE für M3.3-Screens

- **Type**: frontend
- **Size**: S
- **Bounded Context**: tournament
- **Agent**: coder-frontend
- **Dependencies**: TASK-M3.3-T9, TASK-M3.3-T10, TASK-M3.3-T11, TASK-M3.3-T12
- **Wave**: 11
- **Files (anticipated)**: `lib/l10n/app_de.arb`
- **LOC-Budget**: ~50

### Goal

DE-Strings für Pool-Config-Step, Pool-Standings-Screen, Tie-Resolution-Dialog, Gruppen-Tab.

### Acceptance Criteria

- Given Strings referenziert When Generator läuft Then keine Missing-Keys.
- Given DE-Texte ohne Marketing-Wörter.

### Notes

- Konsistente Keys `poolConfig*`, `poolStandings*`, `tieResolve*`.

---

## TASK-M3.3-T14: Integrations-Test 16-Team Pool + KO

- **Type**: tests
- **Size**: L
- **Bounded Context**: tournament
- **Agent**: tester
- **Dependencies**: TASK-M3.3-T9, TASK-M3.3-T10, TASK-M3.3-T11, TASK-M3.3-T12
- **Wave**: 11
- **Files (anticipated)**: `test/integration/pool_phase_ko_e2e_test.dart`
- **LOC-Budget**: ~100

### Goal

E2E-Test: 16-Team-Turnier, 4 Gruppen à 4, alle Pool-Matches gespielt, Top-2 ins KO, Cross-Pool-Tiebreaker greift, KO startet ohne TIE-Block.

### Acceptance Criteria

- Given Test-Setup mit 16 Teams When Test läuft Then alle Schritte grün.
- Given Pool-Phase liefert 8 Qualifier Then Cross-Pool-Seeding ist nach Buchholz sortiert.
- Given KO-Bracket mit 8 Seeds Then 7 KO-Matches angelegt (8→4→2→1) plus optional 3rd-place.

### Notes

- Wenn KO-Bracket nicht relevant: Halt nach `startKoPhase` plus Verifikation der Bracket-Struktur.

---

## TASK-M3.3-T15: Demo-Script M3

- **Type**: docs
- **Size**: S
- **Bounded Context**: core
- **Agent**: coder-docs
- **Dependencies**: TASK-M3.3-T14
- **Wave**: 11
- **Files (anticipated)**: `docs/plans/m3-teams-pools-roster/demo-script.md`
- **LOC-Budget**: ~80

### Goal

Demo-Script für Owner-Abnahme: schrittweiser Ablauf des vollständigen M3-Flows (8 Schritte aus `milestone-plan.md` §"Was nach M3 demobar ist"), Pre-Conditions, erwartete Outputs, Akzeptanz-Checkliste pro Schritt.

### Acceptance Criteria

- Given Script-Datei When gelesen Then 8 Schritte mit klaren Akzeptanzen.
- Given Pre-Conditions sektioniert (Test-DB-Seed, drei Phones).
- Given Demo-Dauer dokumentiert (~45-60 Min).

### Notes

- Vorbild `docs/plans/m2-ko-bracket/demo-script.md`.
