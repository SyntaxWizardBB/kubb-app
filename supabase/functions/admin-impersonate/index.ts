// Admin impersonation (M1 §2.2). An authenticated admin mints a short-lived
// session token for a target user and acts fully as them (spec D1: full
// session incl. security changes). Safeguards: admin-only (DB-checked,
// suspension-aware via caller_is_admin), never impersonate another admin,
// never a suspended target, always audit-logged, and the minted token
// carries `impersonator_id` so the client shows a mandatory banner + exit.
//
// verify_jwt = false at the gateway (config.toml): keypair sessions are
// self-minted HS256 tokens the ES256-issuing gateway may reject, so this
// function does its own auth — getUser() validates the caller's token and
// caller_is_admin() enforces admin + non-suspended against the DB. An
// invalid/absent token yields no user -> 401.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { mintImpersonationToken, resolveJwtSecret } from "../_shared/jwt.ts";

interface ImpersonateRequest {
  target_user_id?: string;
}

function jsonResponse(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

serve(async (req: Request) => {
  if (req.method !== "POST") {
    return jsonResponse(405, { error: "method_not_allowed" });
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const callerJwt = authHeader.replace(/^Bearer\s+/i, "").trim();
  if (!callerJwt) return jsonResponse(401, { error: "missing_bearer" });

  let payload: ImpersonateRequest;
  try {
    payload = await req.json();
  } catch (_err) {
    return jsonResponse(400, { error: "invalid_json" });
  }
  const targetUserId = payload.target_user_id;
  if (!targetUserId) return jsonResponse(400, { error: "missing_field" });

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const jwtSecretBytes = resolveJwtSecret();
  if (!supabaseUrl || !serviceRoleKey || !anonKey || !jwtSecretBytes) {
    return jsonResponse(500, { error: "server_misconfigured" });
  }

  // Resolve the caller. Keypair sessions are HS256 tokens WE minted (GoTrue
  // never issued them), so getUser() rejects them — verify the signature
  // locally with the shared secret. ES256/RS256 (real GoTrue/OAuth sessions)
  // fall back to getUser(jwt).
  let callerId: string | null = null;
  const claims = decodeJwtClaims(callerJwt);
  const alg = decodeJwtHeader(callerJwt)?.alg;

  if (alg === "HS256") {
    const verified = await verifyHs256(callerJwt, jwtSecretBytes);
    if (!verified) return jsonResponse(401, { error: "invalid_session" });
    callerId = typeof verified.sub === "string" ? verified.sub : null;
  } else {
    const asCaller = createClient(supabaseUrl, anonKey, {
      auth: { persistSession: false },
    });
    const { data: userData } = await asCaller.auth.getUser(callerJwt);
    callerId = userData?.user?.id ?? null;
  }
  if (!callerId) return jsonResponse(401, { error: "invalid_session" });

  // Refuse nested impersonation: an already-impersonated session must not
  // mint another impersonation token.
  if (claims?.impersonator_id) {
    return jsonResponse(409, { error: "already_impersonating" });
  }

  // Service client for the admin check, target lookup and audit (bypasses RLS).
  const svc = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false },
  });

  // Admin gate — is_admin AND not suspended (mirrors caller_is_admin()).
  const callerProfile = await svc
    .from("user_profiles")
    .select("is_admin, suspended_at")
    .eq("user_id", callerId)
    .maybeSingle();
  if (callerProfile.error) return jsonResponse(500, { error: "admin_check_failed" });
  if (
    !callerProfile.data ||
    callerProfile.data.is_admin !== true ||
    callerProfile.data.suspended_at != null
  ) {
    return jsonResponse(403, { error: "admin_only" });
  }

  if (targetUserId === callerId) {
    return jsonResponse(400, { error: "cannot_impersonate_self" });
  }

  const target = await svc
    .from("user_profiles")
    .select("nickname, is_admin, suspended_at")
    .eq("user_id", targetUserId)
    .maybeSingle();
  if (target.error) return jsonResponse(500, { error: "target_lookup_failed" });
  if (!target.data) return jsonResponse(404, { error: "target_not_found" });
  if (target.data.is_admin === true) {
    return jsonResponse(403, { error: "cannot_impersonate_admin" });
  }
  if (target.data.suspended_at != null) {
    return jsonResponse(409, { error: "target_suspended" });
  }

  const nickname = (target.data.nickname as string | undefined) ?? "";

  // Audit BEFORE minting (append-only; service_role bypasses RLS).
  const audit = await svc.from("admin_audit_events").insert({
    actor_user_id: callerId,
    target_user_id: targetUserId,
    kind: "impersonation_start",
    payload: { nickname },
  });
  if (audit.error) {
    console.error("audit insert failed", audit.error);
    return jsonResponse(500, { error: "audit_failed" });
  }

  const minted = await mintImpersonationToken(jwtSecretBytes, supabaseUrl, {
    userId: targetUserId,
    nickname,
    impersonatorId: callerId,
  });

  return jsonResponse(200, {
    user_id: targetUserId,
    nickname,
    access_token: minted.accessToken,
    expires_at: minted.expiresAt,
    token_type: "bearer",
    impersonator_id: callerId,
  });
});

function b64urlToBytes(part: string): Uint8Array {
  const padded = part.replace(/-/g, "+").replace(/_/g, "/")
    .padEnd(Math.ceil(part.length / 4) * 4, "=");
  const bin = atob(padded);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

function decodeJwtPart(part: string): Record<string, unknown> | null {
  try {
    return JSON.parse(new TextDecoder().decode(b64urlToBytes(part)));
  } catch (_err) {
    return null;
  }
}

function decodeJwtClaims(jwt: string): Record<string, unknown> | null {
  return decodeJwtPart(jwt.split(".")[1] ?? "");
}

function decodeJwtHeader(jwt: string): Record<string, unknown> | null {
  return decodeJwtPart(jwt.split(".")[0] ?? "");
}

// Verify an HS256 JWT against the shared secret and enforce expiry. Returns
// the claims on success, null on any failure (bad shape/signature/expired).
async function verifyHs256(
  jwt: string,
  secret: Uint8Array,
): Promise<Record<string, unknown> | null> {
  const parts = jwt.split(".");
  if (parts.length !== 3) return null;
  try {
    const key = await crypto.subtle.importKey(
      "raw",
      secret,
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["verify"],
    );
    const data = new TextEncoder().encode(`${parts[0]}.${parts[1]}`);
    const ok = await crypto.subtle.verify("HMAC", key, b64urlToBytes(parts[2]), data);
    if (!ok) return null;
    const claims = decodeJwtPart(parts[1]);
    if (!claims) return null;
    const exp = typeof claims.exp === "number" ? claims.exp : 0;
    if (exp && exp < Math.floor(Date.now() / 1000)) return null;
    return claims;
  } catch (_err) {
    return null;
  }
}
