-- Maengel #2 (P1): organizers cannot remove a CONFIRMED participant today.
-- The 'Entfernen' button wires to tournament_reject_registration, which is
-- creator-only, raises 22023 on a confirmed row, and runs no waitlist logic.
-- The correct freeing-a-slot + dynamic promotion logic only exists inside
-- tournament_withdraw, hard self-gated to the participant.
--
-- This adds tournament_remove_participant: an organizer-facing soft removal.
-- Locked owner decision (Option 1): REUSE registration_status='withdrawn' (no
-- new 'removed' status), promote the oldest waitlisted unit exactly as
-- tournament_withdraw does, and only NOTIFY the organizer about any open live
-- matches the removed participant is in. No auto-void, never a hard DELETE
-- (participant_a/b FK is ON DELETE CASCADE — deleting would drop finalized
-- matches with their winner/score).
--
-- Gate: tournament_caller_can_setup (creator OR club owner/admin; a pure
-- referee is intentionally excluded). Status window mirrors withdraw:
-- registration_open / registration_closed / live only.

CREATE OR REPLACE FUNCTION public.tournament_remove_participant(
  p_participant_id uuid,
  p_reason         text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller        uuid;
  v_user_id       uuid;
  v_team_id       uuid;
  v_tournament_id uuid;
  v_prior         text;
  v_status        text;
  v_name          text;
  v_promoted_id   uuid;
  v_promoted_user uuid;
  v_promoted_team uuid;
  v_member        uuid;
  v_open_matches  int;
  v_organizer     uuid;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT p.user_id, p.team_id, p.tournament_id, p.registration_status
    INTO v_user_id, v_team_id, v_tournament_id, v_prior
    FROM public.tournament_participants p
    WHERE p.id = p_participant_id
    FOR UPDATE;
  IF v_tournament_id IS NULL THEN
    RAISE EXCEPTION 'participant not found' USING ERRCODE = 'P0002';
  END IF;

  -- ORGANIZER gate: creator OR club owner/admin. A pure club referee fails;
  -- a stranger fails. (tournament_caller_can_setup, ADR-0032.)
  IF NOT public.tournament_caller_can_setup(v_tournament_id) THEN
    RAISE EXCEPTION 'not authorised to remove participants'
      USING ERRCODE = '42501';
  END IF;

  SELECT status, display_name, created_by
    INTO v_status, v_name, v_organizer
    FROM public.tournaments WHERE id = v_tournament_id;
  IF v_status NOT IN ('registration_open','registration_closed','live') THEN
    RAISE EXCEPTION 'removal not allowed in current tournament state'
      USING ERRCODE = '22023';
  END IF;

  IF v_prior = 'withdrawn' THEN
    RAISE EXCEPTION 'participant already removed' USING ERRCODE = '22023';
  END IF;

  -- Soft removal — reuse 'withdrawn' (Option 1, no new status). Stamp
  -- withdrew_at like a self-withdrawal so existing projections behave.
  UPDATE public.tournament_participants
    SET registration_status = 'withdrawn',
        withdrew_at         = now()
    WHERE id = p_participant_id;

  INSERT INTO public.tournament_audit_events(
      tournament_id, kind, actor_user_id, payload)
    VALUES (
      v_tournament_id,
      'participant_removed',
      v_caller,
      jsonb_build_object(
        'participant_id', p_participant_id,
        'prior_status',   v_prior,
        'removed_by',     v_caller,
        'reason',         p_reason
      )
    );

  -- DYNAMIC PROMOTION — mirrors tournament_withdraw §6 EXACTLY. Only a
  -- CONFIRMED removal frees a real slot; a waitlist removal changes nothing
  -- for the confirmed pool. Same FOR UPDATE + ORDER BY registered_at, id to
  -- avoid a double-promote race with a concurrent withdrawal/removal in the
  -- same tournament.
  IF v_prior = 'confirmed' THEN
    SELECT p.id, p.user_id, p.team_id
      INTO v_promoted_id, v_promoted_user, v_promoted_team
      FROM public.tournament_participants p
      WHERE p.tournament_id = v_tournament_id
        AND p.registration_status = 'waitlist'
      ORDER BY p.registered_at, p.id
      LIMIT 1
      FOR UPDATE;

    IF v_promoted_id IS NOT NULL THEN
      UPDATE public.tournament_participants
        SET registration_status = 'confirmed',
            responded_at        = now()
        WHERE id = v_promoted_id;

      INSERT INTO public.tournament_audit_events(
          tournament_id, kind, actor_user_id, payload)
        VALUES (
          v_tournament_id,
          'waitlist_promoted',
          v_caller,
          jsonb_build_object(
            'participant_id', v_promoted_id,
            'freed_by',       p_participant_id
          )
        );

      -- Notify the promoted unit. For a team participant, fan out to every
      -- registered roster member; for a solo, the participant's user_id.
      IF v_promoted_team IS NOT NULL THEN
        FOR v_member IN
          SELECT DISTINCT s.member_user_id
            FROM public.tournament_roster_slots s
           WHERE s.participant_id = v_promoted_id
             AND s.member_user_id IS NOT NULL
        LOOP
          INSERT INTO public.user_inbox_messages(
              user_id, kind, subject, body, action_payload)
            VALUES (
              v_member,
              'tournament_promoted',
              'Du bist nachgerückt',
              'Ein Platz bei "' || coalesce(v_name, '')
                || '" ist frei geworden — euer Team ist nachgerückt. Ihr seid dabei!',
              jsonb_build_object(
                'tournament_id',  v_tournament_id,
                'participant_id', v_promoted_id
              )
            );
        END LOOP;
      ELSE
        INSERT INTO public.user_inbox_messages(
            user_id, kind, subject, body, action_payload)
          VALUES (
            v_promoted_user,
            'tournament_promoted',
            'Du bist nachgerückt',
            'Ein Platz bei "' || coalesce(v_name, '')
              || '" ist frei geworden — du bist nachgerückt. Du bist dabei!',
            jsonb_build_object(
              'tournament_id',  v_tournament_id,
              'participant_id', v_promoted_id
            )
          );
      END IF;
    END IF;
  END IF;

  -- OPEN LIVE MATCHES of the removed participant: notice to the organizer.
  -- No auto-void — the organizer decides forfeit/override. Finalized matches
  -- are never touched (and never cascade-deleted, since this is a soft status
  -- change, not a DELETE).
  SELECT count(*)::int INTO v_open_matches
    FROM public.tournament_matches m
    WHERE m.tournament_id = v_tournament_id
      AND m.status IN ('scheduled','awaiting_results','disputed')
      AND (m.participant_a = p_participant_id
           OR m.participant_b = p_participant_id);

  IF v_open_matches > 0 AND v_organizer IS NOT NULL THEN
    INSERT INTO public.user_inbox_messages(
        user_id, kind, subject, body, action_payload)
      VALUES (
        v_organizer,
        'notice',
        'Offene Matches betroffen',
        'Ein entfernter Teilnehmer hat noch ' || v_open_matches
          || ' offene Match(es) bei "' || coalesce(v_name, '')
          || '". Bitte forfeit oder Override setzen.',
        jsonb_build_object(
          'tournament_id', v_tournament_id,
          'participant_id', p_participant_id,
          'open_matches',   v_open_matches
        )
      );
  END IF;

  -- Notify the removed user (solo path only; a team removal would need a
  -- roster fan-out, deferred — solo is the P1 surface).
  IF v_user_id IS NOT NULL THEN
    INSERT INTO public.user_inbox_messages(
        user_id, kind, subject, body, action_payload)
      VALUES (
        v_user_id,
        'notice',
        'Aus Turnier entfernt',
        'Du wurdest von der Organisation aus "' || coalesce(v_name, '')
          || '" entfernt.'
          || coalesce(' Grund: ' || p_reason, ''),
        jsonb_build_object(
          'tournament_id',  v_tournament_id,
          'participant_id', p_participant_id
        )
      );
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.tournament_remove_participant(uuid, text) FROM public;
GRANT EXECUTE ON FUNCTION public.tournament_remove_participant(uuid, text)
  TO authenticated;

COMMENT ON FUNCTION public.tournament_remove_participant(uuid, text) IS
  'Organizer-facing soft removal of a participant (Maengel #2). Reuses '
  'registration_status=''withdrawn'' (Option 1, no new status). Gated by '
  'tournament_caller_can_setup. On a confirmed removal, promotes the oldest '
  'waitlisted unit identically to tournament_withdraw. Open live matches '
  'trigger an organizer notice; never a hard DELETE (FK cascade safety).';
