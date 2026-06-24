-- Push P2 — delivery wiring: claim/finalize helpers + pg_net webhook + cron.
--
-- SPEC: docs/plans/push-notifications/SPEC.md §P2. The edge function
-- push-deliver does the sending; this migration gives it (a) atomic SQL to
-- claim and finalize outbox rows and (b) two invokers — an AFTER-INSERT
-- pg_net webhook (low latency) and a pg_cron sweeper (reliability net).
--
-- "Armed" via Vault: the invoker reads the edge-function URL + service-role
-- key from vault.decrypted_secrets. Until BOTH secrets exist it is a no-op,
-- so this migration applies safely on every environment; delivery turns on
-- the moment the two secrets are set (per env). The invoker NEVER raises —
-- a vault/network hiccup must not roll back the inbox/outbox write.
--
-- Additive only. Depends on 20261330000000 (push_outbox columns, status).

CREATE EXTENSION IF NOT EXISTS pg_net;


-- ---- 1. Claim a batch of due rows (atomic lease) ---------------------
--
-- Leases rows by pushing next_attempt_at into the future under
-- FOR UPDATE SKIP LOCKED, so two concurrent edge invocations never grab the
-- same row. status is untouched here; the worker finalizes via the mark_*
-- functions. If the worker dies mid-flight the lease (2 min) expires and the
-- sweeper retries.

CREATE OR REPLACE FUNCTION public.push_claim_due(p_limit int DEFAULT 50)
RETURNS TABLE (id uuid, user_id uuid, payload jsonb, attempts int)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  UPDATE public.push_outbox o
     SET next_attempt_at = now() + interval '2 minutes'
   WHERE o.id IN (
     SELECT o2.id
       FROM public.push_outbox o2
      WHERE o2.status IN ('pending', 'failed')
        AND o2.next_attempt_at <= now()
      ORDER BY o2.next_attempt_at
      FOR UPDATE SKIP LOCKED
      LIMIT GREATEST(p_limit, 1)
   )
  RETURNING o.id, o.user_id, o.payload, o.attempts;
END;
$$;


-- ---- 2. Finalize: delivered / failed (backoff + dead-letter) ---------

CREATE OR REPLACE FUNCTION public.push_mark_delivered(p_id uuid)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  UPDATE public.push_outbox
     SET status = 'delivered', delivered_at = now(), last_error = NULL
   WHERE id = p_id;
$$;

CREATE OR REPLACE FUNCTION public.push_mark_failed(
  p_id            uuid,
  p_error         text,
  p_max_attempts  int DEFAULT 8
)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  UPDATE public.push_outbox
     SET attempts        = attempts + 1,
         last_error      = left(p_error, 500),
         status          = CASE WHEN attempts + 1 >= p_max_attempts
                                THEN 'dead' ELSE 'failed' END,
         -- exponential backoff on the OLD attempt count, capped at 60 min
         next_attempt_at = now()
                           + make_interval(mins => LEAST(power(2, attempts + 1)::int, 60))
   WHERE id = p_id;
$$;


-- ---- 3. Invoker (Vault-armed, never raises) --------------------------

CREATE OR REPLACE FUNCTION public.push_invoke_deliver()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, net, vault
AS $$
DECLARE
  v_url text;
  v_key text;
BEGIN
  SELECT decrypted_secret INTO v_url
    FROM vault.decrypted_secrets WHERE name = 'push_edge_url';
  SELECT decrypted_secret INTO v_key
    FROM vault.decrypted_secrets WHERE name = 'push_edge_service_key';

  -- Not armed yet -> no-op (safe on any env).
  IF v_url IS NULL OR v_key IS NULL THEN
    RETURN;
  END IF;

  PERFORM net.http_post(
    url     := v_url,
    headers := jsonb_build_object(
                 'Content-Type', 'application/json',
                 'Authorization', 'Bearer ' || v_key
               ),
    body    := jsonb_build_object('source', 'db')
  );
EXCEPTION WHEN OTHERS THEN
  -- A vault/network failure must NEVER break the triggering write.
  RAISE WARNING 'push_invoke_deliver suppressed: %', SQLERRM;
END;
$$;


-- ---- 4. AFTER-INSERT webhook on push_outbox (low latency) ------------

CREATE OR REPLACE FUNCTION public.tg_push_outbox_after_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.push_invoke_deliver();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS push_outbox_after_insert ON public.push_outbox;
CREATE TRIGGER push_outbox_after_insert
  AFTER INSERT ON public.push_outbox
  FOR EACH ROW
  EXECUTE FUNCTION public.tg_push_outbox_after_insert();


-- ---- 5. Cron sweeper (reliability net, only when work is due) ---------

CREATE OR REPLACE FUNCTION public.push_sweep()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.push_outbox
     WHERE status IN ('pending', 'failed') AND next_attempt_at <= now()
  ) THEN
    PERFORM public.push_invoke_deliver();
  END IF;
END;
$$;

-- Re-register idempotently.
DO $$
BEGIN
  PERFORM cron.unschedule('push-deliver-sweep');
EXCEPTION WHEN OTHERS THEN
  NULL;
END $$;
SELECT cron.schedule('push-deliver-sweep', '30 seconds', $$SELECT public.push_sweep();$$);


-- ---- 6. Privileges: service-role only --------------------------------
--
-- None of these are client-callable. The edge function uses the service
-- role; the triggers/cron run as the definer (postgres).

REVOKE ALL ON FUNCTION public.push_claim_due(int)                 FROM public;
REVOKE ALL ON FUNCTION public.push_mark_delivered(uuid)           FROM public;
REVOKE ALL ON FUNCTION public.push_mark_failed(uuid, text, int)   FROM public;
REVOKE ALL ON FUNCTION public.push_invoke_deliver()               FROM public;
REVOKE ALL ON FUNCTION public.push_sweep()                        FROM public;
GRANT EXECUTE ON FUNCTION public.push_claim_due(int)               TO service_role;
GRANT EXECUTE ON FUNCTION public.push_mark_delivered(uuid)         TO service_role;
GRANT EXECUTE ON FUNCTION public.push_mark_failed(uuid, text, int) TO service_role;

COMMENT ON FUNCTION public.push_claim_due(int) IS
  'Push P2: atomically lease up to N due outbox rows (FOR UPDATE SKIP '
  'LOCKED, 2-min lease). Service-role only; called by edge fn push-deliver.';
COMMENT ON FUNCTION public.push_invoke_deliver() IS
  'Push P2: fire-and-forget pg_net POST to the push-deliver edge function. '
  'Reads URL + service key from vault (push_edge_url / push_edge_service_key); '
  'no-op until both are set. Never raises (suppresses all errors).';
