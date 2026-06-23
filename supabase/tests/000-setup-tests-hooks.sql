-- pgTAP setup hook for `supabase test db`.
--
-- Aktiviert die pgTAP-Extension im `extensions`-Schema (Standard-Pattern
-- des Supabase-CLI-Stacks). Wird alphabetisch zuerst ausgefuehrt, daher
-- der `000-`-Prefix; vgl. docs/plans/m2-ko-bracket/pgtap-feasibility.md.
--
-- Tests koennen pgTAP-Funktionen ueber den voreingestellten
-- `extra_search_path` (`public`, `extensions`; siehe `supabase/config.toml`)
-- unqualifiziert ansprechen.
--
-- Der Hook selbst emittiert ein leeres plan() — null Tests, aber valides TAP
-- (`1..0`), damit der Harness fuer dieses File kein 'No plan found' meldet.
-- Kein finish() bei null Tests: pgTAP raised dort 'No tests run!'.

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(0);
