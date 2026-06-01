-- Tournament feature — P6 Phase 1b: Storage for rules + site-map PDFs.
--
-- A single public bucket holds both document kinds, keyed by path
-- prefix (`rules/<uuid>.pdf`, `maps/<uuid>.pdf`). The bucket is public-
-- read because tournaments themselves are public once published; the
-- organiser uploads during the draft phase and the stored public URL is
-- persisted onto `tournaments.rules_pdf_url` / `site_map_pdf_url` via the
-- create RPC. Writes are restricted to authenticated users; an object
-- may only be updated/deleted by its uploader (`owner`).
--
-- The local stack runs with `[storage] enabled = false` (config.toml) to stay
-- lean, so `storage.buckets` is the bare init table without a `public` column
-- and `storage.objects` has no RLS surface. Guard the whole migration on the
-- storage schema being present so it is a no-op locally and only takes effect
-- where storage is actually enabled (cloud / storage-enabled envs).

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'storage' AND table_name = 'buckets'
       AND column_name = 'public'
  ) THEN
    RAISE NOTICE 'storage not enabled — skipping tournament-pdfs bucket setup';
    RETURN;
  END IF;

  INSERT INTO storage.buckets (id, name, public)
    VALUES ('tournament-pdfs', 'tournament-pdfs', true)
    ON CONFLICT (id) DO NOTHING;

  -- Public read for every object in the bucket.
  EXECUTE $ddl$
    CREATE POLICY "tournament_pdfs_public_read"
      ON storage.objects FOR SELECT
      USING (bucket_id = 'tournament-pdfs')
  $ddl$;

  -- Any authenticated user may upload into the bucket.
  EXECUTE $ddl$
    CREATE POLICY "tournament_pdfs_authenticated_insert"
      ON storage.objects FOR INSERT
      TO authenticated
      WITH CHECK (bucket_id = 'tournament-pdfs')
  $ddl$;

  -- Only the uploader may overwrite or remove their own object.
  EXECUTE $ddl$
    CREATE POLICY "tournament_pdfs_owner_update"
      ON storage.objects FOR UPDATE
      TO authenticated
      USING (bucket_id = 'tournament-pdfs' AND owner = auth.uid())
  $ddl$;

  EXECUTE $ddl$
    CREATE POLICY "tournament_pdfs_owner_delete"
      ON storage.objects FOR DELETE
      TO authenticated
      USING (bucket_id = 'tournament-pdfs' AND owner = auth.uid())
  $ddl$;
END $$;
