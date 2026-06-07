-- SRV-05 / C2-T1 (ADR-0029 §9, messaging-framework-plan §(d) + §(h)): migrate the
-- friends list off the 1 s discovery poll onto real CDC.
--
-- Problem: public.friendships is stored CANONICALLY as (low_user_id, high_user_id)
-- with a CHECK (low < high), so there is NO single-column owner filter a per-user
-- CDC subscription can use. Realtime can only filter on one indexed column, and
-- neither low_user_id nor high_user_id maps cleanly to "rows that concern me".
--
-- Solution: a denormalised, owner-scaled public.friend_edges table holding TWO
-- rows per friendship — (A,B) and (B,A) — kept in sync by a SECURITY DEFINER
-- trigger on friendships. The client then subscribes to one per-user CDC channel
-- friend_edges:owner_user_id=<uid> (mirrors inbox/team patterns). The status
-- column is mirrored so a pending->accepted change on friendships becomes a real
-- column change on friend_edges and thus emits a CDC event.

-- ---- 1. Table ---------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.friend_edges (
  owner_user_id  uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  friend_user_id uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  -- status mirrors friendships.status; the CHECK is kept in lock-step with
  -- social_graph.sql so the denormalised copy can never drift to a value the
  -- canonical table forbids. Writes flow only via the trigger/backfill below,
  -- so this is a defence-in-depth invariant, not a client-facing guard.
  status         text        NOT NULL,
  updated_at     timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (owner_user_id, friend_user_id),
  CONSTRAINT friend_edges_status_check CHECK (status IN (
    'pending', 'accepted', 'rejected', 'blocked'
  ))
);

-- Non-unique index on the CDC filter column. owner_user_id leads the PK so the
-- PK index already serves equality lookups, but an explicit index documents the
-- access pattern and matches the social_graph.sql convention.
CREATE INDEX IF NOT EXISTS friend_edges_owner_idx
  ON public.friend_edges(owner_user_id);

-- ---- 2. Trigger function (both directions) ----------------------------
--
-- SECURITY DEFINER so the maintenance runs with table-owner rights regardless of
-- the caller's RLS (the only client write path to friendships is the existing
-- SECURITY DEFINER RPCs; this trigger fans those out to friend_edges).
CREATE OR REPLACE FUNCTION public.friend_edges_sync()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF (TG_OP = 'DELETE') THEN
    DELETE FROM public.friend_edges
      WHERE (owner_user_id = OLD.low_user_id  AND friend_user_id = OLD.high_user_id)
         OR (owner_user_id = OLD.high_user_id AND friend_user_id = OLD.low_user_id);
    RETURN OLD;
  END IF;

  -- INSERT or UPDATE: upsert both directions carrying the current status. On an
  -- UPDATE that flips friendships.status (pending->accepted) the ON CONFLICT
  -- branch rewrites status + updated_at on both edges, which is the CDC trigger.
  INSERT INTO public.friend_edges(owner_user_id, friend_user_id, status, updated_at)
    VALUES
      (NEW.low_user_id,  NEW.high_user_id, NEW.status, now()),
      (NEW.high_user_id, NEW.low_user_id,  NEW.status, now())
    ON CONFLICT (owner_user_id, friend_user_id) DO UPDATE
      SET status = EXCLUDED.status, updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS friend_edges_sync_trg ON public.friendships;
CREATE TRIGGER friend_edges_sync_trg
  AFTER INSERT OR UPDATE OR DELETE ON public.friendships
  FOR EACH ROW EXECUTE FUNCTION public.friend_edges_sync();

-- ---- 3. Backfill (additive INSERT..SELECT) ----------------------------
--
-- Two rows per existing friendship, both directions. ON CONFLICT DO NOTHING keeps
-- the statement idempotent and strictly additive (no DELETE/TRUNCATE/seed).
INSERT INTO public.friend_edges(owner_user_id, friend_user_id, status)
  SELECT low_user_id,  high_user_id, status FROM public.friendships
  UNION ALL
  SELECT high_user_id, low_user_id,  status FROM public.friendships
  ON CONFLICT (owner_user_id, friend_user_id) DO NOTHING;

-- ---- 4. Realtime publication ------------------------------------------
--
-- owner_user_id is part of the PK, so REPLICA IDENTITY DEFAULT already carries
-- the filter column on INSERT/UPDATE/DELETE wire events — no REPLICA IDENTITY
-- FULL required.
ALTER PUBLICATION supabase_realtime ADD TABLE public.friend_edges;

-- ---- 5. RLS — owner isolation -----------------------------------------
--
-- A user sees only their own edge rows; this both authorises the CDC filter and
-- prevents leaking the social graph. Writes happen ONLY via the SECURITY DEFINER
-- trigger above, so no INSERT/UPDATE/DELETE policy is granted to clients.
ALTER TABLE public.friend_edges ENABLE ROW LEVEL SECURITY;
CREATE POLICY friend_edges_owner_read
  ON public.friend_edges FOR SELECT
  USING (owner_user_id = auth.uid());
