// Push P2 — the delivery worker for the transactional push outbox.
//
// SPEC: docs/plans/push-notifications/SPEC.md §P2. Invoked two ways, both
// doing the SAME idempotent work ("claim due rows -> send -> finalize"):
//   1. pg_net AFTER-INSERT webhook on public.push_outbox  -> low latency (<1s)
//   2. pg_cron sweeper (~10s)                              -> reliability net
// Both pass the service-role bearer; verify_jwt stays on (config.toml) so an
// unauthenticated caller cannot trigger a sweep.
//
// Claiming is atomic in Postgres (push_claim_due leases rows by pushing
// next_attempt_at into the future under FOR UPDATE SKIP LOCKED), so two
// concurrent invocations never double-send. Finalize goes back through
// push_mark_delivered / push_mark_failed (backoff + dead-letter live in SQL).
//
// FCM HTTP v1: the OAuth2 access token is minted on the fly from the
// FCM_SERVICE_ACCOUNT secret (RS256 JWT -> token endpoint). Payload is
// PII-free: data {inbox_message_id, kind} + notification {title=subject}.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { create as jwtCreate } from "https://deno.land/x/djwt@v3.0.2/mod.ts";

const CLAIM_LIMIT = 50;
const MAX_ATTEMPTS = 8; // mirrors SQL push_mark_failed dead-letter threshold

interface ServiceAccount {
  client_email: string;
  private_key: string;
  project_id: string;
}

interface OutboxRow {
  id: string;
  user_id: string;
  payload: Record<string, unknown>;
  attempts: number;
}

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function decodeBase64(value: string): Uint8Array {
  const binary = atob(value);
  const out = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) out[i] = binary.charCodeAt(i);
  return out;
}

// Import a PEM PKCS#8 RSA private key for RS256 signing.
async function importPkcs8(pem: string): Promise<CryptoKey> {
  const b64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const der = decodeBase64(b64);
  return await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
}

// Mint a short-lived FCM access token via the service-account JWT grant.
async function mintFcmAccessToken(sa: ServiceAccount): Promise<string> {
  const key = await importPkcs8(sa.private_key);
  const now = Math.floor(Date.now() / 1000);
  const assertion = await jwtCreate(
    { alg: "RS256", typ: "JWT" },
    {
      iss: sa.client_email,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: "https://oauth2.googleapis.com/token",
      iat: now,
      exp: now + 3600,
    },
    key,
  );
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  if (!res.ok) {
    throw new Error(`fcm_oauth_failed ${res.status} ${await res.text()}`);
  }
  const body = await res.json();
  if (!body.access_token) throw new Error("fcm_oauth_no_token");
  return body.access_token as string;
}

interface SendResult {
  ok: boolean;
  permanent: boolean; // token is gone/invalid -> drop it, do not retry
  error?: string;
}

async function sendToToken(
  accessToken: string,
  projectId: string,
  token: string,
  data: Record<string, string>,
  title: string,
): Promise<SendResult> {
  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: { token, data, notification: { title } },
      }),
    },
  );
  if (res.ok) return { ok: true, permanent: false };
  const body = await res.json().catch(() => ({} as Record<string, unknown>));
  const errObj = (body as { error?: { status?: string; details?: Array<{ errorCode?: string }> } }).error;
  const fcmCode = errObj?.status ?? errObj?.details?.[0]?.errorCode;
  // UNREGISTERED (404) or INVALID_ARGUMENT (400) => the token is dead.
  const permanent = res.status === 404 || res.status === 400 ||
    fcmCode === "UNREGISTERED" || fcmCode === "INVALID_ARGUMENT";
  return {
    ok: false,
    permanent,
    error: `${res.status} ${JSON.stringify(errObj ?? {})}`.slice(0, 500),
  };
}

serve(async (_req: Request) => {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const saRaw = Deno.env.get("FCM_SERVICE_ACCOUNT");
  if (!supabaseUrl || !serviceRoleKey) {
    return json(500, { error: "server_misconfigured" });
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false },
  });

  // Claim a batch of due rows atomically (lease via next_attempt_at).
  const claim = await supabase.rpc("push_claim_due", { p_limit: CLAIM_LIMIT });
  if (claim.error) {
    return json(500, { error: "claim_failed", detail: claim.error.message });
  }
  const rows = (claim.data ?? []) as OutboxRow[];
  if (rows.length === 0) return json(200, { claimed: 0 });

  // No FCM key configured => leave the claimed rows for a later run (their
  // lease expires and the sweeper retries once the secret is set).
  if (!saRaw) {
    return json(200, { claimed: rows.length, sent: 0, note: "FCM_SERVICE_ACCOUNT not set" });
  }
  let sa: ServiceAccount;
  try {
    sa = JSON.parse(saRaw) as ServiceAccount;
  } catch {
    return json(500, { error: "fcm_service_account_invalid_json" });
  }

  let accessToken: string;
  try {
    accessToken = await mintFcmAccessToken(sa);
  } catch (err) {
    return json(502, { error: "fcm_oauth_failed", detail: String(err).slice(0, 300) });
  }

  let delivered = 0;
  let failed = 0;

  for (const row of rows) {
    const tokensRes = await supabase
      .from("user_device_tokens")
      .select("token")
      .eq("user_id", row.user_id);

    const tokens = (tokensRes.data ?? []).map((t) => t.token as string);
    const data: Record<string, string> = {
      inbox_message_id: String(row.payload?.id ?? ""),
      kind: String(row.payload?.kind ?? ""),
    };
    const title = String(row.payload?.subject ?? "Kubb Club");

    let success = 0;
    let retriable = 0;
    for (const token of tokens) {
      const r = await sendToToken(accessToken, sa.project_id, token, data, title);
      if (r.ok) {
        success++;
      } else if (r.permanent) {
        // Drop the dead token so it never wastes another send.
        await supabase.from("user_device_tokens").delete().eq("token", token);
      } else {
        retriable++;
      }
    }

    // Delivered if at least one send worked, OR nothing retriable remains
    // (no tokens / all dead). Only transient failures keep the row alive.
    if (success > 0 || retriable === 0) {
      await supabase.rpc("push_mark_delivered", { p_id: row.id });
      delivered++;
    } else {
      await supabase.rpc("push_mark_failed", {
        p_id: row.id,
        p_error: `transient: ${retriable} token(s) failed`,
        p_max_attempts: MAX_ATTEMPTS,
      });
      failed++;
    }
  }

  return json(200, { claimed: rows.length, delivered, failed });
});
