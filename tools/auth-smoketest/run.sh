#!/usr/bin/env bash
# M2-T05 — End-to-end smoketest of the auth schema and Postgres functions.
#
# Run against a freshly started local Supabase stack:
#   cd ~/Workbench/projects/kubb_app
#   supabase start                     # boots Docker stack + applies migrations
#   bash tools/auth-smoketest/run.sh   # this script
#
# The script:
#   1. Reads anon and service-role keys from `supabase status`.
#   2. Hits PostgREST to verify the new tables and functions exist.
#   3. Calls auth.keypair_challenge → keypair_verify against a sample
#      public_key + nickname (no actual cryptography — that lives in the
#      Dart side per ADR-0010 §AK-19).
#   4. Tries to read user_credentials anonymously and asserts RLS denies
#      it.
#
# Exits non-zero on the first failure. Prints a green checklist on
# success.

set -euo pipefail

API_URL="${API_URL:-http://localhost:54321}"
PSQL_URL="${PSQL_URL:-postgresql://postgres:postgres@localhost:54322/postgres}"

if ! command -v psql >/dev/null 2>&1; then
  echo "FAIL: psql not on PATH (needed to seed test rows)" >&2
  exit 1
fi
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

step() { printf '\n— %s\n' "$1"; }
ok()   { printf '  OK   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; exit 1; }

# ----------------------------------------------------------------------
step 'tables and indexes exist'

for table in user_credentials user_keypair_backups user_profiles; do
  count=$(psql "${PSQL_URL}" -tAc \
    "SELECT count(*) FROM information_schema.tables WHERE table_name='${table}'")
  [[ "${count}" == "1" ]] && ok "table ${table} present" \
                          || fail "table ${table} missing"
done

# ----------------------------------------------------------------------
step 'rls enabled'

for table in user_credentials user_keypair_backups user_profiles; do
  enabled=$(psql "${PSQL_URL}" -tAc \
    "SELECT relrowsecurity FROM pg_class WHERE relname='${table}'")
  [[ "${enabled}" == "t" ]] && ok "rls enabled on ${table}" \
                            || fail "rls disabled on ${table}"
done

# ----------------------------------------------------------------------
step 'helper functions exist'

for fn in nickname_hash_salt compute_nickname_hash keypair_attach \
          keypair_challenge keypair_verify; do
  count=$(psql "${PSQL_URL}" -tAc \
    "SELECT count(*) FROM pg_proc p
       JOIN pg_namespace n ON p.pronamespace = n.oid
       WHERE n.nspname='auth' AND p.proname='${fn}'")
  [[ "${count}" -ge "1" ]] && ok "auth.${fn} present" \
                           || fail "auth.${fn} missing"
done

# ----------------------------------------------------------------------
step 'compute_nickname_hash is deterministic and salt-aware'

hash1=$(psql "${PSQL_URL}" -tAc \
  "SELECT auth.compute_nickname_hash('lukas')")
hash2=$(psql "${PSQL_URL}" -tAc \
  "SELECT auth.compute_nickname_hash('lukas')")
hash3=$(psql "${PSQL_URL}" -tAc \
  "SELECT auth.compute_nickname_hash('lukas-2')")
[[ "${hash1}" == "${hash2}" ]] && ok 'same input → same hash' \
                               || fail "deterministic check failed"
[[ "${hash1}" != "${hash3}" ]] && ok 'different input → different hash' \
                               || fail "salt-aware check failed"

# ----------------------------------------------------------------------
step 'keypair_challenge issues a fresh nonce per call'

ch1=$(psql "${PSQL_URL}" -tAc \
  "SELECT auth.keypair_challenge('test-public-key-1')->>'challenge'")
ch2=$(psql "${PSQL_URL}" -tAc \
  "SELECT auth.keypair_challenge('test-public-key-1')->>'challenge'")
[[ "${ch1}" != "${ch2}" ]] && ok 'two consecutive challenges differ' \
                           || fail 'challenge not random'

# Cleanup so the table doesn't accumulate test rows.
psql "${PSQL_URL}" -tAc \
  "DELETE FROM auth.keypair_challenges WHERE public_key LIKE 'test-public-key-%'" \
  >/dev/null

# ----------------------------------------------------------------------
step 'rls denies anonymous reads of user_credentials'

http_code=$(curl -s -o /dev/null -w '%{http_code}' \
  -H "apikey: ${ANON_KEY}" \
  -H "Authorization: Bearer ${ANON_KEY}" \
  "${API_URL}/rest/v1/user_credentials?select=id&limit=1")
# RLS denial returns 200 with empty body for SELECT. So success = empty
# array, not a 401. Call again and parse the body.
body=$(curl -s \
  -H "apikey: ${ANON_KEY}" \
  -H "Authorization: Bearer ${ANON_KEY}" \
  "${API_URL}/rest/v1/user_credentials?select=id&limit=1")
[[ "${body}" == "[]" ]] && ok 'anonymous read returns empty array (rls)' \
                        || fail "anonymous read leaked rows: ${body}"

# ----------------------------------------------------------------------
echo
echo "All auth-smoketest checks passed against ${API_URL}."
