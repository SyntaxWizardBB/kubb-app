-- Tournament feature — P6 D2a: Shoot-Out tiebreak SERVER logic.
--
-- The shoot-out is the *last* preliminary-phase tiebreak stage
-- (docs/P6_SHOOTOUT_TIEBREAK.md, P6_RULES_DECISIONS §H). It only settles
-- QUALIFICATION-RELEVANT ties: maximal runs of participants who are exactly
-- equal on every configured regular tiebreak criterion AND whose relative
-- order decides who qualifies (the run straddles the cut line). Cosmetic
-- ties — entirely above the cut (all already in) or entirely below it (all
-- already out) — never trigger a shoot-out. The recorded result is only
-- "which side won": a simple winner-ordering confirmed by team consensus,
-- replacing the arbitrary participant_id fallback for that group.
--
-- This file is the server mirror of the pure-Dart domain in
-- packages/kubb_domain/lib/src/tournament/shootout.dart:
--   * _tournament_detect_shootout_groups  ~= detectShootoutGroups (L169-207)
--       - maximal consecutive runs equal on every SERVER-RESOLVABLE gated
--         criterion (see the "tied" caveat below), via tiebreaker_order,
--       - straddle-cut condition i < q AND j >= q,
--       - q<=0 OR q>=N => no groups.
--
-- "tied" CAVEAT (NOT a full mirror of _allCriteriaEqualForShootout):
-- The Dart _allCriteriaEqualForShootout (L304-313) walks the WHOLE
-- TiebreakerChain via chain.compareCriterion, i.e. every configured
-- criterion including buchholz_minus_h2h / direct_comparison. This server
-- detector only evaluates the criteria that are resolvable from persisted
-- match stats — total_points / wins / kubb_difference — exactly like the
-- existing tournament_pool_standings / _tournament_compute_pool_cut helper
-- ("gegated wie in tournament_pool_standings"). buchholz_* and
-- direct_comparison are NOT gated into the server "tied" key. Consequence:
-- for tiebreaker_order presets that contain buchholz/direct_comparison (e.g.
-- swiss), two teams the Dart chain WOULD separate on those criteria may be
-- treated as "tied" server-side and thus flagged shoot-out-relevant. For the
-- round_robin_default preset (total_points / kubb_difference only) the server
-- and Dart "tied" notions coincide. This is the same documented limitation
-- the pool-cut helper carries; resolving the extra criteria server-side is
-- deferred until that shared helper grows them.
--   * the resolution applied in tournament_start_ko_phase
--       == resolveWithShootouts (L256-283): resolved groups re-ordered by
--          ordered_winners, pending groups keep the chain order and BLOCK
--          (no silent participant_id fallback).
--   * ordered_winners is a full permutation of tied_participant_ids
--       (ShootoutResult invariant, L53-63).
--
-- Tiebreak gating matches tournament_pool_standings / _tournament_compute_
-- pool_cut: the SQL ranking supports total_points / wins / kubb_difference,
-- each active only when present in tournaments.tiebreaker_order. This is
-- exactly the set of regular criteria the server can resolve from stats;
-- mighty_finisher_shootout / random / buchholz_* are out-of-band or
-- swiss-specific and intentionally not part of the "tied" key here, in
-- lockstep with the existing pool-cut helper and the Dart chain's neutral
-- mightyFinisherShootout comparator.
--
-- Deterministic: no wall clock, no unseeded randomness in any ordering.
--
-- ============================ DEPENDENCIES ============================
-- Tables read:
--   * public.tournaments(id, created_by, tiebreaker_order, display_name)
--   * public.tournament_participants(id, tournament_id, user_id, team_id,
--                                    registration_status, registered_at)
--   * public.tournament_matches(... phase='group', finalized/overridden)
--   * public.tournament_roster_slots(participant_id, member_user_id,
--                                    replaced_at)
-- Tables written:
--   * public.tournament_shootouts (NEW, this file)
--   * public.user_inbox_messages (via _tournament_notify_participants-style
--     direct insert; kind 'tournament_round' — already in the CHECK)
--   * public.tournament_audit_events
-- Function re-stated verbatim + extended:
--   * public.tournament_start_ko_phase(uuid, jsonb)
--       latest body: 20261201000032_tournament_per_tournament_manage_gate.sql
--       §12 (per-tournament manage gate via tournament_caller_can_manage).
--       The seeding/insert logic is identical to the earlier
--       20261201000010 §5 body; only the auth gate is the 000032 one.
-- =====================================================================


-- ====================================================================
-- 1. Table: tournament_shootouts
-- ====================================================================
-- One row per detected qualification-relevant tie group.
--   * tied_participant_ids : the unordered tied set (ShootoutGroup.participantIds
--       in pre-shoot-out chain order). uuid[].
--   * start_rank           : zero-based rank of the first member in the overall
--       ranking (ShootoutGroup.startRank).
--   * ordered_winners      : the resolved best->worst permutation of
--       tied_participant_ids. NULL/empty while pending (ShootoutResult).
--   * reported_by / reported_at      : first side to submit a winner ordering.
--   * confirmed_by / confirmed_at    : the opposing side that confirms it.
--       Mirrors the match consensus two-sided pattern: a result is RESOLVED
--       only once both a report and a matching confirmation from a DIFFERENT
--       involved side exist (ordered_winners then set).
--   * status               : 'pending' | 'reported' | 'resolved' (derived,
--       persisted for cheap querying / the gate).

-- Immutable key from an unordered uuid set: sorts then joins. Used as the
-- generated tie_key so a tie group is identified independent of insertion
-- order (detection idempotency).
CREATE OR REPLACE FUNCTION public._tournament_uuid_set_key(p_ids uuid[])
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT array_to_string(
           ARRAY(SELECT x::text FROM unnest(p_ids) AS x ORDER BY x::text), ',');
$$;
REVOKE ALL ON FUNCTION public._tournament_uuid_set_key(uuid[]) FROM PUBLIC;

CREATE TABLE IF NOT EXISTS public.tournament_shootouts (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tournament_id        uuid NOT NULL
                         REFERENCES public.tournaments(id) ON DELETE CASCADE,
  start_rank           int NOT NULL CHECK (start_rank >= 0),
  tied_participant_ids uuid[] NOT NULL
                         CHECK (array_length(tied_participant_ids, 1) >= 2),
  ordered_winners      uuid[] NULL,
  status               text NOT NULL DEFAULT 'pending'
                         CHECK (status IN ('pending','reported','resolved')),
  reported_by          uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  reported_at          timestamptz NULL,
  confirmed_by         uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  confirmed_at         timestamptz NULL,
  created_at           timestamptz NOT NULL DEFAULT now(),
  -- One shoot-out row per (tournament, tie group). The tie group is uniquely
  -- identified by its sorted participant set; we materialise that as a
  -- normalised key so detection is idempotent (re-detect = no duplicate).
  tie_key              text GENERATED ALWAYS AS (
                         public._tournament_uuid_set_key(tied_participant_ids)
                       ) STORED,
  CONSTRAINT tournament_shootouts_unique_group UNIQUE (tournament_id, tie_key)
);

