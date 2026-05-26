# ADR-0018: Team-Modell (Domain-Typ, DB-Schema, Mitgliedschafts-Lifecycle)

- **Status**: Accepted
- **Date**: 2026-05-26
- **Depends on**: ADR-0001 (Tech-Stack), ADR-0002 (Bounded Contexts), ADR-0014 (Tournament-Match-Pfad-Trennung)
- **Bezug**: `docs/plans/m3-teams-pools-roster/architecture.md` §3.1–§3.3, `docs/specs/tournament-mode-spec.md` §3.7 FR-TEAM, OD-M3-01, OD-M3-02, OD-M3-04, OD-M3-06

## Context

M3 öffnet den Turniermodus für Teams. Spec §3.7 beschreibt Teams als offene Pools mit unbegrenzten Mitgliedern, gleichberechtigten Captain-Rechten für alle registrierten Mitglieder, einer per-Turnier-Roster-Auswahl und Mid-Tournament-Substitutionen. ADR-0002 hat `team/` bereits als pragmatic-CRUD-Context markiert; M3 zieht diese Entscheidung jetzt scharf und legt das konkrete Datenmodell fest.

Die Spec lässt einige Punkte offen, die für die Implementation entscheidend sind:

1. **Layering-Stil** — `team/` als pragmatic CRUD heisst: kein eigenes Domain-Package, kein Hexagonal, Riverpod-direkt-zu-Supabase. Cross-Context-Verweise nur via `TeamRef`-Value-Object.
2. **Pool-Mitgliedschaft als getrennte Tabelle** vs. JSON-Array in `teams`. Schweizer Liga-Vereine haben bis zu 50 Mitglieder pro Pool — JSON-Array wird unhandlich.
3. **Gast-Spieler ohne Auth-Account** — separate Tabelle oder Spalte in `team_memberships`?
4. **Lifecycle von Mitgliedschaften** — Hard-Delete oder Soft-Delete? Spec FR-TEAM-20 fordert Archiv-Sichtbarkeit aufgelöster Teams, was Soft-Delete impliziert.
5. **Captain-Rechte-Mechanismus** — Datenmodell oder reine RPC-Validierung?

## Decision

Folgende M3-ODs werden mit dieser ADR aufgelöst (alle 2026-05-26 resolved):

- **OD-M3-01** (Captain-Schutz): Option B — Audit-Event plus Inbox-Notification an alle aktiven Pool-Mitglieder bei kritischen Aktionen (Removal, Edit, Dissolve). Kein Voting, kein Cooldown. Siehe §Mitgliedschafts-Lifecycle.
- **OD-M3-02** (Roster-Slot-Anzahl): Option B — Team-Grössen {2, 3, 4, 5, 6} im Wizard, Schema-CHECK `team_size BETWEEN 1 AND 6` bleibt. Siehe §Datenmodell.
- **OD-M3-04** (Reservespieler): Option A für M3 — kein Reserve-Konzept, Roster hat genau `team_size` Slots. `tournament_match_lineups` als M5+ Folge-Ticket.
- **OD-M3-06** (Team-Sieg-Punkte): Option A — Match-Sieg-Punkte (3 / 1 / 0) konsistent zu M1. Set-Tiebreaker bleibt EKC-Score. Konfigurierbarkeit (Option C) bleibt M5+ Liga-Block.

### Layering

`team/` läuft als pragmatic CRUD nach ADR-0002 §2. Konkret:

- Kein Code in `packages/kubb_domain/lib/src/team/` — das Domain-Package bleibt für `team/` leer.
- Wire-Models in `lib/features/team/data/team_models.dart` mit freezed.
- Riverpod-Provider in `lib/features/team/application/` mit direkter Supabase-RPC-Anbindung.
- Value Objects `TeamId`, `TeamMembershipId`, `TeamGuestPlayerId`, `TeamInvitationId` in `packages/kubb_domain/lib/src/values/ids.dart` für Cross-Context-Referenzen aus `tournament/`.
- Kein `TeamRemote`-Port. Wenn Tests einen Fake brauchen, kommt der pragmatisch in `lib/features/team/data/`.

Begründung: Captain-Rechte sind ein Vergleich (`SELECT EXISTS team_memberships WHERE team_id = ? AND user_id = ?`), keine State-Machine. Mitgliedschafts-Lifecycle sind drei Aktionen (join, leave, dissolve), die als RPCs ausreichen. Eine reiche Domain bringt hier keinen Wert.

