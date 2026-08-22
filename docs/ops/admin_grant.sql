-- Admin- & Veranstalter-Rechte vergeben (Bootstrap per SQL, Auth-Redesign D2).
-- Ausführen im Supabase Dashboard → SQL Editor (läuft als service_role, umgeht RLS).
-- nickname ist citext → Vergleich ist case-insensitive.

-- 1) Alle User ansehen (nickname herausfinden):
select user_id, nickname, is_admin, can_found_clubs, suspended_at, created_at
from public.user_profiles
order by created_at desc;

-- 2) Admin-Rechte GEBEN (volles Admin-Dashboard + Impersonation):
update public.user_profiles set is_admin = true where nickname = 'NICKNAME';

-- 3) Veranstalter-Rechte GEBEN (darf Turniere erstellen → "+ Neues Turnier"-FAB):
update public.user_profiles set can_found_clubs = true where nickname = 'NICKNAME';

-- 4) Rechte ENTZIEHEN:
update public.user_profiles set is_admin = false        where nickname = 'NICKNAME';
update public.user_profiles set can_found_clubs = false  where nickname = 'NICKNAME';

-- 5) Konto sperren / entsperren (blockt keypair-verify + oauth-reconcile):
update public.user_profiles set suspended_at = now()  where nickname = 'NICKNAME';  -- sperren
update public.user_profiles set suspended_at = null   where nickname = 'NICKNAME';  -- entsperren

-- ----------------------------------------------------------------------
-- Lokal brauchst du das hier meistens nicht: `supabase db reset` legt über
-- supabase/seed.sql einen Veranstalter `veranstalter` (Passwort kubb1234),
-- sechzehn Spieler und ein startbereites Schoch-Turnier an.
