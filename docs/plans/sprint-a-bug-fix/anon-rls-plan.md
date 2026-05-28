# Sprint-A — Wave 3 Implementation-Plan: Anon-RLS-Pfad

- **Status**: Draft (blocked on Owner-Abnahme von ADR-0026)
- **Date**: 2026-05-28
- **Bezug**: ADR-0026 (Anon-Spectator-Revision), Sprint-A R14-F-01/02/03
- **Strategie**: A (Pure-anon, RPC-only) — siehe ADR-0026
- **Owner-Gate**: Wave 3 startet erst, wenn ADR-0026 auf "Accepted" steht.

## Ueberblick

Wave 3 repariert den in ADR-0023 spezifizierten, im Build aber nicht funktionsfaehigen Spectator-Pfad. Strategie A aus ADR-0026: anon-Header statt anon-JWT, dedizierte `public_*`-RPCs statt authenticated-RPCs, eigene Wire-Models statt Mixed-Use der authenticated-Modelle.

Skopus: ausschliesslich der Read-Pfad fuer `PublicTournamentScreen` und `PublicMatchScreen`. Realtime-Subscribes fuer anon sind ein Folge-Task in Wave 4 (Tracking-Stub in T6).

LOC-Schaetzung total: 250–350 LOC, davon ~150 SQL und ~150 Dart, plus ~50 pgTAP.

## Reihenfolge & Abhaengigkeiten

```
T1 (RPCs)  -->  T2 (Migration-Policies)  -->  T3 (Repo + Models)  -->  T4 (Screen-Cutover)
   |                                                                       |
   +-->  T5 (pgTAP)                                                        T6 (Realtime-Followup-Stub)
```

T1 und T5 koennen parallel laufen (gleicher Worker, gleiche Migration). T3 blockiert T4 hart. T6 ist Doku-only und kann am Ende.

## Wave-3-Tasks

### T1 — Neue Public-RPCs anlegen

- **Files**:
  - `supabase/migrations/20260601000001_public_tournament_rpcs.sql` (neu)
- **Aufgabe**:
  - `CREATE OR REPLACE FUNCTION public.public_tournament_get(p_tournament_id uuid) RETURNS jsonb` — `SECURITY DEFINER`, `SET search_path = public, auth`, kein `auth.uid()`-Guard.
  - Vorab-Check: `tournaments.public = true AND status IN ('published','registration_open','registration_closed','live','finalized')` — sonst `RETURN NULL`.
  - Projektion: `tournament_id`, `display_name`, `format`, `status`, `started_at`, `completed_at`, `team_size`, `match_format_config`, `matches[]` (ohne `set_score_proposals`, ohne `submitter_user_id`), `roster[]` aus `public_tournament_roster_view` (`display_name` only), `participant_count`.
  - **Nicht** projiziert: `created_by`, `participants[*].user_id`, `participants[*].nickname` (kommt nur via Roster-View), `audit_tail`, `tiebreaker_order` (intern), `bye_points`/`forfeit_points` (intern).
  - `CREATE OR REPLACE FUNCTION public.public_tournament_match_get(p_match_id uuid) RETURNS jsonb` analog — Match-Header + Score + Status, kein `set_score_proposals`-Array.
  - `GRANT EXECUTE ON FUNCTION public.public_tournament_get(uuid) TO anon, authenticated;`
  - `GRANT EXECUTE ON FUNCTION public.public_tournament_match_get(uuid) TO anon, authenticated;`
- **LOC**: ~120 SQL.
- **Acceptance**:
  - `psql` als `anon`-Rolle kann beide RPCs gegen ein public-Turnier aufrufen und bekommt einen jsonb-Envelope.
  - Gegen ein `public=false`-Turnier liefern beide `NULL`.
  - Envelope enthaelt keine der verbotenen Spalten (grep auf `user_id`, `created_by`, `email` im Result-jsonb — leer).

### T2 — Migrations-Block fuer Policy-Vereinheitlichung

- **Files**:
  - `supabase/migrations/20260601000002_anon_policy_cleanup.sql` (neu)
