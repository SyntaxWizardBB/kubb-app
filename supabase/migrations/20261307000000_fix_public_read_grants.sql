-- Schliesst die Luecke zwischen den deklarierten Read-Policies und den
-- fehlenden Supabase-Default-Grants. In dieser DB gehoeren die Tabellen
-- der Rolle `postgres`; deren ALTER-DEFAULT-PRIVILEGES gibt anon/
-- authenticated nur Dxt (kein SELECT). Dadurch sind die korrekt
-- formulierten USING-Policies tot: ein direkter anon/authenticated-Read
-- scheitert mit 42501, bevor RLS ueberhaupt evaluiert wird.
--
-- Fix ist rein additiv: pro Flaeche genau der SELECT-Grant, den die
-- Policy ohnehin gaten wuerde, plus ein gebundener INSERT-Grant fuer den
-- league-admin-Award-Pfad. Keine Policy, Tabelle, Spalte oder Enum wird
-- entfernt oder abgeschwaecht. Anon-Write bleibt ueberall 42501
-- (SELECT-Grant impliziert kein INSERT).
--
-- Zusaetzlich wird v_season_standings auf security_invoker gesetzt: der
-- View gehoert `postgres` (BYPASSRLS=t) und umgeht ohne dieses Flag die
-- RLS der Basis-Tabelle, sodass draft-Standings an anon durchlecken.
-- security_invoker laesst den View als Aufrufer laufen, womit die
-- bestehende season_standings_awards-RLS greift — Single Source of Truth
-- statt dupliziertem Filter.
--
-- Refs: ADR-0040, FR-PUB-9, FR-AUTH-5, FR-SOCIAL-4 (DSGVO Art. 25),
-- FR-POINTS-11, ADR-0023, ADR-0026.


-- ---- 1. teams: blanket public read (FR-PUB-9) ------------------------
-- Policy teams_public_read USING (true) — oeffentliche Team-Suche.

GRANT SELECT ON public.teams TO anon, authenticated;


-- ---- 2. tournaments spectator surface (ADR-0023, Defense-in-Depth) ----
-- Die *_anon_public_read-Policies gaten auf public=true + non-draft.
-- Per ADR-0026 ist das die sekundaere Verteidigungslinie; der Grant
-- macht sie real wirksam gegen direkte PostgREST-/Realtime-Tablezugriffe.

GRANT SELECT ON public.tournaments                    TO anon, authenticated;
GRANT SELECT ON public.tournament_matches             TO anon, authenticated;
GRANT SELECT ON public.tournament_participants        TO anon, authenticated;
GRANT SELECT ON public.tournament_set_score_proposals TO anon, authenticated;

-- 2a. Role-Scoping der authenticated-Read-Policies.
-- Die `*_read`-Policies wurden ohne TO-Klausel angelegt und greifen
-- damit fuer PUBLIC (= auch anon). Ihre Praedikate gaten auf
-- `status <> 'draft'` / `auth.uid()`, NICHT auf das `public`-Flag — sie
-- sind die authenticated-Listen-/Detail-Policies. Solange anon keinen
-- SELECT-Grant hatte, war das folgenlos; mit dem Grant oben wuerden sie
-- anon non-public-Turniere (live, nicht-draft) durchlecken, weil RLS
-- permissive Policies OR-verknuepft. Wir scopen sie auf `authenticated`,
-- sodass anon ausschliesslich ueber die `*_anon_public_read`-Policies
-- (public = true AND non-draft) liest. Die Policies bleiben bestehen,
-- nur ihre Rolle wird auf die tatsaechliche Zielgruppe verengt — keine
-- Abschwaechung des authenticated-Pfads.

DROP POLICY IF EXISTS tournaments_public_read ON public.tournaments;
CREATE POLICY tournaments_public_read
  ON public.tournaments
  FOR SELECT
  TO authenticated
  USING (
    created_by = auth.uid()
    OR (
      status <> 'draft'
      AND (
        invite_only = false
        OR public.tournament_caller_has_active_invitation(tournaments.id)
      )
    )
  );

