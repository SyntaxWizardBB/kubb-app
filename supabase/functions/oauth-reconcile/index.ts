// Server-side reconcile that links an OAuth identity to an existing
// keypair-backed account, per docs/plans/oauth-account-link/architecture.md
// and ADR-0042.
//
// A returning keypair user holds a self-minted HS256 session GoTrue never
// issued, so client-side linkIdentity() cannot work. Instead the caller
// proves both halves in the request body and this function reconciles:
//
//   Proof A — keypair ownership: an Ed25519 signature over a server-issued,
//     single-use, 60s-TTL challenge (the keypair-verify mechanism). Yields
//     the target keypair_user_id.
//   Proof B — OAuth ownership: the OAuth access token re-validated by a
//     server-to-server GET ${SUPABASE_URL}/auth/v1/user. GoTrue returns the
//     authoritative identities; oauth_subject is read from that response,
//     never from the request body. Yields the forked user_id + subject.
//
// Only when both pass does it write the oauth_* credential against the
// keypair user_id and delete the forked auth.users row (one transaction in
// the reconcile_link_oauth RPC), then mint a fresh keypair token.
//
// verify_jwt=false: the request JWT is the anon key, not the transient
// forked OAuth bearer — identity comes from the two body-borne proofs.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import {
  createClient,
  type SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2.45.4";
import * as ed from "https://esm.sh/@noble/ed25519@2.1.0";
import { mintKeypairToken, resolveJwtSecret } from "../_shared/jwt.ts";

interface ReconcileRequest {
  provider?: string;
  public_key?: string;
  challenge_b64?: string;
  signature_b64?: string;
  oauth_access_token?: string;
}

const CHALLENGE_TTL_SECONDS = 60;

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

// PostgREST stores bytea as a hex-escaped string; the challenge column is
// keyed by the raw challenge bytes, so we render \\x<hex> for the filter.
function byteaHex(bytes: Uint8Array): string {
  return `\\x${Array.from(bytes)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("")}`;
}

serve(async (req: Request) => {
  if (req.method !== "POST") {
    return jsonResponse(405, { error: "method_not_allowed" });
  }

  let payload: ReconcileRequest;
  try {
    payload = await req.json();
  } catch (_err) {
    return jsonResponse(400, { error: "invalid_json" });
  }

  const provider = payload.provider;
  const publicKeyB64 = payload.public_key;
  const challengeB64 = payload.challenge_b64;
  const signatureB64 = payload.signature_b64;
  const oauthAccessToken = payload.oauth_access_token;

  if (
    !provider ||
    !publicKeyB64 ||
    !challengeB64 ||
    !signatureB64 ||
    !oauthAccessToken
  ) {
    return jsonResponse(400, { error: "missing_field" });
  }

  if (provider !== "google" && provider !== "apple") {
    return jsonResponse(400, { error: "invalid_provider" });
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

  const challengeHex = byteaHex(challengeBytes);

  // -- Proof A: keypair ownership (exact keypair-verify path) ----------
  const challengeRow = await supabase
    .from("keypair_challenges")
    .select("issued_at")
    .eq("public_key", publicKeyB64)
    .eq("challenge", challengeHex)
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
      .eq("challenge", challengeHex);
    return jsonResponse(410, { error: "challenge_expired" });
  }

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

  const keypairUserId = credentialRow.data.user_id as string;

  // Single-use: drop the challenge so a replay is impossible.
  await supabase
    .from("keypair_challenges")
    .delete()
    .eq("public_key", publicKeyB64)
    .eq("challenge", challengeHex);

  // -- Proof B: OAuth ownership (GoTrue-authoritative) -----------------
  // Server-to-server read. The subject is taken from GoTrue's response,
  // never from the request body, and admin.getUser is deliberately not
  // used (access-token claims do not reliably carry the provider sub).
  let userResponse: Response;
  try {
    userResponse = await fetch(`${supabaseUrl}/auth/v1/user`, {
      method: "GET",
      headers: {
        Authorization: `Bearer ${oauthAccessToken}`,
        apikey: serviceRoleKey,
      },
    });
  } catch (_err) {
    return jsonResponse(401, { error: "oauth_token_invalid" });
  }

  if (userResponse.status !== 200) {
    return jsonResponse(401, { error: "oauth_token_invalid" });
  }

  let gotrueUser: {
    id?: string;
    identities?: Array<{ id?: string | null; provider?: string }>;
  };
  try {
    gotrueUser = await userResponse.json();
  } catch (_err) {
    return jsonResponse(401, { error: "oauth_token_invalid" });
  }

  const forkedUserId = gotrueUser.id;
  if (!forkedUserId) {
    return jsonResponse(401, { error: "oauth_token_invalid" });
  }

  const matchingIdentity = (gotrueUser.identities ?? []).find(
    (identity) => identity?.provider === provider && identity?.id != null,
  );
  if (!matchingIdentity?.id) {
    return jsonResponse(422, { error: "oauth_provider_mismatch" });
  }
  const oauthSubject = matchingIdentity.id;

  // -- Idempotency short-circuit ---------------------------------------
  if (forkedUserId === keypairUserId) {
    return await respondAlreadyLinked(
      supabase,
      keypairUserId,
      provider,
      oauthSubject,
      supabaseUrl,
      jwtSecretBytes,
    );
  }

  const credentialKind = `oauth_${provider}`;

  // -- Collision guard (before any mutation) ---------------------------
  const subjectRow = await supabase
    .from("user_credentials")
    .select("user_id")
    .eq("kind", credentialKind)
    .eq("oauth_subject", oauthSubject)
    .maybeSingle();

  if (subjectRow.error) {
    console.error("oauth_subject lookup failed", subjectRow.error);
    return jsonResponse(500, { error: "credential_lookup_failed" });
  }
  if (subjectRow.data) {
    const owner = subjectRow.data.user_id as string;
    if (owner === keypairUserId) {
      return await respondAlreadyLinked(
        supabase,
        keypairUserId,
        provider,
        oauthSubject,
        supabaseUrl,
        jwtSecretBytes,
      );
    }
    // Subject already bound to a different user — never touch anything.
    return jsonResponse(409, { error: "oauth_subject_in_use" });
  }

  // -- Data guard (before delete) --------------------------------------
  // The forked user is a brand-new GoTrue OAuth signup; it must own no
  // real history before we delete it. These are the auth.users-cascade
  // tables that count as a genuine tournament footprint.
  const hasData = await forkedUserHasData(supabase, forkedUserId);
  if (hasData === null) {
    return jsonResponse(500, { error: "credential_lookup_failed" });
  }
  if (hasData) {
    return jsonResponse(409, { error: "forked_user_has_data" });
  }

  // -- Mutation via SECURITY DEFINER RPC (service-role) ----------------
  const rpc = await supabase.rpc("reconcile_link_oauth", {
    p_keypair_user_id: keypairUserId,
    p_kind: credentialKind,
    p_oauth_subject: oauthSubject,
    p_forked_user_id: forkedUserId,
  });

  if (rpc.error) {
    // The RPC re-checks the subject collision as defence-in-depth and
    // raises 23505; surface it as the same 409 the edge guard would.
    if (rpc.error.code === "23505") {
      return jsonResponse(409, { error: "oauth_subject_in_use" });
    }
    console.error("reconcile_link_oauth failed", rpc.error);
    return jsonResponse(500, { error: "reconcile_failed" });
  }

  const forkedUserDeleted =
    (rpc.data as { forked_user_deleted?: boolean } | null)
      ?.forked_user_deleted ?? false;

  return await mintAndRespond(
    supabase,
    keypairUserId,
    provider,
    oauthSubject,
    supabaseUrl,
    jwtSecretBytes,
    forkedUserDeleted,
  );
});

