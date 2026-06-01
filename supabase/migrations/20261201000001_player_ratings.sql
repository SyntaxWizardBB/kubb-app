-- P6 "TournierStart" — ELO rating store (auto-seeding source).
--
-- Introduces `player_ratings`, the persistent per-user ELO used as the
-- seed source for ELO-based auto-seeding (P6_RULES_DECISIONS §I,
-- `seed_source = elo`, `elo_default = 1200`). Ratings are PUBLIC per spec
-- (anyone may read a player's rating), but only SECURITY DEFINER RPCs may
-- write — there is no direct-write RLS policy, so client INSERT/UPDATE
-- fail closed.
--
-- IMPORTANT — out of scope here (Phase 6): the actual ELO UPDATE after a
-- match is finalized is NOT implemented in this migration. Today ELO is
-- still hardcoded 1200 in the app (e.g. match_lobby_screen) and no row is
-- ever written to this table yet, so auto-seeding will currently resolve
-- every participant to the `elo_default` of 1200 and fall back to the
-- deterministic tie-break draw. The match→rating writer is a Phase 6 task.
--
-- ---- Dependencies (verified by reading) -------------------------------
--  * auth.users(id)
--      — referenced exactly as in tournament_participants.user_id,
--        20260525000001_tournament_schema.sql (l.47). No new dependency.
--  * No existing `public.player_ratings` object — confirmed absent by a
--    repo-wide grep over supabase/migrations/*.sql at authoring time.

-- ---- 1. Table ---------------------------------------------------------
--
-- One row per (user_id, discipline). `discipline` keeps the door open for
-- per-format ratings (e.g. 'solo','team') without a schema change; the
-- default 'overall' is the single bucket consumed by this phase's
-- auto-seeding. ELO is a plain int (no fractional ratings in this system),
-- defaulting to the binding neutral 1200.

CREATE TABLE public.player_ratings (
  user_id     uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  discipline  text        NOT NULL DEFAULT 'overall'
                            CHECK (length(discipline) BETWEEN 1 AND 32),
  elo         int         NOT NULL DEFAULT 1200 CHECK (elo >= 0),
  games       int         NOT NULL DEFAULT 0 CHECK (games >= 0),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT player_ratings_pkey PRIMARY KEY (user_id, discipline)
);

-- Supports the auto-seed lookup "give me the ELO for these N user_ids in
-- this discipline" (PK already covers (user_id, discipline); this index
-- speeds the discipline-scoped leaderboard read used by future surfaces).
CREATE INDEX player_ratings_discipline_elo_idx
  ON public.player_ratings(discipline, elo DESC);


-- ---- 2. RLS -----------------------------------------------------------
--
-- Public read (ratings are public per spec). No write policy at all: every
-- mutation must go through a SECURITY DEFINER RPC (Phase 6 ELO writer and
-- this phase's autoseed read-only consumer). This mirrors the
-- "RPC-only writes" pattern of tournament_matches / audit_events in
-- 20260525000001_tournament_schema.sql (l.137-152).

ALTER TABLE public.player_ratings ENABLE ROW LEVEL SECURITY;

CREATE POLICY player_ratings_public_read
  ON public.player_ratings FOR SELECT
  USING (true);

GRANT SELECT ON public.player_ratings TO anon, authenticated;

COMMENT ON TABLE public.player_ratings IS
  'Persistent per-user ELO (P6_RULES_DECISIONS §I, elo_default=1200). '
  'Public read; writes via SECURITY DEFINER RPC only. The match->ELO '
  'writer is a Phase 6 task — no rows are produced by this phase.';