CREATE INDEX IF NOT EXISTS tournament_shootouts_tournament_idx
  ON public.tournament_shootouts(tournament_id);


-- ====================================================================
-- 2. RLS — analog to tournament_seeding_overrides (20260601000011).
-- ====================================================================
-- Read: organizer (created_by) OR any registered participant of the
-- tournament. Write: organizer only via direct policy; all participant-
-- driven mutations flow through the SECURITY DEFINER consensus RPCs below,
-- which bypass RLS. authenticated has no unrestricted table write.

ALTER TABLE public.tournament_shootouts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS tournament_shootouts_read
  ON public.tournament_shootouts;
CREATE POLICY tournament_shootouts_read
  ON public.tournament_shootouts FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.tournaments t
       WHERE t.id = tournament_shootouts.tournament_id
         AND (t.created_by = auth.uid() OR t.status <> 'draft')
    )
    OR EXISTS (
      SELECT 1 FROM public.tournament_participants p
       WHERE p.tournament_id = tournament_shootouts.tournament_id
         AND p.user_id       = auth.uid()
    )
  );

DROP POLICY IF EXISTS tournament_shootouts_organizer_write
  ON public.tournament_shootouts;
CREATE POLICY tournament_shootouts_organizer_write
  ON public.tournament_shootouts FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.tournaments t
       WHERE t.id = tournament_shootouts.tournament_id
         AND t.created_by = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.tournaments t
       WHERE t.id = tournament_shootouts.tournament_id
         AND t.created_by = auth.uid()
    )
  );


-- ====================================================================
-- 3. Helper: _tournament_detect_shootout_groups
-- ====================================================================
-- Pure detection. Returns one row per qualification-relevant tie group:
-- (start_rank, participant_ids[]). Mirrors detectShootoutGroups for the
-- server-resolvable criteria (see the "tied" CAVEAT in the file header):
-- total_points / wins / kubb_difference gated via tiebreaker_order, like
-- pool_standings — NOT the full chain (buchholz/direct_comparison excluded).
--
-- Ranking model: chain-gated stats over ALL group-phase matches of the
-- tournament (the flat standings ranking detectShootoutGroups operates on).
-- Per-group pool tournaments still ultimately qualify off the same per-
-- participant criteria; the straddle-cut detection is performed on the
-- canonical chain-ordered ranking so the "tied" notion is identical to the
-- Dart chain (tiebreaker_order-gated total_points / wins / kubb_difference,
-- deterministic registered_at/id tail only as the LAST resort — which the
-- detector explicitly does NOT treat as separating).

CREATE OR REPLACE FUNCTION public._tournament_detect_shootout_groups(
  p_tournament_id   uuid,
  p_qualifier_count int
)
RETURNS TABLE (start_rank int, participant_ids uuid[])
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_chain text[];
  v_n     int;
BEGIN
  SELECT tiebreaker_order INTO v_chain
    FROM public.tournaments
   WHERE id = p_tournament_id;
  IF v_chain IS NULL THEN
    RAISE EXCEPTION 'tournament not found: %', p_tournament_id
      USING ERRCODE = 'P0002';
  END IF;

  -- detectShootoutGroups L175-179: q<=0 or q>=N => no qualification-relevant
  -- tie possible (no meaningful cut line).
  SELECT count(*) INTO v_n
    FROM public.tournament_participants
   WHERE tournament_id = p_tournament_id
     AND registration_status = 'confirmed';

  IF p_qualifier_count <= 0 OR p_qualifier_count >= v_n THEN
    RETURN;  -- empty result set
  END IF;

  RETURN QUERY
  WITH stats AS (
    SELECT p.id AS pid,
           p.registered_at,
           coalesce(sum(CASE WHEN m.winner_participant = p.id THEN 1 ELSE 0 END), 0) AS wins,
           coalesce(sum(
             CASE WHEN m.participant_a = p.id THEN coalesce(m.final_score_a,0)
                  WHEN m.participant_b = p.id THEN coalesce(m.final_score_b,0)
                  ELSE 0 END), 0) AS total_points,
           coalesce(sum(
             CASE WHEN m.participant_a = p.id
                    THEN coalesce(m.final_score_a,0) - coalesce(m.final_score_b,0)
                  WHEN m.participant_b = p.id
                    THEN coalesce(m.final_score_b,0) - coalesce(m.final_score_a,0)
                  ELSE 0 END), 0) AS kubb_diff
      FROM public.tournament_participants p
      LEFT JOIN public.tournament_matches m
        ON m.tournament_id = p.tournament_id
       AND m.phase         = 'group'
       AND m.status        IN ('finalized','overridden')
       AND (m.participant_a = p.id OR m.participant_b = p.id)
     WHERE p.tournament_id      = p_tournament_id
       AND p.registration_status = 'confirmed'
     GROUP BY p.id, p.registered_at
  ),
  ranked AS (
    -- Chain-ordered ranking. Gated keys mirror tournament_pool_standings /
    -- _tournament_compute_pool_cut so the order matches the qualifier
    -- selection. registered_at/pid form the deterministic ID-fallback tail
    -- (NOT a separating criterion).
    SELECT s.pid,
           s.total_points, s.wins, s.kubb_diff,
           -- Chain-gated "criteria fingerprint": two rows are TIED iff their
           -- fingerprints match (_allCriteriaEqualForShootout). Only criteria
           -- present in tiebreaker_order contribute; others collapse to 0.
           (CASE WHEN 'total_points'    = ANY(v_chain) THEN s.total_points ELSE 0 END)::text
             || '|' ||
           (CASE WHEN 'wins'            = ANY(v_chain) THEN s.wins         ELSE 0 END)::text
             || '|' ||
           (CASE WHEN 'kubb_difference' = ANY(v_chain) THEN s.kubb_diff    ELSE 0 END)::text
             AS tie_fp,
           row_number() OVER (
             ORDER BY
               CASE WHEN 'total_points'    = ANY(v_chain) THEN -s.total_points ELSE 0 END,
               CASE WHEN 'wins'            = ANY(v_chain) THEN -s.wins         ELSE 0 END,
               CASE WHEN 'kubb_difference' = ANY(v_chain) THEN -s.kubb_diff    ELSE 0 END,
               s.registered_at ASC,
               s.pid ASC
           ) - 1 AS rnk0          -- zero-based rank
      FROM stats s
  ),
  -- Maximal runs of consecutive equal-fingerprint rows. A "run id" is the
  -- rank at which a new fingerprint starts (gaps-and-islands).
  marked AS (
    SELECT r.*,
           CASE WHEN lag(r.tie_fp) OVER (ORDER BY r.rnk0) IS DISTINCT FROM r.tie_fp
                THEN 1 ELSE 0 END AS is_new_run
      FROM ranked r
  ),
  runs AS (
    SELECT m.*,
           sum(m.is_new_run) OVER (ORDER BY m.rnk0) AS run_id
      FROM marked m
  ),
  grouped AS (
    SELECT run_id,
           min(rnk0)                                  AS first_rank,
           max(rnk0)                                  AS last_rank,
           count(*)                                   AS cnt,
           array_agg(pid ORDER BY rnk0)               AS pids
      FROM runs
     GROUP BY run_id
  )
  -- detectShootoutGroups L188-200: only runs of length >= 2 that STRADDLE
  -- the cut line (first < q AND last >= q).
  SELECT g.first_rank::int AS start_rank,
         g.pids            AS participant_ids
    FROM grouped g
   WHERE g.cnt > 1
     AND g.first_rank <  p_qualifier_count
     AND g.last_rank  >= p_qualifier_count
   ORDER BY g.first_rank;
