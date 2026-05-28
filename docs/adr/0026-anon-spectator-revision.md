# ADR-0026: Anon-Spectator-Pfad — Revision von ADR-0023 (RPC-only, anon-grants)

- **Status**: Proposed
- **Date**: 2026-05-28
- **Amends**: ADR-0023 (Spectator-View — Public-Read-RLS mit anonymem JWT)
- **Depends on**: ADR-0001 (Supabase), ADR-0003 (Auth + User-Management), ADR-0010 (Identity & Auth), ADR-0021 (Realtime-Subscription-Architecture)
- **Bezug**: Sprint-A R14-F-01/02/03, `docs/plans/sprint-a-bug-fix/anon-rls-plan.md`

## Context

Der in ADR-0023 spezifizierte Spectator-Pfad ist im aktuellen Build strukturell broken — eine spezifikationskonforme Implementierung wurde nie ausgeliefert. Die drei Bruchstellen sind unabhaengig voneinander entstanden und addieren sich zu einem nicht-funktionalen Anon-Pfad:

1. **Rollen-Mismatch zwischen Bootstrapper und RLS.** `AnonSessionBootstrapper.ensureAnonSession` in `lib/core/data/supabase/anon_session.dart` ruft `supabase.auth.signInAnonymously()`. Supabase setzt fuer diese Session den JWT-Claim `role = "authenticated"` (mit `is_anonymous = true`), nicht `role = "anon"`. Damit greifen die in `20260701000002_tournaments_public_flag.sql` deklarierten `*_anon_public_read`-Policies (`TO anon`) niemals, weil Postgres-RLS rolle-strikt evaluiert. Der anonyme Spectator ist auf Laufzeit ein `authenticated`-Caller ohne `tournament_participants`-Zeile und sieht durch die regulaeren authenticated-Policies *gar nichts*.

2. **RPC-Grant kollidiert mit Read-Pfad.** Die UI-Provider (`tournamentDetailProvider`, `tournamentMatchDetailProvider`) lesen ueber `tournament_get` / `tournament_match_get` (siehe `lib/features/tournament/data/tournament_repository.dart:191, 300`). Beide RPCs sind in `20260525000003_tournament_discovery_registration_rpcs.sql` per `GRANT EXECUTE ... TO authenticated` registriert und beginnen mit `IF auth.uid() IS NULL THEN RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501'`. Selbst wenn der Bootstrapper auf reines anon umgestellt wuerde, koennte ein anon-Caller (oder ein anonymous-authenticated-Caller ohne `auth.uid()` — je nach Pfad) die RPC nicht aufrufen. PostgREST 401/42501 vor jeder Datenlinie.

3. **Privacy-View ohne Aufrufer.** `public_tournament_roster_view` hat den expliziten `GRANT SELECT ... TO anon, authenticated`, aber im gesamten Flutter-Client gibt es null Referenzen darauf. `PublicTournamentScreen` und `PublicMatchScreen` lesen ueber die authenticated-RPCs, nicht ueber die View. Damit ist die in ADR-0023 zugesagte Spalten-Projektion (kein `user_id`, kein E-Mail) eine reine Migrations-Artefakt, kein tatsaechlicher Privacy-Anker. Sobald der Pfad funktioniert, leakt der RPC-Envelope `user_id` und `nickname` aus `tournament_participants` direkt an anonyme Spectator.

Zusaetzlich divergiert `supabase/tests/public_rls_test.sql` vom Laufzeitpfad — er testet `set_config('role', 'anon', true)` (also Pure-anon) und beweist damit, dass die Policies *unter dieser Bedingung* korrekt waeren, deckt aber nicht den realen Client-Pfad ab.

Der Owner hat in Sprint-A R14-F-01/02/03 entschieden, den Pfad zu reparieren statt zu deaktivieren. Diese Revision waehlt zwischen zwei Strategien.

## Decision

**Strategie A — Pure-anon-Pfad mit RPC-only Read.** Wir entfernen das `signInAnonymously()` aus dem Public-Routen-Bootstrap. Public-Spectator-Reads laufen ueber zwei neue dedizierte `SECURITY DEFINER`-RPCs — `public_tournament_get` und `public_tournament_match_get` — mit `GRANT EXECUTE ... TO anon` und ohne `auth.uid()`-Guard. Diese RPCs projizieren nur Public-konforme Spalten und lesen intern aus den Basistabellen plus `public_tournament_roster_view`. Die `tournaments.public = true AND status IN (...)`-Bedingung wandert aus den `TO anon`-Tabellen-Policies in den RPC-Body. Die `*_anon_public_read`-Tabellen-Policies werden in Sprint-A entweder dropgesetzt (V1) oder als Defense-in-Depth gegen direkte PostgREST-Tablezugriffe stehengelassen (V2, empfohlen).

Konkret:

### 1. Anon-Bootstrapper entfernt sich aus dem Public-Pfad

