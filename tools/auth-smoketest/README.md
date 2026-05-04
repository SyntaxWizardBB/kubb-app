# auth-smoketest

End-to-end checks of the local auth stack. Confirms that the SQL
migrations under `supabase/migrations/` produced the expected tables,
RLS policies, helper functions and that PostgREST refuses anonymous
reads of credential rows.

## Prerequisites

- Local Supabase stack running (`supabase start` from the repo root).
- `psql`, `curl`, `jq` on `PATH`.

## Run

```bash
bash tools/auth-smoketest/run.sh
```

The script auto-detects the local anon key via `supabase status`. If
you run against a different stack, override the relevant env vars:

```bash
API_URL=https://kubb.example.com \
PSQL_URL=postgresql://app:secret@db.example.com:5432/app \
ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9... \
bash tools/auth-smoketest/run.sh
```

Exits 0 on success, non-zero (with the failed check named) on the first
failure.

## What it does NOT cover

- The Dart-side encryption / Argon2id derivation. Those have their own
  unit tests (`flutter test test/features/auth/data/`).
- Real Ed25519 verify on the server. The current `auth.keypair_verify`
  ships a TODO for the pgsodium hookup; the smoketest only checks that
  the challenge issuance and lookup round-trip work, not that an
  invalid signature is rejected.
- JWT issuance for verified users. That is also a Hetzner-integration
  decision (edge function vs. anonymous-session-on-restore).
