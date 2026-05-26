-- Tournament feature — M2 KO-Sieger-Fortschreibung via Trigger.
--
-- AFTER-UPDATE-Trigger auf `tournament_matches`. Feuert wenn ein
-- KO-Match (`phase IN ('ko','third_place','final')`) auf
-- `finalized`/`overridden` wechselt. Schreibt den Sieger ins
-- Folge-Match (round_number+1, ceil(bracket_position/2)) und —
-- bei aktivem `with_third_place_playoff` — den Halbfinal-Verlierer
-- ins Third-Place-Match.
--
-- Bezug: ADR-0017 §5, docs/plans/m2-ko-bracket/tasks.md T4,
--        R-M2.2-2 (Race mit Konsens-Pfad: kein Race, Trigger läuft
--        AFTER UPDATE in derselben Transaktion wie finalisierende
--        RPC), R-M2.2-3 (Forfeit/Walkover).
--
-- Slot-Mapping:
--   bracket_position ungerade → Sieger nach `participant_a`.
--   bracket_position gerade   → Sieger nach `participant_b`.
--
-- Walkover/Forfeit: liest nur `winner_participant`; final_score_a/b
-- werden nicht benötigt. Forfeit-Path ist datenmodell-kompatibel
-- ohne Sonderlogik. (Loser-Mapping winner==a → loser=b identisch.)
--
-- Status-Promotion: Folge-Match-Status `scheduled` → `awaiting_results`
-- sobald beide Slots gefüllt sind.
--
-- Recursion-Schutz: Trigger updated nur *andere* Match-Rows; das
-- Folge-Update setzt nur `participant_a/b` und ggf. `status` auf
-- `awaiting_results` — kein erneuter Wechsel auf finalized/overridden,
-- daher feuert die WHEN-Bedingung nicht rekursiv. Zusätzlich
-- schliesst `OLD.status NOT IN ('finalized','overridden')` Re-Fires
-- bereits finalisierter Matches aus.
--
-- SECURITY INVOKER: die auslösende UPDATE-Anweisung stammt aus
-- `tournament_propose_set_scores` oder `tournament_organizer_override`
-- (beide SECURITY DEFINER, RLS-geprüft). Der Trigger erbt den Kontext.

CREATE OR REPLACE FUNCTION public.tournament_advance_ko_winner()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, auth
AS $$
DECLARE
  v_loser_part      uuid;
  v_next_round      int;
  v_next_position   int;
  v_is_odd          boolean;
  v_third_enabled   boolean;
  v_final_round     int;
  v_next_a          uuid;
  v_next_b          uuid;
  v_next_status     text;
  v_tp_a            uuid;
  v_tp_b            uuid;
  v_tp_status       text;
