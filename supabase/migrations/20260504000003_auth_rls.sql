-- M2-T02 — Row-level-security policies for the auth tables.
-- Enforces ADR-0010 §RLS plus ADR-0003 §RLS where overlap exists.

-- ----------------------------------------------------------------------
-- user_credentials
--
-- Owner-only access. Users cannot enumerate other users' credentials.
-- Inserts go through the keypair_create / linkOAuth flows which run
-- under the user's session; the policy verifies user_id matches.
-- Updates and deletes are not exposed yet — credential rotation is
-- not a v1 flow. Account deletion cascades from auth.users.
-- ----------------------------------------------------------------------

ALTER TABLE user_credentials ENABLE ROW LEVEL SECURITY;

CREATE POLICY user_credentials_owner_read ON user_credentials
  FOR SELECT
  USING (user_id = auth.uid());

CREATE POLICY user_credentials_owner_insert ON user_credentials
  FOR INSERT
  WITH CHECK (user_id = auth.uid());


-- ----------------------------------------------------------------------
-- user_keypair_backups
--
-- Anyone may read by nickname_hash — that is how a fresh-install
-- client looks up its own backup row before signing in. The ciphertext
-- is useless without the passphrase, so this exposure is acceptable
-- and required for cross-device restore. Writes are owner-only.
-- ----------------------------------------------------------------------

ALTER TABLE user_keypair_backups ENABLE ROW LEVEL SECURITY;

-- Anonymous-or-authenticated lookup. The function-side rate limit and
-- the client-side cooldown (M4-T06) protect against enumeration.
CREATE POLICY user_keypair_backups_lookup ON user_keypair_backups
  FOR SELECT
  USING (true);

CREATE POLICY user_keypair_backups_owner_insert ON user_keypair_backups
  FOR INSERT
  WITH CHECK (user_id = auth.uid());

CREATE POLICY user_keypair_backups_owner_update ON user_keypair_backups
  FOR UPDATE
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE POLICY user_keypair_backups_owner_delete ON user_keypair_backups
  FOR DELETE
  USING (user_id = auth.uid());


-- ----------------------------------------------------------------------
-- user_profiles
--
-- Owner reads and writes their own row. Public read access is opened
-- later by ADR-0003 once tournaments need to display nicknames; for
-- now the auth feature only needs owner access.
-- ----------------------------------------------------------------------

ALTER TABLE user_profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY user_profiles_owner_read ON user_profiles
  FOR SELECT
  USING (user_id = auth.uid());

CREATE POLICY user_profiles_owner_insert ON user_profiles
  FOR INSERT
  WITH CHECK (user_id = auth.uid());

CREATE POLICY user_profiles_owner_update ON user_profiles
  FOR UPDATE
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());
