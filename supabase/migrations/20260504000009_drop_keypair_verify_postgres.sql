-- M8-T01 — Drop the auth.keypair_verify and public.keypair_verify
-- Postgres functions in favour of the keypair-verify edge function.
--
-- The Postgres implementation never had a real Ed25519 verify; it
-- delegated the cryptographic check to a TODO marker. The edge function
-- under supabase/functions/keypair-verify/ replaces it with an actual
-- @noble/ed25519 verify and reads the same auth.keypair_challenges
-- table for TTL + single-use enforcement.
--
-- auth.keypair_challenge stays — it still issues challenges via RPC.
-- Only the verify side moves out of Postgres.

DROP FUNCTION IF EXISTS public.keypair_verify(text, text, text);
DROP FUNCTION IF EXISTS auth.keypair_verify(text, text, text);
