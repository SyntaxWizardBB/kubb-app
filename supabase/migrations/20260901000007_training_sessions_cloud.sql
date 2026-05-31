-- Cloud mirror of completed training sessions (P2).
--
-- Stores one aggregated row per completed session — not the per-throw event
-- log. That is enough to render a player's own history and a friend's stats,
-- and keeps the table small. The local drift store remains the source of
-- truth for live sessions; rows land here only on completion.
--
-- Visibility (P2): a session is readable by its owner and by the owner's
-- accepted friends. Owners may insert/update/delete their own rows (the
-- delete path backs the "Sessions löschen" requirement).

CREATE TABLE IF NOT EXISTS public.training_sessions (
  id           uuid        PRIMARY KEY,
  user_id      uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  mode         text        NOT NULL CHECK (mode IN ('sniper', 'finisseur')),
  -- Sniper aggregates.
  distance_m   numeric     NULL,
  hit_rate     integer     NULL CHECK (hit_rate BETWEEN 0 AND 100),
  throws       integer     NULL CHECK (throws >= 0),
  -- Finisseur aggregates.
  win          boolean     NULL,
  sticks_used  integer     NULL CHECK (sticks_used >= 0),
  field_target integer     NULL CHECK (field_target >= 0),
  base_target  integer     NULL CHECK (base_target >= 0),
  started_at   timestamptz NOT NULL,
  completed_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS training_sessions_user_idx
  ON public.training_sessions(user_id, completed_at DESC);

ALTER TABLE public.training_sessions ENABLE ROW LEVEL SECURITY;

-- Owner: full CRUD on their own sessions.
CREATE POLICY training_sessions_owner_all
  ON public.training_sessions FOR ALL
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- Accepted friends may read. Friendships are stored canonically with
-- low_user_id < high_user_id (see 20260507000001_social_graph.sql), so we
-- check both orderings against the caller.
CREATE POLICY training_sessions_friend_read
  ON public.training_sessions FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.friendships f
      WHERE f.status = 'accepted'
        AND (
          (f.low_user_id = auth.uid()  AND f.high_user_id = training_sessions.user_id)
          OR
          (f.high_user_id = auth.uid() AND f.low_user_id  = training_sessions.user_id)
        )
    )
  );

COMMENT ON TABLE public.training_sessions IS
  'Aggregated completed training sessions (P2). Readable by owner and accepted '
  'friends; writable only by the owner.';
