#!/usr/bin/env bash
# Admin CLI for the local Supabase instance — wraps the
# admin_purge_account / admin_inbox_send / admin_inbox_list_for_user
# RPCs from migration 20260504000011 with curl.
#
# All RPCs are SECURITY DEFINER and gated on `auth.role() =
# 'service_role'`, so the script must use the service-role key, not
# the anon key. The default values below match a vanilla
# `supabase start` on this project; override via env if you run on
# a different host or rotate the keys.
#
# Usage:
#   tools/admin/admin.sh purge       <user_id>
#   tools/admin/admin.sh inbox-send  <user_id> <kind> <subject> <body> [json-action-payload]
#   tools/admin/admin.sh inbox-list  <user_id>
#   tools/admin/admin.sh users       # quick lookup of users via psql
#
# kinds for inbox-send: notice | verification_request | system

set -euo pipefail

SUPABASE_URL="${SUPABASE_URL:-http://127.0.0.1:54321}"
DB_CONTAINER="${DB_CONTAINER:-supabase_db_kubb-app-local}"

# Pull the service-role key out of the running edge-runtime container
# instead of asking the operator to paste it. Fails loudly if Supabase
# isn't running.
fetch_service_role_key() {
  if [ -n "${SUPABASE_SERVICE_ROLE_KEY:-}" ]; then
    echo "$SUPABASE_SERVICE_ROLE_KEY"
    return
  fi
  if command -v sudo >/dev/null && sudo -n docker ps >/dev/null 2>&1; then
    sudo -n docker exec supabase_edge_runtime_kubb-app-local \
      sh -c 'echo $SUPABASE_SERVICE_ROLE_KEY'
    return
  fi
  echo "ERROR: cannot read SUPABASE_SERVICE_ROLE_KEY. Set it in the env or" >&2
  echo "       allow passwordless sudo for docker." >&2
  exit 1
}

call_rpc() {
  local fn="$1" body="$2"
  local key
  key=$(fetch_service_role_key)
  curl -sS -X POST "$SUPABASE_URL/rest/v1/rpc/$fn" \
    -H "apikey: $key" \
    -H "Authorization: Bearer $key" \
    -H "Content-Type: application/json" \
    -d "$body"
  echo
}

cmd_purge() {
  local user_id="$1"
  if [ -z "$user_id" ]; then
    echo "usage: admin.sh purge <user_id>" >&2
    exit 2
  fi
  echo "Purging $user_id …"
  call_rpc admin_purge_account "{\"p_user_id\":\"$user_id\"}"
}

cmd_inbox_send() {
  local user_id="$1" kind="$2" subject="$3" body="$4"
  local action_payload="${5:-null}"
  if [ -z "$user_id" ] || [ -z "$kind" ] || [ -z "$subject" ] || [ -z "$body" ]; then
    cat >&2 <<EOF
usage: admin.sh inbox-send <user_id> <kind> <subject> <body> [json-action-payload]
       kinds: notice | verification_request | system
EOF
    exit 2
  fi
  # JSON-escape via python (always available on NixOS shell)
  local payload
  payload=$(python3 -c "
import json, sys
print(json.dumps({
  'p_user_id': sys.argv[1],
  'p_kind': sys.argv[2],
  'p_subject': sys.argv[3],
  'p_body': sys.argv[4],
  'p_action_payload': json.loads(sys.argv[5]) if sys.argv[5] != 'null' else None,
}))
" "$user_id" "$kind" "$subject" "$body" "$action_payload")
  call_rpc admin_inbox_send "$payload"
}

cmd_inbox_list() {
  local user_id="$1"
  if [ -z "$user_id" ]; then
    echo "usage: admin.sh inbox-list <user_id>" >&2
    exit 2
  fi
  call_rpc admin_inbox_list_for_user "{\"p_user_id\":\"$user_id\"}"
}

cmd_users() {
  sudo -n docker exec "$DB_CONTAINER" psql -U postgres -d postgres -c "
    SELECT u.id, u.created_at, p.nickname, c.kind
    FROM auth.users u
    LEFT JOIN user_profiles p ON p.user_id = u.id
    LEFT JOIN user_credentials c ON c.user_id = u.id
    ORDER BY u.created_at DESC;
  "
}

usage() {
  sed -n '5,20p' "$0"
}

case "${1:-}" in
  purge)       shift; cmd_purge "$@" ;;
  inbox-send)  shift; cmd_inbox_send "$@" ;;
  inbox-list)  shift; cmd_inbox_list "$@" ;;
  users)       cmd_users ;;
  -h|--help|"") usage ;;
  *) echo "unknown command: $1" >&2; usage; exit 2 ;;
esac