- **Aufgabe**:
  - Variante V2 (empfohlen, ADR-0026 §"Tabellen-Policies vereinheitlicht"): bestehende `tournaments_anon_public_read`, `tournament_matches_anon_public_read`, `tournament_participants_anon_public_read`, `tournament_set_score_proposals_anon_public_read` aus `20260701000002_tournaments_public_flag.sql` bleiben *erhalten* als Defense-in-Depth.
  - Migration enthaelt nur **COMMENT-Updates** auf den vier Policies: dokumentiert, dass der reguläre Read-Pfad ueber `public_*_get` RPCs laeuft und die Policies Sekundaer-Schutz gegen direkte PostgREST-Tablezugriffe sind.
  - `REVOKE INSERT, UPDATE, DELETE ON public.tournaments FROM anon;` (idempotent, redundant — RLS deny-by-default — aber expliziter Audit-Anker).
  - Optional: `GRANT SELECT ON public.public_tournament_roster_view TO anon;` re-asserten (schon vorhanden, aber sichert Idempotenz bei Re-Migrate).
- **LOC**: ~40 SQL.
- **Acceptance**:
  - `supabase db reset` laeuft sauber durch.
  - `pg_policies`-Query zeigt die vier `*_anon_public_read`-Policies unveraendert.
  - Kein bestehender Test bricht.

### T3 — Client-Repository `PublicTournamentRepository` + Wire-Models

- **Files**:
  - `lib/features/tournament/data/public_tournament_models.dart` (neu)
  - `lib/features/tournament/data/public_tournament_repository.dart` (neu)
  - `lib/features/tournament/application/public_tournament_providers.dart` (neu)
- **Aufgabe**:
  - **Models** (`public_tournament_models.dart`): `PublicTournamentDetail`, `PublicTournamentSummary`, `PublicRosterEntry` (`displayName`, `slotIndex`), `PublicMatchDetail`. Bewusst *keine* Wiederverwendung der `TournamentDetail`/`TournamentParticipant`-Typen — der Public-Envelope hat strikt weniger Felder, ein neuer Typ verhindert Null-Splatter.
  - **Repository** (`public_tournament_repository.dart`): abstrakte Klasse `PublicTournamentRepository` mit zwei Methoden, plus Impl `SupabasePublicTournamentRepository` die `_client.rpc('public_tournament_get', ...)` / `_client.rpc('public_tournament_match_get', ...)` aufruft.
  - **Provider** (`public_tournament_providers.dart`): `publicTournamentRepositoryProvider`, `publicTournamentDetailProvider(TournamentId)`, `publicMatchDetailProvider(TournamentMatchId)` — jeweils `FutureProvider.family`.
- **LOC**: ~150 Dart (60 Models + 50 Repo + 40 Providers).
- **Acceptance**:
  - Unit-Test (`test/features/tournament/data/public_tournament_repository_test.dart`): mockt `SupabaseClient`, asserted dass `public_tournament_get` mit `p_tournament_id`-Param aufgerufen wird und der Envelope korrekt deserialisiert.
  - `flutter analyze` ist clean.
  - Keine Imports von `tournament_repository.dart` oder `tournament_models.dart` — bewusste Isolation.

### T4 — `PublicTournamentScreen` + `PublicMatchScreen` auf Public-Pfad umstellen

- **Files**:
  - `lib/features/tournament/presentation/public/public_tournament_screen.dart` (edit)
  - `lib/features/tournament/presentation/public/public_match_screen.dart` (edit)
  - `lib/app/public_router_shell.dart` (edit — Bootstrapper-Aufruf entfernen)
- **Aufgabe**:
  - `PublicTournamentScreen`:
    - Ersetze `ref.watch(tournamentDetailProvider(...))` durch `ref.watch(publicTournamentDetailProvider(...))`.
    - Entferne den Fallback `d.tournament.matchFormatConfig['public'] != false` — die RPC liefert bereits `NULL` fuer non-public; Null-Branch zeigt `_notPublic`.
    - Entferne `_StandingsTab`s direkten `tournamentStandingsProvider`-Read — Standings kommen jetzt als Teil des Envelopes (oder separater Public-Standings-RPC; siehe Vermerk unten).
    - Realtime-Provider-Aufrufe (`tournamentMatchListRealtimeProvider`, `tournamentBracketRealtimeProvider`) bleiben fuer authenticated-Pfad nutzbar — fuer den anon-Pfad in T6 als bekannte Luecke dokumentiert.
  - `PublicMatchScreen`:
    - Ersetze `tournamentMatchDetailProvider` durch `publicMatchDetailProvider`.
    - Ersetze `tournamentDetailProvider`-Lookup fuer Teilnehmernamen durch das Roster-Array aus `publicTournamentDetailProvider`.
  - `public_router_shell.dart`:
    - Entferne den `ref.read(anonSessionBootstrapperProvider).ensureAnonSession()`-Aufruf aus dem Public-Routen-Bootstrap (Bootstrapper-Klasse selbst bleibt erhalten — wird vom Authenticated-Onboarding weiter genutzt).