### Datenmodell

Fünf Tabellen, getrennt nach Verantwortung:

```sql
CREATE TABLE public.teams (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  display_name         text NOT NULL CHECK (length(display_name) BETWEEN 1 AND 60),
  logo_url             text NULL,
  home_club_id         uuid NULL, -- FK to public.clubs (M5+)
  country              text NULL CHECK (country IS NULL OR length(country) = 2),
  league_membership    text NOT NULL DEFAULT 'B' CHECK (league_membership IN ('A','B','C')),
  created_by           uuid NOT NULL REFERENCES auth.users(id) ON DELETE SET DEFAULT,
  dissolved_at         timestamptz NULL,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.team_memberships (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id       uuid NOT NULL REFERENCES public.teams(id) ON DELETE CASCADE,
  user_id       uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  joined_at     timestamptz NOT NULL DEFAULT now(),
  removed_at    timestamptz NULL,
  removed_by    uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT team_memberships_unique_active
    EXCLUDE USING gist (team_id WITH =, user_id WITH =)
    WHERE (removed_at IS NULL)
);

CREATE TABLE public.team_guest_players (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id             uuid NOT NULL REFERENCES public.teams(id) ON DELETE CASCADE,
  display_name        text NOT NULL CHECK (length(display_name) BETWEEN 1 AND 40),
  added_by            uuid NOT NULL REFERENCES auth.users(id) ON DELETE SET DEFAULT,
  added_at            timestamptz NOT NULL DEFAULT now(),
  removed_at          timestamptz NULL,
  claimed_by_user_id  uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL
);

CREATE TABLE public.team_invitations (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id           uuid NOT NULL REFERENCES public.teams(id) ON DELETE CASCADE,
  invitee_user_id   uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  invited_by        uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  state             text NOT NULL DEFAULT 'pending' CHECK (state IN ('pending','accepted','declined','revoked')),
  created_at        timestamptz NOT NULL DEFAULT now(),
  responded_at      timestamptz NULL
);

CREATE TABLE public.team_audit_events (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id         uuid NOT NULL REFERENCES public.teams(id) ON DELETE CASCADE,
  kind            text NOT NULL,
  actor_user_id   uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  payload         jsonb NOT NULL DEFAULT '{}'::jsonb,
  at              timestamptz NOT NULL DEFAULT now()
);
```

Indices: `team_memberships(user_id) WHERE removed_at IS NULL` (für "Meine Teams"), `team_invitations(invitee_user_id, state)` (Inbox-Pull), `team_audit_events(team_id, at DESC)` (Historie).

### Mitgliedschafts-Lifecycle

Vier Aktionen, alle als `SECURITY DEFINER`-RPCs:

1. **Invite** (`team_invite`) — jedes aktive Pool-Mitglied. Inserted `team_invitations` (state=pending) plus Inbox-Eintrag für den Eingeladenen.
2. **Respond** (`team_invitation_respond`) — nur der Invitee. Bei accept: `team_memberships`-Insert, Audit-Event `member_joined`. Bei decline: state=declined.
3. **Remove** (`team_remove_member`) — jedes aktive Pool-Mitglied. Setzt `removed_at` plus `removed_by`. Audit-Event `member_removed` mit optionalem Reason. Inbox-Notification an alle anderen aktiven Pool-Mitglieder (OD-M3-01 Empfehlung B).
4. **Leave** (`team_leave`) — eigene Membership. Setzt `removed_at`. Wenn letztes aktives Mitglied: trigger `team_auto_dissolve` setzt `teams.dissolved_at` (FR-TEAM-19).

Soft-Delete via `removed_at` (FR-TEAM-20). Hard-Delete der Membership-Rows nie. Aufgelöste Teams bleiben sichtbar, ihre `dissolved_at IS NOT NULL` filtert sie aus aktiven Listen.

### Captain-Rechte

Reine RPC-Validierung, kein Datenmodell-Feld. Jede RPC mit Privileg-Anforderung führt zu Beginn aus:

```sql
IF NOT EXISTS (
  SELECT 1 FROM public.team_memberships
  WHERE team_id = p_team_id AND user_id = auth.uid() AND removed_at IS NULL
) THEN
  RAISE EXCEPTION 'NOT_POOL_MEMBER' USING ERRCODE = '42501';
END IF;
```

