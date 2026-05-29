-- W3-T5 (Sprint-C): Realtime-Updates fuer den anon-Spectator-Pfad.
--
-- Schliesst das Followup aus `docs/plans/sprint-a-bug-fix/anon-rls-plan.md`
-- T6 und implementiert die in ADR-0026 §Consequences "Realtime fuer anon"
-- skizzierte Strategie. Heute ist der PublicTournamentScreen rein
-- Pull-basiert; diese Migration fuehrt dedizierte Realtime-Broadcast-
-- Events ueber `realtime.send()` ein, ohne die `tournament_*`-Tabellen
-- selbst in die `supabase_realtime`-Publication zu nehmen (das wuerde
-- das gesamte Zeilen-Set an alle anonymen Subscriber leaken).
--
-- Architektur:
--
--   * Pro Turnier ein eigener Realtime-Topic mit dem Namen
--     `public_tournament_events:<tournament_id>`. Anonyme Clients
--     subscriben mit `private: false`, kein JWT noetig (vgl. ADR-0026
--     §Alternatives B "Realtime-Argument zieht nicht mehr").
--
--   * Ein AFTER-Trigger auf `tournament_matches` feuert beim Status-
--     Wechsel (`status` alt != neu) und schreibt ein `match_status`-
--     Event mit explizit whitelisted Spalten: match_id, tournament_id,
--     round_number, match_number_in_round, status (alt + neu),
--     participant_a_id, participant_b_id, winner_participant_id,
--     final_score_a, final_score_b, phase, bracket_position, started_at,
--     completed_at. KEIN `created_by`, KEIN `submitter_user_id`, KEIN
--     `user_id`.
--
--   * Ein AFTER-INSERT-Trigger auf `tournament_set_score_proposals`
--     feuert ein `proposal_created`-Event, das nur match_id,
--     tournament_id, consensus_round und set_number transportiert.
--     Bewusst KEIN submitter_user_id, basekubbs_*, set_winner — der
--     anonyme Spectator soll wissen "es bewegt sich was", nicht wer
--     was vorgeschlagen hat.
--
-- Der Trigger ist `SECURITY DEFINER`, damit er auch dann durchlaeuft,
-- wenn der mutierende Caller (RPC-Owner) keine direkten Rechte auf das
-- `realtime`-Schema hat. Pre-Check: nur Turniere mit `public = true`
-- und einem sichtbaren Lifecycle-Status emittieren Events.
--
-- Sources: ADR-0026 §Consequences "Realtime fuer anon",
--          docs/plans/sprint-a-bug-fix/anon-rls-plan.md T6 Followup.


-- ---- 1. Topic-Name-Helper --------------------------------------------
--
-- Eine zentrale Funktion liefert den Topic-Namen pro Turnier-ID, sodass
-- Trigger und Client denselben Namensraum nutzen und ein Drift sofort
-- in den Tests auffaellt.

CREATE OR REPLACE FUNCTION public.public_tournament_realtime_topic(
  p_tournament_id uuid
) RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT 'public_tournament_events:' || p_tournament_id::text;
$$;

COMMENT ON FUNCTION public.public_tournament_realtime_topic(uuid) IS
  'Dedizierter Realtime-Topic-Name fuer den anon-Spectator-Pfad. '
  'Trigger und Client konsumieren denselben Namensraum.';


-- ---- 2. Visibility-Helper --------------------------------------------
--
-- Trigger emittieren nur fuer Turniere, die schon ueber die
-- `public_*_get`-RPCs sichtbar waeren. Konstanten-Liste aus ADR-0026
-- §Decision §2.

CREATE OR REPLACE FUNCTION public.public_tournament_is_visible(
  p_tournament_id uuid
) RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
      FROM public.tournaments
     WHERE id = p_tournament_id
       AND public = true
       AND status IN (
         'published',
         'registration_open',
         'registration_closed',
         'live',
         'finalized'
       )
  );
$$;

COMMENT ON FUNCTION public.public_tournament_is_visible(uuid) IS
  'Spiegelt die Visibility-Bedingung der public_tournament_get-RPC. '
  'Realtime-Trigger emittieren nur, wenn diese Funktion true zurueckgibt.';


-- ---- 3. Trigger-Funktion: tournament_matches.status -> match_status --

CREATE OR REPLACE FUNCTION public.public_tournament_emit_match_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, realtime
AS $$
DECLARE
  v_topic   text;
  v_payload jsonb;
