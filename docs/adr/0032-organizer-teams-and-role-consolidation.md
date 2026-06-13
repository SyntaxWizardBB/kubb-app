# ADR-0032: Veranstalterteams & Rollen-Konsolidierung (Berechtigungskonzept)

- **Status**: Proposed
- **Date**: 2026-06-11
- **Bezug**: ProjectPlan.txt „MilestoneBerechtigungskonzept"; ADR-0031 (Veranstalter-
  Dashboard, `tournament_caller_can_manage`, referee-Gate); Club-Schema
  `20260901000012`, Club-RPCs `20260901000013`, Club-Membership-Ops `20260901000016`,
  Early-Access-Gate `20261001000003` (`can_found_clubs`, Code `JH5U-QZ4L`),
  Per-Tournament-Gate `20261201000031` + referee-Ergänzung `20261255000000`.
- **Code-Quelle**: `lib/features/club/` (`clubRoles` in `data/club_models.dart`,
  `club_detail_screen.dart`, `club_add_member_screen.dart`), `tournament_providers.dart`
  (`canManageTournamentClubProvider`, `canAdministerTournamentProvider`,
  `manageableClubsProvider`), `home_screen.dart` (Kachel „Meine Vereine"),
  `my_active_match_provider.dart`.

> **Reines DESIGN-/Entscheid-Dokument.** Legt Rollenmodell, Gates, Rename-Scope und
> Invarianten fest; keine Implementierung/Tests (die materialisiert der Phasen-Plan).

## Kontext & Motivation

Heute existieren **8 Club-Rollen** (owner, admin, member, referee, timemaster, organizer,
scorekeeper, treasurer) — die meisten funktional ungenutzt. Das Konstrukt „Verein" ist in
der Praxis ein **Veranstalterteam** (eine kleine Gruppe, die Turniere organisiert), kein
Mitglieder-Verein. Gebraucht wird: ein **schlankes Rollenmodell**, ein **referee** der
laufende Turniere administriert (aber kein Setup macht), eine **Veranstalter-Kachel** mit
Zugangs-Gate, **Rollenwahl beim Einladen**, und eine **Ongoing-Match-Kachel**.

## Entscheidung

### 1. Rollen-Konsolidierung: 8 → **{owner, admin, referee}**
- **owner** — Ersteller des Teams, alle Rechte.
- **admin** — gleiche Rechte wie owner (Management).
- **referee** — administriert **laufende** Turniere des Teams (Punkte via Override, Zeit/
  Pause/Skip), aber **kein Setup** und **kein** Team-/Mitglieder-Management.
- **Entfernt:** member, timemaster, organizer, scorekeeper, treasurer.
- **Keine neutrale Mitgliedschaft** — wer im Team ist, ist owner/admin/referee.
- **Bestand-Mapping (additiv, kein db reset):** gestrippte Rollen → Fallback **admin**
  (organizer→admin; wenn `roles` nach dem Strippen leer wäre → admin). CHECK-Constraint auf
  das neue Set. Audit-Event je geänderter Mitgliedschaft.

### 2. Rename „Verein" → „Veranstalterteam" (DB + Code + UI)
- Tabellen: `clubs` → `organizer_teams`, `club_memberships` → `team_members`.
- Spalte: `tournaments.club_id` → `tournaments.organizer_team_id` (betrifft Spaß-Turnier-
  Logik `… IS NULL` und das Dashboard-Gate — der Diff muss verhalten-neutral sein).
- Code: `lib/features/club/` → `organizer_team`-Kontext; Bezeichner `Club*`/`clubRoles` →
  `OrganizerTeam*`/`teamRoles`; RPC-Namen `club_*` → `team_*`.
- UI/Strings: „Verein" → „Veranstalterteam"; Kachel „Meine Vereine" → „**Veranstalter**".
- **Rein mechanisch, verhalten-neutral** — eigene, isoliert getestete Phase (höchste
  Blast-Radius; volle Suite + analyze als Gate, keine stille Logik-Änderung).

### 3. Permission-Matrix (server-autoritativ)

| Aktion | Personal-Turnier (kein Team) | Team-Turnier |
|---|---|---|
| Team gründen | — | nur mit `can_found_clubs` (Veranstalter-Legitimierung); Ersteller = owner |
| Team editieren / Mitglieder einladen+Rolle / entfernen / Rollen ändern | — | owner, admin |
| Turnier erstellen | Ersteller | owner, admin |
| **Turnier-Config editieren** (`tournament_update`) | Ersteller | **owner, admin** (referee NEIN — heute läuft update bereits übers Manage-Gate inkl. referee; wird auf das Setup-Gate **verengt**) |
| Publish / Start / Seeding | Ersteller | owner, admin |
| **Live administrieren** (Override, Forfait, Pause/Resume/Skip, Check-in) | Ersteller | owner, admin, **referee** |
| Finalisieren | Ersteller | owner, admin |

**Zwei Gates (Migration spaltet das heutige `tournament_caller_can_manage`):**
- **Setup-Gate** `…_can_setup` = Ersteller **ODER** Team-{owner, admin} → create/update/
  publish/start/seeding.
- **Admin-Gate** `…_can_administer` = Ersteller **ODER** Team-{owner, admin, referee} →
  Override/Forfait/Pause/Resume/Skip/Check-in. (= heutiges Gate inkl. referee.)
- Server bleibt die Sicherheitsgrenze; Client-Provider spiegeln exakt diese zwei Gates.
  `canManageTournamentClubProvider`/`canAdministerTournament` werden vereinheitlicht;
  **referee NICHT im Wizard-Club-Picker** (kein Setup).

### 4. Veranstalter-Kachel
- „Meine Vereine" → „**Veranstalter**". **Sichtbar wenn** `can_found_clubs = true`
  **ODER** owner/admin/referee in irgendeinem Team.
- Ziel: **Veranstalter-Sektion** = Organizer-Dashboard (meine administrierbaren Turniere,
  ADR-0031) **+** meine Veranstalterteams (Mitwirkende).

### 5. Veranstalter-Legitimierung
- Dieser Milestone respektiert **nur das Gate** `can_found_clubs` (gesetzt vom Code
  `JH5U-QZ4L` bei Signup). **Kein** Self-Service-Code-Redeem.
- Die **Admin-Grant-Oberfläche** (User später freischalten) ist Teil des **separaten
  AdminDashBoard-Milestones**, nicht hier.

### 6. Mitglied einladen mit Rolle
- Rolle wird **beim Einladen** gewählt (alle verfügbaren Rollen owner/admin/referee), bei
  Accept gesetzt. Invite-RPC + UI um Rollen-Parameter erweitern.
- **Team-Rollen (member/guest) im 1vs1-/Team-Feature bleiben UNANGETASTET** (separat).

### 7. Ongoing-Match-Kachel (Home-Screen)
- **Neue** Kachel auf dem Home-Screen: zeigt das laufende **Turnier-Match** des Nutzers
  (cross-Turnier), Absprung zum Match. **Ausgeblendet, wenn nichts läuft.**
- Braucht einen **cross-Turnier-Provider** (heute ist `myActiveMatchProvider` per-Turnier).
  Nur Turnier-Matches (kein 1vs1/Casual/Training).
- Die **1vs1-„Match Modus"-Kachel bleibt im Training-Hub** (1vs1 unangetastet). → der
  ProjectPlan-Punkt „MatchModus entfernen" entfällt damit bewusst.

### 8. Events, i18n, Audit
- Invite / Rollenänderung → **Inbox-Event** an den Betroffenen (ADR-0029-Spine).
- Neue **DE-Strings** (Veranstalter, Veranstalterteam, Rollennamen). Audit-Logging der
  Rollen-/Mitgliedschafts-Änderungen beibehalten.

## Migration / Bestand
Additiv, nie `db reset`. Reihenfolge: (a) Rollen-Set-CHECK + Bestand-Remap (→admin); (b)
Gate-Split (Setup/Admin) auf aktuellen Bodies (Stale-Body-Diff!); (c) Tabellen-/Spalten-
Rename verhalten-neutral; (d) Client-Identifier-Rename. Jede CDC-/RLS-relevante Stelle
mitziehen (Publication-Mitgliedschaft der umbenannten Tabellen prüfen).

## Abgrenzung
- **Nicht** die Admin-Grant-UI (Veranstalter freischalten) — separater AdminDashBoard-Milestone.
- **Nicht** die Team-Rollen `member/guest` des 1vs1-/Team-Features.
- Der **Rename ist verhalten-neutral** — keine neue Logik, nur Bezeichner.
- **Nicht** Owner-Transfer/Team-Löschen als neues Feature (nur Aussperr-Schutz: der letzte
  owner kann sich nicht selbst entfernen).

## Offene Punkte (vor/in der Umsetzung)
1. **Rename-Tiefe der RPC-Namen** (`club_*` → `team_*`): viele Client-Call-Sites. Default:
   voll umbenennen (verhalten-neutral), in einer Phase + voller Suite als Gate.
2. **Bestand-Edge:** Zeilen, die NUR `member`/`scorekeeper`/… hatten, werden zu `admin`
   hochgestuft (Über-Vergabe) — bei realem Bestand prüfen; ggf. manuell nachziehen.
3. **`tournament_start` Gate:** als Setup (owner/admin) eingeordnet; falls referee den
   Start auslösen können soll („Zeit managen"), ins Admin-Gate verschieben — am Phasenstart
   bestätigen. Default: Setup.
4. **CDC/RLS nach Rename:** umbenannte Tabellen müssen Publication-Mitgliedschaft + Policies
   behalten (ALTER … RENAME erhält das i.d.R., aber explizit verifizieren).

> Fundament für den Berechtigungskonzept-Milestone. Baut auf ADR-0031 (Gate/Dashboard) auf;
> Phasen-Plan materialisiert die Reihenfolge und die Tests.
