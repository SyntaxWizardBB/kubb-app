# ADR-0040: Public-Read-Grant-Schicht und security_invoker fuer Spectator-/Season-Flaechen

- **Status**: Accepted
- **Date**: 2026-06-23
- **Depends on**: ADR-0023 (Spectator-Public-Read-RLS), ADR-0026 (Anon-Spectator-Revision), ADR-0013 (Solo-Match server-shaped)

## Context

In der lokalen DB (Migrationen bis 20261306000000) halten `anon` und
`authenticated` auf allen oeffentlichen bzw. sichtbarkeits-gateten
Read-Flaechen nur `REFERENCES`/`TRIGGER`/`TRUNCATE` — **kein** `SELECT`,
**kein** `INSERT`. Nachgewiesen ueber `information_schema.role_table_grants`.

Ursache: Die Tabellen gehoeren der Rolle `postgres`. Deren
`ALTER DEFAULT PRIVILEGES` fuer von `postgres` erzeugte public-Tabellen
gewaehrt `anon`/`authenticated` nur `Dxt` (kein `SELECT`) und
ueberschreibt damit die permissive `supabase_admin`-Default-ACL, die auf
Hosted-Supabase greift. Folge: die korrekt formulierten Read-Policies
sind tot — ein direkter `anon`/`authenticated`-Table-Read scheitert mit
`42501`, bevor RLS ueberhaupt evaluiert wird. Betroffen sind die
pgtap-Vertraege in `team_schema_test`, `public_rls_test`,
`profile_visibility_rls_test`, `season_rls.test`.

Zwei weitere Befunde kamen beim Schliessen der Grant-Luecke ans Licht:

1. **View-Leak `v_season_standings`**: Der View ist per `GRANT SELECT`
   freigegeben, laeuft aber als `postgres`-Owner (`rolbypassrls = t`,
   live bestaetigt) ohne `security_invoker`. Auf PG15 laeuft ein View
   ohne dieses Flag mit Owner-Rechten — er umgeht damit die RLS der
   Basis-Tabelle. `anon` sah `draft + open + closed` (3 Zeilen statt 2);
   draft-Standings leckten an anonyme Clients durch.

2. **PUBLIC-skopierte Read-Policies auf der tournaments-Flaeche**: Die
   `*_read`-Policies (`tournaments_public_read`,
   `tournament_matches_read`, `tournament_participants_read`,
   `tournament_participants_self_read`,
   `tournament_set_score_proposals_read`) wurden ohne `TO`-Klausel
   angelegt und greifen damit fuer PUBLIC (= auch `anon`). Ihre
   Praedikate gaten auf `status <> 'draft'` / `auth.uid()`, **nicht** auf
   das `public`-Flag. Solange `anon` keinen Grant hatte, war das
   folgenlos. Mit dem SELECT-Grant wuerden sie `anon` non-public-Turniere
   (live, nicht-draft) durchlecken, weil RLS permissive Policies
   OR-verknuepft.

## Decision

Eine additive, abwaertskompatible Migration
(`20261307000000_fix_public_read_grants.sql`):

1. **GRANT SELECT** fuer `anon, authenticated` auf `teams`, die vier
   tournaments-Spectator-Tabellen, `seasons`, `season_tournaments`,
   `season_standings_awards`. Fuer `user_profiles` ebenfalls beide Rollen
   (anon bleibt mangels Policy deny — der Grant macht den Deny als
   sauberen 0-Rows-Read statt als `42501` sichtbar). `friendships` nur
   `authenticated` (Pflicht-Dependency des friends_only-Policy-Zweigs).

2. **GRANT INSERT** auf `season_standings_awards` nur `authenticated`,
   gebunden durch das bestehende `league_admin`-WITH-CHECK. Bewusst kein
   UPDATE/DELETE — der Append-only-Kontrakt (plus T6-Trigger) bleibt.

3. **Role-Scoping** der fuenf `*_read`-Policies auf `TO authenticated`.
   Die Policies bleiben bestehen, nur ihre Rolle wird auf die
   tatsaechliche Zielgruppe verengt. `anon` liest danach ausschliesslich
   ueber die `*_anon_public_read`-Policies (`public = true AND non-draft`).
   Keine Abschwaechung des authenticated-Pfads.

4. **`ALTER VIEW v_season_standings SET (security_invoker = true)`**.
   Der View erbt damit die RLS des Aufrufers; in Kombination mit dem
   SELECT-Grant auf der Basis-Tabelle sieht `anon` nur noch open/closed —
   ueber View und Basis-Tabelle identisch. Single Source of Truth statt
   dupliziertem Filter.

Keine Policy, Tabelle, Spalte oder Enum wird entfernt oder abgeschwaecht.

## Alternatives considered

