# Local Supabase stack — developer setup

Local Supabase runs in Docker via the official Supabase CLI. The CLI
boots Postgres, GoTrue (auth), PostgREST (REST API), Realtime, Studio,
and an Inbucket SMTP catch-all on the standard CLI ports.

Production hosting (Hetzner self-hosted) is a separate concern — see
`docs/adr/0009-hosting-model.md`.

## One-time setup

1. **Install Docker.** Any recent Docker Desktop or Docker Engine works.
   Verify with `docker --version`.
2. **Install the Supabase CLI.** Pick whichever fits your environment:
   - Linux / macOS via Homebrew: `brew install supabase/tap/supabase`
   - Linux via direct download: see <https://github.com/supabase/cli/releases>
   - npm (global, works everywhere Node does): `npm install -g supabase`
3. **Create a local env file:** `cp tools/supabase-local/.env.example
   tools/supabase-local/.env`. Leave the OAuth client IDs empty until
   you have real Google/Apple credentials — the keypair-only auth path
   works without them.

## Daily use

From the repo root:

| Command | What it does |
|---|---|
| `supabase start` | Boots the full local stack. First run pulls Docker images (~2 GB). |
| `supabase status` | Shows URLs and the local anon/service-role keys. |
| `supabase stop` | Stops the stack but keeps the data volume. |
| `supabase stop --no-backup` | Stops and wipes the data volume. |
| `supabase db reset` | Drops the local DB and re-applies all migrations + seed. |

After `supabase start`, the standard endpoints are:

| Service | URL |
|---|---|
| API gateway | <http://localhost:54321> |
| Postgres | `postgresql://postgres:postgres@localhost:54322/postgres` |
| Studio (admin UI) | <http://localhost:54323> |
| Inbucket (SMTP catch-all) | <http://localhost:54324> |

## Loading OAuth credentials

The Google and Apple OAuth flows need real client IDs to test end-to-end.
Until those exist, the anonymous keypair path is the only working
sign-in. To wire up OAuth later:

1. Create OAuth apps in the Google Cloud Console and Apple Developer
   Portal. Set the callback to `http://localhost:54321/auth/v1/callback`
   for local dev.
2. Fill in `SUPABASE_AUTH_GOOGLE_CLIENT_ID`, `SUPABASE_AUTH_GOOGLE_SECRET`,
   `SUPABASE_AUTH_APPLE_CLIENT_ID`, `SUPABASE_AUTH_APPLE_SECRET` in
   `tools/supabase-local/.env`.
3. Source the env file before starting: `set -a && source
   tools/supabase-local/.env && set +a && supabase start`.

## Why the Supabase CLI and not a hand-rolled docker-compose

The CLI runs the same Docker images as a self-hosted Supabase deploy and
hides ~500 lines of compose YAML behind a config file we control
(`supabase/config.toml`). Updates from the Supabase team flow in by
upgrading the CLI; we do not own the wiring. The Hetzner production
setup will pin specific image versions explicitly when M2 is deployed.

If you cannot install the CLI for some reason, the upstream
docker-compose template lives at
<https://github.com/supabase/supabase/tree/master/docker> — clone it,
copy our env into it, and you get the same stack at the same ports.

## Migrations and seed

- SQL migrations live in `supabase/migrations/`. They are applied in
  filename order on `supabase start` and on `supabase db reset`.
- The auth-feature schema lands here in M2-T01 through M2-T04 (tables,
  RLS, custom Postgres functions for the keypair flow).
- `supabase/seed.sql` is the place for non-migration test data; empty
  for now.

## Smoke-testing the stack

Once `supabase start` reports healthy:

```bash
# API gateway returns the standard hello payload
curl -s http://localhost:54321/rest/v1/ | head

# Postgres is reachable
psql postgresql://postgres:postgres@localhost:54322/postgres -c "select version();"
```

The full curl-based auth smoketest lands in M2-T05.