`AnonSessionBootstrapper.ensureAnonSession()` wird fuer Public-Routes nicht mehr aufgerufen. `lib/app/public_router_shell.dart` mountet die Public-Screens ohne Session-Bootstrap. Der `SupabaseClient` traegt im Header weiterhin den `apikey` (= anon-Key) — das ist Supabase-Default und reicht fuer PostgREST + Realtime mit `TO anon`-Grants. JWT-Claims sind leer, `auth.uid()` ist `NULL`, Postgres-Rolle ist `anon`. Das ist exakt der Pfad, den `public_rls_test.sql` heute schon testet.

Der Bootstrapper bleibt als Klasse erhalten — Authenticated-User-Flows (Account-Setup, Account-Upgrade) nutzen `signInAnonymously()` weiter als legitimen Schritt. Nur die Public-Spectator-Route entkoppelt sich.

### 2. Neue RPCs: `public_tournament_get` + `public_tournament_match_get`

Beide `SECURITY DEFINER`, `SET search_path = public, auth`, `GRANT EXECUTE ... TO anon, authenticated`. Kein `auth.uid()`-Check. Stattdessen vorab:

```sql
IF NOT EXISTS (
  SELECT 1 FROM public.tournaments
   WHERE id = p_tournament_id
     AND public = true
     AND status IN ('published','registration_open','registration_closed','live','finalized')
) THEN
  RETURN NULL;  -- oder leerer Set
END IF;
```

Projektion bewusst reduziert vs. `tournament_get`:

- **enthalten**: `tournament_id`, `display_name`, `format`, `status`, `started_at`, `completed_at`, `participant_count`, `matches[]` (ohne `set_score_proposals`), Standings-Snapshot, Roster aus `public_tournament_roster_view` (`display_name` only).
- **nicht enthalten**: `created_by`, `participants[*].user_id`, `participants[*].nickname` aus `user_profiles`, `audit_tail`, `set_score_proposals`. Diese Felder existieren in `tournament_get` aus legitimen Owner-/Participant-Gruenden und gehoeren nicht in den anonymen Envelope.

`public_tournament_match_get(p_match_id uuid)` analog: Match-Header + finaler Score + Status, ohne Proposals und ohne Submitter-IDs.

### 3. Client-Repository `PublicTournamentRepository`

Neuer Read-only Repository unter `lib/features/tournament/data/public_tournament_repository.dart` mit zwei Methoden:

- `Future<PublicTournamentDetail?> getPublicTournamentDetail(TournamentId id)`
- `Future<PublicMatchDetail?> getPublicMatchDetail(TournamentMatchId id)`

Eigene Wire-Models (`public_tournament_models.dart`) — die existierenden `TournamentDetail`/`TournamentMatchRef` enthalten Felder (z.B. `participantUserId`), die der Public-Envelope nicht liefert. Saubere Trennung verhindert "Null-Splatter" und macht die Privacy-Grenze typsicher.

Die Public-Screens (`PublicTournamentScreen`, `PublicMatchScreen`) wechseln vollstaendig auf die neuen Provider (`publicTournamentDetailProvider`, `publicMatchDetailProvider`) und nutzen die authenticated-RPCs nicht mehr.

### 4. Tabellen-Policies vereinheitlicht

Die existierenden `*_anon_public_read`-Policies bleiben als Defense-in-Depth bestehen (V2-Variante). Sie matchen auf den `anon`-Pfad und schuetzen bei direkten PostgREST-Tablezugriffen (z.B. Mis-Konfiguration eines Realtime-Channels). Da der Client diese Pfade nicht mehr nutzt, ist der Effekt nicht funktional, aber sicherheitsrelevant.

### 5. pgTAP-Tests erweitert

`public_rls_test.sql` bleibt fuer die Tabellen-Ebene. Neu: `public_rpc_test.sql` testet `public_tournament_get` / `public_tournament_match_get` unter `set_config('role','anon')` — verifiziert sowohl die Sichtbarkeits-Bedingung (public=true) als auch die Spalten-Projektion (kein `user_id`/`created_by` im Envelope).

## Alternatives considered

### Strategie B — `authenticated-anonymous`-Modell beibehalten

Alle `TO anon`-Policies + pgTAP-Tests auf `TO authenticated` umstellen. RPCs behalten ihren `auth.uid()`-Guard. Spectator-Filterung erfolgt allein durch den JWT-Claim `is_anonymous`-Flag und durch eine in den RPCs explizit gepruefte Branch (`is_anonymous = true` → nur Public-Projektion liefern).

**Verworfen wegen**:

- **Komplexitaets-Vermehrung in jeder RPC**. Jeder bestehende `tournament_get`/`tournament_match_get` muesste eine zweite Branch fuer den `is_anonymous`-Pfad bekommen — inkl. Spalten-Maskierung. Das Risiko, in einer der Branches versehentlich `user_id` zu leaken, ist nicht testbar gegen die Spec.
- **`is_anonymous`-Claim ist gotrue-spezifisch und unstabil**. Supabase-Doku markiert das Feature als "experimental"; die Claim-Form hat sich zwischen gotrue-Versionen schon einmal geaendert. Eine RLS-Bedingung darauf zu bauen ist Vendor-Lock-in auf eine Feature-Flag-Form.
- **JWT-Generierung kostet**. `signInAnonymously()` macht einen Round-Trip beim Cold-Start jeder Spectator-URL. Bei viralen Links (das war die ADR-0023-These) ist das Free-Tier-gotrue-Limit ein realer Pain-Point. Strategie A spart diesen Trip komplett.
- **Realtime-Argument zieht nicht mehr**. ADR-0023 §"Anonymes JWT auf dem Client" begruendete den Bootstrap mit "Realtime verlangt eine gueltige JWT". Supabase Realtime akzeptiert seit 2025 anon-apikey-only-Verbindungen fuer `TO anon`-Channels. Der Bootstrap ist obsolet.
- **Strategie B repariert nur eine der drei Bruchstellen** (Policy-Rolle). RPC-Grant und View-Aufrufer bleiben ungeloest.

### Strategie C — Public-Routes deaktivieren, Spectator-Pfad nach M5 verschieben

Verworfen vom Owner als Sprint-A-Eingangsbedingung — der Pilot braucht den Spectator-Link. ADR-0023 bleibt im Grundsatz gueltig, nur der Implementierungspfad wird revidiert.

### Strategie D — PostgREST-Direct-Read auf die Tabellen (kein RPC)

Wenn die `*_anon_public_read`-Policies funktionierten (was nach Strategie A der Fall waere), koennte der Client direkt `from('tournaments').select()` etc. machen. **Verworfen**: gibt anon-Spectator Zugriff auf alle Spalten, inkl. `created_by`. Privacy-Projektion ist nur ueber RPC oder View enforcebar — und die View ist nicht aggregierbar (kein Join-Envelope wie `tournament_get`). RPC ist der einzige Pfad, der ohne N+1-Round-Trips bleibt.

## Consequences

### Positiv

- **Funktionaler Pfad**. Spectator-URL funktioniert ohne Login, ohne `signInAnonymously()`-Round-Trip, mit klarer Spalten-Projektion.
- **Privacy-Anker testbar**. pgTAP kann den exakten Envelope-Inhalt von `public_tournament_get` asserten; Leak-Pruefung ist eine Mengen-Pruefung, keine Code-Review-Frage.
- **Typsicherheit auf dem Client**. `PublicTournamentDetail` und `TournamentDetail` sind getrennte Typen — Mixing-Fehler werden compile-time erkannt.
- **Klares Mental-Model**. "Anon liest ausschliesslich ueber `public_*`-RPCs" ist ein Satz, der die ganze Security-Surface beschreibt.

### Negativ

- **Code-Duplikation**. `public_tournament_get` ist ~70 % der Logik von `tournament_get`. Refactoring in eine gemeinsame Helper-Funktion ist moeglich, aber explizit nicht Sprint-A — Doppelung gegen Maskierungs-Risiko getauscht.
- **Realtime fuer anon ist separater Folgepfad**. ADR-0021 hat Public-Realtime nicht final spezifiziert; mit Strategie A muessen Realtime-Channels mit `private: false` deklariert sein und ohne JWT subscribebar bleiben. Folge-Task in Wave 4, nicht Wave 3.
- **Migrationsmenge**. Ein neuer Migrations-Block (RPCs + ggf. Policy-Cleanup) plus Client-Code-Move. Geschaetzt 250–350 LOC, davon 60 % SQL.

### Neutral

- `AnonSessionBootstrapper` bleibt als Klasse erhalten, wird aber im Public-Pfad nicht mehr gecallt. Lifecycle der Klasse aendert sich nicht (Authenticated-Onboarding nutzt sie weiter).
- ADR-0023 wird nicht superseded — die *Strategie* (anonymer Read, per-Tournament Public-Flag, Privacy-View) bleibt gueltig. Nur der *Mechanismus* (anon-JWT + Tabellen-Policies → anon-Header + RPCs) wechselt. ADR-0026 amendiert.

### Migrations-Pfad

Strikt vorwaertskompatibel: neue RPCs koexistieren neben den bestehenden, Client schaltet Public-Routes als atomare Wave-3-Aenderung um, alte `tournament_get` bleibt unveraendert. Kein Rollback-Risiko fuer Authenticated-Pfade.

## Status-Notiz

Owner-Abnahme zu Strategie A vs. B blockiert Sprint-A Wave 3. Empfehlung des Architecten: **Strategie A** — siehe Begruendung in "Alternatives considered". Plan-Datei `docs/plans/sprint-a-bug-fix/anon-rls-plan.md` ist auf Strategie A geschnitten; bei Owner-Entscheidung B muss der Plan neu geschnitten werden (vier statt sechs Wave-3-Tasks).
