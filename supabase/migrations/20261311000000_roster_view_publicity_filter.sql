-- Roster-View: Publicity-Filter + security_invoker (Owner-Entscheid Option B).
--
-- Befund: public_tournament_roster_view (20260701000002, l.126-138) lief als
-- SECURITY-DEFINER-View (owner=postgres, kein security_invoker) mit direktem
-- anon-SELECT-Grant. Die WHERE filterte nur `replaced_at IS NULL` — kein
-- Bezug zur Sichtbarkeit des zugehoerigen Turniers. Folge: anon las die
-- display_names aller Roster-Slots, auch von draft- und private-Turnieren.
--
-- Fix in zwei Schichten:
--   1. WHERE bindet jeden Slot an sein Turnier und schraenkt auf dieselbe
--      Sichtbarkeits-Menge ein wie die *_anon_public_read-Policies
--      (20260701000002, l.36-89): public = true UND status in der Whitelist.
--   2. security_invoker = true. Die View laeuft damit nicht mehr als owner.
--      Der direkte anon-View-Read scheitert kuenftig an der fehlenden
--      SELECT-Privilege auf tournament_roster_slots — das ist gewollt: der
--      Soll-Pfad ist die SECURITY-DEFINER-RPC public_tournament_get
--      (ADR-0026), deren owner (postgres) die Basis-Tabelle weiterhin liest.
--
-- Projektion UNVERAENDERT (slot_id, participant_id, slot_index, display_name,
-- assigned_at) — kein Breaking Change fuer public_tournament_get, das
-- v.slot_id / v.participant_id / v.slot_index / v.display_name konsumiert.

-- ---- 1. View neu: Projektion gleich, Publicity-Filter ergaenzt -----------

CREATE OR REPLACE VIEW public.public_tournament_roster_view AS
SELECT
  trs.id                                                        AS slot_id,
  trs.participant_id,
  trs.slot_index,
  COALESCE(up.nickname::text, gp.display_name, 'Unbekannt')     AS display_name,
  trs.assigned_at
FROM public.tournament_roster_slots trs
LEFT JOIN public.user_profiles    up ON up.user_id = trs.member_user_id
LEFT JOIN public.team_guest_players gp ON gp.id    = trs.guest_player_id
WHERE trs.replaced_at IS NULL
  AND EXISTS (
    SELECT 1
      FROM public.tournament_participants tp
      JOIN public.tournaments t ON t.id = tp.tournament_id
     WHERE tp.id = trs.participant_id
       AND t.public = true
       AND t.status IN (
         'published',
         'registration_open',
         'registration_closed',
         'live',
         'finalized'
       )
  );


-- ---- 2. Defense-in-Depth: View laeuft als Invoker, nicht als Owner -------

ALTER VIEW public.public_tournament_roster_view
  SET (security_invoker = true);

COMMENT ON VIEW public.public_tournament_roster_view IS
  'Public spectator roster: display_name only, no user_id / email / team_id. '
  'Scoped to public, non-draft tournaments (same visibility set as the '
  '*_anon_public_read policies). Runs security_invoker = true — the anon '
  'read path is the SECURITY DEFINER RPC public_tournament_get (ADR-0026), '
  'not a direct view SELECT. Driven by ADR-0023.';


-- ---- 3. player_ratings: Kommentar-Hygiene (keine RLS-/Grant-Aenderung) ---
--
-- Die disziplin-gebundene RLS wurde durch 20261221000000 aufgeloest: die
-- 'tournament'-ELO ist oeffentlich (anon + authenticated), die 'personal'-ELO
-- nur fuer den Owner und akzeptierte Freunde. Der anon-Grant bleibt gewollt
-- (oeffentliche Tournament-ELO, docs/ELO_RATINGS.md §5). Hier wird NUR der
-- Tabellen-Kommentar an den aktuellen Stand angeglichen — keine Policy, kein
-- Grant, kein Verhalten aendert sich.

COMMENT ON TABLE public.player_ratings IS
  'Persistent per-user ELO (P6_RULES_DECISIONS §I, elo_default=1200). '
  'Discipline-aware read (20261221000000): tournament ELO is public '
  '(anon + authenticated), personal ELO is owner + accepted friends only. '
  'Writes via SECURITY DEFINER RPC only — no INSERT/UPDATE/DELETE policy.';

COMMENT ON POLICY player_ratings_tournament_public ON public.player_ratings IS
  'Tournament ELO is publicly readable (leaderboard / seeding / profile). '
  'anon + authenticated, discipline = ''tournament'' only.';

COMMENT ON POLICY player_ratings_personal_self_or_friends ON public.player_ratings IS
  'Personal ELO is readable by the owner and accepted friends only. '
  'authenticated, discipline = ''personal''; friendships checked in both '
  'canonical orientations with status = ''accepted''.';
