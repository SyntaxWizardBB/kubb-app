-- Follow-up patches to ADR-0012 Phase 2 Match feature.
--
-- Three bugs surfaced in real testing:
--
-- 1. Walk-ins were a planning misstep. The original spec accepted them
--    but they cascade complexity (UI overflow on the chip, separate
--    voting branch, kind_shape CHECK that blocks DELETE cascades —
--    see #3) for a use-case the owner does not actually need. Drop
--    the whole walk-in concept: only in-app users can be participants.
--
-- 2. `match_get` returned `match.id` for the match-row's primary key
--    while `match_list_for_caller` returned `match_id`. The Dart
--    parser expected `match_id` everywhere and threw a cast-error on
--    detail load — surfaced to the user as "Match konnte nicht
--    geladen werden". Normalise the wire shape.
--
-- 3. Account deletion failed because `match_participants.user_id` is
--    `ON DELETE SET NULL`, but the `kind_shape` CHECK requires
--    `user_id IS NOT NULL` for `kind='in_app'`. Cascading a user
--    delete into that row violates the CHECK and aborts the whole
--    auth.users delete transaction. Switch to `ON DELETE CASCADE` —
--    when an in-app participant deletes their account, the
--    participant row goes with them. The match continues if at least
--    one in-app participant remains; otherwise it voids on the next
--    propose attempt (no more 'in_app + accepted' rows = required = 0
--    case, already handled by reconciler).

-- ---- 1. Drop walk-in support -----------------------------------------

-- Remove any existing walk-in rows so the new CHECK can take effect.
-- These were test data only — by design no production matches exist.
DELETE FROM public.match_participants WHERE kind = 'walk_in';

-- Loosen the kind_shape CHECK first (we are about to change kind enum).
ALTER TABLE public.match_participants
  DROP CONSTRAINT IF EXISTS match_participants_kind_shape;

-- Drop the kind enum's walk_in option. New CHECK + we keep the column
-- (legacy data) but enforce 'in_app' only.
ALTER TABLE public.match_participants
  DROP CONSTRAINT IF EXISTS match_participants_kind_check;
ALTER TABLE public.match_participants
  ADD CONSTRAINT match_participants_kind_check
    CHECK (kind = 'in_app');

-- Drop the walkin_name column entirely — no more walk-in concept.
ALTER TABLE public.match_participants
  DROP COLUMN IF EXISTS walkin_name;

-- New shape constraint: every participant has a user_id.
ALTER TABLE public.match_participants
  ADD CONSTRAINT match_participants_user_required
    CHECK (user_id IS NOT NULL);

-- Switch the FK from ON DELETE SET NULL to ON DELETE CASCADE so account
-- deletion can actually cascade through.
ALTER TABLE public.match_participants
  DROP CONSTRAINT IF EXISTS match_participants_user_id_fkey;
ALTER TABLE public.match_participants
  ADD CONSTRAINT match_participants_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- match_participants_unique_user_per_match was a partial index keyed on
-- "WHERE user_id IS NOT NULL". With user_id now NOT NULL, the WHERE
-- clause is redundant — replace with a plain unique index.
DROP INDEX IF EXISTS public.match_participants_unique_user_per_match;
CREATE UNIQUE INDEX match_participants_unique_user_per_match
  ON public.match_participants(match_id, user_id);


-- ---- 2. Replace match_create with the simplified, walk-in-free body --

CREATE OR REPLACE FUNCTION public.match_create(
  p_format  text,
  p_scoring text,
  p_team_a  jsonb,
  p_team_b  jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller       uuid;
  v_match_id     uuid;
  v_team         text;
  v_arr          jsonb;
  v_elem         jsonb;
  v_user_id      uuid;
  v_caller_seen  boolean := false;
  v_pending      int := 0;
  v_caller_nick  text;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;
  IF p_format NOT IN ('bo1','bo3','bo5') THEN
    RAISE EXCEPTION 'invalid format: %', p_format USING ERRCODE = '22023';
  END IF;
  IF p_scoring NOT IN ('wins','points') THEN
    RAISE EXCEPTION 'invalid scoring: %', p_scoring USING ERRCODE = '22023';
  END IF;
  IF jsonb_array_length(p_team_a) NOT BETWEEN 1 AND 6
     OR jsonb_array_length(p_team_b) NOT BETWEEN 1 AND 6 THEN
    RAISE EXCEPTION 'each team must have 1..6 players' USING ERRCODE = '22023';
  END IF;

  v_match_id := gen_random_uuid();
  INSERT INTO public.matches(
      id, created_by, format, scoring, status, current_round, started_at)
    VALUES (v_match_id, v_caller, p_format, p_scoring, 'pending_invites', 0, now());

  INSERT INTO public.match_teams(match_id, team_id) VALUES (v_match_id, 'A'), (v_match_id, 'B');

  INSERT INTO public.match_audit_events(match_id, kind, actor_user_id, payload)
    VALUES (v_match_id, 'created', v_caller,
            jsonb_build_object('format', p_format, 'scoring', p_scoring));

  -- Caller's nickname for inbox messages.
  SELECT nickname::text INTO v_caller_nick
    FROM public.user_profiles WHERE user_id = v_caller;

  -- Walk through both teams. Every entry must be {kind:'in_app', user_id:'<uuid>'}.
  FOR v_team IN SELECT unnest(ARRAY['A','B']) LOOP
    v_arr := CASE v_team WHEN 'A' THEN p_team_a ELSE p_team_b END;
    FOR v_elem IN SELECT jsonb_array_elements(v_arr) LOOP
      IF (v_elem->>'kind') <> 'in_app' THEN
        RAISE EXCEPTION 'walk-in participants are not supported'
          USING ERRCODE = '22023';
      END IF;
      v_user_id := (v_elem->>'user_id')::uuid;
      IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'in_app participant requires user_id'
          USING ERRCODE = '22023';
      END IF;

      IF v_user_id = v_caller THEN
        v_caller_seen := true;
        INSERT INTO public.match_participants(
            match_id, team_id, kind, user_id, invitation_status, responded_at)
          VALUES (v_match_id, v_team, 'in_app', v_user_id, 'accepted', now());
      ELSE
        -- Friendship check (mirror group_invite_member).
        IF NOT EXISTS (
          SELECT 1 FROM public.friendships
            WHERE status = 'accepted'
              AND ((low_user_id  = v_caller  AND high_user_id = v_user_id) OR
                   (low_user_id  = v_user_id AND high_user_id = v_caller))
        ) THEN
          RAISE EXCEPTION 'can only invite accepted friends'
            USING ERRCODE = '42501';
        END IF;
        INSERT INTO public.match_participants(
            match_id, team_id, kind, user_id, invitation_status)
          VALUES (v_match_id, v_team, 'in_app', v_user_id, 'pending');
        v_pending := v_pending + 1;

        -- Inbox message for invitee.
        INSERT INTO public.user_inbox_messages(
            user_id, kind, subject, body, action_payload)
          VALUES (
            v_user_id,
            'verification_request',
            'Match-Einladung',
            coalesce(v_caller_nick, 'Ein Spieler') ||
              ' lädt dich zu einem ' || p_format || '-Match ein.',
            jsonb_build_object(
              'kind', 'match_invite',
              'match_id', v_match_id,
              'invited_by_user_id', v_caller,
              'invited_by_nickname', v_caller_nick,
              'format', p_format,
              'scoring', p_scoring
            )
          );
      END IF;

      INSERT INTO public.match_audit_events(match_id, kind, actor_user_id, payload)
        VALUES (v_match_id, 'participant_invited', v_caller,
          jsonb_build_object('user_id', v_user_id, 'team_id', v_team,
                             'kind', 'in_app'));
    END LOOP;
  END LOOP;

  IF NOT v_caller_seen THEN
    RAISE EXCEPTION 'creator must be a participant' USING ERRCODE = '22023';
  END IF;

  -- If no peers needed inviting, jump straight to active.
  IF v_pending = 0 THEN
    UPDATE public.matches SET status = 'active' WHERE id = v_match_id;
    INSERT INTO public.match_audit_events(match_id, kind, actor_user_id, payload)
      VALUES (v_match_id, 'started', v_caller, jsonb_build_object('auto', true));
  END IF;

  RETURN jsonb_build_object('match_id', v_match_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.match_create(text, text, jsonb, jsonb) TO authenticated;


-- ---- 3. Normalise match_get JSON shape (match.match_id, not match.id) -

CREATE OR REPLACE FUNCTION public.match_get(p_match_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller       uuid;
  v_match        jsonb;
  v_teams        jsonb;
  v_participants jsonb;
  v_own          jsonb;
  v_audit        jsonb;
  v_round        smallint;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.match_participants
    WHERE match_id = p_match_id AND user_id = v_caller
  ) THEN
    RETURN NULL;
  END IF;

  -- Project explicitly so the JSON key is `match_id` (matches the
  -- list-RPC and the Dart parser's expectation).
  SELECT jsonb_build_object(
           'match_id',       m.id,
           'created_by',     m.created_by,
           'format',         m.format,
           'scoring',        m.scoring,
           'status',         m.status,
           'current_round',  m.current_round,
           'winner_team_id', m.winner_team_id,
           'final_score_a',  m.final_score_a,
           'final_score_b',  m.final_score_b,
           'settings',       m.settings,
           'started_at',     m.started_at,
           'completed_at',   m.completed_at,
           'voided_at',      m.voided_at
         )
    INTO v_match
    FROM public.matches m WHERE m.id = p_match_id;
  IF v_match IS NULL THEN
    RETURN NULL;
  END IF;

  v_round := (v_match ->> 'current_round')::smallint;

  SELECT coalesce(jsonb_agg(to_jsonb(t.*) ORDER BY t.team_id), '[]'::jsonb)
    INTO v_teams
    FROM public.match_teams t
    WHERE t.match_id = p_match_id;

  -- Project participants explicitly: include nickname for in_app users.
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'participant_id',    p.participant_id,
           'team_id',           p.team_id,
           'kind',              p.kind,
           'user_id',           p.user_id,
           'nickname',          up.nickname,
           'invitation_status', p.invitation_status,
           'joined_at',         p.joined_at,
           'responded_at',      p.responded_at
         ) ORDER BY p.team_id, p.joined_at), '[]'::jsonb)
    INTO v_participants
    FROM public.match_participants p
    LEFT JOIN public.user_profiles up ON up.user_id = p.user_id
    WHERE p.match_id = p_match_id;

  SELECT jsonb_build_object(
           'round',          pr.round,
           'winner_team_id', pr.winner_team_id,
           'score_a',        pr.score_a,
           'score_b',        pr.score_b
         )
    INTO v_own
    FROM public.match_result_proposals pr
    WHERE pr.match_id = p_match_id
      AND pr.user_id  = v_caller
      AND pr.round    = v_round;

  SELECT coalesce(jsonb_agg(to_jsonb(e.*) ORDER BY e.at DESC), '[]'::jsonb)
    INTO v_audit
    FROM (
      SELECT * FROM public.match_audit_events
       WHERE match_id = p_match_id
       ORDER BY at DESC
       LIMIT 20
    ) e;

  RETURN jsonb_build_object(
    'match',         v_match,
    'teams',         v_teams,
    'participants',  v_participants,
    'own_proposal',  v_own,
    'audit_tail',    v_audit
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.match_get(uuid) TO authenticated;
