-- SRV-06 / C8-T1 (Phase P6, ADR-0029 §Unified Messaging):
-- The inbox push-seam — an AFTER-INSERT fan-out trigger on
-- public.user_inbox_messages.
--
-- "One write, two wakes": a single durable inbox write must wake the
-- client through TWO independent paths.
--   1. Foreground wake  : the Postgres CDC publication membership from P1
--      (20261213000000_cdc_user_inbox_messages.sql) already streams the
--      row-level change to the open per-user RealtimeChannel. THAT path is
--      the live foreground source and is left completely untouched here.
--   2. Push wake (seam)  : this migration adds a PII-FREE broadcast nudge
--      via realtime.send() that is the seam for a FUTURE OS-level push
--      delivery. Today no client consumes this nudge; the push half is a
--      pure stub/no-op (see §2 below). No real push, no edge-function call,
--      no HTTP / pg_net.
--
-- Pattern source for realtime.send + SECURITY DEFINER:
-- 20260601000031_public_tournament_realtime.sql.
--
-- PII-Leak-Risk (plan §(h)): an inbox row carries sensitive payload
-- (body, action_payload, reply_payload) and addressing PII (user_id,
-- created_by, email, nickname). The broadcast nudge therefore uses a
-- STRICT column whitelist — only the four non-sensitive descriptor fields
-- id / kind / subject / sent_at travel in the payload. The user_id is used
-- ONLY to address the per-recipient topic name, never inside the payload.


-- ---- 1. push_outbox stub table (no-op seam) --------------------------
--
-- This table is the durable hand-off point for a LATER push phase
-- (P8 / token-table + edge-function). It is created additively as a STUB:
-- the trigger below does NOT write to it yet (TODO marker in the function
-- body). RLS is enabled with NO client INSERT/UPDATE/DELETE/SELECT policy,
-- so only the service role can ever touch it — there is no client write
-- path. Keeping the table here makes the seam concrete and testable
-- without introducing any real delivery mechanism.

CREATE TABLE IF NOT EXISTS public.push_outbox (
  id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  payload      jsonb       NOT NULL,
  created_at   timestamptz NOT NULL DEFAULT now(),
  delivered_at timestamptz NULL
);

ALTER TABLE public.push_outbox ENABLE ROW LEVEL SECURITY;

-- Intentionally NO policies: the client never reads or writes push_outbox.
-- A future push phase will enqueue/dequeue rows under the service role.

COMMENT ON TABLE public.push_outbox IS
  'STUB / seam (SRV-06, ADR-0029 P6). Durable hand-off for a future '
  'OS-push phase. RLS on, no client policy. Not written yet — the '
  'inbox push-seam trigger only emits a PII-free realtime nudge today.';


-- ---- 2. Trigger function: tg_inbox_push_seam -------------------------
--
-- SECURITY DEFINER so the trigger can reach the realtime schema even when
-- the mutating caller (e.g. admin_inbox_send under service_role, or any
-- producer RPC owner) lacks direct realtime rights — same rationale as
-- public_tournament_emit_match_event in 20260601000031.

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

  -- TODO (push phase / P8): enqueue a public.push_outbox row here to drive
  -- real OS-push delivery via a token table + edge-function. Intentionally
  -- a NO-OP today — this is a pure seam, no real push is sent.

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.tg_inbox_push_seam() IS
  'SRV-06/C8-T1 (ADR-0029 P6): AFTER-INSERT push-seam on '
  'user_inbox_messages. Emits a PII-free realtime nudge (whitelist '
  'id/kind/subject/sent_at) on the private per-user topic user_push:<id>. '
  '"One write, two wakes": CDC (P1) wakes foreground, this nudge is the '
  'future-push seam. push_outbox enqueue is a documented no-op stub.';


-- ---- 3. Trigger binding ----------------------------------------------

DROP TRIGGER IF EXISTS inbox_push_seam_after_insert
  ON public.user_inbox_messages;
CREATE TRIGGER inbox_push_seam_after_insert
  AFTER INSERT
  ON public.user_inbox_messages
  FOR EACH ROW
  EXECUTE FUNCTION public.tg_inbox_push_seam();