- **LOC**: ~80 Dart (edits, kein Net-New).
- **Acceptance**:
  - `flutter test test/features/tournament/presentation/public/` (Widget-Tests, falls vorhanden) laufen durch.
  - Manuelle Smoke: `flutter run -d chrome --dart-define=...`, oeffne `/public/tournament/<live-id>` → Spielplan + Rangliste + Bracket sichtbar ohne Login-Round-Trip.
  - Netzwerk-Inspector zeigt: kein `POST /auth/v1/signup?anonymous=true`, nur `POST /rest/v1/rpc/public_tournament_get` mit `apikey`-Header.
  - Public-Match-URL `/public/match/<id>` rendert mit Spielernamen aus dem Roster.

### T5 — pgTAP-Tests fuer den neuen Pfad

- **Files**:
  - `supabase/tests/public_rpc_test.sql` (neu)
  - `supabase/tests/public_rls_test.sql` (edit — Headline-Kommentar updaten, Tests bleiben)
- **Aufgabe**:
  - Plan: `SELECT plan(8)`.
  - Helper `_pub_as_anon()` wie in `public_rls_test.sql` (Copy-Paste oder gemeinsamer Setup-File).
  - Cases:
    1. `public_tournament_get(<public-id>)` als anon → jsonb nicht-null.
    2. `public_tournament_get(<non-public-id>)` als anon → `NULL`.
    3. `public_tournament_get(<draft-id>)` als anon → `NULL`.
    4. Envelope-Inhalt: `jsonb_typeof(result -> 'matches') = 'array'`, `result ? 'roster'`, `NOT (result ? 'audit_tail')`, `NOT (result -> 'tournament' ? 'created_by')`.
    5. `public_tournament_match_get(<public-match-id>)` als anon → jsonb nicht-null, `NOT (result ? 'set_score_proposals')`.
    6. `public_tournament_match_get(<non-public-match-id>)` als anon → `NULL`.
    7. `EXECUTE` von `public_tournament_get` als `postgres` → funktioniert (Sanity).
    8. Grep auf Envelope nach Strings `user_id`, `email`, `created_by` → keine Treffer.
  - `public_rls_test.sql`: Headline-Kommentar aktualisieren — markiere als "Defense-in-Depth Layer; primaerer Pfad ist `public_rpc_test.sql`".
- **LOC**: ~80 pgTAP.
- **Acceptance**:
  - `supabase test db` zeigt 8 von 8 passing fuer `public_rpc_test.sql`.
  - `public_rls_test.sql` bleibt 9 von 9 passing.
  - CI-Merge-Gate fuer Sprint-A ist gruen.

### T6 — Followup-Tracking: Realtime fuer anon-Spectator

- **Files**:
  - `docs/plans/sprint-a-bug-fix/anon-rls-plan.md` (dieser File — Followup-Section pflegen)
  - `docs/adr/0021-realtime-subscription-architecture.md` (edit — Followup-Notiz, kein Inhalts-Change)
- **Aufgabe** (Doku-only, kein Code):
  - Dokumentiere die in T4 entstandene Luecke: `tournamentMatchListRealtimeProvider` & Co. nutzen die authenticated-Channels und funktionieren fuer anon-Spectator nicht (kein JWT, kein `auth.uid()`).
  - Vorschlag fuer Wave 4: neue `public_tournament_channel(p_tournament_id uuid)`-Funktion + Supabase-Realtime-Public-Topic mit `private: false`. RPC-Polling als Fallback ist heute bereits aktiv (`tournamentDetailProvider` re-fetcht auf Invalidate).
  - Eintrag in `docs/open-decisions.md` als OD-SprintA-01: "Anon-Realtime-Pfad — Sprint-B oder Wave 4?"
