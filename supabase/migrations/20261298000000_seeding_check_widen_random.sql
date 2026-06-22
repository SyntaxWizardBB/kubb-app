-- Widen tournament_stages.seeding to allow 'random' (additive, deploy-safe).
--
-- Welle M3 der Seeding-Spec (docs/specs/stage-seeding-spec.md §2 + §6): die
-- Setzlisten-Quelle "Zufall" wird ergänzt. Die Dart-Seite schreibt den neuen
-- Wire-String StageSeedingSource.random -> 'random' (M3-A/B). Diese Migration
-- bringt die CHECK-Constraint nach, damit der Wert serverseitig speicherbar ist.
--
-- Deploy-Sicherheit (Muster 20261293000000): die Constraint wird zu einem
-- SUPERSET geweitet. Alle bisherigen Werte bleiben gültig, 'random' kommt
-- additiv dazu. So gibt es kein Fenster, in dem die Constraint einen Wert
-- ablehnt, den eine laufende App (alt oder neu) noch schreiben könnte. DROP
-- IF EXISTS + ADD läuft in einer Transaktion (jede Migration ist eine).

ALTER TABLE public.tournament_stages
  DROP CONSTRAINT IF EXISTS tournament_stages_seeding_check;
ALTER TABLE public.tournament_stages
  ADD CONSTRAINT tournament_stages_seeding_check CHECK (seeding IN (
    'from_elo','from_prev_ranking','manual','random','as_routed'));
