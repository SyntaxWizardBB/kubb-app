# ADR-0010: Identity and authentication model

- **Status**: Accepted
- **Date**: 2026-05-04
- **Supersedes** (in part): ADR-0003 §Auth — magic-link is dropped; the rest of ADR-0003 (roles, lifecycle, RLS, flows) stands.
- **Depends on**: ADR-0009 (self-hosted Supabase on Hetzner)

## Context

ADR-0003 originally picked Supabase Auth with email magic-link as the only authentication method. Two issues with that pick became clear:

1. **Email-deliverability** is fragile and rate-limited (Supabase free tier caps; even self-hosted needs a real SMTP gateway). Owner wants to remove email from the critical path entirely.
2. **No path for users who do not want an account** at all. Casual-friend-match players, walk-in tournament participants, and privacy-minded users should be able to use the app without giving up an email address.

## Decision

Two parallel auth paths, user picks at onboarding.

### Path A — OAuth (recommended for most users)

- **Google Sign-In** and **Apple Sign-In** via Supabase Auth's built-in OAuth providers.
- Friction: one tap on a known account.
- Recovery: handled by the OAuth provider — not our problem.
- Account is durable, syncs across devices automatically.
- Required for tournament organizers (audit-trail value of a known identity).

### Path B — Anonymous keypair account

- On onboarding, the client generates an Ed25519 keypair locally.
- Public key + a user-chosen nickname becomes the account identity. No email, no third-party login.
- The private key is the credential. It lives in the OS secure-storage (Keychain on iOS, Keystore on Android, Secret Service on Linux, encrypted file on web with a passphrase).
- Backup is a separate, opt-in step — see below.
- Allowed for: training mode, friend-match participation, tournament registration as a player.
- Not allowed for: organizing tournaments (force OAuth there for accountability).

### Backup of the anonymous account

The Bitcoin-mnemonic UX is overkill for this domain. Lost account = lost stats and tournament history, not lost money. The chosen scheme:

1. User picks a passphrase at backup time (separate from device-unlock).
2. Client derives a key with **Argon2id** (memory-hard KDF, modern parameters).
3. The Ed25519 private key is encrypted with that derived key (XChaCha20-Poly1305).
4. The ciphertext is uploaded to the server, indexed by `nickname` (or by a hash of nickname + a server-issued salt to prevent enumeration).
5. On a new device, the user enters nickname + passphrase. Client downloads the ciphertext, derives the key from the passphrase, decrypts.

Server **never** sees the passphrase or the unencrypted private key. If the user forgets the passphrase, there is no recovery — by design. The UI must make this clear at backup time.

Optional power-user export: QR code containing the private key, for users who want to manage backups themselves.

### Account upgrade path

Anonymous users can upgrade to OAuth at any time:

- "Link Google account" / "Link Apple account" in profile settings.
- Server keeps the same internal user ID; OAuth provider becomes an additional credential, the keypair stays valid as a fallback.
- This is the preferred path for users who started anonymous and now want a tournament-organizer role.

### Multi-credential users

A user is not limited to one credential. The same `auth.users.id` may have any combination of `oauth_google`, `oauth_apple`, and `keypair` rows in `user_credentials` (the table already encodes multi-row-per-user — see *Data model deltas*).

