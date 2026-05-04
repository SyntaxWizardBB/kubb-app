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
const ACCESS_TOKEN_TTL_SECONDS = 3600;

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
  const jwtSecret = Deno.env.get("SUPABASE_JWT_SECRET");
  if (!supabaseUrl || !serviceRoleKey || !jwtSecret) {
    return jsonResponse(500, { error: "server_misconfigured" });
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false },
  });

  // Look up the active challenge. The row is keyed by (public_key,
  // challenge bytes); we read the issued_at to enforce the TTL.
  const challengeRow = await supabase
    .schema("auth")
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
      .schema("auth")
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

  // Resolve user_id + nickname behind the public_key. Same join the
  // dropped Postgres function ran.
  const credentialRow = await supabase
    .from("user_credentials")
    .select("user_id, user_profiles!inner(nickname)")
    .eq("kind", "keypair")
    .eq("public_key", publicKeyB64)
    .maybeSingle();

  if (credentialRow.error || !credentialRow.data) {
    return jsonResponse(401, { error: "no_account_for_public_key" });
  }

  // Single-use: drop the challenge so a replay is impossible.
  await supabase
    .schema("auth")
    .from("keypair_challenges")
    .delete()
    .eq("public_key", publicKeyB64)
    .eq("challenge", `\\x${Array.from(challengeBytes)
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("")}`);

  const userId = credentialRow.data.user_id as string;
  const profileJoin = credentialRow.data.user_profiles as
    | { nickname?: string }
    | { nickname?: string }[]
    | null;
  let nickname = "";
  if (Array.isArray(profileJoin)) {
    nickname = profileJoin[0]?.nickname ?? "";
  } else if (profileJoin) {
    nickname = profileJoin.nickname ?? "";
  }

  // Mint the access token. HS256 with SUPABASE_JWT_SECRET — same key
  // the gotrue server uses to sign its own tokens, so PostgREST and
  // the storage / functions gateways accept it transparently.
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(jwtSecret),
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