Gleichberechtigung ist Eigenschaft des Checks selbst — kein Lead-Captain, kein Rollen-Feld. FR-TEAM-5 wörtlich.

### Cross-Context-Brücke zu `tournament/`

`tournament_participants` bekommt eine nullable `team_id`-Spalte (siehe ADR-0019). Roster-Slots verweisen via `member_user_id` auf `team_memberships.user_id` oder via `guest_player_id` auf `team_guest_players.id`. Keine direkten Joins von `tournament_matches` auf `team_memberships`. Cross-Context-Verweis läuft über `TeamRef(TeamId)` als Value Object.

## Alternatives considered

### A) Eigenes Domain-Package `kubb_domain/team/` mit `TeamRemote`-Port

Verworfen. Team-Operationen haben keine reiche Geschäftslogik. Property-Tests wären trivial ("ein Team hat einen Namen"). Hexagonal kostet hier mehr als es bringt. ADR-0002 § Pragmatic-Default ist anwendbar.

### B) JSON-Array von Mitgliedern in `teams.pool_members jsonb`

Verworfen. Pool kann 50+ Mitglieder haben (Vereins-Teams). JSON-Array ohne FK macht Cross-Tournament-Lookups (BR-5) unzumutbar — Trigger müsste JSON deserialisieren. Auch hard für Membership-Audit ohne separate Tabelle.

### C) Einzelne `team_members`-Tabelle für registrierte plus Gäste

Verworfen. `team_memberships.user_id REFERENCES auth.users` kann nicht NULL sein wenn Gäste keinen Auth-Account haben. Eine kombinierte Tabelle mit nullable `user_id` plus `guest_display_name` mischt zwei verschiedene Identitäts-Modelle und erschwert Joins (jeder Join muss nullable `user_id` behandeln). Zwei Tabellen sind sauberer.

### D) Captain-Rolle explizit ("Lead-Captain" plus normale Mitglieder)

Verworfen. FR-TEAM-5 sagt explizit: alle registrierten Mitglieder haben identische Captain-Rechte, kein Lead-Captain. Eine Rolle einzubauen wäre Spec-Verletzung.

### E) Hard-Delete bei Member-Removal

Verworfen. NFR-AUDIT-5 fordert Mitgliedschaftsänderungen protokolliert. Hard-Delete würde Audit-Spur löschen. Soft-Delete via `removed_at` plus Audit-Event ist Standard-Pattern.

## Consequences

### Was einfacher wird

- Membership-CRUD ist mechanisch — fünf RPCs decken den Lifecycle ab.
- Bestehende Inbox-Infrastruktur trägt Team-Einladungen ohne grosse Anpassung.
- Roster-Slots können direkt auf `team_memberships.user_id` und `team_guest_players.id` referenzieren — keine zusätzliche Indirektion.
- Soft-Delete-Pattern erlaubt Archiv-Sichtbarkeit aufgelöster Teams ohne separate History-Tabelle.

### Was teurer wird

- Captain-Aktionen ohne Schutz-Mechanik (OD-M3-01 Empfehlung B nur Audit plus Notification) sind Vertrauens-empfindlich. Wenn Pilot-Phase Missbrauch zeigt, kommt nachträglich C (Voting) als M5-Erweiterung — Aufwand etwa 3 Tage.
- BR-5-Cross-Tournament-Check (ADR-0019) hängt am `team_memberships.user_id`-Lookup. Skaliert bis Tier 1 ohne extra Index, Tier 2 braucht Partial-Index `(member_user_id) WHERE replaced_at IS NULL` auf `tournament_roster_slots`.
- Gäste-Spieler-Identitäts-Claim (FR-TEAM-10) braucht eigenen Migrations-Pfad — kommt M5+, ist mit aktueller Struktur kompatibel (claimed_by_user_id ist schon FK-Stub).

### Nicht-Konsequenzen

- Vereine (FR-CLUB): `home_club_id` ist FK-Stub, bleibt in M3 NULL. Vereins-Modell wird unabhängig modelliert.
- Liga-Wechsel mid-season: `league_membership` ist Init-only in M3. Wechsel-Mechanik kommt M5.
- File-Upload für Logos: `logo_url` ist text. Avatar-Pipeline ist M5+ Polish.