DROP POLICY IF EXISTS tournament_matches_read ON public.tournament_matches;
CREATE POLICY tournament_matches_read
  ON public.tournament_matches
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
        FROM public.tournaments t
       WHERE t.id = tournament_matches.tournament_id
         AND (t.status <> 'draft' OR t.created_by = auth.uid())
    )
  );

DROP POLICY IF EXISTS tournament_participants_read ON public.tournament_participants;
CREATE POLICY tournament_participants_read
  ON public.tournament_participants
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
        FROM public.tournaments t
       WHERE t.id = tournament_participants.tournament_id
         AND (t.status <> 'draft' OR t.created_by = auth.uid())
    )
  );

DROP POLICY IF EXISTS tournament_participants_self_read ON public.tournament_participants;
CREATE POLICY tournament_participants_self_read
  ON public.tournament_participants
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS tournament_set_score_proposals_read
  ON public.tournament_set_score_proposals;
CREATE POLICY tournament_set_score_proposals_read
  ON public.tournament_set_score_proposals
  FOR SELECT
  TO authenticated
  USING (
    submitter_user_id = auth.uid()
    OR EXISTS (
      SELECT 1
        FROM public.tournament_matches m
        JOIN public.tournaments t ON t.id = m.tournament_id
       WHERE m.id = tournament_set_score_proposals.match_id
         AND (
           t.created_by = auth.uid()
           OR EXISTS (
             SELECT 1
               FROM public.tournament_participants p
              WHERE p.tournament_id = t.id
                AND p.user_id = auth.uid()
                AND p.id = ANY (ARRAY[m.participant_a, m.participant_b])
           )
         )
    )
  );


-- ---- 3. user_profiles visibility-gated read --------------------------
-- Die einzige SELECT-Policy ist TO authenticated; anon bleibt mangels
-- Policy deny (Privacy-by-Default, Spectator-Pfad laeuft ueber public_*
-- RPCs). Der anon-Grant ist bewusst gesetzt, aber harmlos: ohne anon-
-- Policy liefert die Tabelle anon sauber 0 Zeilen statt eines 42501 an
-- der Grant-Schicht — die Deny-Semantik bleibt, wird aber als
-- Policy-Deny (0 rows) statt als Grant-Fehler sichtbar. friendships ist
-- Pflicht-Dependency: der friends_only-Zweig referenziert sie, ohne
-- Grant wirft die Policy permission denied statt sauber zu gaten.

GRANT SELECT ON public.user_profiles TO anon, authenticated;
GRANT SELECT ON public.friendships   TO authenticated;


-- ---- 4. season surface (FR-POINTS-11) --------------------------------
-- Public read auf open/closed; draft bleibt ueber die USING-Policy
-- verborgen. Der INSERT-Grant fuer season_standings_awards ist durch das
-- league_admin-WITH-CHECK gebunden; bewusst KEIN UPDATE/DELETE-Grant,
-- damit der Append-only-Kontrakt (plus T6-Trigger) bestehen bleibt.

GRANT SELECT ON public.seasons                 TO anon, authenticated;
GRANT SELECT ON public.season_tournaments      TO anon, authenticated;
GRANT SELECT ON public.season_standings_awards TO anon, authenticated;
GRANT INSERT ON public.season_standings_awards TO authenticated;


-- ---- 5. Draft-Leak schliessen: v_season_standings als Aufrufer -------
-- Ohne security_invoker laeuft der View als postgres-Owner (BYPASSRLS)
-- und liefert anon draft+open+closed. Mit dem Flag erbt er die RLS des
-- Aufrufers; in Kombination mit dem SELECT-Grant auf der Basis-Tabelle
-- (Schritt 4) sieht anon nur noch open/closed — ueber View und
-- Basis-Tabelle identisch.

ALTER VIEW public.v_season_standings SET (security_invoker = true);

COMMENT ON VIEW public.v_season_standings IS
  'Public-readable season standings aggregate. Laeuft als '
  'security_invoker, damit die season_standings_awards-RLS (status IN '
  '(open, closed)) des Aufrufers greift statt der BYPASSRLS des '
  'postgres-Owners. draft-Standings bleiben anon verborgen.';
