-- Team-Anmeldung: jedes aktive Team-Pool-Mitglied darf die Turnier-Anmeldung
-- des Teams verwalten (zurückziehen) und sie in der eigenen
-- "Angemeldete Turniere"-Liste sehen — nicht mehr nur die Person, die das Team
-- ursprünglich angemeldet hat.
--
-- Motivation: der Score-Pfad (tournament_propose_set_scores, zuletzt
-- 20261238000000_score_consensus_canonical_set_winner.sql und der Override in
-- 20261314000000) autorisiert bereits jedes aktive Team-Mitglied über die
-- Team-Pool-Mitgliedschaft (team_memberships.removed_at IS NULL). Withdraw und
-- die "meine Anmeldungen"-Liste hingen aber noch am Registranten. Diese
-- Migration zieht beide auf denselben Autorisierungs-Gate wie der Score-Pfad.
--
-- Zwei CREATE OR REPLACE, jeweils byte-nah zur letzten Definition, geändert
-- ist NUR der Autorisierungs-Gate bzw. die WHERE-Sichtbarkeit:
--   * tournament_withdraw          — letzte Definition 20261201000040 §3.
--     Der Registranten-only-Gate (v_user_id IS DISTINCT FROM v_caller) wird
--     durch das SOLO-ODER-AKTIVES-TEAM-MITGLIED-Prädikat ersetzt. Alles andere
--     (Status-Gate, dynamische Nachrück-Promotion, Inbox-Fan-out, Audit) bleibt
--     verbatim; der Audit-Actor bleibt der Aufrufer (v_caller).
--   * tournament_list_my_registrations — letzte Definition 20260901000004.
--     Die WHERE-Klausel wird von "nur eigene Solo-Zeilen" (p.user_id =
--     v_caller) auf "eigene Solo-Zeilen ODER Team-Zeilen, in deren Team der
--     Aufrufer aktives Pool-Mitglied ist" verbreitert.
--
-- Scope = aktives TEAM-POOL-Mitglied (team_memberships.removed_at IS NULL) —
-- deckungsgleich mit dem Score-Pfad; ein Ex-Mitglied (removed_at gesetzt) ist
-- ausgeschlossen. Es entsteht KEINE zweite tournament_participants-Zeile: das
-- Unique (tournament_id, user_id) bleibt unangetastet, Mitglieder operieren
-- über die RPC auf der bestehenden Team-Zeile.
--
-- Bewusst NICHT angefasst:
--   * RLS-Policy tournament_participants_self_withdraw bleibt wie sie ist —
--     withdraw läuft als SECURITY DEFINER und umgeht ohnehin die Row-Level-
--     Policy; der Autorisierungs-Gate liegt in der Funktion selbst.
--   * tournament_list_for_caller (zuletzt 20261277000000) listet Turniere nach
--     Status/Invite/Creator, NICHT nach der Anmelde-Zeile des Aufrufers — es
--     versteckt eine Team-Anmeldung also gar nicht vor Nicht-Registranten.
--     Kein user_id=caller-Binding auf DERSELBEN Anmeldung, daher hier nichts zu
--     verbreitern. Ein separates my_active_match-RPC existiert nicht.


-- ====================================================================
-- 1. tournament_withdraw — verbatim re-base von 20261201000040 §3. EINZIGE
--    Änderung: der Registranten-only-Gate wird durch das
--    Solo-oder-aktives-Team-Mitglied-Prädikat ersetzt (v_team_id zusätzlich
--    geladen). Status-Gate, Promotion, Inbox-Fan-out und Audit unverändert.
-- ====================================================================