- **LOC**: ~30 Markdown.
- **Acceptance**:
  - Followup-Notiz in beiden Files vorhanden und cross-referenziert.
  - Owner kann das offene Realtime-Thema in der Sprint-B-Planung wiederfinden.

## Out-of-Scope

- Realtime-Subscriptions fuer den anon-Pfad (T6 trackt es; Implementierung fruehestens Wave 4).
- Refactoring von `tournament_get` / `tournament_match_get` zur Code-Deduplizierung mit den neuen Public-RPCs. Bewusste Doppelung — siehe ADR-0026 §Consequences.
- `tournament_list_for_caller` → `public_tournament_list`. Die Public-Liste ist nicht Teil von Sprint-A R14-F-01/02/03; Spectator kommt heute nur via Direkt-Link auf das Detail.
- Standings-Berechnung fuer den anon-Pfad als separater RPC. T3 nimmt an, dass `public_tournament_get` die Standings im Envelope mitliefert (kompakt, kein zusaetzlicher Round-Trip). Falls Standings-Logik zu komplex fuer Inline-Aggregation: Folge-RPC `public_tournament_standings` als T1.5.

## Vermerke fuer den Owner

- **Standings im Envelope**: T1 baut die Standings inline in `public_tournament_get`. Falls die existierende Standings-Berechnung (siehe `tournament_standings_provider.dart`) zu komplex zum Inline-Portieren ist, splittet T1 in T1a (Detail-RPC ohne Standings) + T1b (eigene `public_tournament_standings` RPC). Entscheidung beim Code-Review, nicht Plan-blockierend.
- **Bracket-Daten**: `BracketCanvas` braucht die KO-Pairings. T1 nimmt diese aus den `matches[]` im Envelope; falls die Bracket-Berechnung serverseitige Hilfsdaten braucht, ergaenzt T1 das Envelope-Feld `bracket_layout`.
- **Test-Daten-Setup**: T5 leiht den `_pub_seed_tournament`-Helper aus `public_rls_test.sql`. Falls die beiden Test-Files in einem Run laufen, muss der Helper in einen Shared-Setup-File extrahiert werden.

## Followup-Tracking (T6) — Realtime fuer den anon-Spectator

Wave 3 (W3-T3) hat den Read-Pfad nach ADR-0026 Strategie A implementiert;
Realtime-Subscriptions fuer den anon-Pfad sind bewusst nicht Teil dieser
Wave. Bekannte Luecke:

- `tournamentMatchListRealtimeProvider`, `tournamentMatchDetailRealtime-
  Provider` und `tournamentBracketRealtimeProvider` nutzen die
  authenticated Realtime-Channels und funktionieren fuer anon-Spectator
  nicht (kein JWT, kein `auth.uid()`).
- Im Code haben die Public-Screens (`PublicTournamentScreen`,
  `PublicMatchScreen`) deshalb keinen Realtime-Watch mehr. Aktualisierung
  passiert ueber den naechsten User-Refresh oder einen Polling-Tick
  (TODO: dedizierter Polling-Provider fuer den Public-Pfad — heute kein
  Polling im Public-Pfad).
- Vorschlag fuer Wave 4 / Sprint-B: `public_tournament_channel(
  p_tournament_id uuid)`-Funktion + Realtime-Topic mit `private: false`
  und einer kuratierten Spalten-Whitelist; alternativ RPC-Polling alle
  N Sekunden auf `publicTournamentDetailProvider`.

Tracking: `OD-SprintA-01` ("Anon-Realtime-Pfad — Sprint-B oder Wave 4?")
wird beim Sprint-B-Planning eroeffnet, sobald `docs/open-decisions.md`
existiert.

## Decision-Punkt — Owner-Lesepfad

Lese-Reihenfolge fuer den Owner (10-Minuten-Entscheidung A oder B):

1. ADR-0026 §"Context" — drei Bruchstellen verstehen.
2. ADR-0026 §"Decision" vs. §"Alternatives considered" §B — A oder B?
3. Bei A: dieser Plan ist anwendbar, Wave-3-Start auf Gruen.
4. Bei B: Plan muss neu geschnitten werden (vier Tasks: Policy-Rolle-Wechsel, RPC-Branch-Logik, View-Aufrufer einbauen, pgTAP-Spiegelung). LOC-Schaetzung ~200, aber Privacy-Surface schlechter testbar — siehe ADR-0026 §B.
