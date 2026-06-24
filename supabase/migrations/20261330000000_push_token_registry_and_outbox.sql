-- Push P1 — Token registry + outbox made real (SPEC docs/plans/push-notifications/SPEC.md).
--
-- Builds on the inbox push-seam stub (20261233000000_inbox_push_seam.sql):
--   * adds public.user_device_tokens (per-user FCM/APNs registration),
--   * sharpens public.push_outbox from a stub into a real delivery queue,
--   * flips tg_inbox_push_seam() from a documented no-op into an idempotent
--     enqueue (one durable outbox row per inbox message).
--
-- Band note: the SPEC drafted band 20261290000000, but parallel branches have
-- since advanced the applied migrations to 20261320000000. New migrations MUST
-- sort strictly after the highest applied one or `db push` rejects them as
-- out of order — hence 20261330000000.
--
-- Additive only; no destructive change. Delivery (edge function + pg_net +
-- pg_cron sweeper) is P2; this migration writes the queue, nothing reads it yet.


-- ---- 1. user_device_tokens -------------------------------------------
--
-- One row per (account, device-token). Token is globally UNIQUE so that a
-- device handed from account A to account B re-homes to B on re-register
-- (the RPC upsert below rewrites user_id). Writes go ONLY through the
-- SECURITY DEFINER RPCs — there is no client INSERT/UPDATE policy.

CREATE TABLE IF NOT EXISTS public.user_device_tokens (
  id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  platform     text        NOT NULL CHECK (platform IN ('android', 'ios')),
  token        text        NOT NULL,
  created_at   timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (token)
);

CREATE INDEX IF NOT EXISTS idx_user_device_tokens_user_id
  ON public.user_device_tokens (user_id);

ALTER TABLE public.user_device_tokens ENABLE ROW LEVEL SECURITY;

-- Owner-only read/delete. No INSERT/UPDATE policy: the register/unregister
-- RPCs (SECURITY DEFINER) are the only write path.
CREATE POLICY user_device_tokens_owner_select
  ON public.user_device_tokens FOR SELECT
  USING (user_id = auth.uid());

CREATE POLICY user_device_tokens_owner_delete
  ON public.user_device_tokens FOR DELETE
  USING (user_id = auth.uid());

COMMENT ON TABLE public.user_device_tokens IS
  'Push P1 (SPEC push-notifications). Per-user device push tokens '
  '(FCM/APNs). Token globally UNIQUE; re-register re-homes the token to '
  'the new account. Owner-only RLS read/delete; writes via SECURITY '
  'DEFINER RPCs push_register_device_token / push_unregister_device_token.';


-- ---- 2. Token RPCs ----------------------------------------------------