CREATE OR REPLACE FUNCTION public.tournament_withdraw(
  p_participant_id uuid
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
  v_status        text;
  v_prior         text;
  v_promoted_id   uuid;
  v_promoted_user uuid;
  v_promoted_team uuid;
  v_name          text;
  v_member        uuid;
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
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'participant not found' USING ERRCODE = 'P0002';
  END IF;

  -- SOLO-OR-ACTIVE-TEAM-MEMBER: the registrant may always withdraw their own
  -- row; for a team registration any active pool member of that team may
  -- withdraw it too (same gate as the score path). Ex-members (removed_at set)
  -- are excluded.
  IF NOT (
    v_user_id = v_caller
    OR (
      v_team_id IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM public.team_memberships tm
         WHERE tm.team_id = v_team_id
           AND tm.user_id = v_caller
           AND tm.removed_at IS NULL
      )
    )
  ) THEN
    RAISE EXCEPTION 'only the participant or an active team member can withdraw'
      USING ERRCODE = '42501';
  END IF;

  SELECT status, display_name INTO v_status, v_name
    FROM public.tournaments WHERE id = v_tournament_id;
  IF v_status NOT IN ('registration_open','registration_closed','live') THEN
    RAISE EXCEPTION 'withdrawal not allowed in current tournament state'
      USING ERRCODE = '22023';
  END IF;

  IF v_prior = 'withdrawn' THEN
    RAISE EXCEPTION 'already withdrawn' USING ERRCODE = '22023';
  END IF;

  UPDATE public.tournament_participants
    SET registration_status = 'withdrawn',
        withdrew_at         = now()
    WHERE id = p_participant_id;

  INSERT INTO public.tournament_audit_events(
      tournament_id, kind, actor_user_id, payload)
    VALUES (
      v_tournament_id,
      'withdrawn',
      v_caller,
      jsonb_build_object(
        'participant_id', p_participant_id,
        'prior_status',   v_prior
      )
    );

  -- DYNAMIC PROMOTION: only a CONFIRMED withdrawal frees a real slot. A
  -- waitlist withdrawal changes nothing for the confirmed pool, so we do
  -- nothing extra. Promote the OLDEST waitlisted participant
  -- (ORDER BY registered_at, id) and lock that row to avoid a double-promote
  -- race with a concurrent withdrawal in the same tournament.
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
            'participant_id',     v_promoted_id,
            'freed_by',           p_participant_id
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
END;
$$
;

GRANT EXECUTE ON FUNCTION public.tournament_withdraw(uuid) TO authenticated
;

-- ====================================================================
-- 2. tournament_list_my_registrations — verbatim re-base von 20260901000004.
--    EINZIGE Änderung: die WHERE-Klausel deckt zusätzlich zu den eigenen
--    Solo-Zeilen jene Team-Zeilen ab, in deren Team der Aufrufer aktives
--    Pool-Mitglied ist (dasselbe Prädikat wie im Withdraw-Gate).
-- ====================================================================

CREATE OR REPLACE FUNCTION public.tournament_list_my_registrations(
  p_limit int DEFAULT 50
)
RETURNS SETOF jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller uuid;
  v_limit  int;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  v_limit := COALESCE(p_limit, 50);
  IF v_limit < 1 OR v_limit > 500 THEN
    RAISE EXCEPTION 'limit out of range' USING ERRCODE = '22023';
  END IF;

  RETURN QUERY
    SELECT jsonb_build_object(
             'tournament_id',       t.id,
             'created_by',          t.created_by,
             'display_name',        t.display_name,
             'format',              t.format,
             'status',              t.status,
             'started_at',          t.started_at,
             'completed_at',        t.completed_at,
             'participant_count',   (
               SELECT count(*)::int FROM public.tournament_participants pc
                WHERE pc.tournament_id = t.id
                  AND pc.registration_status = 'confirmed'
             ),
             'participant_id',      p.id,
             'registration_status', p.registration_status
           )
      FROM public.tournament_participants p
      JOIN public.tournaments t ON t.id = p.tournament_id
     WHERE (
             p.user_id = v_caller
             OR (
               p.team_id IS NOT NULL
               AND EXISTS (
                 SELECT 1 FROM public.team_memberships tm
                  WHERE tm.team_id = p.team_id
                    AND tm.user_id = v_caller
                    AND tm.removed_at IS NULL
               )
             )
           )
       AND p.registration_status IN ('pending', 'confirmed', 'waitlist')
     ORDER BY t.started_at DESC NULLS FIRST, t.created_at DESC
     LIMIT v_limit;
END;
$$
;

GRANT EXECUTE ON FUNCTION public.tournament_list_my_registrations(int)
  TO authenticated
;