BEGIN
  -- Nur Status-Wechsel emittieren. UPDATEs ohne Statusaenderung sind
  -- haeufig (Score-Patches in `awaiting_results`); der Spectator-Tab
  -- braucht sie nicht. INSERTs sind ebenfalls relevant (neuer Match-
  -- Eintrag im Spielplan), darum nicht auf UPDATE einschraenken.
  IF TG_OP = 'UPDATE'
     AND NEW.status IS NOT DISTINCT FROM OLD.status
     AND NEW.winner_participant IS NOT DISTINCT FROM OLD.winner_participant
     AND NEW.final_score_a IS NOT DISTINCT FROM OLD.final_score_a
     AND NEW.final_score_b IS NOT DISTINCT FROM OLD.final_score_b THEN
    RETURN NEW;
  END IF;

  IF NOT public.public_tournament_is_visible(NEW.tournament_id) THEN
    RETURN NEW;
  END IF;

  v_topic := public.public_tournament_realtime_topic(NEW.tournament_id);

  -- Explizite Spalten-Whitelist: KEIN created_by / submitter_user_id /
  -- user_id. Die hier projektierten Felder spiegeln 1:1 das, was die
  -- `public_tournament_get`-RPC im `matches[]`-Array liefert.
  v_payload := jsonb_build_object(
    'event_type',            'match_status',
    'match_id',              NEW.id,
    'tournament_id',         NEW.tournament_id,
    'round_number',          NEW.round_number,
    'match_number_in_round', NEW.match_number_in_round,
    'status',                NEW.status,
    'previous_status',
      CASE WHEN TG_OP = 'UPDATE' THEN OLD.status ELSE NULL END,
    'consensus_round',       NEW.consensus_round,
    'participant_a_id',      NEW.participant_a,
    'participant_b_id',      NEW.participant_b,
    'winner_participant_id', NEW.winner_participant,
    'final_score_a',         NEW.final_score_a,
    'final_score_b',         NEW.final_score_b,
    'phase',                 NEW.phase,
    'bracket_position',      NEW.bracket_position,
    'started_at',            NEW.started_at,
    'completed_at',          NEW.finalized_at,
    'emitted_at',            now()
  );

  PERFORM realtime.send(
    v_payload,
    'match_status',  -- event name
    v_topic,         -- topic
    false            -- private=false -> anon-readable
  );

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.public_tournament_emit_match_event() IS
  'Emittiert ein match_status-Event in den public_tournament_events-Topic. '
  'Spalten-Whitelist explizit gepflegt; KEIN PII-Leak. ADR-0026 Realtime.';


-- ---- 4. Trigger-Funktion: tournament_set_score_proposals -> proposal -

CREATE OR REPLACE FUNCTION public.public_tournament_emit_proposal_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, realtime
AS $$
DECLARE
  v_tournament_id uuid;
  v_topic         text;
  v_payload       jsonb;
BEGIN
  SELECT m.tournament_id
    INTO v_tournament_id
    FROM public.tournament_matches m
   WHERE m.id = NEW.match_id;

  IF v_tournament_id IS NULL THEN
    RETURN NEW;
  END IF;

  IF NOT public.public_tournament_is_visible(v_tournament_id) THEN
    RETURN NEW;
  END IF;

  v_topic := public.public_tournament_realtime_topic(v_tournament_id);

  -- Spalten-Whitelist: bewusst KEIN submitter_user_id, KEIN
  -- basekubbs_knocked_by_a/b, KEIN set_winner. Der anonyme Spectator
  -- soll nur das Signal "im Match bewegt sich was" bekommen; der
  -- konkrete Score-Vorschlag bleibt authentifizierten Teilnehmern
  -- vorbehalten.
  v_payload := jsonb_build_object(
    'event_type',      'proposal_created',
    'match_id',        NEW.match_id,
    'tournament_id',   v_tournament_id,
    'consensus_round', NEW.consensus_round,
    'set_number',      NEW.set_number,
    'emitted_at',      now()
  );

  PERFORM realtime.send(
    v_payload,
    'proposal_created',
    v_topic,
    false
  );

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.public_tournament_emit_proposal_event() IS
  'Emittiert ein proposal_created-Event in den public_tournament_events-Topic. '
  'KEIN submitter_user_id, KEIN basekubbs-Score. ADR-0026 Realtime.';


-- ---- 5. Trigger-Bindings ---------------------------------------------

DROP TRIGGER IF EXISTS public_tournament_emit_match_event
  ON public.tournament_matches;
CREATE TRIGGER public_tournament_emit_match_event
  AFTER INSERT OR UPDATE
  ON public.tournament_matches
  FOR EACH ROW
  EXECUTE FUNCTION public.public_tournament_emit_match_event();

DROP TRIGGER IF EXISTS public_tournament_emit_proposal_event
  ON public.tournament_set_score_proposals;
CREATE TRIGGER public_tournament_emit_proposal_event
  AFTER INSERT
  ON public.tournament_set_score_proposals
  FOR EACH ROW
  EXECUTE FUNCTION public.public_tournament_emit_proposal_event();


-- ---- 6. Grants -------------------------------------------------------
--
-- `realtime.send()` braucht keinen GRANT fuer den anon-Empfaenger; das
-- Topic ist nicht-privat (siehe `false` im send()-Aufruf). Wir machen
-- den Visibility-Helper bewusst fuer beide Rollen executable, damit
-- pgTAP-Tests unter der anon-Rolle ihn rufen koennen.

GRANT EXECUTE ON FUNCTION public.public_tournament_realtime_topic(uuid)
  TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.public_tournament_is_visible(uuid)
  TO anon, authenticated;
