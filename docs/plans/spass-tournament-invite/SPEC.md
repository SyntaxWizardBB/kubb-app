# Spec — Spaßturnier „auf Einladung" (invite-only fun tournament)

Quelle der Wahrheit für die Agent-Pipeline. Branch `feat/spass-tournament-invite`
(ab `main`). Stand 2026-06-10.

## Ziel

Beim Turnier-Setup soll für ein **Spaßturnier** (`tournaments.club_id IS NULL`,
ohne Wertung) eine Option **„Auf Einladung"** erscheinen. Ist sie aktiv, kann der
Ersteller über eine **Spielersuche** Spieler einladen. Eingeladene Spieler
bekommen eine **Inbox-Nachricht** und können sich für **genau dieses** Turnier
**anmelden**.

## Owner-Entscheide (verbindlich)

1. **Sichtbarkeit:** Ein `invite_only`-Turnier erscheint in der öffentlichen
   Turnierliste **nur für eingeladene Spieler** (und den Ersteller). Für alle
   anderen ist es unsichtbar (Liste + Detail).
2. **Anmeldung:** Nimmt ein eingeladener Spieler an, wird er **`pending`** — der
   Ersteller bestätigt final wie bei der normalen Anmeldung (kein Auto-Confirm).
3. Die Option gilt **nur für Spaßturniere** (club_id IS NULL). Die DB-Spalte
   `invite_only` ist generisch, die UI zeigt den Schalter nur bei `clubId == null`.

## Bestehende Muster, die exakt gespiegelt werden

- `public.club_invitations` (`20260901000012`) + `club_invitation_respond`
  (`20260901000013` Z.261) — Tabellen-Shape (state pending/accepted/declined/
  revoked, invited_by, responded_at) und Respond-Gate (invitee-only,
  state='pending').
- `public.user_inbox_messages` (`20260504000011`) — Notification-Spine; Insert
  mit kind/subject/body/action_payload in derselben Transaktion wie die Invitation.
- `friend_search_by_username(p_query)` (`20260507000001`) — sucht ALLE User per
  Nickname-Prefix (≥2 Zeichen, LIMIT 20, schließt Caller + blocked aus) →
  `friendSearchProvider` + Debounce-Suchfeld aus `team_add_player_screen.dart`.
- `tournament_register_single` (`20260525000003`) — Anmelde-RPC (status muss
  `registration_open`, dup-guard, Kapazität→waitlist, setzt `pending`).
- `tournament_update(…, p_setup jsonb)` (`20261201000020`) — liest viele Keys aus
  `p_setup` (location, league_categories, …). **`invite_only` reitet hier mit.**
- `tournament_list_for_caller` (jüngste Def: `20261240000000`) — Discovery-Liste.
- RLS `tournaments_public_read` (`20260525000001`): `status <> 'draft' OR
  created_by = auth.uid()`.

## SERVER (Block S) — additive Migrationen ab `20261270000000`

> Guardrails: nur additive Migrationen; `db reset` VERBOTEN; lokal via
> `docker exec -i supabase_db_kubb-app-local psql -U postgres` out-of-band laden;
> alle Proben in `BEGIN/ROLLBACK`; bei jedem `CREATE OR REPLACE` den **echten
> letzten Body** re-basen (Stale-Body per Diff ausschließen), nur die spezifizierte
> Zeile ändern; Migrationen idempotent (IF NOT EXISTS / DROP POLICY IF EXISTS).

### S1 — `tournaments.invite_only`
`ALTER TABLE public.tournaments ADD COLUMN IF NOT EXISTS invite_only boolean
NOT NULL DEFAULT false`. Kommentar: „nur eingeladene Spieler sehen/registrieren;
relevant v.a. für Spaßturniere (club_id IS NULL)".

### S2 — `tournament_invitations` + Inbox-Kind
- Tabelle `public.tournament_invitations` (Shape wie club_invitations):
  `id uuid pk`, `tournament_id uuid NOT NULL REFERENCES tournaments(id) ON DELETE
  CASCADE`, `invitee_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE
  CASCADE`, `invited_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE`,
  `state text NOT NULL DEFAULT 'pending' CHECK (state IN ('pending','accepted',
  'declined','revoked'))`, `created_at timestamptz NOT NULL DEFAULT now()`,
  `responded_at timestamptz NULL`, `UNIQUE (tournament_id, invitee_user_id)`.
- Index auf `invitee_user_id` (für die Sichtbarkeits-Subquery).
- RLS aktiv: SELECT für `invitee_user_id = auth.uid()` ODER
  `EXISTS (tournaments t WHERE t.id = tournament_id AND t.created_by = auth.uid())`.
  Keine INSERT/UPDATE/DELETE-Policy (Schreibpfad nur SECURITY DEFINER).
- Inbox-Kind: `user_inbox_messages_kind_check` um `'tournament_invitation'`
  erweitern (DROP CONSTRAINT IF EXISTS + ADD, alle bestehenden Werte erhalten).

### S3 — RPCs
Alle `SECURITY DEFINER`, `search_path = public, auth`, GRANT authenticated.