CREATE OR REPLACE FUNCTION public.push_register_device_token(
  p_platform text,
  p_token    text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'push_register_device_token: authentication required'
      USING errcode = '28000';
  END IF;
  IF p_platform NOT IN ('android', 'ios') THEN
    RAISE EXCEPTION 'push_register_device_token: invalid platform %', p_platform
      USING errcode = '22023';
  END IF;
  IF p_token IS NULL OR length(btrim(p_token)) = 0 THEN
    RAISE EXCEPTION 'push_register_device_token: token required'
      USING errcode = '22023';
  END IF;

  -- Upsert on the unique token. Same token re-registered (same or different
  -- account) → rewrite owner/platform and bump last_seen_at.
  INSERT INTO public.user_device_tokens (user_id, platform, token, last_seen_at)
  VALUES (auth.uid(), p_platform, p_token, now())
  ON CONFLICT (token) DO UPDATE
    SET user_id      = excluded.user_id,
        platform     = excluded.platform,
        last_seen_at = now();
END;
$$;

CREATE OR REPLACE FUNCTION public.push_unregister_device_token(
  p_token text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'push_unregister_device_token: authentication required'
      USING errcode = '28000';
  END IF;

  -- Only the caller's own token may be removed.
  DELETE FROM public.user_device_tokens
   WHERE token = p_token
     AND user_id = auth.uid();
END;
$$;

REVOKE ALL ON FUNCTION public.push_register_device_token(text, text) FROM public;
REVOKE ALL ON FUNCTION public.push_unregister_device_token(text)     FROM public;
GRANT EXECUTE ON FUNCTION public.push_register_device_token(text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.push_unregister_device_token(text)     TO authenticated;


-- ---- 3. push_outbox: stub -> real delivery queue ---------------------
--
-- Additive columns. The original stub (20261233000000) carried only
-- id/user_id/payload/created_at/delivered_at.

ALTER TABLE public.push_outbox
  ADD COLUMN IF NOT EXISTS inbox_message_id uuid,
  ADD COLUMN IF NOT EXISTS status           text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'delivered', 'failed', 'dead')),
  ADD COLUMN IF NOT EXISTS attempts         int  NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS next_attempt_at  timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS last_error       text;

-- Idempotency: at most one outbox row per inbox message. NULLs stay distinct
-- (legacy/non-inbox rows), so the enqueue ON CONFLICT below is exact.
ALTER TABLE public.push_outbox
  ADD CONSTRAINT uq_push_outbox_inbox_message_id UNIQUE (inbox_message_id);

-- Sweeper/claim index: P2 scans (status='pending'/'failed', next_attempt_at <= now()).
CREATE INDEX IF NOT EXISTS idx_push_outbox_status_next_attempt
  ON public.push_outbox (status, next_attempt_at);

COMMENT ON TABLE public.push_outbox IS
  'Push P1 (SPEC push-notifications). Durable delivery queue. One row per '
  'inbox message (idempotent via UNIQUE inbox_message_id). status: pending '
  '-> delivered | failed -> dead. RLS on, no client policy: only the '
  'service role (edge function push-deliver, P2) reads/claims rows.';


-- ---- 4. tg_inbox_push_seam(): no-op -> idempotent enqueue -------------
--
-- Re-based byte-for-byte from 20261233000000; the ONLY change is the TODO
-- no-op block (§2 there) replaced by the push_outbox enqueue. The PII-free
-- whitelist (id/kind/subject/sent_at) and the realtime nudge are unchanged.

CREATE OR REPLACE FUNCTION public.tg_inbox_push_seam()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, realtime
AS $$
DECLARE
  v_topic   text;
  v_payload jsonb;
BEGIN
  -- Per-recipient, user-addressed topic. The user_id appears ONLY in the
  -- topic name (addressing), NEVER in the payload body below.
  v_topic := 'user_push:' || NEW.user_id::text;

  -- STRICT PII whitelist. Only the four non-sensitive descriptor columns
  -- travel in the nudge: id, kind, subject, sent_at (plus constant meta).
  -- DELIBERATELY EXCLUDED: body, action_payload, reply_payload, read_at,
  -- replied_at, archived_at (sensitive payload) and user_id, created_by,
  -- email, nickname (addressing PII). Adding any of those here would
  -- re-introduce the §(h) PII-leak the seam exists to avoid.
  v_payload := jsonb_build_object(
    'event_type', 'inbox_push',
    'id',         NEW.id,
    'kind',       NEW.kind,
    'subject',    NEW.subject,
    'sent_at',    NEW.sent_at,
    'emitted_at', now()
  );

  -- Wake #2: PII-free broadcast nudge on the authenticated, user-private
  -- channel. private:=true -> this is an authenticated per-user channel,
  -- NOT an anon channel.
  PERFORM realtime.send(
    payload => v_payload,
    event   => 'inbox_push',    -- event name
    topic   => v_topic,         -- topic (user-addressed)
    private => true             -- private=true -> authenticated user channel, never anon
  );

  -- Wake #3 (push, P1): enqueue ONE durable push_outbox row with the SAME
  -- PII-free descriptor as the nudge. The edge function push-deliver (P2)
  -- claims it and sends the real OS push. Idempotent via the UNIQUE
  -- inbox_message_id constraint — a re-fired trigger never double-enqueues.
  INSERT INTO public.push_outbox (user_id, inbox_message_id, payload)
  VALUES (NEW.user_id, NEW.id, v_payload)
  ON CONFLICT (inbox_message_id) DO NOTHING;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.tg_inbox_push_seam() IS
  'SRV-06/C8-T1 (ADR-0029 P6) + Push P1: AFTER-INSERT push-seam on '
  'user_inbox_messages. Emits a PII-free realtime nudge (whitelist '
  'id/kind/subject/sent_at) on the private per-user topic user_push:<id> '
  'AND enqueues one idempotent push_outbox row (UNIQUE inbox_message_id) '
  'for OS-push delivery. "One write, two wakes": CDC wakes foreground, '
  'the outbox/edge-function path wakes background.';
