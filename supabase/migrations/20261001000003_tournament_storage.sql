-- Tournament feature — P6 Phase 1b: Storage for rules + site-map PDFs.
--
-- A single public bucket holds both document kinds, keyed by path
-- prefix (`rules/<uuid>.pdf`, `maps/<uuid>.pdf`). The bucket is public-
-- read because tournaments themselves are public once published; the
-- organiser uploads during the draft phase and the stored public URL is
-- persisted onto `tournaments.rules_pdf_url` / `site_map_pdf_url` via the
-- create RPC. Writes are restricted to authenticated users; an object
-- may only be updated/deleted by its uploader (`owner`).

INSERT INTO storage.buckets (id, name, public)
  VALUES ('tournament-pdfs', 'tournament-pdfs', true)
  ON CONFLICT (id) DO NOTHING;

-- Public read for every object in the bucket.
CREATE POLICY "tournament_pdfs_public_read"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'tournament-pdfs');

-- Any authenticated user may upload into the bucket.
CREATE POLICY "tournament_pdfs_authenticated_insert"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (bucket_id = 'tournament-pdfs');

-- Only the uploader may overwrite or remove their own object.
CREATE POLICY "tournament_pdfs_owner_update"
  ON storage.objects FOR UPDATE
  TO authenticated
  USING (bucket_id = 'tournament-pdfs' AND owner = auth.uid());

CREATE POLICY "tournament_pdfs_owner_delete"
  ON storage.objects FOR DELETE
  TO authenticated
  USING (bucket_id = 'tournament-pdfs' AND owner = auth.uid());
