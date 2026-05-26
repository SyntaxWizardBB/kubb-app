-- pgTAP setup hook for `supabase test db`.
--
-- Aktiviert die pgTAP-Extension im `extensions`-Schema (Standard-Pattern
-- des Supabase-CLI-Stacks). Wird alphabetisch zuerst ausgefuehrt, daher
-- der `000-`-Prefix; vgl. docs/plans/m2-ko-bracket/pgtap-feasibility.md.
--
-- Tests koennen pgTAP-Funktionen ueber den voreingestellten
-- `extra_search_path` (`public`, `extensions`; siehe `supabase/config.toml`)
-- unqualifiziert ansprechen.

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
