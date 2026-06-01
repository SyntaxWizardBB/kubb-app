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

-- ---- 2b. Team size range ----------------------------------------------
-- The M1 `team_size` column is the MINIMUM players per team; this adds
-- the MAXIMUM. NULL = fixed-size team (max equals team_size). A solo
-- tournament is team_size = max_team_size = 1.
ALTER TABLE public.tournaments
  ADD COLUMN max_team_size smallint NULL
    CHECK (max_team_size IS NULL OR max_team_size BETWEEN 1 AND 6);

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

-- ---- 5c. Pool-phase config (hybrid formats) ---------------------------
--
-- pool_phase_config — the organiser's chosen pool grouping for hybrid
-- formats (round_robin/schoch/swiss → KO). Stored at create so the
-- pool-generation RPC (`_tournament_compute_pools`) can read the same
-- shape it already accepts as `p_config`. NULL for pure formats. Shape:
--   { "group_count": int, "qualifiers_per_group": int,
--     "strategy": "snake"|"random"|"seeded", "random_seed": int? }
-- (ko_config already exists from 20260601000010_tournament_ko_phase.)
ALTER TABLE public.tournaments
  ADD COLUMN pool_phase_config jsonb NULL;

-- ---- 5b. KO bracket setup choices (P6 Phase 3) ------------------------
-- bracket_type        — single vs double elimination (per P6_RULES_DECISIONS D)
-- ko_matchup          — seeding pattern for the bracket (decision C)
-- ko_tiebreak_method  — how a tied KO match is decided (decision B)
ALTER TABLE public.tournaments
  ADD COLUMN bracket_type       text NOT NULL DEFAULT 'single_elimination'
    CHECK (bracket_type IN ('single_elimination','double_elimination')),
  ADD COLUMN ko_matchup         text NOT NULL DEFAULT 'seed_high_vs_low'
    CHECK (ko_matchup IN ('seed_high_vs_low','one_vs_two')),
  ADD COLUMN ko_tiebreak_method text NOT NULL DEFAULT 'classic_kingtoss_removal'
    CHECK (ko_tiebreak_method IN (
      'classic_kingtoss_removal','mighty_finisher_shootout'));

-- ---- 6. Notes ---------------------------------------------------------
--
-- No new indices: all new columns are read alongside the already-indexed
-- header row (single-row lookups by id / status). RLS is unchanged — the
-- existing tournaments_* policies already gate the whole row, and these
-- columns ride along. The updated_at trigger keeps firing on UPDATE.
