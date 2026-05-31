-- Tournament feature — P6 setup fields (Phase 0: data model).
--
-- The M1 schema (20260525000001) only carried the bare minimum a
-- tournament header needs: name, sizes, format, one match_format
-- blob, tiebreaker order, bye/forfeit points, status and the
-- lifecycle timestamps. The P6 setup wizard (Screens 1-3) needs a
-- much richer header: organiser meta (location, date, fees, contact,
-- info blocks, PDFs), the league A/B/C categories, a SEPARATE KO
-- match-format (decision: "Vorrunde + KO getrennt"), the rule
-- variants the organiser mails toggle (sureshot/diggy/2-4-6), the
-- pitch plan, plus the Mighty-Finisher qualification and consolation
-- bracket configs.
--
-- This migration is purely ADDITIVE: every column is nullable or has
-- a default, and the canonical `match_format` column keeps its M1
-- meaning (now explicitly the PRELIM/group format). `ko_match_format`
-- is NULL until set; consumers fall back to `match_format` when it is
-- NULL. No existing RPC or read path changes here — wiring the
-- create-RPC to populate these lands with Screen 1 (Phase 1).

-- ---- 1. Organiser meta ------------------------------------------------

ALTER TABLE public.tournaments
  ADD COLUMN location            text NULL,
  ADD COLUMN venue_address       text NULL,
  ADD COLUMN event_starts_at     timestamptz NULL,
  -- On-site check-in deadline (Speakerpult "Anmeldung bis"), distinct
  -- from the in-app registration_closes_at deadline.
  ADD COLUMN checkin_until       timestamptz NULL,
  ADD COLUMN weather_note        text NULL,
  ADD COLUMN info_food           text NULL,
  ADD COLUMN info_travel         text NULL,
  ADD COLUMN info_accommodation  text NULL,
  ADD COLUMN contact_name        text NULL,
  ADD COLUMN contact_phone       text NULL,
  ADD COLUMN entry_fee_cents     int NULL CHECK (entry_fee_cents IS NULL OR entry_fee_cents >= 0),
  ADD COLUMN currency            text NOT NULL DEFAULT 'CHF',
  -- Allowed payment methods; subset of the fixed vocabulary. Every
  -- organiser mail offers some combination of cash / Twint / card.
  ADD COLUMN payment_methods     text[] NOT NULL DEFAULT '{}'::text[]
    CHECK (payment_methods <@ ARRAY['cash','twint','card']::text[]),
  -- Uploaded PDFs (Supabase Storage object paths/URLs). Buckets and
  -- RLS are created in the Screen-1 migration when the upload UI lands.
  ADD COLUMN rules_pdf_url       text NULL,
  ADD COLUMN site_map_pdf_url    text NULL;

-- ---- 2. League categories (A/B/C, multi-select) -----------------------

ALTER TABLE public.tournaments
  ADD COLUMN league_categories   text[] NOT NULL DEFAULT '{}'::text[]
    CHECK (league_categories <@ ARRAY['A','B','C']::text[]);

-- ---- 3. Rule variants + separate KO match format ----------------------
--
-- `rule_variants` mirrors the toggles every organiser mail states:
--   { "sureshot": bool,           -- false = king may be felled normally
--     "diggy": bool,              -- Diggy / double-award-kubb rule on
--     "opening_rule": "2-4-6",    -- Anspielregel
--     "strafkubb_off_baseline": bool }  -- penalty kubb min one stick off baseline
-- `scoring` (ekc/classic) stays its own column from M1.

ALTER TABLE public.tournaments
  ADD COLUMN rule_variants jsonb NOT NULL DEFAULT jsonb_build_object(
    'sureshot', false,
    'diggy', false,
    'opening_rule', '2-4-6',
    'strafkubb_off_baseline', true
  ),
  -- Separate match rules for the KO phase. NULL => fall back to
  -- `match_format`. Same shape as match_format plus `final_no_tiebreak`
  -- (covers the common "ab Halbfinale ohne Tiebreak" without going to a
  -- full per-KO-round model). Shape:
  --   { "sets_to_win", "max_sets", "time_limit_seconds",
  --     "tiebreak_enabled", "tiebreak_after_seconds",
  --     "break_between_matches_seconds", "basekubbs_per_side",
  --     "final_no_tiebreak" }
  ADD COLUMN ko_match_format jsonb NULL;

-- ---- 4. Pitch plan ----------------------------------------------------
--
-- A venue has N pitches with arbitrary numbering, split across parallel
-- A/B/C tournaments. Shape:
--   { "mode": "range" | "manual",
--     "range_from": int, "range_to": int,        -- when mode=range
--     "numbers": [int, ...],                      -- when mode=manual
--     "order": [int, ...],                        -- explicit display order
--     "sort_strategy": "top_seeds_low_numbers" | "manual",
--     "group_assignment": { "A": [int,...], "B": [int,...] } }  -- pool phase

ALTER TABLE public.tournaments
  ADD COLUMN pitch_plan jsonb NULL;

-- ---- 5. Mighty-Finisher qualification + consolation bracket -----------
--
-- mighty_finisher_quali — shootout as a QUALIFICATION stage between the
-- group phase and the KO (Wasserschloss model: group runner-ups shoot
-- out for the remaining KO slots). Shape:
--   { "enabled": bool, "slots": int, "source": "group_runner_ups" }
--
-- consolation_bracket — a second KO bracket for players knocked out in
-- the early KO rounds (Bâton Rouille / "Best of the Rest"). Shape:
--   { "enabled": bool, "source_rounds": [int,...],
--     "match_format": { ...same shape as ko_match_format... } }

ALTER TABLE public.tournaments
  ADD COLUMN mighty_finisher_quali jsonb NULL,
  ADD COLUMN consolation_bracket   jsonb NULL;

-- ---- 6. Notes ---------------------------------------------------------
--
-- No new indices: all new columns are read alongside the already-indexed
-- header row (single-row lookups by id / status). RLS is unchanged — the
-- existing tournaments_* policies already gate the whole row, and these
-- columns ride along. The updated_at trigger keeps firing on UPDATE.