- `tournament_invite_user(p_tournament_id uuid, p_user_id uuid) RETURNS uuid`
  - Gate: `tournament_caller_can_manage(p_tournament_id)` (sonst 42501), Turnier
    muss `invite_only = true` (sonst 22023 'tournament is not invite-only').
  - `p_user_id` muss existierender User sein; Selbst-Einladung verboten (22023).
  - Upsert in `tournament_invitations` (ON CONFLICT (tournament_id, invitee_user_id):
    war state in ('revoked','declined') → zurück auf 'pending' + neue created_at;
    war 'pending'/'accepted' → unverändert/no-op, dieselbe id zurück).
  - Bei neuer/re-aktivierter Einladung: `user_inbox_messages`-Insert kind
    `'tournament_invitation'`, subject/body deutsch, `action_payload =
    {tournament_id, invitation_id, tournament_name}`.
  - Audit-Event `kind='invitation_sent'`. Returns invitation id.
- `tournament_revoke_invitation(p_invitation_id uuid) RETURNS void`
  - Gate manage; state → 'revoked', responded_at = now(). (Entfernt einen evtl.
    schon registrierten Teilnehmer NICHT — bewusst, hält den Pfad einfach.)
- `tournament_invitation_respond(p_invitation_id uuid, p_accept boolean) RETURNS void`
  - Invitee-only (sonst 42501), state muss 'pending' (sonst P0001).
  - decline → state 'declined', responded_at.
  - accept → state 'accepted', responded_at, UND Teilnahme analog
    `tournament_register_single`: Turnier-status muss `registration_open` (sonst
    22023), dup-guard (already registered → 23505), Kapazität→waitlist, Insert
    `tournament_participants(tournament_id, user_id, registration_status)` mit
    `pending`/`waitlist`, Audit `registration_received`. (Owner-Entscheid: pending.)
- `tournament_register_single` — **CREATE OR REPLACE, Body re-basen.** Einzige
  Ergänzung: ist das Turnier `invite_only`, muss der Caller eine Einladung in
  state ('pending','accepted') haben, sonst `42501 'invitation required'`.
  Nicht-invite_only byte-identisch.
- `tournament_update` — **CREATE OR REPLACE, Body re-basen.** Einzige Ergänzung:
  im UPDATE-SET `invite_only = coalesce((v_setup->>'invite_only')::boolean,
  public.tournaments.invite_only)` (bzw. false-Fallback), alles andere byte-genau.
- `tournament_list_for_caller` — **CREATE OR REPLACE, Body re-basen.** WHERE
  erweitern: ein `invite_only`-Turnier nur listen, wenn `t.created_by = v_caller`
  ODER `EXISTS (tournament_invitations i WHERE i.tournament_id = t.id AND
  i.invitee_user_id = v_caller AND i.state <> 'revoked')`. Nicht-invite_only
  unverändert.

### S4 — RLS `tournaments` SELECT
`tournaments_public_read` (DROP POLICY IF EXISTS + CREATE) auf:
`created_by = auth.uid() OR (status <> 'draft' AND (invite_only = false OR
EXISTS (SELECT 1 FROM public.tournament_invitations i WHERE i.tournament_id =
tournaments.id AND i.invitee_user_id = auth.uid() AND i.state <> 'revoked')))`.

### Server-Verifikation (BEGIN/ROLLBACK-Fixtures)
- invite_only-Turnier: Nicht-Eingeladener sieht es weder in list_for_caller noch
  per RLS; Eingeladener + Ersteller sehen es.
- invite → Inbox-Message geschrieben; respond(accept) → participant pending;
  respond(decline) → declined, kein participant; register_single ohne Einladung →
  42501; mit Einladung → pending.
- Re-Invite nach revoke/decline → wieder pending. Nicht-invite_only unverändert.

## CLIENT (Block C) — zweiter Workflow nach Server-Verifikation

- Domain: `InboxMessageKind.tournamentInvitation` (wire `'tournament_invitation'`)
  + Parsing action_payload (tournamentId, invitationId, tournamentName).
- Inbox-UI: Annehmen/Ablehnen-Panel → `tournament_invitation_respond`.
- Repository: `inviteUser`, `respondInvitation`, `revokeInvitation`.
- Wizard `_StepStammdaten`: bei `clubId == null` Schalter „Auf Einladung"
  (`draft.inviteOnly`); aktiv → Debounce-Spielersuche (`friendSearchProvider`) +
  Einladungs-Chips (`draft.invitedUserIds`). Persist: `invite_only` in `p_setup`
  von `tournament_update`; nach create+update je eingeladenem User
  `tournament_invite_user` aufrufen.
- Turnier-Detail: Anmelden-Button bei invite_only nur für Eingeladene (Server-RPC
  erzwingt es ohnehin; UI spiegelt es).
- l10n-Keys (de), `flutter analyze` clean, gezielte Tests (Draft-Logik,
  Inbox-Parsing, Mapping). Design-System (KubbTokens) einhalten.
