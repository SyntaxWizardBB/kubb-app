// M8-T01 — Edge function that performs the Ed25519 verify step of the
// cross-device sign-in (per ADR-0010 §AK-4).
//
// The previous implementation lived in auth.keypair_verify (Postgres
// SECURITY DEFINER function) but Postgres has no built-in Ed25519
// primitive — pgsodium would have been the alternative. Moving the
// verify into a Deno edge function gives us a real cryptographic check
// without pulling a new database extension.
//
// M8-T03 — On successful verify the function now also mints a real
// Supabase access token (HS256, signed with SUPABASE_JWT_SECRET) so
// the client can hydrate a live auth session via
// gotrue.recoverSession(...) — no admin-create-user round-trip and no
// service-role key on the device.
//
// Phase-1 trade-off: no refresh_token. The token lives one hour; once
// it expires the user signs in again with the keypair. ADR-0010
// follow-up tracks lifting this in Phase 2.
//
// Caller flow (matches lib/features/auth/data/supabase_auth_adapter_impl.dart):
//   POST { public_key, challenge_b64, signature_b64 }
//   -> 200 { user_id, nickname, access_token, expires_at, token_type }
//      on success
//   -> 401 { error: "<reason>" }   on signature / lookup failure
//   -> 410 { error: "challenge_expired" } when the challenge is past its TTL

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import * as ed from "https://esm.sh/@noble/ed25519@2.1.0";
import { create as jwtCreate } from "https://deno.land/x/djwt@v3.0.2/mod.ts";

interface VerifyRequest {
  public_key?: string;
  challenge_b64?: string;
  signature_b64?: string;
}

const CHALLENGE_TTL_SECONDS = 60;
// 12h lifetime: low-risk mitigation that widens the window before a
// Phase-1 keypair JWT expires. The durable fix is client-side — the
// app re-signs on resume and auto-retries on PGRST303 — but a longer
// TTL means most sessions never hit the expiry path at all.
const ACCESS_TOKEN_TTL_SECONDS = 43200;

function jsonResponse(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function decodeBase64(value: string): Uint8Array {
  const binary = atob(value);
  const out = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    out[i] = binary.charCodeAt(i);
  }
  return out;
}

function decodeBase64Url(value: string): Uint8Array {
  const padded = value
    .replace(/-/g, "+")
    .replace(/_/g, "/")
    .padEnd(Math.ceil(value.length / 4) * 4, "=");
  return decodeBase64(padded);
}

// Resolve the HS256 signing secret across Supabase deployments.
//
// 1. SUPABASE_JWT_SECRET — present on Hetzner prod and on older
//    self-hosted/CLI setups.
// 2. SUPABASE_JWKS — newer Supabase CLI (>= 2.9x) does NOT expose the raw
//    secret; the edge-runtime wrapper actively strips every
//    SUPABASE_INTERNAL_* env var before invoking the user worker. The
//    symmetric key still travels through as the "oct" entry in
//    SUPABASE_JWKS, with `k` holding the base64url-encoded raw bytes
//    (same string that would be in SUPABASE_JWT_SECRET).
function resolveJwtSecret(): Uint8Array | null {
  const direct = Deno.env.get("SUPABASE_JWT_SECRET");
  if (direct && direct.length > 0) {
    return new TextEncoder().encode(direct);
  }
  // 1b. SUPABASE_INTERNAL_JWT_SECRET — some local CLI builds pass the raw
  //     symmetric secret through under this name instead of stripping it.
  //     Same value as SUPABASE_JWT_SECRET, so use it as a local-dev
  //     fallback. Prod (Hetzner) sets the direct var above and never hits
  //     this branch.
  const internal = Deno.env.get("SUPABASE_INTERNAL_JWT_SECRET");
  if (internal && internal.length > 0) {
    return new TextEncoder().encode(internal);
  }
  const jwksRaw = Deno.env.get("SUPABASE_JWKS");
  if (!jwksRaw) return null;
  try {
    const jwks = JSON.parse(jwksRaw) as {
      keys?: Array<{ kty?: string; k?: string }>;
    };
    const oct = jwks.keys?.find((entry) => entry?.kty === "oct" && entry?.k);
    if (!oct?.k) return null;
    return decodeBase64Url(oct.k);
  } catch (_err) {
    return null;
  }
}

