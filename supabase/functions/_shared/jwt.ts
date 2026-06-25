// Shared HS256 helpers for the keypair-backed edge functions.
//
// The secret resolution and the token mint both live in keypair-verify
// today; oauth-reconcile re-mints the very same keypair session token
// after linking an OAuth identity, so the mint block is hoisted here to
// keep the two functions in lock-step. keypair-verify itself is left
// untouched — this module is additive.

import { create as jwtCreate } from "https://deno.land/x/djwt@v3.0.2/mod.ts";

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
// 2. SUPABASE_INTERNAL_JWT_SECRET — some local CLI builds pass the raw
//    symmetric secret through under this name instead of stripping it.
// 3. SUPABASE_JWKS — newer Supabase CLI (>= 2.9x) does NOT expose the raw
//    secret; the symmetric key still travels through as the "oct" entry,
//    with `k` holding the base64url-encoded raw bytes.
export function resolveJwtSecret(): Uint8Array | null {
  const direct = Deno.env.get("SUPABASE_JWT_SECRET");
  if (direct && direct.length > 0) {
    return new TextEncoder().encode(direct);
  }
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

const ACCESS_TOKEN_TTL_SECONDS = 43200;

export interface MintKeypairTokenOptions {
  userId: string;
  nickname: string;
  // The extra provider(s) the keypair session now carries (e.g. the
  // freshly linked 'google'/'apple'). app_metadata.providers becomes
  // ['keypair', ...extraProviders]; provider stays 'keypair' so the
  // client still classifies the session as keypair-backed.
  extraProviders?: string[];
}

export interface MintedKeypairToken {
  accessToken: string;
  expiresAt: number;
  issuer: string;
}

// Mint a keypair session token. Mirrors the HS256 block in keypair-verify:
// same claims, same TTL, same issuer shape. The only delta is the
// providers array, which lets a reconciled session advertise its linked
// OAuth provider while keeping provider:'keypair'.
export async function mintKeypairToken(
  secret: Uint8Array,
  supabaseUrl: string,
  options: MintKeypairTokenOptions,
): Promise<MintedKeypairToken> {
  const key = await crypto.subtle.importKey(
    "raw",
    secret,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );

  const now = Math.floor(Date.now() / 1000);
  const expiresAt = now + ACCESS_TOKEN_TTL_SECONDS;
  const issuer = `${supabaseUrl}/auth/v1`;
  const providers = ["keypair", ...(options.extraProviders ?? [])];

  const accessToken = await jwtCreate(
    { alg: "HS256", typ: "JWT" },
    {
      sub: options.userId,
      aud: "authenticated",
      role: "authenticated",
      iss: issuer,
      iat: now,
      exp: expiresAt,
      session_id: crypto.randomUUID(),
      app_metadata: { provider: "keypair", providers },
      user_metadata: { nickname: options.nickname },
      is_anonymous: false,
    },
    key,
  );

  return { accessToken, expiresAt, issuer };
}