// The forked user owns real history if it appears in any auth.users-cascade
// table that represents a tournament footprint. Per ADR-0042 §Open
// decisions: tournament_participants (the registration row, user_id) and
// tournament_set_score_proposals (submitter_user_id) are blocking;
// tournaments.created_by is ON DELETE SET NULL so it is tolerated.
async function forkedUserHasData(
  supabase: SupabaseClient<any, any, any>,
  forkedUserId: string,
): Promise<boolean | null> {
  const registration = await supabase
    .from("tournament_participants")
    .select("id")
    .eq("user_id", forkedUserId)
    .limit(1)
    .maybeSingle();
  if (registration.error) {
    console.error("tournament_participants guard failed", registration.error);
    return null;
  }
  if (registration.data) return true;

  const proposal = await supabase
    .from("tournament_set_score_proposals")
    .select("id")
    .eq("submitter_user_id", forkedUserId)
    .limit(1)
    .maybeSingle();
  if (proposal.error) {
    console.error("score proposal guard failed", proposal.error);
    return null;
  }
  if (proposal.data) return true;

  return false;
}

async function respondAlreadyLinked(
  supabase: SupabaseClient<any, any, any>,
  keypairUserId: string,
  provider: string,
  oauthSubject: string,
  supabaseUrl: string,
  jwtSecretBytes: Uint8Array,
): Promise<Response> {
  return await mintAndRespond(
    supabase,
    keypairUserId,
    provider,
    oauthSubject,
    supabaseUrl,
    jwtSecretBytes,
    false,
  );
}

async function mintAndRespond(
  supabase: SupabaseClient<any, any, any>,
  keypairUserId: string,
  provider: string,
  oauthSubject: string,
  supabaseUrl: string,
  jwtSecretBytes: Uint8Array,
  forkedUserDeleted: boolean,
): Promise<Response> {
  const profileRow = await supabase
    .from("user_profiles")
    .select("nickname")
    .eq("user_id", keypairUserId)
    .maybeSingle();

  const nickname = (profileRow.data?.nickname as string | undefined) ?? "";

  const minted = await mintKeypairToken(jwtSecretBytes, supabaseUrl, {
    userId: keypairUserId,
    nickname,
    extraProviders: [provider],
  });

  return jsonResponse(200, {
    user_id: keypairUserId,
    nickname,
    access_token: minted.accessToken,
    expires_at: minted.expiresAt,
    token_type: "bearer",
    linked_provider: provider,
    oauth_subject: oauthSubject,
    forked_user_deleted: forkedUserDeleted,
  });
}