BEGIN
  -- Defensive: winner_participant darf bei phase IN ('ko','third_place','final')
  -- nicht NULL sein, wenn der Match finalisiert/overridden wird.
  -- (Trigger ohne Sieger hat nichts fortzuschreiben.)
  IF NEW.winner_participant IS NULL THEN
    RETURN NEW;
  END IF;

  -- Loser für Third-Place-Propagation berechnen (siehe §5 Punkt 4).
  v_loser_part := CASE
    WHEN NEW.winner_participant = NEW.participant_a THEN NEW.participant_b
    WHEN NEW.winner_participant = NEW.participant_b THEN NEW.participant_a
    ELSE NULL  -- defensiv: inkonsistente Daten
  END;

  v_next_round    := NEW.round_number + 1;
  v_next_position := (NEW.bracket_position + 1) / 2;  -- ceil(x/2) für x>=1
  v_is_odd        := (NEW.bracket_position % 2) = 1;

  -- ---- 1. Sieger ins Folge-Match (phase 'ko' oder 'final') ----------
  -- Third-Place-Match teilt sich (round, position=1) mit dem Finale,
  -- wird aber via `phase IN ('ko','final')` ausgeschlossen. Ein
  -- third_place-Match propagiert seinen Sieger NICHT weiter.
  IF NEW.phase IN ('ko','final') THEN
    SELECT participant_a, participant_b, status
      INTO v_next_a, v_next_b, v_next_status
      FROM public.tournament_matches
      WHERE tournament_id = NEW.tournament_id
        AND round_number  = v_next_round
        AND bracket_position = v_next_position
        AND phase IN ('ko','final')
      FOR UPDATE;

    IF FOUND THEN
      IF v_is_odd THEN
        v_next_a := NEW.winner_participant;
      ELSE
        v_next_b := NEW.winner_participant;
      END IF;

      -- Status-Promotion: scheduled → awaiting_results sobald beide
      -- Slots gefüllt sind.
      IF v_next_a IS NOT NULL AND v_next_b IS NOT NULL
         AND v_next_status = 'scheduled' THEN
        v_next_status := 'awaiting_results';
      END IF;

      UPDATE public.tournament_matches
        SET participant_a = v_next_a,
            participant_b = v_next_b,
            status        = v_next_status
        WHERE tournament_id = NEW.tournament_id
          AND round_number  = v_next_round
          AND bracket_position = v_next_position
          AND phase IN ('ko','final');
    END IF;
  END IF;

  -- ---- 2. Halbfinal-Verlierer ins Third-Place-Match ------------------
  -- Halbfinale = phase 'ko' UND nächste Runde ist die Final-Runde.
  -- Third-Place-Match: round_number = final_round, bracket_position = 1,
  -- phase = 'third_place'. Slot-Mapping: bracket_position des
  -- Halbfinales bestimmt a/b analog zur Sieger-Logik.
  IF NEW.phase = 'ko' AND v_loser_part IS NOT NULL THEN
    SELECT (t.ko_config ->> 'with_third_place_playoff')::boolean
      INTO v_third_enabled
      FROM public.tournaments t
      WHERE t.id = NEW.tournament_id;

    IF COALESCE(v_third_enabled, false) THEN
      -- Final-Runde bestimmen: max(round_number) über phase='final'.
      SELECT MAX(round_number)
        INTO v_final_round
        FROM public.tournament_matches
        WHERE tournament_id = NEW.tournament_id
          AND phase = 'final';

      IF v_final_round IS NOT NULL AND v_next_round = v_final_round THEN
        SELECT participant_a, participant_b, status
          INTO v_tp_a, v_tp_b, v_tp_status
          FROM public.tournament_matches
          WHERE tournament_id    = NEW.tournament_id
            AND round_number     = v_final_round
            AND bracket_position = 1
            AND phase            = 'third_place'
          FOR UPDATE;

        IF FOUND THEN
          IF v_is_odd THEN
            v_tp_a := v_loser_part;
          ELSE
            v_tp_b := v_loser_part;
          END IF;

          IF v_tp_a IS NOT NULL AND v_tp_b IS NOT NULL
             AND v_tp_status = 'scheduled' THEN
            v_tp_status := 'awaiting_results';
          END IF;

          UPDATE public.tournament_matches
            SET participant_a = v_tp_a,
                participant_b = v_tp_b,
                status        = v_tp_status
            WHERE tournament_id    = NEW.tournament_id
              AND round_number     = v_final_round
              AND bracket_position = 1
              AND phase            = 'third_place';
        END IF;
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- WHEN-Clause kapselt den Phasen- und Status-Filter. Damit feuert
-- der Trigger nur auf relevanten Transitions und nicht bei jedem
-- Match-Update (z.B. Pitch-Zuweisung, consensus_round-Bump).
DROP TRIGGER IF EXISTS tournament_advance_ko_winner ON public.tournament_matches;
CREATE TRIGGER tournament_advance_ko_winner
  AFTER UPDATE ON public.tournament_matches
  FOR EACH ROW
  WHEN (
    OLD.status NOT IN ('finalized','overridden')
    AND NEW.status     IN ('finalized','overridden')
    AND NEW.phase      IN ('ko','third_place','final')
  )
  EXECUTE FUNCTION public.tournament_advance_ko_winner();

COMMENT ON FUNCTION public.tournament_advance_ko_winner() IS
  'AFTER-UPDATE-Trigger-Function: schreibt KO-Sieger ins Folge-Match '
  '(ADR-0017 §5). Halbfinal-Verlierer fliessen ins Third-Place-Match, '
  'wenn `tournaments.ko_config->>with_third_place_playoff = true`. '
  'Walkover/Forfeit-kompatibel: liest nur `winner_participant`, '
  'unabhaengig von `final_score_a/b`.';