serve(async (req: Request) => {
  if (req.method !== "POST") {
    return jsonResponse(405, { error: "method_not_allowed" });
  }

  let payload: VerifyRequest;
  try {
    payload = await req.json();
  } catch (_err) {
    return jsonResponse(400, { error: "invalid_json" });
  }

  const publicKeyB64 = payload.public_key;
  const challengeB64 = payload.challenge_b64;
  const signatureB64 = payload.signature_b64;
  if (!publicKeyB64 || !challengeB64 || !signatureB64) {
    return jsonResponse(400, { error: "missing_field" });
  }

  let publicKeyBytes: Uint8Array;
  let challengeBytes: Uint8Array;
  let signatureBytes: Uint8Array;
  try {
    publicKeyBytes = decodeBase64(publicKeyB64);
    challengeBytes = decodeBase64(challengeB64);
    signatureBytes = decodeBase64(signatureB64);
  } catch (_err) {
    return jsonResponse(400, { error: "invalid_base64" });
  }

  if (publicKeyBytes.length !== 32) {
    return jsonResponse(400, { error: "invalid_public_key_length" });
  }
  if (signatureBytes.length !== 64) {
    return jsonResponse(400, { error: "invalid_signature_length" });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const jwtSecretBytes = resolveJwtSecret();
  if (!supabaseUrl || !serviceRoleKey || !jwtSecretBytes) {
    return jsonResponse(500, { error: "server_misconfigured" });
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false },
  });

  // Look up the active challenge. The row is keyed by (public_key,
  // challenge bytes); we read the issued_at to enforce the TTL.
  const challengeRow = await supabase
    .from("keypair_challenges")
    .select("issued_at")
    .eq("public_key", publicKeyB64)
    .eq("challenge", `\\x${Array.from(challengeBytes)
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("")}`)
    .maybeSingle();

  if (challengeRow.error) {
    return jsonResponse(500, { error: "challenge_lookup_failed" });
  }
  if (!challengeRow.data) {
    return jsonResponse(401, { error: "challenge_not_found" });
  }

  const issuedAt = new Date(challengeRow.data.issued_at as string);
  const ageSeconds = (Date.now() - issuedAt.getTime()) / 1000;
  if (ageSeconds > CHALLENGE_TTL_SECONDS) {
    await supabase
      .from("keypair_challenges")
      .delete()
      .eq("public_key", publicKeyB64)
      .eq("challenge", `\\x${Array.from(challengeBytes)
        .map((b) => b.toString(16).padStart(2, "0"))
        .join("")}`);
    return jsonResponse(410, { error: "challenge_expired" });
  }

  // Real Ed25519 verify — the whole point of moving off Postgres.
  let signatureValid = false;
  try {
    signatureValid = await ed.verifyAsync(
      signatureBytes,
      challengeBytes,
      publicKeyBytes,
    );
  } catch (_err) {
    signatureValid = false;
  }
  if (!signatureValid) {
    return jsonResponse(401, { error: "signature_invalid" });
  }

  // Resolve user_id behind the public_key. We previously did this as a
  // single PostgREST embedded select with `user_profiles!inner(...)`, but
  // PostgREST refuses that join because user_credentials and
  // user_profiles do not have a direct foreign-key relationship — both
  // FK to auth.users(id), not to each other (PGRST200).
  const credentialRow = await supabase
    .from("user_credentials")
    .select("user_id")
    .eq("kind", "keypair")
    .eq("public_key", publicKeyB64)
    .maybeSingle();

  if (credentialRow.error) {
    console.error("user_credentials lookup failed", credentialRow.error);
    return jsonResponse(500, { error: "credential_lookup_failed" });
  }
  if (!credentialRow.data) {
    return jsonResponse(401, { error: "no_account_for_public_key" });
  }

  const userId = credentialRow.data.user_id as string;

  const profileRow = await supabase
    .from("user_profiles")
    .select("nickname")
    .eq("user_id", userId)
    .maybeSingle();

  if (profileRow.error) {
    console.error("user_profiles lookup failed", profileRow.error);
    return jsonResponse(500, { error: "profile_lookup_failed" });
  }
  const nickname = (profileRow.data?.nickname as string | undefined) ?? "";

  // Single-use: drop the challenge so a replay is impossible.
  await supabase
    .from("keypair_challenges")
    .delete()
    .eq("public_key", publicKeyB64)
    .eq("challenge", `\\x${Array.from(challengeBytes)
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("")}`);

  // Mint the access token. HS256 with SUPABASE_JWT_SECRET — same key
  // the gotrue server uses to sign its own tokens, so PostgREST and
  // the storage / functions gateways accept it transparently.
  const key = await crypto.subtle.importKey(
    "raw",
    jwtSecretBytes,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );

  const now = Math.floor(Date.now() / 1000);
  const expiresAt = now + ACCESS_TOKEN_TTL_SECONDS;
  const accessToken = await jwtCreate(
    { alg: "HS256", typ: "JWT" },
    {
      sub: userId,
      aud: "authenticated",
      role: "authenticated",
      iss: `${supabaseUrl}/auth/v1`,
      iat: now,
      exp: expiresAt,
      session_id: crypto.randomUUID(),
      app_metadata: { provider: "keypair", providers: ["keypair"] },
      user_metadata: { nickname },
      is_anonymous: false,
    },
    key,
  );

  return jsonResponse(200, {
    user_id: userId,
    nickname,
    access_token: accessToken,
    expires_at: expiresAt,
    token_type: "bearer",
  });
});
