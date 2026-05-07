# ADR-0011: BIP-39 mnemonic for anonymous accounts, admin operations, in-app inbox

- **Status**: Accepted
- **Date**: 2026-05-05
- **Supersedes** (in part): ADR-0010 §Path B "Backup of the anonymous account" and the `BIP39 mnemonic backup — rejected` line in §Alternatives. The OAuth path, the keypair-challenge protocol, the upgrade path to OAuth, and the data-model deltas for `user_credentials` from ADR-0010 stand unchanged.

## Context

After implementing ADR-0010's free-form passphrase + Argon2id + server-side encrypted backup, two issues surfaced:

1. **Custodial-vs-non-custodial muddle.** The "encrypted backup at the server, restore-by-nickname-hash" model is one foot in each camp. The server stores the ciphertext, the user holds the passphrase. UX-wise it looks like "log in with nickname + passphrase", which conditions users to think the server can recover them — it can't. UX intent and crypto reality drift apart.
2. **Multiple bugs hid behind that hybrid design** — base64-vs-bytea encoding mismatches, nonce-prepend bugs, PostgREST embedded-join failures, `compute_nickname_hash` without proper schema-qualifier. Each was fixable but the surface area was disproportionate.

Separately, the operator (project owner) needs admin tooling: ability to purge specific accounts, ability to send messages / verifications to users in-app. ADR-0010 implicitly assumed Supabase Studio is enough; in practice running a CASCADE delete in Studio is too easy to fat-finger and there is no in-app communication channel at all.

## Decision

Three coordinated changes.

### Change 1 — Replace passphrase backup with BIP-39 mnemonic, deterministic key derivation, no server-side backup

The Bitcoin-wallet model:

1. On signup, the client generates a **BIP-39 mnemonic**. Length is user-selectable: **12, 15, or 18 words** (the user picks; default 12). 21- and 24-word lengths are not exposed in the UI to keep the choice tractable, but the underlying helpers accept any valid BIP-39 length so we can lift the cap later without a schema change.
2. The mnemonic → 64-byte BIP-39 seed (PBKDF2-HMAC-SHA512, 2048 iterations, salt = `"mnemonic"`). The first 32 bytes of the seed become the Ed25519 secret seed. Public key is derived from there.
3. Public key is uploaded once to `user_credentials`. **The mnemonic itself never leaves the device.** No ciphertext, no Argon2id, no server-side backup table.
4. Restore on a new device: user enters the mnemonic words. Client validates against the BIP-39 wordlist + checksum, derives the keypair, runs the existing challenge / sign / verify with the keypair-verify edge function. Lookup is **by public key only** — no nickname lookup, no `nickname_hash`.

The optional BIP-39 25th-word passphrase is **not** offered. It would add a second secret to memorize for marginal extra security; the threat model (lost stats, not lost money) does not justify the UX cost.

**No recovery.** Lost mnemonic = lost account. The UI at signup must make this unmissable: a confirm-the-mnemonic step where the user re-enters 3 random words from their freshly generated phrase before the account is finalized.

### Change 2 — In-app inbox

A persistent message store inside the app, addressable per user, written by admins (and later, by automated system events). Replaces all "we'll send an email" assumptions:

- **Message kinds**: `notice`, `verification_request`, `system`. Discriminated by `kind` so the UI can render appropriately (notice = read-only banner; verification_request = inline action button → user replies; system = warnings / account state changes).
- **Schema**: `user_inbox_messages(id, user_id FK, kind, subject, body, action_payload jsonb, sent_at, read_at, replied_at, archived_at)`. RLS: user reads/marks-read their own; admin role inserts via SECURITY DEFINER RPC.
- **Verification flow** (admin-driven): admin sends `verification_request` with a payload describing what to verify. User opens inbox, sees the request, taps a Confirm/Deny action. Their response is recorded against the message and the admin polls / receives via a separate admin-facing query. No federated identity provider involved.
- **Push notifications**: out of scope for this ADR. The inbox itself is the source of truth; push is an optional notification channel layered on top later. For now, a small badge counter on the app's main shell indicates unread messages.

### Change 3 — Admin operations RPC + tooling

A small set of `SECURITY DEFINER` Postgres functions, callable only from the `service_role` key (not from `authenticated`):

- `admin_purge_account(p_user_id uuid)` — deletes the user from `auth.users`, which cascades to `user_profiles`, `user_credentials`, `user_inbox_messages`, plus any feature-domain tables that reference `auth.users(id)`. Logs the purge to a future `admin_audit` table (TODO when audit is needed).
- `admin_inbox_send(p_user_id uuid, p_kind text, p_subject text, p_body text, p_action_payload jsonb)` — inserts into `user_inbox_messages`.
- `admin_inbox_list_for_user(p_user_id uuid)` — returns the inbox of a specific user (admin debugging).

Invocation is via a small CLI script `tools/admin/admin.sh` that wraps `curl` against the local Supabase instance using the service-role key. Production will eventually want a small admin web page; that is deferred.

## Data model deltas (against ADR-0010 §Data model)

| Table | Change |
|---|---|
| `user_keypair_backups` | **Dropped.** No more ciphertext storage. |
| `user_credentials` | Unchanged in shape. `kind` enum still `{oauth_google, oauth_apple, keypair}`. Still one row per credential, multiple per user allowed. |
| `auth_server_salt` | **Effectively unused** — kept as a no-op table for now since dropping it would require touching old migrations. Drops in a follow-up cleanup. |
| `keypair_challenges` | Unchanged. |
| `user_inbox_messages` | **New.** Per-user message store, RLS scoped to owner. Admins write via SECURITY DEFINER. |

The `compute_nickname_hash` SQL function is dropped; nickname is back to being a display string only and is no longer hashed for credential lookup.

## Username constraints

`user_profiles.nickname` stays `citext UNIQUE NOT NULL`. The username is set during onboarding (both OAuth and mnemonic paths) and is the public display name. It is **not** part of the auth lookup anymore — only the public key is — but uniqueness is enforced for tournament-history clarity (no two players named "kubb_master").

## Migration strategy

The auth branch has no production users. Migration is therefore destructive:

1. Drop `user_keypair_backups`, drop the `keypair_rotate_backup`, `compute_nickname_hash`, `auth_server_salt` content.
2. Replace `keypair_attach` with `keypair_register` — same idea (one transaction registers credential + profile) but no `ciphertext`/`kdf_salt`/`kdf_params` parameters.
3. Add `user_inbox_messages` table and `admin_*` RPCs.
4. Reset all test users (`TRUNCATE auth.users CASCADE`).

## Consequences

- Whole class of bugs disappears: no more bytea-vs-base64 encoding worries, no AEAD nonce framing, no Argon2id parameter migrations.
- Onboarding gets a "write down your mnemonic" screen that is non-skippable. UX-wise this is a deliberate friction point — the cost of the no-recovery promise.
- A user who loses their mnemonic and never wrote it down has no recourse. The owner can `admin_purge_account` to free the username for a re-signup, but stats / tournament history under the old account are gone.
- Inbox feature unlocks the "support contacts user" pattern without an email pipeline. Same channel can be reused for system notifications later (lock / unlock account, tournament invitations, etc.).
- Admin tooling is local-CLI only for now. Production admin needs a thin admin UI and audit log; tracked as a follow-up.
- 21- and 24-word mnemonic lengths are deliberately hidden from the UI. Power users who want them can be unlocked later via a settings toggle without a schema change.
