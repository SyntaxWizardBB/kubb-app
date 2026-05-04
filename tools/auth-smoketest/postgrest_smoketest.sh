#!/usr/bin/env bash
# M7-Fix-HIGH-1 — End-to-end smoketest of the auth RPCs through PostgREST.
#
# The original `run.sh` calls the auth.* functions over psql, which
# bypasses the API gateway and never exercises the schema-exposure
# config. This script hits PostgREST directly so a missing public-schema
# wrapper would surface as PGRST404.
#
# Run against a local Supabase stack:
#   cd ~/Workbench/projects/kubb_app
#   supabase start
#   bash tools/auth-smoketest/postgrest_smoketest.sh
#
# The script verifies that each of the five client-facing RPCs is
# reachable via /rest/v1/rpc/<name>. It does NOT exercise the full
# happy-path (which needs an anonymous Supabase session, a real
# keypair, and seeded user_profiles rows — that is `run.sh`'s job). A
# 401 / 403 / 4xx with a sensible PostgREST error body is treated as
# proof that the function is reachable; only PGRST404 ("not found") or
# transport failures are considered a fail.

set -euo pipefail

API_URL="${API_URL:-http://localhost:54321}"

if ! command -v curl >/dev/null 2>&1; then
  echo "FAIL: curl not on PATH" >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "FAIL: jq not on PATH" >&2
  exit 1
fi

ANON_KEY="${ANON_KEY:-}"
if [[ -z "${ANON_KEY}" ]]; then
  if command -v supabase >/dev/null 2>&1; then
    ANON_KEY=$(supabase status --output json 2>/dev/null \
                 | jq -r '.ANON_KEY // empty')
  fi
fi
if [[ -z "${ANON_KEY}" ]]; then
  echo "FAIL: ANON_KEY env var not set and 'supabase status' unavailable" >&2
  exit 1
fi

ok()   { printf '  OK   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; exit 1; }

# Calls the given rpc with the given JSON body and asserts the response
# is NOT a PGRST404 (= function not exposed through public schema).
assert_rpc_reachable() {
  local fn="$1"
  local body="$2"

  local response
  response=$(curl -s -w '\n%{http_code}' \
    -X POST \
    -H "apikey: ${ANON_KEY}" \
    -H "Authorization: Bearer ${ANON_KEY}" \
    -H "Content-Type: application/json" \
    -d "${body}" \
    "${API_URL}/rest/v1/rpc/${fn}")

  local http_code="${response##*$'\n'}"
  local payload="${response%$'\n'*}"

  # PGRST404 has both http 404 and a `code` field of "PGRST202" / "404"
  # depending on the cause. The simplest and most reliable signal is
  # the body containing PGRST202 (function not found in schema cache).
  if [[ "${payload}" == *PGRST202* ]]; then
    fail "rpc ${fn} not exposed (PGRST202): ${payload}"
  fi

  # 200 / 4xx with a real PostgreSQL error means the function ran. Any
  # transport-level failure (000, 5xx) is also a fail.
  if [[ "${http_code}" == "000" ]]; then
    fail "rpc ${fn} transport failure"
  fi
  if [[ "${http_code}" =~ ^5 ]]; then
    fail "rpc ${fn} server error ${http_code}: ${payload}"
  fi

  ok "rpc ${fn} reachable (http ${http_code})"
}

printf '\n— public-schema RPC reachability\n'

# compute_nickname_hash is unauthenticated-safe; expect a 200.
assert_rpc_reachable compute_nickname_hash \
  '{"p_nickname": "smoketest"}'

# keypair_challenge is unauthenticated-safe; expect a 200.
assert_rpc_reachable keypair_challenge \
  '{"p_public_key": "smoketest-public-key"}'

# keypair_verify moved out of Postgres into the keypair-verify edge
# function (M8-T01). The RPC reachability check no longer applies; the
# edge function lives under supabase/functions/keypair-verify/ and is
# exercised by run.sh against `${API_URL}/functions/v1/keypair-verify`.

# keypair_attach requires an authenticated session. Anonymous call will
# raise the "requires an authenticated session" exception — which is
# fine, the function ran. PGRST202 would mean it was not exposed.
assert_rpc_reachable keypair_attach \
  '{"p_nickname": "smk", "p_public_key": "k", "p_ciphertext": null, "p_kdf_salt": null, "p_kdf_params": {}}'

# fn_profile_update_with_hash needs `authenticated` role; anon call gets
# rejected by the GRANT but the function exists. Acceptable.
assert_rpc_reachable fn_profile_update_with_hash \
  '{"p_nickname": null, "p_avatar_color": null, "p_onboarding_done": null}'

echo
echo "All postgrest-smoketest checks passed against ${API_URL}."
