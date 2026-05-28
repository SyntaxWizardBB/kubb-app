-- W3-T3 (Sprint-A): Anon-Policy-Cleanup nach ADR-0026 Strategie A.
--
-- Die in `20260701000002_tournaments_public_flag.sql` deklarierten
-- `*_anon_public_read`-Policies (`tournaments`, `tournament_matches`,
-- `tournament_participants`, `tournament_set_score_proposals`) bleiben
-- bestehen als Defense-in-Depth. Der regulaere anon-Read-Pfad laeuft ab
-- Wave 3 ueber die neuen `public_*_get`-RPCs (siehe Migration
-- 20260901000001); die Tabellen-Policies fangen nur noch direkte
-- PostgREST-Tablezugriffe (Mis-Konfiguration, Realtime-Channel-Leak) ab.
--
-- Diese Migration:
--   1. Aktualisiert die Policy-COMMENTs so, dass die geaenderte Rolle
--      ("Sekundaer-Schutz") aus dem Schema-Browse hervorgeht.
--   2. Reasserted REVOKE WRITE auf `tournaments` fuer `anon` als
--      expliziten Audit-Anker (RLS deny-by-default macht es ohnehin
--      bereits unmoeglich, der explizite REVOKE dokumentiert die
--      Absicht).
--   3. Reasserted den GRANT SELECT auf `public_tournament_roster_view`
--      idempotent (bereits in T1-Migration vergeben; hier nur fuer
--      Re-Migrate-Sicherheit).
--
-- Sources: ADR-0026 §"Tabellen-Policies vereinheitlicht",
--          docs/plans/sprint-a-bug-fix/anon-rls-plan.md T2.


-- ---- 1. COMMENT-Updates auf den vier Defense-in-Depth-Policies -------

COMMENT ON POLICY tournaments_anon_public_read
  ON public.tournaments IS
  'Defense-in-depth: anon-SELECT auf tournaments. Der primaere '
  'Spectator-Read-Pfad laeuft seit ADR-0026 ueber die RPC '
  'public_tournament_get; diese Policy schuetzt nur noch direkte '
  'PostgREST-Tablezugriffe (z.B. Realtime-Channel-Mis-Konfiguration).';

COMMENT ON POLICY tournament_matches_anon_public_read
  ON public.tournament_matches IS
  'Defense-in-depth: anon-SELECT auf tournament_matches. Primaerer '
  'Pfad ueber RPC public_tournament_get / public_tournament_match_get '
  'seit ADR-0026.';

COMMENT ON POLICY tournament_participants_anon_public_read
  ON public.tournament_participants IS
  'Defense-in-depth: anon-SELECT auf tournament_participants. Primaerer '
  'Pfad ueber RPC public_tournament_get (Roster kommt ueber die '
  'public_tournament_roster_view, NICHT ueber diese Tabelle) seit '
  'ADR-0026.';

COMMENT ON POLICY tournament_set_score_proposals_anon_public_read
  ON public.tournament_set_score_proposals IS
  'Defense-in-depth: anon-SELECT auf tournament_set_score_proposals. '
  'Die Public-RPCs liefern bewusst KEINE Proposals an anon-Spectator '
  '(ADR-0026 §Decision §2). Policy bleibt nur fuer direkte '
  'PostgREST-Tablezugriffe.';


-- ---- 2. Explizite WRITE-REVOKEs auf tournaments fuer anon ------------
--
-- RLS deny-by-default verbietet INSERT/UPDATE/DELETE bereits ohne eine
-- entsprechende Policy. Der explizite REVOKE ist ein Audit-Anker im
-- Schema-Dump: das Fehlen einer Policy beweist die Absicht weniger
-- offensichtlich als ein explizites REVOKE.

REVOKE INSERT, UPDATE, DELETE ON public.tournaments FROM anon;


-- ---- 3. Idempotenter GRANT auf die Roster-View -----------------------

GRANT SELECT ON public.public_tournament_roster_view TO anon, authenticated;
