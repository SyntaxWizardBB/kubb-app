-- M2-T01 — Auth tables for OAuth + anonymous keypair flow.
-- Implements the schema spec from ADR-0010 §Data model and from
-- docs/plans/auth-oauth-keypair/architecture.md §Server-Schema-Deltas.

-- citext for case-insensitive nickname uniqueness.
CREATE EXTENSION IF NOT EXISTS citext;

-- pgcrypto exposes gen_random_uuid().
CREATE EXTENSION IF NOT EXISTS pgcrypto;


-- ----------------------------------------------------------------------
-- user_credentials
--
-- One row per credential per user. A keypair-only user has exactly one
-- row (kind='keypair'). After upgrading to OAuth, a second row appears
-- with the same user_id and kind='oauth_<provider>'.
-- ----------------------------------------------------------------------

CREATE TABLE user_credentials (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  kind          text        NOT NULL CHECK (kind IN (
                              'oauth_google',
                              'oauth_apple',
                              'keypair'
                            )),
  public_key    text        NULL,    -- base64; non-null when kind='keypair'
  oauth_subject text        NULL,    -- non-null when kind starts with 'oauth_'
  created_at    timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT user_credentials_shape CHECK (
    (kind = 'keypair'
       AND public_key IS NOT NULL
       AND oauth_subject IS NULL)
    OR (kind <> 'keypair'
       AND oauth_subject IS NOT NULL
       AND public_key IS NULL)
  )
);

CREATE INDEX user_credentials_user_id_idx ON user_credentials(user_id);

-- One OAuth subject can only ever map to one credential row.
CREATE UNIQUE INDEX user_credentials_oauth_subject_idx
  ON user_credentials(kind, oauth_subject)
  WHERE oauth_subject IS NOT NULL;

-- One public_key can only ever back one user.
CREATE UNIQUE INDEX user_credentials_public_key_idx
  ON user_credentials(public_key)
  WHERE public_key IS NOT NULL;


-- ----------------------------------------------------------------------
-- user_keypair_backups
--
-- One row per keypair user. Holds the user's encrypted private key
-- so they can restore on a new device by entering nickname + passphrase.
-- nickname_hash = sha256(nickname || server_salt) so that an attacker
-- who steals the table cannot trivially map it back to nicknames.
-- ----------------------------------------------------------------------

CREATE TABLE user_keypair_backups (
  user_id        uuid        PRIMARY KEY
                              REFERENCES auth.users(id) ON DELETE CASCADE,
  nickname_hash  text        NOT NULL UNIQUE,
  ciphertext     bytea       NOT NULL,
  kdf_salt       bytea       NOT NULL,
  kdf_params     jsonb       NOT NULL,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX user_keypair_backups_nickname_hash_idx
  ON user_keypair_backups(nickname_hash);


-- ----------------------------------------------------------------------
-- user_profiles extensions (the base table is created by ADR-0003 in a
-- later migration; here we only declare the columns the auth feature
-- depends on).
-- ----------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS user_profiles (
  user_id              uuid        PRIMARY KEY
                                    REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at           timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE user_profiles
  ADD COLUMN IF NOT EXISTS nickname             citext UNIQUE,
  ADD COLUMN IF NOT EXISTS avatar_color         text NULL,
  ADD COLUMN IF NOT EXISTS onboarding_completed boolean NOT NULL DEFAULT false;