END;
$$;

REVOKE ALL ON FUNCTION public._tournament_detect_shootout_groups(uuid, int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._tournament_detect_shootout_groups(uuid, int) TO authenticated;

COMMENT ON FUNCTION public._tournament_detect_shootout_groups(uuid, int) IS
  'Mirror of shootout.dart detectShootoutGroups for the server-resolvable '
  'criteria: maximal consecutive runs of participants tied on every '
  'tiebreaker_order-gated, stats-resolvable criterion (total_points / wins / '
  'kubb_difference, like pool_standings) that straddle the cut line '
  '(first<q AND last>=q). q<=0 OR q>=N => empty. buchholz/direct_comparison '
  'are NOT evaluated (same limitation as the pool-cut helper), so it is not '
  'the full _allCriteriaEqualForShootout chain. Deterministic. SECURITY DEFINER.';


-- ====================================================================
-- 4. Helper: _tournament_shootout_user_in_group
-- ====================================================================
-- True when p_user is a registered app-user behind ANY participant in the
-- given tie group (solo user_id OR open team roster member). Used to gate
-- the consensus RPCs to involved teams only.

CREATE OR REPLACE FUNCTION public._tournament_shootout_user_in_group(
  p_tournament_id uuid,
  p_tied          uuid[],
  p_user          uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
  SELECT EXISTS (
    -- Solo participants.
    SELECT 1
      FROM public.tournament_participants p
     WHERE p.tournament_id = p_tournament_id
       AND p.id = ANY(p_tied)
       AND p.user_id = p_user
    UNION ALL
    -- Team participants: open roster members.
    SELECT 1
      FROM public.tournament_participants p
      JOIN public.tournament_roster_slots s
        ON s.participant_id = p.id
     WHERE p.tournament_id = p_tournament_id
       AND p.id = ANY(p_tied)
       AND p.team_id IS NOT NULL
       AND s.replaced_at IS NULL
       AND s.member_user_id = p_user
  );
$$;

REVOKE ALL ON FUNCTION public._tournament_shootout_user_in_group(uuid, uuid[], uuid) FROM PUBLIC;


-- ====================================================================
-- 5. Helper: _tournament_notify_shootout_group
-- ====================================================================
-- Fan-out one inbox row per distinct app-user behind the tie group's
-- participants. Same recipient resolution as
-- _tournament_notify_participants (20261201000010 §1) but scoped to the
-- group. Uses the existing 'tournament_round' kind (already in the inbox
-- kind CHECK) — a shoot-out is a new on-site task for the involved teams.

CREATE OR REPLACE FUNCTION public._tournament_notify_shootout_group(
  p_tournament_id uuid,
  p_tied          uuid[],
  p_subject       text,
  p_body          text,
  p_payload       jsonb DEFAULT NULL
)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_inserted int := 0;
BEGIN
  WITH recipients AS (
    SELECT p.user_id AS user_id
      FROM public.tournament_participants p
     WHERE p.tournament_id = p_tournament_id
       AND p.id = ANY(p_tied)
       AND p.user_id IS NOT NULL
    UNION
    SELECT s.member_user_id AS user_id
      FROM public.tournament_participants p
      JOIN public.tournament_roster_slots s
        ON s.participant_id = p.id
     WHERE p.tournament_id = p_tournament_id
       AND p.id = ANY(p_tied)
       AND p.team_id IS NOT NULL
       AND s.replaced_at IS NULL
       AND s.member_user_id IS NOT NULL
  ),
  ins AS (
    INSERT INTO public.user_inbox_messages(
        user_id, kind, subject, body, action_payload)
    SELECT DISTINCT r.user_id, 'tournament_round', p_subject, p_body, p_payload
      FROM recipients r
     WHERE r.user_id IS NOT NULL
    RETURNING 1
  )
  SELECT count(*) INTO v_inserted FROM ins;

  RETURN v_inserted;
END;
$$;

REVOKE ALL ON FUNCTION public._tournament_notify_shootout_group(uuid, uuid[], text, text, jsonb) FROM PUBLIC;


-- ====================================================================
-- 6. RPC: tournament_detect_shootouts  (organizer-triggered detection)
-- ====================================================================
-- Detects qualification-relevant tie groups for the given qualifier_count
-- and materialises one tournament_shootouts row per group (idempotent via
-- the tie_key unique constraint) plus an inbox notification to each group.
-- Organizer-only. Returns the detected groups. tournament_start_ko_phase
-- calls the detection inline too (the gate), but exposing it as an RPC lets
-- the client surface pending shoot-outs before attempting the KO start.

CREATE OR REPLACE FUNCTION public.tournament_detect_shootouts(
  p_tournament_id   uuid,
  p_qualifier_count int
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller   uuid;
  v_creator  uuid;
  v_name     text;
  v_grp      record;
  v_created  int := 0;
  v_groups   jsonb := '[]'::jsonb;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  SELECT created_by, display_name INTO v_creator, v_name
    FROM public.tournaments
   WHERE id = p_tournament_id
   FOR UPDATE;

  -- PER-TOURNAMENT manage gate (20261201000032 §12): creator OR
  -- owner/admin/organizer of the club_id, same as tournament_start_ko_phase.
  IF v_creator IS NULL
     OR NOT public.tournament_caller_can_manage(p_tournament_id) THEN
    RAISE EXCEPTION 'NOT_ORGANIZER: tournament not found or not authorised'
      USING ERRCODE = '42501';
  END IF;

  FOR v_grp IN
    SELECT * FROM public._tournament_detect_shootout_groups(
                     p_tournament_id, p_qualifier_count)
  LOOP
    INSERT INTO public.tournament_shootouts(
        tournament_id, start_rank, tied_participant_ids)
      VALUES (p_tournament_id, v_grp.start_rank, v_grp.participant_ids)
      ON CONFLICT (tournament_id, tie_key) DO NOTHING;

    IF FOUND THEN
      v_created := v_created + 1;
      PERFORM public._tournament_notify_shootout_group(
        p_tournament_id,
        v_grp.participant_ids,
        'Shoot-Out nötig',
        'Turnier "' || coalesce(v_name, '')
          || '": Gleichstand an der Qualifikations-Grenze — tragt den '
          || 'Shoot-Out-Sieger ein.',
        jsonb_build_object(
          'tournament_id', p_tournament_id,
          'kind',          'shootout',
          'start_rank',    v_grp.start_rank,
          'tied',          to_jsonb(v_grp.participant_ids)));
    END IF;

    v_groups := v_groups || jsonb_build_object(
      'start_rank', v_grp.start_rank,
      'tied',       to_jsonb(v_grp.participant_ids));
  END LOOP;

  INSERT INTO public.tournament_audit_events(
      tournament_id, kind, actor_user_id, payload)
    VALUES (
      p_tournament_id,
      'shootouts_detected',
      v_caller,
      jsonb_build_object(
        'qualifier_count', p_qualifier_count,
        'created',         v_created,
        'groups',          v_groups));

  RETURN jsonb_build_object(
    'tournament_id', p_tournament_id,
    'created',       v_created,
    'groups',        v_groups);
END;
$$;

REVOKE ALL ON FUNCTION public.tournament_detect_shootouts(uuid, int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.tournament_detect_shootouts(uuid, int) TO authenticated;

COMMENT ON FUNCTION public.tournament_detect_shootouts(uuid, int) IS
  'Organizer-triggered shoot-out detection: materialises one '
  'tournament_shootouts row per qualification-relevant straddle-cut tie '
  'group (idempotent) and notifies the involved teams. Mirrors '
  'detectShootoutGroups for the server-resolvable criteria (see '
  '_tournament_detect_shootout_groups COMMENT). SECURITY DEFINER, '
  'per-tournament manage-gated.';


-- ====================================================================
-- 7. Consensus RPCs: report + confirm shoot-out winners
-- ====================================================================
-- Reuses the match consensus two-sided pattern (tournament_propose_set_scores):
--   * tournament_report_shootout_winners(shootout_id, ordered_winners[])
--       — an INVOLVED team submits the winner ordering. Stores it as a
--         pending report (status='reported', reported_by=caller). A later
--         submission by an involved user overwrites the report and resets
--         confirmation (the two sides must agree on the SAME ordering).
--   * tournament_confirm_shootout(shootout_id, ordered_winners[])
--       — a DIFFERENT involved team confirms the reported ordering. Once a
--         confirmation from a distinct involved user matches the report, the
--         shoot-out is RESOLVED (ordered_winners set, status='resolved').
-- Both gate on auth.uid() being an involved team; non-involved callers get
-- NOT_AUTHORISED / 42501.

CREATE OR REPLACE FUNCTION public._tournament_validate_shootout_order(
  p_tied    uuid[],
  p_ordered uuid[]
)
RETURNS void
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  -- ShootoutResult invariant: ordered_winners must be a full permutation of
  -- tied_participant_ids (same length, no dupes, same set).
  IF p_ordered IS NULL
     OR array_length(p_ordered, 1) IS DISTINCT FROM array_length(p_tied, 1) THEN
    RAISE EXCEPTION 'INVALID_ORDER: ordered_winners must cover all tied participants'
      USING ERRCODE = '22023';
  END IF;
  IF EXISTS (
        SELECT 1 FROM (SELECT unnest(p_ordered) AS x) q
        GROUP BY x HAVING count(*) > 1) THEN
    RAISE EXCEPTION 'INVALID_ORDER: ordered_winners must not contain duplicates'
      USING ERRCODE = '22023';
  END IF;
  IF EXISTS (SELECT unnest(p_ordered) EXCEPT SELECT unnest(p_tied))
     OR EXISTS (SELECT unnest(p_tied) EXCEPT SELECT unnest(p_ordered)) THEN
    RAISE EXCEPTION 'INVALID_ORDER: ordered_winners must be a permutation of the tied set'
      USING ERRCODE = '22023';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public._tournament_validate_shootout_order(uuid[], uuid[]) FROM PUBLIC;


CREATE OR REPLACE FUNCTION public.tournament_report_shootout_winners(
  p_shootout_id     uuid,
  p_ordered_winners uuid[]
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller    uuid;
  v_tid       uuid;
  v_tied      uuid[];
  v_status    text;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  SELECT tournament_id, tied_participant_ids, status
    INTO v_tid, v_tied, v_status
    FROM public.tournament_shootouts
   WHERE id = p_shootout_id
   FOR UPDATE;

  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'shoot-out not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_status = 'resolved' THEN
    RAISE EXCEPTION 'ALREADY_RESOLVED: shoot-out already resolved'
      USING ERRCODE = '22023';
  END IF;

  IF NOT public._tournament_shootout_user_in_group(v_tid, v_tied, v_caller) THEN
    RAISE EXCEPTION 'NOT_AUTHORISED: caller is not part of this shoot-out group'
      USING ERRCODE = '42501';
  END IF;

  PERFORM public._tournament_validate_shootout_order(v_tied, p_ordered_winners);

  -- Record the report; reset any prior (mismatched) confirmation.
  UPDATE public.tournament_shootouts
     SET ordered_winners = p_ordered_winners,
         status          = 'reported',
         reported_by     = v_caller,
         reported_at     = now(),
         confirmed_by    = NULL,
         confirmed_at    = NULL
   WHERE id = p_shootout_id;

  INSERT INTO public.tournament_audit_events(
      tournament_id, kind, actor_user_id, payload)
    VALUES (v_tid, 'shootout_reported', v_caller,
            jsonb_build_object(
              'shootout_id',     p_shootout_id,
              'ordered_winners', to_jsonb(p_ordered_winners)));

  RETURN jsonb_build_object(
    'shootout_id', p_shootout_id,
    'status',      'reported',
    'ordered_winners', to_jsonb(p_ordered_winners));
END;
$$;

REVOKE ALL ON FUNCTION public.tournament_report_shootout_winners(uuid, uuid[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.tournament_report_shootout_winners(uuid, uuid[]) TO authenticated;


CREATE OR REPLACE FUNCTION public.tournament_confirm_shootout(
  p_shootout_id     uuid,
  p_ordered_winners uuid[]
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller     uuid;
  v_tid        uuid;
  v_tied       uuid[];
  v_status     text;
  v_reported   uuid[];
  v_reported_by uuid;
  v_match      boolean;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  SELECT tournament_id, tied_participant_ids, status,
         ordered_winners, reported_by
    INTO v_tid, v_tied, v_status, v_reported, v_reported_by
    FROM public.tournament_shootouts
   WHERE id = p_shootout_id
   FOR UPDATE;

  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'shoot-out not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_status = 'resolved' THEN
    -- Idempotent: already resolved.
    RETURN jsonb_build_object(
      'shootout_id', p_shootout_id, 'status', 'resolved',
      'ordered_winners', to_jsonb(v_reported));
  END IF;
  IF v_status <> 'reported' OR v_reported IS NULL THEN
    RAISE EXCEPTION 'NOT_REPORTED: no winner ordering has been reported yet'
      USING ERRCODE = '22023';
  END IF;

  IF NOT public._tournament_shootout_user_in_group(v_tid, v_tied, v_caller) THEN
    RAISE EXCEPTION 'NOT_AUTHORISED: caller is not part of this shoot-out group'
      USING ERRCODE = '42501';
  END IF;

  -- Confirmation must come from a DIFFERENT side than the reporter (two-sided
  -- consensus, mirrors match consensus needing both submitters).
  IF v_caller = v_reported_by THEN
    RAISE EXCEPTION 'NOT_AUTHORISED: reporter cannot self-confirm; the other side must confirm'
      USING ERRCODE = '42501';
  END IF;

  -- The confirmation must agree with the reported ordering exactly.
  v_match := (p_ordered_winners = v_reported);
  IF NOT v_match THEN
    RAISE EXCEPTION 'ORDER_MISMATCH: confirmation does not match the reported ordering'
      USING ERRCODE = '22023';
  END IF;

  UPDATE public.tournament_shootouts
     SET status       = 'resolved',
         confirmed_by = v_caller,
         confirmed_at = now()
   WHERE id = p_shootout_id;

  INSERT INTO public.tournament_audit_events(
      tournament_id, kind, actor_user_id, payload)
    VALUES (v_tid, 'shootout_resolved', v_caller,
            jsonb_build_object(
              'shootout_id',     p_shootout_id,
              'ordered_winners', to_jsonb(v_reported)));

  RETURN jsonb_build_object(
    'shootout_id', p_shootout_id,
    'status',      'resolved',
    'ordered_winners', to_jsonb(v_reported));
END;
$$;

REVOKE ALL ON FUNCTION public.tournament_confirm_shootout(uuid, uuid[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.tournament_confirm_shootout(uuid, uuid[]) TO authenticated;

COMMENT ON FUNCTION public.tournament_confirm_shootout(uuid, uuid[]) IS
  'Second-side confirmation of a reported shoot-out winner ordering. '
  'Resolves the shoot-out (ordered_winners frozen) only when a DIFFERENT '
  'involved team confirms the exact reported permutation. Non-involved '
  'callers -> NOT_AUTHORISED 42501. Mirrors the match consensus two-sided '
  'agreement; ShootoutResult permutation invariant enforced.';


-- ====================================================================
-- 8. tournament_start_ko_phase — latest body (20261201000032 §12,
--    per-tournament manage gate) re-stated VERBATIM + SHOOTOUT-GATE and
--    SHOOTOUT-RESOLVE.
-- ====================================================================
-- Two additions, both clearly marked:
--   * SHOOTOUT-GATE  : right before seed selection, detect qualification-
--     relevant tie groups; for each, ensure a tournament_shootouts row
--     exists (auto-detect + notify) and BLOCK with SHOOTOUT_PENDING (P0001)
--     if any such group is not yet resolved. No KO matches are inserted.
--   * SHOOTOUT-RESOLVE : after the seed list is built, re-order the tie
--     groups inside the seed list by their recorded ordered_winners
--     (resolveWithShootouts), replacing the participant_id fallback, then
--     re-cut to qualifier_count.

CREATE OR REPLACE FUNCTION public.tournament_start_ko_phase(
  p_tournament_id uuid,
  p_ko_config     jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller            uuid;
  v_creator           uuid;
  v_with_third_place  boolean;
  v_qualifier_count   int;
  v_incomplete        uuid[];
  v_ko_exists         int;
  v_has_pool_phase    boolean;
  v_seeds_jsonb       jsonb;
  v_match_count       int := 0;
  v_bye_count         int := 0;
  v_group_label       text;
  v_top_n             int;
  v_cut_result        jsonb;
  v_conflict_ids      jsonb := '[]'::jsonb;
  v_override_ids      uuid[];
  v_pool_count        int;
  v_bracket_type      text;
  v_with_reset        boolean;
  v_round             smallint;   -- PITCH-PLAN loop variable
  v_name              text;       -- GO-LIVE-NOTIFY
  v_grp               record;     -- SHOOTOUT-GATE
  v_pending_shootouts int := 0;   -- SHOOTOUT-GATE
  v_full_order        uuid[];     -- SHOOTOUT-RESOLVE
  v_chain             text[];     -- SHOOTOUT-RESOLVE
  v_so                record;     -- SHOOTOUT-RESOLVE
  v_k                 int;        -- SHOOTOUT-RESOLVE
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  SELECT created_by, bracket_type,
         coalesce((ko_config ->> 'with_bracket_reset')::boolean, true),
         display_name
    INTO v_creator, v_bracket_type, v_with_reset, v_name
    FROM public.tournaments
    WHERE id = p_tournament_id
    FOR UPDATE;

  -- PER-TOURNAMENT: creator OR owner/admin/organizer of the club_id
  -- (20261201000032 §12 — the actual latest auth gate). Keeps the
  -- delegation capability intact; do NOT regress to created_by-only.
  IF v_creator IS NULL
     OR NOT public.tournament_caller_can_manage(p_tournament_id) THEN
    RAISE EXCEPTION 'NOT_ORGANIZER: tournament not found or not authorised'
      USING ERRCODE = '42501';
  END IF;

  IF p_ko_config IS NULL OR jsonb_typeof(p_ko_config) <> 'object' THEN
    RAISE EXCEPTION 'INVALID_KO_CONFIG: ko_config must be a JSON object'
      USING ERRCODE = '22023';
  END IF;
  v_with_third_place := coalesce(
    (p_ko_config ->> 'with_third_place_playoff')::boolean, false);
  v_qualifier_count := coalesce((p_ko_config ->> 'qualifier_count')::int, 0);
  IF v_qualifier_count < 2 OR v_qualifier_count > 64 THEN
    RAISE EXCEPTION 'INVALID_KO_CONFIG: qualifier_count must be in [2, 64]'
      USING ERRCODE = '22023';
  END IF;

  IF v_bracket_type = 'double_elimination' THEN
    v_with_reset := coalesce(
      (p_ko_config ->> 'with_bracket_reset')::boolean, v_with_reset);
    IF v_with_third_place THEN
      RAISE EXCEPTION 'INVALID_KO_CONFIG: with_third_place_playoff is not allowed for double_elimination'
        USING ERRCODE = '22023';
    END IF;
  END IF;

  SELECT count(*) INTO v_ko_exists
    FROM public.tournament_matches
    WHERE tournament_id = p_tournament_id
      AND phase IN ('ko','third_place','final',
                    'wb','lb','grand_final','grand_final_reset');
  IF v_ko_exists > 0 THEN
    RAISE EXCEPTION 'ALREADY_STARTED: ko phase already initialised'
      USING ERRCODE = '40001';
  END IF;

  SELECT coalesce(array_agg(id ORDER BY id), ARRAY[]::uuid[])
    INTO v_incomplete
    FROM public.tournament_matches
    WHERE tournament_id = p_tournament_id
      AND phase = 'group'
      AND status NOT IN ('finalized','overridden','voided');
  IF array_length(v_incomplete, 1) IS NOT NULL THEN
    RAISE EXCEPTION 'PHASE_NOT_COMPLETE: % group match(es) not terminal: %',
      array_length(v_incomplete, 1), v_incomplete
      USING ERRCODE = '22023';
  END IF;

  -- ==================================================================
  -- SHOOTOUT-GATE (P6 D2a, docs/P6_SHOOTOUT_TIEBREAK.md).
  -- Detect qualification-relevant straddle-cut ties. For each detected
  -- group, ensure a tournament_shootouts row exists (auto-detect + notify
  -- the involved teams) and refuse to start the KO while ANY such group is
  -- not yet resolved. We do NOT silently fall back to the participant_id
  -- order (resolveWithShootouts pending semantics). This runs BEFORE any
  -- seed selection or match insert, so a pending shoot-out leaves zero KO
  -- matches behind.
  -- ==================================================================
  FOR v_grp IN
    SELECT * FROM public._tournament_detect_shootout_groups(
                     p_tournament_id, v_qualifier_count)
  LOOP
    -- Materialise (idempotent) so the involved teams have a task + the
    -- consensus RPCs have a target row.
    INSERT INTO public.tournament_shootouts(
        tournament_id, start_rank, tied_participant_ids)
      VALUES (p_tournament_id, v_grp.start_rank, v_grp.participant_ids)
      ON CONFLICT (tournament_id, tie_key) DO NOTHING;

    IF FOUND THEN
      PERFORM public._tournament_notify_shootout_group(
        p_tournament_id,
        v_grp.participant_ids,
        'Shoot-Out nötig',
        'Turnier "' || coalesce(v_name, '')
          || '": Gleichstand an der Qualifikations-Grenze — tragt den '
          || 'Shoot-Out-Sieger ein.',
        jsonb_build_object(
          'tournament_id', p_tournament_id,
          'kind',          'shootout',
          'start_rank',    v_grp.start_rank,
          'tied',          to_jsonb(v_grp.participant_ids)));
    END IF;

    -- Pending unless a RESOLVED row exists for this exact group.
    IF NOT EXISTS (
      SELECT 1 FROM public.tournament_shootouts s
       WHERE s.tournament_id = p_tournament_id
         AND s.status = 'resolved'
         AND s.tied_participant_ids @> v_grp.participant_ids
         AND s.tied_participant_ids <@ v_grp.participant_ids
    ) THEN
      v_pending_shootouts := v_pending_shootouts + 1;
    END IF;
  END LOOP;

  IF v_pending_shootouts > 0 THEN
    RAISE EXCEPTION 'SHOOTOUT_PENDING: % qualification-relevant shoot-out(s) unresolved',
      v_pending_shootouts USING ERRCODE = 'P0001';
  END IF;
  -- ==================== end SHOOTOUT-GATE ===========================

  SELECT EXISTS (
    SELECT 1 FROM public.tournament_participants
     WHERE tournament_id = p_tournament_id
       AND group_label IS NOT NULL
  ) INTO v_has_pool_phase;

  IF v_has_pool_phase THEN
    SELECT coalesce(array_agg(participant_id), ARRAY[]::uuid[])
      INTO v_override_ids
      FROM public.tournament_seeding_overrides
     WHERE tournament_id = p_tournament_id;

    SELECT count(DISTINCT group_label) INTO v_pool_count
      FROM public.tournament_participants
     WHERE tournament_id = p_tournament_id
       AND group_label IS NOT NULL;
    v_top_n := greatest(1, ((v_qualifier_count + v_pool_count - 1) / v_pool_count));

    CREATE TEMP TABLE IF NOT EXISTS _tmp_pool_cuts (
      group_label text,
      rank_in_pool int,
      participant_id uuid
    ) ON COMMIT DROP;
    TRUNCATE _tmp_pool_cuts;

    FOR v_group_label IN
      SELECT DISTINCT group_label
        FROM public.tournament_participants
       WHERE tournament_id = p_tournament_id
         AND group_label IS NOT NULL
       ORDER BY 1
    LOOP
      v_cut_result := public._tournament_compute_pool_cut(
        p_tournament_id, v_group_label, v_top_n);

      IF coalesce((v_cut_result ->> 'tie_resolution_needed')::boolean, false) THEN
        v_conflict_ids := v_conflict_ids
          || coalesce(v_cut_result -> 'conflicting_participants', '[]'::jsonb);
      END IF;

      INSERT INTO _tmp_pool_cuts(group_label, rank_in_pool, participant_id)
      SELECT v_group_label,
             (ord)::int,
             (val #>> '{}')::uuid
        FROM jsonb_array_elements(v_cut_result -> 'qualifiers')
             WITH ORDINALITY AS t(val, ord);
    END LOOP;

    IF jsonb_array_length(v_conflict_ids) > 0 THEN
      SELECT coalesce(jsonb_agg(elem ORDER BY elem), '[]'::jsonb)
        INTO v_conflict_ids
        FROM (
          SELECT DISTINCT elem
            FROM jsonb_array_elements_text(v_conflict_ids) AS elem
           WHERE (elem)::uuid <> ALL (v_override_ids)
        ) sub;

      IF jsonb_array_length(v_conflict_ids) > 0 THEN
        RAISE EXCEPTION 'TIEBREAKER_NEEDS_RESOLUTION'
          USING ERRCODE = 'P0001',
                DETAIL = jsonb_build_object(
                  'conflicting_participants', v_conflict_ids)::text;
      END IF;
    END IF;

    WITH labels AS (
      SELECT group_label,
             dense_rank() OVER (ORDER BY group_label) AS label_idx
        FROM (SELECT DISTINCT group_label FROM _tmp_pool_cuts) g
    ),
    base AS (
      SELECT c.participant_id,
             (c.rank_in_pool - 1) * 1000 + l.label_idx AS interleave_seed
        FROM _tmp_pool_cuts c
        JOIN labels l USING (group_label)
    ),
    overrides AS (
      SELECT participant_id, seed_override
        FROM public.tournament_seeding_overrides
       WHERE tournament_id = p_tournament_id
    ),
    combined AS (
      SELECT b.participant_id,
             coalesce(o.seed_override::numeric,
                      b.interleave_seed::numeric + 1000000) AS effective_seed,
             b.interleave_seed
        FROM base b
        LEFT JOIN overrides o USING (participant_id)
    ),
    seeded AS (
      SELECT participant_id,
             row_number() OVER (ORDER BY effective_seed, interleave_seed) AS final_seed
        FROM combined
    )
    SELECT coalesce(jsonb_agg(to_jsonb(participant_id::text) ORDER BY final_seed), '[]'::jsonb)
      INTO v_seeds_jsonb
      FROM seeded
     WHERE final_seed <= v_qualifier_count;

  ELSE
    WITH stats AS (
      SELECT p.id AS participant_id,
             p.registered_at,
             coalesce(sum(CASE WHEN m.winner_participant = p.id THEN 1 ELSE 0 END), 0) AS wins,
             coalesce(sum(
               CASE WHEN m.participant_a = p.id THEN m.final_score_a - m.final_score_b
                    WHEN m.participant_b = p.id THEN m.final_score_b - m.final_score_a
                    ELSE 0 END), 0) AS kubb_diff
        FROM public.tournament_participants p
        LEFT JOIN public.tournament_matches m
          ON m.tournament_id = p.tournament_id
         AND m.phase = 'group'
         AND m.status IN ('finalized','overridden')
         AND (m.participant_a = p.id OR m.participant_b = p.id)
       WHERE p.tournament_id = p_tournament_id
         AND p.registration_status = 'confirmed'
       GROUP BY p.id, p.registered_at
    ),
    ranked AS (
      SELECT participant_id,
             row_number() OVER (
               ORDER BY wins DESC, kubb_diff DESC, registered_at ASC, participant_id ASC
             ) AS auto_seed
        FROM stats
    ),
    overrides AS (
      SELECT participant_id, seed_override
        FROM public.tournament_seeding_overrides
       WHERE tournament_id = p_tournament_id
    ),
    combined AS (
      SELECT r.participant_id,
             coalesce(o.seed_override::numeric,
                      r.auto_seed::numeric + 1000) AS effective_seed,
             r.auto_seed
        FROM ranked r
        LEFT JOIN overrides o USING (participant_id)
    ),
    seeded AS (
      SELECT participant_id,
             row_number() OVER (ORDER BY effective_seed, auto_seed) AS final_seed
        FROM combined
    )
    SELECT coalesce(jsonb_agg(to_jsonb(participant_id::text) ORDER BY final_seed), '[]'::jsonb)
      INTO v_seeds_jsonb
      FROM seeded
     WHERE final_seed <= v_qualifier_count;
  END IF;

  -- ==================================================================
  -- SHOOTOUT-RESOLVE (resolveWithShootouts L256-283).
  -- At this point every qualification-relevant tie group is RESOLVED (the
  -- gate above guaranteed it). The seed list (v_seeds_jsonb) was built with
  -- the deterministic participant_id fallback for tied ranks; we now build
  -- the FULL ranking, overwrite each resolved group's slice
  -- [start_rank .. start_rank+n-1] with its recorded ordered_winners, and
  -- re-cut to qualifier_count — replacing the fallback for those groups.
  -- Cosmetic ties keep their existing chain/ID order untouched.
  --
  -- IMPORTANT: this flat-ranking splice mirrors the pure-Dart
  -- resolveWithShootouts, which operates on ONE flat ranking and knows no
  -- pools. It is therefore only applied in the NON-pool branch. For pool
  -- tournaments the interleaved per-pool cut built above is authoritative;
  -- overwriting it with a flat cross-pool ranking would ignore the pool
  -- boundaries and corrupt the KO seeding (and the flat detector likewise
  -- has no pool semantics, so a straddle-cut detected flatly does not map to
  -- the per-pool qualification anyway). Guarding on NOT v_has_pool_phase
  -- keeps the pool-correct seeds intact.
  -- ==================================================================
  IF NOT v_has_pool_phase AND EXISTS (
    SELECT 1 FROM public.tournament_shootouts
     WHERE tournament_id = p_tournament_id AND status = 'resolved'
  ) THEN
    -- Build the full deterministic ranking (same gated chain key as the
    -- detector / non-pool standings) as an ordered uuid[] over ALL confirmed
    -- participants, then splice in each resolved group.
    SELECT tiebreaker_order INTO v_chain
      FROM public.tournaments WHERE id = p_tournament_id;

    WITH stats AS (
      SELECT p.id AS pid,
             p.registered_at,
             coalesce(sum(CASE WHEN m.winner_participant = p.id THEN 1 ELSE 0 END), 0) AS wins,
             coalesce(sum(
               CASE WHEN m.participant_a = p.id THEN coalesce(m.final_score_a,0)
                    WHEN m.participant_b = p.id THEN coalesce(m.final_score_b,0)
                    ELSE 0 END), 0) AS total_points,
             coalesce(sum(
               CASE WHEN m.participant_a = p.id
                      THEN coalesce(m.final_score_a,0) - coalesce(m.final_score_b,0)
                    WHEN m.participant_b = p.id
                      THEN coalesce(m.final_score_b,0) - coalesce(m.final_score_a,0)
                    ELSE 0 END), 0) AS kubb_diff
        FROM public.tournament_participants p
        LEFT JOIN public.tournament_matches m
          ON m.tournament_id = p.tournament_id
         AND m.phase = 'group'
         AND m.status IN ('finalized','overridden')
         AND (m.participant_a = p.id OR m.participant_b = p.id)
       WHERE p.tournament_id = p_tournament_id
         AND p.registration_status = 'confirmed'
       GROUP BY p.id, p.registered_at
    )
    SELECT array_agg(pid ORDER BY rnk)
      INTO v_full_order
      FROM (
        SELECT s.pid,
               row_number() OVER (
                 ORDER BY
                   CASE WHEN 'total_points'    = ANY(v_chain) THEN -s.total_points ELSE 0 END,
                   CASE WHEN 'wins'            = ANY(v_chain) THEN -s.wins         ELSE 0 END,
                   CASE WHEN 'kubb_difference' = ANY(v_chain) THEN -s.kubb_diff    ELSE 0 END,
                   s.registered_at ASC,
                   s.pid ASC
               ) AS rnk
          FROM stats s
      ) r;

    -- Splice each resolved group's ordered_winners into its rank slice.
    FOR v_so IN
      SELECT start_rank, ordered_winners
        FROM public.tournament_shootouts
       WHERE tournament_id = p_tournament_id
         AND status = 'resolved'
         AND ordered_winners IS NOT NULL
    LOOP
      FOR v_k IN 1 .. array_length(v_so.ordered_winners, 1) LOOP
        -- v_full_order is 1-based; start_rank is 0-based.
        v_full_order[v_so.start_rank + v_k] := v_so.ordered_winners[v_k];
      END LOOP;
    END LOOP;

    -- Re-cut to qualifier_count from the resolved full order.
    SELECT coalesce(jsonb_agg(to_jsonb(pid::text) ORDER BY ord), '[]'::jsonb)
      INTO v_seeds_jsonb
      FROM (
        SELECT pid, ord
          FROM unnest(v_full_order) WITH ORDINALITY AS t(pid, ord)
         WHERE ord <= v_qualifier_count
      ) q;
  END IF;
  -- ==================== end SHOOTOUT-RESOLVE ========================

  IF jsonb_array_length(v_seeds_jsonb) < v_qualifier_count THEN
    RAISE EXCEPTION 'INVALID_KO_CONFIG: qualifier_count % exceeds confirmed participants',
      v_qualifier_count USING ERRCODE = '22023';
  END IF;

  UPDATE public.tournaments
    SET ko_config = p_ko_config
    WHERE id = p_tournament_id;

  IF v_bracket_type = 'double_elimination' THEN
    INSERT INTO public.tournament_matches(
        tournament_id, round_number, match_number_in_round,
        bracket_position, participant_a, participant_b,
        phase, status, winner_participant, pitch_number, finalized_at)
    SELECT p_tournament_id,
           b.round_number::smallint,
           b.bracket_position::smallint,
           b.bracket_position,
           b.participant_a,
           b.participant_b,
           b.phase,
           CASE WHEN b.is_bye_pairing THEN 'finalized' ELSE 'scheduled' END,
           CASE WHEN b.is_bye_pairing
                THEN coalesce(b.participant_a, b.participant_b) END,
           1,
           CASE WHEN b.is_bye_pairing THEN now() END
      FROM public._tournament_compute_de_bracket(v_seeds_jsonb, v_with_reset) b;
  ELSE
    INSERT INTO public.tournament_matches(
        tournament_id, round_number, match_number_in_round,
        bracket_position, participant_a, participant_b,
        phase, status, winner_participant, pitch_number, finalized_at)
    SELECT p_tournament_id,
           b.round_number::smallint,
           b.bracket_position::smallint,
           b.bracket_position,
           b.participant_a,
           b.participant_b,
           b.phase,
           CASE WHEN b.is_bye_pairing THEN 'finalized' ELSE 'scheduled' END,
           CASE WHEN b.is_bye_pairing
                THEN coalesce(b.participant_a, b.participant_b) END,
           1,
           CASE WHEN b.is_bye_pairing THEN now() END
      FROM public._tournament_compute_ko_bracket(v_seeds_jsonb, v_with_third_place) b;
  END IF;

  GET DIAGNOSTICS v_match_count = ROW_COUNT;

  FOR v_round IN
    SELECT DISTINCT round_number
      FROM public.tournament_matches
     WHERE tournament_id = p_tournament_id
       AND phase IN ('ko','third_place','final',
                     'wb','lb','grand_final','grand_final_reset')
     ORDER BY round_number
  LOOP
    PERFORM public._tournament_assign_pitches(p_tournament_id, v_round);
  END LOOP;

  SELECT count(*) INTO v_bye_count
    FROM public.tournament_matches
    WHERE tournament_id = p_tournament_id
      AND phase IN ('ko','final','wb','lb')
      AND status = 'finalized';

  INSERT INTO public.tournament_audit_events(
      tournament_id, kind, actor_user_id, payload)
    VALUES (
      p_tournament_id,
      'ko_phase_started',
      v_caller,
      jsonb_build_object(
        'qualifier_count',          v_qualifier_count,
        'with_third_place_playoff', v_with_third_place,
        'bracket_type',             v_bracket_type,
        'with_bracket_reset',       v_with_reset,
        'match_count',              v_match_count,
        'bye_count',                v_bye_count,
        'pool_phase_present',       v_has_pool_phase,
        'seeds',                    v_seeds_jsonb));

  -- GO-LIVE-NOTIFY: KO bracket published — new round for everyone.
  PERFORM public._tournament_notify_participants(
    p_tournament_id,
    'tournament_round',
    'Neue Runde',
    'Turnier "' || coalesce(v_name, '') || '": K.-o.-Phase — dein Platz ist da, leg los!',
    jsonb_build_object('tournament_id', p_tournament_id, 'phase', 'ko'));

  RETURN jsonb_build_object(
    'tournament_id', p_tournament_id,
    'match_count',   v_match_count,
    'bye_count',     v_bye_count,
    'pool_phase',    v_has_pool_phase,
    'bracket_type',  v_bracket_type);
END;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_start_ko_phase(uuid, jsonb)
  TO authenticated;

COMMENT ON FUNCTION public.tournament_start_ko_phase(uuid, jsonb) IS
  'KO-Start (latest body 20261201000032, per-tournament manage gate) + '
  'P6 D2a SHOOTOUT-GATE/RESOLVE: '
  'blockiert mit SHOOTOUT_PENDING (P0001) solange eine quali-relevante '
  'Shoot-Out-Gruppe (straddle-cut tie) offen ist, und ersetzt bei Auflösung '
  'den participant_id-Fallback an der Cut-Linie durch die erfasste '
  'ordered_winners-Reihenfolge (resolveWithShootouts). Spiegelt shootout.dart '
  'fuer die serverseitig aufloesbaren Kriterien (Detector-CAVEAT beachten); '
  'die flache Resolve-Splice gilt nur im Nicht-Pool-Zweig (Pool-Seeds bleiben '
  'das interleaved per-pool cut).';