- **Test-Grants statt Migration**: kaschiert die Vertragsluecke und macht
  die Tests inkonsistent zur Laufzeit. Verworfen — der Fix gehoert in
  eine Migration.

- **FORCE ROW LEVEL SECURITY gegen den View-Leak**: live getestet und
  wirkungslos. FORCE bindet nur den Owner an RLS, hebt aber `BYPASSRLS`
  nicht auf; der DEFINER-View (`postgres`) leckt weiter draft. Auch fuer
  die Basis-Tabellen unnoetig: die Tests switchen via `set_config('role',
  ...)` auf die echte `anon`/`authenticated`-Rolle (kein BYPASSRLS), die
  Policy filtert also ohne FORCE. Verworfen.

- **draft-Filter direkt im View**: schliesst den Leak, dupliziert aber
  das RLS-Praedikat (Drift-Risiko), laesst den Basis-Tabellen-Read weiter
  broken und ist nicht zukunftssicher gegen feinere RLS. Verworfen
  zugunsten von `security_invoker`.

- **tournaments-Tabellen RPC-only belassen** (ADR-0026 Strategie A): die
  Tabellen-Policies sind dort nur Defense-in-Depth. Verworfen zugunsten
  des Grants, damit die deklarierte zweite Verteidigungslinie real wirkt;
  bei Gegenentscheid waeren `public_rls_test` cases 3-6 auf `42501` zu
  re-baselinen.

- **`public_tournament_roster_view` ebenfalls auf `security_invoker`**:
  bewusst NICHT umgesetzt. Der View joint `tournament_roster_slots`
  (RLS=false) und das jetzt visibility-gatete `user_profiles`. Ein direkter
  anon-Read (der View ist an anon grantet) wuerde unter `security_invoker`
  entweder `42501` werfen (keine Basis-Grants) oder bei zusaetzlichem
  Grant ueber die RLS-lose `tournament_roster_slots` ungefiltert
  exponieren. Der View bleibt DEFINER mit reiner display_name-Projektion
  (keine PII) — exakt das Verhalten, das `public_rls_test` case 9
  asserted. Die `public_*`-RPCs sind SECURITY DEFINER und lesen den View
  als `postgres`, sind also unberuehrt.

- **Breites `ALTER DEFAULT PRIVILEGES FOR ROLE postgres ... GRANT SELECT`**:
  wuerde die Ursache global beheben, ist aber eine weitreichende
  Policy-Aenderung. Ausgelagert als optionale Folgeentscheidung; der
  chirurgische Einzel-Grant ist das Minimum.

## Consequences

Die oeffentlichen/gateten Read-Pfade funktionieren erstmals real:

- `teams` blanket-public (FR-PUB-9).
- tournaments nur `public = true` + non-draft fuer anon; die
  PUBLIC-Policies sind auf `authenticated` verengt, kein non-public-Leak.
- `user_profiles` sichtbarkeits-gated; anon bleibt deny (0 Zeilen).
- seasons/awards nur open/closed; der draft-Leak in `v_season_standings`
  ist geschlossen (live: anon sieht nur open+closed, ueber View und
  Basis-Tabelle identisch je 0 draft-Zeilen).

Alle anon-Write-Verbote bleiben `42501` (SELECT-Grant impliziert kein
INSERT). Append-only von `season_standings_awards` bleibt.

pgtap: `team_schema_test`, `public_rls_test`,
`profile_visibility_rls_test`, `season_rls.test` laufen gruen, indem das
**Modell** gefixt ist (Grant + Role-Scoping + security_invoker), nicht
der Test geschwaecht.

`profile_visibility_rls_test` case 5 wurde re-baselined: die
Original-Variante jointe direkt ueber `matches` + `match_participants`.
Der match/-Kontext ist server-shaped und RPC-only (ADR-0013);
`match_participants_participant_read` enthaelt einen self-referentiellen
EXISTS, der bei jedem direkten authenticated-Read `infinite recursion
detected in policy` wirft. Diese Tabellen sind bewusst nicht grantet.
Die Visibility-Garantie haengt allein an der `user_profiles`-Projektion
(Nickname-Quelle der Stats-Surfaces) — und die prueft der re-baselinete
Case direkt unter der echten stranger-Rolle, ohne den rekursiven
match-Pfad. Die zwei Fixture-TEMP-Tabellen-Grants (`_pv_ctx`) wurden
ergaenzt, analog `_pub_ctx`/`_t7_ctx` in den Schwester-Suiten.

Auf Hosted-Supabase sind die expliziten Grants idempotent/harmlos
(`supabase_admin` grantet sie dort ohnehin). `security_invoker`-Views
brauchen echte Caller-Grants auf die Basis-Tabelle — durch die hier
gesetzten Grants erfuellt.