- **Both Google and Apple linked**: both OAuth identities point to the same internal `user_id`. Either provider can sign the user in; the resulting session is indistinguishable. Stats, tournaments, friends, and roles are the same record regardless of which credential was used at sign-in.
- **Keypair plus OAuth**: same shape — keypair stays valid as a fallback after an upgrade, and additional OAuth providers can be linked on top.
- **Account-link screen**: lists every linked credential for the current user, grouped by kind (Google, Apple, keypair). Each row shows the provider, the linked-at timestamp, and the credential's account hint (e.g. masked email for OAuth, nickname for keypair). "Link Google" / "Link Apple" actions are visible whenever the corresponding `user_credentials` row is missing for the active user; this replaces the earlier "only on anonymous accounts" gating.
- **Sign-in collision rule**: if a user signs in via an OAuth provider whose `oauth_subject` is not yet linked to any internal user, Supabase Auth creates a new `auth.users` row as usual. We do **not** auto-merge by email — merging existing accounts is a destructive operation and must be an explicit, authenticated action.
- **Detach path (backlog)**: removing a linked credential ("Unlink Google") is intentionally **out of scope for this revision**. It needs a guard rail (don't strand the user without any credential), an audit entry, and a confirmation flow. Tracked as backlog under R18-F-24 follow-ups; until shipped, the account-link screen only adds credentials, it does not remove them.

### Removed from ADR-0003

- Email magic-link authentication.
- The "Magic-link deliverability" open question in ADR-0003 §Open questions is resolved by removal.
- The walk-in flow stays unchanged: walk-ins still produce an `applicant_id = NULL` row with `walk_in_name`. They have no client-side auth at all.

## Data model deltas (against ADR-0003)

| Table | Change |
|---|---|
| `auth.users` | Now backed by Supabase Auth's OAuth flow OR a custom row created on anonymous-account creation. Both share the same `id` (uuid) primary key. |
| `user_profiles` | Adds `nickname_unique` (citext, unique) — needed because nickname is now an identifier for keypair-account lookups, not just a display string. |
| `user_credentials` | New table. Columns: `user_id` FK, `kind` (enum: `oauth_google`, `oauth_apple`, `keypair`), `public_key` text NULL, `oauth_subject` text NULL, `created_at`. Multi-row per user (one anonymous user can later add OAuth). |
| `user_keypair_backups` | New table. Columns: `user_id` FK, `nickname_hash` text indexed, `ciphertext` bytea, `kdf_salt` bytea, `kdf_params` jsonb, `created_at`, `updated_at`. One row per user; updated on passphrase change. |

RLS policies for the new tables: `user_credentials` readable only by owner; `user_keypair_backups` readable by anyone who knows the `nickname_hash` (that is the lookup mechanism for cross-device restore — the ciphertext is useless without the passphrase).

## Auth challenge for keypair accounts

Standard request signing:

1. Client requests a short-lived challenge string from the server.
2. Client signs `challenge || timestamp` with the Ed25519 private key.
3. Server verifies the signature against the stored public key for the claimed `user_id`, issues a JWT scoped like a normal Supabase session.
4. JWT lifetime: 1h. Refresh via re-signing.

Implementation: a custom Postgres function + a small server endpoint (Edge Function or a tiny Dart sidecar). Supabase Auth's existing JWT issuance is reused.

## Alternatives considered

- **Email + password** — rejected: password reuse, breach surface, password-reset still needs email.
- **Magic-link only** (as in ADR-0003) — rejected: keeps email in the critical path, deliverability fragile.
- **Passkeys / WebAuthn** as the anonymous path — considered. Pro: no passphrase to remember, biometric unlock. Con: cross-device sync still requires a platform account (iCloud Keychain, Google Password Manager) which defeats "anonymous". Could be added later as a third path for users who want it.
- **BIP39 mnemonic backup** — rejected: scary UX, overkill for the threat model. Lost account is annoying, not financially catastrophic.
- **No backup at all for anonymous accounts** ("device-only") — rejected: too brittle, users will lose stats on phone replacement. The encrypted server backup adds one passphrase prompt and removes the foot-gun.

## Consequences

- No email infrastructure required. SMTP gateway is not in the v1 stack.
- Two onboarding flows to design and test (OAuth and anonymous). UI cost is real but bounded — both flows reuse the same post-login screens.
- Keypair handling needs a small crypto library — `cryptography` package on pub.dev (well-maintained, ed25519 + argon2 + xchacha20-poly1305 supported).
- OS secure-storage integration: `flutter_secure_storage` covers iOS Keychain, Android Keystore, Linux Secret Service, and Windows Credential Vault. Web needs a passphrase-on-each-load fallback.
- Server backup of encrypted keypair adds one new table and a small endpoint pair (upload ciphertext, lookup ciphertext by nickname-hash). Not architecturally significant.
- Tournament organizers are forced to use OAuth (audit-trail), which the security-checker agent enforces at the RLS layer.
- ADR-0003 §Auth is dead code from now on; the rest of ADR-0003 (roles, tournament lifecycle, applications, RLS, walk-ins, client integration) stays in force.
